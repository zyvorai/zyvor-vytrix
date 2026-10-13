// SPDX-License-Identifier: BUSL-1.1
import SwiftUI
import Charts

/// CPU, Memory, Disk, Network and Battery: a current reading, a few derived stats, a history chart,
/// and for CPU and Memory the applications driving it. Mirrors components/monitor/ResourceView.tsx.
struct ResourceView: View {
    let pane: Pane
    @EnvironmentObject var store: TelemetryStore
    @State private var range: TimeInterval = 300
    @State private var selection: AppGroup.ID?
    @State private var report: AnomalyReport?
    @State private var selected: ClosedRange<Date>?
    @State private var evidence: EvidenceRequest?

    private let MB = 1_048_576.0

    var body: some View {
        if let s = store.snapshot {
            if pane == .battery, s.battery == nil {
                ContentUnavailableView("No battery reading", systemImage: "battery.0percent",
                                       description: Text("This host does not report a battery, or the collector cannot read it."))
            } else {
                content(s)
            }
        }
    }

    // MARK: layout

    private func content(_ s: Snapshot) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack(alignment: .top, spacing: 16) {
                    hero(s).frame(width: 300)
                    chartPanel.frame(maxWidth: .infinity)
                }
                if pane == .cpu || pane == .memory { appsPanel(s) }
            }
            .padding(32)
        }
        .inspector(isPresented: Binding(get: { selectedApp != nil }, set: { if !$0 { selection = nil } })) {
            if let a = selectedApp { ProcessList(group: a) }
        }
        .sheet(item: $evidence) { EvidenceSheet(request: $0).environmentObject(store) }
        .task(id: refreshKey) { await refreshAnomalies() }
    }

    private var selectedApp: AppGroup? { store.apps.first { $0.id == selection } }

    // MARK: anomalies

    /// The collector metric behind this pane, or nil (battery has no band).
    private var metric: String? {
        switch pane { case .cpu: return "cpu"; case .memory: return "memory"; case .disk: return "disk"; case .network: return "network"; default: return nil }
    }

    /// Evidence ranks apps by CPU, memory or network; disk has a ribbon but no per-app ranking.
    private var explainable: Bool { pane == .cpu || pane == .memory || pane == .network }

    private var refreshKey: String { "\(pane.rawValue)-\(Int(range))-\(String(describing: store.source))" }

    private func refreshAnomalies() async {
        report = nil; selected = nil
        guard metric != nil, store.canExplain else { return }
        while !Task.isCancelled {
            report = await store.anomalies(since: Date().addingTimeInterval(-range))
            try? await Task.sleep(nanoseconds: 10_000_000_000)
        }
    }

    private var bands: [ClosedRange<Date>] {
        guard let metric, let report else { return [] }
        return report.ranges(for: metric)
    }

    @ChartContentBuilder private var overlays: some ChartContent {
        ForEach(Array(bands.enumerated()), id: \.offset) { _, b in
            RectangleMark(xStart: .value("From", b.lowerBound), xEnd: .value("To", b.upperBound))
                .foregroundStyle(.orange.opacity(0.22))
        }
        if let selected {
            RectangleMark(xStart: .value("From", selected.lowerBound), xEnd: .value("To", selected.upperBound))
                .foregroundStyle(Color.accentColor.opacity(0.14))
        }
    }

    private var anomalyCaption: String? {
        guard let metric, store.canExplain else { return nil }
        guard let report else { return "Checking for anomalies…" }
        if !report.isScored(metric) { return "Anomaly band warming up: it needs about five minutes of history." }
        let n = bands.count
        return n == 0 ? "No anomalies in this range." : "\(n) anomal\(n == 1 ? "y" : "ies") in this range, shaded."
    }

    private var windowed: [Sample] {
        let cutoff = Date().addingTimeInterval(-range)
        return store.history.filter { $0.date >= cutoff }
    }

    // MARK: current reading and stats

    private func hero(_ s: Snapshot) -> some View {
        let memPct = s.host.memoryTotal > 0 ? s.memoryUsed / s.host.memoryTotal * 100 : 0
        let diskPct = s.diskTotal > 0 ? s.diskUsed / s.diskTotal * 100 : 0
        let w = windowed
        func peak(_ f: (Sample) -> Double) -> Double { w.map(f).max() ?? 0 }
        func avg(_ f: (Sample) -> Double) -> Double { w.isEmpty ? 0 : w.map(f).reduce(0, +) / Double(w.count) }
        return Panel(title: pane.rawValue, subtitle: subtitle) {
            VStack(alignment: .leading, spacing: 16) {
                switch pane {
                case .cpu:
                    reading(String(format: "%.1f", s.cpu), "%", "in use")
                    stat("Logical cores", "\(s.host.cores)")
                    stat("Average", Format.percent(avg(\.cpu)))
                    stat("Peak", Format.percent(peak(\.cpu)))
                    stat("Processes", "\(s.processes.count)")
                case .memory:
                    reading(String(format: "%.0f", memPct), "%", Format.bytes(s.memoryUsed))
                    stat("Installed", Format.bytes(s.host.memoryTotal))
                    stat("In use", Format.bytes(s.memoryUsed))
                    stat("Available", Format.bytes(max(0, s.host.memoryTotal - s.memoryUsed)))
                    stat("Peak", Format.percent(peak(\.memory)))
                case .disk:
                    reading(String(format: "%.0f", diskPct), "%", "full")
                    stat("Capacity", Format.bytes(s.diskTotal))
                    stat("Used", Format.bytes(s.diskUsed))
                    stat("Free", Format.bytes(max(0, s.diskTotal - s.diskUsed)))
                case .network:
                    reading(Format.bytes(s.download), "/s in", "↑ \(Format.rate(s.upload)) out")
                    stat("Peak in", Format.rate(peak(\.download)))
                    stat("Peak out", Format.rate(peak(\.upload)))
                    stat("Average in", Format.rate(avg(\.download)))
                case .battery:
                    reading(String(format: "%.0f", s.battery ?? 0), "%", "charge")
                    stat("Lowest in range", Format.percent(w.compactMap(\.battery).min() ?? (s.battery ?? 0)))
                default:
                    EmptyView()
                }
            }
        }
    }

    private var subtitle: String {
        switch pane {
        case .memory: return "App memory is summed RSS and can count shared pages more than once."
        case .disk: return "Root volume only. Per-app disk I/O is not collected here."
        case .network: return "Non-loopback interfaces. Per-app bandwidth is not collected here."
        default: return ""
        }
    }

    private func reading(_ value: String, _ unit: String, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 40, weight: .semibold)).monospacedDigit()
                Text(unit).font(.title3).foregroundStyle(.tertiary)
            }
            Text(hint).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }

    // MARK: history

    private var chartPanel: some View {
        Panel(title: "History") {
            Picker("Range", selection: $range) {
                Text("1m").tag(60.0); Text("5m").tag(300.0); Text("1h").tag(3600.0)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 150)
            chart.frame(height: 260)
            if let caption = anomalyCaption {
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
            if explainable, let metric, store.canExplain {
                HStack {
                    Text(selected == nil ? "Drag across the chart to select a range." : "Selected \(selected!.lowerBound.formatted(date: .omitted, time: .standard)) – \(selected!.upperBound.formatted(date: .omitted, time: .standard))")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Show Evidence") { evidence = EvidenceRequest.make(selected, metric: metric) }
                        .disabled(EvidenceRequest.make(selected, metric: metric) == nil)
                }
            }
        }
    }

    @ViewBuilder private var chart: some View {
        let w = windowed
        switch pane {
        case .network:
            Chart {
                ForEach(w) { p in
                    LineMark(x: .value("Time", p.date), y: .value("MB/s", p.download / MB), series: .value("Series", "Download"))
                        .foregroundStyle(by: .value("Series", "Download"))
                    LineMark(x: .value("Time", p.date), y: .value("MB/s", p.upload / MB), series: .value("Series", "Upload"))
                        .foregroundStyle(by: .value("Series", "Upload"))
                }
                overlays
            }
            .chartXSelection(range: $selected)
            .chartForegroundStyleScale(["Download": MetricColor.network.color, "Upload": MetricColor.upload.color])
            .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel(String(format: "%.1f MB/s", v.as(Double.self) ?? 0)) } }
        default:
            let value: (Sample) -> Double? = {
                switch pane {
                case .cpu: return $0.cpu
                case .memory: return $0.memory
                case .disk: return $0.disk
                default: return $0.battery
                }
            }
            Chart {
                ForEach(w) { p in
                    if let v = value(p) {
                        LineMark(x: .value("Time", p.date), y: .value(pane.rawValue, v))
                            .foregroundStyle(lineColor)
                    }
                }
                overlays
            }
            .chartXSelection(range: $selected)
            .chartYScale(domain: 0...100)
            .chartYAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { v in AxisGridLine(); AxisValueLabel("\(v.as(Int.self) ?? 0)%") } }
        }
    }

    private var lineColor: Color {
        switch pane {
        case .cpu: return MetricColor.cpu.color
        case .memory: return MetricColor.memory.color
        case .disk: return MetricColor.disk.color
        default: return MetricColor.battery.color
        }
    }

    // MARK: applications

    private func appsPanel(_ s: Snapshot) -> some View {
        let byMemory = pane == .memory
        let rows = Array(store.apps.sorted { byMemory ? $0.memory > $1.memory : $0.cpu > $1.cpu }.prefix(15))
        return Panel(title: byMemory ? "Memory by application" : "CPU by application", subtitle: "Select an application to see its processes.") {
            VStack(spacing: 0) {
                ForEach(rows) { a in
                    Button { selection = a.id } label: {
                        HStack(spacing: 10) {
                            Monogram(name: a.name, size: 24)
                            Text(a.name).lineLimit(1)
                            Spacer()
                            Text(byMemory ? Format.bytes(a.memory) : Format.percent(a.cpu)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if a.id != rows.last?.id { Divider() }
                }
            }
        }
    }
}

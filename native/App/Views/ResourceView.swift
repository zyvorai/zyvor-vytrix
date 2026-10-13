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
        .inspector(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selection = nil } })) {
            if let a = selected { ProcessList(group: a) }
        }
    }

    private var selected: AppGroup? { store.apps.first { $0.id == selection } }

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
            }
            .chartForegroundStyleScale(["Download": Color.accentColor, "Upload": Color.secondary])
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
            Chart(w) { p in
                if let v = value(p) {
                    LineMark(x: .value("Time", p.date), y: .value(pane.rawValue, v))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { v in AxisGridLine(); AxisValueLabel("\(v.as(Int.self) ?? 0)%") } }
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

// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import Charts

struct OverviewView: View {
    @EnvironmentObject var store: TelemetryStore
    let open: (Pane) -> Void
    @State private var range: TimeInterval = 300

    var body: some View {
        if let s = store.snapshot {
            ScrollView {
                VStack(spacing: 24) {
                    if case .demo = store.source {
                        Label("You are viewing simulated telemetry.", systemImage: "info.circle")
                            .font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                    }
                    tiles(s)
                    HStack(alignment: .top, spacing: 16) {
                        activity.frame(maxWidth: .infinity)
                        topConsumers.frame(width: 340)
                    }
                    if let running = running(s), !running.isEmpty { runningContainers(running) }
                }
                .padding(32)
            }
        }
    }

    private func running(_ s: Snapshot) -> [Container]? { s.containers?.filter(\.isRunning) }

    private func tiles(_ s: Snapshot) -> some View {
        let recent = store.history.suffix(60)
        let apps = AppGroup.group(s)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
            MetricTile(label: "CPU", symbol: "cpu", value: String(format: "%.1f", s.cpu), unit: "%",
                       hint: "\(s.host.cores) logical cores", series: recent.map(\.cpu), tint: .accentColor)
            MetricTile(label: "Memory", symbol: "memorychip", value: String(format: "%.1f", s.memoryUsed / 1_073_741_824), unit: "GB",
                       hint: "of \(Format.bytes(s.host.memoryTotal))", series: recent.map(\.memory))
            MetricTile(label: "Disk", symbol: "internaldrive", value: String(format: "%.0f", s.diskUsed / max(1, s.diskTotal) * 100), unit: "%",
                       hint: "\(Format.bytes(s.diskTotal - s.diskUsed)) free", series: recent.map(\.disk))
            MetricTile(label: "Network", symbol: "arrow.up.arrow.down", value: Format.bytes(s.download), unit: "/s in",
                       hint: "↑ \(Format.rate(s.upload)) out", series: recent.map(\.network))
            MetricTile(label: "Applications", symbol: "square.stack.3d.up", value: "\(apps.count)", unit: "apps",
                       hint: "\(s.processes.count) processes", action: { open(.applications) })
            MetricTile(label: "Containers", symbol: "shippingbox", value: "\(running(s)?.count ?? 0)", unit: "running",
                       hint: "\(s.containers?.count ?? 0) total", action: { open(.containers) })
        }
    }

    private var windowed: [Sample] {
        let cutoff = Date().addingTimeInterval(-range)
        return store.history.filter { $0.date >= cutoff }
    }

    private var activity: some View {
        Panel(title: "Activity", subtitle: "CPU and memory, percent") {
            Picker("Range", selection: $range) {
                Text("1m").tag(60.0); Text("5m").tag(300.0); Text("1h").tag(3600.0)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 150)
            Chart {
                ForEach(windowed) { p in
                    LineMark(x: .value("Time", p.date), y: .value("CPU", p.cpu), series: .value("Series", "CPU"))
                        .foregroundStyle(by: .value("Series", "CPU"))
                    LineMark(x: .value("Time", p.date), y: .value("Memory", p.memory), series: .value("Series", "Memory"))
                        .foregroundStyle(by: .value("Series", "Memory"))
                }
            }
            .chartForegroundStyleScale(["CPU": Color.accentColor, "Memory": Color.secondary])
            .chartYScale(domain: 0...100)
            .chartYAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { v in AxisGridLine(); AxisValueLabel("\(v.as(Int.self) ?? 0)%") } }
            .frame(height: 230)
        }
    }

    private var topConsumers: some View {
        let top = Array(store.apps.prefix(6))
        let peak = max(1, top.map(\.cpu).max() ?? 1)
        return Panel(title: "Top consumers", subtitle: "By CPU") {
            VStack(spacing: 14) {
                ForEach(top) { a in
                    HStack(spacing: 10) {
                        Monogram(name: a.name)
                        VStack(spacing: 5) {
                            HStack { Text(a.name).lineLimit(1); Spacer(); Text(Format.percent(a.cpu)).monospacedDigit().foregroundStyle(.secondary) }
                            Meter(fraction: a.cpu / peak)
                        }
                    }
                }
            }
        }
    }

    private func runningContainers(_ list: [Container]) -> some View {
        Panel(title: "Running containers") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                ForEach(list) { c in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Text(c.name).fontWeight(.medium); Spacer(); Text(Format.percent(c.cpu)).monospacedDigit() }
                        Text(c.image).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .padding(12).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
}

// SPDX-License-Identifier: BUSL-1.1
import SwiftUI
import WidgetKit

struct VytrixEntry: TimelineEntry {
    let date: Date
    let data: WidgetData?
}

struct VytrixProvider: TimelineProvider {
    func placeholder(in context: Context) -> VytrixEntry { VytrixEntry(date: Date(), data: Self.sample) }
    func getSnapshot(in context: Context, completion: @escaping (VytrixEntry) -> Void) {
        completion(VytrixEntry(date: Date(), data: context.isPreview ? Self.sample : WidgetStore.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<VytrixEntry>) -> Void) {
        let now = Date()
        completion(Timeline(entries: [VytrixEntry(date: now, data: WidgetStore.read())], policy: .after(now.addingTimeInterval(60))))
    }
    /// Gallery preview only; never shown as a reading.
    static let sample = WidgetData(updated: Date(), host: "zyvor-dev-01", simulated: true, cpu: 42, memory: 48, disk: 62,
                                   download: 3.4e6, upload: 0.8e6, alerts: 0,
                                   topApps: [.init(name: "Google Chrome", cpu: 18), .init(name: "python", cpu: 13), .init(name: "Docker", cpu: 4)])
}

private struct Ring: View {
    let title: String, value: Double
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 7)
                Circle().trim(from: 0, to: min(1, max(0, value / 100)))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                Text("\(Int(value.rounded()))%").font(.system(.callout, design: .rounded).weight(.semibold)).monospacedDigit()
            }
            .frame(width: 58, height: 58)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct Waiting: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent").font(.title2).foregroundStyle(.secondary)
            Text("Open Vytrix to start readings").font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
    }
}

struct VytrixWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: VytrixEntry
    var body: some View { VytrixWidgetContent(entry: entry, family: family) }
}

struct VytrixWidgetContent: View {
    let entry: VytrixEntry
    let family: WidgetFamily

    var body: some View {
        Group {
            if let d = entry.data {
                if family == .systemSmall { small(d) } else { medium(d) }
            } else {
                Waiting()
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private func footer(_ d: WidgetData) -> some View {
        let text = d.simulated ? "Simulated" : d.isStale(now: entry.date) ? "Vytrix is not running · \(d.age(now: entry.date))" : d.host
        return Text(text).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
    }

    private func small(_ d: WidgetData) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) { Ring(title: "CPU", value: d.cpu); Ring(title: "Memory", value: d.memory) }
            footer(d)
        }
    }

    private func medium(_ d: WidgetData) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 8) {
                HStack(spacing: 12) { Ring(title: "CPU", value: d.cpu); Ring(title: "Memory", value: d.memory) }
                footer(d)
            }
            .frame(width: 132)
            VStack(alignment: .leading, spacing: 6) {
                Text("Busiest apps").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(Array(d.topApps.prefix(3).enumerated()), id: \.offset) { _, app in
                    HStack { Text(app.name).lineLimit(1); Spacer(); Text("\(Int(app.cpu.rounded()))%").monospacedDigit().foregroundStyle(.secondary) }
                        .font(.callout)
                }
                if d.topApps.isEmpty { Text("No app data").font(.callout).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                if d.alerts > 0 {
                    Label("\(d.alerts) alert\(d.alerts == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct VytrixSystemWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "dev.zyvor.vytrix.system", provider: VytrixProvider()) { entry in
            VytrixWidgetView(entry: entry)
        }
        .configurationDisplayName("System")
        .description("CPU and memory, and the busiest apps. Read-only; readings come from the Vytrix app.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#if !WIDGET_PREVIEW_HARNESS
@main
#endif
struct VytrixWidgetBundle: WidgetBundle {
    var body: some Widget { VytrixSystemWidget() }
}

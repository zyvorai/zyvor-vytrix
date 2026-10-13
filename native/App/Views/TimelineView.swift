// SPDX-License-Identifier: BUSL-1.1
import SwiftUI

/// Alerts, anomaly windows and container changes over a window, replayed by the collector from its
/// stored history, plus apps and ports that appeared or went away. Read-only; needs a collector.
struct TimelineView: View {
    @EnvironmentObject var store: TelemetryStore
    @State private var minutes = 15
    @State private var timeline: TimelineReport?
    @State private var changes: ChangesReport?
    @State private var loading = true

    var body: some View {
        Group {
            if !store.canExplain {
                ContentUnavailableView("Timeline needs a collector", systemImage: "clock.arrow.circlepath",
                    description: Text("The timeline replays the collector's stored history. Demo data and imported snapshots have none."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Picker("Window", selection: $minutes) {
                            Text("5 min").tag(5); Text("15 min").tag(15); Text("30 min").tag(30)
                        }
                        .pickerStyle(.segmented).frame(width: 260)
                        if loading && timeline == nil {
                            ProgressView().frame(maxWidth: .infinity, minHeight: 160)
                        } else {
                            eventsPanel
                            changesPanel
                        }
                    }
                    .padding(24)
                }
            }
        }
        .task(id: "\(minutes)-\(Int(store.threshold))-\(store.canExplain)") { await load() }
    }

    private func load() async {
        guard store.canExplain else { return }
        let end = Date(), start = end.addingTimeInterval(-Double(minutes) * 60)
        async let t = store.timeline(from: start, to: end)
        async let c = store.changes(from: start, to: end)
        let (tt, cc) = await (t, c)
        timeline = tt; changes = cc; loading = false
    }

    private var eventsPanel: some View {
        Panel(title: "Incident timeline",
              subtitle: "Alert transitions at \(Int(store.threshold))%, anomaly windows and container changes") {
            if let t = timeline {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Text("Fingerprint")
                        Text(t.fingerprint).font(.callout.monospaced()).textSelection(.enabled)
                        Text("· \(t.eventCount) event\(t.eventCount == 1 ? "" : "s") in \(t.window.samples) samples")
                    }
                    .font(.callout).foregroundStyle(.secondary)
                    if t.events.isEmpty {
                        Text("Nothing happened in this window: no alert fired, no anomaly, no container change.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        ForEach(t.events) { e in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(Self.clock(e.time)).monospacedDigit().foregroundStyle(.secondary).frame(width: 76, alignment: .leading)
                                Text(e.kind.capitalized).font(.caption.weight(.semibold))
                                    .foregroundStyle(e.severity == "critical" ? .red : e.severity == "warning" ? .orange : .secondary)
                                    .frame(width: 70, alignment: .leading)
                                Text(e.text)
                                Spacer(minLength: 0)
                            }
                            .font(.callout)
                        }
                    }
                    if let w = t.whyChanged, !(w.newSincePrevious.isEmpty && w.goneSincePrevious.isEmpty) {
                        Divider()
                        Text("Why this differs from the window before").font(.callout.weight(.semibold))
                        ForEach(w.newSincePrevious, id: \.self) { Label("New: \(TimelineReport.describe(key: $0))", systemImage: "plus.circle").font(.callout) }
                        ForEach(w.goneSincePrevious, id: \.self) { Label("Gone: \(TimelineReport.describe(key: $0))", systemImage: "minus.circle").font(.callout) }
                    }
                    ForEach(t.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
            } else {
                Text("The collector did not return a timeline. It may be older than this app.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var changesPanel: some View {
        Panel(title: "What changed", subtitle: "First against last sample in the window") {
            if let c = changes?.changes {
                VStack(alignment: .leading, spacing: 10) {
                    if c.isEmpty { Text("No apps, ports or containers appeared or went away.").font(.callout).foregroundStyle(.secondary) }
                    group("Apps started", c.appsStarted)
                    group("Apps stopped", c.appsStopped)
                    group("Ports opened", c.portsOpened.map { "\($0.port) · \($0.app)" })
                    group("Ports closed", c.portsClosed.map { "\($0.port) · \($0.app)" })
                    group("Containers appeared", c.containersAppeared)
                    group("Containers gone", c.containersGone)
                    group("Containers changed", c.containersChanged.map { "\($0.container): \($0.from ?? "?") to \($0.to ?? "?")" })
                    group("Came and went inside the window",
                          c.transient.apps + c.transient.ports.map { "\($0.port) · \($0.app)" } + c.transient.containers)
                    ForEach(changes?.notes ?? [], id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
            } else if changes != nil {
                Text("Fewer than two samples in this window; nothing to compare.").font(.callout).foregroundStyle(.secondary)
            } else {
                Text("The collector did not return changes. It may be older than this app.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func group(_ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.semibold))
                Text(items.joined(separator: "  ·  ")).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }

    private static func clock(_ iso: String) -> String {
        EvidenceTime.date(iso)?.formatted(date: .omitted, time: .standard) ?? iso
    }
}

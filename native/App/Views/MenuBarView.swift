// SPDX-License-Identifier: BUSL-1.1
import SwiftUI
import AppKit

/// The menu bar label: one glyph and the current CPU load. Absent data shows a dash, never a zero.
struct MenuBarLabel: View {
    @EnvironmentObject private var store: TelemetryStore
    var body: some View {
        if let s = store.snapshot {
            Label(String(format: "%.0f%%", s.cpu),
                  systemImage: store.alerts.isEmpty ? "gauge.with.dots.needle.bottom.50percent" : "exclamationmark.triangle.fill")
        } else {
            Label("–", systemImage: "gauge.with.dots.needle.bottom.50percent")
        }
    }
}

/// A read-only glance at the host: totals and the five busiest apps. No controls beyond opening the
/// window and quitting Vytrix itself.
struct MenuBarView: View {
    @EnvironmentObject private var store: TelemetryStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let s = store.snapshot {
                header(s)
                Divider()
                topApps(s)
            } else {
                Text(placeholder).font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Button("Open Vytrix") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private var placeholder: String {
        if case .failed(let message) = store.status { return message }
        return "Waiting for the first sample…"
    }

    private func header(_ s: Snapshot) -> some View {
        let memory = s.host.memoryTotal > 0 ? s.memoryUsed / s.host.memoryTotal * 100 : 0
        return VStack(alignment: .leading, spacing: 6) {
            Text(s.host.name).font(.headline)
            row("CPU", Format.percent(s.cpu))
            row("Memory", Format.percent(memory))
            row("Network", "↓ \(Format.rate(s.download))  ↑ \(Format.rate(s.upload))")
            row("Alerts", store.alerts.isEmpty ? "None" : "\(store.alerts.count) active")
            if store.source == .demo {
                Text("Simulated telemetry").font(.caption).foregroundStyle(.secondary)
            }
            if case .file(let name) = store.source {
                Text("Imported snapshot · \(name)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func topApps(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Busiest apps").font(.caption).foregroundStyle(.secondary)
            ForEach(AppGroup.group(s).prefix(5)) { app in
                HStack {
                    Text(app.name).lineLimit(1)
                    Spacer()
                    Text(Format.percent(app.cpu)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
    }
}

// SPDX-License-Identifier: BUSL-1.1
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Appearance, accent, alert threshold, snapshot import/export and the data source. Mirrors
/// components/monitor/SettingsView.tsx; the native window already follows the system's macOS look, so
/// there is no window-style switch here. Nothing on this page changes the host.
struct SettingsView: View {
    @EnvironmentObject var store: TelemetryStore
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Panel(title: "Appearance") {
                    VStack(alignment: .leading, spacing: 16) {
                        row("Appearance", "Follow the system, or pin light or dark.") {
                            Picker("Appearance", selection: $store.appearance) {
                                ForEach(AppearanceChoice.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented).labelsHidden().frame(width: 220)
                        }
                        Divider()
                        row("Accent", "Used for selection, links and the primary chart line.") {
                            HStack(spacing: 10) {
                                ForEach(AccentChoice.allCases) { a in
                                    Button { store.accent = a } label: {
                                        Circle().fill(a.color).frame(width: 22, height: 22)
                                            .overlay(Circle().strokeBorder(.primary.opacity(store.accent == a ? 0.9 : 0), lineWidth: 2).padding(-4))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(a.label) accent")
                                    .accessibilityAddTraits(store.accent == a ? .isSelected : [])
                                }
                            }
                        }
                    }
                }
                Panel(title: "Alerts") {
                    VStack(alignment: .leading, spacing: 16) {
                        row("Threshold", "Warning at this level, critical 10 points above it.") {
                            HStack {
                                Slider(value: $store.threshold, in: 50...99, step: 1).frame(width: 180)
                                Text("\(Int(store.threshold))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                            }
                        }
                        Divider()
                        row("Notifications", "Local, informational, never for demo data.") {
                            Toggle("Notify", isOn: $store.notificationsEnabled).labelsHidden()
                        }
                    }
                }
                Panel(title: "Data") {
                    VStack(alignment: .leading, spacing: 16) {
                        row("Snapshot", "Import collector output, or export the current sample as JSON.") {
                            HStack {
                                Button("Import…") { importSnapshot() }
                                Button("Export…") { exportSnapshot() }.disabled(store.snapshot == nil)
                            }
                        }
                        Divider()
                        row("Data source", sourceText) {
                            HStack {
                                Button("Monitor This Mac") { store.useThisMac() }.disabled(store.source == .local)
                                Button("Use Demo Data") { store.useDemo() }.disabled(store.source == .demo)
                            }
                        }
                        if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
                    }
                }
                Text("History shows samples since the collector started (up to 30 days in its SQLite file). The collector token stays in memory and is forgotten on quit. GPU, fans, audio and Bluetooth are not collected in this release.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(32)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    private var sourceText: String {
        switch store.source {
        case .demo: return "Simulated data is running."
        case .local: return "Reading this Mac through the bundled collector every 2 seconds."
        case .remote(let u): return "Polling \(URL(string: u)?.host ?? "a remote collector") every 2 seconds."
        case .file(let name): return "Viewing a single imported snapshot, \(name)."
        }
    }

    private func row<Control: View>(_ title: String, _ detail: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            control()
        }
    }

    // MARK: snapshot files

    private func importSnapshot() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Vytrix snapshot (JSON)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.importSnapshot(from: url)
            message = nil
        } catch {
            message = "That file is not a Vytrix snapshot: \(error.localizedDescription)"
        }
    }

    private func exportSnapshot() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "vytrix-snapshot.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let data = try store.exportSnapshot() else { return }
            try data.write(to: url, options: .atomic)
            message = "Exported \(url.lastPathComponent). It includes process names, ports and paths from this host."
        } catch {
            message = "Export failed: \(error.localizedDescription)"
        }
    }
}

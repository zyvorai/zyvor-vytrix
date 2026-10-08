// SPDX-License-Identifier: Apache-2.0
import SwiftUI

struct ContainersView: View {
    @EnvironmentObject var store: TelemetryStore
    @State private var filter = "All"

    var body: some View {
        let s = store.snapshot
        let all = s?.containers ?? []
        let q = store.search.lowercased()
        let list = all.filter { c in
            (filter == "All" || (filter == "Running") == c.isRunning)
                && (q.isEmpty || c.name.lowercased().contains(q) || c.image.lowercased().contains(q))
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                runtimes(s?.runtimes ?? [])
                Text("On macOS, Docker Desktop and Podman run containers inside a Linux VM. CPU and memory are relative to that VM, not the Mac.")
                    .font(.callout).foregroundStyle(.secondary)
                Picker("State", selection: $filter) { Text("All").tag("All"); Text("Running").tag("Running"); Text("Stopped").tag("Stopped") }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 240)
                if all.isEmpty {
                    ContentUnavailableView("No containers", systemImage: "shippingbox",
                                           description: Text("Docker or Podman isn't running or has no containers."))
                } else {
                    ForEach(["docker", "podman"], id: \.self) { rt in
                        let rows = list.filter { $0.runtime == rt }
                        if !rows.isEmpty {
                            Panel(title: rt.capitalized) {
                                VStack(spacing: 0) {
                                    ForEach(rows) { c in
                                        row(c)
                                        if c.id != rows.last?.id { Divider() }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(32)
        }
    }

    private func runtimes(_ r: [RuntimeStatus]) -> some View {
        HStack(spacing: 16) {
            ForEach(r, id: \.name) { rt in
                HStack(spacing: 8) {
                    Circle().fill(rt.available ? Color.green : Color.secondary).frame(width: 8, height: 8)
                    Text(rt.name.capitalized).fontWeight(.medium)
                    Text(rt.available ? "available" : (rt.error ?? "unavailable")).foregroundStyle(.secondary)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func row(_ c: Container) -> some View {
        HStack(spacing: 14) {
            Circle().fill(c.isRunning ? Color.green : Color.secondary.opacity(0.5)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.name).fontWeight(.medium)
                Text(c.image).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if !c.ports.isEmpty { Text(c.ports.map(\.label).joined(separator: "  ")).font(.caption.monospaced()).foregroundStyle(.secondary) }
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.percent(c.cpu)).monospacedDigit()
                Text(c.memoryLimit.map { "\(Format.bytes(c.memory)) / \(Format.bytes($0))" } ?? Format.bytes(c.memory))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(width: 130, alignment: .trailing)
        }
        .padding(.vertical, 10)
    }
}

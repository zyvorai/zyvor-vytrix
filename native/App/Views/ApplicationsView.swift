// SPDX-License-Identifier: BUSL-1.1
import SwiftUI

struct ApplicationsView: View {
    @EnvironmentObject var store: TelemetryStore
    @State private var sort = [KeyPathComparator(\AppGroup.cpu, order: .reverse)]
    @State private var selection: AppGroup.ID?

    var body: some View {
        let rows = store.apps.sorted(using: sort)
        Table(rows, selection: $selection, sortOrder: $sort) {
            TableColumn("Application", value: \.name) { a in
                HStack(spacing: 10) {
                    Monogram(name: a.name, size: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(a.name)
                        Text(a.project.map { "Project · \($0)" } ?? "\(a.processCount) processes").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            TableColumn("Processes", value: \.processCount) { Text("\($0.processCount)").monospacedDigit() }.width(80)
            TableColumn("CPU", value: \.cpu) { Text(Format.percent($0.cpu)).monospacedDigit() }.width(80)
            TableColumn("Memory", value: \.memory) { Text(Format.bytes($0.memory)).monospacedDigit() }.width(100)
            TableColumn("Ports") { Text($0.portsText.isEmpty ? "—" : $0.portsText).font(.body.monospaced()).foregroundStyle(.secondary) }
        }
        .inspector(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selection = nil } })) {
            if let a = selected { ProcessList(group: a) }
        }
        .overlay { if rows.isEmpty { ContentUnavailableView.search(text: store.search) } }
    }

    private var selected: AppGroup? { store.apps.first { $0.id == selection } }
}

struct ProcessList: View {
    let group: AppGroup
    var body: some View {
        List {
            Section {
                Text("Memory is RSS and can count shared pages more than once. CPU: 100% is one full core.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("\(group.name) · \(group.processCount) processes") {
                ForEach(group.processes.sorted { $0.cpu > $1.cpu }) { p in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.name).lineLimit(1)
                            Text("PID \(p.pid)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Format.percent(p.cpu)).monospacedDigit()
                            Text(Format.bytes(p.memory)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }
        }
        .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
    }
}

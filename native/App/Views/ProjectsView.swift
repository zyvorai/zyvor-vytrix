// SPDX-License-Identifier: Apache-2.0
import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject var store: TelemetryStore

    private struct Project: Identifiable { var name: String; var apps: [AppGroup]; var id: String { name }
        var cpu: Double { apps.reduce(0) { $0 + $1.cpu } }
        var memory: Double { apps.reduce(0) { $0 + $1.memory } }
    }

    private var projects: [Project] {
        Dictionary(grouping: store.apps.filter { $0.project != nil }, by: { $0.project! })
            .map { Project(name: $0.key, apps: $0.value) }.sorted { $0.cpu > $1.cpu }
    }

    var body: some View {
        let list = projects
        if list.isEmpty {
            ContentUnavailableView("No projects", systemImage: "folder",
                                   description: Text("Projects are the best-effort folder names of running processes."))
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(list) { p in
                        Panel(title: p.name, subtitle: "\(p.apps.count) apps · \(Format.percent(p.cpu)) CPU · \(Format.bytes(p.memory))") {
                            VStack(spacing: 0) {
                                ForEach(p.apps) { a in
                                    HStack(spacing: 10) {
                                        Monogram(name: a.name, size: 24)
                                        Text(a.name)
                                        Spacer()
                                        Text(a.portsText.isEmpty ? "" : "ports \(a.portsText)").font(.caption.monospaced()).foregroundStyle(.secondary)
                                        Text(Format.percent(a.cpu)).monospacedDigit().frame(width: 70, alignment: .trailing)
                                    }
                                    .padding(.vertical, 8)
                                    if a.id != p.apps.last?.id { Divider() }
                                }
                            }
                        }
                    }
                }
                .padding(32)
            }
        }
    }
}

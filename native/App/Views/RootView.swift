// SPDX-License-Identifier: BUSL-1.1
import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: TelemetryStore
    @State private var section: Pane? = VytrixApp.initialSection
    @State private var connecting = false

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $section) { s in
                Label(s.rawValue, systemImage: s.symbol).tag(s as Pane?)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
            .safeAreaInset(edge: .bottom) { HostFooter().padding(12) }
        } detail: {
            Group {
                if case .failed(let message) = store.status, store.snapshot == nil {
                    ProblemView(message: message, connect: { connecting = true })
                } else if store.snapshot == nil {
                    ProgressView("Starting the collector…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    switch section ?? .overview {
                    case .overview: OverviewView(open: { section = $0 })
                    case .applications: ApplicationsView()
                    case .containers: ContainersView()
                    case .projects: ProjectsView()
                    }
                }
            }
            .navigationTitle((section ?? .overview).rawValue)
            .navigationSubtitle(subtitle)
        }
        .searchable(text: $store.search, placement: .toolbar, prompt: "Search")
        .toolbar {
            ToolbarItemGroup {
                Button { store.paused.toggle() } label: { Image(systemName: store.paused ? "play.fill" : "pause.fill") }
                    .help(store.paused ? "Resume sampling" : "Pause sampling")
                Button("Connect…") { connecting = true }
            }
        }
        .sheet(isPresented: $connecting) { ConnectSheet() }
    }

    private var subtitle: String {
        guard let s = store.snapshot else { return "" }
        return "\(s.host.name) · \(s.host.os)"
    }
}

struct HostFooter: View {
    @EnvironmentObject var store: TelemetryStore
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(store.snapshot?.host.name ?? "Vytrix").font(.callout.weight(.medium)).lineLimit(1)
                Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
    private var color: Color {
        if store.paused { return .secondary }
        switch store.status { case .live: return .green; case .starting: return .secondary; case .failed: return .red }
    }
    private var label: String {
        if store.paused { return "Paused" }
        switch (store.source, store.status) {
        case (.demo, _): return "Demo data"
        case (_, .failed): return "Not connected"
        case (.local, _): return "This Mac · read-only"
        case (.remote(let u), _): return URL(string: u)?.host ?? "Remote collector"
        }
    }
}

struct ProblemView: View {
    @EnvironmentObject var store: TelemetryStore
    let message: String
    let connect: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("Can't read telemetry", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try This Mac Again") { store.useThisMac() }
            Button("Connect to a Collector…", action: connect)
            Button("Show Demo Data") { store.useDemo() }
        }
    }
}

struct ConnectSheet: View {
    @EnvironmentObject var store: TelemetryStore
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var token = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect to a Collector").font(.title3.weight(.semibold))
            Text("Enter the address and token of a running Vytrix collector. The token stays in memory and is forgotten when you quit.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("https://host:9847", text: $url).textFieldStyle(.roundedBorder)
            SecureField("Token", text: $token).textFieldStyle(.roundedBorder)
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                Button("Monitor This Mac") { store.useThisMac(); dismiss() }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Connect") {
                    switch TelemetryStore.validate(url) {
                    case .bad(let m): error = m
                    case .ok(let u):
                        guard token.count >= 24 else { error = "Tokens are at least 24 characters."; return }
                        store.connect(url: u, token: token)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

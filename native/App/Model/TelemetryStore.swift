// SPDX-License-Identifier: BUSL-1.1
import Foundation
import SwiftUI

/// Sidebar grouping, the same three sections as the web dashboard.
enum PaneSection: String, CaseIterable, Identifiable {
    case monitor = "Monitor", workloads = "Workloads", system = "System"
    var id: Self { self }
}

enum Pane: String, CaseIterable, Identifiable {
    case overview = "Overview", cpu = "CPU", memory = "Memory", disk = "Disk", network = "Network", battery = "Battery"
    case applications = "Applications", containers = "Containers", projects = "Projects"
    case alerts = "Alerts", timeline = "Timeline", settings = "Settings"
    var id: Self { self }   // the sidebar List tags rows by id; it must match the Pane selection
    var section: PaneSection {
        switch self {
        case .overview, .cpu, .memory, .disk, .network, .battery: return .monitor
        case .applications, .containers, .projects: return .workloads
        case .alerts, .timeline, .settings: return .system
        }
    }
    var symbol: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.bottom.50percent"
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .network: return "arrow.up.arrow.down"
        case .battery: return "battery.75percent"
        case .applications: return "square.stack.3d.up"
        case .containers: return "shippingbox"
        case .projects: return "folder"
        case .alerts: return "bell.badge"
        case .timeline: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
final class TelemetryStore: ObservableObject {
    enum Source: Equatable { case local, remote(String), demo, file(String) }
    enum Status: Equatable { case starting, live, failed(String) }

    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var history: [Sample] = []
    @Published private(set) var status: Status = .starting
    @Published private(set) var source: Source = .local
    @Published var paused = false
    /// Time machine: stored samples (full snapshots) and the one on screen. While `replayIndex` is set
    /// the dashboard shows that past sample and live polling keeps recording without replacing it.
    @Published private(set) var replay: [Snapshot] = []
    @Published private(set) var replayIndex: Int?
    var isReplaying: Bool { replayIndex != nil }
    @Published var search = ""
    @Published var threshold: Double = {
        let v = UserDefaults.standard.double(forKey: "vytrix.threshold")
        return v >= 1 && v <= 100 ? v : AlertRules.defaultThreshold
    }() { didSet { UserDefaults.standard.set(threshold, forKey: "vytrix.threshold") } }
    @Published var notificationsEnabled: Bool = UserDefaults.standard.object(forKey: "vytrix.notify") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "vytrix.notify"); if notificationsEnabled { AlertNotifications.requestAuthorization() } }
    }
    @Published var accent: AccentChoice = AccentChoice(rawValue: UserDefaults.standard.string(forKey: "vytrix.accent") ?? "") ?? .blue {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: "vytrix.accent") }
    }
    @Published var appearance: AppearanceChoice = AppearanceChoice(rawValue: UserDefaults.standard.string(forKey: "vytrix.appearance") ?? "") ?? .auto {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "vytrix.appearance") }
    }
    @Published private(set) var dismissed: Set<String> = []
    private var notifier = AlertNotifier()

    /// Alerts for the latest sample that the person has not dismissed. A dismissed alert comes back
    /// if it clears and fires again.
    var alerts: [VytrixAlert] {
        guard let s = snapshot else { return [] }
        return AlertRules.compute(s, threshold: threshold).filter { !dismissed.contains($0.id) }
            .sorted { $0.severity > $1.severity }
    }
    func dismiss(_ id: String) { dismissed.insert(id) }
    func dismissAll() { dismissed.formUnion(alerts.map(\.id)) }

    let collector = CollectorProcess()
    private var endpoint: URL?
    private var token = ""          // memory only: never persisted, logged or put in a URL
    private var loop: Task<Void, Never>?
    private let maxSamples = 1800   // one hour at the collector's 2 s interval
    private var failures = 0
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 5
        return URLSession(configuration: c)
    }()

    var apps: [AppGroup] {
        guard let s = snapshot else { return [] }
        let all = AppGroup.group(s)
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? all : all.filter { $0.name.lowercased().contains(q) || ($0.project ?? "").lowercased().contains(q) }
    }

    // MARK: sources

    func useThisMac() { begin(.local) }
    func useDemo() { begin(.demo) }

    /// Plain HTTP is only allowed to this machine; anything remote must be HTTPS (docs/SECURITY.md).
    enum Check { case ok(URL), bad(String) }
    static func validate(_ text: String) -> Check {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespaces)), let host = url.host?.lowercased(),
              let scheme = url.scheme?.lowercased() else { return .bad("Enter a full URL such as https://host:9847") }
        let loopback = ["localhost", "127.0.0.1", "::1"].contains(host)
        if scheme == "https" || (scheme == "http" && loopback) { return .ok(url) }
        return .bad("Plain HTTP is only allowed for localhost. Use https:// for a remote collector.")
    }

    /// Shows one snapshot from a JSON file (the dashboard's export format) and stops polling.
    func importSnapshot(from url: URL) throws {
        let s = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
        begin(.file(url.lastPathComponent))
        snapshot = s
        history = [Sample(s, at: Self.date(from: s.timestamp))]
        status = .live
    }

    /// The latest sample as JSON in the telemetry schema, for Export.
    func exportSnapshot() throws -> Data? {
        guard let s = snapshot else { return nil }
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(s)
    }

    func connect(url: URL, token: String) {
        self.token = token
        begin(.remote(url.absoluteString), endpoint: url)
    }

    private func begin(_ new: Source, endpoint url: URL? = nil) {
        loop?.cancel()
        snapshot = nil
        history = []
        dismissed = []
        replay = []
        replayIndex = nil
        notifier.reset()
        failures = 0
        status = .starting
        source = new
        if new != .local { collector.stop() }
        if new == .demo { token = "" }
        endpoint = url
        loop = Task { [weak self] in await self?.run() }
    }

    func start() {
        if notificationsEnabled { AlertNotifications.requestAuthorization() }
        let args = CommandLine.arguments
        if args.contains("--demo") { begin(.demo) } else { begin(.local) }
    }

    func stop() {
        loop?.cancel()
        collector.stop()
    }

    // MARK: polling

    private func run() async {
        switch source {
        case .demo:
            var t = 0.0
            // Pre-fill so the charts have shape in the first frame.
            for i in stride(from: -60.0, to: 0, by: 1) { append(DemoData.snapshot(at: i), date: Date().addingTimeInterval(i * 2)) }
            while !Task.isCancelled {
                if !paused { append(DemoData.snapshot(at: t), date: Date()); status = .live }
                t += 1
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            return
        case .local:
            do {
                let ep = try collector.start()
                endpoint = ep.url
                token = ep.token
            } catch {
                status = .failed(error.localizedDescription)
                return
            }
        case .file:
            return
        case .remote:
            break
        }
        await seedHistory()
        while !Task.isCancelled {
            if !paused { await poll() }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private func request(_ path: String) -> URLRequest? {
        guard let base = endpoint, let url = URL(string: path, relativeTo: base) else { return nil }
        var r = URLRequest(url: url)
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }

    // MARK: anomalies and evidence (collector endpoints; absent for demo data and imported files)

    private var hasCollector: Bool {
        switch source { case .local, .remote: return true; case .demo, .file: return false }
    }

    private func fetch<T: Decodable>(_ path: String, as type: T.Type) async -> T? {
        guard hasCollector, let r = request(path) else { return nil }
        guard let (data, resp) = try? await session.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Nil when there is no collector, or it predates /v1/anomalies.
    func anomalies(since: Date, limit: Int = 900) async -> AnomalyReport? {
        await fetch("/v1/anomalies?since=\(Int(since.timeIntervalSince1970))&limit=\(limit)", as: AnomalyReport.self)
    }

    func evidence(_ q: EvidenceRequest) async -> EvidenceReport? {
        await fetch("/v1/evidence?from=\(q.from.timeIntervalSince1970)&to=\(q.to.timeIntervalSince1970)&metric=\(q.metric)",
                    as: EvidenceReport.self)
    }

    func timeline(from: Date, to: Date) async -> TimelineReport? {
        await fetch("/v1/timeline?from=\(from.timeIntervalSince1970)&to=\(to.timeIntervalSince1970)&threshold=\(Int(threshold))",
                    as: TimelineReport.self)
    }

    func changes(from: Date, to: Date) async -> ChangesReport? {
        await fetch("/v1/changes?since=\(from.timeIntervalSince1970)&to=\(to.timeIntervalSince1970)", as: ChangesReport.self)
    }

    var canExplain: Bool { hasCollector }

    // MARK: time machine

    /// Loads up to the last 1000 stored samples (about 33 minutes at the default interval) and shows the
    /// newest. False when there is no collector or it holds fewer than two samples.
    func beginReplay() async -> Bool {
        let since = Int(Date().timeIntervalSince1970) - 3600
        guard let h = await fetch("/v1/history?since=\(since)&limit=1000", as: HistoryResponse.self), h.samples.count > 1 else { return false }
        replay = h.samples
        scrub(to: h.samples.count - 1)
        return true
    }

    func scrub(to index: Int) {
        guard replay.indices.contains(index) else { return }
        replayIndex = index
        snapshot = replay[index]
    }

    func endReplay() {
        replayIndex = nil
        replay = []
        Task { await poll() }
    }

    private func seedHistory() async {
        let since = Int(Date().timeIntervalSince1970) - 1800
        guard let r = request("/v1/history?since=\(since)&limit=300") else { return }
        for _ in 0..<10 {   // the local collector needs a moment to bind
            if Task.isCancelled { return }
            if let (data, resp) = try? await session.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200,
               let h = try? JSONDecoder().decode(HistoryResponse.self, from: data) {
                history = h.samples.map { Sample($0, at: Self.date(from: $0.timestamp)) }
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    private func poll() async {
        guard let r = request("/v1/snapshot") else { return }
        do {
            let (data, resp) = try await session.data(for: r)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                throw NSError(domain: "vytrix", code: code, userInfo: [NSLocalizedDescriptionKey:
                    code == 401 ? "The collector rejected the token (401)." : "The collector answered HTTP \(code)."])
            }
            append(try JSONDecoder().decode(Snapshot.self, from: data), date: Date())
            failures = 0
            status = .live
        } catch {
            failures += 1
            // The local collector is still starting for the first few polls; don't flash an error.
            if source != .local || failures > 5 { status = .failed(error.localizedDescription) }
        }
    }

    private func append(_ s: Snapshot, date: Date) {
        if replayIndex == nil { snapshot = s }
        let firing = AlertRules.compute(s, threshold: threshold)
        dismissed.formIntersection(firing.map(\.id))
        let fresh = notifier.fresh(firing)
        if source != .demo, notificationsEnabled, !fresh.isEmpty, replayIndex == nil { AlertNotifications.post(fresh, host: s.host.name) }
        history.append(Sample(s, at: date))
        if history.count > maxSamples { history.removeFirst(history.count - maxSamples) }
    }

    private static func date(from iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso) ?? Date()
    }
}

// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftUI

enum Pane: String, CaseIterable, Identifiable {
    case overview = "Overview", applications = "Applications", containers = "Containers", projects = "Projects"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.bottom.50percent"
        case .applications: return "square.stack.3d.up"
        case .containers: return "shippingbox"
        case .projects: return "folder"
        }
    }
}

@MainActor
final class TelemetryStore: ObservableObject {
    enum Source: Equatable { case local, remote(String), demo }
    enum Status: Equatable { case starting, live, failed(String) }

    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var history: [Sample] = []
    @Published private(set) var status: Status = .starting
    @Published private(set) var source: Source = .local
    @Published var paused = false
    @Published var search = ""

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

    func connect(url: URL, token: String) {
        self.token = token
        begin(.remote(url.absoluteString), endpoint: url)
    }

    private func begin(_ new: Source, endpoint url: URL? = nil) {
        loop?.cancel()
        snapshot = nil
        history = []
        failures = 0
        status = .starting
        source = new
        if new != .local { collector.stop() }
        if new == .demo { token = "" }
        endpoint = url
        loop = Task { [weak self] in await self?.run() }
    }

    func start() {
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
        snapshot = s
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

// SPDX-License-Identifier: BUSL-1.1
import Foundation

/// Response of the collector's GET /v1/anomalies (docs/API.md). Scores are nil while the band warms
/// up or when the host did not report the metric: absent, never zero.
struct AnomalyReport: Decodable, Equatable {
    struct Score: Decodable, Equatable { var score: Double; var anomalous: Bool }
    struct Row: Decodable, Equatable {
        var timestamp: String
        var cpu: Score?; var memory: Score?; var disk: Score?; var network: Score?
        func score(_ metric: String) -> Score? {
            switch metric { case "cpu": return cpu; case "memory": return memory; case "disk": return disk; case "network": return network; default: return nil }
        }
    }
    struct Window: Decodable, Equatable { var metric: String; var start: String; var end: String; var peak: Double; var samples: Int }
    var warmupSamples: Int
    var threshold: Double
    var samples: [Row]
    var windows: [Window]
    var rate: [String: Double?]

    /// True once any sample in the range was scored for the metric.
    func isScored(_ metric: String) -> Bool { samples.contains { $0.score(metric) != nil } }

    /// Anomaly windows of one metric as date ranges, widened to at least two seconds so a single
    /// anomalous sample is still visible on a chart.
    func ranges(for metric: String) -> [ClosedRange<Date>] {
        windows.filter { $0.metric == metric }.compactMap { w in
            guard let a = EvidenceTime.date(w.start), let b = EvidenceTime.date(w.end) else { return nil }
            return a...max(b, a.addingTimeInterval(2))
        }
    }
}

/// Response of GET /v1/evidence.
struct EvidenceReport: Decodable, Equatable {
    struct Span: Decodable, Equatable { var from: Double; var to: Double; var samples: Int; var baselineSamples: Int }
    struct Stat: Decodable, Equatable { var mean: Double?; var peak: Double? }
    struct App: Decodable, Equatable, Identifiable {
        var name: String; var mean: Double; var peak: Double?; var present: Int; var samples: Int
        var baselineMean: Double?; var delta: Double?
        var id: String { name }
    }
    struct Container: Decodable, Equatable, Identifiable {
        var name: String?; var runtime: String?; var image: String?
        var meanCpu: Double?; var peakCpu: Double?; var peakMemory: Double?; var memoryLimit: Double?
        var id: String { "\(runtime ?? "")-\(name ?? "")" }
    }
    struct Anomalies: Decodable, Equatable {
        var windows: [AnomalyReport.Window]; var peaks: [String: Double?]; var scoredSamples: Int
    }
    var metric: String
    var window: Span
    var host: [String: Stat]
    var baselineHost: [String: Stat]?
    var apps: [App]
    var containers: [Container]
    var anomalies: Anomalies
    var notes: [String]
}

enum EvidenceTime {
    static func date(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }
}

/// A selected time range on a chart, to ask the collector what was busy then.
struct EvidenceRequest: Identifiable, Equatable {
    var from: Date
    var to: Date
    var metric: String
    var id: String { "\(metric)-\(from.timeIntervalSince1970)-\(to.timeIntervalSince1970)" }

    /// The collector needs from < to and at most 24 hours; a drag of under two seconds is a click.
    static func make(_ range: ClosedRange<Date>?, metric: String) -> EvidenceRequest? {
        guard let r = range, r.upperBound.timeIntervalSince(r.lowerBound) >= 2,
              r.upperBound.timeIntervalSince(r.lowerBound) <= 86_400 else { return nil }
        return EvidenceRequest(from: r.lowerBound, to: r.upperBound, metric: metric)
    }
}

/// Response of GET /v1/timeline: alert transitions, container changes and anomaly windows in order,
/// with a fingerprint of the pattern and how it differs from the range before.
struct TimelineReport: Decodable, Equatable {
    struct Event: Decodable, Equatable, Identifiable {
        var time: String; var kind: String; var subject: String; var detail: String
        var severity: String; var text: String
        var id: String { "\(time)|\(kind)|\(subject)|\(detail)" }
    }
    struct Why: Decodable, Equatable {
        var newSincePrevious: [String]; var goneSincePrevious: [String]; var previousFingerprint: String
    }
    struct Span: Decodable, Equatable { var samples: Int; var baselineSamples: Int }
    var window: Span
    var threshold: Double
    var fingerprint: String
    var events: [Event]
    var eventCount: Int
    var whyChanged: Why?
    var notes: [String]

    /// `alert|cpu|fired|critical` as words.
    static func describe(key: String) -> String {
        let p = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard p.count >= 3 else { return key }
        return "\(p[0]) \(p[1]) \(p[2])" + (p.count > 3 && !p[3].isEmpty ? " (\(p[3]))" : "")
    }
}

/// Response of GET /v1/changes. `changes` is nil with fewer than two samples in the window.
struct ChangesReport: Decodable, Equatable {
    struct PortRow: Decodable, Equatable, Hashable { var port: Int; var app: String }
    struct ContainerChange: Decodable, Equatable, Hashable { var container: String; var from: String?; var to: String? }
    struct Transient: Decodable, Equatable { var apps: [String]; var ports: [PortRow]; var containers: [String] }
    struct Changes: Decodable, Equatable {
        var appsStarted: [String]; var appsStopped: [String]
        var portsOpened: [PortRow]; var portsClosed: [PortRow]
        var containersAppeared: [String]; var containersGone: [String]
        var containersChanged: [ContainerChange]
        var transient: Transient
        var isEmpty: Bool {
            appsStarted.isEmpty && appsStopped.isEmpty && portsOpened.isEmpty && portsClosed.isEmpty
                && containersAppeared.isEmpty && containersGone.isEmpty && containersChanged.isEmpty
                && transient.apps.isEmpty && transient.ports.isEmpty && transient.containers.isEmpty
        }
    }
    var changes: Changes?
    var notes: [String]
}

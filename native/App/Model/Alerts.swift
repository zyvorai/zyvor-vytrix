// SPDX-License-Identifier: BUSL-1.1
import Foundation

/// Port of lib/alerts.ts: threshold alerts on host CPU, memory, disk and container memory limits.
/// Informational only; nothing here changes the host.
struct VytrixAlert: Identifiable, Equatable {
    enum Severity: Int, Comparable {
        case warning = 0, critical = 1
        static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
        var label: String { self == .critical ? "Critical" : "Warning" }
    }
    var id: String
    var severity: Severity
    var title: String
    var text: String
}

enum AlertRules {
    static let defaultThreshold = 80.0

    /// Critical from threshold + 10, capped at 100, exactly as the web dashboard does.
    static func compute(_ s: Snapshot, threshold: Double) -> [VytrixAlert] {
        func severity(_ v: Double) -> VytrixAlert.Severity { v >= min(100, threshold + 10) ? .critical : .warning }
        var out: [VytrixAlert] = []
        let memory = s.host.memoryTotal > 0 ? s.memoryUsed / s.host.memoryTotal * 100 : 0
        let disk = s.diskTotal > 0 ? s.diskUsed / s.diskTotal * 100 : 0
        let t = String(format: "%.0f", threshold)
        if s.cpu >= threshold {
            out.append(.init(id: "cpu", severity: severity(s.cpu), title: "CPU pressure",
                             text: String(format: "Host CPU is %.1f%%, above your %@%% threshold.", s.cpu, t)))
        }
        if memory >= threshold {
            out.append(.init(id: "memory", severity: severity(memory), title: "Memory pressure",
                             text: String(format: "Memory is %.0f%% used, above your %@%% threshold.", memory, t)))
        }
        if disk >= threshold {
            out.append(.init(id: "disk", severity: severity(disk), title: "Disk nearly full",
                             text: String(format: "The root volume is %.0f%% full.", disk)))
        }
        for c in s.containers ?? [] where c.state.lowercased() == "running" {
            guard let limit = c.memoryLimit, limit > 0 else { continue }
            let pct = c.memory / limit * 100
            if pct >= threshold {
                out.append(.init(id: "container-\(c.runtime)-\(c.id)", severity: severity(pct),
                                 title: "\(c.name) near memory limit",
                                 text: String(format: "%@ container is using %.0f%% of its memory limit.", c.runtime, pct)))
            }
        }
        return out
    }
}

/// Decides which alerts deserve a notification. An alert notifies once when it appears and again if it
/// escalates to critical; it re-arms only after it has been absent for `quietPolls` samples, so a value
/// hovering at the threshold does not spam.
struct AlertNotifier {
    var quietPolls = 3
    private var notified: [String: VytrixAlert.Severity] = [:]
    private var absent: [String: Int] = [:]

    init(quietPolls: Int = 3) { self.quietPolls = quietPolls }

    mutating func fresh(_ current: [VytrixAlert]) -> [VytrixAlert] {
        let ids = Set(current.map(\.id))
        for id in notified.keys where !ids.contains(id) {
            absent[id, default: 0] += 1
            if absent[id]! >= quietPolls { notified[id] = nil; absent[id] = nil }
        }
        var out: [VytrixAlert] = []
        for a in current {
            absent[a.id] = nil
            if let seen = notified[a.id], seen >= a.severity { continue }
            notified[a.id] = a.severity
            out.append(a)
        }
        return out
    }

    mutating func reset() { notified = [:]; absent = [:] }
}

// SPDX-License-Identifier: BUSL-1.1
import Foundation

@main
struct AlertTests {
    static var failures = 0
    static func check(_ ok: Bool, _ name: String) {
        if ok { print("ok   \(name)") } else { print("FAIL \(name)"); failures += 1 }
    }

    static func snapshot(cpu: Double = 10, memory: Double = 0.4, disk: Double = 0.4, containers: [Container]? = nil) -> Snapshot {
        let json = """
        {"version":1,"timestamp":"2026-10-13T00:00:00Z","host":{"name":"zyvor-dev-01","os":"macOS","cores":8,"memoryTotal":1000},
         "cpu":\(cpu),"memoryUsed":\(memory * 1000),"diskUsed":\(disk * 1000),"diskTotal":1000,"download":0,"upload":0,"processes":[]}
        """
        var s = try! JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        s.containers = containers
        return s
    }

    static func container(memory: Double, limit: Double?, state: String = "running") -> Container {
        Container(runtime: "docker", id: "abc", name: "db", image: "pg", state: state, cpu: 1, memory: memory,
                  memoryLimit: limit, netIn: 0, netOut: 0, ports: [])
    }

    static func main() {
        let fixtures = CommandLine.arguments.dropFirst().first
        check(AlertRules.compute(snapshot(), threshold: 80).isEmpty, "quiet host raises nothing")

        let warn = AlertRules.compute(snapshot(cpu: 85), threshold: 80)
        check(warn.count == 1 && warn[0].id == "cpu" && warn[0].severity == .warning, "cpu at 85 is a warning")
        let crit = AlertRules.compute(snapshot(cpu: 90), threshold: 80)
        check(crit.first?.severity == .critical, "critical from threshold + 10")
        check(AlertRules.compute(snapshot(cpu: 99), threshold: 95).first?.severity == .warning, "critical bar is capped at 100, so 99 is a warning")
        check(AlertRules.compute(snapshot(cpu: 100), threshold: 95).first?.severity == .critical, "100 is critical at any threshold")

        let mem = AlertRules.compute(snapshot(memory: 0.9), threshold: 80)
        check(mem.first?.id == "memory" && mem.first?.severity == .critical, "memory at 90% is critical")
        let disk = AlertRules.compute(snapshot(disk: 0.82), threshold: 80)
        check(disk.first?.id == "disk", "disk alert")

        let near = AlertRules.compute(snapshot(containers: [container(memory: 90, limit: 100)]), threshold: 80)
        check(near.first?.id == "container-docker-abc", "container near its memory limit")
        check(AlertRules.compute(snapshot(containers: [container(memory: 90, limit: nil)]), threshold: 80).isEmpty,
              "no limit means no container alert")
        check(AlertRules.compute(snapshot(containers: [container(memory: 90, limit: 100, state: "exited")]), threshold: 80).isEmpty,
              "stopped containers are ignored")

        // Export writes the telemetry schema; Import must read back exactly what Export wrote.
        let original = snapshot(cpu: 42, containers: [container(memory: 50, limit: 100)])
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let roundTrip = (try? JSONDecoder().decode(Snapshot.self, from: enc.encode(original)))
        check(roundTrip == original, "snapshot export decodes back to the same snapshot")
        let text = String(data: (try? enc.encode(original)) ?? Data(), encoding: .utf8) ?? ""
        check(text.contains("\"memoryTotal\"") && !text.contains("battery"), "export uses schema keys and omits absent readings")

        var n = AlertNotifier(quietPolls: 3)
        let a = VytrixAlert(id: "cpu", severity: .warning, title: "CPU", text: "")
        check(n.fresh([a]).count == 1, "first appearance notifies")
        check(n.fresh([a]).isEmpty, "a steady alert does not repeat")
        var c = a; c.severity = .critical
        check(n.fresh([c]).count == 1, "escalation notifies again")
        check(n.fresh([a]).isEmpty, "dropping back to warning is silent")
        _ = n.fresh([]); _ = n.fresh([])
        check(n.fresh([a]).isEmpty, "two quiet polls are not enough to re-arm")
        _ = n.fresh([]); _ = n.fresh([]); _ = n.fresh([])
        check(n.fresh([a]).count == 1, "re-arms after the alert stays clear")

        // Contract with the collector: these files come from agent/vytrix.py (anomaly_report, evidence_report).
        if let dir = fixtures {
            let dec = JSONDecoder()
            let anomalies = try? dec.decode(AnomalyReport.self, from: Data(contentsOf: URL(fileURLWithPath: dir + "/anomalies.json")))
            check(anomalies != nil, "collector /v1/anomalies JSON decodes")
            if let a = anomalies {
                check(a.isScored("cpu") && a.warmupSamples == 150, "anomaly report is scored after warm-up")
                check(a.samples.first?.cpu == nil, "warm-up samples decode as nil, not zero")
                check(a.ranges(for: "cpu").count == 1, "one cpu anomaly range for the spike")
                check(a.ranges(for: "memory").isEmpty, "no memory anomaly ranges")
                check((a.rate["cpu"] ?? nil) != nil, "scored metric has a rate")
            }
            let evidence = try? dec.decode(EvidenceReport.self, from: Data(contentsOf: URL(fileURLWithPath: dir + "/evidence.json")))
            check(evidence != nil, "collector /v1/evidence JSON decodes")
            if let e = evidence {
                check(e.apps.first?.name == "Build" && (e.apps.first?.delta ?? 0) > 0, "busy app leads with a positive delta")
                check(e.containers.first?.name == "db", "containers decode")
                check(e.baselineHost != nil && e.host["cpu"]?.mean != nil, "host stats decode")
                check(!e.notes.isEmpty, "notes decode")
            }
        }
        if let dir = fixtures {
            let dec = JSONDecoder()
            let timeline = try? dec.decode(TimelineReport.self, from: Data(contentsOf: URL(fileURLWithPath: dir + "/timeline.json")))
            check(timeline != nil, "collector /v1/timeline JSON decodes")
            if let t = timeline {
                check(t.fingerprint.count == 12, "fingerprint is 12 hex characters")
                check(t.events.contains { $0.kind == "alert" && $0.subject == "cpu" && $0.detail == "fired" }, "the cpu spike fired an alert")
                check(t.whyChanged != nil, "whyChanged decodes")
                check(TimelineReport.describe(key: "alert|cpu|fired|critical") == "alert cpu fired (critical)", "keys are described in words")
            }
            let changes = try? dec.decode(ChangesReport.self, from: Data(contentsOf: URL(fileURLWithPath: dir + "/changes.json")))
            check(changes != nil, "collector /v1/changes JSON decodes")
            check(changes?.changes?.appsStarted == ["Late"] && changes?.changes?.portsOpened.first?.port == 4000, "started app and opened port decode")
            let none = try? dec.decode(ChangesReport.self, from: Data(contentsOf: URL(fileURLWithPath: dir + "/changes-empty.json")))
            check(none != nil && none?.changes == nil, "a window with too few samples decodes with no changes")
        }
        if let dir = fixtures {
            let h = try? JSONDecoder().decode(HistoryResponse.self, from: Data(contentsOf: URL(fileURLWithPath: dir + "/history.json")))
            check(h != nil && h?.samples.count == 2, "collector /v1/history JSON decodes to full snapshots for the time machine")
            check(h?.samples.first?.processes.isEmpty == false, "a stored sample keeps its processes")
        }
        let t0 = Date(timeIntervalSince1970: 1_000)
        check(EvidenceRequest.make(t0...t0.addingTimeInterval(30), metric: "cpu") != nil, "a 30 s range can ask for evidence")
        check(EvidenceRequest.make(t0...t0.addingTimeInterval(0.5), metric: "cpu") == nil, "a click is not a range")
        check(EvidenceRequest.make(nil, metric: "cpu") == nil, "no selection, no request")
        check(EvidenceRequest.make(t0...t0.addingTimeInterval(90_000), metric: "cpu") == nil, "more than 24 h is refused")

        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("native logic tests passed")
    }
}

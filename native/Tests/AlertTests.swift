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

        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("native logic tests passed")
    }
}

// SPDX-License-Identifier: BUSL-1.1
import Foundation

/// Simulated telemetry for screenshots and trying the app without a collector. Host `zyvor-dev-01`.
/// Public images must come from this, never from a real machine (AGENTS.md).
enum DemoData {
    private static let GB = 1_073_741_824.0
    private static let MB = 1_048_576.0

    static func snapshot(at t: Double) -> Snapshot {
        let apps: [(String, Double, Double, Int, String?, [Int])] = [
            ("Google Chrome", 18.4, 5.2, 24, nil, []), ("python", 12.7, 1.8, 4, "ml-inference", [8000]),
            ("Visual Studio Code", 6.8, 2.1, 12, nil, []), ("Docker", 4.2, 3.6, 8, nil, []),
            ("node", 3.1, 0.72, 5, "zyvor-dashboard", [5173]), ("Zyvor Netra", 2.1, 0.34, 2, nil, []),
            ("Slack", 1.2, 0.48, 7, nil, []), ("Terminal", 0.4, 0.22, 3, nil, []),
        ]
        var pid = 100
        var procs: [Snapshot.Proc] = []
        for (i, a) in apps.enumerated() {
            let wiggle = 1 + 0.12 * sin(t / 3 + Double(i))
            for k in 0..<a.3 {
                pid += 1
                procs.append(.init(pid: pid, name: k == 0 ? a.0 : "\(a.0) Helper \(k)", app: a.0,
                                   cpu: a.1 * wiggle / Double(a.3), memory: a.2 * GB / Double(a.3),
                                   project: a.4, ports: k == 0 ? a.5 : []))
            }
        }
        let cpu = 42 + 8 * sin(t / 4) + 3 * sin(t / 1.7)
        let rows: [(String, String, String, String, String, Double, Double, Double?, [(Int?, Int)])] = [
            ("docker", "a1b2c3d4e5f6", "postgres", "postgres:16-alpine", "running", 2.4, 412 * MB, 2 * GB, [(5432, 5432)]),
            ("docker", "b2c3d4e5f6a1", "redis", "redis:7-alpine", "running", 0.7, 18 * MB, 512 * MB, [(6379, 6379)]),
            ("docker", "c3d4e5f6a1b2", "web", "nginx:alpine", "running", 0.4, 9 * MB, nil, [(8080, 80)]),
            ("podman", "d4e5f6a1b2c3", "ml-worker", "ghcr.io/zyvor/ml-worker:1.4", "running", 39.9, 1.6 * GB, 4 * GB, []),
            ("podman", "e5f6a1b2c3d4", "grafana", "grafana/grafana:11", "exited", 0, 0, nil, [(3000, 3000)]),
        ]
        let containers = rows.map { r in
            Container(runtime: r.0, id: r.1, name: r.2, image: r.3, state: r.4, cpu: r.5, memory: r.6, memoryLimit: r.7,
                      netIn: r.4 == "running" ? 120 * MB : 0, netOut: r.4 == "running" ? 40 * MB : 0,
                      ports: r.8.map { PortMapping(hostPort: $0.0, containerPort: $0.1, protocol: "tcp") })
        }
        return Snapshot(
            version: 1, timestamp: ISO8601DateFormatter().string(from: Date()),
            host: .init(name: "zyvor-dev-01", os: "macOS 27.2 (demo)", cores: 16, memoryTotal: 32 * GB),
            cpu: cpu, memoryUsed: (15.3 + 0.4 * sin(t / 6)) * GB, diskUsed: 0.62 * 316 * GB, diskTotal: 316 * GB,
            download: 2.6 * MB + 0.8 * MB * sin(t / 3), upload: 840 * 1024, battery: nil,
            processes: procs, containers: containers,
            runtimes: [.init(name: "docker", available: true, error: nil), .init(name: "podman", available: true, error: nil)])
    }
}

// SPDX-License-Identifier: BUSL-1.1
import Foundation
import AppIntents

/// Checks for the widget data file and the App Intents' answers.
enum WidgetChecks {
    static func data(updated: Date, simulated: Bool = false, apps: [WidgetData.App]? = nil, alerts: Int = 0) -> WidgetData {
        WidgetData(updated: updated, host: "mac-01", simulated: simulated, cpu: 41.6, memory: 63, disk: 70, download: 1000, upload: 10,
                   alerts: alerts, topApps: apps ?? [.init(name: "Chrome", cpu: 18.4), .init(name: "Xcode", cpu: 9), .init(name: "node", cpu: 4.4)])
    }

    static func answer<I: AppIntent>(_ intent: I) -> String {
        var out = ""
        let done = DispatchSemaphore(value: 0)
        Task {
            if let result = try? await intent.perform() {
                out = Mirror(reflecting: result).children.compactMap { $0.value as? String }.first ?? ""
            }
            done.signal()
        }
        done.wait()
        return out
    }

    static func run(_ check: (Bool, String) -> Void) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let d = data(updated: now)
        check(d.spokenTopApps() == "Chrome 18%, Xcode 9% and node 4%", "top apps are spoken as a list")
        check(data(updated: now, apps: []).spokenTopApps() == nil, "no apps, nothing to say")
        check(data(updated: now, apps: [.init(name: "Chrome", cpu: 3)]).spokenTopApps() == "Chrome 3%", "one app")
        check(!d.isStale(now: now.addingTimeInterval(60)) && d.isStale(now: now.addingTimeInterval(121)), "stale after two minutes")
        check(d.age(now: now.addingTimeInterval(200)) == "3 min ago", "age in minutes")

        // The file round trip through a temporary directory (no widget container needed).
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vytrix-widget-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        check(WidgetStore.read(in: dir) == nil, "nothing to read before the first write")
        check(WidgetStore.write(d, in: dir), "writes the widget file")
        check(WidgetStore.read(in: dir) == d, "reads back exactly what was written")
        let attrs = try? FileManager.default.attributesOfItem(atPath: dir.path)
        check((attrs?[.posixPermissions] as? Int) == 0o700, "the directory is private")
        check(!WidgetStore.write(d, in: nil), "no container, no write")
        let missing = URL(fileURLWithPath: "/nonexistent-home")
        check(WidgetStore.directory(home: missing, sandboxed: false) == nil, "the app does not create the widget container")

        // Intents answer from the published reading, and say when it is old, missing or simulated.
        IntentReading.now = { now }
        IntentReading.source = { d }
        let top = answer(TopCPUIntent())
        check(top == "CPU is at 42%. Busiest: Chrome 18%, Xcode 9% and node 4%.", "top CPU intent answer: \(top)")
        let status = answer(HostStatusIntent())
        check(status == "mac-01: CPU 42%, memory 63%, disk 70% full, no active alerts.", "status intent answer: \(status)")
        IntentReading.source = { data(updated: now, alerts: 2) }
        check(answer(HostStatusIntent()).hasSuffix("2 active alerts."), "alert count is stated")
        IntentReading.source = { data(updated: now.addingTimeInterval(-3600)) }
        check(answer(TopCPUIntent()).hasPrefix("Vytrix is not running, so the last reading was 1 h ago."), "an old reading is called old")
        IntentReading.source = { data(updated: now, simulated: true) }
        check(answer(TopCPUIntent()).hasSuffix("This is simulated data."), "simulated data is labelled")
        IntentReading.source = { nil }
        check(answer(TopCPUIntent()).hasPrefix("Vytrix has no reading yet."), "no reading is stated, not invented")
    }
}

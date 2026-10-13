// SPDX-License-Identifier: BUSL-1.1
import AppIntents

/// Text-only answers from the latest reading the app published. Intents never act on the host, and
/// they say so when the reading is old or missing instead of guessing.
enum IntentReading {
    /// Where intents read the latest published sample; tests replace it.
    static var source: () -> WidgetData? = { WidgetStore.read() }
    static var now: () -> Date = { Date() }
}

private func reading() -> (WidgetData?, String?) {
    guard let d = IntentReading.source() else {
        return (nil, "Vytrix has no reading yet. Open Vytrix and try again in a few seconds.")
    }
    if d.isStale(now: IntentReading.now()) { return (d, "Vytrix is not running, so the last reading was \(d.age(now: IntentReading.now())).") }
    return (d, nil)
}

struct TopCPUIntent: AppIntent {
    static let title: LocalizedStringResource = "What is using my CPU?"
    static let description = IntentDescription("Says which apps are using the most CPU in Vytrix's latest reading. Read-only.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let (data, problem) = reading()
        guard let d = data else { let t = problem ?? "No reading."; return .result(value: t, dialog: IntentDialog(stringLiteral: t)) }
        let apps = d.spokenTopApps() ?? "no application data"
        var text = "CPU is at \(Int(d.cpu.rounded()))%. Busiest: \(apps)."
        if d.simulated { text += " This is simulated data." }
        if let problem { text = problem + " " + text }
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct HostStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "How is my Mac doing?"
    static let description = IntentDescription("CPU, memory, disk and active alerts from Vytrix's latest reading. Read-only.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let (data, problem) = reading()
        guard let d = data else { let t = problem ?? "No reading."; return .result(value: t, dialog: IntentDialog(stringLiteral: t)) }
        var text = "\(d.host): CPU \(Int(d.cpu.rounded()))%, memory \(Int(d.memory.rounded()))%, disk \(Int(d.disk.rounded()))% full, "
            + (d.alerts == 0 ? "no active alerts." : "\(d.alerts) active alert\(d.alerts == 1 ? "" : "s").")
        if d.simulated { text += " This is simulated data." }
        if let problem { text = problem + " " + text }
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct VytrixShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TopCPUIntent(), phrases: ["What is using my CPU in \(.applicationName)", "Top apps in \(.applicationName)"],
                    shortTitle: "What is using my CPU?", systemImageName: "cpu")
        AppShortcut(intent: HostStatusIntent(), phrases: ["How is my Mac doing in \(.applicationName)", "\(.applicationName) status"],
                    shortTitle: "How is my Mac doing?", systemImageName: "gauge.with.dots.needle.bottom.50percent")
    }
}

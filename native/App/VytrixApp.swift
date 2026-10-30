// SPDX-License-Identifier: BUSL-1.1
import SwiftUI
import AppKit

/// Closing the window keeps Vytrix running in the menu bar (and the bundled collector with it). The
/// window is a single `Window` scene, so a Dock click or "Open Vytrix" brings it back; Quit stops
/// the collector.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private var signalSources: [DispatchSourceSignal] = []

    /// `kill`, a logout script or Ctrl-C should quit cleanly so the bundled collector stops with the
    /// app. (The collector also exits by itself when its parent dies, which covers SIGKILL.)
    func applicationDidFinishLaunching(_ notification: Notification) {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }
}

@main
struct VytrixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = TelemetryStore()

    /// `--appearance light|dark` pins the colour scheme (screenshots); otherwise the system decides.
    static var forcedScheme: ColorScheme? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--appearance"), i + 1 < a.count else { return nil }
        return a[i + 1] == "dark" ? .dark : a[i + 1] == "light" ? .light : nil
    }

    /// `--section applications` opens that section (screenshots).
    static var initialSection: Pane {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--section"), i + 1 < a.count else { return .overview }
        return Pane.allCases.first { $0.rawValue.lowercased() == a[i + 1].lowercased() } ?? .overview
    }

    /// The window's task re-runs each time it reopens; the collector must only start once.
    @MainActor private func startOnce() {
        guard !Self.started else { return }
        Self.started = true
        store.start()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { store.stop() }
        }
    }
    @MainActor private static var started = false

    /// Optional, opens the payment page in the browser; the app makes no request itself and nothing is locked.
    static let supportURL = URL(string: "https://payments.cashfree.com/forms/zyvor-vytrix-supporter")!

    static func showAbout() {
        let credits = NSMutableAttributedString(
            string: "A read-only system activity monitor by Zyvor AI Labs.\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        credits.append(NSAttributedString(string: "zyvor.dev", attributes: [.font: NSFont.systemFont(ofSize: 11), .link: URL(string: "https://zyvor.dev")!]))
        credits.append(NSAttributedString(string: " · Business Source License 1.1",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
        let centered = NSMutableParagraphStyle(); centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate()
    }

    var body: some Scene {
        Window("Vytrix", id: "main") {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(Self.forcedScheme ?? store.appearance.scheme)
                .tint(store.accent.color)
                .task { startOnce() }
        }
        .defaultSize(width: 1120, height: 720)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Vytrix") { Self.showAbout() }
            }
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .help) {
                Button("Support Vytrix…") { NSWorkspace.shared.open(Self.supportURL) }
            }
            CommandMenu("Source") {
                Button("Monitor This Mac") { store.useThisMac() }.keyboardShortcut("1")
                Button("Show Demo Data") { store.useDemo() }.keyboardShortcut("2")
                Divider()
                Button(store.paused ? "Resume" : "Pause") { store.paused.toggle() }.keyboardShortcut("p")
            }
        }

        MenuBarExtra {
            MenuBarView().environmentObject(store)
        } label: {
            MenuBarLabel().environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }
}

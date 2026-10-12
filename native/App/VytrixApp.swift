// SPDX-License-Identifier: BUSL-1.1
import SwiftUI
import AppKit

/// Closing the window keeps Vytrix running in the menu bar (and the bundled collector with it). The
/// window is a single `Window` scene, so a Dock click or "Open Vytrix" brings it back; Quit stops
/// the collector.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
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

    var body: some Scene {
        Window("Vytrix", id: "main") {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(Self.forcedScheme)
                .task { startOnce() }
        }
        .defaultSize(width: 1120, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
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

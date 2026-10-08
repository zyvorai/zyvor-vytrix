// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import AppKit

@main
struct VytrixApp: App {
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

    var body: some Scene {
        WindowGroup("Vytrix") {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(Self.forcedScheme)
                .task {
                    store.start()
                    NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
                        MainActor.assumeIsolated { store.stop() }
                    }
                }
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
    }
}

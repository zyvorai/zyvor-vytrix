// SPDX-License-Identifier: BUSL-1.1
import SwiftUI
import AppKit

/// One window: closing it quits, which also stops the bundled collector. Without this the app stays
/// running windowless, and with New Window removed a Dock click cannot bring the window back.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
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
            CommandGroup(replacing: .appInfo) {
                Button("About Vytrix") { Self.showAbout() }
            }
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

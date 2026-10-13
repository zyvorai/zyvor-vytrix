// SPDX-License-Identifier: BUSL-1.1
import Foundation

/// What the widgets and App Intents show: a few totals and the busiest apps from the latest sample.
/// No tokens and no per-process detail beyond app names and CPU; absent readings stay absent.
struct WidgetData: Codable, Equatable {
    struct App: Codable, Equatable { var name: String; var cpu: Double }
    var updated: Date
    var host: String
    var simulated: Bool
    var cpu: Double
    var memory: Double          // percent of installed memory in use
    var disk: Double            // percent of the root volume used
    var download: Double        // bytes per second
    var upload: Double
    var alerts: Int
    var topApps: [App]

    /// Older than this and the app is probably not running: say so instead of showing old numbers as current.
    static let staleAfter: TimeInterval = 120

    func isStale(now: Date = Date()) -> Bool { now.timeIntervalSince(updated) > Self.staleAfter }

    /// "Chrome 18%, Xcode 9% and node 4%", or nil with no apps.
    func spokenTopApps(limit: Int = 3) -> String? {
        let items = topApps.prefix(limit).map { "\($0.name) \(Int($0.cpu.rounded()))%" }
        switch items.count {
        case 0: return nil
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }

    func age(now: Date = Date()) -> String {
        let s = Int(max(0, now.timeIntervalSince(updated)))
        return s < 60 ? "\(s) s ago" : s < 3600 ? "\(s / 60) min ago" : "\(s / 3600) h ago"
    }
}

/// The file the app writes and the widgets read.
///
/// The widget extension is sandboxed, so it reads from its own container. The app is not sandboxed, so
/// it writes into that container (only once the widget has run and created it). Proper Developer ID
/// signing can move this to an App Group without changing the model.
enum WidgetStore {
    static let widgetBundleID = "dev.zyvor.vytrix.widgets"
    static let fileName = "widget.json"

    static var sandboxed: Bool { ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil }

    /// Directory holding the file, or nil when the widget's container does not exist yet.
    static func directory(home: URL = FileManager.default.homeDirectoryForCurrentUser, sandboxed: Bool = WidgetStore.sandboxed) -> URL? {
        if sandboxed {
            return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Vytrix", isDirectory: true)
        }
        let container = home.appendingPathComponent("Library/Containers/\(widgetBundleID)/Data", isDirectory: true)
        guard FileManager.default.fileExists(atPath: container.path) else { return nil }
        return container.appendingPathComponent("Library/Application Support/Vytrix", isDirectory: true)
    }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e
    }
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }

    @discardableResult
    static func write(_ data: WidgetData, in directory: URL? = directory()) -> Bool {
        guard let dir = directory else { return false }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try encoder().encode(data).write(to: dir.appendingPathComponent(fileName), options: .atomic)
            return true
        } catch { return false }
    }

    static func read(in directory: URL? = directory()) -> WidgetData? {
        guard let dir = directory, let raw = try? Data(contentsOf: dir.appendingPathComponent(fileName)) else { return nil }
        return try? decoder().decode(WidgetData.self, from: raw)
    }
}

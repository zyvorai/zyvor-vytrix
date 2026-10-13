// SPDX-License-Identifier: BUSL-1.1
import SwiftUI
import AppKit

/// Fixed per-metric chart colours and radii for the macOS 27 look, taken from the macos27 block of
/// app/globals.css. Chart colours do not follow the accent: colour is data, the accent is for intent.
/// Everything except CPU is a neutral grey, as on the web dashboard.
enum MetricColor {
    case cpu, memory, disk, network, upload, battery, containers, apps

    var color: Color {
        let (light, dark): (UInt32, UInt32)
        switch self {
        case .cpu: (light, dark) = (0x0088ff, 0x3ba3ff)
        case .memory: (light, dark) = (0x8e8e93, 0x98989d)
        case .disk: (light, dark) = (0xa1a1a6, 0x78787d)
        case .network: (light, dark) = (0x636366, 0xaeaeb2)
        case .upload: (light, dark) = (0xc7c7cc, 0x636366)
        case .battery: (light, dark) = (0x8e8e93, 0x98989d)
        case .containers: (light, dark) = (0xa1a1a6, 0x78787d)
        case .apps: (light, dark) = (0x636366, 0xaeaeb2)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return Theme.ns(isDark ? dark : light)
        })
    }
}

enum Theme {
    /// macos27 radii: panels 14, controls 10, small 7 (the window's 26 and the sidebar's 0 are the system's).
    static let panelRadius: CGFloat = 14
    static let controlRadius: CGFloat = 10
    static let smallRadius: CGFloat = 7

    static func ns(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

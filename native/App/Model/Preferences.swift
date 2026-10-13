// SPDX-License-Identifier: BUSL-1.1
import SwiftUI

/// The eight accents of the web dashboard (data-accent in app/globals.css, light values).
enum AccentChoice: String, CaseIterable, Identifiable {
    case blue, purple, pink, red, orange, yellow, green, graphite
    var id: Self { self }
    var label: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .blue: return Color(red: 0.00, green: 0.533, blue: 1.00)
        case .purple: return Color(red: 0.647, green: 0.314, blue: 0.878)
        case .pink: return Color(red: 1.00, green: 0.176, blue: 0.471)
        case .red: return Color(red: 1.00, green: 0.22, blue: 0.235)
        case .orange: return Color(red: 1.00, green: 0.553, blue: 0.157)
        case .yellow: return Color(red: 0.961, green: 0.722, blue: 0.00)
        case .green: return Color(red: 0.157, green: 0.706, blue: 0.29)
        case .graphite: return Color(red: 0.549, green: 0.549, blue: 0.576)
        }
    }
}

enum AppearanceChoice: String, CaseIterable, Identifiable {
    case auto, light, dark
    var id: Self { self }
    var label: String { rawValue.capitalized }
    var scheme: ColorScheme? { self == .light ? .light : self == .dark ? .dark : nil }
}

// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import Charts

/// A flat grouped surface, like the native app's grouped lists: no shadow, no tint.
struct Panel<Content: View>: View {
    var title: String?
    var subtitle: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
                }
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct MetricTile: View {
    let label: String
    let symbol: String
    let value: String
    var unit: String = ""
    let hint: String
    var series: [Double] = []
    var tint: Color = .secondary
    var action: (() -> Void)?

    var body: some View {
        Button { action?() } label: {
            VStack(alignment: .leading, spacing: 10) {
                Label(label, systemImage: symbol).font(.callout.weight(.medium)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).font(.system(size: 26, weight: .semibold)).monospacedDigit()
                    Text(unit).font(.callout).foregroundStyle(.tertiary)
                }
                Text(hint).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if series.count > 1 {
                    Chart(Array(series.enumerated()), id: \.offset) { LineMark(x: .value("t", $0.offset), y: .value("v", $0.element)) }
                        .chartXAxis(.hidden).chartYAxis(.hidden)
                        .foregroundStyle(tint)
                        .frame(height: 30)
                } else {
                    Spacer().frame(height: 30)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label): \(value) \(unit)")
    }
}

/// A thin horizontal bar, 0...1. One accent colour; the track is a neutral fill.
struct Meter: View {
    let fraction: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(Color.accentColor).frame(width: max(2, g.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 5)
    }
}

/// Neutral monogram, the app-icon stand-in (no per-app colours).
struct Monogram: View {
    let name: String
    var size: CGFloat = 28
    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: size * 0.26))
    }
}

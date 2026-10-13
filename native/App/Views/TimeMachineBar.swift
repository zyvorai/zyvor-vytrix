// SPDX-License-Identifier: BUSL-1.1
import SwiftUI

/// Scrubs the whole dashboard back through the collector's stored samples. Everything on screen is the
/// sample at the chosen time; live sampling continues in the background. Read-only.
struct TimeMachineBar: View {
    @EnvironmentObject var store: TelemetryStore

    var body: some View {
        let count = store.replay.count
        let index = store.replayIndex ?? max(0, count - 1)
        HStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
            Slider(value: Binding(get: { Double(index) }, set: { store.scrub(to: Int($0.rounded())) }),
                   in: 0...Double(max(1, count - 1)), step: 1)
                .accessibilityLabel("Time Machine position")
            VStack(alignment: .trailing, spacing: 0) {
                Text(label(index)).monospacedDigit().font(.callout.weight(.medium))
                Text("sample \(index + 1) of \(count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(minWidth: 130, alignment: .trailing)
            Button("Back to Live") { store.endReplay() }.keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func label(_ index: Int) -> String {
        guard store.replay.indices.contains(index), let d = EvidenceTime.date(store.replay[index].timestamp) else { return "–" }
        let ago = Int(Date().timeIntervalSince(d))
        let when = d.formatted(date: .omitted, time: .standard)
        return ago < 5 ? "\(when) · now" : "\(when) · \(ago / 60 > 0 ? "\(ago / 60) min " : "")\(ago % 60) s ago"
    }
}

// SPDX-License-Identifier: BUSL-1.1
import SwiftUI

struct AlertsView: View {
    @EnvironmentObject var store: TelemetryStore

    var body: some View {
        let alerts = store.alerts
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Panel(title: "Thresholds", subtitle: "Alerts fire at the threshold and turn critical 10 points above it.") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Slider(value: $store.threshold, in: 50...99, step: 1)
                            Text("\(Int(store.threshold))%").monospacedDigit().frame(width: 48, alignment: .trailing)
                        }
                        Toggle("Notify when an alert fires", isOn: $store.notificationsEnabled)
                        Text("Notifications are informational and never fire for demo data. Vytrix does not act on any alert.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                if alerts.isEmpty {
                    ContentUnavailableView("No active alerts", systemImage: "checkmark.circle",
                                           description: Text("CPU, memory, disk and container limits are below \(Int(store.threshold))%."))
                } else {
                    Panel(title: "Active", subtitle: "\(alerts.count) alert\(alerts.count == 1 ? "" : "s") on the latest sample") {
                        VStack(spacing: 0) {
                            ForEach(alerts) { a in
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: a.severity == .critical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                                        .foregroundStyle(a.severity == .critical ? .red : .orange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(a.title).font(.body.weight(.medium))
                                        Text(a.text).font(.callout).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Dismiss") { store.dismiss(a.id) }
                                }
                                .padding(.vertical, 10)
                                if a.id != alerts.last?.id { Divider() }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

// SPDX-License-Identifier: BUSL-1.1
import Foundation
import WidgetKit

/// Publishes the latest sample for the widgets and App Intents. Throttled: the widget needs a fresh
/// file every few seconds, and WidgetKit a reload at most about every half minute.
@MainActor
final class WidgetBridge {
    private var lastWrite = Date.distantPast
    private var lastReload = Date.distantPast

    func publish(_ s: Snapshot, alerts: Int, simulated: Bool, now: Date = Date()) {
        guard now.timeIntervalSince(lastWrite) >= 5 else { return }
        lastWrite = now
        let memory = s.host.memoryTotal > 0 ? s.memoryUsed / s.host.memoryTotal * 100 : 0
        let disk = s.diskTotal > 0 ? s.diskUsed / s.diskTotal * 100 : 0
        let top = AppGroup.group(s).prefix(5).map { WidgetData.App(name: $0.name, cpu: $0.cpu) }
        let data = WidgetData(updated: now, host: s.host.name, simulated: simulated, cpu: s.cpu, memory: memory, disk: disk,
                              download: s.download, upload: s.upload, alerts: alerts, topApps: Array(top))
        guard WidgetStore.write(data) else { return }   // no widget container yet: nothing is showing
        if now.timeIntervalSince(lastReload) >= 30 {
            lastReload = now
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

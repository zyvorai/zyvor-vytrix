// SPDX-License-Identifier: BUSL-1.1
import SwiftUI

/// What was busy in a selected range, compared with the same-length range before it. Read-only; it
/// correlates and does not claim a cause.
struct EvidenceSheet: View {
    let request: EvidenceRequest
    @EnvironmentObject var store: TelemetryStore
    @Environment(\.dismiss) private var dismiss
    @State private var report: EvidenceReport?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Evidence").font(.title3.weight(.semibold))
                    Text("\(request.from.formatted(date: .omitted, time: .standard)) – \(request.to.formatted(date: .omitted, time: .standard)) · by \(request.metric)")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            if loading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            } else if let r = report {
                content(r)
            } else {
                ContentUnavailableView("No evidence", systemImage: "magnifyingglass",
                                       description: Text("The collector did not return evidence for this range. It may be older than this app, or the range holds no samples."))
                    .frame(minHeight: 200)
            }
        }
        .padding(24)
        .frame(width: 640, height: 560)
        .task { report = await store.evidence(request); loading = false }
    }

    private func content(_ r: EvidenceReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("\(r.window.samples) samples in range · \(r.window.baselineSamples) in the preceding range")
                    .font(.callout).foregroundStyle(.secondary)
                hostPanel(r)
                appsPanel(r)
                if !r.containers.isEmpty { containersPanel(r) }
                anomalyPanel(r)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(r.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    Text("Evidence shows what changed alongside the selection. It does not establish a cause.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func hostPanel(_ r: EvidenceReport) -> some View {
        Panel(title: "Host", subtitle: "Mean and peak in the range, against the preceding range") {
            VStack(spacing: 8) {
                ForEach(["cpu", "memory", "disk", "network"], id: \.self) { m in
                    if let s = r.host[m] {
                        HStack {
                            Text(m.capitalized).frame(width: 90, alignment: .leading)
                            Text(hostValue(s.mean, m)).monospacedDigit()
                            Text("peak \(hostValue(s.peak, m))").foregroundStyle(.secondary).monospacedDigit()
                            Spacer()
                            if let b = r.baselineHost?[m] { Text("before \(hostValue(b.mean, m))").foregroundStyle(.secondary).monospacedDigit() }
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }

    private func appsPanel(_ r: EvidenceReport) -> some View {
        Panel(title: "Applications", subtitle: "Top by \(r.metric)") {
            if r.apps.isEmpty {
                Text(r.metric == "network" ? "No per-process network rates were collected for this range." : "No applications in this range.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(r.apps) { a in
                        HStack(spacing: 10) {
                            Monogram(name: a.name, size: 22)
                            Text(a.name).lineLimit(1)
                            Spacer()
                            if let d = a.delta {
                                Text((d >= 0 ? "+" : "−") + appValue(abs(d), r.metric)).monospacedDigit()
                                    .foregroundStyle(d >= 0 ? .primary : .secondary)
                            }
                            Text(appValue(a.mean, r.metric)).monospacedDigit().foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
                            Text("\(a.present)/\(a.samples)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                                .frame(width: 56, alignment: .trailing).help("Samples the application was seen in")
                        }
                        .padding(.vertical, 6)
                        if a.id != r.apps.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func containersPanel(_ r: EvidenceReport) -> some View {
        Panel(title: "Containers") {
            VStack(spacing: 6) {
                ForEach(r.containers) { c in
                    HStack {
                        Text(c.name ?? "container").lineLimit(1)
                        Spacer()
                        Text("CPU \(Format.percent(c.meanCpu ?? 0)) · peak \(Format.percent(c.peakCpu ?? 0))").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private func anomalyPanel(_ r: EvidenceReport) -> some View {
        Panel(title: "Anomalies", subtitle: r.anomalies.scoredSamples == 0 ? "Not scored: the band needs about five minutes of history first." : nil) {
            if r.anomalies.windows.isEmpty {
                Text(r.anomalies.scoredSamples == 0 ? "No scored samples in this range." : "No anomalous samples in this range.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(r.anomalies.windows.enumerated()), id: \.offset) { _, w in
                        HStack {
                            Text(w.metric.capitalized)
                            Spacer()
                            Text("\(w.samples) sample\(w.samples == 1 ? "" : "s") · peak score \(String(format: "%.1f", w.peak))")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }

    /// Host figures: CPU, memory and disk are percentages, network is bytes per second.
    private func hostValue(_ v: Double?, _ metric: String) -> String {
        guard let v else { return "–" }
        return metric == "network" ? Format.rate(v) : Format.percent(v)
    }

    /// Per-application figures: CPU is a percentage, memory is summed RSS in bytes, network is bytes per second.
    private func appValue(_ v: Double?, _ metric: String) -> String {
        guard let v else { return "–" }
        switch metric {
        case "memory": return Format.bytes(v)
        case "network": return Format.rate(v)
        default: return Format.percent(v)
        }
    }
}

import Charts
import DarkbloomCore
import SwiftUI

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct MenuView: View {
    @ObservedObject var state: AppState
    @State private var contentHeight: CGFloat = 100
    @State private var pickerOpen = false
    @State private var selectedModels: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.horizontal, 12)
            // The MenuBarExtra panel sizes to the view's ideal height, and a
            // bare ScrollView's ideal height is zero — so measure the content
            // and give the scroll region an explicit height, capped at 460.
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    earningsSection
                    thisMacSection
                    fleetSection
                    chartSection
                    if let err = state.remoteError {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(
                    GeometryReader { g in
                        Color.clear.preference(key: ContentHeightKey.self, value: g.size.height)
                    }
                )
            }
            .frame(height: min(contentHeight, 460))
            .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
            Divider().padding(.horizontal, 12)
            footer
        }
        .frame(width: 340)
        // The panel view persists across dismissals; don't leave a stale
        // picker open the next time the dropdown appears.
        .onDisappear { pickerOpen = false }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(nsColor: state.status.color))
                .frame(width: 9, height: 9)
                .shadow(color: Color(nsColor: state.status.color).opacity(0.6), radius: 3)
            Text("Darkbloom")
                .font(.system(size: 13, weight: .semibold))
            Text(state.status.label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            if let d = state.daemon, state.status != .stopped {
                Text("v\(d.version)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Earnings

    private var earningsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Earnings")
            if let e = state.earnings {
                HStack(alignment: .firstTextBaseline) {
                    Text(Fmt.usd(e.availableBalanceMicroUSD))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("balance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 3) {
                    GridRow {
                        stat("Today", Fmt.usd(state.windows.last24hMicroUSD))
                        stat("7 days", Fmt.usd(state.windows.last7dMicroUSD))
                        stat("Lifetime", Fmt.usd(e.totalMicroUSD))
                    }
                    GridRow {
                        stat("Jobs today", "\(state.windows.last24hJobs)")
                        stat("Total jobs", "\(e.count)")
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
            } else {
                Text(state.remoteError ?? "Loading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: This Mac

    @ViewBuilder
    private var thisMacSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("This Mac")
            if let d = state.daemon, state.status != .stopped {
                VStack(alignment: .leading, spacing: 5) {
                    if let model = d.currentModel {
                        row("Serving", model, mono: true)
                    }
                    if let warm = d.warmModels, warm.count > 1 || (warm.count == 1 && warm.first != d.currentModel) {
                        row("Warm", warm.joined(separator: ", "), mono: true)
                    }
                    if let s = d.stats {
                        row("Requests (session)", Fmt.count(s.requestsServed))
                        row("Tokens (session)", Fmt.count(s.tokensGenerated))
                    }
                    if let c = d.capacity {
                        row("GPU memory", String(format: "%.1f / %.0f GB", c.gpuMemoryActiveGb, c.totalMemoryGb))
                    }
                    row("Uptime", Fmt.uptime(d.uptime()))
                    if let t = d.trust {
                        HStack(spacing: 4) {
                            Text("Trust")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 105, alignment: .leading)
                            Image(systemName: t.trustLevel == "hardware" ? "checkmark.shield.fill" : "shield")
                                .font(.system(size: 10))
                                .foregroundStyle(t.trustLevel == "hardware" ? .green : .orange)
                            Text(t.trustLevel)
                                .font(.system(size: 11))
                        }
                    }
                    Text("Session stats reset when the provider restarts.")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            } else {
                Text("Provider is not running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Fleet

    // Only shown when more than this Mac is online — offline machines can't
    // be enumerated from the public API, and a single-Mac account is already
    // fully described by the This Mac section.
    @ViewBuilder
    private var fleetSection: some View {
        if state.fleet.contains(where: { !$0.isThisMac }) {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("My Macs")
                ForEach(state.fleet) { m in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                        Text(m.displayName)
                            .font(.system(size: 12, weight: .medium))
                        if m.isThisMac {
                            Text("this Mac")
                                .font(.system(size: 9))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                        }
                        Spacer()
                        Text(fleetSubtitle(m))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func fleetSubtitle(_ m: FleetMachine) -> String {
        guard let models = m.live.models, !models.isEmpty else { return m.live.status }
        return models.joined(separator: ", ")
    }

    // MARK: Jobs chart

    @ViewBuilder
    private var chartSection: some View {
        if !state.hourlyJobs.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Jobs · Last 24 Hours")
                Chart(state.hourlyJobs) { b in
                    BarMark(
                        x: .value("Hour", b.hour, unit: .hour),
                        y: .value("Jobs", b.jobs),
                        width: .ratio(0.7)
                    )
                    .foregroundStyle(Color.green.gradient)
                    .cornerRadius(1.5)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 6)) {
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel(format: .dateTime.hour())
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel()
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(height: 64)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let err = state.controlError {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.top, 7)
            }
            if pickerOpen {
                modelPicker
            } else {
                footerControls
            }
        }
    }

    // MARK: Model picker (Restart)

    /// Catalog models plus anything currently served that the catalog no
    /// longer lists, so a restart can't silently drop a model.
    private var pickerModels: [CoordinatorAPI.CatalogModel] {
        var models = state.catalog
        let known = Set(models.map(\.id))
        for id in state.currentModels where !known.contains(id) {
            models.append(.init(id: id, displayName: id, minRamGB: nil, sizeGB: nil, active: true))
        }
        return models
    }

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RESTART SERVING")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            if pickerModels.isEmpty {
                Text("Couldn't load the model catalog.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(pickerModels) { model in
                modelRow(model)
            }
            HStack(spacing: 8) {
                Button("Cancel") { pickerOpen = false }
                Spacer()
                Button {
                    pickerOpen = false
                    state.restartServing(models: pickerModels.map(\.id).filter(selectedModels.contains))
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedModels.isEmpty)
            }
            .controlSize(.small)
            .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func modelRow(_ model: CoordinatorAPI.CatalogModel) -> some View {
        let fits = (model.minRamGB ?? 0) <= state.physicalMemoryGB
        let downloaded = state.downloadedModels.contains(model.id)
        Button {
            if selectedModels.contains(model.id) {
                selectedModels.remove(model.id)
            } else {
                selectedModels.insert(model.id)
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: selectedModels.contains(model.id) ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundStyle(selectedModels.contains(model.id) ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.displayName)
                        .font(.system(size: 12, weight: .medium))
                    Text(modelCaption(model, fits: fits, downloaded: downloaded))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !downloaded, fits {
                    Text("will download")
                        .font(.system(size: 9))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!fits)
        .opacity(fits ? 1 : 0.4)
    }

    private func modelCaption(_ model: CoordinatorAPI.CatalogModel, fits: Bool, downloaded: Bool) -> String {
        var parts: [String] = []
        if let size = model.sizeGB { parts.append(String(format: "%.1f GB", size)) }
        if let ram = model.minRamGB {
            parts.append(fits ? String(format: "needs %.0f GB RAM", ram)
                              : String(format: "needs %.0f GB RAM — too big for this Mac", ram))
        }
        if downloaded { parts.append("downloaded") }
        return parts.isEmpty ? model.id : parts.joined(separator: " · ")
    }

    private var footerControls: some View {
        HStack(spacing: 8) {
            if state.status == .stopped {
                Button {
                    state.runControl("start")
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
            } else {
                Button {
                    state.runControl("stop")
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                Button {
                    selectedModels = Set(state.currentModels)
                    pickerOpen = true
                    Task { await state.refreshCatalog() }
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }
            }
            if state.controlBusy {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Menu {
                Link("Open Console", destination: URL(string: "https://console.darkbloom.dev")!)
                Divider()
                Button("Quit") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .controlSize(.small)
        .disabled(state.controlBusy)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: Bits

    private func sectionLabel(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 105, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: mono ? .monospaced : .default))
                .lineLimit(2)
        }
    }
}

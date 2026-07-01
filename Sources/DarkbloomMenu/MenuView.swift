import AppKit
import Charts
import DarkbloomCore
import DarkbloomMenuSupport
import SwiftUI

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct MenuView: View {
    private static let menuWidth: CGFloat = 360
    private static let normalMinimumScrollHeight: CGFloat = 390
    private static let pickerMinimumScrollHeight: CGFloat = 260
    private static let normalMaximumScrollHeight: CGFloat = 660
    private static let pickerMaximumScrollHeight: CGFloat = 360

    @ObservedObject var state: AppState
    @ObservedObject var preferences: MenuPreferencesStore
    @State private var contentHeight: CGFloat = normalMinimumScrollHeight
    @State private var expandedSections: Set<MenuSection> = []
    @State private var pickerOpen = false
    @State private var pickerIntent: ServingPickerIntent = .restart
    @State private var selectedModels: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    StatusHeroView(
                        statusColor: Color(nsColor: state.status.color),
                        statusSymbol: statusSymbol,
                        title: primaryStatusText,
                        subtitle: secondaryStatusText,
                        metrics: heroMetrics,
                        lines: statusLines,
                        hourlyJobs: state.hourlyJobs,
                        activitySubtitle: activitySubtitle,
                        activityChartAccessibilityValue: activityChartAccessibilityValue
                    )

                    ForEach(visibleMenuSections) { section in
                        sectionCard(section)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: minimumScrollHeight, alignment: .topLeading)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                    }
                )
            }
            .scrollContentBackground(.hidden)
            .background(panelFill)
            .frame(height: scrollHeight)
            .onPreferenceChange(ContentHeightKey.self) {
                contentHeight = max($0, minimumScrollHeight)
            }

            footer
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(panelFill)
        }
        .frame(width: Self.menuWidth)
        .background(panelFill)
        .onAppear {
            expandedSections = preferences.snapshot.defaultExpandedSections(from: MenuSection.allCases)
        }
        .onChange(of: preferences.snapshot.sectionPresentations) { _, _ in
            expandedSections = preferences.snapshot.defaultExpandedSections(from: MenuSection.allCases)
        }
        .onDisappear {
            pickerOpen = false
            expandedSections = preferences.snapshot.defaultExpandedSections(from: MenuSection.allCases)
        }
    }

    private var scrollHeight: CGFloat {
        min(max(contentHeight, minimumScrollHeight), maximumScrollHeight)
    }

    private var minimumScrollHeight: CGFloat {
        pickerOpen ? Self.pickerMinimumScrollHeight : Self.normalMinimumScrollHeight
    }

    private var maximumScrollHeight: CGFloat {
        pickerOpen ? Self.pickerMaximumScrollHeight : Self.normalMaximumScrollHeight
    }

    private var panelFill: Material {
        .regularMaterial
    }

    private var panelHeader: some View {
        HStack(spacing: 8) {
            Image(nsImage: StatusIcon.image(for: state.status))
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Darkbloom Monitor")
                    .font(.system(.headline, design: .default, weight: .semibold))
                Text("Provider control")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(headerStatusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(headerStatusColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(panelFill)
    }

    private var headerStatusText: String {
        switch state.status {
        case .serving: return "Online"
        case .running: return "Connecting"
        case .stopped: return "Offline"
        }
    }

    private var headerStatusColor: Color {
        switch state.status {
        case .serving: return .green
        case .running: return .orange
        case .stopped: return .red
        }
    }

    @ViewBuilder
    private func sectionCard(_ section: MenuSection) -> some View {
        switch section {
        case .earnings:
            MonitorSectionCard(
                section: section,
                subtitle: earningsSubtitle,
                isExpanded: expandedSections.contains(section),
                isForcedVisible: forcedVisibleSections.contains(section),
                toggle: { toggle(section) }
            ) {
                earningsDetail
            }
        case .thisMac:
            MonitorSectionCard(
                section: section,
                subtitle: thisMacSubtitle,
                isExpanded: expandedSections.contains(section),
                isForcedVisible: forcedVisibleSections.contains(section),
                toggle: { toggle(section) }
            ) {
                thisMacDetail
            }
        case .health:
            MonitorSectionCard(
                section: section,
                subtitle: healthSummary.text,
                isExpanded: expandedSections.contains(section),
                isForcedVisible: forcedVisibleSections.contains(section),
                toggle: { toggle(section) }
            ) {
                healthDetail
            }
        case .activity:
            MonitorSectionCard(
                section: section,
                subtitle: activitySubtitle,
                isExpanded: expandedSections.contains(section),
                isForcedVisible: forcedVisibleSections.contains(section),
                toggle: { toggle(section) }
            ) {
                jobsChart
            }
        case .fleet:
            MonitorSectionCard(
                section: section,
                subtitle: fleetSubtitle,
                isExpanded: expandedSections.contains(section),
                isForcedVisible: forcedVisibleSections.contains(section),
                toggle: { toggle(section) }
            ) {
                fleetDetail
            }
        }
    }

    private var availableMenuSections: [MenuSection] {
        var sections: [MenuSection] = [.earnings, .thisMac, .health]
        if !state.hourlyJobs.isEmpty {
            sections.append(.activity)
        }
        if state.fleet.contains(where: { !$0.isThisMac }) {
            sections.append(.fleet)
        }
        return sections
    }

    private var visibleMenuSections: [MenuSection] {
        preferences.snapshot.effectiveVisibleSections(
            from: availableMenuSections,
            warningSections: warningSections
        )
    }

    private var forcedVisibleSections: Set<MenuSection> {
        Set(visibleMenuSections.filter { section in
            !preferences.snapshot.isVisible(section) && warningSections.contains(section)
        })
    }

    private var warningSections: Set<MenuSection> {
        healthSummary.kind == .warning ? [.health] : []
    }

    private func toggle(_ section: MenuSection) {
        if expandedSections.contains(section) {
            expandedSections.remove(section)
        } else {
            expandedSections.insert(section)
        }
    }

    private var thisMacLive: CoordinatorAPI.AttestedProvider? {
        state.fleet.first(where: \.isThisMac)?.live
    }

    private var lastAccountJob: Date? {
        state.earnings?.earnings
            .map(\.createdAt)
            .max()
    }

    private var lastThisMacJob: Date? {
        guard let providerID = thisMacLive?.providerID else { return nil }
        return state.earnings?.earnings
            .filter { $0.providerID == providerID }
            .map(\.createdAt)
            .max()
    }

    private var lastRequest: (date: Date, isThisMac: Bool)? {
        if let lastThisMacJob {
            return (lastThisMacJob, true)
        }
        if let lastAccountJob {
            return (lastAccountJob, false)
        }
        return nil
    }

    private var servedModels: [String] {
        state.currentModels.isEmpty ? (thisMacLive?.models ?? []) : state.currentModels
    }

    private var loadedModelCount: Int {
        guard let daemon = state.daemon else { return 0 }
        return servedModels.filter { id in
            id == daemon.currentModel || (daemon.warmModels?.contains(id) ?? false)
        }.count
    }

    private var isEarningNow: Bool {
        guard state.status == .serving else { return false }
        return state.daemon?.inferenceActive == true
    }

    private var heroMetrics: [SummaryMetric] {
        guard state.earnings != nil else {
            return [
                .init(label: "Today", value: "--"),
                .init(label: "7 days", value: "--"),
                .init(label: "Jobs", value: "--")
            ]
        }
        return [
            .init(label: "Today", value: Fmt.usd(state.windows.last24hMicroUSD)),
            .init(label: "7 days", value: Fmt.usd(state.windows.last7dMicroUSD)),
            .init(label: "Jobs", value: "\(state.windows.last24hJobs)")
        ]
    }

    private var primaryStatusText: String {
        switch state.status {
        case .serving:
            return isEarningNow ? "Online - earning" : "Online - waiting"
        case .running:
            return "Connecting"
        case .stopped:
            return "Stopped"
        }
    }

    private var secondaryStatusText: String {
        if let earnings = state.earnings {
            var parts = [
                "Today \(Fmt.usd(state.windows.last24hMicroUSD))",
                "\(state.windows.last24hJobs) jobs"
            ]
            if let lastAccountJob {
                parts.append("account last job \(Fmt.ago(lastAccountJob))")
            } else if earnings.count > 0 {
                parts.append("\(earnings.count) total jobs")
            }
            return parts.joined(separator: " · ")
        }
        return state.remoteError == nil ? "Loading earnings..." : "Coordinator unavailable"
    }

    private var modelSummaryText: String {
        if state.status == .stopped {
            return "Provider not running"
        }
        guard !servedModels.isEmpty else {
            return "No models selected"
        }
        if servedModels.count == 1 {
            if loadedModelCount > 0 {
                return "\(servedModels[0]) loaded"
            }
            return "\(servedModels[0]) on demand"
        }
        if loadedModelCount > 0 {
            return "\(servedModels.count) models · \(loadedModelCount) loaded"
        }
        return "\(servedModels.count) models"
    }

    private var statusLines: [StatusLine] {
        var lines = [
            StatusLine(
                systemImage: "shippingbox",
                text: modelSummaryText,
                tint: state.status == .stopped ? .secondary : .green
            )
        ]
        if let lastRequest {
            lines.append(.init(
                systemImage: "clock.arrow.circlepath",
                text: "\(lastRequest.isThisMac ? "Last request" : "Last account request") \(requestAgoText(lastRequest.date))",
                tint: .secondary
            ))
        }
        lines.append(
            StatusLine(
                systemImage: healthSummary.systemImage,
                text: healthSummary.text,
                tint: healthSummary.tint
            )
        )
        if let remoteError = state.remoteError {
            lines.append(.init(
                systemImage: "exclamationmark.triangle.fill",
                text: remoteError,
                tint: .orange,
                multiline: true
            ))
        }
        if let controlError = state.controlError {
            lines.append(.init(
                systemImage: "xmark.octagon.fill",
                text: controlError,
                tint: .red,
                multiline: true
            ))
        }
        return lines
    }

    private var healthSummary: HealthSummary {
        var warnings: [String] = []
        if let thermal = state.daemon?.system?.thermalState,
           !["nominal", "fair"].contains(thermal.lowercased()) {
            warnings.append("Thermal \(thermal.capitalized)")
        }
        if let pressure = state.daemon?.system?.memoryPressure, pressure > 0.80 {
            warnings.append("Pressure \(percentText(pressure))")
        }
        if let memory = state.hardwareMetrics.memoryUsedFraction, memory > 0.88 {
            warnings.append("Memory \(memoryUtilizationText(memory))")
        }
        if let cpu = state.hardwareMetrics.averageCPUTempC, cpu >= 90 {
            warnings.append("CPU \(temperatureText(cpu))")
        }
        if let gpu = state.hardwareMetrics.averageGPUTempC, gpu >= 90 {
            warnings.append("GPU \(temperatureText(gpu))")
        }
        if let first = warnings.first {
            return .init(
                text: warnings.count > 1 ? "\(first) +\(warnings.count - 1)" : first,
                tint: .orange,
                systemImage: "exclamationmark.triangle.fill",
                kind: .warning
            )
        }
        if state.hardwareMetrics == .empty && state.daemon?.system == nil {
            return .init(
                text: "Health data unavailable",
                tint: .secondary,
                systemImage: "questionmark.circle",
                kind: .neutral
            )
        }
        return .init(text: "Health normal", tint: .green, systemImage: "checkmark.circle.fill", kind: .normal)
    }

    private var statusSymbol: String {
        switch state.status {
        case .serving:
            return isEarningNow ? "bolt.fill" : "checkmark"
        case .running:
            return "arrow.triangle.2.circlepath"
        case .stopped:
            return "stop.fill"
        }
    }

    private var earningsSubtitle: String {
        guard let earnings = state.earnings else {
            return state.remoteError == nil ? "Loading..." : "Unavailable"
        }
        return "Balance \(Fmt.usd(earnings.availableBalanceMicroUSD)) · lifetime \(Fmt.usd(earnings.totalMicroUSD))"
    }

    private var thisMacSubtitle: String {
        guard let daemon = state.daemon, state.status != .stopped else {
            return "Provider is not running"
        }
        return "\(modelSummaryText) · uptime \(Fmt.uptime(daemon.uptime()))"
    }

    private var activitySubtitle: String {
        let jobs = state.hourlyJobs.reduce(0) { $0 + $1.jobs }
        return "\(jobs) \(jobs == 1 ? "request" : "requests") in the last 24 hours"
    }

    private var fleetSubtitle: String {
        let count = state.fleet.count
        return "\(count) online \(count == 1 ? "Mac" : "Macs")"
    }

    private var earningsDetail: some View {
        Group {
            if let earnings = state.earnings {
                MetricGrid(metrics: [
                    .init(label: "Balance", value: Fmt.usd(earnings.availableBalanceMicroUSD)),
                    .init(label: "Withdrawable", value: Fmt.usd(earnings.withdrawableBalanceMicroUSD)),
                    .init(label: "Lifetime", value: Fmt.usd(earnings.totalMicroUSD)),
                    .init(label: "Today", value: Fmt.usd(state.windows.last24hMicroUSD)),
                    .init(label: "7 days", value: Fmt.usd(state.windows.last7dMicroUSD)),
                    .init(label: "Jobs today", value: "\(state.windows.last24hJobs)"),
                    .init(label: "Total jobs", value: "\(earnings.count)")
                ])
            } else {
                EmptyStateLine(text: state.remoteError ?? "Loading earnings...")
            }
        }
    }

    @ViewBuilder
    private var thisMacDetail: some View {
        if let daemon = state.daemon, state.status != .stopped {
            VStack(alignment: .leading, spacing: 10) {
                if let hardware = thisMacLive {
                    HStack(spacing: 6) {
                        Label(
                            "\(hardware.hardwareModel) · \(hardware.memoryGB) GB · \(hardware.gpuCores) GPU",
                            systemImage: "cpu"
                        )
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        Spacer(minLength: 0)
                        TrustBadge(trustLevel: hardware.trustLevel)
                    }
                }

                if !servedModels.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionMicroHeader(title: "Models", trailing: modelSummaryText)
                        LazyVGrid(columns: modelGridColumns, alignment: .leading, spacing: 6) {
                            ForEach(servedModels, id: \.self) { id in
                                ModelPill(
                                    id: id,
                                    loaded: id == daemon.currentModel || (daemon.warmModels?.contains(id) ?? false)
                                )
                            }
                        }
                    }
                }

                VStack(spacing: 5) {
                    if let stats = daemon.stats {
                        InfoRow("Requests", Fmt.count(stats.requestsServed), detail: "session")
                        InfoRow("Tokens", Fmt.count(stats.tokensGenerated), detail: "session")
                    }
                    if let capacity = daemon.capacity {
                        InfoRow("GPU memory", gpuMemoryText(capacity))
                    }
                    if !daemon.version.isEmpty {
                        InfoRow("Provider version", "v\(daemon.version)")
                    }
                    InfoRow("Uptime", Fmt.uptime(daemon.uptime()))
                }

                Text("Session stats reset when the provider restarts.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } else {
            EmptyStateLine(text: "Provider is not running")
        }
    }

    private var healthDetail: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                MetricTile(
                    title: "Memory",
                    systemImage: "memorychip",
                    value: memoryUtilizationText(state.hardwareMetrics.memoryUsedFraction),
                    detail: "used",
                    tint: .blue,
                    fraction: state.hardwareMetrics.memoryUsedFraction
                )
                MetricTile(
                    title: "Fans",
                    systemImage: "fanblades",
                    value: fanSpeedText(state.hardwareMetrics.fanRPMs),
                    detail: fanDetailText(state.hardwareMetrics.fanRPMs),
                    tint: .orange,
                    fraction: fanSpeedFraction(state.hardwareMetrics.fanRPMs)
                )
                TemperatureTile(metrics: state.hardwareMetrics)
            }

            if let system = state.daemon?.system {
                VStack(spacing: 5) {
                    if let thermal = system.thermalState {
                        InfoRow("Thermal", thermal.capitalized)
                    }
                    if let cpu = system.cpuUsage {
                        InfoRow("CPU load", percentText(cpu))
                    }
                    if let pressure = system.memoryPressure {
                        InfoRow("Memory pressure", percentText(pressure))
                    }
                }
            }
            if preferences.snapshot.fanControl.enabled {
                fanControlRow
            }
        }
    }

    private var fanControlRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Fan control")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 98, alignment: .leading)
            Text(fanControlStatusText)
                .font(.caption)
                .lineLimit(2)
            Spacer(minLength: 0)
            if !state.fanHelperInstalled {
                Button {
                    state.installFanHelper()
                } label: {
                    if state.fanHelperInstallBusy {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Text("Install")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(state.fanHelperInstallBusy)
            }
        }
    }

    private var fanControlStatusText: String {
        let settings = preferences.snapshot.fanControl
        guard state.fanHelperInstalled else {
            return "Install helper to enable cooling assist"
        }
        switch state.fanControlStatus {
        case .automatic:
            return "macOS automatic - cooling starts at \(Int(settings.startTemperatureC.rounded()))°"
        case .manual(let percent, let temperatureC):
            return String(format: "Cooling assist %.0f%% at %.0f°", percent * 100, temperatureC)
        case .unavailable(let reason):
            if reason == "install fan helper" {
                return "Install helper to enable cooling assist"
            }
            if reason == "external fan controller active" {
                return "Paused - Macs Fan Control is running"
            }
            if reason == "fan target not confirmed" {
                return "Cooling not confirmed - fan target was overridden"
            }
            return "Unavailable - \(reason)"
        case .failed(let reason):
            return "Failed - \(reason)"
        }
    }

    @ViewBuilder
    private var jobsChart: some View {
        if !state.hourlyJobs.isEmpty {
            HourlyRequestsChart(
                buckets: state.hourlyJobs,
                height: 86,
                accessibilityValue: activityChartAccessibilityValue
            )
        }
    }

    private var fleetDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(state.fleet) { machine in
                HStack(spacing: 8) {
                    Circle()
                        .fill(machine.isThisMac ? Color(nsColor: state.status.color) : .green)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(machine.displayName)
                                .font(.callout.weight(.medium))
                            if machine.isThisMac {
                                Text("this Mac")
                                    .font(.caption2)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                        Text(fleetMachineSubtitle(machine))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var footer: some View {
        Group {
            if pickerOpen {
                modelPicker
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                footerControls
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var pickerModels: [CoordinatorAPI.CatalogModel] {
        var models = state.catalog
        let known = Set(models.map(\.id))
        for id in state.currentModels where !known.contains(id) {
            models.append(.init(id: id, displayName: id, minRamGB: nil, sizeGB: nil, active: true))
        }
        return models
    }

    private var modelPicker: some View {
        ServingModelPickerView(
            intent: pickerIntent,
            models: pickerModels,
            physicalMemoryGB: state.physicalMemoryGB,
            downloadedModels: state.downloadedModels,
            selectedModels: $selectedModels,
            prewarmAfterRestart: prewarmAfterRestartBinding,
            cancel: {
                withAnimation(.easeOut(duration: 0.18)) {
                    pickerOpen = false
                }
            },
            commit: { models, prewarm in
                withAnimation(.easeOut(duration: 0.18)) {
                    pickerOpen = false
                }
                state.startServing(models: models, prewarm: prewarm)
            }
        )
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.86), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        }
    }

    private var prewarmAfterRestartBinding: Binding<Bool> {
        Binding {
            preferences.snapshot.prewarmAfterRestart
        } set: { enabled in
            preferences.setPrewarmAfterRestart(enabled)
        }
    }

    private var footerControls: some View {
        HStack(spacing: 8) {
            if state.status == .stopped {
                Button {
                    openServingPicker(.start)
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(FloatingActionButtonStyle(tint: .green))
                .disabled(state.controlBusy)
            } else {
                Button {
                    state.runControl("stop")
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(FloatingActionButtonStyle())
                .disabled(state.controlBusy)
                Button {
                    openServingPicker(.restart)
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }
                .buttonStyle(FloatingActionButtonStyle())
                .disabled(state.controlBusy)
            }

            if state.controlBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Provider command in progress")
            }

            Spacer()

            if let versionText {
                Text(versionText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Menu {
                Button {
                    openPreferencesWindow()
                } label: {
                    Label("Preferences...", systemImage: "gearshape")
                }
                Divider()
                Link(destination: URL(string: "https://console.darkbloom.dev")!) {
                    Label("Open Console", systemImage: "safari")
                }
                Divider()
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 28, height: 26)
                    .background(
                        Color(nsColor: .controlBackgroundColor).opacity(0.74),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
                    }
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More options")
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .controlSize(.small)
        .frame(maxWidth: .infinity)
    }

    private func openPreferencesWindow() {
        DispatchQueue.main.async {
            PreferencesWindow.show(preferences: preferences, state: state)
        }
    }

    private var versionText: String? {
        guard let version = state.daemon?.version, !version.isEmpty else { return nil }
        return "darkbloom v\(version)"
    }

    private func openServingPicker(_ intent: ServingPickerIntent) {
        state.refreshModelSelection()
        pickerIntent = intent
        let initialSelection = Set(state.currentModels)
        selectedModels = initialSelection
        withAnimation(.easeOut(duration: 0.18)) {
            pickerOpen = true
        }
        Task {
            await state.refreshCatalog()
            if pickerOpen, pickerIntent == intent, selectedModels == initialSelection {
                selectedModels = Set(state.currentModels)
            }
        }
    }

    private var modelGridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 0), spacing: 6),
            GridItem(.flexible(minimum: 0), spacing: 6)
        ]
    }

    private func memoryUtilizationText(_ fraction: Double?) -> String {
        guard let fraction else { return "--" }
        return String(format: "%.0f%%", fraction * 100)
    }

    private func fanSpeedText(_ rpms: [Double]) -> String {
        guard !rpms.isEmpty else { return "--" }
        let rpm = rpms.reduce(0, +) / Double(rpms.count)
        return "\(Int(rpm.rounded())) rpm"
    }

    private func fanDetailText(_ rpms: [Double]) -> String {
        switch rpms.count {
        case 0: return "unavailable"
        case 1: return "1 fan"
        default: return "\(rpms.count) fans avg"
        }
    }

    private func fanSpeedFraction(_ rpms: [Double]) -> Double? {
        guard !rpms.isEmpty else { return nil }
        let rpm = rpms.reduce(0, +) / Double(rpms.count)
        return rpm / 6_000
    }

    private func temperatureText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.0f°", value)
    }

    private func gpuMemoryText(_ capacity: DaemonState.Capacity) -> String {
        if let cache = capacity.gpuMemoryCacheGb {
            return String(
                format: "%.1f active · %.1f cache · %.0f GB",
                capacity.gpuMemoryActiveGb,
                cache,
                capacity.totalMemoryGb
            )
        }
        return String(format: "%.1f / %.0f GB", capacity.gpuMemoryActiveGb, capacity.totalMemoryGb)
    }

    private func percentText(_ value: Double) -> String {
        String(format: "%.0f%%", value <= 1 ? value * 100 : value)
    }

    private func fleetMachineSubtitle(_ machine: FleetMachine) -> String {
        guard let models = machine.live.models, !models.isEmpty else { return machine.live.status }
        return models.joined(separator: ", ")
    }

    private func requestAgoText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var activityChartAccessibilityValue: String {
        let totalJobs = state.hourlyJobs.reduce(0) { $0 + $1.jobs }
        guard let peak = state.hourlyJobs.max(by: { $0.jobs < $1.jobs }) else {
            return "No requests in the last 24 hours."
        }
        return "\(totalJobs) \(totalJobs == 1 ? "request" : "requests") in the last 24 hours. Peak hour had \(peak.jobs) \(peak.jobs == 1 ? "request" : "requests")."
    }
}

private struct SummaryMetric: Identifiable {
    var label: String
    var value: String

    var id: String { label }
}

private struct StatusLine: Identifiable {
    var systemImage: String
    var text: String
    var tint: Color
    var multiline = false

    var id: String { systemImage + text }
}

private struct HealthSummary {
    enum Kind {
        case normal
        case neutral
        case warning
    }

    var text: String
    var tint: Color
    var systemImage: String
    var kind: Kind
}

private struct StatusHeroView: View {
    var statusColor: Color
    var statusSymbol: String
    var title: String
    var subtitle: String
    var metrics: [SummaryMetric]
    var lines: [StatusLine]
    var hourlyJobs: [HourBucket]
    var activitySubtitle: String
    var activityChartAccessibilityValue: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 9) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.16))
                    Image(systemName: statusSymbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(statusColor)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .contentTransition(.numericText())
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 7) {
                ForEach(metrics) { metric in
                    SummaryMetricTile(metric: metric)
                }
            }

            if !hourlyJobs.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text("Requests · last 24 hours")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text(activitySubtitle)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    HourlyRequestsChart(
                        buckets: hourlyJobs,
                        height: 58,
                        accessibilityValue: activityChartAccessibilityValue
                    )
                }
                .padding(.top, 1)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines) { line in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: line.systemImage)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(line.tint)
                            .frame(width: 14)
                        Text(line.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(line.multiline ? 3 : 1)
                            .truncationMode(line.multiline ? .tail : .middle)
                            .help(line.text)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct HourlyRequestsChart: View {
    var buckets: [HourBucket]
    var height: CGFloat
    var accessibilityValue: String

    var body: some View {
        Chart(buckets) { bucket in
            BarMark(
                x: .value("Hour", bucket.hour, unit: .hour),
                y: .value("Requests", bucket.jobs),
                width: .ratio(0.68)
            )
            .foregroundStyle(Color.green.gradient)
            .cornerRadius(1.5)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) {
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel(format: .dateTime.hour())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(height: height)
        .padding(.top, 2)
        .accessibilityLabel("Requests by hour")
        .accessibilityValue(accessibilityValue)
    }
}

private struct SummaryMetricTile: View {
    var metric: SummaryMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metric.value)
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(metric.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.50), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct FloatingActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(isEnabled ? (tint ?? .primary) : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Color(nsColor: .windowBackgroundColor),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
            }
            .shadow(
                color: .black.opacity(isEnabled ? (configuration.isPressed ? 0.10 : 0.20) : 0.06),
                radius: isEnabled ? (configuration.isPressed ? 3 : 8) : 2,
                x: 0,
                y: isEnabled ? (configuration.isPressed ? 1 : 4) : 1
            )
            .opacity(isEnabled ? 1 : 0.58)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct MonitorSectionCard<Content: View>: View {
    var section: MenuSection
    var subtitle: String
    var isExpanded: Bool
    var isForcedVisible: Bool
    var toggle: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Image(systemName: section.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: 17)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(section.title)
                                .font(.caption.weight(.semibold))
                            if isForcedVisible {
                                Text("warning")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.orange.opacity(0.12), in: Capsule())
                            }
                        }
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(subtitle)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(isExpanded ? .degrees(90) : .degrees(0))
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(section.title)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Press to \(isExpanded ? "collapse" : "expand") this section.")

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    content
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .transition(.opacity)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.58), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.16), value: isExpanded)
    }
}

private struct MetricItem: Identifiable {
    var label: String
    var value: String

    var id: String { label }
}

private struct MetricGrid: View {
    var metrics: [MetricItem]

    private let columns = [
        GridItem(.flexible(minimum: 0), spacing: 7),
        GridItem(.flexible(minimum: 0), spacing: 7),
        GridItem(.flexible(minimum: 0), spacing: 7)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 7) {
            ForEach(metrics) { metric in
                SummaryMetricTile(metric: .init(label: metric.label, value: metric.value))
            }
        }
    }
}

private struct SectionMicroHeader: View {
    var title: String
    var trailing: String

    var body: some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(trailing)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }
}

private struct InfoRow: View {
    var label: String
    var value: String
    var detail: String?

    init(_ label: String, _ value: String, detail: String? = nil) {
        self.label = label
        self.value = value
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 98, alignment: .leading)
            Text(value)
                .font(.caption)
                .lineLimit(2)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ModelPill: View {
    var id: String
    var loaded: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(loaded ? Color.green : Color.secondary.opacity(0.45))
                .frame(width: 5, height: 5)
            Text(id)
                .font(.caption2.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            loaded ? Color.green.opacity(0.14) : Color.secondary.opacity(0.09),
            in: RoundedRectangle(cornerRadius: 7)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(loaded ? Color.green.opacity(0.48) : Color.secondary.opacity(0.12), lineWidth: 1)
        }
        .help(loaded ? "\(id) is loaded in GPU memory" : "\(id) is served on demand")
    }
}

private struct TrustBadge: View {
    var trustLevel: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: trustLevel == "hardware" ? "checkmark.shield.fill" : "shield")
                .font(.caption2.weight(.semibold))
            Text(trustLevel)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(trustLevel == "hardware" ? Color.green : Color.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background((trustLevel == "hardware" ? Color.green : Color.orange).opacity(0.12), in: Capsule())
    }
}

private struct MetricTile: View {
    var title: String
    var systemImage: String
    var value: String
    var detail: String
    var tint: Color
    var fraction: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            MetricBar(fraction: fraction, tint: tint)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.56), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct TemperatureTile: View {
    var metrics: HardwareMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "thermometer.medium")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                Text("Temps")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            TemperatureRow("CPU", metrics.averageCPUTempC, tint: .red)
            TemperatureRow("GPU", metrics.averageGPUTempC, tint: .purple)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.56), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct TemperatureRow: View {
    var label: String
    var value: Double?
    var tint: Color

    init(_ label: String, _ value: Double?, tint: Color) {
        self.label = label
        self.value = value
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)
            MetricBar(fraction: value.map { $0 / 100 }, tint: tint)
            Text(value.map { String(format: "%.0f°", $0) } ?? "--")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 30, alignment: .trailing)
        }
    }
}

private struct MetricBar: View {
    var fraction: Double?
    var tint: Color

    var body: some View {
        let clamped = min(max(fraction ?? 0, 0), 1)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(tint.opacity(fraction == nil ? 0 : 0.75))
                    .frame(width: proxy.size.width * clamped)
            }
        }
        .frame(height: 4)
    }
}

private struct EmptyStateLine: View {
    var text: String

    var body: some View {
        Label(text, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

@MainActor
private enum PreferencesWindow {
    private static var window: NSWindow?

    static func show(preferences: MenuPreferencesStore, state: AppState) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = NSHostingController(rootView: SettingsView(preferences: preferences, state: state))
        let newWindow = NSWindow(contentViewController: controller)
        newWindow.title = "Darkbloom Monitor Preferences"
        newWindow.styleMask = [.titled, .closable, .miniaturizable]
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .floating
        newWindow.collectionBehavior = [.moveToActiveSpace]
        newWindow.setContentSize(NSSize(width: 640, height: 520))
        newWindow.center()
        newWindow.setFrameAutosaveName("DarkbloomMonitorPreferences")
        newWindow.makeKeyAndOrderFront(nil)
        newWindow.orderFrontRegardless()
        window = newWindow
        NSApp.activate(ignoringOtherApps: true)
    }
}

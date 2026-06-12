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
                        stat("Today", Fmt.usd(state.last24hMicroUSD))
                        stat("7 days", Fmt.usd(state.last7dMicroUSD))
                        stat("Lifetime", Fmt.usd(e.totalMicroUSD))
                    }
                    GridRow {
                        stat("Jobs today", "\(state.last24hJobs)")
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
                        row("Requests", Fmt.count(s.requestsServed))
                        row("Tokens out", Fmt.count(s.tokensGenerated))
                    }
                    if let c = d.capacity {
                        row("GPU memory", String(format: "%.1f / %.0f GB", c.gpuMemoryActiveGb, c.totalMemoryGb))
                    }
                    row("Uptime", Fmt.uptime(d.uptime))
                    if let t = d.trust {
                        HStack(spacing: 4) {
                            Text("Trust")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .leading)
                            Image(systemName: t.trustLevel == "hardware" ? "checkmark.shield.fill" : "shield")
                                .font(.system(size: 10))
                                .foregroundStyle(t.trustLevel == "hardware" ? .green : .orange)
                            Text(t.trustLevel)
                                .font(.system(size: 11))
                        }
                    }
                }
            } else {
                Text("Provider is not running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Fleet

    @ViewBuilder
    private var fleetSection: some View {
        if state.fleet.count > 1 || state.fleet.contains(where: { !$0.isThisMac }) {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("My Macs")
                ForEach(state.fleet) { m in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(m.live != nil ? Color.green : Color.secondary.opacity(0.4))
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(m.displayName)
                                    .font(.system(size: 12, weight: .medium))
                                if m.isThisMac {
                                    Text("this Mac")
                                        .font(.system(size: 9))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(.quaternary, in: Capsule())
                                }
                            }
                            Text(fleetSubtitle(m))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(Fmt.usd(m.earnedMicroUSD))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func fleetSubtitle(_ m: FleetMachine) -> String {
        if let live = m.live {
            guard let models = live.models, !models.isEmpty else { return live.status }
            return models.joined(separator: ", ")
        }
        if let seen = m.lastSeen { return "offline · last job \(Fmt.ago(seen))" }
        return "offline"
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
            footerControls
        }
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
                    state.runControl("restart")
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
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: mono ? .monospaced : .default))
                .lineLimit(2)
        }
    }
}

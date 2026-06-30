import DarkbloomMenuSupport
import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: MenuPreferencesStore
    @ObservedObject var state: AppState
    @State private var selectedTab: SettingsTab = .menu

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            tabSwitcher

            switch selectedTab {
            case .menu:
                menuLayout
            case .serving:
                serving
            }
        }
        .padding(20)
        .frame(minWidth: 590, idealWidth: 640, minHeight: 460, idealHeight: 500)
    }

    private var tabSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.title)
                        .font(.callout.weight(selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab ? Color.white : Color.primary)
                        .frame(minWidth: 58)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            if selectedTab == tab {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.accentColor)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var menuLayout: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 10) {
                        Picker("Preset", selection: presetBinding) {
                            ForEach(MenuLayoutPreset.selectablePresets) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        if preferences.snapshot.preset == .custom {
                            Text("Custom")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                        }
                    }

                    Label("Warnings are shown even when their section is hidden.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            } label: {
                Label("Layout", systemImage: "slider.horizontal.3")
            }

            GroupBox {
                VStack(spacing: 0) {
                    ForEach(Array(MenuSection.allCases.enumerated()), id: \.element) { index, section in
                        sectionRow(section)
                        if index < MenuSection.allCases.count - 1 {
                            Divider().padding(.leading, 32)
                        }
                    }
                }
            } label: {
                Label("Default sections", systemImage: "sidebar.left")
            }

            HStack {
                Button("Reset defaults") {
                    preferences.resetDefaults()
                }

                Spacer()

                Text(layoutSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var serving: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Pre-warm selected models after start or restart", isOn: prewarmBinding)
                        .toggleStyle(.checkbox)

                    HStack(spacing: 8) {
                        Image(systemName: preferences.snapshot.prewarmAfterRestart ? "bolt.fill" : "moon")
                            .foregroundStyle(preferences.snapshot.prewarmAfterRestart ? Color.green : Color.secondary)
                            .frame(width: 20)
                        Text(preferences.snapshot.prewarmAfterRestart ? "Models will be warmed after control commands." : "Models will load on first use.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            } label: {
                Label("Model startup", systemImage: "shippingbox")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Cooling assist", isOn: fanControlEnabledBinding)
                        .toggleStyle(.checkbox)

                    Picker("Temperature source", selection: fanControlSensorBinding) {
                        ForEach(FanControlSensor.allCases) { sensor in
                            Text(sensor.title).tag(sensor)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!preferences.snapshot.fanControl.enabled)

                    temperatureSlider(
                        "Start",
                        value: fanControlStartBinding,
                        range: 45...95
                    )
                    temperatureSlider(
                        "Full speed",
                        value: fanControlFullSpeedBinding,
                        range: 55...110
                    )

                    Text("Below the start temperature, macOS keeps normal fan control.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()

                    HStack(spacing: 10) {
                        Label(
                            state.fanHelperInstalled ? "Fan helper installed" : "Fan helper required",
                            systemImage: state.fanHelperInstalled ? "checkmark.circle.fill" : "lock"
                        )
                        .font(.caption)
                        .foregroundStyle(state.fanHelperInstalled ? Color.green : Color.secondary)

                        Spacer()

                        if !state.fanHelperInstalled {
                            Button {
                                state.installFanHelper()
                            } label: {
                                if state.fanHelperInstallBusy {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text("Install helper")
                                }
                            }
                            .disabled(state.fanHelperInstallBusy)
                        }
                    }

                    if let error = state.fanHelperInstallError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
            } label: {
                Label("Fans", systemImage: "fanblades")
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func sectionRow(_ section: MenuSection) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: section.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(section.settingsTitle)
                    .font(.callout.weight(.medium))
                Text(section.settingsDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Picker(section.settingsTitle, selection: presentationBinding(for: section)) {
                ForEach(MenuSectionPresentation.allCases) { presentation in
                    Text(presentationLabel(presentation)).tag(presentation)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(minWidth: 190, idealWidth: 220, maxWidth: 240)
        }
        .padding(.vertical, 9)
    }

    private var presetBinding: Binding<MenuLayoutPreset> {
        Binding {
            preferences.snapshot.preset
        } set: { preset in
            preferences.applyPreset(preset)
        }
    }

    private func presentationBinding(for section: MenuSection) -> Binding<MenuSectionPresentation> {
        Binding {
            preferences.snapshot.presentation(for: section)
        } set: { presentation in
            preferences.setPresentation(presentation, for: section)
        }
    }

    private var prewarmBinding: Binding<Bool> {
        Binding {
            preferences.snapshot.prewarmAfterRestart
        } set: { enabled in
            preferences.setPrewarmAfterRestart(enabled)
        }
    }

    private var fanControlEnabledBinding: Binding<Bool> {
        Binding {
            preferences.snapshot.fanControl.enabled
        } set: { enabled in
            var settings = preferences.snapshot.fanControl
            settings.enabled = enabled
            preferences.setFanControl(settings)
        }
    }

    private var fanControlSensorBinding: Binding<FanControlSensor> {
        Binding {
            preferences.snapshot.fanControl.sensor
        } set: { sensor in
            var settings = preferences.snapshot.fanControl
            settings.sensor = sensor
            preferences.setFanControl(settings)
        }
    }

    private var fanControlStartBinding: Binding<Double> {
        Binding {
            preferences.snapshot.fanControl.startTemperatureC
        } set: { value in
            var settings = preferences.snapshot.fanControl
            settings.startTemperatureC = value.rounded()
            if settings.fullSpeedTemperatureC <= settings.startTemperatureC {
                settings.fullSpeedTemperatureC = settings.startTemperatureC + 1
            }
            preferences.setFanControl(settings)
        }
    }

    private var fanControlFullSpeedBinding: Binding<Double> {
        Binding {
            preferences.snapshot.fanControl.fullSpeedTemperatureC
        } set: { value in
            var settings = preferences.snapshot.fanControl
            settings.fullSpeedTemperatureC = max(value.rounded(), settings.startTemperatureC + 1)
            preferences.setFanControl(settings)
        }
    }

    private var layoutSummary: String {
        let expanded = MenuSection.allCases.filter { preferences.snapshot.isExpandedByDefault($0) }.count
        let hidden = MenuSection.allCases.filter { !preferences.snapshot.isVisible($0) }.count
        return "\(expanded) open by default · \(hidden) hidden"
    }

    private func presentationLabel(_ presentation: MenuSectionPresentation) -> String {
        switch presentation {
        case .expanded: return "Open"
        case .collapsed: return "Click"
        case .hidden: return "Hide"
        }
    }

    private func temperatureSlider(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .frame(width: 72, alignment: .leading)
            Slider(value: value, in: range, step: 1)
            Text("\(Int(value.wrappedValue))°")
                .font(.body.monospacedDigit())
                .frame(width: 42, alignment: .trailing)
        }
        .disabled(!preferences.snapshot.fanControl.enabled)
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case menu
    case serving

    var id: Self { self }

    var title: String {
        switch self {
        case .menu: return "Menu"
        case .serving: return "Serving"
        }
    }
}

import DarkbloomMenuSupport
import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: MenuPreferencesStore

    var body: some View {
        TabView {
            menuLayout
                .tabItem {
                    Label("Menu", systemImage: "rectangle.grid.1x2")
                }

            serving
                .tabItem {
                    Label("Serving", systemImage: "shippingbox")
                }
        }
        .padding(20)
        .frame(minWidth: 590, idealWidth: 640, minHeight: 460, idealHeight: 500)
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
}

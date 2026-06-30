import Combine
import Foundation

public enum MenuSection: String, CaseIterable, Codable, Hashable, Identifiable {
    case earnings
    case thisMac
    case health
    case activity
    case fleet

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .earnings: return "Earnings"
        case .thisMac: return "This Mac"
        case .health: return "Health"
        case .activity: return "Activity"
        case .fleet: return "My Macs"
        }
    }

    public var settingsTitle: String {
        switch self {
        case .thisMac: return "Serving"
        default: return title
        }
    }

    public var settingsDescription: String {
        switch self {
        case .earnings:
            return "Balance, recent earnings, lifetime earnings, and job counts."
        case .thisMac:
            return "Current models, trust, GPU memory, session counters, and uptime."
        case .health:
            return "Memory, fans, temperature, thermal state, and pressure."
        case .activity:
            return "Hourly paid jobs chart for the last 24 hours."
        case .fleet:
            return "Other currently connected Macs that belong to this account."
        }
    }

    public var systemImage: String {
        switch self {
        case .earnings: return "dollarsign.circle"
        case .thisMac: return "desktopcomputer"
        case .health: return "waveform.path.ecg"
        case .activity: return "chart.bar"
        case .fleet: return "macbook.and.iphone"
        }
    }
}

public enum MenuSectionPresentation: String, CaseIterable, Codable, Equatable, Identifiable {
    case expanded
    case collapsed
    case hidden

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .expanded: return "Expanded"
        case .collapsed: return "Collapsed"
        case .hidden: return "Hidden"
        }
    }
}

public enum MenuLayoutPreset: String, CaseIterable, Codable, Equatable, Identifiable {
    case balanced
    case earningsFocused
    case operationsFocused
    case compact
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .balanced: return "Balanced"
        case .earningsFocused: return "Earnings focused"
        case .operationsFocused: return "Operations focused"
        case .compact: return "Compact"
        case .custom: return "Custom"
        }
    }

    public static var selectablePresets: [MenuLayoutPreset] {
        [.balanced, .earningsFocused, .operationsFocused, .compact]
    }
}

public enum FanControlSensor: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case hottest
    case cpu
    case gpu

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .hottest: return "CPU or GPU"
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        }
    }
}

public struct FanControlSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var sensor: FanControlSensor
    public var startTemperatureC: Double
    public var fullSpeedTemperatureC: Double

    public init(
        enabled: Bool = false,
        sensor: FanControlSensor = .hottest,
        startTemperatureC: Double = 70,
        fullSpeedTemperatureC: Double = 90
    ) {
        self.enabled = enabled
        self.sensor = sensor
        self.startTemperatureC = startTemperatureC
        self.fullSpeedTemperatureC = max(fullSpeedTemperatureC, startTemperatureC + 1)
    }

    public static let defaultValue = FanControlSettings()
}

public struct MenuPreferencesSnapshot: Equatable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var preset: MenuLayoutPreset
    public var sectionPresentations: [MenuSection: MenuSectionPresentation]
    public var prewarmAfterRestart: Bool
    public var fanControl: FanControlSettings

    public init(
        schemaVersion: Int = Self.schemaVersion,
        preset: MenuLayoutPreset,
        sectionPresentations: [MenuSection: MenuSectionPresentation],
        prewarmAfterRestart: Bool = true,
        fanControl: FanControlSettings = .defaultValue
    ) {
        self.schemaVersion = schemaVersion
        self.preset = preset
        self.sectionPresentations = sectionPresentations
        self.prewarmAfterRestart = prewarmAfterRestart
        self.fanControl = fanControl
    }

    public static var defaultValue: MenuPreferencesSnapshot {
        defaults(for: .balanced)
    }

    public static func defaults(for preset: MenuLayoutPreset) -> MenuPreferencesSnapshot {
        var presentations = Dictionary(
            uniqueKeysWithValues: MenuSection.allCases.map { ($0, MenuSectionPresentation.collapsed) }
        )

        switch preset {
        case .balanced, .custom:
            break
        case .earningsFocused:
            presentations[.earnings] = .expanded
        case .operationsFocused:
            presentations[.thisMac] = .expanded
            presentations[.health] = .expanded
        case .compact:
            presentations[.activity] = .hidden
            presentations[.fleet] = .hidden
        }

        return MenuPreferencesSnapshot(
            preset: preset,
            sectionPresentations: presentations,
            prewarmAfterRestart: true,
            fanControl: .defaultValue
        )
    }

    public func presentation(for section: MenuSection) -> MenuSectionPresentation {
        sectionPresentations[section] ?? .collapsed
    }

    public func isVisible(_ section: MenuSection) -> Bool {
        presentation(for: section) != .hidden
    }

    public func isExpandedByDefault(_ section: MenuSection) -> Bool {
        presentation(for: section) == .expanded
    }

    public func visibleSections(from availableSections: [MenuSection]) -> [MenuSection] {
        availableSections.filter(isVisible)
    }

    public func effectiveVisibleSections(
        from availableSections: [MenuSection],
        warningSections: Set<MenuSection>
    ) -> [MenuSection] {
        availableSections.filter { section in
            isVisible(section) || warningSections.contains(section)
        }
    }

    public func defaultExpandedSections(from availableSections: [MenuSection]) -> Set<MenuSection> {
        Set(availableSections.filter(isExpandedByDefault))
    }

    public mutating func setPresentation(_ presentation: MenuSectionPresentation, for section: MenuSection) {
        sectionPresentations[section] = presentation
        preset = .custom
    }

    public mutating func applyPreset(_ newPreset: MenuLayoutPreset) {
        guard newPreset != .custom else {
            preset = .custom
            return
        }
        let oldPrewarm = prewarmAfterRestart
        let oldFanControl = fanControl
        self = Self.defaults(for: newPreset)
        prewarmAfterRestart = oldPrewarm
        fanControl = oldFanControl
    }

    public static func load(from defaults: UserDefaults) -> MenuPreferencesSnapshot {
        let preset = defaults.string(forKey: MenuPreferenceKey.preset)
            .flatMap(MenuLayoutPreset.init(rawValue:)) ?? .balanced
        var snapshot = Self.defaults(for: preset)
        var loadedPresentations = false

        if let rawPresentations = defaults.dictionary(forKey: MenuPreferenceKey.sectionPresentations) as? [String: String] {
            for (rawSection, rawPresentation) in rawPresentations {
                guard let section = MenuSection(rawValue: rawSection),
                      let presentation = MenuSectionPresentation(rawValue: rawPresentation)
                else { continue }
                snapshot.sectionPresentations[section] = presentation
                loadedPresentations = true
            }
        }

        if defaults.object(forKey: MenuPreferenceKey.prewarmAfterRestart) != nil {
            snapshot.prewarmAfterRestart = defaults.bool(forKey: MenuPreferenceKey.prewarmAfterRestart)
        }
        snapshot.fanControl = FanControlSettings(
            enabled: defaults.object(forKey: MenuPreferenceKey.fanControlEnabled) == nil
                ? FanControlSettings.defaultValue.enabled
                : defaults.bool(forKey: MenuPreferenceKey.fanControlEnabled),
            sensor: defaults.string(forKey: MenuPreferenceKey.fanControlSensor)
                .flatMap(FanControlSensor.init(rawValue:)) ?? FanControlSettings.defaultValue.sensor,
            startTemperatureC: defaults.object(forKey: MenuPreferenceKey.fanControlStartTemperatureC) == nil
                ? FanControlSettings.defaultValue.startTemperatureC
                : defaults.double(forKey: MenuPreferenceKey.fanControlStartTemperatureC),
            fullSpeedTemperatureC: defaults.object(forKey: MenuPreferenceKey.fanControlFullSpeedTemperatureC) == nil
                ? FanControlSettings.defaultValue.fullSpeedTemperatureC
                : defaults.double(forKey: MenuPreferenceKey.fanControlFullSpeedTemperatureC)
        )
        if loadedPresentations,
           preset != .custom,
           snapshot.sectionPresentations != Self.defaults(for: preset).sectionPresentations {
            snapshot.preset = .custom
        }
        snapshot.schemaVersion = Self.schemaVersion

        return snapshot
    }

    public func save(to defaults: UserDefaults) {
        let existingSchemaVersion = defaults.object(forKey: MenuPreferenceKey.schemaVersion) as? Int
        defaults.set(max(schemaVersion, existingSchemaVersion ?? schemaVersion), forKey: MenuPreferenceKey.schemaVersion)
        defaults.set(preset.rawValue, forKey: MenuPreferenceKey.preset)
        defaults.set(prewarmAfterRestart, forKey: MenuPreferenceKey.prewarmAfterRestart)
        defaults.set(fanControl.enabled, forKey: MenuPreferenceKey.fanControlEnabled)
        defaults.set(fanControl.sensor.rawValue, forKey: MenuPreferenceKey.fanControlSensor)
        defaults.set(fanControl.startTemperatureC, forKey: MenuPreferenceKey.fanControlStartTemperatureC)
        defaults.set(fanControl.fullSpeedTemperatureC, forKey: MenuPreferenceKey.fanControlFullSpeedTemperatureC)
        var persisted = defaults.dictionary(forKey: MenuPreferenceKey.sectionPresentations) as? [String: String] ?? [:]
        persisted = persisted.filter { rawSection, rawPresentation in
            MenuSection(rawValue: rawSection) == nil
                || MenuSectionPresentation(rawValue: rawPresentation) == nil
        }
        for (section, presentation) in sectionPresentations {
            persisted[section.rawValue] = presentation.rawValue
        }
        defaults.set(persisted, forKey: MenuPreferenceKey.sectionPresentations)
    }
}

public enum MenuPreferenceKey {
    public static let schemaVersion = "dev.darkbloom.monitor.menu.schemaVersion.v1"
    public static let preset = "dev.darkbloom.monitor.menu.preset.v1"
    public static let sectionPresentations = "dev.darkbloom.monitor.menu.sectionPresentations.v1"
    public static let prewarmAfterRestart = "dev.darkbloom.monitor.serving.prewarmAfterRestart.v1"
    public static let fanControlEnabled = "dev.darkbloom.monitor.fans.enabled.v1"
    public static let fanControlSensor = "dev.darkbloom.monitor.fans.sensor.v1"
    public static let fanControlStartTemperatureC = "dev.darkbloom.monitor.fans.startTemperatureC.v1"
    public static let fanControlFullSpeedTemperatureC = "dev.darkbloom.monitor.fans.fullSpeedTemperatureC.v1"
}

public final class MenuPreferencesStore: ObservableObject {
    @Published public var snapshot: MenuPreferencesSnapshot {
        didSet {
            snapshot.save(to: defaults)
        }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let hasStoredPreferences = Self.hasStoredPreferences(in: defaults)
        snapshot = MenuPreferencesSnapshot.load(from: defaults)
        if !hasStoredPreferences {
            snapshot.save(to: defaults)
        }
    }

    public func setPresentation(_ presentation: MenuSectionPresentation, for section: MenuSection) {
        var updated = snapshot
        updated.setPresentation(presentation, for: section)
        snapshot = updated
    }

    public func applyPreset(_ preset: MenuLayoutPreset) {
        var updated = snapshot
        updated.applyPreset(preset)
        snapshot = updated
    }

    public func setPrewarmAfterRestart(_ enabled: Bool) {
        var updated = snapshot
        updated.prewarmAfterRestart = enabled
        snapshot = updated
    }

    public func setFanControl(_ fanControl: FanControlSettings) {
        var updated = snapshot
        updated.fanControl = fanControl
        snapshot = updated
    }

    public func resetDefaults() {
        snapshot = .defaultValue
    }

    private static func hasStoredPreferences(in defaults: UserDefaults) -> Bool {
        [
            MenuPreferenceKey.schemaVersion,
            MenuPreferenceKey.preset,
            MenuPreferenceKey.sectionPresentations,
            MenuPreferenceKey.prewarmAfterRestart,
            MenuPreferenceKey.fanControlEnabled,
            MenuPreferenceKey.fanControlSensor,
            MenuPreferenceKey.fanControlStartTemperatureC,
            MenuPreferenceKey.fanControlFullSpeedTemperatureC
        ].contains { defaults.object(forKey: $0) != nil }
    }
}

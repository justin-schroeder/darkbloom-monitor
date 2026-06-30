import XCTest
@testable import DarkbloomMenuSupport

final class MenuPreferencesSnapshotTests: XCTestCase {
    func testBalancedDefaultShowsAllSectionsCollapsed() {
        let prefs = MenuPreferencesSnapshot.defaultValue

        XCTAssertEqual(prefs.preset, .balanced)
        XCTAssertTrue(prefs.prewarmAfterRestart)
        XCTAssertFalse(prefs.fanControl.enabled)
        XCTAssertEqual(prefs.fanControl.sensor, .hottest)
        XCTAssertEqual(prefs.fanControl.startTemperatureC, 70)
        XCTAssertEqual(prefs.fanControl.fullSpeedTemperatureC, 90)
        XCTAssertEqual(prefs.visibleSections(from: MenuSection.allCases), MenuSection.allCases)
        XCTAssertEqual(prefs.defaultExpandedSections(from: MenuSection.allCases), [])
    }

    func testPresetsExpandAndHideExpectedSections() {
        let earnings = MenuPreferencesSnapshot.defaults(for: .earningsFocused)
        XCTAssertTrue(earnings.isExpandedByDefault(.earnings))
        XCTAssertTrue(earnings.isVisible(.activity))

        let operations = MenuPreferencesSnapshot.defaults(for: .operationsFocused)
        XCTAssertTrue(operations.isExpandedByDefault(.thisMac))
        XCTAssertTrue(operations.isExpandedByDefault(.health))
        XCTAssertFalse(operations.isExpandedByDefault(.earnings))

        let compact = MenuPreferencesSnapshot.defaults(for: .compact)
        XCTAssertFalse(compact.isVisible(.activity))
        XCTAssertFalse(compact.isVisible(.fleet))
        XCTAssertTrue(compact.isVisible(.earnings))
    }

    func testManualPresentationMarksSnapshotCustom() {
        var prefs = MenuPreferencesSnapshot.defaultValue

        prefs.setPresentation(.expanded, for: .health)
        prefs.setPresentation(.hidden, for: .fleet)

        XCTAssertEqual(prefs.preset, .custom)
        XCTAssertTrue(prefs.isExpandedByDefault(.health))
        XCTAssertFalse(prefs.isVisible(.fleet))
    }

    func testPresetApplicationPreservesNonLayoutPreferences() {
        var prefs = MenuPreferencesSnapshot.defaultValue
        prefs.prewarmAfterRestart = false
        prefs.fanControl = .init(enabled: true, sensor: .gpu, startTemperatureC: 65, fullSpeedTemperatureC: 82)

        prefs.applyPreset(.operationsFocused)

        XCTAssertEqual(prefs.preset, .operationsFocused)
        XCTAssertFalse(prefs.prewarmAfterRestart)
        XCTAssertEqual(prefs.fanControl, .init(enabled: true, sensor: .gpu, startTemperatureC: 65, fullSpeedTemperatureC: 82))
        XCTAssertTrue(prefs.isExpandedByDefault(.thisMac))
    }

    func testCustomPresetApplicationDoesNotResetLayout() {
        var prefs = MenuPreferencesSnapshot.defaultValue
        prefs.setPresentation(.expanded, for: .health)
        prefs.applyPreset(.custom)

        XCTAssertEqual(prefs.preset, .custom)
        XCTAssertTrue(prefs.isExpandedByDefault(.health))
    }

    func testCustomIsNotSelectablePreset() {
        XCTAssertEqual(
            MenuLayoutPreset.selectablePresets,
            [.balanced, .earningsFocused, .operationsFocused, .compact]
        )
    }

    func testEffectiveVisibleSectionsAlwaysPiercesHiddenWarningSections() {
        var prefs = MenuPreferencesSnapshot.defaults(for: .compact)
        prefs.setPresentation(.hidden, for: .health)

        XCTAssertEqual(
            prefs.effectiveVisibleSections(from: MenuSection.allCases, warningSections: [.health]),
            [.earnings, .thisMac, .health]
        )
    }
}

final class MenuPreferencesStoreTests: XCTestCase {
    func testStorePersistsTypedPreferences() {
        let defaults = makeDefaults()
        let store = MenuPreferencesStore(defaults: defaults)

        store.applyPreset(.compact)
        store.setPresentation(.expanded, for: .earnings)
        store.setPrewarmAfterRestart(false)
        store.setFanControl(.init(enabled: true, sensor: .cpu, startTemperatureC: 68, fullSpeedTemperatureC: 88))

        let reloaded = MenuPreferencesStore(defaults: defaults)

        XCTAssertEqual(reloaded.snapshot.preset, .custom)
        XCTAssertTrue(reloaded.snapshot.isExpandedByDefault(.earnings))
        XCTAssertFalse(reloaded.snapshot.isVisible(.activity))
        XCTAssertFalse(reloaded.snapshot.prewarmAfterRestart)
        XCTAssertEqual(reloaded.snapshot.fanControl, .init(enabled: true, sensor: .cpu, startTemperatureC: 68, fullSpeedTemperatureC: 88))
    }

    func testLoadIgnoresUnknownPersistedSectionsAndPresentations() {
        let defaults = makeDefaults()
        defaults.set(MenuLayoutPreset.balanced.rawValue, forKey: MenuPreferenceKey.preset)
        defaults.set(
            [
                "earnings": "expanded",
                "futureSection": "expanded",
                "health": "nonsense"
            ],
            forKey: MenuPreferenceKey.sectionPresentations
        )

        let snapshot = MenuPreferencesSnapshot.load(from: defaults)

        XCTAssertTrue(snapshot.isExpandedByDefault(.earnings))
        XCTAssertEqual(snapshot.presentation(for: .health), .collapsed)
        XCTAssertEqual(snapshot.visibleSections(from: MenuSection.allCases), MenuSection.allCases)
    }

    func testLoadMarksMismatchedPersistedPresetAsCustom() {
        let defaults = makeDefaults()
        defaults.set(MenuLayoutPreset.compact.rawValue, forKey: MenuPreferenceKey.preset)
        defaults.set(
            [
                "activity": "collapsed",
                "fleet": "hidden"
            ],
            forKey: MenuPreferenceKey.sectionPresentations
        )

        let snapshot = MenuPreferencesSnapshot.load(from: defaults)

        XCTAssertEqual(snapshot.preset, .custom)
        XCTAssertTrue(snapshot.isVisible(.activity))
        XCTAssertFalse(snapshot.isVisible(.fleet))
    }

    func testStoreDoesNotOverwriteExistingFuturePreferencesOnInit() {
        let defaults = makeDefaults()
        defaults.set(99, forKey: MenuPreferenceKey.schemaVersion)
        defaults.set(
            [
                "earnings": "expanded",
                "futureSection": "expanded"
            ],
            forKey: MenuPreferenceKey.sectionPresentations
        )

        _ = MenuPreferencesStore(defaults: defaults)

        let persisted = defaults.dictionary(forKey: MenuPreferenceKey.sectionPresentations) as? [String: String]
        XCTAssertEqual(persisted?["futureSection"], "expanded")
        XCTAssertEqual(defaults.integer(forKey: MenuPreferenceKey.schemaVersion), 99)
    }

    func testStoreMutationPreservesFutureSectionPreferences() {
        let defaults = makeDefaults()
        defaults.set(99, forKey: MenuPreferenceKey.schemaVersion)
        defaults.set(
            [
                "earnings": "expanded",
                "futureSection": "expanded"
            ],
            forKey: MenuPreferenceKey.sectionPresentations
        )

        let store = MenuPreferencesStore(defaults: defaults)
        store.setPrewarmAfterRestart(false)

        let persisted = defaults.dictionary(forKey: MenuPreferenceKey.sectionPresentations) as? [String: String]
        XCTAssertEqual(persisted?["futureSection"], "expanded")
        XCTAssertEqual(defaults.integer(forKey: MenuPreferenceKey.schemaVersion), 99)
        XCTAssertFalse(MenuPreferencesStore(defaults: defaults).snapshot.prewarmAfterRestart)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "DarkbloomMenuSupportTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}

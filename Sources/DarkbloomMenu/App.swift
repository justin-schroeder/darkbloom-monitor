import AppKit
import DarkbloomCore
import DarkbloomMenuSupport
import SwiftUI

@main
struct DarkbloomMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state: AppState
    @StateObject private var preferences: MenuPreferencesStore

    init() {
        let prefs = MenuPreferencesStore()
        let s = AppState()
        s.bindPreferences(prefs)
        s.start()
        _state = StateObject(wrappedValue: s)
        _preferences = StateObject(wrappedValue: prefs)
        appDelegate.preferences = prefs
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(state: state, preferences: preferences)
        } label: {
            Image(nsImage: StatusIcon.image(for: state.status))
                .accessibilityLabel("Darkbloom Monitor, \(state.status.label)")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(preferences: preferences, state: state)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var preferences: MenuPreferencesStore?

    func applicationWillTerminate(_ notification: Notification) {
        _ = FanHelper.restoreAutomatic()
    }
}

enum StatusIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(for status: NodeStatus, template: Bool = false) -> NSImage {
        let key = "\(status.label)-\(template ? "template" : "color")"
        if let img = cache[key] { return img }

        let size = NSSize(width: 16, height: 16)
        // flipped: true so the y-down logo coordinates draw upright.
        let img = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.addPath(DarkbloomLogo.path(fitting: rect.insetBy(dx: 1.5, dy: 1.5)))
            ctx.setFillColor(template ? NSColor.labelColor.cgColor : status.color.cgColor)
            ctx.fillPath()
            return true
        }
        img.isTemplate = template
        cache[key] = img
        return img
    }
}

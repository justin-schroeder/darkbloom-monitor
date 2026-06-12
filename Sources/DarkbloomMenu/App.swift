import AppKit
import DarkbloomCore
import SwiftUI

@main
struct DarkbloomMenuApp: App {
    @StateObject private var state: AppState

    init() {
        let s = AppState()
        s.start()
        _state = StateObject(wrappedValue: s)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(state: state)
        } label: {
            // NSImage is rebuilt whenever status changes; non-template so the
            // green/red tint survives the menu bar's template rendering.
            Image(nsImage: StatusIcon.image(for: state.status))
        }
        .menuBarExtraStyle(.window)
    }
}

enum StatusIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(for status: NodeStatus) -> NSImage {
        let key = status.label
        if let img = cache[key] { return img }

        let size = NSSize(width: 16, height: 16)
        // flipped: true so the y-down logo coordinates draw upright.
        let img = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.addPath(DarkbloomLogo.path(fitting: rect.insetBy(dx: 1.5, dy: 1.5)))
            ctx.setFillColor(status.color.cgColor)
            ctx.fillPath()
            return true
        }
        img.isTemplate = false
        cache[key] = img
        return img
    }
}

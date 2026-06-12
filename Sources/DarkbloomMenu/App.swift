import AppKit
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

        let symbol = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "Darkbloom")!
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))!
        let size = NSSize(width: 18, height: 16)
        let img = NSImage(size: size, flipped: false) { rect in
            let tint: NSColor = status.color
            tint.set()
            let symbolRect = NSRect(
                x: (rect.width - symbol.size.width) / 2,
                y: (rect.height - symbol.size.height) / 2,
                width: symbol.size.width,
                height: symbol.size.height)
            symbol.draw(in: symbolRect)
            // Tint by compositing the color through the symbol's alpha.
            NSGraphicsContext.current?.cgContext.setBlendMode(.sourceAtop)
            tint.setFill()
            rect.fill()
            return true
        }
        img.isTemplate = false
        cache[key] = img
        return img
    }
}

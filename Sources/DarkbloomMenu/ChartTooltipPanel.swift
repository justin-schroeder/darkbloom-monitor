import AppKit
import DarkbloomMenuSupport
import SwiftUI

@MainActor
final class ChartTooltipPanelPresenter: ObservableObject {
    private let panel: NSPanel
    private let hostingView: NSHostingView<AnyView>

    init() {
        hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
    }

    func show<Content: View>(at cursor: CGPoint, @ViewBuilder content: () -> Content) {
        hostingView.rootView = AnyView(
            content()
                .frame(width: 126)
                .padding(6)
                .fixedSize(horizontal: true, vertical: true)
        )
        hostingView.layoutSubtreeIfNeeded()

        let size = hostingView.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        hostingView.frame = CGRect(origin: .zero, size: size)
        panel.setContentSize(size)

        let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(
            TooltipPlacement.origin(
                cursor: cursor,
                tooltipSize: size,
                visibleFrame: visibleFrame
            )
        )
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

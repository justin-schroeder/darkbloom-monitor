import AppKit
import DarkbloomMenuSupport
import SwiftUI

struct ChartTooltipRow: Equatable, Identifiable {
    var category: String
    var value: String

    var id: String { category }
}

struct ChartTooltipContent: Equatable {
    var hour: Date
    var headline: String
    var projection: String?
    var rows: [ChartTooltipRow]
}

@MainActor
private final class ChartTooltipModel: ObservableObject {
    @Published var content: ChartTooltipContent?
}

private struct ChartTooltipPanelView: View {
    @ObservedObject var model: ChartTooltipModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let content = model.content {
                VStack(alignment: .leading, spacing: 2) {
                    Text(content.hour, format: .dateTime.weekday(.abbreviated).hour())
                        .foregroundStyle(.secondary)
                    Text(content.headline)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    if let projection = content.projection {
                        Text(projection)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    ForEach(content.rows) { row in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(earningCategoryColor(row.category))
                                .frame(width: 5, height: 5)
                            Text(row.category)
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text(row.value)
                                .monospacedDigit()
                        }
                    }
                }
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(width: 126, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                .padding(6)
            }
        }
        .frame(width: 138, height: 128, alignment: .topLeading)
    }
}

@MainActor
final class ChartTooltipPanelPresenter: ObservableObject {
    private static let panelSize = CGSize(width: 138, height: 128)

    private let model = ChartTooltipModel()
    private var panel: NSPanel?

    private func makePanel() -> NSPanel {
        let hostingView = NSHostingView(rootView: ChartTooltipPanelView(model: model))
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        hostingView.frame = CGRect(origin: .zero, size: Self.panelSize)
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)

        return panel
    }

    func show(
        hour: Date,
        at cursor: CGPoint,
        content: () -> ChartTooltipContent
    ) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if model.content?.hour != hour {
            model.content = content()
        }

        let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(
            TooltipPlacement.origin(
                cursor: cursor,
                tooltipSize: Self.panelSize,
                visibleFrame: visibleFrame
            )
        )
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        model.content = nil
    }

    func release() {
        hide()
        model.content = nil
        panel?.contentView = nil
        panel?.close()
        panel = nil
    }
}

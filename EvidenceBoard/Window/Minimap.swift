import SwiftUI
import BoardKit
import CanvasKit

/// The whole board in miniature, bottom right (DESIGN.md §4.1). It fades in while you pan or
/// zoom and out 1.5 s after you stop, unless the pointer is over it or View ▸ Always Show
/// Minimap is on. Click or drag in it to move the view there.
struct Minimap: View {
    let controller: CanvasController
    let theme: Theme
    let alwaysVisible: Bool

    static let maxSize = CGSize(width: 220, height: 150)
    @State private var isHovered = false

    var body: some View {
        let board = controller.store.board
        if let geometry = MinimapGeometry(cards: board.cards, revision: controller.boardRevision) {
            let visible = alwaysVisible || isHovered || controller.isNavigating
            ZStack(alignment: .topLeading) {
                MinimapCards(geometry: geometry, cards: board.cards, strings: board.strings, theme: theme)
                    .equatable()
                MinimapViewport(geometry: geometry, rect: controller.visibleWorldRect, theme: theme)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let moved = abs(drag.translation.width) + abs(drag.translation.height) > 2
                controller.centerView(on: geometry.world(at: drag.location), animated: !moved)
            })
            .padding(8)
            .glassPanel(cornerRadius: 14)
            .onHover { isHovered = $0 }
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: visible ? 0.15 : 0.4), value: visible)
            .accessibilityElement()
            .accessibilityLabel("Minimap")
            .accessibilityHint("Click to move the view to that part of the board")
        }
    }
}

/// Maps the board's content into the minimap.
struct MinimapGeometry: Equatable {
    let content: CGRect
    let size: CGSize
    let scale: CGFloat
    let revision: Int

    init?(cards: [Card], revision: Int) {
        let boxes = cards.map { CGRect(x: $0.frame.x, y: $0.frame.y, width: $0.frame.width, height: $0.frame.height) }
        guard var content = boxes.first else { return nil }
        for box in boxes.dropFirst() { content = content.union(box) }
        let margin = max(content.width, content.height) * 0.08 + 40
        content = content.insetBy(dx: -margin, dy: -margin)
        let scale = min(Minimap.maxSize.width / content.width, Minimap.maxSize.height / content.height)
        self.content = content
        self.scale = scale
        self.size = CGSize(width: (content.width * scale).rounded(), height: (content.height * scale).rounded())
        self.revision = revision
    }

    func point(_ world: CGPoint) -> CGPoint {
        CGPoint(x: (world.x - content.minX) * scale, y: (world.y - content.minY) * scale)
    }

    func rect(_ world: CGRect) -> CGRect {
        CGRect(origin: point(world.origin), size: CGSize(width: world.width * scale, height: world.height * scale))
    }

    func world(at point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / scale + content.minX, y: point.y / scale + content.minY)
    }
}

/// Cards as small tiles and strings as hairlines. Redrawn only when the board changes.
private struct MinimapCards: View, Equatable {
    let geometry: MinimapGeometry
    let cards: [Card]
    let strings: [BoardString]
    let theme: Theme

    /// The board's revision (in the geometry) stands in for comparing every card.
    nonisolated static func == (a: MinimapCards, b: MinimapCards) -> Bool {
        a.geometry == b.geometry && a.theme.id == b.theme.id
    }

    var body: some View {
        Canvas { context, _ in
            var centers: [UUID: CGPoint] = [:]
            for card in cards {
                let box = geometry.rect(CGRect(x: card.frame.x, y: card.frame.y, width: card.frame.width, height: card.frame.height))
                centers[card.id] = CGPoint(x: box.midX, y: box.minY + min(box.height, 3))
                let fill: Color = if let tint = card.tint, let gradient = theme.canvas.tints[tint] {
                    gradient.from.color
                } else {
                    switch card.content {
                    case .image: theme.textPrimary.color.opacity(0.75)
                    case .web: theme.accentSelect.from.color.opacity(0.8)
                    case .text: theme.textSecondary.color.opacity(0.7)
                    }
                }
                context.fill(Path(roundedRect: box, cornerRadius: min(2, box.width / 4)), with: .color(fill))
            }
            var threads = Path()
            for string in strings {
                guard let from = centers[string.from], let to = centers[string.to] else { continue }
                threads.move(to: from)
                threads.addLine(to: to)
            }
            context.stroke(threads, with: .color(theme.accentString.from.color.opacity(0.75)), lineWidth: 0.75)
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .background(theme.canvas.background.from.color.opacity(0.35))
    }
}

/// The part of the board in view.
private struct MinimapViewport: View {
    let geometry: MinimapGeometry
    let rect: CGRect
    let theme: Theme

    var body: some View {
        let frame = geometry.rect(rect)
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(theme.accentSelect.from.color.opacity(0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(theme.accentSelect.linear(), lineWidth: 1.5)
            }
            .frame(width: max(frame.width, 6), height: max(frame.height, 4))
            .offset(x: frame.minX, y: frame.minY)
            .allowsHitTesting(false)
    }
}

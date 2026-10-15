import AppKit
import BoardKit

/// Finding cards by what they say (DESIGN.md §4.6).
public enum CardSearch {
    /// Everything a card can be found by: its text, a photo's caption, or a link's title, site,
    /// description and address.
    public static func searchableText(of card: Card) -> String {
        switch card.content {
        case .text(let text):
            return text.content
        case .image(let image):
            return image.caption ?? ""
        case .web(let web):
            let snapshot = web.snapshot
            return [snapshot?.title, snapshot?.siteName, snapshot?.pageDescription, web.url.absoluteString]
                .compactMap { $0 }
                .joined(separator: "\n")
        }
    }

    /// The cards that contain every word of `query` (ignoring case and accents), top to
    /// bottom, then left to right. An empty query finds nothing.
    public static func matches(_ query: String, in cards: [Card]) -> [UUID] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        return cards
            .filter { card in
                let text = searchableText(of: card)
                return words.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            }
            .sorted { ($0.frame.y, $0.frame.x) < ($1.frame.y, $1.frame.x) }
            .map(\.id)
    }
}

extension BoardCanvasView {
    /// Finds `query` on the board: matches glow, everything else dims, and the first match
    /// is selected and brought into view.
    func search(_ query: String) {
        let matches = CardSearch.matches(query, in: store.board.cards)
        highlight = .search(query: query, matches: matches, current: matches.isEmpty ? nil : 0)
        refreshHighlight(animated: true)
        if let first = matches.first { showSearchMatch(first) }
        reportSearch()
    }

    /// ↩ or ⌘G (`step` 1), ⇧⌘G (`step` -1): the next or previous match, wrapping around.
    func stepSearch(_ step: Int) {
        guard case .search(let query, let matches, let current) = highlight, !matches.isEmpty else {
            NSSound.beep()
            return
        }
        let index = ((current ?? (step > 0 ? -1 : 0)) + step + matches.count) % matches.count
        highlight = .search(query: query, matches: matches, current: index)
        refreshHighlight(animated: true)
        showSearchMatch(matches[index])
        reportSearch()
    }

    func endSearch() {
        if case .search = highlight {
            highlight = nil
            refreshHighlight(animated: true)
        }
        window?.makeFirstResponder(self)
    }

    /// Selects a match and brings it into view, close enough to read.
    private func showSearchMatch(_ id: UUID) {
        guard let card = store.card(id) else { return }
        select([id])
        let box = CanvasGeometry.boundingBox(of: card)
        let readable: CGFloat = 0.6
        let visible = camera.visibleWorldRect(in: bounds.size).insetBy(dx: 40 / camera.zoom, dy: 40 / camera.zoom)
        guard !visible.contains(box) || camera.zoom < readable else { return }
        animateCamera(to: Camera(center: CGPoint(x: box.midX, y: box.midY), zoom: max(camera.zoom, readable)), anchor: nil)
    }

    private func reportSearch() {
        guard case .search(_, let matches, let current) = highlight else { return }
        controller?.searchDidUpdate(count: matches.count, index: current)
    }
}

import AppKit
import BoardKit

/// The board for VoiceOver and the keyboard (DESIGN.md §14): every card and string is an
/// accessibility element with a spoken label and actions, each card has a Connections rotor,
/// Tab walks the cards in reading order and ⌥ + arrow keys move to the nearest card in that
/// direction.
extension BoardCanvasView {
    // MARK: - The tree

    public override func isAccessibilityElement() -> Bool { true }
    public override func accessibilityRole() -> NSAccessibility.Role? { .layoutArea }
    public override func accessibilityRoleDescription() -> String? { "evidence board" }

    public override func accessibilityLabel() -> String? {
        let cards = store.board.cards.count
        let strings = store.board.strings.count
        return "Board, \(cards == 1 ? "1 card" : "\(cards) cards"), \(strings == 1 ? "1 string" : "\(strings) strings")"
    }

    public override func accessibilityChildren() -> [Any]? {
        let cards = readingOrder().compactMap { accessibilityElement(forCard: $0) }
        let strings = store.board.strings.compactMap { accessibilityElement(forString: $0.id) }
        return cards + strings
    }

    public override func accessibilitySelectedChildren() -> [Any]? {
        selection.compactMap { accessibilityElement(forCard: $0) }
    }

    public override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        onMain { [self] () -> Any? in
            guard let window else { return self }
            let local = convert(window.convertPoint(fromScreen: point), from: nil)
            if let id = card(at: local) { return accessibilityElement(forCard: id) }
            if let id = string(at: local) { return accessibilityElement(forString: id) }
            return self
        }
    }

    func accessibilityElement(forCard id: UUID) -> CardAccessibilityElement? {
        guard store.contains(card: id) else {
            accessibilityCache.cards[id] = nil
            return nil
        }
        if let element = accessibilityCache.cards[id] { return element }
        let element = CardAccessibilityElement(cardID: id, canvas: self)
        accessibilityCache.cards[id] = element
        return element
    }

    func accessibilityElement(forString id: UUID) -> StringAccessibilityElement? {
        guard store.string(id) != nil else {
            accessibilityCache.strings[id] = nil
            return nil
        }
        if let element = accessibilityCache.strings[id] { return element }
        let element = StringAccessibilityElement(stringID: id, canvas: self)
        accessibilityCache.strings[id] = element
        return element
    }

    /// Tells VoiceOver the board changed, after cards or strings come or go.
    func accessibilityBoardDidChange(_ changes: BoardChanges) {
        for id in changes.removedCards { accessibilityCache.cards[id] = nil }
        for id in changes.removedStrings { accessibilityCache.strings[id] = nil }
        guard !changes.insertedCards.isEmpty || !changes.removedCards.isEmpty
            || !changes.insertedStrings.isEmpty || !changes.removedStrings.isEmpty else { return }
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    // MARK: - Words

    /// A card in a few words, for strings and announcements: "Ferry left 11 minutes early".
    func shortName(of card: Card) -> String {
        let name: String
        switch card.content {
        case .text(let text):
            name = Self.plain(text.content).split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        case .image(let image):
            name = image.caption ?? ""
        case .web(let web):
            name = web.snapshot?.title ?? LinkURLText.host(of: web.url)
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return switch card.content {
            case .text: "empty text card"
            case .image: "photo"
            case .web: "link"
            }
        }
        return trimmed.count > 60 ? String(trimmed.prefix(57)) + "…" : trimmed
    }

    /// What VoiceOver says for a card: "Text card: Ferry left 11 minutes early, locked".
    func spokenLabel(of card: Card) -> String {
        var parts: [String]
        switch card.content {
        case .text(let text):
            let body = Self.plain(text.content)
            parts = ["Text card: " + (body.isEmpty ? "empty" : String(body.prefix(400)))]
        case .image(let image):
            parts = [image.caption.map { "Photo: \($0)" } ?? "Photo"]
        case .web(let web):
            let host = LinkURLText.host(of: web.url)
            if let title = web.snapshot?.title, !title.isEmpty {
                parts = ["Web card: \(title), \(host)"]
            } else {
                parts = ["Web card: \(host)" + (previewTasks[card.id] != nil ? ", loading" : "")]
            }
        }
        if let tint = card.tint { parts.append(tint.rawValue) }
        if card.locked { parts.append("locked") }
        let connections = stringsByCard[card.id]?.count ?? 0
        if connections > 0 { parts.append(connections == 1 ? "1 connection" : "\(connections) connections") }
        return parts.joined(separator: ", ")
    }

    /// "String from Ferry left early to Dock camera, labelled same night, dashed".
    func spokenLabel(of string: BoardString) -> String {
        let from = store.card(string.from).map(shortName(of:)) ?? "a card"
        let to = store.card(string.to).map(shortName(of:)) ?? "a card"
        var label = "String from \(from) to \(to)"
        if let text = string.label, !text.isEmpty { label += ", labelled \(text)" }
        switch string.arrow {
        case .forward: label += ", pointing to \(to)"
        case .both: label += ", pointing both ways"
        case .none: break
        }
        switch string.stroke {
        case .dashed: label += ", dashed"
        case .dotted: label += ", dotted"
        case .solid: break
        }
        return label
    }

    /// Text without the Markdown marks.
    static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Keyboard focus

    /// Cards top to bottom, then left to right.
    func readingOrder() -> [UUID] {
        store.board.cards
            .map { (id: $0.id, box: CanvasGeometry.boundingBox(of: $0)) }
            .sorted { ($0.box.minY, $0.box.minX) < ($1.box.minY, $1.box.minX) }
            .map(\.id)
    }

    /// Tab (`step` 1) and ⇧Tab (`step` -1).
    func focusNextCard(_ step: Int) {
        let order = readingOrder()
        guard !order.isEmpty else {
            NSSound.beep()
            return
        }
        let current = selection.count == 1 ? selection.first.flatMap { order.firstIndex(of: $0) } : nil
        let index = current.map { ($0 + step + order.count) % order.count } ?? (step > 0 ? 0 : order.count - 1)
        focusCard(order[index])
    }

    /// ⌥ + arrow: the nearest card whose center lies that way, favoring ones straight ahead.
    func focusCard(toward direction: CGVector) {
        guard let id = selection.first, selection.count == 1, let card = liveCard(id) else {
            focusNextCard(1)
            return
        }
        let origin = CGPoint(x: card.frame.midX, y: card.frame.midY)
        let best = store.board.cards
            .filter { $0.id != id }
            .compactMap { other -> (UUID, CGFloat)? in
                let dx = CGFloat(other.frame.midX) - origin.x
                let dy = CGFloat(other.frame.midY) - origin.y
                let ahead = dx * direction.dx + dy * direction.dy
                let aside = abs(dx * direction.dy - dy * direction.dx)
                guard ahead > 1 else { return nil }
                return (other.id, ahead + aside * 2)
            }
            .min { $0.1 < $1.1 }
        guard let target = best?.0 else {
            NSSound.beep()
            return
        }
        focusCard(target)
    }

    /// Selects a card, brings it into view and moves VoiceOver to it.
    func focusCard(_ id: UUID) {
        guard let card = liveCard(id) else { return }
        select([id])
        reveal(CanvasGeometry.boundingBox(of: card))
        if let element = accessibilityElement(forCard: id) {
            NSAccessibility.post(element: element, notification: .focusedUIElementChanged)
            NSAccessibility.post(
                element: self, notification: .announcementRequested,
                userInfo: [.announcement: spokenLabel(of: card), .priority: NSAccessibilityPriorityLevel.medium.rawValue]
            )
        }
    }

    /// Remembers single-card selections, newest last, so ⌘K can tie the last two together.
    func noteFocus(_ ids: Set<UUID>) {
        guard ids.count == 1, let id = ids.first, focusHistory.last != id else { return }
        focusHistory.removeAll { $0 == id }
        focusHistory.append(id)
        if focusHistory.count > 8 { focusHistory.removeFirst() }
    }

    /// The card focused before the current one, for ⌘K with one card selected.
    var previouslyFocusedCard: UUID? {
        guard selection.count == 1, let current = selection.first else { return nil }
        return focusHistory.last { $0 != current && store.contains(card: $0) }
    }
}

/// AppKit asks accessibility questions on the main thread, but its accessibility methods
/// aren't declared main-actor ones, so the answers hop onto the main actor explicitly.
func onMain<T>(_ body: @MainActor () -> T) -> T {
    MainActor.assumeIsolated { MainResult(value: body()) }.value
}

private struct MainResult<T>: @unchecked Sendable {
    let value: T
}

/// Accessibility elements of the board, kept so VoiceOver's focus survives a refresh.
@MainActor
final class AccessibilityCache {
    var cards: [UUID: CardAccessibilityElement] = [:]
    var strings: [UUID: StringAccessibilityElement] = [:]
}

/// The host of a web address, for speaking: "example.com".
enum LinkURLText {
    static func host(of url: URL) -> String {
        let host = url.host?.lowercased() ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// A card for VoiceOver. Its methods are called on the main thread.
final class CardAccessibilityElement: NSAccessibilityElement, NSAccessibilityElementProtocol, NSAccessibilityCustomRotorItemSearchDelegate, @unchecked Sendable {
    let cardID: UUID
    private weak var canvas: BoardCanvasView?

    @MainActor
    init(cardID: UUID, canvas: BoardCanvasView) {
        self.cardID = cardID
        self.canvas = canvas
        super.init()
        setAccessibilityRole(.group)
        setAccessibilityParent(canvas)
    }

    override func accessibilityLabel() -> String? {
        onMain { [self] in
            guard let canvas, let card = canvas.liveCard(cardID) else { return nil }
            return canvas.spokenLabel(of: card)
        }
    }

    override func accessibilityRoleDescription() -> String? {
        onMain { [self] in
            switch canvas?.liveCard(cardID)?.content {
            case .text: "text card"
            case .image: "photo card"
            case .web: "web card"
            case nil: nil
            }
        }
    }

    override func accessibilityFrame() -> NSRect {
        onMain { [self] in
            guard let canvas, let card = canvas.liveCard(cardID) else { return .zero }
            return canvas.screenRect(ofWorld: CanvasGeometry.boundingBox(of: card))
        }
    }

    override func isAccessibilitySelected() -> Bool {
        onMain { [self] in canvas?.selection.contains(cardID) ?? false }
    }

    override func accessibilityPerformPress() -> Bool {
        onMain { [self] in
            canvas?.focusCard(cardID)
            return canvas != nil
        }
    }

    override func setAccessibilityFocused(_ focused: Bool) {
        super.setAccessibilityFocused(focused)
        guard focused else { return }
        onMain { [self] in
            if let canvas, canvas.selection != [cardID] { canvas.select([cardID]) }
        }
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        onMain { [self] in customActions() }
    }

    @MainActor
    private func customActions() -> [NSAccessibilityCustomAction]? {
        guard let canvas, let card = canvas.liveCard(cardID) else { return nil }
        let id = cardID
        func action(_ name: String, _ body: @escaping @MainActor (BoardCanvasView) -> Void) -> NSAccessibilityCustomAction {
            NSAccessibilityCustomAction(name: name) { [weak canvas] in
                guard let canvas else { return false }
                MainActor.assumeIsolated { body(canvas) }
                return true
            }
        }
        var actions: [NSAccessibilityCustomAction] = []
        switch card.content {
        case .text:
            actions.append(action("Edit") { $0.select([id]); $0.activate(id, at: nil) })
        case .image:
            actions.append(action("Edit Caption") { $0.select([id]); $0.beginCaptionEditing(id) })
        case .web:
            actions.append(action("Open in Browser") { $0.openInBrowser(id) })
            actions.append(action("Peek") { $0.select([id]); $0.peekSelection() })
        }
        if let previous = canvas.focusHistory.last(where: { $0 != id && canvas.store.contains(card: $0) }),
           let other = canvas.store.card(previous) {
            actions.append(action("Connect to \(canvas.shortName(of: other))") { $0.connect(previous, to: id) })
        }
        actions.append(action("Focus on Connections") { $0.select([id]); $0.focusSelection() })
        actions.append(action(card.locked ? "Unlock" : "Lock") { $0.select([id]); $0.toggleLockOnSelection() })
        actions.append(action("Delete") { $0.select([id]); $0.deleteSelection() })
        return actions
    }

    // MARK: Connections rotor

    override func accessibilityCustomRotors() -> [NSAccessibilityCustomRotor] {
        [NSAccessibilityCustomRotor(label: "Connections", itemSearchDelegate: self)]
    }

    /// The strings tied to this card, in file order.
    var connections: [StringAccessibilityElement] {
        onMain { [self] in
            guard let canvas else { return [] }
            return canvas.store.board.strings
                .filter { $0.from == cardID || $0.to == cardID }
                .compactMap { canvas.accessibilityElement(forString: $0.id) }
        }
    }

    func rotor(
        _ rotor: NSAccessibilityCustomRotor, resultFor searchParameters: NSAccessibilityCustomRotor.SearchParameters
    ) -> NSAccessibilityCustomRotor.ItemResult? {
        let items = connections
        guard !items.isEmpty else { return nil }
        let current = (searchParameters.currentItem?.targetElement as? StringAccessibilityElement)
            .flatMap { element in items.firstIndex { $0 === element } }
        let next: Int
        switch searchParameters.searchDirection {
        case .next: next = current.map { $0 + 1 } ?? 0
        case .previous: next = current.map { $0 - 1 } ?? items.count - 1
        @unknown default: return nil
        }
        guard items.indices.contains(next) else { return nil }
        return NSAccessibilityCustomRotor.ItemResult(targetElement: items[next])
    }
}

/// A string for VoiceOver. Its methods are called on the main thread.
final class StringAccessibilityElement: NSAccessibilityElement, NSAccessibilityElementProtocol, @unchecked Sendable {
    let stringID: UUID
    private weak var canvas: BoardCanvasView?

    @MainActor
    init(stringID: UUID, canvas: BoardCanvasView) {
        self.stringID = stringID
        self.canvas = canvas
        super.init()
        setAccessibilityRole(.group)
        setAccessibilityRoleDescription("string")
        setAccessibilityParent(canvas)
    }

    override func accessibilityLabel() -> String? {
        onMain { [self] in
            guard let canvas, let string = canvas.store.string(stringID) else { return nil }
            return canvas.spokenLabel(of: string)
        }
    }

    override func accessibilityFrame() -> NSRect {
        onMain { [self] in
            guard let canvas, let node = canvas.stringNodes[stringID] else { return .zero }
            return canvas.screenRect(ofWorld: node.curve.bounds.insetBy(dx: -4, dy: -4))
        }
    }

    override func accessibilityPerformPress() -> Bool {
        onMain { [self] in
            guard let canvas else { return false }
            canvas.select([], strings: [stringID])
            return true
        }
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        onMain { [self] in customActions() }
    }

    @MainActor
    private func customActions() -> [NSAccessibilityCustomAction]? {
        guard let canvas, let string = canvas.store.string(stringID) else { return nil }
        let id = stringID
        let ends = [string.from, string.to]
        func action(_ name: String, _ body: @escaping @MainActor (BoardCanvasView) -> Void) -> NSAccessibilityCustomAction {
            NSAccessibilityCustomAction(name: name) { [weak canvas] in
                guard let canvas else { return false }
                MainActor.assumeIsolated { body(canvas) }
                return true
            }
        }
        return [
            action("Go to Start Card") { $0.focusCard(ends[0]) },
            action("Go to End Card") { $0.focusCard(ends[1]) },
            action("Edit Label") { $0.beginLabelEditing(id) },
            action("Delete") { $0.select([], strings: [id]); $0.deleteSelection() },
        ]
    }
}

extension BoardCanvasView {
    /// A world-space rectangle on screen, for accessibility frames.
    func screenRect(ofWorld rect: CGRect) -> NSRect {
        guard let window else { return .zero }
        let a = camera.worldToView(CGPoint(x: rect.minX, y: rect.minY), in: bounds.size)
        let b = camera.worldToView(CGPoint(x: rect.maxX, y: rect.maxY), in: bounds.size)
        let local = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        return window.convertToScreen(convert(local, to: nil))
    }

    /// Ties two cards together with a new string, as one undoable step.
    func connect(_ from: UUID, to: UUID) {
        guard from != to, store.contains(card: from), store.contains(card: to) else {
            NSSound.beep()
            return
        }
        commitPendingEdits()
        let string = makeString(from: from, to: to)
        boardEditor.perform(.insertStrings([string]), actionName: "Connect")
        pullTaut(string.id, drawIn: true)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

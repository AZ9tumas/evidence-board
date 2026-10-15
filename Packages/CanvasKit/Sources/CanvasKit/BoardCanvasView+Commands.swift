import AppKit
import UniformTypeIdentifiers
import BoardKit

extension NSPasteboard.PasteboardType {
    static let boardClip = NSPasteboard.PasteboardType(BoardClip.pasteboardType)
}

/// Clipboard, arrange and style commands, the context menu, and Edit menu validation.
extension BoardCanvasView: NSMenuItemValidation {
    // MARK: - Edit menu (reached through the responder chain)

    @IBAction func copy(_ sender: Any?) {
        writeSelectionToPasteboard()
    }

    @IBAction func cut(_ sender: Any?) {
        writeSelectionToPasteboard()
        deleteSelection(actionName: "Cut")
    }

    @IBAction func paste(_ sender: Any?) {
        pasteFromPasteboard()
    }

    @IBAction func delete(_ sender: Any?) {
        deleteSelection()
    }

    @IBAction public override func selectAll(_ sender: Any?) {
        select(Set(store.board.cards.map(\.id)))
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copy(_:)), #selector(cut(_:)):
            !selection.isEmpty
        case #selector(delete(_:)):
            !selection.isEmpty || !selectedStrings.isEmpty
        case #selector(paste(_:)):
            canPaste
        case #selector(selectAll(_:)):
            !store.board.cards.isEmpty
        default:
            true
        }
    }

    // MARK: - Clipboard

    var canPaste: Bool {
        NSPasteboard.general.availableType(from: Self.acceptedPasteboardTypes) != nil
    }

    func writeSelectionToPasteboard() {
        guard !selection.isEmpty else { return }
        let clip = BoardClip(copying: selection, from: store.board)
        let item = NSPasteboardItem()
        if let data = try? BoardCodec.encodeClip(clip) {
            item.setData(data, forType: .boardClip)
        }
        // Plain text too, top to bottom, so the cards paste sensibly into other apps.
        let text = clip.cards
            .sorted { ($0.frame.y, $0.frame.x) < ($1.frame.y, $1.frame.x) }
            .compactMap { card -> String? in
                switch card.content {
                case .text(let text): text.content
                case .web(let web): web.url.absoluteString
                case .image(let image): image.caption
                }
            }
            .joined(separator: "\n\n")
        if !text.isEmpty { item.setString(text, forType: .string) }
        // A single photo also goes on the clipboard as an image, for pasting into other apps.
        if clip.cards.count == 1, case .image(let photo) = clip.cards[0].content,
           let asset = clip.assets[photo.asset], let data = asset.decodedData(),
           let type = UTType(mimeType: asset.mime) {
            item.setData(data, forType: NSPasteboard.PasteboardType(type.identifier))
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
    }

    func pasteFromPasteboard() {
        commitPendingEdits()
        if !ingest(.general, at: pointerWorldLocation() ?? camera.center, actionName: "Paste") {
            NSSound.beep()
        }
    }

    // MARK: - Selection commands

    func deleteSelection(actionName: String = "Delete") {
        var commands: [BoardCommand] = []
        if !selectedStrings.isEmpty { commands.append(.removeStrings(selectedStrings)) }
        if !selection.isEmpty { commands.append(.removeCards(selection)) }
        guard !commands.isEmpty else { return }
        boardEditor.perform(commands.count == 1 ? commands[0] : .batch(commands), actionName: actionName)
    }

    func duplicateSelection() {
        guard !selection.isEmpty else { return }
        let copy = BoardClip(copying: selection, from: store.board).instantiated(dx: 24, dy: 24, baseZ: store.maxZ + 1)
        boardEditor.perform(copy.insertCommand, actionName: "Duplicate")
        select(Set(copy.cards.map(\.id)))
    }

    func nudgeSelection(dx: Double, dy: Double) {
        var frames: [UUID: Rect] = [:]
        for id in selection {
            guard let card = store.card(id), !card.locked else { continue }
            frames[id] = Rect(x: card.frame.x + dx, y: card.frame.y + dy, width: card.frame.width, height: card.frame.height)
        }
        guard !frames.isEmpty else { return }
        boardEditor.perform(.setFrames(frames), actionName: "Nudge")
    }

    /// Moves the selection above (or below) every other card, keeping its own stacking order.
    func reorderSelection(toFront: Bool) {
        let cards = selection.compactMap { store.card($0) }.sorted { $0.z < $1.z }
        guard !cards.isEmpty else { return }
        let base = toFront ? store.maxZ + 1 : store.minZ - cards.count
        let updated = cards.enumerated().map { offset, card in
            var card = card
            card.z = base + offset
            return card
        }
        boardEditor.perform(.updateCards(updated), actionName: toFront ? "Bring to Front" : "Send to Back")
    }

    func toggleLockOnSelection() {
        let cards = selection.compactMap { store.card($0) }
        guard !cards.isEmpty else { return }
        let lock = !cards.allSatisfy(\.locked)
        updateSelectedCards(actionName: lock ? "Lock" : "Unlock") { $0.locked = lock }
    }

    func setStyleOnSelection(_ style: TextCardStyle) {
        updateSelectedCards(actionName: "Change Style") { card in
            guard case .text(var text) = card.content else { return }
            text.style = style
            card.content = .text(text)
        }
    }

    func setTintOnSelection(_ tint: Tint?) {
        updateSelectedCards(actionName: "Change Color") { $0.tint = tint }
    }

    /// Turns automatic height back on, so the card hugs its text again.
    func fitSelectionToText() {
        updateSelectedCards(actionName: "Fit to Text") { card in
            guard case .text(var text) = card.content else { return }
            text.autoHeight = true
            card.content = .text(text)
        }
    }

    /// Applies `change` to every selected card and re-fits text cards whose height is automatic.
    private func updateSelectedCards(actionName: String, _ change: (inout Card) -> Void) {
        let now = Date.now
        let updated = selection.compactMap { id -> Card? in
            guard var card = store.card(id) else { return nil }
            let before = card
            change(&card)
            if case .text(let text) = card.content, text.autoHeight {
                card.frame.height = TextCardTypography.fittingHeight(
                    for: text, width: CGFloat(card.frame.width), appearance: canvasAppearance
                )
            }
            guard card != before else { return nil }
            card.modifiedAt = now
            return card
        }
        guard !updated.isEmpty else { return }
        boardEditor.perform(.updateCards(updated), actionName: actionName)
    }

    func setTheme(_ theme: ThemeID) {
        commitPendingEdits()
        boardEditor.perform(.setTheme(theme), actionName: "Change Theme")
    }

    /// Lays out `count` sample text cards around the view center, for checking performance.
    func addTestCards(count: Int) {
        let sentences = [
            "Ferry left **11 minutes early** on the 3rd.",
            "Who changed the schedule?",
            "Night guard says the gate was *already open*.",
            "Check the harbor logs for `23:41`.",
            "Second boat seen near pier 4, no lights.",
            "Insurance claim filed two days before the storm.",
        ]
        let styles: [TextCardStyle] = [.note, .note, .note, .typewriter, .headline]
        let tints: [Tint?] = [nil, nil, .amber, nil, .azure, nil, .rose, nil, .lime]
        let columns = max(Int(Double(count).squareRoot().rounded(.up)), 1)
        let spacing = CGSize(width: 300, height: 190)
        let origin = CGPoint(
            x: camera.center.x - CGFloat(columns) * spacing.width / 2,
            y: camera.center.y - CGFloat((count + columns - 1) / columns) * spacing.height / 2
        )
        let now = Date.now
        var z = store.maxZ
        let cards = (0..<count).map { index -> Card in
            z += 1
            let style = styles[index % styles.count]
            let text = TextPayload(content: sentences[index % sentences.count], style: style)
            let width = TextCardTypography.defaultWidth
            let height = TextCardTypography.fittingHeight(for: text, width: width, appearance: canvasAppearance)
            return Card(
                frame: Rect(
                    x: origin.x + CGFloat(index % columns) * spacing.width,
                    y: origin.y + CGFloat(index / columns) * spacing.height,
                    width: width, height: height
                ),
                rotation: Double((index * 37) % 7) - 3,
                z: z,
                tint: tints[index % tints.count],
                createdAt: now,
                modifiedAt: now,
                content: .text(text)
            )
        }
        boardEditor.perform(.insertCards(cards), actionName: "Add Test Cards")
    }

    // MARK: - Context menu

    public override func menu(for event: NSEvent) -> NSMenu? {
        commitPendingEdits()
        let point = location(of: event)
        if let stringID = string(at: point) {
            if !selectedStrings.contains(stringID) { select([], strings: [stringID]) }
            return stringMenu()
        }
        let menu = NSMenu()
        guard let id = card(at: point) else {
            let world = camera.viewToWorld(point, in: bounds.size)
            menu.addItem(item("New Text Card Here", #selector(newTextCardFromMenu(_:)), value: NSValue(point: world)))
            menu.addItem(item("Insert Image…", #selector(insertImageFromMenu(_:))))
            menu.addItem(item("Add Link…", #selector(insertLinkFromMenu(_:))))
            menu.addItem(item("Paste", #selector(paste(_:))))
            menu.addItem(.separator())
            menu.addItem(item("Zoom to Fit", #selector(zoomToFitFromMenu(_:))))
            return menu
        }

        if !selection.contains(id) { select([id]) }
        let cards = selection.compactMap { store.card($0) }
        let texts = cards.compactMap { card -> TextPayload? in
            if case .text(let text) = card.content { return text }
            return nil
        }

        let photos = cards.compactMap(\.content.imagePayload)
        if cards.count == 1, texts.count == 1 {
            menu.addItem(item("Edit Text", #selector(editFromMenu(_:))))
            menu.addItem(.separator())
        }
        if cards.count == 1, photos.count == 1 {
            menu.addItem(item("Edit Caption", #selector(captionFromMenu(_:))))
            menu.addItem(item("Reframe Photo", #selector(reframeFromMenu(_:))))
            menu.addItem(.separator())
        }
        let links = cards.filter { $0.kind == .web }.count
        if links > 0 {
            menu.addItem(item(links == 1 ? "Open in Browser" : "Open \(links) Links in Browser", #selector(openLinksFromMenu(_:))))
            if cards.count == 1 { menu.addItem(item("Peek", #selector(peekFromMenu(_:)))) }
            menu.addItem(item(links == 1 ? "Refresh Preview" : "Refresh Previews", #selector(refreshFromMenu(_:))))
            menu.addItem(item(links == 1 ? "Copy Link" : "Copy Links", #selector(copyLinksFromMenu(_:))))
            menu.addItem(.separator())
        }
        if cards.count == 2 {
            menu.addItem(item("Connect", #selector(connectFromMenu(_:))))
            menu.addItem(item("Trace Path", #selector(traceFromMenu(_:))))
        }
        menu.addItem(item(highlight == nil ? "Focus" : "Focus Here", #selector(focusFromMenu(_:))))
        menu.addItem(.separator())
        if !photos.isEmpty {
            let frames = NSMenu()
            for style in ImageFrameStyle.allCases {
                let entry = item(style.title, #selector(frameFromMenu(_:)), value: style.rawValue)
                entry.state = photos.allSatisfy { $0.frameStyle == style } ? .on : .off
                frames.addItem(entry)
            }
            menu.addItem(submenu("Frame", frames))
            if photos.contains(where: { $0.crop != nil }) {
                menu.addItem(item("Reset Framing", #selector(resetFramingFromMenu(_:))))
            }
        }
        if !texts.isEmpty {
            let styles = NSMenu()
            for style in TextCardStyle.allCases {
                let entry = item(style.title, #selector(styleFromMenu(_:)), value: style.rawValue)
                entry.state = texts.allSatisfy { $0.style == style } ? .on : .off
                styles.addItem(entry)
            }
            menu.addItem(submenu("Style", styles))
        }
        let colors = NSMenu()
        let none = item("None", #selector(tintFromMenu(_:)), value: "none")
        none.state = cards.allSatisfy { $0.tint == nil } ? .on : .off
        colors.addItem(none)
        colors.addItem(.separator())
        for tint in Tint.allCases {
            let entry = item(tint.title, #selector(tintFromMenu(_:)), value: tint.rawValue)
            entry.image = swatch(canvasAppearance.gradient(for: tint))
            entry.state = cards.allSatisfy { $0.tint == tint } ? .on : .off
            colors.addItem(entry)
        }
        menu.addItem(submenu("Color", colors))
        if texts.contains(where: { !$0.autoHeight }) {
            menu.addItem(item("Fit Height to Text", #selector(fitFromMenu(_:))))
        }

        menu.addItem(.separator())
        menu.addItem(item(cards.allSatisfy(\.locked) ? "Unlock" : "Lock", #selector(lockFromMenu(_:))))
        menu.addItem(item("Bring to Front", #selector(frontFromMenu(_:))))
        menu.addItem(item("Send to Back", #selector(backFromMenu(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Duplicate", #selector(duplicateFromMenu(_:))))
        menu.addItem(item("Copy", #selector(copy(_:))))
        menu.addItem(item("Delete", #selector(delete(_:))))
        return menu
    }

    func item(_ title: String, _ action: Selector, value: Any? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = value
        return item
    }

    func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    func swatch(_ gradient: GradientPair) -> NSImage {
        let from = gradient.from
        let to = gradient.to
        return NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            NSGradient(starting: from.nsColor, ending: to.nsColor)?
                .draw(in: NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)), angle: -90)
            return true
        }
    }

    @objc private func newTextCardFromMenu(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? NSValue else { return }
        createTextCard(at: value.pointValue)
    }

    @objc private func zoomToFitFromMenu(_ sender: NSMenuItem) { zoomToFit() }
    @objc private func insertImageFromMenu(_ sender: NSMenuItem) { presentImagePicker() }
    @objc private func insertLinkFromMenu(_ sender: NSMenuItem) { presentLinkPrompt() }
    @objc private func openLinksFromMenu(_ sender: NSMenuItem) { openSelectionInBrowser() }
    @objc private func peekFromMenu(_ sender: NSMenuItem) { peekSelection() }
    @objc private func refreshFromMenu(_ sender: NSMenuItem) { refreshPreviews(all: false) }
    @objc private func copyLinksFromMenu(_ sender: NSMenuItem) { copySelectedLinks() }

    @objc private func captionFromMenu(_ sender: NSMenuItem) {
        guard let id = selection.first else { return }
        beginCaptionEditing(id)
    }

    @objc private func reframeFromMenu(_ sender: NSMenuItem) {
        guard let id = selection.first else { return }
        beginFraming(id)
    }

    @objc private func frameFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = ImageFrameStyle(rawValue: raw) else { return }
        setFrameStyleOnSelection(style)
    }

    @objc private func resetFramingFromMenu(_ sender: NSMenuItem) { resetFramingOnSelection() }

    @objc private func editFromMenu(_ sender: NSMenuItem) {
        guard let id = selection.first else { return }
        beginEditing(id, isNewCard: false, selectAll: false)
    }

    @objc private func styleFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = TextCardStyle(rawValue: raw) else { return }
        setStyleOnSelection(style)
    }

    @objc private func tintFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        setTintOnSelection(Tint(rawValue: raw))
    }

    @objc private func fitFromMenu(_ sender: NSMenuItem) { fitSelectionToText() }
    @objc private func lockFromMenu(_ sender: NSMenuItem) { toggleLockOnSelection() }
    @objc private func frontFromMenu(_ sender: NSMenuItem) { reorderSelection(toFront: true) }
    @objc private func backFromMenu(_ sender: NSMenuItem) { reorderSelection(toFront: false) }
    @objc private func duplicateFromMenu(_ sender: NSMenuItem) { duplicateSelection() }
}

extension TextCardStyle {
    var title: String {
        switch self {
        case .note: "Note"
        case .headline: "Headline"
        case .typewriter: "Typewriter"
        }
    }
}

extension ImageFrameStyle {
    var title: String {
        switch self {
        case .polaroid: "Polaroid"
        case .photo: "Photo"
        case .borderless: "Borderless"
        }
    }
}

extension Tint {
    var title: String { rawValue.capitalized }
}

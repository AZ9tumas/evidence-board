import AppKit
import BoardKit
import LinkPreviewKit

/// The images of a fetched preview, turned into board assets off the main thread.
struct WebPreviewAssets: Sendable {
    var image: ImportedImage?
    var icon: ImportedImage?

    /// Hero images are kept up to 1600 px, icons up to 256 px (DESIGN.md §7.6).
    static func make(from preview: LinkPreview) -> WebPreviewAssets {
        WebPreviewAssets(
            image: preview.image.flatMap { try? ImageImporter.importData($0, maxPixelSize: 1600) },
            icon: preview.icon.flatMap { try? ImageImporter.importData($0, maxPixelSize: 256) }
        )
    }

    var all: [AssetID: Asset] {
        var assets: [AssetID: Asset] = [:]
        if let image { assets[image.id] = image.asset }
        if let icon { assets[icon.id] = icon.asset }
        return assets
    }
}

/// Web cards: creating them from links, fetching and refreshing previews, opening and
/// peeking (DESIGN.md §4.4, §7).
extension BoardCanvasView {
    // MARK: - Content and size

    /// What a web card shows right now, including whether its preview is loading.
    func webContent(for card: Card) -> WebCardContent? {
        guard case .web(let payload) = card.content else { return nil }
        return WebCardContent(payload: payload, assets: store.board.assets, isLoading: previewTasks[card.id] != nil)
    }

    /// The layout of a web card at `width` (its own width when `nil`).
    func webLayout(for card: Card, width: CGFloat? = nil) -> WebCardLayout? {
        webContent(for: card).map { WebCardLayout(content: $0, width: width ?? CGFloat(card.frame.width), appearance: canvasAppearance) }
    }

    /// Web cards take the height their layout needs. Boards written elsewhere may have saved
    /// another one; like text cards, fitting it isn't an edit.
    func fitWebCards() {
        let fitted = store.board.cards.compactMap { card -> Card? in
            guard let layout = webLayout(for: card) else { return nil }
            let width = layout.size.width
            guard abs(layout.size.height - CGFloat(card.frame.height)) > 0.5 || abs(width - CGFloat(card.frame.width)) > 0.5 else { return nil }
            var card = card
            card.frame.width = Double(width)
            card.frame.height = Double(layout.size.height)
            return card
        }
        if !fitted.isEmpty { store.apply(.updateCards(fitted)) }
    }

    // MARK: - Creating

    /// Adds a web card for each URL around `world`, then fetches their previews.
    func insertWebCards(_ urls: [URL], at world: CGPoint, actionName: String) {
        let now = Date.now
        var z = store.maxZ
        let width = WebCardLayout.defaultWidth
        let cards = urls.enumerated().map { index, url -> Card in
            z += 1
            let payload = WebPayload(url: url)
            let height = WebCardLayout(
                content: WebCardContent(payload: payload, assets: [:], isLoading: true), width: width, appearance: canvasAppearance
            ).size.height
            return Card(
                frame: Rect(
                    x: world.x - width / 2 + CGFloat(index) * 28, y: world.y - height / 2 + CGFloat(index) * 28,
                    width: width, height: height
                ),
                z: z,
                createdAt: now,
                modifiedAt: now,
                content: .web(payload)
            )
        }
        guard !cards.isEmpty else { return }
        // Mark them loading first, so they appear as skeletons.
        for card in cards { previewTasks[card.id] = Task {} }
        boardEditor.perform(.insertCards(cards), actionName: actionName)
        select(Set(cards.map(\.id)))
        for card in cards { fetchPreview(for: card.id, refresh: false) }
    }

    /// Insert ▸ Link…: asks for an address, offering the one on the clipboard.
    func presentLinkPrompt() {
        guard let window else { return }
        commitPendingEdits()
        let alert = NSAlert()
        alert.messageText = "Add a Link"
        alert.informativeText = "Paste or type a web address. The card shows a preview of the page."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "https://"
        if let clipboard = NSPasteboard.general.string(forType: .string), LinkURL.webURL(from: clipboard) != nil {
            field.stringValue = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        alert.accessoryView = field
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        let target = pointerWorldLocation() ?? camera.center
        Task { [weak self] in
            let response = await alert.beginSheetModal(for: window)
            guard response == .alertFirstButtonReturn, let self else { return }
            guard let url = LinkURL.webURL(from: field.stringValue) else {
                NSSound.beep()
                self.controller?.showNotice("That doesn't look like a web address")
                return
            }
            self.insertWebCards([url], at: target, actionName: "Add Link")
        }
    }

    /// Web addresses on a pasteboard: links dragged from a browser, `.webloc` files, or text
    /// that is exactly one address.
    static func webURLs(on pasteboard: NSPasteboard) -> [URL] {
        let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let weblocs = files.filter { $0.pathExtension.lowercased() == "webloc" }.compactMap(webURL(fromWebloc:))
        if !weblocs.isEmpty { return weblocs }
        if !files.isEmpty { return [] }
        let links = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? [])
            .compactMap { LinkURL.normalize($0) }
        if !links.isEmpty { return links }
        if let text = pasteboard.string(forType: .string), let url = LinkURL.webURL(from: text) {
            return [url]
        }
        return []
    }

    /// The address inside a `.webloc` file (a property list with a `URL` key).
    static func webURL(fromWebloc file: URL) -> URL? {
        guard let data = try? Data(contentsOf: file),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let address = plist["URL"] as? String else { return nil }
        return LinkURL.webURL(from: address)
    }

    // MARK: - Fetching

    /// Fetches the preview for a web card. The first fetch fills in a card that was just
    /// added, as part of adding it; a refresh is its own undoable step.
    func fetchPreview(for id: UUID, refresh: Bool) {
        guard let card = store.card(id), case .web(let payload) = card.content else { return }
        previewTasks[id]?.cancel()
        previewTasks[id] = Task { [weak self] in
            let preview = await LinkPreviewService.shared.preview(for: payload.url, refresh: refresh)
            guard !Task.isCancelled else { return }
            let assets = await Task.detached(priority: .userInitiated) { WebPreviewAssets.make(from: preview) }.value
            guard !Task.isCancelled else { return }
            self?.finishPreview(for: id, with: preview, assets: assets, refresh: refresh)
        }
        if payload.snapshot == nil { refreshWebNode(id) }
    }

    func finishPreview(for id: UUID, with preview: LinkPreview, assets: WebPreviewAssets, refresh: Bool) {
        previewTasks[id] = nil
        guard var card = store.card(id), case .web(var payload) = card.content else { return }
        if preview.variant == .fallback, payload.snapshot != nil {
            // Keep what the card had rather than replacing it with "unavailable".
            refreshWebNode(id)
            controller?.showNotice("Couldn't reach \(LinkURL.displayHost(of: payload.url))")
            return
        }
        payload.snapshot = LinkSnapshot(preview, assets: assets)
        card.content = .web(payload)
        card.modifiedAt = .now
        var withAssets = store.board.assets
        withAssets.merge(assets.all) { current, _ in current }
        let content = WebCardContent(payload: payload, assets: withAssets, isLoading: false)
        card.frame.height = Double(WebCardLayout(content: content, width: CGFloat(card.frame.width), appearance: canvasAppearance).size.height)
        let command = BoardCommand.batch([.addAssets(assets.all), .updateCards([card])])
        cardNodes[id]?.crossFadeContent()
        if refresh {
            boardEditor.perform(command, actionName: "Refresh Preview")
        } else {
            store.apply(command)
            noteDocumentChanged()
        }
    }

    /// Re-applies a web card's content, for loading-state changes the store doesn't see.
    func refreshWebNode(_ id: UUID) {
        guard let node = cardNodes[id], let card = store.card(id) else { return }
        withoutAnimation { node.update(card: card, appearance: canvasAppearance, web: webContent(for: card)) }
        scheduleRenders()
    }

    /// Marks the document edited without an undo step, for previews that arrive after the
    /// card was added.
    func noteDocumentChanged() {
        (window?.windowController?.document as? NSDocument)?.updateChangeCount(.changeDone)
    }

    /// ⌘R on the selection, or every web card on the board.
    func refreshPreviews(all: Bool) {
        let ids = (all ? store.board.cards.map(\.id) : Array(selection)).filter { store.card($0)?.kind == .web }
        guard !ids.isEmpty else {
            NSSound.beep()
            return
        }
        for id in ids { fetchPreview(for: id, refresh: true) }
    }

    // MARK: - Opening

    var selectedWebURLs: [URL] {
        store.board.cards.filter { selection.contains($0.id) }.compactMap { card in
            if case .web(let web) = card.content { return web.url }
            return nil
        }
    }

    func openSelectionInBrowser() {
        let urls = selectedWebURLs
        guard !urls.isEmpty else {
            NSSound.beep()
            return
        }
        for url in urls { NSWorkspace.shared.open(url) }
    }

    func openInBrowser(_ id: UUID) {
        guard let card = store.card(id), case .web(let web) = card.content else { return }
        NSWorkspace.shared.open(web.url)
    }

    /// Space on a selected web card: a live view of the page in a popover (DESIGN.md §7.7).
    func peekSelection() {
        guard selection.count == 1, let id = selection.first, let card = liveCard(id),
              case .web(let web) = card.content else { return }
        let box = CanvasGeometry.boundingBox(of: card)
        let topLeft = camera.worldToView(CGPoint(x: box.minX, y: box.minY), in: bounds.size)
        let bottomRight = camera.worldToView(CGPoint(x: box.maxX, y: box.maxY), in: bounds.size)
        let rect = CGRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
            .intersection(bounds)
        guard !rect.isNull else { return }
        PeekPopover.show(web.url, relativeTo: rect, of: self)
    }

    #if DEBUG
    /// One web card of each layout and one still loading, made from generated pages and laid
    /// out in columns around the view center. For the Debug menu and the snapshot workflow.
    func addTestWebCards() {
        let center = camera.center
        Task { [weak self] in
            let samples = await Task.detached(priority: .userInitiated) { TestLinks.make() }.value
            self?.insertTestWebCards(samples, around: center)
        }
    }

    private func insertTestWebCards(_ samples: [TestLinks.Sample], around center: CGPoint) {
        let width = WebCardLayout.defaultWidth
        let gap: CGFloat = 40
        let columns = 4
        let left = center.x - (CGFloat(columns) * width + CGFloat(columns - 1) * gap) / 2
        var bottoms = [CGFloat](repeating: 0, count: columns)
        var assets = store.board.assets
        var added: [AssetID: Asset] = [:]
        var cards: [Card] = []
        var loading: [UUID] = []
        let now = Date.now
        var z = store.maxZ
        for sample in samples {
            var payload = WebPayload(url: sample.url)
            if let preview = sample.preview {
                payload.snapshot = LinkSnapshot(preview, assets: sample.assets)
                assets.merge(sample.assets.all) { current, _ in current }
                added.merge(sample.assets.all) { current, _ in current }
            }
            let content = WebCardContent(payload: payload, assets: assets, isLoading: sample.preview == nil)
            let height = WebCardLayout(content: content, width: width, appearance: canvasAppearance).size.height
            let column = bottoms.indices.min { bottoms[$0] < bottoms[$1] } ?? 0
            z += 1
            let card = Card(
                frame: Rect(x: left + CGFloat(column) * (width + gap), y: bottoms[column], width: width, height: height),
                z: z, createdAt: now, modifiedAt: now, content: .web(payload)
            )
            bottoms[column] += height + gap
            if sample.preview == nil { loading.append(card.id) }
            cards.append(card)
        }
        // Center the columns vertically on the view.
        let top = center.y - ((bottoms.max() ?? gap) - gap) / 2
        for index in cards.indices { cards[index].frame.y += top }
        for id in loading { previewTasks[id] = Task {} }
        boardEditor.perform(.batch([.addAssets(added), .insertCards(cards)]), actionName: "Add Test Links")
    }
    #endif

    func copySelectedLinks() {
        let urls = selectedWebURLs
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls.map { $0 as NSURL })
        NSPasteboard.general.setString(urls.map(\.absoluteString).joined(separator: "\n"), forType: .string)
    }
}

extension LinkSnapshot {
    /// What a web card saves of a fetched preview: the text, layout and palette, with the
    /// images as references to board assets.
    init(_ preview: LinkPreview, assets: WebPreviewAssets) {
        self.init(
            fetchedAt: preview.fetchedAt.truncatedToSecond,
            variant: preview.variant,
            title: preview.title,
            pageDescription: preview.pageDescription,
            siteName: preview.siteName,
            author: preview.author,
            publishedAt: preview.publishedAt,
            mediaDuration: preview.duration,
            image: assets.image?.id,
            icon: assets.icon?.id,
            palette: preview.palette
        )
    }
}

extension Date {
    var truncatedToSecond: Date {
        Date(timeIntervalSince1970: timeIntervalSince1970.rounded(.down))
    }
}

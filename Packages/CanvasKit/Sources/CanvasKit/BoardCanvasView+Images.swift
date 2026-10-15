import AppKit
import UniformTypeIdentifiers
import BoardKit

/// A photo being reframed: dragging pans the image inside its frame, scrolling or pinching
/// zooms it. Nothing is committed until ↩ or a click elsewhere; Esc puts it back.
struct FramingSession {
    let cardID: UUID
    let original: Card
    /// Normalized, always matching the photo area's aspect ratio.
    var crop: CGRect
}

/// Where an imported image comes from.
enum ImageImportSource: Sendable {
    case file(URL)
    case data(Data)
}

extension BoardCanvasView {
    static let imagePasteboardTypes: [NSPasteboard.PasteboardType] = [
        .png, NSPasteboard.PasteboardType(UTType.jpeg.identifier), NSPasteboard.PasteboardType(UTType.heic.identifier), .tiff, .pdf,
    ]

    /// Everything the canvas accepts from the clipboard or a drag.
    static let acceptedPasteboardTypes: [NSPasteboard.PasteboardType] = [.boardClip, .fileURL] + imagePasteboardTypes + [.string]

    // MARK: - Pasting and dropping

    /// Adds whatever `pasteboard` holds at `world`: copied cards, image files, image data or
    /// plain text, in that order of preference. Returns false if there was nothing usable.
    @discardableResult
    func ingest(_ pasteboard: NSPasteboard, at world: CGPoint, actionName: String) -> Bool {
        if let data = pasteboard.data(forType: .boardClip),
           let clip = try? BoardCodec.decodeClip(data), let bounds = clip.bounds {
            let copy = clip.instantiated(dx: Double(world.x) - bounds.midX, dy: Double(world.y) - bounds.midY, baseZ: store.maxZ + 1)
            boardEditor.perform(copy.insertCommand, actionName: actionName)
            select(Set(copy.cards.map(\.id)))
            return true
        }

        // Finder puts the file's icon on the pasteboard too, so when there are files, use only
        // the files.
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !urls.isEmpty {
            let images = urls.filter(Self.isImageFile)
            guard !images.isEmpty else { return false }
            importImages(images.map { .file($0) }, at: world, actionName: actionName)
            return true
        }

        if let data = Self.imagePasteboardTypes.lazy.compactMap({ pasteboard.data(forType: $0) }).first {
            importImages([.data(data)], at: world, actionName: actionName)
            return true
        }

        if let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            insertTextCard(text, at: world, actionName: actionName)
            return true
        }
        return false
    }

    static func isImageFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .pdf)
    }

    public override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.availableType(from: Self.acceptedPasteboardTypes) == nil ? [] : .copy
    }

    public override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    public override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        commitPendingEdits()
        let point = convert(sender.draggingLocation, from: nil)
        return ingest(sender.draggingPasteboard, at: camera.viewToWorld(point, in: bounds.size), actionName: "Drop")
    }

    // MARK: - Importing

    /// Imports images in the background, then adds them as one undoable step.
    func importImages(_ sources: [ImageImportSource], at world: CGPoint, actionName: String) {
        Task { [weak self] in
            let images = await Task.detached(priority: .userInitiated) {
                sources.compactMap { source -> ImportedImage? in
                    switch source {
                    case .file(let url): try? ImageImporter.importFile(at: url)
                    case .data(let data): try? ImageImporter.importData(data)
                    }
                }
            }.value
            guard let self else { return }
            guard !images.isEmpty else {
                NSSound.beep()
                return
            }
            self.insertImages(images, at: world, actionName: actionName)
        }
    }

    /// Adds polaroids for `images` around `world`: fanned out a little, or in a grid.
    func insertImages(_ images: [ImportedImage], at world: CGPoint, actionName: String, inGrid: Bool = false) {
        let now = Date.now
        var z = store.maxZ
        var assets: [AssetID: Asset] = [:]
        let columns = max(Int(Double(images.count).squareRoot().rounded(.up)), 1)
        let cards = images.enumerated().map { index, image -> Card in
            assets[image.id] = image.asset
            z += 1
            let size = ImageCardLayout.cardSize(for: image.pixelSize, style: .polaroid)
            let origin: CGPoint = if inGrid {
                CGPoint(
                    x: world.x + CGFloat(index % columns - columns / 2) * 340 - size.width / 2,
                    y: world.y + CGFloat(index / columns - columns / 2) * 380 - size.height / 2
                )
            } else {
                CGPoint(x: world.x - size.width / 2 + CGFloat(index) * 28, y: world.y - size.height / 2 + CGFloat(index) * 28)
            }
            return Card(
                frame: Rect(x: origin.x, y: origin.y, width: size.width, height: size.height),
                z: z,
                createdAt: now,
                modifiedAt: now,
                content: .image(ImagePayload(asset: image.id))
            )
        }
        boardEditor.perform(.batch([.addAssets(assets), .insertCards(cards)]), actionName: actionName)
        select(Set(cards.map(\.id)))
    }

    /// Insert ▸ Image…
    func presentImagePicker() {
        guard let window else { return }
        commitPendingEdits()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .pdf]
        panel.allowsMultipleSelection = true
        panel.message = "Choose images to pin to the board."
        let target = camera.center
        Task { [weak self] in
            guard await panel.beginSheetModal(for: window) == .OK else { return }
            let urls = panel.urls
            self?.importImages(urls.map { .file($0) }, at: target, actionName: urls.count == 1 ? "Insert Image" : "Insert Images")
        }
    }

    /// Generated photos for checking memory and speed with many images.
    func addTestPhotos(count: Int) {
        let center = camera.center
        Task { [weak self] in
            let images = await Task.detached(priority: .userInitiated) {
                (0..<count).compactMap { TestPhotos.make(index: $0) }
            }.value
            self?.insertImages(images, at: center, actionName: "Add Test Photos", inGrid: true)
        }
    }

    // MARK: - Activating cards

    /// Double-click or ↩: edit a text card's text; on a photo, edit the caption when the click
    /// is on it (or for ↩), otherwise reframe the photo.
    func activate(_ id: UUID, at world: CGPoint?) {
        guard let card = store.card(id) else { return }
        switch card.content {
        case .text:
            beginEditing(id, isNewCard: false, selectAll: false)
        case .image(let photo):
            let size = CGSize(width: card.frame.width, height: card.frame.height)
            let local = world.map { point -> CGPoint in
                let centered = CanvasGeometry.localPoint(point, in: card)
                return CGPoint(x: centered.x + size.width / 2, y: centered.y + size.height / 2)
            }
            let photoRect = ImageCardLayout.photoRect(for: photo.frameStyle, in: size)
            let onCaption = local.map { point in
                ImageCardLayout.captionIsOverlaid(for: photo.frameStyle)
                    ? point.y > photoRect.maxY - 40
                    : point.y > photoRect.maxY
            } ?? true
            if onCaption {
                beginCaptionEditing(id)
            } else {
                beginFraming(id)
            }
        case .web:
            break
        }
    }

    /// Finishes any open text editor, caption editor or reframing, keeping the changes.
    func commitPendingEdits() {
        finishEditing()
        finishCaptionEditing(commit: true)
        finishLabelEditing(commit: true)
        finishFraming(commit: true)
    }

    // MARK: - Reframing

    func beginFraming(_ id: UUID) {
        commitPendingEdits()
        guard let card = store.card(id), let node = cardNodes[id], let crop = node.visibleCrop, !card.locked else {
            NSSound.beep()
            return
        }
        select([id])
        framing = FramingSession(cardID: id, original: card, crop: crop)
        withoutAnimation {
            node.setFraming(crop)
            updateHandles()
        }
        NSCursor.openHand.set()
        requestImageIfNeeded(id)
    }

    func updateFraming(_ crop: CGRect) {
        guard var session = framing else { return }
        session.crop = ImageCardLayout.clampCrop(crop)
        framing = session
        withoutAnimation { cardNodes[session.cardID]?.setFraming(session.crop) }
        requestImageIfNeeded(session.cardID)
    }

    /// Pans the photo by a drag of (`dx`, `dy`) world points.
    func panFraming(dx: CGFloat, dy: CGFloat) {
        guard let session = framing, let card = store.card(session.cardID), let node = cardNodes[session.cardID] else { return }
        let angle = -CanvasGeometry.radians(card.rotation)
        let localX = dx * cos(angle) - dy * sin(angle)
        let localY = dx * sin(angle) + dy * cos(angle)
        let photo = node.photoFrame.size
        var crop = session.crop
        crop.origin.x -= localX * crop.width / max(photo.width, 1)
        crop.origin.y -= localY * crop.height / max(photo.height, 1)
        updateFraming(crop)
    }

    /// Zooms the photo by `factor` around `world`.
    func zoomFraming(by factor: CGFloat, around world: CGPoint) {
        guard let session = framing, let card = store.card(session.cardID), let node = cardNodes[session.cardID] else { return }
        let photo = node.photoFrame
        let centered = CanvasGeometry.localPoint(world, in: card)
        let local = CGPoint(x: centered.x + CGFloat(card.frame.width) / 2, y: centered.y + CGFloat(card.frame.height) / 2)
        let u = min(max((local.x - photo.minX) / max(photo.width, 1), 0), 1)
        let v = min(max((local.y - photo.minY) / max(photo.height, 1), 0), 1)
        let anchor = CGPoint(x: session.crop.minX + u * session.crop.width, y: session.crop.minY + v * session.crop.height)
        updateFraming(ImageCardLayout.zoomCrop(session.crop, by: factor, around: anchor))
    }

    func isFraming(at point: CGPoint) -> Bool {
        guard let session = framing else { return false }
        return card(at: point) == session.cardID
    }

    func finishFraming(commit: Bool) {
        guard let session = framing else { return }
        framing = nil
        withoutAnimation {
            cardNodes[session.cardID]?.setFraming(nil)
            updateHandles()
        }
        NSCursor.arrow.set()
        guard commit, var card = store.card(session.cardID), case .image(var photo) = card.content else { return }
        let newCrop = Rect(session.crop)
        guard photo.crop != newCrop else { return }
        // A crop that shows exactly what "no crop" showed is stored as no crop.
        if let node = cardNodes[session.cardID], let aspect = node.imageAspect {
            let fitted = ImageCardLayout.visibleCrop(crop: nil, imageAspect: aspect, photoSize: node.photoFrame.size)
            if photo.crop == nil, Self.isClose(fitted, session.crop) { return }
        }
        photo.crop = newCrop
        card.content = .image(photo)
        card.modifiedAt = .now
        boardEditor.perform(.updateCards([card]), actionName: "Reframe Photo")
    }

    private static func isClose(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.001 && abs(a.minY - b.minY) < 0.001
            && abs(a.width - b.width) < 0.001 && abs(a.height - b.height) < 0.001
    }

    // MARK: - Captions

    func beginCaptionEditing(_ id: UUID) {
        commitPendingEdits()
        guard let card = store.card(id), case .image(let photo) = card.content else { return }
        select([id])
        let editor = CaptionEditor(
            card: card, caption: photo.caption ?? "",
            overlaid: ImageCardLayout.captionIsOverlaid(for: photo.frameStyle), appearance: canvasAppearance
        )
        editor.onFinish = { [weak self] commit in self?.finishCaptionEditing(commit: commit) }
        captionEditor = editor
        superview?.addSubview(editor.field, positioned: .above, relativeTo: self)
        withoutAnimation {
            cardNodes[id]?.setEditing(true)
            updateHandles()
        }
        layoutCaptionEditor()
        reveal(CanvasGeometry.boundingBox(of: card))
        editor.focus()
        controller?.editingDidChange(true)
    }

    func layoutCaptionEditor() {
        guard let editor = captionEditor, let card = store.card(editor.cardID), case .image(let photo) = card.content else { return }
        let size = CGSize(width: card.frame.width, height: card.frame.height)
        let caption = ImageCardLayout.captionRect(for: photo.frameStyle, in: size)
        let center = camera.worldToView(CanvasGeometry.worldPoint(
            CGPoint(x: caption.midX - size.width / 2, y: caption.midY - size.height / 2), in: card
        ), in: bounds.size)
        let rect = CGRect(
            x: center.x - caption.width * camera.zoom / 2, y: center.y - caption.height * camera.zoom / 2,
            width: caption.width * camera.zoom, height: caption.height * camera.zoom
        )
        editor.layout(viewRect: convert(rect, to: superview), zoom: camera.zoom)
    }

    func finishCaptionEditing(commit: Bool) {
        guard let editor = captionEditor else { return }
        captionEditor = nil
        editor.onFinish = nil
        let text = editor.text.trimmingCharacters(in: .whitespacesAndNewlines)
        editor.field.removeFromSuperview()
        window?.makeFirstResponder(self)
        withoutAnimation {
            cardNodes[editor.cardID]?.setEditing(false)
            updateHandles()
        }
        controller?.editingDidChange(false)
        guard commit, var card = store.card(editor.cardID), case .image(var photo) = card.content else { return }
        let caption = text.isEmpty ? nil : text
        guard caption != photo.caption else { return }
        photo.caption = caption
        card.content = .image(photo)
        card.modifiedAt = .now
        boardEditor.perform(.updateCards([card]), actionName: "Edit Caption")
    }

    // MARK: - Photo commands

    func setFrameStyleOnSelection(_ style: ImageFrameStyle) {
        updatePhotos(actionName: "Change Frame") { $0.frameStyle = style }
    }

    func resetFramingOnSelection() {
        updatePhotos(actionName: "Reset Framing") { $0.crop = nil }
    }

    private func updatePhotos(actionName: String, _ change: (inout ImagePayload) -> Void) {
        let now = Date.now
        let updated = selection.compactMap { id -> Card? in
            guard var card = store.card(id), case .image(var photo) = card.content else { return nil }
            let before = photo
            change(&photo)
            guard photo != before else { return nil }
            card.content = .image(photo)
            card.modifiedAt = now
            return card
        }
        guard !updated.isEmpty else { return }
        boardEditor.perform(.updateCards(updated), actionName: actionName)
    }
}

/// A one-line caption field laid over a photo's caption area.
@MainActor
final class CaptionEditor: NSObject, NSTextFieldDelegate {
    let cardID: UUID
    let field = NSTextField()
    private let overlaid: Bool
    private let appearance: CanvasAppearance
    private var finished = false
    var onFinish: ((Bool) -> Void)?

    init(card: Card, caption: String, overlaid: Bool, appearance: CanvasAppearance) {
        cardID = card.id
        self.overlaid = overlaid
        self.appearance = appearance
        super.init()
        field.stringValue = caption
        field.placeholderString = "Caption"
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.alignment = overlaid ? .left : .center
        field.delegate = self
    }

    var text: String { field.stringValue }

    func layout(viewRect: CGRect, zoom: CGFloat) {
        let attributes = TextCardTypography.captionAttributes(overlay: overlaid, appearance: appearance, size: 13 * zoom)
        field.font = attributes[.font] as? NSFont
        field.textColor = attributes[.foregroundColor] as? NSColor
        let height = ceil((field.font?.boundingRectForFont.height ?? 16 * zoom))
        field.frame = CGRect(x: viewRect.minX, y: viewRect.midY - height / 2, width: viewRect.width, height: height)
    }

    func focus() {
        field.window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            finish(commit: true)
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            finish(commit: false)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        finish(commit: true)
    }

    private func finish(commit: Bool) {
        guard !finished else { return }
        finished = true
        onFinish?(commit)
    }
}

/// Procedurally drawn "photos" for the debug menu and the snapshot workflow.
enum TestPhotos {
    static func make(index: Int) -> ImportedImage? {
        let width = 1600
        let height = index % 3 == 0 ? 1600 : 1200
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { return nil }
        let hue = CGFloat((index * 47) % 360) / 360
        let sky = NSColor(hue: hue, saturation: 0.55, brightness: 0.35, alpha: 1).cgColor
        let glow = NSColor(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.95, alpha: 1).cgColor
        let ground = NSColor(hue: hue, saturation: 0.4, brightness: 0.12, alpha: 1).cgColor
        if let gradient = CGGradient(colorsSpace: space, colors: [glow, sky] as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
        }
        context.setFillColor(CGColor(gray: 1, alpha: 0.85))
        context.fillEllipse(in: CGRect(x: width / 2 - 90, y: height / 3, width: 180, height: 180))
        context.setFillColor(ground)
        let path = CGMutablePath()
        path.move(to: .zero)
        for step in 0...16 {
            let x = CGFloat(step) * CGFloat(width) / 16
            path.addLine(to: CGPoint(x: x, y: CGFloat(height) * (0.22 + 0.08 * sin(CGFloat(step + index) * 1.3))))
        }
        path.addLine(to: CGPoint(x: width, y: 0))
        path.closeSubpath()
        context.addPath(path)
        context.fillPath()
        guard let image = context.makeImage() else { return nil }
        return try? ImageImporter.encode(image, opaque: true)
    }
}

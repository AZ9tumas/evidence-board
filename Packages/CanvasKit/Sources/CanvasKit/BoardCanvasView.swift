import AppKit
import QuartzCore
import BoardKit

/// The board canvas: a layer-hosting view that draws the world with Core Animation.
///
/// Pan and zoom change a single matrix, `worldLayer.sublayerTransform`, so moving around
/// never re-lays out a card. Text is drawn into bitmaps per zoom tier, only for cards near
/// the viewport, a few per frame. Input, editing and commands live in the extensions.
@MainActor
public final class BoardCanvasView: NSView {
    public var canvasAppearance: CanvasAppearance {
        didSet {
            guard canvasAppearance != oldValue else { return }
            applyAppearance()
        }
    }

    public internal(set) var camera: Camera
    weak var controller: CanvasController?

    let store: BoardStore
    let boardEditor: BoardEditor

    // Layer tree. The root is geometry-flipped so every layer uses a top-left origin.
    let rootLayer = CALayer()
    let backgroundLayer = CAGradientLayer()
    let vignetteLayer = CAGradientLayer()
    let grid = DotGrid()
    let worldLayer = CALayer()
    let cardsLayer = CALayer()
    let stringsLayer = CALayer()
    let rings: SelectionRings
    let overlay = HandleOverlay()

    var cardNodes: [UUID: CardNode] = [:]
    var stringNodes: [UUID: StringNode] = [:]
    var stringsByCard: [UUID: Set<UUID>] = [:]
    var fanOffsets: [UUID: CGFloat] = [:]
    var spatialIndex = SpatialGrid()

    var selection: Set<UUID> = []
    var interaction = Interaction.idle
    var isSpaceHeld = false
    var textEditor: CardTextEditor?
    /// The card being edited, as it looks right now (its height follows the text).
    var editingCard: Card?

    var detailLevel = DetailLevel.full
    /// The zoom tier text bitmaps are drawn for. It follows the zoom once the zoom settles.
    var renderTier: CGFloat
    var tierSettleTask: Task<Void, Never>?
    var visibleIDs: Set<UUID> = []
    lazy var renderQueue = RenderQueue(view: self) { [weak self] id in self?.renderText(of: id) }

    struct CameraAnimation {
        let from: Camera
        let to: Camera
        let anchor: CGPoint?
        let start: CFTimeInterval
        let duration: CFTimeInterval
    }

    var cameraAnimation: CameraAnimation?
    var animationLink: CADisplayLink?
    private var observerToken: UUID?

    init(store: BoardStore, appearance: CanvasAppearance) {
        self.store = store
        self.boardEditor = BoardEditor(store: store)
        self.canvasAppearance = appearance
        self.camera = Camera(viewport: store.viewport)
        self.renderTier = Self.tier(for: Camera(viewport: store.viewport).zoom)
        self.rings = SelectionRings(
            appearance: appearance,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        super.init(frame: .zero)

        // Assigning the layer before turning on wantsLayer makes this a layer-hosting view.
        layer = rootLayer
        wantsLayer = true
        rootLayer.isGeometryFlipped = true
        rootLayer.masksToBounds = true

        backgroundLayer.startPoint = CGPoint(x: 0, y: 0)
        backgroundLayer.endPoint = CGPoint(x: 1, y: 1)
        vignetteLayer.type = .radial
        vignetteLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        vignetteLayer.endPoint = CGPoint(x: 1.2, y: 1.2)
        vignetteLayer.locations = [0, 0.55, 1]

        worldLayer.anchorPoint = .zero
        worldLayer.addSublayer(cardsLayer)
        worldLayer.addSublayer(stringsLayer)
        worldLayer.addSublayer(rings.layer)

        rootLayer.addSublayer(backgroundLayer)
        rootLayer.addSublayer(vignetteLayer)
        rootLayer.addSublayer(grid.layer)
        rootLayer.addSublayer(worldLayer)
        rootLayer.addSublayer(overlay.layer)

        detailLevel = DetailLevel(zoom: camera.zoom)
        applyAppearance()
        observerToken = store.addObserver { [weak self] changes in self?.storeDidChange(changes) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("BoardCanvasView is created in code")
    }

    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }
    public override var isOpaque: Bool { true }

    // MARK: - Layout

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutLayers()
    }

    public override func layout() {
        super.layout()
        layoutLayers()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        updateContentsScale()
        Task { @MainActor [weak self] in
            guard let self, let window = self.window, window.firstResponder === window else { return }
            window.makeFirstResponder(self)
        }
    }

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            stopCameraAnimation()
            renderQueue.stop()
            tierSettleTask?.cancel()
        }
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
        for node in cardNodes.values { node.discardRenderedText() }
        updateVisibility()
    }

    var backingScale: CGFloat { window?.backingScaleFactor ?? 2 }

    private func updateContentsScale() {
        let scale = backingScale
        withoutAnimation {
            for item: CALayer in [rootLayer, backgroundLayer, vignetteLayer, worldLayer, overlay.layer] {
                item.contentsScale = scale
            }
            grid.setContentsScale(scale)
            for node in cardNodes.values { node.setContentsScale(scale) }
            for node in stringNodes.values { node.setContentsScale(scale) }
        }
    }

    private func layoutLayers() {
        withoutAnimation {
            backgroundLayer.frame = bounds
            vignetteLayer.frame = bounds
            overlay.layer.frame = bounds
            worldLayer.bounds = CGRect(origin: .zero, size: bounds.size)
            worldLayer.position = .zero
        }
        applyCamera()
    }

    // MARK: - Appearance

    private func applyAppearance() {
        withoutAnimation {
            backgroundLayer.colors = canvasAppearance.background.cgColors
            vignetteLayer.colors = [RGBA.clear.cgColor, RGBA.clear.cgColor, canvasAppearance.vignette.cgColor]
            grid.setColor(canvasAppearance.gridDot)
            overlay.setAppearance(canvasAppearance)
        }
        rebuildContent()
    }

    /// Recreates every card and string layer. Used on load and when the theme changes;
    /// edits go through ``storeDidChange(_:)`` instead.
    private func rebuildContent() {
        withoutAnimation {
            cardsLayer.sublayers = nil
            stringsLayer.sublayers = nil
            cardNodes = [:]
            stringNodes = [:]
            stringsByCard = [:]
            spatialIndex = SpatialGrid()
            for card in store.board.cards { addCardNode(card) }
            fanOffsets = CanvasGeometry.fanOffsets(for: store.board.strings)
            for string in store.board.strings { addStringNode(string) }
        }
        visibleIDs = []
        selectionDidChange()
        updateVisibility()
    }

    // MARK: - Nodes

    func addCardNode(_ card: Card) {
        let node = CardNode(card: card, appearance: canvasAppearance, scale: backingScale)
        node.setDetail(detailLevel)
        cardNodes[card.id] = node
        cardsLayer.addSublayer(node.root)
        spatialIndex.insert(card.id, rect: CanvasGeometry.boundingBox(of: card))
    }

    func removeCardNode(_ id: UUID) {
        guard let node = cardNodes.removeValue(forKey: id) else { return }
        node.root.removeFromSuperlayer()
        spatialIndex.remove(id)
        visibleIDs.remove(id)
        if textEditor?.cardID == id { tearDownEditor() }
    }

    func addStringNode(_ string: BoardString) {
        let node = StringNode(string: string, scale: backingScale)
        stringNodes[string.id] = node
        stringsByCard[string.from, default: []].insert(string.id)
        stringsByCard[string.to, default: []].insert(string.id)
        stringsLayer.addSublayer(node.layer)
        layoutString(node)
    }

    func removeStringNode(_ id: UUID) {
        guard let node = stringNodes.removeValue(forKey: id) else { return }
        node.layer.removeFromSuperlayer()
        stringsByCard[node.string.from]?.remove(id)
        stringsByCard[node.string.to]?.remove(id)
    }

    /// The frame a card shows right now, including an unfinished drag, resize or edit.
    func liveCard(_ id: UUID) -> Card? {
        if let editingCard, editingCard.id == id { return editingCard }
        guard var card = store.card(id) else { return nil }
        switch interaction {
        case .draggingCards(_, _, let current):
            if let frame = current[id] { card.frame = frame }
        case .resizing(_, _, _, let latest) where latest.id == id:
            card = latest
        default:
            break
        }
        return card
    }

    func layoutString(_ node: StringNode) {
        guard let from = liveCard(node.string.from), let to = liveCard(node.string.to) else { return }
        node.update(
            string: node.string,
            from: CanvasGeometry.pinPoint(of: from),
            to: CanvasGeometry.pinPoint(of: to),
            fan: fanOffsets[node.string.id] ?? 0,
            appearance: canvasAppearance
        )
    }

    /// Re-routes every string attached to `cardIDs`.
    func layoutStrings(attachedTo cardIDs: some Sequence<UUID>) {
        var done = Set<UUID>()
        for cardID in cardIDs {
            for stringID in stringsByCard[cardID] ?? [] where done.insert(stringID).inserted {
                if let node = stringNodes[stringID] { layoutString(node) }
            }
        }
    }

    // MARK: - Store changes

    func storeDidChange(_ changes: BoardChanges) {
        withoutAnimation {
            for id in changes.removedStrings { removeStringNode(id) }
            for id in changes.removedCards { removeCardNode(id) }
            for id in changes.insertedCards {
                guard cardNodes[id] == nil, let card = store.card(id) else { continue }
                addCardNode(card)
            }
            for id in changes.updatedCards {
                guard let node = cardNodes[id], let card = store.card(id) else { continue }
                node.update(card: card, appearance: canvasAppearance)
                spatialIndex.insert(id, rect: CanvasGeometry.boundingBox(of: card))
            }
            for id in changes.insertedStrings {
                guard stringNodes[id] == nil, let string = store.board.strings.first(where: { $0.id == id }) else { continue }
                addStringNode(string)
            }
            if !changes.insertedStrings.isEmpty || !changes.removedStrings.isEmpty {
                fanOffsets = CanvasGeometry.fanOffsets(for: store.board.strings)
                for node in stringNodes.values { layoutString(node) }
            } else {
                layoutStrings(attachedTo: changes.updatedCards.union(changes.insertedCards))
            }
        }
        let remaining = selection.filter { store.contains(card: $0) }
        if remaining != selection { selection = remaining }
        selectionDidChange()
        updateVisibility(force: true)
        controller?.boardDidChange(isEmpty: store.board.cards.isEmpty)
    }

    // MARK: - Visibility and text bitmaps

    static let tiers: [CGFloat] = [0.25, 0.5, 1, 2, 4]

    static func tier(for zoom: CGFloat) -> CGFloat {
        tiers.first { $0 >= zoom } ?? tiers[tiers.count - 1]
    }

    /// Works out which cards are near the viewport, queues their text for drawing and frees
    /// the bitmaps of cards that went far away.
    func updateVisibility(force: Bool = false) {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let visibleRect = camera.visibleWorldRect(in: size)
        let nearby = spatialIndex.query(visibleRect.insetBy(dx: -visibleRect.width * 0.25, dy: -visibleRect.height * 0.25))
        guard force || nearby != visibleIDs else { return }

        let left = visibleIDs.subtracting(nearby)
        visibleIDs = nearby
        if !left.isEmpty {
            let keep = visibleRect.insetBy(dx: -visibleRect.width, dy: -visibleRect.height)
            for id in left where spatialIndex.rects[id]?.intersects(keep) != true {
                cardNodes[id]?.discardRenderedText()
            }
        }
        scheduleRenders()
    }

    func scheduleRenders() {
        guard detailLevel != .minimal else {
            renderQueue.schedule([])
            return
        }
        let center = camera.center
        let needed = visibleIDs.compactMap { id -> (UUID, CGFloat)? in
            guard let node = cardNodes[id], node.isTextCard, node.renderedTier != renderTier,
                  textEditor?.cardID != id else { return nil }
            let frame = node.card.frame
            return (id, hypot(CGFloat(frame.midX) - center.x, CGFloat(frame.midY) - center.y))
        }
        renderQueue.schedule(needed.sorted { $0.1 < $1.1 }.map { $0.0 })
    }

    /// Draws the text of one card for the current tier.
    func renderText(of id: UUID) {
        guard let node = cardNodes[id], node.renderedTier != renderTier, visibleIDs.contains(id),
              let card = liveCard(id), case .text(let text) = card.content else { return }
        let size = CGSize(width: card.frame.width, height: card.frame.height)
        // Cap bitmaps at 4096 px on the long side, however far in you zoom.
        let scale = min(renderTier * backingScale, 4096 / max(size.width, size.height, 1))
        let image = TextCardTypography.render(text, size: size, scale: scale, appearance: canvasAppearance)
        withoutAnimation { node.setRenderedText(image, tier: renderTier, scale: scale) }
    }

    /// Redraws one card right away, for live resizing and typing.
    func renderTextNow(of id: UUID) {
        cardNodes[id]?.discardRenderedText()
        renderText(of: id)
    }

    // MARK: - Camera

    func setCamera(_ newCamera: Camera) {
        camera = newCamera
        applyCamera()
    }

    func applyCamera() {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        withoutAnimation {
            worldLayer.sublayerTransform = CATransform3DMakeAffineTransform(camera.transform(in: size))
            grid.update(camera: camera, viewSize: size)
            let level = DetailLevel(zoom: camera.zoom)
            if level != detailLevel {
                detailLevel = level
                for node in cardNodes.values { node.setDetail(level) }
            }
            updateHandles()
        }
        layoutEditor()
        updateVisibility()
        settleTierIfNeeded()
        controller?.cameraDidChange(camera)
    }

    /// Text bitmaps and ring widths follow the zoom once it has been still for a moment, so a
    /// pinch doesn't redraw every card on every frame.
    private func settleTierIfNeeded() {
        tierSettleTask?.cancel()
        tierSettleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled, let self else { return }
            withoutAnimation {
                self.rings.setZoom(self.camera.zoom, cards: self.selection.compactMap { self.liveCard($0) })
            }
            let tier = Self.tier(for: self.camera.zoom)
            if tier != self.renderTier {
                self.renderTier = tier
                self.scheduleRenders()
            }
        }
    }

    func zoomIn() {
        zoom(to: camera.nextZoomStep(up: true))
    }

    func zoomOut() {
        zoom(to: camera.nextZoomStep(up: false))
    }

    /// Zooms around the middle of the view.
    func zoom(to level: CGFloat) {
        let anchor = CGPoint(x: bounds.midX, y: bounds.midY)
        animateCamera(to: camera.zoomed(to: level, anchor: anchor, in: bounds.size), anchor: anchor)
    }

    func zoomToFit() {
        let target = CanvasGeometry.contentBounds(of: store.board.cards)
            .map { Camera.fitting($0, in: bounds.size) } ?? Camera()
        animateCamera(to: target, anchor: nil)
    }

    /// Brings `rect` (world space) into view if it's off screen, without changing the zoom.
    func reveal(_ rect: CGRect) {
        let visible = camera.visibleWorldRect(in: bounds.size).insetBy(dx: 40 / camera.zoom, dy: 40 / camera.zoom)
        guard !visible.contains(rect) else { return }
        animateCamera(to: Camera(center: CGPoint(x: rect.midX, y: rect.midY), zoom: camera.zoom), anchor: nil)
    }

    func animateCamera(to target: Camera, anchor: CGPoint?) {
        guard target != camera else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            stopCameraAnimation()
            setCamera(target)
            return
        }
        cameraAnimation = CameraAnimation(
            from: camera, to: target, anchor: anchor, start: CACurrentMediaTime(), duration: 0.28
        )
        if animationLink == nil {
            let link = displayLink(target: self, selector: #selector(stepCameraAnimation(_:)))
            link.add(to: .main, forMode: .common)
            animationLink = link
        }
    }

    @objc private func stepCameraAnimation(_ link: CADisplayLink) {
        guard let animation = cameraAnimation else {
            stopCameraAnimation()
            return
        }
        let progress = min(max((link.targetTimestamp - animation.start) / animation.duration, 0), 1)
        let eased = 1 - pow(1 - progress, 3)
        setCamera(Camera.interpolate(
            from: animation.from, to: animation.to, progress: eased, anchor: animation.anchor, in: bounds.size
        ))
        if progress >= 1 { stopCameraAnimation() }
    }

    func stopCameraAnimation() {
        cameraAnimation = nil
        animationLink?.invalidate()
        animationLink = nil
    }
}

@MainActor
func withoutAnimation(_ body: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    body()
    CATransaction.commit()
}

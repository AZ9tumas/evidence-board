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
            // A theme switch cross-fades the whole board (DESIGN.md §6.6).
            let fade = CATransition()
            fade.type = .fade
            fade.duration = Motion.isReduced ? 0.15 : 0.4
            rootLayer.add(fade, forKey: "theme")
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
    let lineGrid = LineGrid()
    let grain = GrainTexture()
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
    var selectedStrings: Set<UUID> = []
    var interaction = Interaction.idle
    var tool = CanvasTool.select
    var isSpaceHeld = false
    var textEditor: CardTextEditor?
    /// The card being edited, as it looks right now (its height follows the text).
    var editingCard: Card?

    var detailLevel = DetailLevel.full
    /// The zoom tier text bitmaps are drawn for. It follows the zoom once the zoom settles.
    var renderTier: CGFloat
    var tierSettleTask: Task<Void, Never>?
    var visibleIDs: Set<UUID> = []
    lazy var renderQueue: RenderQueue = {
        let queue = RenderQueue(view: self) { [weak self] id in self?.renderText(of: id) }
        queue.isMoving = { [weak self] in
            guard let self else { return false }
            return CACurrentMediaTime() - self.lastCameraMove < 0.2
        }
        return queue
    }()
    /// When the camera last moved, so drawing yields to panning and zooming.
    var lastCameraMove: CFTimeInterval = 0
    let imageStore = ImageStore()
    var captionEditor: CaptionEditor?
    /// The photo being reframed, if any.
    var framing: FramingSession?

    // Strings (DESIGN.md §4.5, §5.5).
    /// A string being pulled out of a pin.
    var connection: ConnectSession?
    /// The card under the pointer, whose pin is brightened.
    var hoveredCard: UUID?
    /// Strings springing to their resting sag after being created.
    var droopSprings: [UUID: Spring] = [:]
    let physics = FrameTicker()
    var labelEditor: StringLabelEditor?
    /// Web cards whose previews are being fetched.
    var previewTasks: [UUID: Task<Void, Never>] = [:]
    /// Space was pressed and nothing else happened yet: on release it peeks a web card.
    var spaceTapPending = false
    /// The color, thickness and style of the last string changed, used for new strings.
    var newStringStyle = BoardString(from: UUID(), to: UUID())
    var highlight: Highlight? {
        didSet {
            // Focus, Trace or Esc on the board ends a search; tell the search field.
            if case .search = oldValue {
                if case .search = highlight {} else { controller?.searchDidEnd() }
            }
        }
    }
    var highlightedCards: Set<UUID> = []
    var highlightedStrings: Set<UUID> = []
    var tracePath: GraphPath?
    /// Fades everything that Focus or Trace doesn't highlight.
    let dimLayer = CALayer()
    /// The glow that travels along a traced path: a 60 pt piece of the path, re-cut every
    /// frame, drawn as a soft wide stroke under a bright core. Plus the path as points with
    /// their running distances, and when the pulse set off.
    let pulseLayer = CALayer()
    let pulseGlow = CAShapeLayer()
    let pulseCore = CAShapeLayer()
    var pulsePoints: [CGPoint] = []
    var pulseDistances: [CGFloat] = []
    var pulseLength: CGFloat = 0
    var pulseStart: CFTimeInterval = 0
    /// What the mode banner says while Focus or Trace is on.
    var highlightStatus: CanvasModeStatus?
    var reduceMotion: Bool { Motion.isReduced }

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
            reduceMotion: Motion.isReduced
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
        dimLayer.zPosition = CardNode.dimmingZ
        dimLayer.isHidden = true
        cardsLayer.addSublayer(dimLayer)
        pulseLayer.zPosition = 1_000_000
        pulseLayer.isHidden = true
        for stroke in [pulseGlow, pulseCore] {
            stroke.fillColor = nil
            stroke.lineCap = .round
            stroke.lineJoin = .round
            pulseLayer.addSublayer(stroke)
        }
        stringsLayer.addSublayer(pulseLayer)
        worldLayer.addSublayer(cardsLayer)
        worldLayer.addSublayer(stringsLayer)
        worldLayer.addSublayer(rings.layer)

        rootLayer.addSublayer(backgroundLayer)
        rootLayer.addSublayer(vignetteLayer)
        rootLayer.addSublayer(grain.layer)
        rootLayer.addSublayer(lineGrid.layer)
        rootLayer.addSublayer(grid.layer)
        rootLayer.addSublayer(worldLayer)
        rootLayer.addSublayer(overlay.layer)

        detailLevel = DetailLevel(zoom: camera.zoom)
        physics.onTick = { [weak self] dt in self?.stepStringPhysics(dt) ?? false }
        applyAppearance()
        observerToken = store.addObserver { [weak self] changes in self?.storeDidChange(changes) }
        fitAutoHeightTextCards()
        fitWebCards()
        registerForDraggedTypes(Self.acceptedPasteboardTypes)
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
            physics.stop()
            renderQueue.stop()
            tierSettleTask?.cancel()
        }
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
        for node in cardNodes.values {
            node.discardRenderedText()
            node.discardImage()
        }
        updateVisibility(force: true)
    }

    var backingScale: CGFloat { window?.backingScaleFactor ?? 2 }

    private func updateContentsScale() {
        let scale = backingScale
        withoutAnimation {
            for item: CALayer in [rootLayer, backgroundLayer, vignetteLayer, worldLayer, overlay.layer] {
                item.contentsScale = scale
            }
            grid.setContentsScale(scale)
            lineGrid.setContentsScale(scale)
            if canvasAppearance.texture == .grain { grain.setColor(canvasAppearance.gridDot, scale: scale) }
            for node in cardNodes.values { node.setContentsScale(scale) }
            for node in stringNodes.values {
                node.setContentsScale(scale)
                node.setLabelScale(labelScale)
            }
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
            dimLayer.backgroundColor = canvasAppearance.background.to.opacity(0.74).cgColor
            backgroundLayer.colors = canvasAppearance.background.cgColors
            vignetteLayer.colors = [RGBA.clear.cgColor, RGBA.clear.cgColor, canvasAppearance.vignette.cgColor]
            let texture = canvasAppearance.texture
            grid.layer.isHidden = texture != .dots
            lineGrid.layer.isHidden = texture != .lines
            grain.layer.isHidden = texture != .grain
            grid.setColor(canvasAppearance.gridDot)
            lineGrid.setColor(canvasAppearance.gridDot)
            if texture == .grain { grain.setColor(canvasAppearance.gridDot, scale: backingScale) }
            overlay.setAppearance(canvasAppearance)
        }
        rebuildContent()
        applyCamera()
    }

    /// Recreates every card and string layer. Used on load and when the theme changes;
    /// edits go through ``storeDidChange(_:)`` instead.
    private func rebuildContent() {
        cancelConnecting(animated: false)
        droopSprings = [:]
        withoutAnimation {
            cardsLayer.sublayers = [dimLayer]
            stringsLayer.sublayers = [pulseLayer]
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
        refreshHighlight()
        updateVisibility()
    }

    /// Text cards whose height follows their text get the height this Mac's fonts need. A
    /// board written elsewhere (or by hand) may have saved a different one. This isn't an edit,
    /// so it's not undoable and doesn't mark the document as changed.
    private func fitAutoHeightTextCards() {
        let fitted = store.board.cards.compactMap { card -> Card? in
            guard case .text(let text) = card.content, text.autoHeight else { return nil }
            let height = TextCardTypography.fittingHeight(
                for: text, width: CGFloat(card.frame.width), appearance: canvasAppearance
            )
            guard abs(height - CGFloat(card.frame.height)) > 0.5 else { return nil }
            var card = card
            card.frame.height = Double(height)
            return card
        }
        if !fitted.isEmpty { store.apply(.updateCards(fitted)) }
    }

    // MARK: - Nodes

    func addCardNode(_ card: Card) {
        let node = CardNode(card: card, appearance: canvasAppearance, scale: backingScale)
        if let content = webContent(for: card) {
            node.update(card: card, appearance: canvasAppearance, web: content)
        }
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
        if captionEditor?.cardID == id { finishCaptionEditing(commit: false) }
        if framing?.cardID == id { framing = nil }
        previewTasks.removeValue(forKey: id)?.cancel()
    }

    /// Pixels per point for string labels, following the text tier.
    var labelScale: CGFloat { min(renderTier * backingScale, 8) }

    func addStringNode(_ string: BoardString) {
        let node = StringNode(
            string: string, appearance: canvasAppearance, detail: detailLevel, zoom: camera.zoom,
            scale: backingScale, labelScale: labelScale
        )
        stringNodes[string.id] = node
        stringsByCard[string.from, default: []].insert(string.id)
        stringsByCard[string.to, default: []].insert(string.id)
        stringsLayer.addSublayer(node.layer)
        layoutString(node)
    }

    /// Removes a string's layer, snapping it away first when `animated`.
    func removeStringNode(_ id: UUID, animated: Bool = false) {
        guard let node = stringNodes.removeValue(forKey: id) else { return }
        stringsByCard[node.string.from]?.remove(id)
        stringsByCard[node.string.to]?.remove(id)
        droopSprings[id] = nil
        if labelEditor?.stringID == id { finishLabelEditing(commit: false) }
        guard animated, !reduceMotion else {
            node.layer.removeFromSuperlayer()
            return
        }
        node.animateRemoval()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(170))
            node.layer.removeFromSuperlayer()
        }
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

    /// The string as it shows right now, including an unfinished sag drag.
    func liveString(_ id: UUID) -> BoardString? {
        if case .adjustingSag(let adjusting, _, _, let latest) = interaction, adjusting == id { return latest }
        return store.string(id)
    }

    func layoutString(_ node: StringNode) {
        let string = liveString(node.id) ?? node.string
        guard let from = liveCard(string.from), let to = liveCard(string.to) else { return }
        node.update(
            string: string,
            from: CanvasGeometry.pinPoint(of: from),
            to: CanvasGeometry.pinPoint(of: to),
            fan: fanOffsets[string.id] ?? 0,
            droopScale: droopSprings[string.id]?.value ?? 1,
            appearance: canvasAppearance
        )
        if tracePath?.strings.contains(string.id) == true { setNeedsPulseUpdate() }
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
        if changes.themeChanged { controller?.themeDidChange(store.board.theme) }
        withoutAnimation {
            for id in changes.removedStrings { removeStringNode(id, animated: true) }
            for id in changes.removedCards { removeCardNode(id) }
            // New cards pop in, unless a whole batch arrives at once (test cards, big pastes).
            let entrance = changes.insertedCards.count <= 40
            for id in changes.insertedCards {
                guard cardNodes[id] == nil, let card = store.card(id) else { continue }
                addCardNode(card)
                if entrance { cardNodes[id]?.playEntrance() }
            }
            for id in changes.updatedCards {
                guard let node = cardNodes[id], let card = store.card(id) else { continue }
                node.update(card: card, appearance: canvasAppearance, web: webContent(for: card))
                spatialIndex.insert(id, rect: CanvasGeometry.boundingBox(of: card))
            }
            for id in changes.insertedStrings {
                guard stringNodes[id] == nil, let string = store.string(id) else { continue }
                addStringNode(string)
            }
            for id in changes.updatedStrings {
                // Keep the card → string map right if a string was tied to other cards.
                guard let node = stringNodes[id], let string = store.string(id),
                      Set([node.string.from, node.string.to]) != Set([string.from, string.to]) else { continue }
                stringsByCard[node.string.from]?.remove(id)
                stringsByCard[node.string.to]?.remove(id)
                stringsByCard[string.from, default: []].insert(id)
                stringsByCard[string.to, default: []].insert(id)
            }
            if !changes.insertedStrings.isEmpty || !changes.removedStrings.isEmpty || !changes.updatedStrings.isEmpty {
                fanOffsets = CanvasGeometry.fanOffsets(for: store.board.strings)
                for node in stringNodes.values { layoutString(node) }
            } else {
                layoutStrings(attachedTo: changes.updatedCards.union(changes.insertedCards))
            }
        }
        if let connection, !store.contains(card: connection.source) { cancelConnecting(animated: false) }
        let remaining = selection.filter { store.contains(card: $0) }
        if remaining != selection { selection = remaining }
        let remainingStrings = selectedStrings.filter { stringNodes[$0] != nil }
        if remainingStrings != selectedStrings { selectedStrings = remainingStrings }
        selectionDidChange()
        if highlight != nil { refreshHighlight() }
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
        let entered = nearby.subtracting(visibleIDs)
        visibleIDs = nearby
        if !left.isEmpty {
            let keep = visibleRect.insetBy(dx: -visibleRect.width, dy: -visibleRect.height)
            for id in left where spatialIndex.rects[id]?.intersects(keep) != true {
                cardNodes[id]?.discardRenderedText()
                cardNodes[id]?.discardImage()
            }
        }
        // Mid-gesture, only the cards that just came into view are added; the whole queue
        // is re-sorted once the camera settles.
        if !force, renderQueue.isMoving() {
            scheduleRenders(adding: entered)
        } else {
            scheduleRenders()
        }
    }

    private func scheduleRenders(adding ids: Set<UUID>) {
        let byDistance = sortedByDistance(ids)
        for id in byDistance { requestImageIfNeeded(id) }
        guard detailLevel != .minimal else { return }
        renderQueue.enqueue(byDistance.filter(needsRender))
    }

    private func sortedByDistance(_ ids: Set<UUID>) -> [UUID] {
        let center = camera.center
        return ids.compactMap { id -> (UUID, CGFloat)? in
            guard let frame = cardNodes[id]?.card.frame else { return nil }
            return (id, hypot(CGFloat(frame.midX) - center.x, CGFloat(frame.midY) - center.y))
        }
        .sorted { $0.1 < $1.1 }
        .map { $0.0 }
    }

    private func needsRender(_ id: UUID) -> Bool {
        guard let node = cardNodes[id] else { return false }
        return node.hasTextContent && node.renderedTier != renderTier && editingCardID != id
    }

    func scheduleRenders() {
        let byDistance = sortedByDistance(visibleIDs)
        // Photos stay visible at every detail level, so they load even when zoomed far out.
        for id in byDistance { requestImageIfNeeded(id) }

        guard detailLevel != .minimal else {
            renderQueue.schedule([])
            return
        }
        renderQueue.schedule(byDistance.filter(needsRender))
    }

    /// The card whose text or caption is open in an editor.
    var editingCardID: UUID? {
        textEditor?.cardID ?? captionEditor?.cardID
    }

    /// Draws the text (or caption) of one card for the current tier.
    func renderText(of id: UUID) {
        guard let node = cardNodes[id], node.renderedTier != renderTier, visibleIDs.contains(id),
              let card = liveCard(id) else { return }
        let image: CGImage?
        let scale: CGFloat
        switch card.content {
        case .text(let text):
            let size = CGSize(width: card.frame.width, height: card.frame.height)
            // Cap bitmaps at 4096 px on the long side, however far in you zoom.
            scale = min(renderTier * backingScale, 4096 / max(size.width, size.height, 1))
            image = TextCardTypography.render(text, size: size, scale: scale, appearance: canvasAppearance)
        case .image(let photo):
            guard let caption = photo.caption, !caption.isEmpty else { return }
            let size = ImageCardLayout.captionRect(
                for: photo.frameStyle, in: CGSize(width: card.frame.width, height: card.frame.height)
            ).size
            scale = min(renderTier * backingScale, 4096 / max(size.width, size.height, 1))
            image = TextCardTypography.renderCaption(
                caption, overlay: ImageCardLayout.captionIsOverlaid(for: photo.frameStyle),
                size: size, scale: scale, appearance: canvasAppearance
            )
        case .web:
            guard let layout = node.webLayout else { return }
            scale = min(renderTier * backingScale, 4096 / max(layout.size.width, layout.size.height, 1))
            image = WebCardTypography.render(layout, scale: scale)
        }
        withoutAnimation { node.setRenderedText(image, tier: renderTier, scale: scale) }
    }

    /// Starts decoding a photo if the card needs more pixels than it has asked for.
    func requestImageIfNeeded(_ id: UUID) {
        guard let node = cardNodes[id], let card = liveCard(id) else { return }
        if case .web(let web) = card.content {
            requestWebImagesIfNeeded(node, web: web)
            return
        }
        guard case .image(let photo) = card.content, let asset = store.board.assets[photo.asset] else { return }
        let photoSize = ImageCardLayout.photoRect(
            for: photo.frameStyle, in: CGSize(width: card.frame.width, height: card.frame.height)
        ).size
        let knownAspect = node.imageAspect
            ?? asset.pixelWidth.flatMap { width in asset.pixelHeight.map { CGFloat(width) / CGFloat(max($0, 1)) } }
            ?? photoSize.width / max(photoSize.height, 1)
        // While reframing, ask for enough pixels for the zoomed-in crop.
        let crop = framing?.cardID == id ? framing.map { Rect($0.crop) } : photo.crop
        let needed = ImageCardLayout.bucket(ImageCardLayout.neededLongSide(
            crop: crop, imageAspect: knownAspect, photoSize: photoSize, scale: renderTier * backingScale
        ))
        if let requested = node.requestedLongSide, requested >= needed { return }
        node.requestedLongSide = needed
        imageStore.load(asset: photo.asset, base64: asset.base64, longSide: needed) { [weak self, weak node] image in
            guard let self, let node, self.cardNodes[node.id] === node else { return }
            withoutAnimation { node.setImage(image) }
        }
    }

    /// The page image and site icon of a web card, each decoded at the size it's shown.
    private func requestWebImagesIfNeeded(_ node: CardNode, web: WebPayload) {
        guard let snapshot = web.snapshot, let layout = node.webLayout else { return }
        let scale = renderTier * backingScale
        // Social posts may show their image as the poster's avatar instead.
        let imageArea = layout.image ?? (node.webContent?.imageIsAvatar == true ? layout.icon : nil)
        if let id = snapshot.image, let asset = store.board.assets[id], let area = imageArea {
            let aspect = node.imageAspect
                ?? asset.pixelWidth.flatMap { width in asset.pixelHeight.map { CGFloat(width) / CGFloat(max($0, 1)) } }
                ?? area.width / max(area.height, 1)
            let needed = ImageCardLayout.bucket(ImageCardLayout.neededLongSide(crop: nil, imageAspect: aspect, photoSize: area.size, scale: scale))
            if (node.requestedLongSide ?? 0) < needed {
                node.requestedLongSide = needed
                imageStore.load(asset: id, base64: asset.base64, longSide: needed) { [weak self, weak node] image in
                    guard let self, let node, self.cardNodes[node.id] === node else { return }
                    withoutAnimation { node.setImage(image) }
                }
            }
        }
        if let id = snapshot.icon, let asset = store.board.assets[id], let area = layout.icon {
            let needed = ImageCardLayout.bucket(Int((max(area.width, area.height) * scale).rounded(.up)))
            if (node.requestedIconSide ?? 0) < needed {
                node.requestedIconSide = needed
                imageStore.load(asset: id, base64: asset.base64, longSide: needed) { [weak self, weak node] image in
                    guard let self, let node, self.cardNodes[node.id] === node else { return }
                    withoutAnimation { node.setIcon(image) }
                }
            }
        }
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
        lastCameraMove = CACurrentMediaTime()
        withoutAnimation {
            worldLayer.sublayerTransform = CATransform3DMakeAffineTransform(camera.transform(in: size))
            switch canvasAppearance.texture {
            case .dots: grid.update(camera: camera, viewSize: size)
            case .lines: lineGrid.update(camera: camera, viewSize: size, backingScale: backingScale)
            case .grain: grain.update(camera: camera, viewSize: size)
            }
            let level = DetailLevel(zoom: camera.zoom)
            if level != detailLevel {
                detailLevel = level
                for node in cardNodes.values { node.setDetail(level) }
                for node in stringNodes.values { node.setDetail(level, zoom: camera.zoom) }
                if level == .minimal { setHoveredCard(nil) }
            }
            if highlight != nil { layoutDimLayer() }
            updateHandles()
        }
        layoutEditor()
        layoutCaptionEditor()
        layoutLabelEditor()
        updateVisibility()
        settleTierIfNeeded()
        controller?.cameraDidChange(camera, visible: camera.visibleWorldRect(in: size))
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
                // Halos, hairlines and fibers depend on the exact zoom.
                for node in self.stringNodes.values { node.setDetail(self.detailLevel, zoom: self.camera.zoom) }
            }
            let tier = Self.tier(for: self.camera.zoom)
            if tier != self.renderTier {
                self.renderTier = tier
                withoutAnimation {
                    for node in self.stringNodes.values { node.setLabelScale(self.labelScale) }
                }
            }
            // Nearest cards first, now that the camera has stopped.
            self.scheduleRenders()
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
        if Motion.isReduced {
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

import AppKit
import QuartzCore
import BoardKit

/// The board canvas: a layer-hosting view that draws the world with Core Animation.
///
/// Pan and zoom change a single matrix, `worldLayer.sublayerTransform`, so moving around
/// never re-lays out or re-renders a card.
@MainActor
public final class BoardCanvasView: NSView {
    public var canvasAppearance: CanvasAppearance {
        didSet {
            guard canvasAppearance != oldValue else { return }
            applyAppearance()
        }
    }

    public private(set) var camera: Camera
    weak var controller: CanvasController?

    private let store: BoardStore

    // Layer tree. The root is geometry-flipped so every layer uses a top-left origin.
    private let rootLayer = CALayer()
    private let backgroundLayer = CAGradientLayer()
    private let vignetteLayer = CAGradientLayer()
    private let grid = DotGrid()
    private let worldLayer = CALayer()
    private let cardsLayer = CALayer()
    private let stringsLayer = CALayer()
    private let pinsLayer = CALayer()

    private var cardNodes: [UUID: CardNode] = [:]
    private var stringNodes: [StringNode] = []

    private enum Interaction {
        case idle
        case panning(last: CGPoint)
    }

    private var interaction = Interaction.idle
    private var isSpaceHeld = false

    private struct CameraAnimation {
        let from: Camera
        let to: Camera
        let anchor: CGPoint?
        let start: CFTimeInterval
        let duration: CFTimeInterval
    }

    private var cameraAnimation: CameraAnimation?
    private var animationLink: CADisplayLink?

    init(store: BoardStore, appearance: CanvasAppearance) {
        self.store = store
        self.canvasAppearance = appearance
        self.camera = Camera(viewport: store.viewport)
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
        worldLayer.addSublayer(pinsLayer)

        rootLayer.addSublayer(backgroundLayer)
        rootLayer.addSublayer(vignetteLayer)
        rootLayer.addSublayer(grid.layer)
        rootLayer.addSublayer(worldLayer)

        applyAppearance()
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
        if newWindow == nil { stopCameraAnimation() }
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
    }

    private var contentsScale: CGFloat { window?.backingScaleFactor ?? 2 }

    private func updateContentsScale() {
        let scale = contentsScale
        withoutAnimation {
            for item: CALayer in [rootLayer, backgroundLayer, vignetteLayer, worldLayer] { item.contentsScale = scale }
            grid.setContentsScale(scale)
            for node in cardNodes.values { node.setContentsScale(scale) }
            for node in stringNodes { node.layer.contentsScale = scale }
        }
    }

    private func layoutLayers() {
        withoutAnimation {
            backgroundLayer.frame = bounds
            vignetteLayer.frame = bounds
            worldLayer.bounds = CGRect(origin: .zero, size: bounds.size)
            worldLayer.position = .zero
        }
        applyCamera()
    }

    // MARK: - Content

    private func applyAppearance() {
        withoutAnimation {
            backgroundLayer.colors = canvasAppearance.background.cgColors
            vignetteLayer.colors = [
                RGBA.clear.cgColor,
                RGBA.clear.cgColor,
                canvasAppearance.vignette.cgColor,
            ]
            grid.setColor(canvasAppearance.gridDot)
        }
        rebuildContent()
    }

    /// Builds layers for every card and string. M1 replaces this with incremental change sets
    /// and viewport culling.
    private func rebuildContent() {
        let board = store.board
        let scale = contentsScale

        withoutAnimation {
            cardsLayer.sublayers = nil
            stringsLayer.sublayers = nil
            pinsLayer.sublayers = nil
            cardNodes = [:]
            stringNodes = []

            for card in board.cards.sorted(by: { $0.z < $1.z }) {
                let node = CardNode(card: card, appearance: canvasAppearance, scale: scale)
                cardsLayer.addSublayer(node.root)
                pinsLayer.addSublayer(node.pin.root)
                cardNodes[card.id] = node
            }

            let cardsByID = Dictionary(board.cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let fans = CanvasGeometry.fanOffsets(for: board.strings)
            for string in board.strings {
                guard let from = cardsByID[string.from], let to = cardsByID[string.to] else { continue }
                let node = StringNode(
                    string: string,
                    from: CanvasGeometry.pinPoint(of: from),
                    to: CanvasGeometry.pinPoint(of: to),
                    fan: fans[string.id] ?? 0,
                    appearance: canvasAppearance,
                    scale: scale
                )
                stringsLayer.addSublayer(node.layer)
                stringNodes.append(node)
            }
        }
    }

    // MARK: - Camera

    private func setCamera(_ newCamera: Camera) {
        camera = newCamera
        applyCamera()
    }

    private func applyCamera() {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        withoutAnimation {
            worldLayer.sublayerTransform = CATransform3DMakeAffineTransform(camera.transform(in: size))
            grid.update(camera: camera, viewSize: size)
        }
        controller?.cameraDidChange(camera)
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

    private func animateCamera(to target: Camera, anchor: CGPoint?) {
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

    private func stopCameraAnimation() {
        cameraAnimation = nil
        animationLink?.invalidate()
        animationLink = nil
    }

    // MARK: - Trackpad and mouse

    public override func scrollWheel(with event: NSEvent) {
        stopCameraAnimation()
        if event.modifierFlags.contains(.command) {
            let step: CGFloat = event.hasPreciseScrollingDeltas ? 0.01 : 0.1
            let factor = exp(event.scrollingDeltaY * step)
            setCamera(camera.zoomed(to: camera.zoom * factor, anchor: location(of: event), in: bounds.size))
        } else {
            // Mouse wheels report lines, trackpads report points.
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
            var next = camera
            next.pan(by: CGVector(dx: event.scrollingDeltaX * scale, dy: event.scrollingDeltaY * scale))
            setCamera(next)
        }
    }

    public override func magnify(with event: NSEvent) {
        stopCameraAnimation()
        setCamera(camera.zoomed(to: camera.zoom * (1 + event.magnification), anchor: location(of: event), in: bounds.size))
    }

    public override func smartMagnify(with event: NSEvent) {
        let anchor = location(of: event)
        let target: CGFloat = abs(camera.zoom - 1) < 0.01 ? 2 : 1
        animateCamera(to: camera.zoomed(to: target, anchor: anchor, in: bounds.size), anchor: anchor)
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if isSpaceHeld {
            beginPan(at: location(of: event))
        } else {
            super.mouseDown(with: event)
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        continuePan(to: location(of: event))
    }

    public override func mouseUp(with event: NSEvent) {
        endPan()
    }

    public override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 {
            beginPan(at: location(of: event))
        } else {
            super.otherMouseDown(with: event)
        }
    }

    public override func otherMouseDragged(with event: NSEvent) {
        continuePan(to: location(of: event))
    }

    public override func otherMouseUp(with event: NSEvent) {
        endPan()
    }

    private func beginPan(at point: CGPoint) {
        stopCameraAnimation()
        interaction = .panning(last: point)
        NSCursor.closedHand.set()
    }

    private func continuePan(to point: CGPoint) {
        guard case .panning(let last) = interaction else { return }
        var next = camera
        next.pan(by: CGVector(dx: point.x - last.x, dy: point.y - last.y))
        setCamera(next)
        interaction = .panning(last: point)
    }

    private func endPan() {
        guard case .panning = interaction else { return }
        interaction = .idle
        (isSpaceHeld ? NSCursor.openHand : NSCursor.arrow).set()
    }

    private func location(of event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    // MARK: - Keyboard

    private static let spaceKeyCode: UInt16 = 49

    public override func keyDown(with event: NSEvent) {
        guard event.keyCode == Self.spaceKeyCode else {
            super.keyDown(with: event)
            return
        }
        if !isSpaceHeld {
            isSpaceHeld = true
            if case .idle = interaction { NSCursor.openHand.set() }
        }
    }

    public override func keyUp(with event: NSEvent) {
        guard event.keyCode == Self.spaceKeyCode else {
            super.keyUp(with: event)
            return
        }
        isSpaceHeld = false
        if case .idle = interaction { NSCursor.arrow.set() }
    }

    public override func resignFirstResponder() -> Bool {
        isSpaceHeld = false
        return super.resignFirstResponder()
    }
}

@MainActor
private func withoutAnimation(_ body: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    body()
    CATransaction.commit()
}

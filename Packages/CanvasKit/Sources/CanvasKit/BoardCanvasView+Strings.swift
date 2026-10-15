import AppKit
import BoardKit

/// The sticky canvas tools (DESIGN.md §5.1). Text is a one-shot key (T), so it isn't one.
public enum CanvasTool: Sendable {
    case select
    /// Drag from anywhere on a card, not only its pin, to connect it.
    case connect
}

/// What Focus or Trace is showing.
enum Highlight: Equatable {
    case focus(seeds: Set<UUID>, hops: Int)
    case trace(from: UUID, to: UUID)
}

/// A string being pulled out of a pin. Its loose end follows the pointer on a spring, and
/// snaps onto a card's pin when one is close.
@MainActor
final class ConnectSession {
    let source: UUID
    let preview: StringNode
    var pointer: CGPoint
    var target: UUID?
    var endX: Spring
    var endY: Spring

    init(source: UUID, preview: StringNode, start: CGPoint) {
        self.source = source
        self.preview = preview
        pointer = start
        endX = Spring(value: start.x, target: start.x, response: 0.08, damping: 0.9)
        endY = Spring(value: start.y, target: start.y, response: 0.08, damping: 0.9)
    }

    /// Follows the pointer closely, or springs onto a target with a little overshoot.
    func setSnapping(_ snapping: Bool) {
        let response: CGFloat = snapping ? 0.24 : 0.08
        let damping: CGFloat = snapping ? 0.58 : 0.9
        endX.response = response
        endX.damping = damping
        endY.response = response
        endY.damping = damping
    }

    var end: CGPoint { CGPoint(x: endX.value, y: endY.value) }
}

/// Strings: hit testing, the connect gesture, sag dragging, labels, string commands, and the
/// Focus and Trace modes (DESIGN.md §4.5, §5.5).
extension BoardCanvasView {
    // MARK: - Hit testing

    /// The topmost card at `world`.
    func topCard(atWorld world: CGPoint, tolerance: CGFloat = 0) -> UUID? {
        spatialIndex.query(world)
            .compactMap { liveCard($0) }
            .filter { CanvasGeometry.contains($0, point: world, tolerance: tolerance) }
            .max { $0.z < $1.z }?
            .id
    }

    /// The card whose pin is under `point` (view space), unless another card covers the pin.
    func pinCard(at point: CGPoint) -> UUID? {
        guard detailLevel != .minimal else { return nil }
        let world = camera.viewToWorld(point, in: bounds.size)
        let reach = max(CanvasGeometry.pinDiameter / 2 + 2 / camera.zoom, 9 / camera.zoom)
        return visiblePin(near: world, within: reach, excluding: nil)
    }

    /// The nearest uncovered pin within `reach` of `world`.
    private func visiblePin(near world: CGPoint, within reach: CGFloat, excluding excluded: UUID?) -> UUID? {
        let area = CGRect(x: world.x - reach, y: world.y - reach, width: reach * 2, height: reach * 2)
        var best: (id: UUID, distance: CGFloat)?
        for id in spatialIndex.query(area) where id != excluded {
            guard let card = liveCard(id) else { continue }
            let pin = CanvasGeometry.pinPoint(of: card)
            let distance = hypot(pin.x - world.x, pin.y - world.y)
            guard distance <= reach, distance < (best?.distance ?? .infinity), topCard(atWorld: pin) == id else { continue }
            best = (id, distance)
        }
        return best?.id
    }

    /// The string under `point` (view space): its label, or the nearest thread within 6 pt
    /// on screen (DESIGN.md §10.6).
    func string(at point: CGPoint) -> UUID? {
        let world = camera.viewToWorld(point, in: bounds.size)
        let slop = 8 / camera.zoom
        var best: (id: UUID, distance: CGFloat)?
        for node in stringNodes.values where node.hitBounds.insetBy(dx: -slop, dy: -slop).contains(world) {
            if node.showsLabel, let label = node.labelFrame, label.contains(world) { return node.id }
            let tolerance = 6 / camera.zoom + CGFloat(node.string.thickness) / 2
            let distance = CanvasGeometry.distance(from: world, to: node.polyline)
            if distance <= tolerance, distance < (best?.distance ?? .infinity) {
                best = (node.id, distance)
            }
        }
        return best?.id
    }

    // MARK: - Hover

    /// Brightens the pin of the card under the pointer, a hint that it can be pulled.
    func setHoveredCard(_ id: UUID?) {
        guard id != hoveredCard else { return }
        if let old = hoveredCard, old != connection?.source, old != connection?.target {
            cardNodes[old]?.setPinState(.normal)
        }
        hoveredCard = id
        if let id, connection == nil { cardNodes[id]?.setPinState(.hover) }
    }

    private func restoreHover() {
        let previous = hoveredCard
        hoveredCard = nil
        if let previous { cardNodes[previous]?.setPinState(.normal) }
        guard let window else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if bounds.contains(point) { setHoveredCard(card(at: point)) }
    }

    // MARK: - Connecting

    func beginConnecting(from source: UUID) {
        guard let card = liveCard(source) else { return }
        setHoveredCard(nil)
        let style = newStringStyle
        let preview = StringNode(
            string: BoardString(from: source, to: UUID(), color: style.color, thickness: style.thickness, stroke: style.stroke),
            appearance: canvasAppearance, detail: detailLevel, zoom: camera.zoom, scale: backingScale, labelScale: labelScale
        )
        preview.layer.zPosition = 500_000
        let session = ConnectSession(source: source, preview: preview, start: CanvasGeometry.pinPoint(of: card))
        connection = session
        interaction = .connecting
        withoutAnimation {
            stringsLayer.addSublayer(preview.layer)
            layoutPreview()
            updateHandles()
        }
        cardNodes[source]?.setPinState(.active)
        NSCursor.closedHand.set()
        physics.start(in: self)
    }

    func continueConnecting(to world: CGPoint) {
        guard let connection else { return }
        connection.pointer = world
        let target = connectionTarget(near: world, excluding: connection.source)
        if target != connection.target {
            if let old = connection.target { cardNodes[old]?.setPinState(.normal) }
            connection.target = target
            if let target { cardNodes[target]?.setPinState(.target) }
            connection.setSnapping(target != nil)
        }
        physics.start(in: self)
    }

    /// The card a string let go at `world` ties onto: the card under the pointer, or one
    /// whose pin is close enough to pull the string in.
    func connectionTarget(near world: CGPoint, excluding source: UUID) -> UUID? {
        if let id = topCard(atWorld: world), id != source { return id }
        return visiblePin(near: world, within: 36 / camera.zoom, excluding: source)
    }

    func finishConnecting() {
        guard let connection else { return }
        self.connection = nil
        cardNodes[connection.source]?.setPinState(.normal)
        if let target = connection.target { cardNodes[target]?.setPinState(.normal) }
        guard let target = connection.target, store.contains(card: target) else {
            retract(connection.preview)
            restoreHover()
            return
        }
        withoutAnimation { connection.preview.layer.removeFromSuperlayer() }
        let string = makeString(from: connection.source, to: target)
        boardEditor.perform(.insertStrings([string]), actionName: "Connect")
        pullTaut(string.id, drawIn: false)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        restoreHover()
    }

    func cancelConnecting(animated: Bool) {
        guard let connection else { return }
        self.connection = nil
        if case .connecting = interaction { interaction = .idle }
        cardNodes[connection.source]?.setPinState(.normal)
        if let target = connection.target { cardNodes[target]?.setPinState(.normal) }
        if animated {
            retract(connection.preview)
        } else {
            withoutAnimation { connection.preview.layer.removeFromSuperlayer() }
        }
    }

    /// The string goes back into its pin.
    private func retract(_ preview: StringNode) {
        guard !reduceMotion else {
            withoutAnimation { preview.layer.removeFromSuperlayer() }
            return
        }
        preview.animateRetraction()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            preview.layer.removeFromSuperlayer()
        }
    }

    private func layoutPreview() {
        guard let connection, let source = liveCard(connection.source) else { return }
        // A little extra slack while it's held, so it can pull taut when it's tied on.
        connection.preview.update(
            string: connection.preview.string, from: CanvasGeometry.pinPoint(of: source), to: connection.end,
            fan: 0, droopScale: 1.3, appearance: canvasAppearance
        )
    }

    /// A new string in the color, thickness and style used last.
    func makeString(from: UUID, to: UUID) -> BoardString {
        BoardString(from: from, to: to, color: newStringStyle.color, thickness: newStringStyle.thickness, stroke: newStringStyle.stroke)
    }

    /// ⌘K: ties the two selected cards together, older card first.
    func connectSelection() {
        let cards = store.board.cards.filter { selection.contains($0.id) }
        guard cards.count == 2 else {
            NSSound.beep()
            return
        }
        commitPendingEdits()
        let string = makeString(from: cards[0].id, to: cards[1].id)
        boardEditor.perform(.insertStrings([string]), actionName: "Connect")
        pullTaut(string.id, drawIn: true)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// "Pull taut" (DESIGN.md §6.6): the new string starts with extra slack and springs to its
    /// resting sag, overshooting a little. With `drawIn`, it first draws out of its pin.
    func pullTaut(_ id: UUID, drawIn: Bool) {
        guard let node = stringNodes[id] else { return }
        guard !reduceMotion else {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.15
            node.layer.add(fade, forKey: "appear")
            return
        }
        if drawIn { node.animateDrawIn() }
        droopSprings[id] = Spring(value: 1.3, target: 1, response: 0.45, damping: 0.6, delay: drawIn ? 0.22 : 0)
        withoutAnimation { layoutString(node) }
        physics.start(in: self)
    }

    /// One frame of string motion: the loose end of a string being pulled, and new strings
    /// settling. Returns whether anything is still moving.
    func stepStringPhysics(_ dt: CFTimeInterval) -> Bool {
        withoutAnimation {
            if let connection {
                let end = connection.target.flatMap { liveCard($0) }.map { CanvasGeometry.pinPoint(of: $0) } ?? connection.pointer
                connection.endX.target = end.x
                connection.endY.target = end.y
                connection.endX.step(dt)
                connection.endY.step(dt)
                layoutPreview()
            }
            for (id, var spring) in droopSprings {
                spring.step(dt)
                droopSprings[id] = spring.isSettled() ? nil : spring
                if let node = stringNodes[id] { layoutString(node) }
            }
        }
        if isPulsing { updatePulseFrame(at: CACurrentMediaTime()) }
        return connection != nil || !droopSprings.isEmpty || isPulsing
    }

    // MARK: - Sag

    /// Dragging a string up or down changes how much it sags.
    func adjustSag(to world: CGPoint) {
        guard case .adjustingSag(let id, let startWorld, let original, _) = interaction,
              let from = liveCard(original.from), let to = liveCard(original.to) else { return }
        let sag = CanvasGeometry.sag(
            CGFloat(original.sag), afterDragging: world.y - startWorld.y,
            from: CanvasGeometry.pinPoint(of: from), to: CanvasGeometry.pinPoint(of: to)
        )
        var latest = original
        latest.sag = (Double(sag) * 100).rounded() / 100
        interaction = .adjustingSag(id: id, startWorld: startWorld, original: original, latest: latest)
        withoutAnimation {
            if let node = stringNodes[id] { layoutString(node) }
            updateHandles()
        }
    }

    // MARK: - String commands

    func updateSelectedStrings(actionName: String, _ change: (inout BoardString) -> Void) {
        let updated = store.board.strings.filter { selectedStrings.contains($0.id) }.compactMap { string -> BoardString? in
            var changed = string
            change(&changed)
            return changed == string ? nil : changed
        }
        guard !updated.isEmpty else { return }
        boardEditor.perform(.updateStrings(updated), actionName: actionName)
    }

    func setStringColor(_ color: StringColor) {
        newStringStyle.color = color
        updateSelectedStrings(actionName: "Change String Color") { $0.color = color }
    }

    func setStringThickness(_ thickness: Double) {
        newStringStyle.thickness = thickness
        updateSelectedStrings(actionName: "Change Thickness") { $0.thickness = thickness }
    }

    func setStringStroke(_ stroke: StringStroke) {
        newStringStyle.stroke = stroke
        updateSelectedStrings(actionName: "Change String Style") { $0.stroke = stroke }
    }

    func setStringArrow(_ arrow: StringArrow) {
        updateSelectedStrings(actionName: "Change Arrow") { $0.arrow = arrow }
    }

    func setStringSag(_ sag: Double) {
        updateSelectedStrings(actionName: "Change Slack") { $0.sag = sag }
    }

    func reverseSelectedStrings() {
        updateSelectedStrings(actionName: "Reverse String") { string in
            (string.from, string.to) = (string.to, string.from)
        }
    }

    // MARK: - Labels

    func beginLabelEditing(_ id: UUID) {
        commitPendingEdits()
        guard let string = store.string(id), let node = stringNodes[id] else { return }
        select([], strings: [id])
        let editor = StringLabelEditor(stringID: id, text: string.label ?? "", appearance: canvasAppearance)
        editor.onFinish = { [weak self] commit in self?.finishLabelEditing(commit: commit) }
        editor.onChange = { [weak self] in self?.layoutLabelEditor() }
        labelEditor = editor
        superview?.addSubview(editor.view, positioned: .above, relativeTo: self)
        withoutAnimation {
            node.setEditingLabel(true)
            updateHandles()
        }
        layoutLabelEditor()
        let middle = node.curve.point(at: 0.5)
        reveal(CGRect(x: middle.x - 80, y: middle.y - 20, width: 160, height: 40))
        editor.focus()
        controller?.editingDidChange(true)
    }

    func layoutLabelEditor() {
        guard let editor = labelEditor, let node = stringNodes[editor.stringID] else { return }
        let center = camera.worldToView(node.curve.point(at: 0.5), in: bounds.size)
        editor.layout(center: convert(center, to: superview), zoom: camera.zoom)
    }

    func finishLabelEditing(commit: Bool) {
        guard let editor = labelEditor else { return }
        labelEditor = nil
        editor.onFinish = nil
        editor.onChange = nil
        let text = editor.text.trimmingCharacters(in: .whitespacesAndNewlines)
        editor.view.removeFromSuperview()
        window?.makeFirstResponder(self)
        withoutAnimation {
            stringNodes[editor.stringID]?.setEditingLabel(false)
            updateHandles()
        }
        controller?.editingDidChange(false)
        guard commit, var string = store.string(editor.stringID) else { return }
        let label = text.isEmpty ? nil : text
        guard label != string.label else { return }
        string.label = label
        boardEditor.perform(.updateStrings([string]), actionName: label == nil ? "Remove Label" : "Edit Label")
    }

    // MARK: - Tools and modes

    func setTool(_ newTool: CanvasTool) {
        guard newTool != tool else { return }
        tool = newTool
        if newTool == .select, connection != nil { cancelConnecting(animated: true) }
        updateModeStatus()
        controller?.toolDidChange(newTool)
        if case .idle = interaction { NSCursor.arrow.set() }
    }

    /// Esc lets go of a string, then leaves Focus or Trace, then the Connect tool, then
    /// clears the selection.
    func escape() {
        if connection != nil {
            cancelConnecting(animated: true)
        } else if highlight != nil {
            exitHighlight()
        } else if tool != .select {
            setTool(.select)
        } else {
            select([])
        }
    }

    func updateModeStatus() {
        var status = highlightStatus
        if status == nil, tool == .connect {
            status = CanvasModeStatus(
                symbol: "point.topleft.down.to.point.bottomright.curvepath",
                title: "Connect",
                hint: "Drag from one card to another · V or Esc to finish"
            )
        }
        controller?.modeDidChange(status)
    }

    // MARK: - Focus and Trace

    /// F: highlights the selected cards and everything one string away. Pressing F again
    /// widens by one more hop.
    func focusSelection() {
        guard !selection.isEmpty else {
            NSSound.beep()
            return
        }
        if case .focus(let seeds, let hops) = highlight, seeds == selection {
            guard store.graph.neighborhood(of: seeds, hops: hops).canWiden else {
                NSSound.beep()
                controller?.showNotice("Everything connected is already in focus")
                return
            }
            highlight = .focus(seeds: seeds, hops: hops + 1)
        } else {
            highlight = .focus(seeds: selection, hops: 1)
        }
        refreshHighlight(animated: true)
    }

    /// ⌘T: the shortest chain of strings between the two selected cards.
    func traceSelection() {
        let cards = store.board.cards.filter { selection.contains($0.id) }
        guard cards.count == 2 else {
            NSSound.beep()
            return
        }
        guard store.graph.shortestPath(from: cards[0].id, to: cards[1].id) != nil else {
            NSSound.beep()
            controller?.showNotice("No chain of strings connects these cards")
            return
        }
        highlight = .trace(from: cards[0].id, to: cards[1].id)
        refreshHighlight(animated: true)
    }

    func exitHighlight() {
        guard highlight != nil else { return }
        highlight = nil
        refreshHighlight(animated: true)
    }

    /// Works out what Focus or Trace shows (again, after an edit) and shows it.
    func refreshHighlight(animated: Bool = false) {
        var cards: Set<UUID> = []
        var strings: Set<UUID> = []
        var path: GraphPath?
        var status: CanvasModeStatus?
        switch highlight {
        case .focus(let seeds, let hops):
            let live = seeds.filter { store.contains(card: $0) }
            if live.isEmpty {
                highlight = nil
            } else {
                let found = store.graph.neighborhood(of: live, hops: hops)
                cards = found.cards
                strings = found.strings
                status = CanvasModeStatus(
                    symbol: "scope",
                    title: hops == 1 ? "Focus · 1 hop" : "Focus · \(hops) hops",
                    hint: found.canWiden ? "F to widen · Esc to exit" : "Esc to exit"
                )
            }
        case .trace(let from, let to):
            if let found = store.graph.shortestPath(from: from, to: to) {
                path = found
                cards = Set(found.cards)
                strings = Set(found.strings)
                let count = found.strings.count
                status = CanvasModeStatus(
                    symbol: "point.topleft.down.to.point.bottomright.curvepath",
                    title: count == 1 ? "Trace · 1 string" : "Trace · \(count) strings",
                    hint: "Esc to exit"
                )
            } else {
                highlight = nil
                controller?.showNotice("The traced cards are no longer connected")
            }
        case nil:
            break
        }
        highlightedCards = cards
        highlightedStrings = strings
        tracePath = path
        highlightStatus = status
        applyHighlight(animated: animated)
        updateModeStatus()
    }

    private func applyHighlight(animated: Bool) {
        let active = highlight != nil
        withoutAnimation {
            for (id, node) in cardNodes { node.setRaised(active && highlightedCards.contains(id)) }
            if active, dimLayer.isHidden {
                dimLayer.opacity = 0
                dimLayer.isHidden = false
            }
            layoutDimLayer()
        }
        CATransaction.begin()
        CATransaction.setDisableActions(!animated || reduceMotion)
        CATransaction.setAnimationDuration(0.25)
        for (id, node) in stringNodes {
            let emphasis: StringEmphasis = if !active {
                .normal
            } else if highlightedStrings.contains(id) {
                tracePath == nil ? .normal : .glowing
            } else {
                .dimmed
            }
            node.setEmphasis(emphasis)
        }
        dimLayer.opacity = active ? 1 : 0
        CATransaction.commit()
        if !active {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, self.highlight == nil else { return }
                withoutAnimation { self.dimLayer.isHidden = true }
            }
        }
        updatePulse()
    }

    /// The dimming layer only needs to cover what's on screen.
    func layoutDimLayer() {
        let visible = camera.visibleWorldRect(in: bounds.size)
        dimLayer.frame = visible.insetBy(dx: -visible.width, dy: -visible.height)
    }

    static let pulseSpeed: CGFloat = 600
    static let pulseSegment: CGFloat = 60
    static let pulsePause: CFTimeInterval = 0.35

    /// Whether the Trace pulse is moving, which keeps the frame ticker running.
    var isPulsing: Bool { tracePath != nil && !pulseLayer.isHidden }

    /// A 60 pt glow that travels along the traced path at 600 pt/s (DESIGN.md §6.6). It's
    /// moved by the frame ticker, so it's exactly the piece of path the design asks for.
    private func updatePulse() {
        guard let tracePath, !tracePath.strings.isEmpty, !reduceMotion else {
            withoutAnimation { pulseLayer.isHidden = true }
            pulsePoints = []
            return
        }
        let color = stringNodes[tracePath.strings[0]].map { canvasAppearance.gradient(for: $0.string.color).from } ?? canvasAppearance.pin.from
        withoutAnimation {
            pulseLayer.isHidden = false
            // A wide translucent stroke reads as glow without an offscreen shadow pass.
            pulseGlow.strokeColor = color.opacity(0.4).cgColor
            pulseGlow.lineWidth = 11
            pulseCore.strokeColor = color.mixed(with: .white, 0.75).cgColor
            pulseCore.lineWidth = 3.5
        }
        pulseStart = CACurrentMediaTime()
        updatePulsePath()
        physics.start(in: self)
    }

    /// Joins the traced strings end to end, each in the direction of travel, as points with
    /// their running distances. Called again when a traced card moves.
    func updatePulsePath() {
        guard let tracePath, !pulseLayer.isHidden else { return }
        var points: [CGPoint] = []
        for (index, id) in tracePath.strings.enumerated() {
            guard let node = stringNodes[id], index < tracePath.cards.count else { continue }
            let curve = node.string.from == tracePath.cards[index] ? node.curve : node.curve.reversed
            let piece = curve.flattened(segments: 48)
            points += points.last == piece.first ? piece.dropFirst() : piece[...]
        }
        var distances: [CGFloat] = points.isEmpty ? [] : [0]
        for (a, b) in zip(points, points.dropFirst()) {
            distances.append(distances[distances.count - 1] + hypot(b.x - a.x, b.y - a.y))
        }
        pulsePoints = points
        pulseDistances = distances
        pulseLength = distances.last ?? 0
        // Real bounds around the whole path, with world coordinates inside (see StringNode).
        let box = CGRect(
            x: points.map(\.x).min() ?? 0, y: points.map(\.y).min() ?? 0, width: 0, height: 0
        ).union(CGRect(x: points.map(\.x).max() ?? 0, y: points.map(\.y).max() ?? 0, width: 0, height: 0))
            .insetBy(dx: -16, dy: -16)
        withoutAnimation {
            for stroke in [pulseGlow, pulseCore] {
                stroke.bounds = box
                stroke.position = CGPoint(x: box.midX, y: box.midY)
            }
        }
        updatePulseFrame(at: CACurrentMediaTime())
    }

    /// Cuts the glowing piece for time `now`: its head runs from the first pin to past the
    /// last, so the tail slides into the pin, then waits a moment and sets off again.
    func updatePulseFrame(at now: CFTimeInterval) {
        guard pulsePoints.count >= 2, pulseLength > 0 else { return }
        let travel = CFTimeInterval((pulseLength + Self.pulseSegment) / Self.pulseSpeed)
        let elapsed = (now - pulseStart).truncatingRemainder(dividingBy: travel + Self.pulsePause)
        let head = min(CGFloat(elapsed) * Self.pulseSpeed, pulseLength + Self.pulseSegment)
        let path = CGMutablePath()
        let from = max(head - Self.pulseSegment, 0)
        let to = min(head, pulseLength)
        if to > from {
            path.move(to: pulsePoint(at: from))
            for (point, distance) in zip(pulsePoints, pulseDistances) where distance > from && distance < to {
                path.addLine(to: point)
            }
            path.addLine(to: pulsePoint(at: to))
        }
        withoutAnimation {
            // Hidden rather than given an empty path between runs.
            for stroke in [pulseGlow, pulseCore] {
                stroke.isHidden = path.isEmpty
                if !path.isEmpty { stroke.path = path }
            }
        }
    }

    /// The point `distance` along the pulse path.
    private func pulsePoint(at distance: CGFloat) -> CGPoint {
        guard let next = pulseDistances.firstIndex(where: { $0 >= distance }), next > 0 else {
            return distance <= 0 ? pulsePoints[0] : pulsePoints[pulsePoints.count - 1]
        }
        let a = pulsePoints[next - 1]
        let b = pulsePoints[next]
        let span = pulseDistances[next] - pulseDistances[next - 1]
        let t = span > 0 ? (distance - pulseDistances[next - 1]) / span : 0
        return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    func setNeedsPulseUpdate() {
        updatePulsePath()
    }

    // MARK: - Context menu

    func stringMenu() -> NSMenu {
        let strings = store.board.strings.filter { selectedStrings.contains($0.id) }
        let menu = NSMenu()
        if strings.count == 1 {
            menu.addItem(item(strings[0].label == nil ? "Add Label" : "Edit Label", #selector(editLabelFromMenu(_:))))
            menu.addItem(.separator())
        }

        let colors = NSMenu()
        for tint in Tint.allCases {
            let entry = item(tint.title, #selector(stringColorFromMenu(_:)), value: tint.rawValue)
            entry.image = swatch(canvasAppearance.gradient(for: tint))
            entry.state = strings.allSatisfy { $0.color == .tint(tint) } ? .on : .off
            colors.addItem(entry)
        }
        menu.addItem(submenu("Color", colors))

        let thicknesses = NSMenu()
        for (title, value) in [("Fine", 1.0), ("Regular", 2.0), ("Thick", 3.0), ("Heavy", 4.0)] {
            let entry = item(title, #selector(stringThicknessFromMenu(_:)), value: value)
            entry.state = strings.allSatisfy { $0.thickness == value } ? .on : .off
            thicknesses.addItem(entry)
        }
        menu.addItem(submenu("Thickness", thicknesses))

        let styles = NSMenu()
        for stroke in StringStroke.allCases {
            let entry = item(stroke.title, #selector(stringStrokeFromMenu(_:)), value: stroke.rawValue)
            entry.state = strings.allSatisfy { $0.stroke == stroke } ? .on : .off
            styles.addItem(entry)
        }
        menu.addItem(submenu("Style", styles))

        let arrows = NSMenu()
        for arrow in StringArrow.allCases {
            let entry = item(arrow.title, #selector(stringArrowFromMenu(_:)), value: arrow.rawValue)
            entry.state = strings.allSatisfy { $0.arrow == arrow } ? .on : .off
            arrows.addItem(entry)
        }
        menu.addItem(submenu("Arrow", arrows))

        let slack = NSMenu()
        for (title, value) in [("Taut", 0.1), ("Natural", 0.5), ("Loose", 0.9)] {
            let entry = item(title, #selector(stringSagFromMenu(_:)), value: value)
            entry.state = strings.allSatisfy { abs($0.sag - value) < 0.01 } ? .on : .off
            slack.addItem(entry)
        }
        menu.addItem(submenu("Slack", slack))
        menu.addItem(item("Reverse Direction", #selector(reverseStringsFromMenu(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Delete", #selector(delete(_:))))
        return menu
    }

    @objc private func editLabelFromMenu(_ sender: NSMenuItem) {
        guard let id = selectedStrings.first else { return }
        beginLabelEditing(id)
    }

    @objc private func stringColorFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let tint = Tint(rawValue: raw) else { return }
        setStringColor(.tint(tint))
    }

    @objc private func stringThicknessFromMenu(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        setStringThickness(value)
    }

    @objc private func stringStrokeFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let stroke = StringStroke(rawValue: raw) else { return }
        setStringStroke(stroke)
    }

    @objc private func stringArrowFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let arrow = StringArrow(rawValue: raw) else { return }
        setStringArrow(arrow)
    }

    @objc private func stringSagFromMenu(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        setStringSag(value)
    }

    @objc private func reverseStringsFromMenu(_ sender: NSMenuItem) { reverseSelectedStrings() }
    @objc func connectFromMenu(_ sender: NSMenuItem) { connectSelection() }
    @objc func traceFromMenu(_ sender: NSMenuItem) { traceSelection() }
    @objc func focusFromMenu(_ sender: NSMenuItem) { focusSelection() }
}

extension StringStroke {
    var title: String {
        switch self {
        case .solid: "Solid"
        case .dashed: "Dashed"
        case .dotted: "Dotted"
        }
    }
}

extension StringArrow {
    var title: String {
        switch self {
        case .none: "None"
        case .forward: "Forward"
        case .both: "Both Ways"
        }
    }
}

/// What the mode banner over the canvas says while a mode or tool is on.
public struct CanvasModeStatus: Sendable, Equatable {
    /// An SF Symbol name.
    public var symbol: String
    public var title: String
    public var hint: String
}

/// A one-line label field laid over the middle of a string, styled like the label capsule.
@MainActor
final class StringLabelEditor: NSObject, NSTextFieldDelegate {
    let stringID: UUID
    let view = NSView()
    private let field = NSTextField()
    private let appearance: CanvasAppearance
    private var finished = false
    var onFinish: ((Bool) -> Void)?
    var onChange: (() -> Void)?

    init(stringID: UUID, text: String, appearance: CanvasAppearance) {
        self.stringID = stringID
        self.appearance = appearance
        super.init()
        view.wantsLayer = true
        view.layer?.backgroundColor = appearance.labelFill.from.opacity(0.97).cgColor
        view.layer?.borderColor = appearance.selection.from.cgColor
        view.layer?.borderWidth = 1.5
        field.stringValue = text
        field.placeholderString = "Label"
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.alignment = .center
        field.delegate = self
        view.addSubview(field)
    }

    var text: String { field.stringValue }

    /// Centers the editor on `center` (in the superview), sized for the zoom but never too
    /// small to read.
    func layout(center: CGPoint, zoom: CGFloat) {
        let scale = max(zoom, 0.9)
        let attributes = StringLabelStyle.attributes(appearance: appearance, size: StringLabelStyle.fontSize * scale)
        let font = attributes[.font] as? NSFont ?? StringLabelStyle.font()
        field.font = font
        field.textColor = appearance.labelText.nsColor
        let sample = field.stringValue.isEmpty ? "Label" : field.stringValue
        let textWidth = ceil(NSAttributedString(string: sample, attributes: attributes).size().width)
        let height = ceil((StringLabelStyle.height + 4) * scale)
        let width = max(textWidth + 32 * scale, 96 * scale)
        view.frame = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        view.layer?.cornerRadius = height / 2
        let lineHeight = ceil(NSLayoutManager().defaultLineHeight(for: font))
        field.frame = CGRect(x: 12 * scale, y: (height - lineHeight) / 2, width: width - 24 * scale, height: lineHeight)
    }

    func focus() {
        field.window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func controlTextDidChange(_ notification: Notification) {
        onChange?()
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

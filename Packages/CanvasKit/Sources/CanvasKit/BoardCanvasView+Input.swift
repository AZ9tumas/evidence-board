import AppKit
import BoardKit

extension BoardCanvasView {
    /// What the current mouse gesture is doing.
    enum Interaction {
        case idle
        case panning(last: CGPoint)
        /// Mouse is down on a card but hasn't moved far enough to count as a drag.
        case pressingCard(id: UUID, start: CGPoint, startWorld: CGPoint)
        /// Selected cards follow the mouse. Nothing is committed until mouse up.
        case draggingCards(startWorld: CGPoint, origins: [UUID: Rect], current: [UUID: Rect])
        case marquee(start: CGPoint, base: Set<UUID>)
        case resizing(id: UUID, handle: ResizeHandle, original: Card, latest: Card)
        /// Panning a photo inside its frame while reframing.
        case framing(last: CGPoint)
        /// Pulling a new string out of a pin (see ``BoardCanvasView/connection``).
        case connecting
        /// Mouse is down on a string but hasn't moved far enough to count as a drag.
        case pressingString(id: UUID, start: CGPoint, startWorld: CGPoint)
        /// Dragging a string up or down to change its sag. Committed on mouse up.
        case adjustingSag(id: UUID, startWorld: CGPoint, original: BoardString, latest: BoardString)
    }

    func location(of event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    /// The topmost card under `point` (view space).
    func card(at point: CGPoint) -> UUID? {
        topCard(atWorld: camera.viewToWorld(point, in: bounds.size), tolerance: 2 / camera.zoom)
    }

    // MARK: - Selection

    /// Selects cards and strings, replacing the current selection.
    func select(_ ids: Set<UUID>, strings: Set<UUID> = []) {
        guard ids != selection || strings != selectedStrings else { return }
        selection = ids
        selectedStrings = strings
        noteFocus(ids)
        selectionDidChange()
    }

    func selectionDidChange() {
        withoutAnimation {
            rings.show(selection.compactMap { liveCard($0) }, zoom: camera.zoom, appearance: canvasAppearance)
            for (id, node) in stringNodes { node.setSelected(selectedStrings.contains(id)) }
            updateHandles()
        }
        controller?.selectionDidChange(
            count: selection.count, strings: selectedStrings.count,
            links: selection.filter { store.card($0)?.kind == .web }.count,
            canConnect: selection.count == 2 || previouslyFocusedCard != nil
        )
    }

    func updateHandles() {
        var showsHandles = selection.count == 1 && textEditor == nil && captionEditor == nil && framing == nil
        switch interaction {
        case .draggingCards, .marquee, .panning, .connecting: showsHandles = false
        default: break
        }
        // A lone selected string gets a grip at its middle (unless its label is the grip).
        if selection.isEmpty, selectedStrings.count == 1, labelEditor == nil, connection == nil,
           let node = selectedStrings.first.flatMap({ stringNodes[$0] }), !node.showsLabel {
            overlay.showSagHandle(at: camera.worldToView(node.curve.point(at: 0.5), in: bounds.size))
        } else {
            overlay.showSagHandle(at: nil)
        }
        guard showsHandles, let id = selection.first, let card = liveCard(id), !card.locked else {
            overlay.showHandles(for: nil, frame: nil, camera: camera, viewSize: bounds.size)
            return
        }
        overlay.showHandles(for: card, frame: card.frame, camera: camera, viewSize: bounds.size)
    }

    // MARK: - Mouse

    public override func mouseDown(with event: NSEvent) {
        let point = location(of: event)
        let world = camera.viewToWorld(point, in: bounds.size)
        if framing != nil, !isSpaceHeld, isFraming(at: point) {
            interaction = .framing(last: world)
            NSCursor.closedHand.set()
            return
        }
        commitPendingEdits()
        window?.makeFirstResponder(self)
        if isSpaceHeld || tool == .hand {
            beginPan(at: point)
            return
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let additive = modifiers.contains(.shift) || modifiers.contains(.command)

        if event.clickCount == 2 {
            if let id = string(at: point) {
                beginLabelEditing(id)
            } else if let id = card(at: point) {
                activate(id, at: world)
            } else {
                createTextCard(at: world)
            }
            return
        }

        if !additive, let handle = overlay.handle(at: point), selection.count == 1,
           let id = selection.first, let card = store.card(id), !card.locked {
            interaction = .resizing(id: id, handle: handle, original: card, latest: card)
            return
        }

        // Pull a string out of a pin, or out of any card with the Connect tool.
        var source = pinCard(at: point)
        if source == nil, tool == .connect {
            source = card(at: point)
        }
        if !additive, let source {
            beginConnecting(from: source)
            return
        }

        if let id = string(at: point) {
            if additive {
                var next = selectedStrings
                if next.remove(id) == nil { next.insert(id) }
                select(selection, strings: next)
            } else if !selectedStrings.contains(id) {
                select([], strings: [id])
            }
            interaction = .pressingString(id: id, start: point, startWorld: world)
            return
        }

        if let id = card(at: point) {
            if additive {
                var next = selection
                if next.remove(id) == nil { next.insert(id) }
                select(next, strings: selectedStrings)
            } else if !selection.contains(id) {
                select([id])
            }
            if selection.contains(id) {
                interaction = .pressingCard(id: id, start: point, startWorld: world)
            }
        } else {
            let base = additive ? selection : []
            select(base, strings: additive ? selectedStrings : [])
            interaction = .marquee(start: point, base: base)
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        let point = location(of: event)
        let world = camera.viewToWorld(point, in: bounds.size)
        switch interaction {
        case .idle:
            break
        case .panning:
            continuePan(to: point)
        case .pressingCard(_, let start, let startWorld):
            guard hypot(point.x - start.x, point.y - start.y) > 3 else { return }
            let origins = Dictionary(uniqueKeysWithValues: selection.compactMap { id -> (UUID, Rect)? in
                guard let card = store.card(id), !card.locked else { return nil }
                return (id, card.frame)
            })
            guard !origins.isEmpty else { return }
            interaction = .draggingCards(startWorld: startWorld, origins: origins, current: origins)
            for id in origins.keys { cardNodes[id]?.setLifted(true) }
            dragCards(to: world)
        case .draggingCards:
            dragCards(to: world)
        case .marquee(let start, let base):
            updateMarquee(from: start, to: point, base: base)
        case .resizing(let id, let handle, let original, _):
            // Photos keep their shape unless ⇧ is held; everything else is the other way round.
            let shift = event.modifierFlags.contains(.shift)
            resize(id, handle: handle, original: original, to: world, keepAspectRatio: original.kind == .image ? !shift : shift)
        case .framing(let last):
            panFraming(dx: world.x - last.x, dy: world.y - last.y)
            interaction = .framing(last: world)
        case .connecting:
            continueConnecting(to: world)
        case .pressingString(let id, let start, let startWorld):
            guard hypot(point.x - start.x, point.y - start.y) > 3, let string = store.string(id) else { return }
            interaction = .adjustingSag(id: id, startWorld: startWorld, original: string, latest: string)
            NSCursor.frameResize(position: .top, directions: .all).set()
            adjustSag(to: world)
        case .adjustingSag:
            adjustSag(to: world)
        }
    }

    public override func mouseUp(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let finished = interaction
        interaction = .idle
        switch finished {
        case .idle:
            break
        case .panning:
            interaction = .panning(last: .zero)
            endPan()
        case .pressingCard(let id, _, _):
            // A plain click on one card of a multiple selection selects just that card.
            if !modifiers.contains(.shift), !modifiers.contains(.command), selection.count > 1 {
                select([id])
            }
        case .draggingCards(_, let origins, let current):
            for id in origins.keys { cardNodes[id]?.setLifted(false) }
            let moved = current.filter { origins[$0.key] != $0.value }
            if moved.isEmpty {
                restoreNodes(origins.keys)
            } else {
                boardEditor.perform(.setFrames(moved), actionName: "Move")
            }
        case .marquee:
            withoutAnimation { overlay.showMarquee(nil) }
        case .framing:
            NSCursor.openHand.set()
        case .resizing(let id, _, let original, let latest):
            if latest != original {
                boardEditor.perform(.updateCards([latest]), actionName: "Resize")
            } else {
                restoreNodes([id])
            }
        case .connecting:
            finishConnecting()
        case .pressingString(let id, _, _):
            if !modifiers.contains(.shift), !modifiers.contains(.command), selectedStrings.count > 1 || !selection.isEmpty {
                select([], strings: [id])
            }
        case .adjustingSag(let id, _, let original, let latest):
            NSCursor.arrow.set()
            if latest != original {
                boardEditor.perform(.updateStrings([latest]), actionName: "Adjust Slack")
            } else if let node = stringNodes[id] {
                withoutAnimation { layoutString(node) }
            }
        }
        withoutAnimation { updateHandles() }
    }

    /// Puts nodes back to the store's version after a gesture that changed nothing.
    private func restoreNodes(_ ids: some Sequence<UUID>) {
        withoutAnimation {
            for id in ids {
                guard let card = store.card(id) else { continue }
                cardNodes[id]?.update(card: card, appearance: canvasAppearance)
                rings.move(card, to: card.frame)
            }
            layoutStrings(attachedTo: ids)
        }
    }

    private func dragCards(to world: CGPoint) {
        guard case .draggingCards(let startWorld, let origins, _) = interaction else { return }
        let dx = Double(world.x - startWorld.x)
        let dy = Double(world.y - startWorld.y)
        var current = origins
        for (id, frame) in origins {
            current[id] = Rect(x: frame.x + dx, y: frame.y + dy, width: frame.width, height: frame.height)
        }
        interaction = .draggingCards(startWorld: startWorld, origins: origins, current: current)
        withoutAnimation {
            for (id, frame) in current {
                cardNodes[id]?.setPosition(frame)
                if let card = store.card(id) { rings.move(card, to: frame) }
            }
            layoutStrings(attachedTo: current.keys, live: true)
        }
    }

    private func updateMarquee(from start: CGPoint, to point: CGPoint, base: Set<UUID>) {
        let rect = CGRect(
            x: min(start.x, point.x), y: min(start.y, point.y),
            width: abs(point.x - start.x), height: abs(point.y - start.y)
        )
        withoutAnimation { overlay.showMarquee(rect) }
        let topLeft = camera.viewToWorld(rect.origin, in: bounds.size)
        let bottomRight = camera.viewToWorld(CGPoint(x: rect.maxX, y: rect.maxY), in: bounds.size)
        let worldRect = CGRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
        select(base.union(spatialIndex.query(worldRect)))
    }

    private func resize(_ id: UUID, handle: ResizeHandle, original: Card, to world: CGPoint, keepAspectRatio: Bool) {
        let minimum = switch original.kind {
        case .text: TextCardTypography.minimumSize
        case .image: ImageCardLayout.minimumSize
        case .web: WebCardLayout.minimumSize
        }
        var frame = CanvasGeometry.resizedFrame(
            of: original, dragging: handle, to: world, minimumSize: minimum, keepAspectRatio: keepAspectRatio
        )
        var latest = original
        if original.kind == .web {
            // Web cards choose their width; the height follows the layout.
            frame.width = min(frame.width, Double(WebCardLayout.widthRange.upperBound))
            if let layout = webLayout(for: original, width: CGFloat(frame.width)) {
                frame.height = Double(layout.size.height)
            }
        }
        if case .text(var text) = original.content {
            if text.autoHeight, abs(frame.height - original.frame.height) < 8 {
                // A mostly sideways drag keeps the height following the text.
                frame.height = TextCardTypography.fittingHeight(for: text, width: CGFloat(frame.width), appearance: canvasAppearance)
            } else {
                text.autoHeight = false
            }
            latest.content = .text(text)
        }
        latest.frame = frame
        interaction = .resizing(id: id, handle: handle, original: original, latest: latest)
        withoutAnimation {
            cardNodes[id]?.update(card: latest, appearance: canvasAppearance)
            rings.move(latest, to: frame)
            layoutStrings(attachedTo: [id], live: true)
            updateHandles()
        }
        renderTextNow(of: id)
    }

    // MARK: - Trackpad and wheel

    public override func scrollWheel(with event: NSEvent) {
        spaceTapPending = false
        stopCameraAnimation()
        let point = location(of: event)
        if isFraming(at: point) {
            // Scrolling over a photo being reframed zooms the photo, not the board.
            let step: CGFloat = event.hasPreciseScrollingDeltas ? 0.01 : 0.1
            zoomFraming(by: exp(event.scrollingDeltaY * step), around: camera.viewToWorld(point, in: bounds.size))
            return
        }
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
        spaceTapPending = false
        stopCameraAnimation()
        let point = location(of: event)
        if isFraming(at: point) {
            zoomFraming(by: 1 + event.magnification, around: camera.viewToWorld(point, in: bounds.size))
            return
        }
        setCamera(camera.zoomed(to: camera.zoom * (1 + event.magnification), anchor: location(of: event), in: bounds.size))
    }

    public override func smartMagnify(with event: NSEvent) {
        let anchor = location(of: event)
        let target: CGFloat = abs(camera.zoom - 1) < 0.01 ? 2 : 1
        animateCamera(to: camera.zoomed(to: target, anchor: anchor, in: bounds.size), anchor: anchor)
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
        spaceTapPending = false
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
        (isSpaceHeld || tool == .hand ? NSCursor.openHand : NSCursor.arrow).set()
    }

    // MARK: - Cursor

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil
        ))
    }

    public override func mouseMoved(with event: NSEvent) {
        guard case .idle = interaction else { return }
        let point = location(of: event)
        let panning = isSpaceHeld || tool == .hand
        let hovered = panning || framing != nil || detailLevel == .minimal ? nil : card(at: point)
        setHoveredCard(hovered)
        if panning || isFraming(at: point) {
            NSCursor.openHand.set()
        } else if let handle = overlay.handle(at: point) {
            NSCursor.frameResize(position: handle.cursorPosition, directions: .all).set()
        } else if pinCard(at: point) != nil || (tool == .connect && hovered != nil) {
            NSCursor.crosshair.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    public override func mouseExited(with event: NSEvent) {
        if case .idle = interaction { setHoveredCard(nil) }
    }

    // MARK: - Keyboard

    private static let spaceKey: UInt16 = 49

    public override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let step: Double = modifiers.contains(.shift) ? 10 : 1
        if framing != nil, [36, 76, 53].contains(event.keyCode) {
            finishFraming(commit: event.keyCode != 53)
            return
        }
        if event.keyCode != Self.spaceKey { spaceTapPending = false }
        switch event.keyCode {
        case Self.spaceKey:
            if !isSpaceHeld {
                isSpaceHeld = true
                spaceTapPending = !event.isARepeat
                if case .idle = interaction { NSCursor.openHand.set() }
            }
        case 51, 117: // delete, forward delete
            deleteSelection()
        case 36, 76: // return, enter
            if modifiers == .command {
                openSelectionInBrowser()
            } else if selection.count == 1, let id = selection.first {
                activate(id, at: nil)
            } else if selection.isEmpty, selectedStrings.count == 1, let id = selectedStrings.first {
                beginLabelEditing(id)
            }
        case 53: // escape
            escape()
        case 48: // tab: the next card in reading order
            focusNextCard(modifiers.contains(.shift) ? -1 : 1)
        case 123 where modifiers == .option: focusCard(toward: CGVector(dx: -1, dy: 0))
        case 124 where modifiers == .option: focusCard(toward: CGVector(dx: 1, dy: 0))
        case 125 where modifiers == .option: focusCard(toward: CGVector(dx: 0, dy: 1))
        case 126 where modifiers == .option: focusCard(toward: CGVector(dx: 0, dy: -1))
        case 123: nudgeSelection(dx: -step, dy: 0)
        case 124: nudgeSelection(dx: step, dy: 0)
        case 125: nudgeSelection(dx: 0, dy: step)
        case 126: nudgeSelection(dx: 0, dy: -step)
        default:
            let key = modifiers.isEmpty ? event.charactersIgnoringModifiers?.lowercased() ?? "" : ""
            switch key {
            case "t": createTextCard(at: pointerWorldLocation() ?? camera.center)
            case "c": setTool(tool == .connect ? .select : .connect)
            case "v": setTool(.select)
            case "h": setTool(.hand)
            case "f": focusSelection()
            default: super.keyDown(with: event)
            }
        }
    }

    public override func keyUp(with event: NSEvent) {
        guard event.keyCode == Self.spaceKey else {
            super.keyUp(with: event)
            return
        }
        isSpaceHeld = false
        if case .idle = interaction { NSCursor.arrow.set() }
        // A quick tap (no pan) on a selected web card peeks at the page.
        if spaceTapPending {
            spaceTapPending = false
            peekSelection()
        }
    }

    public override func resignFirstResponder() -> Bool {
        isSpaceHeld = false
        spaceTapPending = false
        return super.resignFirstResponder()
    }

    /// Where the mouse is in world space, if it's over the canvas.
    func pointerWorldLocation() -> CGPoint? {
        guard let window else { return nil }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard bounds.contains(point) else { return nil }
        return camera.viewToWorld(point, in: bounds.size)
    }
}

extension ResizeHandle {
    var cursorPosition: NSCursor.FrameResizePosition {
        switch self {
        case .topLeft: .topLeft
        case .topRight: .topRight
        case .bottomLeft: .bottomLeft
        case .bottomRight: .bottomRight
        }
    }
}

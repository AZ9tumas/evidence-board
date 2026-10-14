import AppKit
import BoardKit

extension BoardCanvasView {
    /// Adds an empty text card centered on `world` and starts typing into it. The card only
    /// becomes an undoable edit once it has text; left empty, it disappears.
    func createTextCard(at world: CGPoint) {
        finishEditing()
        let now = Date.now
        let payload = TextPayload(content: "")
        let width = TextCardTypography.defaultWidth
        let height = TextCardTypography.fittingHeight(for: payload, width: width, appearance: canvasAppearance)
        let card = Card(
            frame: Rect(x: world.x - width / 2, y: world.y - height / 2, width: width, height: height),
            z: store.maxZ + 1,
            createdAt: now,
            modifiedAt: now,
            content: .text(payload)
        )
        store.apply(.insertCards([card]))
        beginEditing(card.id, isNewCard: true, selectAll: false)
    }

    /// Adds a finished text card, for pasting text.
    func insertTextCard(_ text: String, at world: CGPoint, actionName: String) {
        let now = Date.now
        let payload = TextPayload(content: text)
        let width: CGFloat = text.count > 140 ? 340 : TextCardTypography.defaultWidth
        let height = TextCardTypography.fittingHeight(for: payload, width: width, appearance: canvasAppearance)
        let card = Card(
            frame: Rect(x: world.x - width / 2, y: world.y - height / 2, width: width, height: height),
            z: store.maxZ + 1,
            createdAt: now,
            modifiedAt: now,
            content: .text(payload)
        )
        boardEditor.perform(.insertCards([card]), actionName: actionName)
        select([card.id])
    }

    func beginEditing(_ id: UUID, isNewCard: Bool, selectAll: Bool) {
        guard textEditor == nil, let card = store.card(id), case .text = card.content else { return }
        select([id])
        let editor = CardTextEditor(card: card, isNewCard: isNewCard, appearance: canvasAppearance)
        editor.onTextChange = { [weak self] text in self?.editorTextDidChange(text) }
        editor.onFinish = { [weak self] in self?.finishEditing() }
        textEditor = editor
        editingCard = card
        superview?.addSubview(editor.scrollView, positioned: .above, relativeTo: self)
        withoutAnimation {
            cardNodes[id]?.setEditing(true)
            updateHandles()
        }
        layoutEditor()
        reveal(CanvasGeometry.boundingBox(of: card))
        editor.focus(selectAll: selectAll)
        controller?.editingDidChange(true)
    }

    /// Keeps the editor over its card as the camera moves.
    func layoutEditor() {
        guard let editor = textEditor, let card = editingCard else { return }
        let center = camera.worldToView(CGPoint(x: card.frame.midX, y: card.frame.midY), in: bounds.size)
        let width = CGFloat(card.frame.width) * camera.zoom
        let height = CGFloat(card.frame.height) * camera.zoom
        let rect = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        editor.layout(cardFrame: card.frame, viewRect: convert(rect, to: superview), zoom: camera.zoom)
    }

    private func editorTextDidChange(_ text: String) {
        guard var card = editingCard, case .text(var payload) = card.content else { return }
        payload.content = text
        card.content = .text(payload)
        if payload.autoHeight {
            card.frame.height = TextCardTypography.fittingHeight(
                for: payload, width: CGFloat(card.frame.width), appearance: canvasAppearance
            )
        }
        editingCard = card
        withoutAnimation {
            cardNodes[card.id]?.update(card: card, appearance: canvasAppearance)
            rings.move(card, to: card.frame)
            layoutStrings(attachedTo: [card.id])
        }
        layoutEditor()
    }

    /// Closes the editor and commits the text as one undoable step.
    func finishEditing() {
        guard let editor = textEditor, var card = editingCard else { return }
        let id = editor.cardID
        tearDownEditor()
        window?.makeFirstResponder(self)

        let isBlank = editor.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if editor.isNewCard {
            guard !isBlank else {
                store.apply(.removeCards([id]))
                return
            }
            card.modifiedAt = .now
            store.apply(.updateCards([card]))
            boardEditor.registerUndo(of: .removeCards([id]), actionName: "New Text Card")
        } else if card != editor.original {
            card.modifiedAt = .now
            boardEditor.perform(.updateCards([card]), actionName: "Edit Text")
        } else if let stored = store.card(id) {
            withoutAnimation { cardNodes[id]?.update(card: stored, appearance: canvasAppearance) }
        }
        renderTextNow(of: id)
    }

    /// Removes the editor without committing anything.
    func tearDownEditor() {
        guard let editor = textEditor else { return }
        textEditor = nil
        editingCard = nil
        editor.onTextChange = nil
        editor.onFinish = nil
        editor.scrollView.removeFromSuperview()
        withoutAnimation {
            cardNodes[editor.cardID]?.setEditing(false)
            updateHandles()
        }
        controller?.editingDidChange(false)
    }
}

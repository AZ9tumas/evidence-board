import AppKit
import BoardKit

/// The live text editor laid over a text card while you type.
///
/// It's an `NSTextView` inside a magnified `NSScrollView`, so it lays text out at the card's
/// world width and draws it at the current zoom, with the same attributes as the rendered
/// bitmap. It edits the raw text, `**markdown**` markers included.
@MainActor
final class CardTextEditor: NSObject, NSTextViewDelegate {
    let cardID: UUID
    /// The card as it was before editing, for undo and for cancelling.
    let original: Card
    /// True when the card was created for this edit, so an empty result removes it.
    let isNewCard: Bool

    let scrollView = NSScrollView()
    private let textView = EditorTextView()
    private let localUndo = UndoManager()
    private var payload: TextPayload
    private let appearance: CanvasAppearance

    var onTextChange: ((TextPayload) -> Void)?
    var onFinish: (() -> Void)?

    init(card: Card, isNewCard: Bool, appearance: CanvasAppearance) {
        cardID = card.id
        original = card
        self.isNewCard = isNewCard
        let text: TextPayload = switch card.content {
        case .text(let text): text
        default: TextPayload(content: "")
        }
        payload = text
        self.appearance = appearance
        super.init()

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.allowsMagnification = true
        scrollView.minMagnification = Camera.minZoom
        scrollView.maxMagnification = Camera.maxZoom
        scrollView.contentView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false

        let insets = TextCardTypography.insets
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: insets.left, height: insets.top)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        let attributes = TextCardTypography.baseAttributes(for: text, appearance: appearance)
        textView.typingAttributes = attributes
        textView.defaultParagraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
        textView.font = TextCardTypography.font(for: text, appearance: appearance)
        textView.textColor = TextCardTypography.textColor(for: text.style, appearance: appearance)
        textView.insertionPointColor = appearance.selection.from.nsColor
        textView.selectedTextAttributes = [.backgroundColor: appearance.selection.from.opacity(0.35).nsColor]
        textView.string = text.content
        textView.textStorage?.setAttributes(attributes, range: NSRange(location: 0, length: textView.textStorage?.length ?? 0))
        textView.typingAttributes = attributes
        textView.delegate = self
        textView.onCommandReturn = { [weak self] in self?.onFinish?() }
        textView.onFormat = { [weak self] format in
            guard let self else { return }
            var updated = self.payload
            updated.set(format, enabled: !updated.isEnabled(format))
            self.applyFormatting(updated)
        }
        scrollView.documentView = textView
    }

    var text: String { textView.string }

    /// Formatting keeps the insertion point and participates in the editor's undo stack.
    func applyFormatting(_ updated: TextPayload) {
        let previous = payload
        var updated = updated
        updated.content = textView.string
        guard updated != previous else { return }
        if !localUndo.isUndoing && !localUndo.isRedoing { textView.breakUndoCoalescing() }
        localUndo.registerUndo(withTarget: self) { editor in
            MainActor.assumeIsolated { editor.applyFormatting(previous) }
        }
        localUndo.setActionName("Format Text")
        payload = updated
        let attributes = TextCardTypography.baseAttributes(for: payload, appearance: appearance)
        let selection = textView.selectedRanges
        textView.font = TextCardTypography.font(for: payload, appearance: appearance)
        textView.textColor = TextCardTypography.textColor(for: payload.style, appearance: appearance)
        textView.textStorage?.setAttributes(attributes, range: NSRange(location: 0, length: textView.textStorage?.length ?? 0))
        textView.defaultParagraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
        textView.selectedRanges = selection
        textView.typingAttributes = attributes
        onTextChange?(payload)
    }

    /// Places the editor over the card: `rect` is the card's unrotated frame in view space.
    func layout(cardFrame: Rect, viewRect: CGRect, zoom: CGFloat) {
        scrollView.frame = viewRect
        scrollView.magnification = zoom
        textView.frame = CGRect(
            x: 0, y: 0, width: CGFloat(cardFrame.width), height: max(CGFloat(cardFrame.height), textView.frame.height)
        )
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func focus(selectAll: Bool) {
        scrollView.window?.makeFirstResponder(textView)
        if selectAll {
            textView.selectAll(nil)
        } else {
            textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        }
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        payload.content = textView.string
        onTextChange?(payload)
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            onFinish?()
            return true
        }
        return false
    }

    /// Typing gets its own undo stack, so ⌘Z inside the editor never reaches the board's.
    func undoManager(for view: NSTextView) -> UndoManager? {
        localUndo
    }
}

/// Ends editing on ⌘↩; a plain ↩ starts a new line.
private final class EditorTextView: NSTextView {
    var onCommandReturn: (() -> Void)?
    var onFormat: ((TextFormat) -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let format = ["b": TextFormat.bold, "i": .italic, "u": .underline][event.charactersIgnoringModifiers ?? ""] {
            onFormat?(format)
            return
        }
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            onCommandReturn?()
            return
        }
        super.keyDown(with: event)
    }
}

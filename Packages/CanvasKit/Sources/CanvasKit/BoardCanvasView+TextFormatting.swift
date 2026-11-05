import AppKit
import BoardKit

extension BoardCanvasView {
    /// Locked cards and non-text cards never participate in text formatting.
    var selectedTextPayloads: [TextPayload] {
        selection.sorted { $0.uuidString < $1.uuidString }.compactMap { id in
            guard let card = liveCard(id), !card.locked, case .text(let text) = card.content else { return nil }
            return text
        }
    }

    func updateTextFormattingSelection() {
        controller?.textFormattingDidChange(selectedTextPayloads)
    }

    /// While typing, formatting is part of the live edit; otherwise it is one board undo.
    func formatSelectedText(actionName: String = "Format Text", _ change: (inout TextPayload) -> Void) {
        if let editor = textEditor, let card = editingCard, !card.locked, case .text(var text) = card.content {
            change(&text)
            editor.applyFormatting(text)
            return
        }
        updateSelectedCards(actionName: actionName) { card in
            guard !card.locked, case .text(var text) = card.content else { return }
            change(&text)
            card.content = .text(text)
        }
    }

    func setTextFormat(_ format: TextFormat, enabled: Bool) {
        formatSelectedText { $0.set(format, enabled: enabled) }
    }

    func setTextFontSize(_ size: Double?) {
        guard size == nil || size?.isFinite == true else { return }
        formatSelectedText(actionName: "Change Text Size") { text in
            text.fontSize = size.map { min(max($0, TextPayload.fontSizeRange.lowerBound), TextPayload.fontSizeRange.upperBound) }
        }
    }

    func changeTextFontSize(by amount: Double) {
        guard amount.isFinite else { return }
        formatSelectedText(actionName: "Change Text Size") { text in
            text.fontSize = min(max(text.resolvedFontSize + amount, TextPayload.fontSizeRange.lowerBound), TextPayload.fontSizeRange.upperBound)
        }
    }

    func setTextAlignment(_ alignment: TextCardAlignment) {
        formatSelectedText(actionName: "Align Text") { $0.alignment = alignment }
    }

    func resetTextFormatting() {
        formatSelectedText(actionName: "Reset Text Formatting") { $0.resetFormatting() }
    }
}

import SwiftUI
import BoardKit
import CanvasKit

/// Shared by the toolbar and menu bar. Settings apply to all text in selected cards.
struct TextFormattingMenu: View {
    let controller: CanvasController
    private let sizes: [Double] = [8, 10, 12, 14, 15, 16, 18, 20, 24, 28, 32, 36, 48, 64, 72, 96]

    var body: some View {
        Group {
            Menu("Font Size") {
                Toggle("Style Default", isOn: Binding(
                    get: { controller.selectedTextPayloads.allSatisfy { $0.fontSize == nil } },
                    set: { _ in controller.setTextFontSize(nil) }
                ))
                Divider()
                ForEach(sizes, id: \.self) { size in
                    Toggle("\(Int(size)) pt", isOn: Binding(
                        get: { controller.selectedTextPayloads.allSatisfy { $0.resolvedFontSize == size } },
                        set: { _ in controller.setTextFontSize(size) }
                    ))
                }
            }
            Button("Larger Text") { controller.changeTextFontSize(by: 2) }
            Button("Smaller Text") { controller.changeTextFontSize(by: -2) }
            Divider()
            Toggle("Bold", isOn: formatBinding(.bold))
                .keyboardShortcut("b", modifiers: .command)
            Toggle("Italic", isOn: formatBinding(.italic))
                .keyboardShortcut("i", modifiers: .command)
            Toggle("Underline", isOn: formatBinding(.underline))
                .keyboardShortcut("u", modifiers: .command)
            Toggle("Strikethrough", isOn: formatBinding(.strikethrough))
            Divider()
            Menu("Alignment") {
                alignment("Left", .leading)
                alignment("Center", .center)
                alignment("Right", .trailing)
            }
            Menu("Card Style") {
                ForEach(TextCardStyle.allCases, id: \.self) { style in
                    Toggle(style.rawValue.capitalized, isOn: Binding(
                        get: { controller.selectedTextPayloads.allSatisfy { $0.style == style } },
                        set: { _ in controller.setTextStyle(style) }
                    ))
                }
            }
            Divider()
            Button("Reset Card Formatting") { controller.resetTextFormatting() }
        }
        .disabled(!controller.hasTextSelection)
    }

    private func formatBinding(_ format: TextFormat) -> Binding<Bool> {
        Binding(get: { controller.textFormatIsEnabled(format) }, set: { controller.setTextFormat(format, enabled: $0) })
    }

    private func alignment(_ title: String, _ alignment: TextCardAlignment) -> some View {
        Toggle(title, isOn: Binding(
            get: { controller.selectedTextPayloads.allSatisfy { $0.alignment == alignment } },
            set: { _ in controller.setTextAlignment(alignment) }
        ))
    }
}

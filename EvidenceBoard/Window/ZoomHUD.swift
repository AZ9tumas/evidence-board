import SwiftUI
import CanvasKit

/// `−  72%  +` in the bottom-left corner. Clicking the percentage offers presets.
struct ZoomHUD: View {
    let controller: CanvasController
    let theme: Theme

    var body: some View {
        HStack(spacing: 0) {
            HUDButton(systemImage: "minus", label: "Zoom Out") { controller.zoomOut() }

            Menu {
                Button("Zoom to Fit") { controller.zoomToFit() }
                Divider()
                ForEach([0.5, 1, 2] as [CGFloat], id: \.self) { level in
                    Button("\(Int(level * 100))%") { controller.zoom(to: level) }
                }
            } label: {
                Text("\(controller.zoomPercent)%")
                    .monospacedDigit()
                    .frame(minWidth: 44)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel("Zoom level \(controller.zoomPercent) percent")

            HUDButton(systemImage: "plus", label: "Zoom In") { controller.zoomIn() }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(theme.textSecondary.color)
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .glassCapsule()
    }
}

private struct HUDButton: View {
    let systemImage: String
    let label: String
    let action: @MainActor () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 22)
                .background(.white.opacity(isHovered ? 0.08 : 0), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(label)
    }
}

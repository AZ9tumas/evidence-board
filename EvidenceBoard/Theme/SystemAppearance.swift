import AppKit
import Observation
import SwiftUI

/// Whether the Mac is in Dark Mode, for boards whose theme is Automatic. Read from the
/// application, which board windows never override, so a board forced into Daylight doesn't
/// change what Automatic means for the others.
@MainActor
@Observable
final class SystemAppearance {
    static let shared = SystemAppearance()

    private(set) var isDark: Bool
    @ObservationIgnored private var observation: NSKeyValueObservation?

    private init() {
        isDark = Self.current
        observation = NSApplication.shared.observe(\.effectiveAppearance) { _, _ in
            Task { @MainActor in
                let dark = SystemAppearance.current
                if SystemAppearance.shared.isDark != dark { SystemAppearance.shared.isDark = dark }
            }
        }
    }

    private static var current: Bool {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

/// Gives the hosting window the theme's light or dark appearance, so window chrome, menus
/// and materials match the board.
struct WindowAppearance: NSViewRepresentable {
    let isDark: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        if let window = view.window {
            window.appearance = appearance
        } else {
            Task { @MainActor in view.window?.appearance = appearance }
        }
    }
}

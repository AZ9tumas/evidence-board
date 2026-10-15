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

    func makeNSView(context: Context) -> AppearanceView {
        let view = AppearanceView()
        view.isDark = isDark
        return view
    }

    func updateNSView(_ view: AppearanceView, context: Context) {
        view.isDark = isDark
    }

    /// Applies the appearance once it's in a window, and again whenever it changes.
    final class AppearanceView: NSView {
        var isDark = true {
            didSet { if isDark != oldValue { apply() } }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        private func apply() {
            window?.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        }
    }
}

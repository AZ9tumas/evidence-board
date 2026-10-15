import AppKit
import Observation

/// Whether the Mac is in Dark Mode, for boards whose theme is Automatic. Read from the
/// system setting rather than from any window, so a board shown in Daylight doesn't change
/// what Automatic means for the others.
@MainActor
@Observable
final class SystemAppearance {
    static let shared = SystemAppearance()

    private(set) var isDark: Bool
    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {
        isDark = Self.current
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                let dark = SystemAppearance.current
                if SystemAppearance.shared.isDark != dark { SystemAppearance.shared.isDark = dark }
            }
        }
    }

    private static var current: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle")?.lowercased() == "dark"
    }
}

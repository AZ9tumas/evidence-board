import AppKit
import WebKit

/// A live view of a web card's page in a popover (DESIGN.md §7.7). The web view is made when
/// the popover opens and torn down when it closes; it never shares cookies or storage with
/// anything, and nothing web-based ever lives on the canvas itself.
@MainActor
final class PeekPopover: NSObject, NSPopoverDelegate {
    private static var current: PeekPopover?

    private let popover = NSPopover()
    private var webView: WKWebView?

    static func show(_ url: URL, relativeTo rect: CGRect, of view: NSView) {
        current?.popover.performClose(nil)
        let peek = PeekPopover(url: url)
        current = peek
        peek.popover.show(relativeTo: rect, of: view, preferredEdge: .maxX)
    }

    private init(url: URL) {
        super.init()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 720, height: 520), configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        self.webView = webView

        let controller = NSViewController()
        controller.view = webView
        popover.contentViewController = controller
        popover.contentSize = CGSize(width: 720, height: 520)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    func popoverDidClose(_ notification: Notification) {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        popover.contentViewController = nil
        webView = nil
        if Self.current === self { Self.current = nil }
    }
}

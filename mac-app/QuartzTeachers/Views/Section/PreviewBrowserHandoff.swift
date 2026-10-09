import AppKit
import Foundation
import WebKit

/// Hands a page from Plantoir's own preview to the teacher's web browser
/// (#454, plan review B1).
///
/// The preview is a bare `WKWebView` inside the app, and a web view inside an
/// app has no print dialog of its own and opens no new windows: measured on
/// macOS 26.6, `print()` returned at once with no dialog and no `afterprint`,
/// and a `target="_blank"` link did nothing. A teacher's first press of Print
/// is almost always in the preview, right after adding `printable: true`, so
/// Print had to do something there. Two doors, both to the default browser:
///
/// - the page's own print code finds the `plantoirPrint` message handler and
///   posts `{mode, url}`; the page is opened in the browser with
///   `#plantoir-print=<mode>`, which makes the handout and prints it at once;
/// - any link that asks for a new window - a page's own PDF among them - is
///   opened in the browser instead of being dropped.
///
/// REJECTED: `WKWebView.printOperation(with:)`, which prints the frame on
/// screen rather than the handout made in its hidden frame.
///
/// An NSObject of its own because WebKit's delegate and handler protocols
/// need one, and so the content controller's strong hold on a message
/// handler cannot keep the preview's controller alive.
final class PreviewBrowserHandoff: NSObject, WKUIDelegate, WKScriptMessageHandler {

    // MARK: - Stored properties

    /// The name the page's print code looks for (print.inline.ts).
    nonisolated static let messageName: String = "plantoirPrint"

    /// The ways of printing a page can ask for
    /// (contracts/shared-rules.json → printablePages.modes).
    nonisolated static let modes: [String] = ["withAnswersAtTheEnd", "questionsOnly", "answersOnly"]

    /// Told after a page has been handed over, for the trail.
    var whenHandedOver: ((URL, Reason) -> Void)?

    /// Opens a URL; replaceable so a test can watch instead of opening one.
    var open: (URL) -> Void = { url in
        NSWorkspace.shared.open(url)
    }

    // MARK: - Functions

    /// Why a page went to the browser.
    enum Reason: Equatable {
        case printHandout(mode: String)
        case newWindow
    }

    /// The address to open for a print request, or nil when the request is
    /// not one this app should act on: only the preview's own pages, served
    /// from this Mac, and only a way of printing the contract names.
    nonisolated static func printAddress(pageAddress: String, mode: String) -> URL? {
        guard modes.contains(mode),
              var parts = URLComponents(string: pageAddress),
              parts.scheme == "http" || parts.scheme == "https",
              let host = parts.host,
              host == "localhost" || host == "127.0.0.1" else {
            return nil
        }
        parts.fragment = "plantoir-print=" + mode
        return parts.url
    }

    /// The trail's words (activityTrail → `preview page opened in the web
    /// browser`): why, and the page's place in the site - its address below
    /// the preview's root, never anything written on it.
    nonisolated static func trailWords(for url: URL, reason: Reason) -> String {
        var place: String = url.path
        while place.hasPrefix("/") {
            place.removeFirst()
        }
        if place.isEmpty {
            place = "the front page"
        }
        var why: String = "a link that opens in a new window"
        if case .printHandout(let mode) = reason {
            why = "to print it " + modeWords(mode)
        } else if url.pathExtension.lowercased() == "pdf" {
            why = "a page's own PDF"
        }
        return "preview page opened in the web browser — " + why + " (" + place + ")"
    }

    nonisolated private static func modeWords(_ mode: String) -> String {
        if mode == "questionsOnly" {
            return "questions only"
        }
        if mode == "answersOnly" {
            return "answers only"
        }
        return "with the answers at the end"
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == PreviewBrowserHandoff.messageName,
              let body = message.body as? [String: Any],
              let page = body["url"] as? String,
              let mode = body["mode"] as? String,
              let address = PreviewBrowserHandoff.printAddress(pageAddress: page, mode: mode) else {
            return
        }
        open(address)
        whenHandedOver?(address, .printHandout(mode: mode))
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" || scheme == "mailto" {
            open(url)
            whenHandedOver?(url, .newWindow)
        }
        return nil
    }
}

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
///   posts `{mode, paper, url}`; the page is opened in the browser with
///   `#plantoir-print=<mode>&paper=<paper>`, which makes the handout on that
///   paper and prints it at once (#499: the paper is chosen in the page's
///   Print menu, because the page lays out its handout before any print
///   dialog opens);
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

    /// The ways of printing a page can ask for, in the menu's order
    /// (contracts/shared-rules.json → printablePages.modes; #499 decision 29).
    nonisolated static let modes: [String] = ["questionsOnly", "answersOnly", "withAnswersAtTheEnd"]

    /// The papers a page can ask for (printablePages.paper).
    nonisolated static let papers: [String] = ["portrait", "landscape"]

    /// Told after a page has been handed over, for the trail.
    /// The page the teacher was on (nil when the web view has none), then
    /// what was opened.
    var whenHandedOver: ((URL?, URL, Reason) -> Void)?

    /// Opens a URL; replaceable so a test can watch instead of opening one.
    var open: (URL) -> Void = { url in
        NSWorkspace.shared.open(url)
    }

    // MARK: - Functions

    /// Why a page went to the browser.
    enum Reason: Equatable {
        case printHandout(mode: String, paper: String)
        case newWindow
    }

    /// The address to open for a print request, or nil when the request is
    /// not one this app should act on: only the preview's own pages, served
    /// from this Mac, and only a way of printing and a paper the contract names.
    nonisolated static func printAddress(pageAddress: String, mode: String, paper: String) -> URL? {
        guard modes.contains(mode),
              papers.contains(paper),
              var parts = URLComponents(string: pageAddress),
              parts.scheme == "http" || parts.scheme == "https",
              let host = parts.host,
              host == "localhost" || host == "127.0.0.1" else {
            return nil
        }
        parts.fragment = "plantoir-print=" + mode + "&paper=" + paper
        return parts.url
    }

    /// The trail's words (activityTrail → `preview page opened in the web
    /// browser`): why, and the slug of the PAGE the teacher was on - never
    /// where a link led. A link's destination is something the teacher wrote
    /// on a page, and a shared-document address is a key to that document
    /// (implementation review S2: the first version recorded the path of any
    /// link, a Drive document id included). So a new-window link says only
    /// whether it was the page's own PDF, a page of the site, or another site.
    nonisolated static func trailWords(page: URL?, target: URL, reason: Reason) -> String {
        var place: String = "an unknown page"
        if let page, isThePreviews(page) {
            place = page.path
            while place.hasPrefix("/") {
                place.removeFirst()
            }
            if place.isEmpty {
                place = "the front page"
            }
        }
        var why: String = "a link to another site"
        if case .printHandout(let mode, let paper) = reason {
            why = "to print it " + modeWords(mode)
            if paper == "landscape" {
                why += ", on landscape paper"
            }
        } else if isThePreviews(target) {
            if target.pathExtension.lowercased() == "pdf" {
                why = "the page's own PDF"
            } else {
                why = "a link to another page of the site"
            }
        }
        return "preview page opened in the web browser — " + why + " (" + place + ")"
    }

    /// Whether an address is one of the preview's own pages, served from this Mac.
    nonisolated static func isThePreviews(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased() else {
            return false
        }
        return host == "localhost" || host == "127.0.0.1"
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
              let mode = body["mode"] as? String else {
            return
        }
        // A page built before #499 sends no paper: portrait, as it printed.
        let paper: String = (body["paper"] as? String) ?? "portrait"
        guard let address = PreviewBrowserHandoff.printAddress(pageAddress: page, mode: mode, paper: paper) else {
            return
        }
        open(address)
        whenHandedOver?(address, address, .printHandout(mode: mode, paper: paper))
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
            whenHandedOver?(webView.url, url, .newWindow)
        }
        return nil
    }
}

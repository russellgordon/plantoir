// Shows one web page in a plain macOS window with no browser around it, and
// photographs that window with macOS's own window capture.
//
// Why it exists: two figures on plantoir.app are about the SITES, not the
// browser — three courses' colour schemes fanned out, and one course in light
// and dark side by side. Three sets of traffic lights and address bars read as
// three browser windows. The old answer was to photograph Safari and then CUT
// the toolbar off and paint new rounded corners on with Pillow, and Russell
// saw the painted corners on the live site. A crop through a window cannot
// keep the window's real corners, so the answer is a window that never had a
// toolbar: this one. Its edge is the window's own edge, and
// `screencapture -x -l <window number>` — macOS's own window capture — hands
// it back with the real corner curve and the window's natural shadow (#434).
// The window is made key and this process the active app before the
// picture, because macOS draws a smaller, lighter shadow round an inactive
// window, and the parts of a figure must match every other window shot.
// Safari 26 has no "Hide Toolbar" outside full screen, which is why this is
// not simply Safari with its toolbar hidden.
//
// The page is drawn by WebKit, the engine Safari uses, and follows the Mac's
// appearance exactly as Safari does. It keeps no website data between runs,
// so no light/dark choice saved while browsing can override that appearance.
//
// Usage: swift webwindow.swift <url> <width> <height> <output.png> [settle seconds]
//            [--prepare <script.js>] [--prepare-timeout <seconds>]
//
// A URL with a #fragment is loaded without it first; once the page has
// finished drawing its mathematics and diagrams, the element is scrolled to
// the top, so the scroll lands where the anchor is in the FINAL layout.
//
// `--prepare <script.js>` puts the page into the state a figure promises
// before the picture: it presses Run on a runnable block, or answers a quiz
// and presses Check (website/shots/prepare/, #562). The file is the BODY of
// an async JavaScript function, run in the page after the settle and after
// the scroll above (so its own last step, scrolling the block into view, is
// the scroll the picture keeps). It is given `timeoutMs` and must return the
// string "ready" once what it waits for is on the page — the status line's
// "Finished.", the quiz's feedback — or any other string, which is the reason
// it is not, and stops the run. It is waited for for at most
// `--prepare-timeout` seconds (default 90), measured from when it starts:
// the minute the page itself is given to load has stopped counting by then.
// Exits 0 once the picture is written, 1 on any failure.

import AppKit
import Foundation
import WebKit

@MainActor
final class PageWindow: NSObject, WKNavigationDelegate {

    // MARK: - Stored properties

    let address: URL
    let fragment: String
    let outputPath: String
    let settleSeconds: Double
    let prepareScript: String
    let prepareTimeoutSeconds: Double
    let window: NSWindow
    let webView: WKWebView

    /// The one bound running at any moment: first the page's minute to load,
    /// then — once it has loaded — a bound on the settle, the prepare script
    /// and the picture. Each replaces the one before, so a slow prepare is
    /// reported as a slow prepare, never as a page that did not load.
    var watchdog: Task<Void, Never>?
    var photographStarted: Bool = false

    // MARK: - Initializer

    init(address: URL, width: Double, height: Double, outputPath: String, settleSeconds: Double,
         prepareScript: String, prepareTimeoutSeconds: Double) {
        var components = URLComponents(url: address, resolvingAgainstBaseURL: false)
        let requestedFragment: String = components?.fragment ?? ""
        components?.fragment = nil
        self.address = components?.url ?? address
        self.fragment = requestedFragment
        self.outputPath = outputPath
        self.settleSeconds = settleSeconds
        self.prepareScript = prepareScript
        self.prepareTimeoutSeconds = prepareTimeoutSeconds

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        let frame = NSRect(x: 0, y: 0, width: width, height: height)
        self.webView = WKWebView(frame: frame, configuration: configuration)

        // Titled, so macOS gives it a real window shape with real corners;
        // the title bar itself is made invisible and the page runs under it.
        let style: NSWindow.StyleMask = [.titled, .fullSizeContentView]
        self.window = NSWindow(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
        super.init()

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isReleasedWhenClosed = false
        window.contentView = webView
        webView.navigationDelegate = self
    }

    // MARK: - Functions

    func show() {
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            window.setFrameTopLeftPoint(NSPoint(x: visible.minX + 60, y: visible.maxY - 40))
        }
        bringToFront()
        webView.load(URLRequest(url: address))
    }

    // A missing page or a server error still "finishes loading", and would be
    // photographed as if it were the class site. Refuse it by its status.
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        let status: Int = (navigationResponse.response as? HTTPURLResponse)?.statusCode ?? 200
        if navigationResponse.isForMainFrame && status >= 400 {
            decisionHandler(.cancel)
            fail("the page answered \(status)")
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if photographStarted {
            return
        }
        photographStarted = true
        Task { @MainActor in
            await self.photographWhenSettled()
        }
    }

    /// Replaces whatever bound is running with one of `seconds`, which ends
    /// the run with `reason` if nothing cancels or replaces it first.
    func guardFor(seconds: Double, reason: String) {
        watchdog?.cancel()
        watchdog = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            if Task.isCancelled {
                return
            }
            self.fail(reason)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail("the page did not load: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail("the page did not load: \(error.localizedDescription)")
    }

    func photographWhenSettled() async {
        // The page has loaded, so its minute is over. What remains — the
        // settle, the scroll, the prepare script and the picture — gets a
        // bound of its own; the prepare script gets its own again below.
        guardFor(seconds: settleSeconds + 30,
                 reason: "the page loaded but was not photographed within \(Int(settleSeconds + 30)) seconds")
        // Mathematics, chemistry and diagrams are drawn by scripts after the
        // page itself has loaded; the settle time is for them. This is the
        // same wait the Safari captures use, for the same pages.
        try? await Task.sleep(for: .seconds(settleSeconds))
        if !fragment.isEmpty {
            let script: String = "var target = document.getElementById(\(javaScriptString(fragment)));"
                + " if (target) { target.scrollIntoView({block: 'start'}); true } else { false }"
            let found = try? await webView.evaluateJavaScript(script)
            if let wasFound = found as? Bool, wasFound == false {
                fail("the page has no element with the id \"\(fragment)\"")
                return
            }
            try? await Task.sleep(for: .seconds(1.5))
        } else {
            // Without a fragment the picture is of the page's TOP. Quartz
            // scrolls the sidebar's list to the current page when a page that
            // is not the home page loads, which in a window this size scrolls
            // the whole page about 300 points down (measured on 2026-10-09: a
            // class site's exercise page loaded at scrollY 346), cutting off
            // the title and its Print button.
            _ = try? await webView.evaluateJavaScript("window.scrollTo(0, 0); true")
            try? await Task.sleep(for: .seconds(1.0))
        }
        if !prepareScript.isEmpty {
            let ready: Bool = await prepare()
            if !ready {
                return
            }
        }
        guardFor(seconds: 30, reason: "the page window was not photographed within 30 seconds of being ready")
        await capture()
    }

    /// Runs the prepare script and waits for it, at most
    /// `prepareTimeoutSeconds`. The script's own wait is bounded by the same
    /// number (`timeoutMs`), so it normally says what it was waiting for; the
    /// bound here, a few seconds longer, catches a script that never returns.
    func prepare() async -> Bool {
        guardFor(seconds: prepareTimeoutSeconds + 5,
                 reason: "the prepare script had not finished after \(Int(prepareTimeoutSeconds + 5)) seconds")
        let answer: Any?
        do {
            answer = try await webView.callAsyncJavaScript(
                prepareScript,
                arguments: ["timeoutMs": prepareTimeoutSeconds * 1000],
                in: nil,
                contentWorld: .page
            )
        } catch {
            // WebKit puts the script's own words (the exception's message, or
            // that its promise was dropped unsettled) in the error's details.
            let details: String = ((error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String) ?? ""
            fail("the prepare script failed: \(error.localizedDescription) \(details)")
            return false
        }
        let said: String = (answer as? String) ?? "it returned \(String(describing: answer))"
        if said != "ready" {
            fail("the page was not ready to photograph: \(said)")
            return false
        }
        // The block's output was just written and scrolled into view; give
        // the page a moment to finish drawing it before the picture.
        try? await Task.sleep(for: .seconds(1.0))
        return true
    }

    /// Active app, key window: the state macOS draws the full shadow for.
    func bringToFront() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func capture() async {
        // Asked again just before the picture, and given a second to redraw
        // the shadow: something else may have come forward during the settle.
        bringToFront()
        try? await Task.sleep(for: .seconds(1))
        if !NSApplication.shared.isActive || !window.isKeyWindow {
            fail("the page window was not the active window, so its shadow would not match the other shots")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-l", String(window.windowNumber), outputPath]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            fail("screencapture could not run: \(error.localizedDescription)")
            return
        }
        if process.terminationStatus != 0 || !FileManager.default.fileExists(atPath: outputPath) {
            fail("screencapture wrote nothing for window \(window.windowNumber)")
            return
        }
        window.close()
        exit(0)
    }

    func fail(_ reason: String) {
        FileHandle.standardError.write(Data("webwindow: \(reason)\n".utf8))
        exit(1)
    }
}

func javaScriptString(_ text: String) -> String {
    var escaped: String = ""
    for character in text {
        if character == "\\" || character == "\"" {
            escaped.append("\\")
        }
        escaped.append(character)
    }
    return "\"" + escaped + "\""
}

let usage: String = "Usage: swift webwindow.swift <url> <width> <height> <output.png> [settle seconds]"
    + " [--prepare <script.js>] [--prepare-timeout <seconds>]\n"
let arguments: [String] = CommandLine.arguments
guard arguments.count >= 5,
      let address = URL(string: arguments[1]),
      let width = Double(arguments[2]),
      let height = Double(arguments[3]) else {
    FileHandle.standardError.write(Data(usage.utf8))
    exit(1)
}

// The positional settle time stays where it always was (the sixth argument),
// so every existing caller is read exactly as before; the named options come
// after it, or straight after the output path when there is no settle time.
var settleSeconds: Double = 3.5
var prepareScript: String = ""
var prepareTimeoutSeconds: Double = 90
var position: Int = 5
if position < arguments.count && !arguments[position].hasPrefix("--") {
    settleSeconds = Double(arguments[position]) ?? 3.5
    position += 1
}
while position < arguments.count {
    let option: String = arguments[position]
    let value: String? = position + 1 < arguments.count ? arguments[position + 1] : nil
    if option == "--prepare", let path = value {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8), !text.isEmpty else {
            FileHandle.standardError.write(Data("webwindow: cannot read the prepare script \(path)\n".utf8))
            exit(1)
        }
        prepareScript = text
    } else if option == "--prepare-timeout", let text = value, let seconds = Double(text), seconds > 0 {
        prepareTimeoutSeconds = seconds
    } else {
        FileHandle.standardError.write(Data(usage.utf8))
        exit(1)
    }
    position += 2
}

// Top-level code runs on the main thread; saying so lets it build the window.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    application.setActivationPolicy(.regular)
    let pageWindow = PageWindow(
        address: address,
        width: width,
        height: height,
        outputPath: arguments[4],
        settleSeconds: settleSeconds,
        prepareScript: prepareScript,
        prepareTimeoutSeconds: prepareTimeoutSeconds
    )
    // A page that never finishes loading must not hold the run up for ever.
    // This bound ends when the page has loaded (photographWhenSettled
    // replaces it); until #562 it ran from launch and was never cancelled,
    // so everything after the load counted against the same minute.
    pageWindow.guardFor(seconds: 60, reason: "the page had not finished loading after a minute")
    pageWindow.show()
    application.run()
}

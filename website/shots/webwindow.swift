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
//
// A URL with a #fragment is loaded without it first; once the page has
// finished drawing its mathematics and diagrams, the element is scrolled to
// the top, so the scroll lands where the anchor is in the FINAL layout.
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
    let window: NSWindow
    let webView: WKWebView

    // MARK: - Initializer

    init(address: URL, width: Double, height: Double, outputPath: String, settleSeconds: Double) {
        var components = URLComponents(url: address, resolvingAgainstBaseURL: false)
        let requestedFragment: String = components?.fragment ?? ""
        components?.fragment = nil
        self.address = components?.url ?? address
        self.fragment = requestedFragment
        self.outputPath = outputPath
        self.settleSeconds = settleSeconds

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
        Task { @MainActor in
            await self.photographWhenSettled()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail("the page did not load: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail("the page did not load: \(error.localizedDescription)")
    }

    func photographWhenSettled() async {
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
        }
        await capture()
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

let arguments: [String] = CommandLine.arguments
guard arguments.count >= 5,
      let address = URL(string: arguments[1]),
      let width = Double(arguments[2]),
      let height = Double(arguments[3]) else {
    FileHandle.standardError.write(Data("Usage: swift webwindow.swift <url> <width> <height> <output.png> [settle seconds]\n".utf8))
    exit(1)
}
let settleSeconds: Double = arguments.count >= 6 ? (Double(arguments[5]) ?? 3.5) : 3.5

// Top-level code runs on the main thread; saying so lets it build the window.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    application.setActivationPolicy(.regular)
    let pageWindow = PageWindow(
        address: address,
        width: width,
        height: height,
        outputPath: arguments[4],
        settleSeconds: settleSeconds
    )
    pageWindow.show()

    // A page that never finishes loading must not hold the run up for ever.
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(60))
        pageWindow.fail("the page had not finished loading after a minute")
    }
    application.run()
}

import Foundation

/// Which file Open in Obsidian opens for the page a section's preview is
/// showing (#518) — the address on screen, looked up in the list the build
/// wrote beside the site (`contracts/file-formats.json` → `pageSourcesList`).
///
/// Every rule here is a case in `contracts/shared-rules.json` →
/// `obsidianOpensThePreviewedPage`, run by `ObsidianOpensThePreviewedPageTests`
/// and by the Windows suite against its own copy of this.
enum PreviewedPageSource {

    // MARK: - Types

    /// Why the press opened the section as before, rather than a page.
    enum Fallback: String, CaseIterable {
        case noPageShowing
        case noList
        case notInTheList
        case collided
        case outsideTheCourse
        case fileGone
    }

    /// What a section's Open in Obsidian opens.
    enum Answer: Equatable {

        /// The file behind the page on screen; `place` is its place in the
        /// course folder without `.md`, for the trail.
        case page(URL, place: String, hidden: Bool)

        /// What the press opened before #518.
        case fallback(Fallback)
    }

    // MARK: - Stored properties

    /// The list's name, beside `public/` in the section's built output.
    static let listFileName: String = ".page-sources.json"

    /// The only version this app reads; any other is no list.
    static let listVersion: Int = 1

    // MARK: - Functions

    /// Where the build writes a section's list: the section's built output,
    /// reached through the course's `.merged_output` link.
    static func listURL(courseFolder: URL, sectionNumber: Int) -> URL {
        return courseFolder
            .appendingPathComponent(".merged_output")
            .appendingPathComponent("section\(sectionNumber)")
            .appendingPathComponent(PreviewedPageSource.listFileName)
    }

    /// The file for `address` — the preview's path below its root, as
    /// `PreviewStartPage.rememberedPath` gives it, or nil when no page is
    /// showing — from the list's bytes, inside `courseFolder` only.
    static func resolve(address: String?, listData: Data?, courseFolder: URL) -> Answer {
        guard let address else {
            return .fallback(.noPageShowing)
        }
        guard let pages = PreviewedPageSource.pages(fromList: listData) else {
            return .fallback(.noList)
        }
        var entry: [String: Any]?
        for key in PreviewedPageSource.lookupKeys(forAddress: address) {
            if let found = pages[key] {
                entry = found
                break
            }
        }
        guard let entry else {
            return .fallback(.notInTheList)
        }
        if entry["collided"] as? Bool == true {
            return .fallback(.collided)
        }
        guard let source = entry["source"] as? String else {
            return .fallback(.notInTheList)
        }
        let hidden: Bool = entry["hidden"] as? Bool ?? false
        // The front page that is only an embed of a class opens the class
        // (ruling 1) — while that file is there; otherwise the front page.
        if let shows = entry["shows"] as? String {
            let shown: Answer = PreviewedPageSource.file(source: shows, hidden: false, courseFolder: courseFolder)
            if case .page = shown {
                return shown
            }
        }
        return PreviewedPageSource.file(source: source, hidden: hidden, courseFolder: courseFolder)
    }

    /// The addresses to look up, in order: '' is the front page; an address
    /// ending '/' is a folder's page first and then the page itself; any
    /// other the page and then the folder's page. Decoded once and put in
    /// NFC, as every key is (`pages(fromList:)`).
    static func lookupKeys(forAddress address: String) -> [String] {
        let decoded: String = (address.removingPercentEncoding ?? address).precomposedStringWithCanonicalMapping
        if decoded.isEmpty {
            return ["index"]
        }
        if decoded.hasSuffix("/") {
            let withoutTheSlash: String = String(decoded.dropLast())
            if withoutTheSlash.isEmpty {
                return ["index"]
            }
            return [decoded + "index", withoutTheSlash]
        }
        return [decoded, decoded + "/index"]
    }

    /// The list's pages, keyed in NFC, or nil when there is no list this app
    /// can read.
    static func pages(fromList listData: Data?) -> [String: [String: Any]]? {
        guard let listData,
              let object = try? JSONSerialization.jsonObject(with: listData),
              let list = object as? [String: Any],
              list["version"] as? Int == PreviewedPageSource.listVersion,
              let pages = list["pages"] as? [String: Any] else {
            return nil
        }
        var result: [String: [String: Any]] = [:]
        for (key, value) in pages {
            if let entry = value as? [String: Any] {
                result[key.precomposedStringWithCanonicalMapping] = entry
            }
        }
        return result
    }

    /// One file named by the list, refused unless it is a page inside the
    /// course folder (links followed) that is still there.
    static func file(source: String, hidden: Bool, courseFolder: URL) -> Answer {
        if !source.hasSuffix(".md") {
            return .fallback(.notInTheList)
        }
        let candidate: URL = courseFolder.appendingPathComponent(source)
        let insideFolder: String = courseFolder.standardizedFileURL.resolvingSymlinksInPath().path
        let resolved: String = candidate.standardizedFileURL.resolvingSymlinksInPath().path
        if !resolved.hasPrefix(insideFolder + "/") {
            return .fallback(.outsideTheCourse)
        }
        var isFolder: ObjCBool = false
        if !FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isFolder) || isFolder.boolValue {
            return .fallback(.fileGone)
        }
        let place: String = String(source.dropLast(".md".count))
        return .page(candidate, place: place, hidden: hidden)
    }

    /// The trail line for a section's press (`activityTrail` → "page opened
    /// in Obsidian"), without the course and section, which
    /// `ActivityTrail.note(_:_:course:section:)` adds.
    static func trailWords(_ answer: Answer) -> String {
        switch answer {
        case .page(_, let place, let hidden):
            if hidden {
                return "opened \(place) in Obsidian, the page the preview shows (hidden from students)"
            }
            return "opened \(place) in Obsidian, the page the preview shows"
        case .fallback(let reason):
            return "opened the section in Obsidian, not a page of the preview: " + PreviewedPageSource.why(reason)
        }
    }

    /// The reason in words (`obsidianOpensThePreviewedPage.fallbacks`).
    static func why(_ reason: Fallback) -> String {
        switch reason {
        case .noPageShowing:
            return "no preview page was showing"
        case .noList:
            return "the preview's list of pages could not be read"
        case .notInTheList:
            return "the page on screen is not one of the course's own files"
        case .collided:
            return "two of the course's files make a page at that address"
        case .outsideTheCourse:
            return "the page's file is not inside the course folder"
        case .fileGone:
            return "the page's file is no longer there"
        }
    }
}

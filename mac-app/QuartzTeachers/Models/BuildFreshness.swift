import Foundation

/// Works out whether a section's built website is still up to date with
/// the teacher's content, so publishing can rebuild first when needed.
enum BuildFreshness {

    // MARK: - Functions

    /// True when there is no built site yet, the built site is a
    /// preview's build, or the content has changed since the build that
    /// made it STARTED.
    ///
    /// Since the START, not since `index.html` was written (issue #265). A
    /// build reads the settings and the pages when it begins and writes the
    /// page minutes later, so a Save made while a publish was building is
    /// older than the page — and compared with the page alone it looked
    /// built, so the next Publish sent the same old site and said it had
    /// succeeded. `build_site.py` notes the start in `.build-started` beside
    /// the site; see `referenceDate`. `contracts/app-rules.json` →
    /// `buildFreshness`.
    static func needsRebuild(course: Course, sectionNumber: Int) -> Bool {
        let indexURL: URL = builtIndexURL(course: course, sectionNumber: sectionNumber)
        guard let builtDate = modificationDate(of: indexURL) else {
            return true
        }
        // A preview's build is never deploy-fresh: serve mode bakes a
        // live-reload client pointed at ws://localhost into every page
        // (recognised by its script tag, not the address: issue #291),
        // and publishing that makes browsers ask visitors about
        // "access to other apps and services on this device". Every page,
        // not the front page alone (issue #136) — see `builtForPreview`.
        if builtForPreview(publicDirectory: builtPublicURL(course: course, sectionNumber: sectionNumber)) {
            return true
        }
        guard let contentDate = newestContentDate(course: course) else {
            // No readable content: nothing to rebuild for.
            return false
        }
        let startedDate: Date? = modificationDate(
            of: buildStartedMarkerURL(course: course, sectionNumber: sectionNumber)
        )
        return contentDate > referenceDate(builtDate: builtDate, buildStartedDate: startedDate)
    }

    /// The time the course's files are compared with: when the build that
    /// made the site started, or — for a site built before that was noted —
    /// when its page was written. The EARLIER of the two when both are
    /// there, because an early answer only ever costs a rebuild that was not
    /// needed, and a late one sends a stale site. The scheduled publish's
    /// shell check makes the same choice (`ScheduledDeploy.oneShotCommand`).
    static func referenceDate(builtDate: Date, buildStartedDate: Date?) -> Date {
        guard let buildStartedDate else {
            return builtDate
        }
        if buildStartedDate < builtDate {
            return buildStartedDate
        }
        return builtDate
    }

    /// Where `build_site.py` notes when the build that made the section's
    /// site started: a file whose modification time IS that moment, made by
    /// the build before it reads anything and moved into place once the site
    /// is copied out. Hidden, so `newestContentDate` never counts it.
    /// `contracts/app-rules.json` → `buildFreshness.buildStartedMarker`.
    static func buildStartedMarkerURL(course: Course, sectionNumber: Int) -> URL {
        return course.directoryURL
            .appendingPathComponent(".merged_output")
            .appendingPathComponent("section\(sectionNumber)")
            .appendingPathComponent(buildStartedMarkerName)
    }

    /// The marker's file name, as `build_site.py` writes it.
    static let buildStartedMarkerName: String = ".build-started"

    /// The tag Quartz opens the preview server's live-reload client with.
    /// `contracts/app-rules.json` → `buildFreshness.previewBuild.signature.scriptTag`.
    static let liveReloadScriptTag: String = "<script type=\"application/javascript\">"

    /// The client's first statement, as Quartz writes it, up to the port.
    /// `contracts/app-rules.json` → `buildFreshness.previewBuild.signature.client`.
    static let liveReloadClient: String = "const socket = new WebSocket('ws://localhost:"

    /// The same rule as a basic regular expression, for the scheduled
    /// publish's own shell check (`ScheduledDeploy.oneShotCommand`), which
    /// runs when the app is closed. `contracts/app-rules.json` →
    /// `buildFreshness.previewBuild.signature.asABasicRegex`.
    static let liveReloadPattern: String = liveReloadScriptTag + "[[:space:]]*" + liveReloadClient

    /// The bytes allowed between the tag and the client: POSIX `[[:space:]]`
    /// in the C locale — space, tab, line feed, vertical tab, form feed,
    /// carriage return. `contracts/app-rules.json` →
    /// `buildFreshness.previewBuild.signature.between`.
    static let liveReloadWhitespace: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D]

    /// True when the page holds the live-reload client's first statement
    /// directly after its script tag, with only `liveReloadWhitespace`
    /// between (issue #291).
    ///
    /// The bare address `ws://localhost:` was the rule until 2026-09-26, and
    /// any page whose note MENTIONS the address carries that too — one
    /// networking lesson, measured in a production build, carried it 20 times
    /// on 7 lines — so its site read as a preview's on every Publish and was rebuilt.
    /// A page's own words cannot produce the raw tag, because Quartz writes
    /// `<` as `&lt;` in text and in attributes alike.
    ///
    /// EVERY occurrence of the client is tried, not only the first: a
    /// preview's page about networking mentions the statement in its words
    /// (inline code, a code block) before Quartz writes the real client at
    /// the end of the body. And "the tag and the client both appear" is not
    /// the rule either: a production page already holds the same tag for
    /// Quartz's own inline script.
    static func carriesLiveReloadClient(_ page: Data) -> Bool {
        let tagBytes: Data = Data(liveReloadScriptTag.utf8)
        let clientBytes: Data = Data(liveReloadClient.utf8)
        var searchStart: Data.Index = page.startIndex
        while let clientRange = page.range(of: clientBytes, in: searchStart..<page.endIndex) {
            // Step back over the whitespace in front of this occurrence.
            var tagEnd: Data.Index = clientRange.lowerBound
            while tagEnd > page.startIndex {
                let previousByte: UInt8 = page[page.index(before: tagEnd)]
                if !liveReloadWhitespace.contains(previousByte) {
                    break
                }
                tagEnd = page.index(before: tagEnd)
            }
            // Then compare what comes before that with the tag.
            let tagLength: Int = tagBytes.count
            if page.distance(from: page.startIndex, to: tagEnd) >= tagLength {
                let tagStart: Data.Index = page.index(tagEnd, offsetBy: -tagLength)
                if page[tagStart..<tagEnd] == tagBytes {
                    return true
                }
            }
            searchStart = clientRange.upperBound
        }
        return false
    }

    /// True when any page of the built site carries the preview server's
    /// live-reload client (`carriesLiveReloadClient`, issue #291) — or when
    /// the front page cannot be read, since a site whose front page is
    /// missing is rebuilt rather than trusted.
    ///
    /// EVERY page, not the front page alone (issue #136). Serve mode bakes
    /// the client into all of them and the built tree is replaced file by
    /// file, so a clean front page in front of a preview's pages is a real
    /// state. Reading only the front page called it fresh, the Publish
    /// button skipped its build, and the launcher then rebuilt it under the
    /// destination's leg instead — which reads the whole tree, as `deploy.py`
    /// and `deploy.ps1` do. One rule for all of them:
    /// `contracts/app-rules.json` → `buildFreshness.previewBuild`.
    ///
    /// Pages are compared as BYTES, never decoded: one page that is not valid
    /// UTF-8 would otherwise force a rebuild on every publish, and no launcher
    /// decodes either. Each page is read WHOLE, because Quartz writes the tag
    /// and the client on different lines. A page that cannot be opened is
    /// passed over, as the launchers pass it over. The front page is read
    /// first, so a real preview's build answers from one file; a clean site
    /// is read to the end (measured 12 ms for an 864-file section on an M4
    /// Pro, warm).
    static func builtForPreview(publicDirectory: URL) -> Bool {
        let indexURL: URL = publicDirectory.appendingPathComponent("index.html")
        guard let frontPage = try? Data(contentsOf: indexURL) else {
            // Unreadable: rebuild rather than trust it.
            return true
        }
        if carriesLiveReloadClient(frontPage) {
            return true
        }

        // No `.skipsHiddenFiles`: `grep -r` and `rglob` both look inside
        // hidden folders, and a reader narrower than the launchers is the
        // fault this exists to close.
        guard let enumerator = FileManager.default.enumerator(
            at: publicDirectory,
            includingPropertiesForKeys: nil,
            options: []
        ) else {
            return false
        }
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension != "html" {
                continue
            }
            guard let page = try? Data(contentsOf: fileURL) else {
                continue
            }
            if carriesLiveReloadClient(page) {
                return true
            }
        }
        return false
    }

    /// Where the section's built website lives: the folder that is published.
    static func builtPublicURL(course: Course, sectionNumber: Int) -> URL {
        return course.directoryURL
            .appendingPathComponent(".merged_output")
            .appendingPathComponent("section\(sectionNumber)")
            .appendingPathComponent("public")
    }

    /// Where the section's built landing page lives.
    static func builtIndexURL(course: Course, sectionNumber: Int) -> URL {
        return builtPublicURL(course: course, sectionNumber: sectionNumber)
            .appendingPathComponent("index.html")
    }

    /// When the section's site was last built, or nil if it never was.
    static func builtSiteDate(course: Course, sectionNumber: Int) -> Date? {
        return modificationDate(of: builtIndexURL(course: course, sectionNumber: sectionNumber))
    }

    /// The newest change anywhere in the course's own content.
    ///
    /// Hidden entries are skipped, which conveniently excludes the
    /// generated `.merged_output`, the Netlify markers in
    /// `.netlify_sites`, Obsidian's `.obsidian` settings, and `.DS_Store`
    /// — none of which are content a rebuild should chase.
    static func newestContentDate(course: Course) -> Date? {
        let fileManager: FileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: course.directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var newestDate: Date?
        for case let fileURL as URL in enumerator {
            guard let date = modificationDate(of: fileURL) else {
                continue
            }
            if newestDate == nil || date > newestDate! {
                newestDate = date
            }
        }
        return newestDate
    }

    private static func modificationDate(of url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }
}

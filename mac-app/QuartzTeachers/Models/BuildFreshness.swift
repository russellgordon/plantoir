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
        // live-reload client pointed at ws://localhost into every page,
        // and publishing that makes browsers ask visitors about
        // "access to other apps and services on this device".
        if builtForPreview(indexURL) {
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

    /// True when the built page carries the preview server's
    /// live-reload client.
    static func builtForPreview(_ builtIndexURL: URL) -> Bool {
        guard let html = try? String(contentsOf: builtIndexURL, encoding: .utf8) else {
            // Unreadable: rebuild rather than trust it.
            return true
        }
        return html.contains("ws://localhost:")
    }

    /// Where the section's built landing page lives.
    static func builtIndexURL(course: Course, sectionNumber: Int) -> URL {
        return course.directoryURL
            .appendingPathComponent(".merged_output")
            .appendingPathComponent("section\(sectionNumber)")
            .appendingPathComponent("public")
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

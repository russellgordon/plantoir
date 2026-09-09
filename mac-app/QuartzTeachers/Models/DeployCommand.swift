import Foundation

/// What `deploy.sh` is asked to do for one section, at one destination.
///
/// One place decides this, because several now ask: the Deploy button, the
/// assistant, and the launchd agent a scheduled deploy leaves behind.
/// Building the arguments separately in each would let a scheduled
/// Cloudflare deploy quietly go to Netlify — the failure would appear once,
/// overnight, on a live class site.
///
/// A course can publish to more than one destination now (redundancy
/// against one host having a bad day) — see
/// `CourseConfiguration.allDeployDestinations`. The functions here that
/// take a single `destination:` are the ones a multi-destination deploy
/// calls once per leg; the ones that take a whole `configuration:` are
/// thin wrappers over those, kept so every existing caller and every
/// existing test — all written against "this course's ONE destination" —
/// keeps working unchanged, reading `deployTarget` as that one destination.
enum DeployCommand {

    // MARK: - Stored properties

    /// The launcher in the teacher's working folder.
    static let scriptName: String = "deploy.sh"

    // MARK: - Functions

    /// The arguments for one section's deploy, to one destination.
    ///
    /// Netlify passes no target flag at all: it is `deploy.sh`'s default,
    /// and every course written before Cloudflare existed relies on that.
    ///
    /// `unattended` is what a SCHEDULED deploy passes and nothing else
    /// does. It is the difference between the two kinds of caller, and it
    /// has to be a choice rather than something the launcher works out for
    /// itself: pressing Deploy runs the launcher through a pseudo-terminal
    /// (`PseudoTerminal`), so a question from `deploy.py` comes back to the
    /// app and becomes a dialog the teacher answers. That is the feature,
    /// not a fault, and it must keep working. The launchd agent runs
    /// through the identical machinery with nobody in front of it, and
    /// there the same question either waits forever or is answered with a
    /// default nobody chose. So the caller says which it is.
    static func arguments(
        courseCode: String,
        sectionNumber: Int,
        destination: CourseConfiguration.DeployDestination,
        cloudflareAccountID: String,
        unattended: Bool = false
    ) -> [String] {
        var arguments: [String] = [courseCode, String(sectionNumber)]
        // Before the destination, so every shape of deploy carries it in
        // the same place — including a folder deploy, which asks nothing
        // today but is still being run by nobody.
        if unattended {
            arguments.append("--non-interactive")
        }
        if destination.type == "local_folder" {
            arguments.append("--to-folder")
            arguments.append(destination.path)
            return arguments
        }
        if destination.type == "cloudflare_pages" {
            arguments.append("--target")
            arguments.append("cloudflare")
            // The launcher can discover the account from some tokens and
            // remembers it afterwards, but a token scoped only to Pages
            // cannot list its own account — so the app hands over what the
            // teacher gave it rather than leaving a console prompt that
            // nothing here can answer.
            let identifier: String = cloudflareAccountID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !identifier.isEmpty {
                arguments.append("--account")
                arguments.append(identifier)
            }
        }
        return arguments
    }

    /// The arguments for one section's deploy, to this course's PRIMARY
    /// destination only — a thin wrapper over the destination-aware
    /// function above, kept for every caller that still means "the one
    /// place this course deploys."
    static func arguments(
        courseCode: String,
        sectionNumber: Int,
        configuration: CourseConfiguration,
        cloudflareAccountID: String,
        unattended: Bool = false
    ) -> [String] {
        return arguments(
            courseCode: courseCode,
            sectionNumber: sectionNumber,
            destination: CourseConfiguration.DeployDestination(
                type: configuration.deployTarget, path: configuration.deployFolderPath
            ),
            cloudflareAccountID: cloudflareAccountID,
            unattended: unattended
        )
    }

    /// Where a destination deploys to, in the teacher's words.
    static func destinationDescription(for destination: CourseConfiguration.DeployDestination) -> String {
        if destination.type == "local_folder" {
            return destination.path
        }
        if destination.type == "cloudflare_pages" {
            return "Cloudflare Pages"
        }
        return "Netlify"
    }

    /// Where this course's PRIMARY destination deploys to, in the
    /// teacher's words.
    static func destinationDescription(for configuration: CourseConfiguration) -> String {
        return destinationDescription(for: CourseConfiguration.DeployDestination(
            type: configuration.deployTarget, path: configuration.deployFolderPath
        ))
    }

    /// The marker file `deploy.py` writes the first time a section goes out
    /// to a given destination TYPE, or nil for a destination that keeps
    /// none.
    ///
    /// It is the honest answer to "has this section ever been deployed
    /// HERE?" — `deploy.py` reads it to reuse the site rather than asking
    /// what to call a new one. A folder deploy asks nothing, so it has no
    /// marker. Marker files are keyed purely by destination TYPE
    /// (`.netlify_sites/`, `.cloudflare_sites/`), never by whether that
    /// type happens to be this course's primary or an additional target —
    /// `deploy.py` itself has never known the difference, so an additional
    /// Cloudflare target reuses the identical marker path a primary
    /// Cloudflare target would.
    static func firstDeployMarkerURL(
        forSection sectionNumber: Int,
        in course: Course,
        destinationType: String
    ) -> URL? {
        if destinationType == "local_folder" {
            return nil
        }
        let folderName: String = destinationType == "cloudflare_pages" ? ".cloudflare_sites" : ".netlify_sites"
        return course.directoryURL
            .appendingPathComponent(folderName)
            .appendingPathComponent("section\(sectionNumber).json")
    }

    /// The marker file for this course's PRIMARY destination — a thin
    /// wrapper over the destination-aware function above.
    static func firstDeployMarkerURL(
        forSection sectionNumber: Int,
        in course: Course
    ) -> URL? {
        return firstDeployMarkerURL(
            forSection: sectionNumber, in: course, destinationType: course.configuration.deployTarget
        )
    }

    /// What cutting a section loose from its published website did.
    struct SiteRelease: Equatable {

        // MARK: - Stored properties

        /// The kept files, named as a teacher would find them — relative to
        /// the course folder — in the order they were released.
        let keptFiles: [String]

        /// The moves, recorded so an undo puts the section back on last
        /// year's website rather than leaving it orphaned.
        let savedFiles: [AssistSavedFile]

        /// Destinations this section is STILL pinned to, because releasing
        /// them failed.
        ///
        /// **Kept apart from "there was nothing to release", which is the
        /// distinction that matters.** Both used to produce an empty
        /// `keptFiles`, so a marker that existed and could not be moved was
        /// reported to the teacher as "this section had not been published
        /// anywhere yet" — the opposite of the truth, about the one fact the
        /// whole feature turns on. The section is still pinned, the next
        /// publish still overwrites last year's site, and the sentence said it
        /// could not.
        let stillPinned: [String]

        // MARK: - Computed properties

        /// Whether this section was pinned to any website at all.
        var releasedAnything: Bool {
            return keptFiles.isEmpty == false
        }

        /// Whether anything was left pinned — either because a release failed
        /// or because only some of several destinations came loose.
        var somethingIsStillPinned: Bool {
            return stillPinned.isEmpty == false
        }
    }

    /// The name a released marker is kept under.
    ///
    /// **Frozen, and shared with Windows** (`AssistWorkspace.ReleaseSite`), so
    /// a teacher who wants back onto last year's website is told the same
    /// filename whichever app they are sitting at. Pinned in
    /// `contracts/file-formats.json` → `firstDeployMarkers`.
    static func releasedMarkerName(forSection sectionNumber: Int, at moment: Date) -> String {
        return "section\(sectionNumber).previous-" + stamp(moment) + ".json"
    }

    /// Cut a section loose from the website it publishes to, so the next
    /// publish makes a new one instead of overwriting last year's.
    ///
    /// **Renamed aside, never deleted.** The file holds the site's id and its
    /// admin address, and a teacher who decides they wanted the old website
    /// after all has no other way back to it. `deploy.py` and `build_site.py`
    /// read markers by their exact path and never glob the folder, so a
    /// `.previous-*.json` sitting beside them is inert.
    ///
    /// **Every destination type, not just this course's primary — and that is
    /// a deliberate divergence from Windows**, whose `ReleaseSite` returns
    /// inside the first folder that has a marker and so leaves a Cloudflare
    /// marker pinned when a Netlify one was released first. Markers are keyed
    /// purely by destination TYPE (see `firstDeployMarkerURL` above), and a
    /// course can carry additional targets, so releasing only the primary
    /// would leave an additional destination still overwriting last year's
    /// site. Written up for Windows as work they owe.
    static func releaseSite(
        forSection sectionNumber: Int,
        in course: Course,
        at moment: Date = Date()
    ) -> SiteRelease {
        var keptFiles: [String] = []
        var savedFiles: [AssistSavedFile] = []
        var stillPinned: [String] = []

        for destinationType in CourseConfiguration.knownDeployTargetTypes {
            guard let markerURL = firstDeployMarkerURL(
                forSection: sectionNumber, in: course, destinationType: destinationType
            ) else {
                // A folder destination keeps no marker, so there is nothing
                // pinning it to anywhere.
                continue
            }
            guard FileManager.default.fileExists(atPath: markerURL.path) else {
                // Nothing pinning this destination, which is the ordinary case
                // for a course that only publishes one way.
                continue
            }
            guard let contents = try? String(contentsOf: markerURL, encoding: .utf8) else {
                stillPinned.append(nameForTeacher(markerURL))
                continue
            }
            let keptURL: URL = markerURL.deletingLastPathComponent()
                .appendingPathComponent(releasedMarkerName(forSection: sectionNumber, at: moment))
            do {
                try FileManager.default.moveItem(at: markerURL, to: keptURL)
            } catch {
                // A marker that could not be moved is one this section is
                // still pinned to, and the reply has to say so rather than
                // reporting the same empty result as "never published".
                stillPinned.append(nameForTeacher(markerURL))
                continue
            }
            keptFiles.append(nameForTeacher(keptURL))
            savedFiles.append(AssistSavedFile(fileURL: markerURL, before: contents, after: nil))
            savedFiles.append(AssistSavedFile(fileURL: keptURL, before: nil, after: contents))
        }

        // The LEGACY marker, which `deploy.py` still reads and migrates back
        // into the stable path (`load_netlify_marker`, `scripts/deploy.py:454`).
        // Leaving it would make a rollover report "never published" and then
        // publish over last year's site on the next deploy — the whole defect,
        // in exactly the folders old enough to have taught somebody something.
        // Netlify only: there has never been a Cloudflare equivalent.
        //
        // **It lives in the BUILT OUTPUT, not beside the teacher's pages**, and
        // getting that wrong is the easy mistake: `deploy.py` computes it from
        // `section_dir`, which is `merged_output_root(...)/section<N>`
        // (`scripts/deploy.py:1001-1004`), never the content folder. An earlier
        // version of this released `courses/<CODE>/section<N>/.netlify_site.json`
        // — a path that has never held a marker in any version of the layout —
        // so it did nothing at all. `.merged_output` is a symlink out to
        // Application Support, and it may not exist yet; that is ordinary and
        // not a failure.
        let legacyURL: URL = course.directoryURL
            .appendingPathComponent(".merged_output")
            .appendingPathComponent("section\(sectionNumber)")
            .appendingPathComponent(".netlify_site.json")
        if FileManager.default.fileExists(atPath: legacyURL.path) {
            if let contents = try? String(contentsOf: legacyURL, encoding: .utf8) {
                let keptURL: URL = legacyURL.deletingLastPathComponent()
                    .appendingPathComponent(
                        ".netlify_site.previous-" + stamp(moment) + ".json"
                    )
                do {
                    try FileManager.default.moveItem(at: legacyURL, to: keptURL)
                    keptFiles.append(nameForTeacher(keptURL))
                    savedFiles.append(
                        AssistSavedFile(fileURL: legacyURL, before: contents, after: nil)
                    )
                    savedFiles.append(
                        AssistSavedFile(fileURL: keptURL, before: nil, after: contents)
                    )
                } catch {
                    stillPinned.append(nameForTeacher(legacyURL))
                }
            } else {
                stillPinned.append(nameForTeacher(legacyURL))
            }
        }

        return SiteRelease(keptFiles: keptFiles, savedFiles: savedFiles, stillPinned: stillPinned)
    }

    /// The moment, spelled the way both apps spell it in a kept filename.
    private static func stamp(_ moment: Date) -> String {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: moment)
    }

    /// A marker named the way a teacher would find it — the folder it sits in
    /// and the file, without the rest of the path.
    private static func nameForTeacher(_ markerURL: URL) -> String {
        return markerURL.deletingLastPathComponent().lastPathComponent
             + "/" + markerURL.lastPathComponent
    }

    /// True when this section has been deployed to the given destination
    /// TYPE at least once, so a deploy to it asks the teacher nothing.
    static func hasDeployedBefore(section sectionNumber: Int, in course: Course, destinationType: String) -> Bool {
        guard let markerURL = firstDeployMarkerURL(forSection: sectionNumber, in: course, destinationType: destinationType) else {
            return true
        }
        return FileManager.default.fileExists(atPath: markerURL.path)
    }

    /// True when this section has been deployed to its PRIMARY destination
    /// at least once — a thin wrapper over the destination-aware function
    /// above.
    static func hasDeployedBefore(section sectionNumber: Int, in course: Course) -> Bool {
        return hasDeployedBefore(section: sectionNumber, in: course, destinationType: course.configuration.deployTarget)
    }
}

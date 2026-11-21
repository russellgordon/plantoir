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
    /// Every destination is NAMED, Netlify included (`--target netlify`)
    /// since #668. Before that Netlify passed no flag, as `deploy.sh`'s own
    /// default; but a `deploy.sh` given no destination now reads the
    /// course's SAVED one and deploys every saved destination, one leg each
    /// (Russell, 2026-11-01), so the Netlify leg of a course that also
    /// deploys elsewhere would have run every leg again. Naming it keeps
    /// one call, one destination.
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
            // Trimmed the same way `deployFolderProblem` trims before it
            // checks, so the folder that was validated is the folder that is
            // published into. The settings form saves what was typed, spaces
            // and all; passed on verbatim, " /Users/x/Sites" is a RELATIVE
            // path to the launcher and "/Users/x/Sites " is another folder
            // (GitHub issue #227).
            arguments.append(destination.path.trimmingCharacters(in: .whitespaces))
            return arguments
        }
        if destination.type != "cloudflare_pages" {
            arguments.append("--target")
            arguments.append("netlify")
            return arguments
        }
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
        let legacyURL: URL = legacyMarkerURL(forSection: sectionNumber, in: course)
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

    /// What a rollover's release of the website planned into its step, and
    /// what was brought in from the built output before it.
    struct PlannedRelease {

        // MARK: - Stored properties

        let release: SiteRelease

        let broughtIn: LegacyMarkerBroughtIn?
    }

    /// A test fixes the moment a rollover's kept names are stamped with, so
    /// it can lay a file at that name first. Nil in the app.
    nonisolated(unsafe) static var momentForATest: Date?

    /// THE ONE PLACE a rollover's step names what it sets aside (the review
    /// of U3b's fixes, round four, MEDIUM 1): a file's kept name is its own
    /// name with `.previous-<stamp>` before its `.json`, then `.2`, `.3`…
    /// after the stamp, the first that is neither on disk nor already
    /// chosen for this step. So no two ops of one step share a place, and
    /// no file already there stops a rollover.
    struct KeptNames {

        // MARK: - Stored properties

        /// Every place chosen for this step so far, by path.
        var chosen: Set<String> = []

        // MARK: - Functions

        /// The kept place for `url`, now chosen.
        mutating func choose(for url: URL, stamp: String) -> URL {
            let folder: URL = url.deletingLastPathComponent()
            let base: String = String(url.lastPathComponent.dropLast(".json".count)) + ".previous-" + stamp
            var number: Int = 1
            while true {
                var name: String = base + ".json"
                if number >= 2 {
                    name = base + ".\(number).json"
                }
                let candidate: URL = folder.appendingPathComponent(name)
                // `attributesOfItem` sees a link that leads nowhere too.
                let onDisk: Bool = (try? FileManager.default.attributesOfItem(atPath: candidate.path)) != nil
                if !chosen.contains(candidate.path) && !onDisk {
                    chosen.insert(candidate.path)
                    return candidate
                }
                number += 1
            }
        }
    }

    /// `releaseSite`, PLANNED into the rollover's ONE step instead of
    /// written (#899 U3b; #897 piece B, seams 1 and 3): each record a deploy
    /// reads becomes one `moveApart`, the section's records standing apart
    /// from the rest of the step as a GROUP, so an Undo after a deploy has
    /// filled a record's place leaves every record where it is and takes
    /// back the rest (Russell's ruling of 2026-11-19 on Q3; #959; the
    /// director's decision of 2026-11-20). A record that cannot be read is
    /// still pinned, as before. A Netlify record no deploy goes on with a
    /// site from (`netlifySiteADeployGoesOnWith` is nil) is not a website
    /// and is never moved: a deploy starts a new website from it before and
    /// after, whatever the step does (round four). Every kept name is chosen
    /// by `KeptNames`, which never gives a place twice or one on disk.
    ///
    /// The legacy marker in the built output is brought into the working
    /// folder first (`moveTheLegacyMarkerIn`), so the record a deploy reads
    /// is planned here like any other. Every STALE LEFTOVER brought in from
    /// the built output (`section<N>.from-built-output[.<k>].json`) is set
    /// aside here too, each a `setAside` op on its own, kept as
    /// `<its name>.previous-<stamp>.json`: never one of the records, never
    /// in `keptFiles` (a leftover is not a website the section was on, the
    /// review of U3b's fixes, LOW 4; its two halves are in `savedFiles`, so
    /// today's undo puts it back), and never decisive, so a leftover
    /// changed or missing by Undo or Redo is left and named and the records
    /// still go back (LOW 3). A leftover that cannot be set aside is left
    /// where it is: no deploy reads it. When the legacy record cannot be
    /// brought in, this throws that refusal and nothing has been planned or
    /// changed.
    static func planSiteRelease(
        forSection sectionNumber: Int,
        in course: Course,
        at moment: Date = Date(),
        into step: JournaledStep
    ) throws(LegacyMarkerNotMovedIn) -> PlannedRelease {
        let broughtIn: LegacyMarkerBroughtIn? = try moveTheLegacyMarkerIn(forSection: sectionNumber, in: course)
        let netlifySite: String? = netlifySiteADeployGoesOnWith(forSection: sectionNumber, in: course)
        let stampText: String = stamp(momentForATest ?? moment)
        var keptNames: KeptNames = KeptNames()
        var keptFiles: [String] = []
        var savedFiles: [AssistSavedFile] = []
        var stillPinned: [String] = []

        for destinationType in CourseConfiguration.knownDeployTargetTypes {
            guard let markerURL = firstDeployMarkerURL(
                forSection: sectionNumber, in: course, destinationType: destinationType
            ) else {
                continue
            }
            guard FileManager.default.fileExists(atPath: markerURL.path) else {
                continue
            }
            if destinationType == "netlify" {
                guard (try? Data(contentsOf: markerURL)) != nil else {
                    // Its bytes cannot be read at all: what it names cannot
                    // be told now, so it is still pinned (11-19 #4).
                    stillPinned.append(nameForTeacher(markerURL))
                    continue
                }
                if netlifySite == nil {
                    // Read, and no deploy goes on with a site from it (it
                    // does not parse, or it names no site): not the
                    // section's website, never moved and never pinned
                    // (round four, LOWs 2 and 3).
                    continue
                }
            }
            guard let contents = try? String(contentsOf: markerURL, encoding: .utf8) else {
                stillPinned.append(nameForTeacher(markerURL))
                continue
            }
            let keptURL: URL = keptNames.choose(for: markerURL, stamp: stampText)
            if !step.move(markerURL, to: keptURL, standsApart: true) {
                stillPinned.append(nameForTeacher(markerURL))
                continue
            }
            keptFiles.append(nameForTeacher(keptURL))
            savedFiles.append(AssistSavedFile(fileURL: markerURL, before: contents, after: nil))
            savedFiles.append(AssistSavedFile(fileURL: keptURL, before: nil, after: contents))
        }

        // The stale leftovers brought in from the built output (now or by
        // an earlier rollover), each set aside on its own. Nothing else is:
        // a file no deploy reads needs no moving (documentation 09).
        for leftover in leftoverURLs(.fromBuiltOutput, forSection: sectionNumber, in: course) {
            let keptURL: URL = keptNames.choose(for: leftover, stamp: stampText)
            guard let data = try? Data(contentsOf: leftover), step.setAside(leftover, to: keptURL) else {
                continue
            }
            // In today's undo with the records (never in `keptFiles`), so
            // Undo Last Change puts a leftover back where the step found it.
            let contents: String = String(decoding: data, as: UTF8.self)
            savedFiles.append(AssistSavedFile(fileURL: leftover, before: contents, after: nil))
            savedFiles.append(AssistSavedFile(fileURL: keptURL, before: nil, after: contents))
        }

        return PlannedRelease(
            release: SiteRelease(keptFiles: keptFiles, savedFiles: savedFiles, stillPinned: stillPinned),
            broughtIn: broughtIn
        )
    }

    /// The legacy Netlify marker `releaseSite` also moves: inside the BUILT
    /// output, `.merged_output/section<N>/.netlify_site.json` (see there).
    static func legacyMarkerURL(forSection sectionNumber: Int, in course: Course) -> URL {
        return course.directoryURL
            .appendingPathComponent(".merged_output")
            .appendingPathComponent("section\(sectionNumber)")
            .appendingPathComponent(".netlify_site.json")
    }

    /// Whether ANY marker `releaseSite` would try to move is on disk for the
    /// section: one per destination type, and the legacy one. A marker that
    /// cannot be read still counts, since `releaseSite` reports it as still
    /// pinned (#897 piece B, the plan review's amendment 12). The ONE test
    /// Classes ▸ Roll Over to a New Year…'s sheet asks before offering the
    /// website question, over the same URLs the release walks, so the sheet
    /// and the release cannot disagree about whether there is a website to
    /// keep or leave.
    static func sectionIsPinned(forSection sectionNumber: Int, in course: Course) -> Bool {
        for destinationType in CourseConfiguration.knownDeployTargetTypes {
            guard let markerURL = firstDeployMarkerURL(
                forSection: sectionNumber, in: course, destinationType: destinationType
            ) else {
                continue
            }
            if FileManager.default.fileExists(atPath: markerURL.path) {
                return true
            }
        }
        return FileManager.default.fileExists(atPath: legacyMarkerURL(forSection: sectionNumber, in: course).path)
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
    nonisolated static func nameForTeacher(_ markerURL: URL) -> String {
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

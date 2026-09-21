import Foundation

/// Locking a reference course's pages on disk, and unlocking them again.
///
/// A reference course is FROZEN, and frozen here means what a teacher would
/// mean by it: Finder shows the pages as **Locked**, Obsidian cannot save a
/// change to one, a terminal cannot overwrite or delete one, and neither can
/// an agent's own file tools without deliberately unlocking first.
///
/// **The mechanism is `chflags uchg` — the user-immutable flag — and only
/// that.** Read-only PERMISSIONS were measured and rejected twice over:
///
/// * `chmod a-w` does not stop a rename-over, which is how every serious
///   editor saves. The measurement replaced a page's contents at exit 0, and
///   `rm -f` deleted it. The immutable flag refuses both.
/// * Mode 444 also BREAKS THE PREVIEW BUILD, which is the finding that
///   settled it. The build copies each page into the build tree with
///   `shutil.copy2` (mode and flags travel), then rewrites the copy's
///   frontmatter — which is where `draft: true` becomes `publish: false`. On
///   the host bind mount the container's root does not get its usual
///   permission override, so the rewrite fails with one warning line per page
///   and the copy keeps `draft: true` and gains no `publish` key — and the
///   Explorer publishes anything that does not say `publish: false`. Every
///   page a teacher had HIDDEN would have appeared in the preview of their
///   frozen course. With the flag alone and the mode left at 644, the same
///   build writes `publish: false` correctly and the source is still refused
///   even to container root.
///
/// **Directories are never locked**, and that is measured too: with the course
/// folder locked, `ln -s … .merged_output` fails, and `BuildOutputLocation`
/// has to create that link inside the course folder on every reload. Locking
/// the folders would kill the preview a reference course exists to give.
///
/// **The honest limit, which belongs in the documentation and never in the
/// GUI.** With the folders unlocked a NEW file can still be added to one, and
/// anybody who means to can clear the flag. The lock stops every ordinary
/// edit, save, rename and delete of the material that is there — which is what
/// a teacher will meet — and it is a statement of intent rather than a
/// security boundary. In a cloud-synced folder it is weaker still: the file
/// provider models the locked bit itself and clears it while a file uploads,
/// so the lock is per-Mac and is re-asserted rather than assumed
/// (`ensureLocked`).
nonisolated enum ReferenceLock {

    // MARK: - Types

    /// What one pass of `ensureLocked` managed.
    struct Outcome: Equatable {

        // MARK: - Stored properties

        /// How many files this pass had to lock — zero on a course that was
        /// already frozen, which is the ordinary case.
        let locked: Int

        /// How many did not take: the flag was set and reading it back said
        /// it was not there.
        ///
        /// Not a failure to report to the teacher, and never a loop to retry
        /// in. It is what a synced folder does while a file uploads, and the
        /// answer is the next re-assertion rather than a wait — a delay
        /// chosen to let something settle is a guess that stops working on a
        /// slower machine.
        let didNotTake: Int

        // MARK: - Computed properties

        /// How many files the walk SAW — every content file in the course,
        /// after the never-locked names are taken out.
        let walked: Int

        /// How many of those are locked when the pass finishes.
        let lockedAfterwards: Int

        // MARK: - Computed properties

        /// True when there was nothing to do, so nothing is said anywhere.
        var isQuiet: Bool {
            return locked == 0 && didNotTake == 0
        }

        /// True when every file the walk saw is locked.
        ///
        /// The check the old `Outcome` could not make. It is not a promise
        /// that the WALK was complete — nothing inside this type can know
        /// that — which is why `walked` is carried too, and why the test that
        /// pins the walk counts files on disk rather than asking here.
        var everythingWalkedIsLocked: Bool {
            return lockedAfterwards == walked
        }
    }

    // MARK: - Stored properties

    /// Names never locked, wherever they appear inside a course.
    ///
    /// Each one is here because something has to WRITE it while the course is
    /// open, and a locked copy would break a thing a reference course is
    /// promised to do:
    ///
    /// * `course_config.json` — the school year can be changed later, and the
    ///   build's own preflight rewrites this file whenever a folder list
    ///   changes.
    /// * `course_config.backup.json` — written beside it by that same
    ///   preflight, with `shutil.copy2`, which would raise on a locked
    ///   destination.
    /// * `.obsidian` — Obsidian writes `workspace.json` the moment a vault is
    ///   opened, and opening the course in Obsidian is the whole point of
    ///   keeping it.
    /// * `.merged_output` — the built website. It is a symlink out of the
    ///   folder, and it is rebuilt rather than kept.
    /// * `course_config.json.tmp` — the half of that same atomic write that
    ///   exists only between `open()` and `os.replace()`. A build interrupted
    ///   between the two leaves it on disk; locking it would mean every later
    ///   preflight failed both its write AND its cleanup, so that course's
    ///   settings could never be reconciled again.
    /// * `.DS_Store` — Finder's own bookkeeping. Nothing a teacher wrote.
    static let neverLocked: Set<String> = [
        "course_config.json",
        "course_config.backup.json",
        "course_config.json.tmp",
        ".obsidian",
        ".merged_output",
        ".DS_Store",
    ]

    /// Suffixes never locked, whatever the rest of the name is.
    ///
    /// Anything half-written. `SectionPublishState` already ignores the same
    /// suffix when it fingerprints a section, for the same reason: a `.tmp`
    /// is not a teacher's page, it is the middle of somebody's atomic write —
    /// and locking the middle of one is how a writer ends up unable to finish
    /// OR to clean up.
    static let neverLockedSuffixes: [String] = [".tmp"]

    // MARK: - Functions

    /// Locks every content file in the course, and reports what it had to do.
    ///
    /// Idempotent and cheap: a file that is already locked costs one `stat`
    /// and is not touched. Safe to call on any course — a course that is not
    /// kept for reference is left alone entirely, so callers do not each have
    /// to remember to ask.
    @MainActor
    @discardableResult
    static func ensureLocked(_ course: Course) -> Outcome {
        guard course.isKeptForReference else {
            return Outcome(locked: 0, didNotTake: 0, walked: 0, lockedAfterwards: 0)
        }
        return ReferenceLock.lock(courseDirectory: course.directoryURL)
    }

    /// The same, OFF the main actor — for the re-assertion points a teacher
    /// is waiting on: the folder being read, a course being selected, a
    /// preview starting, Obsidian opening.
    ///
    /// Measured on this Mac, 1,220 files: **~24 ms** for a pass with nothing
    /// to do and **~80 ms** for one that locks everything. Below the
    /// perception threshold for one course and not free for four, and
    /// `reloadCourses()` runs after most sheets — so the walk goes to the
    /// cooperative pool and the teacher's click never waits for a `stat` per
    /// file.
    ///
    /// `Task.detached`, not `DispatchQueue`: structured concurrency, no
    /// queue, and nothing that waits for a guessed interval. The trail line
    /// hops back to the main actor, because that is where the store is
    /// replaced by a test.
    ///
    /// Nothing awaits this deliberately. It is an ASSERTION that the course
    /// is what it says it is, not a step in anything — and the refusal to
    /// deploy has never depended on it.
    @MainActor
    static func ensureLockedInBackground(_ course: Course) {
        guard course.isKeptForReference else {
            return
        }
        let directoryURL: URL = course.directoryURL
        let displayCode: String = course.displayCode
        Task {
            let outcome: Outcome = await ReferenceLock.locking(courseDirectory: directoryURL)
            if outcome.isQuiet {
                return
            }
            ActivityTrail.note(
                .referenceCoursePagesLockedAgain,
                ReferenceCourseUpkeep.trailLine(for: outcome, course: displayCode)
            )
        }
    }

    /// The walk, off the caller's actor.
    ///
    /// **`@concurrent` is load-bearing, and it is measured rather than
    /// decorative.** This target builds with `SWIFT_APPROACHABLE_CONCURRENCY`,
    /// which turns on `NonisolatedNonsendingByDefault` — and under that rule a
    /// plain `nonisolated async` function runs on its CALLER's actor. So
    /// marking this `async` and leaving it at that would have kept every
    /// `stat` on the main actor while reading as though it did not, which is
    /// the worst kind of fix. `@concurrent` is what actually leaves.
    /// `testTheLockWalkDoesNotRunOnTheMainThread` proves it rather than
    /// trusting the annotation.
    ///
    /// Structured concurrency throughout: no `DispatchQueue`, and nothing
    /// that waits for a guessed interval.
    @concurrent
    static func locking(courseDirectory: URL) async -> Outcome {
        // `Thread.isMainThread` is unavailable from an async context (it is
        // the question Swift wants asked with an isolation annotation
        // instead), so the thread is read by the synchronous worker below —
        // which is where the `stat` per file actually happens, and therefore
        // the honest place to ask.
        return ReferenceLock.lock(courseDirectory: courseDirectory)
    }

    /// Whether the last off-actor pass really ran off the main thread.
    ///
    /// Written by `locking` and read by one test. A seam rather than an
    /// assertion in the product, for the reason every other override here is
    /// one: the thing worth pinning is a fact about the running program, and
    /// an annotation that stops working silently is exactly what this feature
    /// has already been bitten by once.
    nonisolated(unsafe) static var lastPassRanOnTheMainThread: Bool?

    /// The same, for a folder rather than a loaded course — what the copier
    /// has in hand as the last step of making one.
    @discardableResult
    static func lock(courseDirectory: URL) -> Outcome {
        ReferenceLock.lastPassRanOnTheMainThread = Thread.isMainThread
        var locked: Int = 0
        var didNotTake: Int = 0
        var walked: Int = 0
        var alreadyLocked: Int = 0
        for fileURL in ReferenceLock.contentFiles(in: courseDirectory) {
            walked += 1
            if ReferenceLock.isLocked(fileURL) {
                alreadyLocked += 1
                continue
            }
            ReferenceLock.set(immutable: true, at: fileURL)
            // ASSERTED, then VERIFIED. `setAttributes` returning without
            // throwing is not the same as the file being locked: in an iCloud
            // Drive folder the file provider reconciles the locked bit off
            // again about a second after an upload starts, with no error
            // anywhere. Reading it back is the only honest answer.
            if ReferenceLock.isLocked(fileURL) {
                locked += 1
            } else {
                didNotTake += 1
            }
        }
        return Outcome(
            locked: locked,
            didNotTake: didNotTake,
            // Counted rather than assumed. A walk that silently skips part of
            // the course used to report a perfectly healthy `locked` and
            // `didNotTake: 0` — the count it had WALKED was the thing nobody
            // was keeping, so the one number that could have shown the defect
            // did not exist. `lockedAfterwards` is what every file the walk
            // saw ended up as; a caller comparing it with `walked` can say
            // whether the pass actually covered the course.
            walked: walked,
            lockedAfterwards: alreadyLocked + locked
        )
    }

    /// Unlocks everything in the course, so it can be removed or restored
    /// over.
    ///
    /// Measured: `FileManager.removeItem` and `rm -rf` both REFUSE a locked
    /// tree ("Operation not permitted", "Directory not empty"), so every
    /// removal path has to come through here first.
    static func unlock(courseDirectory: URL) {
        for fileURL in ReferenceLock.contentFiles(in: courseDirectory) {
            ReferenceLock.set(immutable: false, at: fileURL)
        }
    }

    /// Clears the lock on something copied OUT of a reference course.
    ///
    /// The flag travels: `FileManager.copyItem`, `cp -p`, `ditto` and
    /// `shutil.copy2` all carry it, and only a plain `cp -R` or a zip round
    /// trip loses it. So a page copied into the course a teacher is teaching
    /// arrives locked unless somebody clears it, and a page they cannot edit
    /// with no explanation reads as "the app is broken".
    ///
    /// Takes a file or a whole tree, and clears the folders too: a folder
    /// copied out could carry the flag even though this never sets one on a
    /// folder.
    static func clearLock(at url: URL) {
        ReferenceLock.set(immutable: false, at: url)
        let fileManager: FileManager = FileManager.default
        guard let walker = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else {
            return
        }
        for case let child as URL in walker {
            ReferenceLock.set(immutable: false, at: child)
        }
    }

    /// The refusal for a course folder that is kept for reference, or nil
    /// when it is an ordinary one.
    ///
    /// Asked of the config ON DISK, for the callers that hold a folder rather
    /// than a loaded `Course` — the folder renamer, and anything else reached
    /// from a path. `nonisolated` so those callers need not be main-actor.
    nonisolated static func frozenCourseOnDisk(at courseDirectory: URL) -> ReferenceCourseIsFrozen? {
        let configURL: URL = courseDirectory.appendingPathComponent("course_config.json")
        guard let data = try? Data(contentsOf: configURL),
              let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              decoded["kept_for_reference"] as? Bool == true else {
            return nil
        }
        let recorded: String = (decoded["course_code"] as? String) ?? ""
        if recorded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ReferenceCourseIsFrozen(displayCode: courseDirectory.lastPathComponent)
        }
        return ReferenceCourseIsFrozen(displayCode: recorded)
    }

    /// Whether this file carries the user-immutable flag RIGHT NOW.
    ///
    /// Asked of `FileManager`, never of `URL.resourceValues`, and that is not
    /// a preference: a `URL` CACHES the resource values it has been asked
    /// for, so the natural spelling answers with the value from before the
    /// flag was set. Measured here the expensive way — locking reported zero
    /// files locked and three that "did not take", on files that were
    /// perfectly well locked, because every answer came out of the cache. A
    /// verify step that reads a cache is not a verify step.
    static func isLocked(_ url: URL) -> Bool {
        let attributes: [FileAttributeKey: Any]? = try? FileManager.default
            .attributesOfItem(atPath: url.path)
        guard let stored = attributes?[FileAttributeKey.immutable] as? NSNumber else {
            return false
        }
        return stored.boolValue
    }

    // MARK: - Private helpers

    /// Every file inside the course that the lock applies to: no directories,
    /// no symlinks, nothing under `neverLocked`.
    private static func contentFiles(in courseDirectory: URL) -> [URL] {
        let fileManager: FileManager = FileManager.default
        guard let walker = fileManager.enumerator(
            at: courseDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else {
            return []
        }

        var found: [URL] = []
        for case let child as URL in walker {
            if ReferenceLock.isNeverLocked(child.lastPathComponent) {
                // A skipped FOLDER takes everything inside it: `.obsidian`
                // holds plugins and themes, and the point is that Obsidian
                // may write in there freely.
                //
                // **Only when it IS a folder**, and that word is the whole
                // defect this line used to carry. `skipDescendants()` asked
                // of a FILE — `course_config.json`, which every course has at
                // its top level — is applied by the enumerator to the next
                // directory it has not descended into yet, so the folder
                // AFTER it was never walked and never locked. Measured on a
                // real course: 842 of 934 files walked, and the 92 missed
                // included 27 real pages. Which folder was lost depended on
                // readdir order, so it MOVED between passes — which is why
                // the course came out mostly locked and never entirely
                // locked, and why nothing looked wrong.
                let skipped: URLResourceValues? = try? child.resourceValues(
                    forKeys: [.isDirectoryKey]
                )
                if skipped?.isDirectory == true {
                    walker.skipDescendants()
                }
                continue
            }
            let values: URLResourceValues? = try? child.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            // A symlink is never locked: `.merged_output` is one, and setting
            // the flag through a link would set it on whatever it points at.
            if values?.isSymbolicLink == true {
                continue
            }
            if values?.isDirectory == true {
                continue
            }
            found.append(child)
        }
        return found
    }

    /// Whether this name is one the lock never touches.
    static func isNeverLocked(_ name: String) -> Bool {
        if ReferenceLock.neverLocked.contains(name) {
            return true
        }
        for suffix in ReferenceLock.neverLockedSuffixes where name.hasSuffix(suffix) {
            return true
        }
        return false
    }

    private static func set(immutable: Bool, at url: URL) {
        try? FileManager.default.setAttributes(
            [FileAttributeKey.immutable: immutable], ofItemAtPath: url.path
        )
    }
}

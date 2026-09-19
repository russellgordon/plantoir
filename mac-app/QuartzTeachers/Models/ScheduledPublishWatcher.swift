import AppKit
import Foundation

/// Watches the folder where a scheduled run writes down how it went, so the
/// notice appears on the section the teacher is already looking at.
///
/// A scheduled publish runs in a separate process, so there is no in-app event
/// to hang the notice on — **the file is the event**. Until this existed, both
/// places that read the record read it only when they were built: the section's
/// `onAppear` and the sidebar row's own render. A teacher who stayed on the
/// section while the run finished was told nothing until they clicked up to the
/// course and back down again.
///
/// **One watcher for the whole app.** The record folder hangs off the HOME
/// folder alone (`ScheduledPublishOutcome.directory(inHomeFolder:)`), not off a
/// working folder, so one watcher serves every window, every course and every
/// section. A watcher per window would be several watchers and several counters
/// for one global truth, and a second window's sidebar would go stale.
///
/// **Nothing here reads a record and nothing here writes one.** The counter
/// carries no payload: every observer re-reads its OWN record after any change.
/// Two sections finishing in the same millisecond therefore produce one bump and
/// two correct notices, and a coalesced event is never a lost one. The record
/// files themselves stay strictly READ-ONLY — an earlier draft of the notice
/// appended a "noted" marker to the record, which re-dated an overnight problem
/// to the morning somebody read it (`ScheduledPublishOutcome.noteOnTrail`). The
/// only thing this type creates is the containing FOLDER, which no record's
/// modification date depends on.
///
/// **Why a kernel file-system source rather than a timer.** Polling is a guessed
/// number: fast enough to feel live is a filesystem read every second for ever,
/// against an event that happens once a day; slow enough to be polite is not
/// "while the teacher is looking". The thing being waited for — a file arriving
/// — is directly observable, so it is observed.
@MainActor
@Observable
final class ScheduledPublishWatcher {

    // MARK: - Types

    /// What one change was.
    ///
    /// A `DispatchSource.FileSystemEvent` is not `Sendable`, and the difference
    /// that matters to a reader is only ever this one: something changed, or
    /// the thing being watched is not there any more — in which case the watch
    /// on it is now deaf and has to be made again.
    enum Change: Sendable {
        case somethingChanged
        case theWatchedThingWentAway
    }

    // MARK: - Stored properties

    /// The one the app uses.
    ///
    /// `init` is deliberately inert — it stores a URL and touches nothing — so
    /// that instantiating this in the test suite (where real windows are built,
    /// and the sidebar's body reaches for `shared`) cannot reach into the
    /// teacher's real Application Support. Everything that touches the disk is
    /// in `start()`, and `start()` is called once, from `AppDelegate`, behind
    /// the suite's own guard.
    static let shared: ScheduledPublishWatcher = ScheduledPublishWatcher(
        folder: ScheduledPublishOutcome.directory(
            inHomeFolder: FileManager.default.homeDirectoryForCurrentUser
        )
    )

    /// Moves every time something about a record changes, and once whenever the
    /// app comes back to the front.
    ///
    /// Nothing reads its VALUE. A view names it so that SwiftUI re-reads the
    /// disk when it moves — the same trick `scheduleGeneration` plays for the
    /// clock beside the sidebar's badge. It used to live on `WorkspaceModel`,
    /// bumped only by Dismiss; it moved here so that the section's band and the
    /// sidebar's warning move together, in BOTH directions, from one counter
    /// for one global folder.
    private(set) var generation: Int = 0

    /// The folder being watched.
    private let folder: URL

    /// The one task this watcher owns: the folder watch and the
    /// app-came-back watch are children of it, so cancelling it stops both.
    @ObservationIgnored private var watchTask: Task<Void, Never>?

    /// A task per record that exists but is not finished being written, keyed
    /// by path. See `watchAnyHalfWrittenRecords()` — these are what make a job
    /// scheduled by an OLDER build show its notice live too.
    @ObservationIgnored private var halfWrittenRecordWatches: [String: Task<Void, Never>] = [:]

    // MARK: - Initializer

    init(folder: URL) {
        self.folder = folder
    }

    deinit {
        watchTask?.cancel()
        for (_, task) in halfWrittenRecordWatches {
            task.cancel()
        }
    }

    // MARK: - Functions

    /// Begin watching. Calling it again does nothing.
    ///
    /// **Both watches are armed HERE, before this function returns**, and the
    /// consuming task only reads what they deliver. `AsyncStream`'s build
    /// closure runs during its `init`, so a record moved into place — or an
    /// activation posted — the instant after this call cannot be missed. A
    /// watcher that armed itself inside its task would lose whatever happened
    /// in between, which in the app is a run finishing during launch and in the
    /// suite is every test needing a sleep to paper over it.
    func start() {
        guard watchTask == nil else {
            return
        }
        makeTheFolderIfItIsNotThereYet()
        let folderChanges: AsyncStream<Change> = Self.changes(
            at: folder, watching: [.write, .delete, .rename]
        )
        let comingBack: AsyncStream<Void> = Self.appComingBackToTheFront()
        // A record already half written when the app started — a run that was
        // interrupted mid-write, or one in flight during launch — gets its own
        // watch straight away rather than waiting for a change it has already
        // made.
        watchAnyHalfWrittenRecords()
        watchTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await self?.watchTheFolder(startingWith: folderChanges)
                }
                group.addTask {
                    await self?.reRead(whenever: comingBack)
                }
            }
        }
    }

    /// Stop watching and let go of the folder.
    ///
    /// The app never calls this — it watches for as long as it runs — but a
    /// test that made its own watcher against a temporary folder should not
    /// leave a file descriptor open for the rest of the suite.
    func stop() {
        watchTask?.cancel()
        watchTask = nil
        for (path, task) in halfWrittenRecordWatches {
            task.cancel()
            halfWrittenRecordWatches.removeValue(forKey: path)
        }
    }

    /// Say that the answer on disk may have changed.
    ///
    /// Called by the watch, and by the Dismiss button in the section view: a
    /// button must not wait on the filesystem to tell the sidebar what the
    /// teacher just did, and the suite runs with no watcher started at all.
    func noteChanged() {
        generation += 1
    }

    /// Watch the folder, and re-arm if the folder itself goes away.
    ///
    /// A vnode source is a watch on an OPEN FILE DESCRIPTOR, so a folder that
    /// is deleted and recreated leaves the old descriptor deaf — measured: a
    /// record written into a recreated folder produced **0 events** on the
    /// original descriptor. The re-arm is therefore load-bearing rather than
    /// defensive. Every attempt at it is caused by an EVENT, which a dead watch
    /// cannot deliver, so this cannot become a polling loop: there is no timer
    /// here and no sleep.
    private func watchTheFolder(startingWith firstWatch: AsyncStream<Change>) async {
        var changes: AsyncStream<Change> = firstWatch
        while !Task.isCancelled {
            var theFolderWentAway: Bool = false
            for await change in changes {
                if change == .theWatchedThingWentAway {
                    theFolderWentAway = true
                    break
                }
                watchAnyHalfWrittenRecords()
                noteChanged()
            }
            if !theFolderWentAway {
                // The stream ended without the folder being deleted, which
                // means the folder could not be opened at all. Stop here: a
                // retry without an event to cause it would be a spin.
                //
                // Say plainly what that costs, because the watch does NOT come
                // back afterwards — `watchTask` stays non-nil, so `start()`
                // does nothing more. What still works is the READING: the app
                // coming back to the front re-reads, and so does opening the
                // section. A teacher is then exactly where they were before
                // this existed, which is the right floor for a case that needs
                // the folder to become unopenable between making it and
                // opening it.
                return
            }
            makeTheFolderIfItIsNotThereYet()
            changes = Self.changes(at: folder, watching: [.write, .delete, .rename])
            // Say so only NOW, with the new watch already armed. Announcing the
            // folder's disappearance first would invite every observer to look
            // at a folder nothing was watching yet, and a record written in
            // that gap would be seen by nobody until the app was next brought
            // to the front.
            watchAnyHalfWrittenRecords()
            noteChanged()
        }
    }

    /// Re-read when the app comes back to the front.
    ///
    /// Belt and braces, and it costs nothing standing: it covers a watch that
    /// could not start, a record restored from a backup, and — the commonest
    /// human case by far — a teacher coming back the next morning to an app
    /// that was open all night.
    ///
    /// The app-level notification rather than `scenePhase`, because `scenePhase`
    /// is per scene in a multi-window app and would need wiring into every view,
    /// and because this is already the app's idiom for exactly this refresh
    /// (`SectionDetailView` watches the same notification for the " — Edited"
    /// marker).
    private func reRead(whenever comingBack: AsyncStream<Void>) async {
        for await _ in comingBack {
            watchAnyHalfWrittenRecords()
            noteChanged()
        }
    }

    /// Every time the app is brought back to the front, as an `AsyncStream`.
    ///
    /// Its own stream rather than a block observer left registered for ever:
    /// the observer is removed when the stream ends, so a watcher that stops —
    /// which in practice means a test's watcher — leaves nothing behind. It
    /// also arms synchronously, which is what lets `start()` promise that an
    /// activation straight afterwards is not lost.
    nonisolated static func appComingBackToTheFront() -> AsyncStream<Void> {
        return AsyncStream<Void>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            // `nonisolated(unsafe)` for the token alone: it is handed straight
            // back to the notification centre, which is thread-safe, and it is
            // touched nowhere else.
            nonisolated(unsafe) let token: any NSObjectProtocol =
                NotificationCenter.default.addObserver(
                    forName: NSApplication.didBecomeActiveNotification,
                    object: nil,
                    queue: nil
                ) { _ in
                    continuation.yield(())
                }
            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(token)
            }
        }
    }

    /// Make sure the folder exists, so there is something to open.
    ///
    /// Harmless: the wrapper `mkdir -p`s it before writing anyway, and creating
    /// a directory changes no record's modification date, so the read-only rule
    /// above still holds.
    private func makeTheFolderIfItIsNotThereYet() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Watch, file by file, any record that is there but cannot be read yet.
    ///
    /// **This is what a job scheduled by an older build needs.** A folder watch
    /// fires when an entry is created, removed or renamed; it does NOT fire when
    /// an existing file grows. A wrapper that writes its record with two `echo`s
    /// therefore delivers exactly one event, carrying an empty file, and the
    /// line that completes the record produces no event at all — measured 0 out
    /// of 40 (see `ScheduledPublishOutcome.partialRecordURL`). Wrappers are
    /// written to disk when the section is SCHEDULED and are not rewritten
    /// until it is scheduled again, so a job installed by an older build still
    /// writes in two steps however this app now generates them.
    ///
    /// A vnode source on the FILE does see that second write. So: for any record
    /// that exists and does not parse, watch the file itself until it does —
    /// an event, not a timer, and it goes away the moment the record is
    /// readable or gone.
    ///
    /// REJECTED: rewriting every pending job's wrapper at launch. It is more
    /// code, it edits files the teacher's launchd is about to run (including,
    /// unavoidably, one that may be running at that moment), and it would fix
    /// only wrappers this app wrote — where this fixes any two-step writer,
    /// including a record dragged in from a backup.
    private func watchAnyHalfWrittenRecords() {
        let contents: [URL] = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        )) ?? []
        for url in contents {
            if url.pathExtension != "txt" {
                continue
            }
            watchIfItIsHalfWritten(url)
        }
    }

    /// Watch one record until it can be read.
    private func watchIfItIsHalfWritten(_ url: URL) {
        let path: String = url.path
        if halfWrittenRecordWatches[path] != nil {
            return
        }
        // ARM FIRST, LOOK SECOND, and the order is the whole correctness
        // argument: the write that completes a record is the only event that
        // record will ever produce, so a watch armed after it has landed waits
        // for ever. Arming first means the look below is the only other way the
        // completion can be discovered, and one of the two always sees it —
        // unless a record that is ALREADY being waited on is unlinked and
        // replaced by another unreadable one within a single turn, in which
        // case this watch is left on the old file and the app coming back to
        // the front, or the section being opened, is what carries it. That
        // needs a record left half written by a killed run AND a second run
        // compressing its `rm` and its first `echo` into one event window; the
        // wrapper puts a whole build and publish between the two, measured as
        // two separate turns. Re-arming from the tail of the watching task is
        // NOT the fix: when the file cannot be opened the stream finishes at
        // once, so the tail would re-arm immediately and spin.
        //
        // Letting go of the stream when the record turns out to be readable
        // costs nothing: measured, an `AsyncStream` that is never iterated runs
        // its termination handler when it is released, which cancels the source
        // and closes the descriptor. The caller says so on the counter a moment
        // later, so nothing is lost by returning here in silence.
        let changes: AsyncStream<Change> = Self.changes(
            at: url, watching: [.write, .extend, .delete, .rename]
        )
        if ScheduledPublishOutcome.record(at: url) != nil {
            return
        }
        halfWrittenRecordWatches[path] = Task { [weak self] in
            for await _ in changes {
                guard let self else {
                    return
                }
                self.noteChanged()
                if ScheduledPublishOutcome.record(at: url) != nil {
                    break
                }
                if !FileManager.default.fileExists(atPath: path) {
                    break
                }
            }
            self?.stopWatchingHalfWrittenRecord(at: path)
        }
    }

    /// Forget a half-written record we are no longer waiting on.
    private func stopWatchingHalfWrittenRecord(at path: String) {
        halfWrittenRecordWatches.removeValue(forKey: path)
    }

    /// Every change to a file or a folder, as an `AsyncStream`.
    ///
    /// **The one permitted use of GCD in this app, and this comment is the
    /// permission.** Russell's rule forbids Dispatch for deferring work, for
    /// hopping to the main thread and for waiting before doing something; none
    /// of those happens here. `DispatchSource.makeFileSystemObjectSource` is the
    /// kernel's own file-system event source and a `DispatchQueue` is a required
    /// parameter of it — the queue is the delivery channel, not somewhere work
    /// is thrown. Nothing is deferred, nothing is delayed, and the events are
    /// consumed with `for await` on the main actor. Everything else about this
    /// file is structured concurrency.
    ///
    /// What was rejected, and why none of it is smaller:
    /// - `NSFilePresenter`/`NSFileCoordinator` observes COORDINATED writes. The
    ///   record is moved into place by `/bin/mv` from a shell script, which is
    ///   not one, so it would never fire at all. That is a fact rather than a
    ///   preference.
    /// - `FSEventStream` takes a `DispatchQueue` too, and adds a C callback, an
    ///   `Unmanaged` context and a coalescing delay: more Dispatch, three times
    ///   the code, later events.
    /// - A raw `kevent()` loop needs a thread of its own blocked in the kernel,
    ///   which is further from structured concurrency rather than closer.
    ///
    /// The source is ARMED BEFORE THIS FUNCTION RETURNS: `AsyncStream`'s build
    /// closure runs during its `init`, so a record written the instant after the
    /// call cannot be missed. `.bufferingNewest(1)` because every element means
    /// the same thing — "look again" — so coalescing is free and the buffer
    /// cannot grow. The descriptor is closed in the source's cancel handler, and
    /// the stream's termination cancels the source, so ending the `for await`
    /// (or cancelling the task around it) closes everything.
    nonisolated static func changes(
        at url: URL,
        watching events: DispatchSource.FileSystemEvent
    ) -> AsyncStream<Change> {
        return AsyncStream<Change>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let descriptor: Int32 = open(url.path, O_EVTONLY)
            if descriptor < 0 {
                continuation.finish()
                return
            }
            let deliveries: DispatchQueue = DispatchQueue(
                label: "ca.russellgordon.Plantoir.scheduled-publish-record-changes"
            )
            let source: any DispatchSourceFileSystemObject =
                DispatchSource.makeFileSystemObjectSource(
                    fileDescriptor: descriptor,
                    eventMask: events,
                    queue: deliveries
                )
            source.setEventHandler {
                let happened: DispatchSource.FileSystemEvent = source.data
                if happened.contains(.delete) || happened.contains(.rename) {
                    continuation.yield(.theWatchedThingWentAway)
                } else {
                    continuation.yield(.somethingChanged)
                }
            }
            source.setCancelHandler {
                close(descriptor)
            }
            continuation.onTermination = { _ in
                source.cancel()
            }
            source.resume()
        }
    }
}

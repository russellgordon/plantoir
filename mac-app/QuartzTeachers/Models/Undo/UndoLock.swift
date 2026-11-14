import Foundation

/// The list's one exclusive lock: `flock(LOCK_EX)` on `undo/.lock`.
///
/// `flock` belongs to the open file, at the BSD level, so the app, an
/// `--mcp-stdio` process, a scheduled run and a second copy of the app all
/// exclude each other through it, and so do two `UndoJournal` objects in one
/// process (each opens the file itself). The kernel lets it go when the
/// holder dies, so a crash can never leave the list locked.
///
/// **The contract names the rule, not this mechanism** (`undo.rule`): one
/// exclusive lock for every change to the list, the journal read fresh inside
/// it, held only for journal events and never while a change is applied.
/// Windows meets the same rule with an exclusive open of the same file
/// (`FileShare.None`), measured by its director on #899.
///
/// It is taken without blocking and retried at a deliberate pace for a
/// bounded time, rather than waited on with a blocking `flock`: the holder
/// only ever holds it for a few appends, so a lock that stays busy for two
/// seconds is a process that has stopped, and a writer on the main actor
/// must not wait on it for ever.
nonisolated final class UndoLock {

    // MARK: - Stored properties

    private var descriptor: Int32

    /// How long between tries: half a millisecond, doubling to two.
    ///
    /// Kept short on purpose, and measured: with the longest pause at a
    /// tenth of a second, two writers each making 200 steps as fast as they
    /// could starved one another, and one gave up after its two seconds
    /// (the U1 harness, two writers in one process). A holder lets go within
    /// a few milliseconds, so a waiter that looks again within two catches it.
    static let firstPause: Double = 0.0005
    static let longestPause: Double = 0.002

    // MARK: - Initializer

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    // MARK: - Functions

    /// Takes the lock, trying for at most `seconds`.
    static func take(at url: URL, waitingAtMost seconds: Double) throws -> UndoLock {
        let descriptor: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return -1
            }
            return open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        }
        if descriptor < 0 {
            throw UndoJournalError.couldNotOpenTheLock(errno)
        }
        let deadline: Date = Date().addingTimeInterval(seconds)
        var pause: Double = firstPause
        while true {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                return UndoLock(descriptor: descriptor)
            }
            let failure: Int32 = errno
            if failure != EWOULDBLOCK && failure != EINTR {
                close(descriptor)
                throw UndoJournalError.couldNotOpenTheLock(failure)
            }
            if Date() >= deadline {
                close(descriptor)
                throw UndoJournalError.lockBusy
            }
            var interval: timespec = timespec(tv_sec: 0, tv_nsec: Int(pause * 1_000_000_000))
            nanosleep(&interval, nil)
            pause = min(pause * 2, longestPause)
        }
    }

    func release() {
        if descriptor < 0 {
            return
        }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    deinit {
        release()
    }
}

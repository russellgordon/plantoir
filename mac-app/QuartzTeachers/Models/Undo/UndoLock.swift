import Foundation

/// The list's one exclusive lock: `flock(LOCK_EX)` on `undo/.lock`.
///
/// `flock` belongs to the open file, so the app, an `--mcp-stdio` process, a
/// scheduled run and two `UndoJournal` objects in one process all exclude
/// each other through it, and the kernel lets it go when the holder dies.
/// The contract names the rule, not this mechanism (`undo.rule.oneLock`).
///
/// **How it is waited for.** First a try that does not block; when the lock
/// is held, a BLOCKING `flock` on a thread of its own, which the kernel
/// queues, while the caller waits on a condition for that thread's answer or
/// its deadline, whichever comes first. Nothing spins and nothing sleeps for
/// a guessed time: the caller is woken by the grant itself. A wait that runs
/// out abandons the thread's request, and the thread lets the lock go the
/// moment it is granted.
///
/// *Rejected, measured* (the core review, 2026-11-13): a non-blocking poll
/// with a pause, which starved waiters (8 processes making 200 steps each:
/// 663 of 1,600 gave up), and a pause that grew to a tenth of a second,
/// which was worse.
///
/// **In shadow** a wait is a tenth of the live one, and once a shadow wait
/// has run out in this process (a holder that has stopped), later shadow
/// attempts only try once, without waiting, until the lock is next taken:
/// a stuck outside-assistant process can cost one publish a short wait, not
/// every publish.
nonisolated final class UndoLock {

    // MARK: - Stored properties

    private var descriptor: Int32

    /// Folders whose lock a shadow wait last gave up on.
    nonisolated(unsafe) private static var shadowGaveUp: Set<String> = []

    private static let guardLock: NSLock = NSLock()

    // MARK: - Initializer

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    // MARK: - Functions

    /// Takes the lock, waiting at most `seconds`.
    static func take(at url: URL, waitingAtMost seconds: Double, inShadow: Bool = false) throws -> UndoLock {
        let key: String = url.standardizedFileURL.path
        let descriptor: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return -1
            }
            return open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        }
        if descriptor < 0 {
            throw UndoJournalError.couldNotOpenTheLock(errno)
        }
        if UndoLock.tryOnce(descriptor) {
            UndoLock.noteTaken(key)
            return UndoLock(descriptor: descriptor)
        }
        var wait: Double = seconds
        if inShadow && UndoLock.shadowHasGivenUp(key) {
            wait = 0
        }
        if wait <= 0 {
            close(descriptor)
            throw UndoJournalError.lockBusy
        }
        let request: UndoLockRequest = UndoLockRequest(descriptor: descriptor)
        let thread: Thread = Thread {
            request.blockUntilGranted()
        }
        thread.start()
        if request.waitForGrant(until: Date().addingTimeInterval(wait)) {
            UndoLock.noteTaken(key)
            return UndoLock(descriptor: descriptor)
        }
        if inShadow {
            guardLock.lock()
            shadowGaveUp.insert(key)
            guardLock.unlock()
        }
        throw UndoJournalError.lockBusy
    }

    static func tryOnce(_ descriptor: Int32) -> Bool {
        var result: Int32 = flock(descriptor, LOCK_EX | LOCK_NB)
        while result != 0 && errno == EINTR {
            result = flock(descriptor, LOCK_EX | LOCK_NB)
        }
        return result == 0
    }

    static func noteTaken(_ key: String) {
        guardLock.lock()
        shadowGaveUp.remove(key)
        guardLock.unlock()
    }

    static func shadowHasGivenUp(_ key: String) -> Bool {
        guardLock.lock()
        let gaveUp: Bool = shadowGaveUp.contains(key)
        guardLock.unlock()
        return gaveUp
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

/// One blocking request for the lock, answered on a condition.
nonisolated final class UndoLockRequest: @unchecked Sendable {

    // MARK: - Stored properties

    private let descriptor: Int32

    private let condition: NSCondition = NSCondition()

    private var granted: Bool = false

    private var abandoned: Bool = false

    /// The blocking request came back, granted or not.
    private var finished: Bool = false

    // MARK: - Initializer

    init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    // MARK: - Functions

    /// On the request's own thread: block in the kernel's queue.
    func blockUntilGranted() {
        var result: Int32 = flock(descriptor, LOCK_EX)
        while result != 0 && errno == EINTR {
            result = flock(descriptor, LOCK_EX)
        }
        condition.lock()
        if abandoned {
            // The caller has gone: let the lock go at once, and the file.
            condition.unlock()
            if result == 0 {
                flock(descriptor, LOCK_UN)
            }
            close(descriptor)
            return
        }
        granted = result == 0
        finished = true
        condition.signal()
        condition.unlock()
    }

    /// On the caller's thread: true when granted by the deadline. False
    /// abandons the request; the request's thread then owns the descriptor.
    func waitForGrant(until deadline: Date) -> Bool {
        condition.lock()
        while !finished {
            if !condition.wait(until: deadline) {
                break
            }
        }
        if granted {
            condition.unlock()
            return true
        }
        if finished {
            // The kernel refused outright: the descriptor is still ours.
            condition.unlock()
            close(descriptor)
            return false
        }
        abandoned = true
        condition.unlock()
        return false
    }
}

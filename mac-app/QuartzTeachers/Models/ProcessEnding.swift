import Darwin
import Foundation

/// When another process ends, as an `AsyncStream` — so a held update (#204)
/// can wait for a scheduled publish, or another program's build, to finish
/// without looking at a clock.
///
/// **The second permitted use of GCD in this app, and this comment is the
/// permission** — the first is `ScheduledPublishWatcher.changes(at:watching:)`,
/// and the reasoning is the same. Russell's rule forbids Dispatch for
/// deferring work, for hopping to the main thread and for waiting before doing
/// something; none of those happens here. `DispatchSource.makeProcessSource`
/// is the kernel's own "this process has exited" event, and a `DispatchQueue`
/// is a required parameter of it — the delivery channel, not somewhere work is
/// thrown. The event is consumed with `for await`.
///
/// Rejected: looking every few seconds (a timer standing in for an event the
/// kernel already delivers, which `CLAUDE.md` rules out); `NSWorkspace`'s
/// termination notice, which covers applications only — a scheduled publish
/// and an assistant's server never become one (measured by #204's plan
/// review: a headless copy is not an `NSRunningApplication`); and a raw
/// `kevent()` loop, which needs a thread of its own blocked in the kernel.
nonisolated enum ProcessEnding {

    // MARK: - Functions

    /// Yields once when the process ends — at once, if it has already gone —
    /// and then finishes.
    ///
    /// ARMED BEFORE THIS RETURNS (the stream's build closure runs during its
    /// `init`), and the process is asked whether it still exists only AFTER
    /// the source is armed, so an ending in between cannot be missed.
    /// Cancelling the task that reads it cancels the source.
    static func ends(of pid: Int32) -> AsyncStream<Void> {
        return AsyncStream<Void>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let deliveries: DispatchQueue = DispatchQueue(
                label: "ca.russellgordon.Plantoir.process-ending"
            )
            let source: any DispatchSourceProcess = DispatchSource.makeProcessSource(
                identifier: pid,
                eventMask: .exit,
                queue: deliveries
            )
            source.setEventHandler {
                continuation.yield(())
                continuation.finish()
            }
            continuation.onTermination = { _ in
                source.cancel()
            }
            source.resume()
            if !ProcessEnding.stillExists(pid) {
                continuation.yield(())
                continuation.finish()
            }
        }
    }

    /// Whether a process id names a process at all — `kill(pid, 0)` answering
    /// anything but "no such process" (`ProcessLiveness`'s measurement: EPERM
    /// means it exists and is someone else's).
    static func stillExists(_ pid: Int32) -> Bool {
        if pid <= 0 {
            return false
        }
        if kill(pid, 0) == 0 {
            return true
        }
        return errno != ESRCH
    }
}

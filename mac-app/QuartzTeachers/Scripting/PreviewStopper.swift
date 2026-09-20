import Foundation

/// Reclaims the container-side processes of a preview that just ended.
///
/// Stopping a preview (the Stop Preview button, clicking away from the
/// section, closing the window) terminates the HOST-side launcher — but
/// the build or server processes inside the container would keep running:
/// idle for a server, real CPU for a mid-flight build. This runs the
/// launcher's stop mode quietly in the background to end them too.
@MainActor
enum PreviewStopper {

    // MARK: - Stored properties

    /// One stop in flight, and which section it belongs to.
    ///
    /// The section is kept because waiting matters: a preview must not begin
    /// while ITS section's stop is still running, and equally must not be
    /// held up by a stop belonging to a different section in another window.
    struct Stopping {
        let courseCode: String
        let sectionNumber: Int
        let process: Process
    }

    /// Keeps each stop process alive until it finishes.
    private(set) static var running: [Stopping] = []

    // MARK: - Functions

    /// Fire-and-forget: asks the launcher to stop the section's
    /// container-side processes. Quiet by design — this runs behind
    /// actions that already have their own feedback, and if it cannot
    /// run, the next preview of the section frees its ports anyway.
    static func stopSectionProcesses(courseCode: String, sectionNumber: Int, workspaceURL: URL) {
        let scriptURL: URL = workspaceURL.appendingPathComponent("preview.sh")
        if !FileManager.default.fileExists(atPath: scriptURL.path) {
            return
        }

        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path, courseCode, String(sectionNumber), "--stop"]
        process.currentDirectoryURL = workspaceURL
        // The launcher prints how many processes it ended, and this used to
        // send that straight to the null device. The number is the one thing
        // that separates "there was nothing left to stop" from "a build was
        // still running and was ended", which are the two explanations for a
        // teacher reporting that their publish stopped halfway — so it is
        // read, put on the trail, and otherwise still ignored. Errors stay
        // discarded: this runs behind actions that have their own feedback,
        // and a stop that fails is handled by the next preview freeing the
        // ports anyway.
        let output: Pipe = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { finished in
            let printed: String = String(
                data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
            ) ?? ""
            Task { @MainActor in
                PreviewStopper.noteWhatWasReclaimed(
                    printed, courseCode: courseCode, sectionNumber: sectionNumber
                )
                var remaining: [Stopping] = []
                for candidate in running {
                    if candidate.process !== finished {
                        remaining.append(candidate)
                    }
                }
                running = remaining
            }
        }

        do {
            try process.run()
            running.append(Stopping(
                courseCode: courseCode, sectionNumber: sectionNumber, process: process
            ))
        } catch {
            // Could not start: nothing held, nothing to clean up.
        }
    }

    /// How many processes the launcher said it ended, or nil when it said
    /// nothing of the kind.
    ///
    /// Parsed rather than counted here because the counting happens inside
    /// the container, where the rule runs — see `contracts/shared-rules.json`
    /// → `stopPreview`. The launcher's own sentence is the only report of it
    /// that crosses back.
    nonisolated static func countReclaimed(in printed: String) -> Int? {
        for line in printed.split(separator: "\n") {
            guard let stopped = line.range(of: "Stopped ") else {
                continue
            }
            let rest: Substring = line[stopped.upperBound...]
            var digits: String = ""
            for character in rest {
                if character.isNumber {
                    digits.append(character)
                } else {
                    break
                }
            }
            if let value = Int(digits) {
                return value
            }
        }
        return nil
    }

    /// Puts the count on the trail, in the words a teacher would recognise.
    ///
    /// Nothing is recorded when the launcher said nothing countable — it
    /// declines to start when there is no container, and a line claiming
    /// zero would be indistinguishable from a sweep that ran and found
    /// nothing. Those are different facts and the trail should not blur them.
    static func noteWhatWasReclaimed(
        _ printed: String, courseCode: String, sectionNumber: Int
    ) {
        guard let count = countReclaimed(in: printed) else {
            return
        }
        let what: String = count == 1
            ? "reclaimed 1 leftover website-builder process"
            : "reclaimed \(count) leftover website-builder processes"
        ActivityTrail.note(
            .sectionProcessesReclaimed, what, course: courseCode, section: sectionNumber
        )
    }

    /// Stop the section's container-side processes and WAIT for that to
    /// finish.
    ///
    /// Fire-and-forget is right behind a button — the teacher has already
    /// moved on — and wrong in front of a rebuild. The stop runs
    /// `preview.sh --stop`, which reaches into the container and kills the
    /// processes belonging to that section; start a new preview while it is
    /// still going and it kills that one too. The symptom is nasty precisely
    /// because it is not an error: the preview simply never appears, and the
    /// site on disk stays at the last build that was allowed to FINISH, so a
    /// teacher who restarts it by hand is shown yesterday's pages and has no
    /// reason to suspect the assistant.
    ///
    /// Bounded, because a stop that hangs must not take the rebuild with it:
    /// after the deadline the caller carries on, which is no worse than the
    /// old fire-and-forget behaviour.
    static func stopSectionProcessesAndWait(
        courseCode: String,
        sectionNumber: Int,
        workspaceURL: URL,
        secondsToWait: Double = 20
    ) async {
        stopSectionProcesses(
            courseCode: courseCode, sectionNumber: sectionNumber, workspaceURL: workspaceURL
        )
        await waitForStopsToFinish(
            courseCode: courseCode, sectionNumber: sectionNumber, secondsToWait: secondsToWait
        )
    }

    /// Waits until this section has no stop still running, or the deadline
    /// passes.
    ///
    /// Scoped to the section on purpose. Waiting for every stop everywhere
    /// would be safe but would let one window's Stop delay another window's
    /// Preview for no reason — and a preview that takes a few unexplained
    /// seconds is how this whole class of problem gets excused rather than
    /// found.
    static func waitForStopsToFinish(
        courseCode: String,
        sectionNumber: Int,
        secondsToWait: Double = 20
    ) async {
        let deadline: Date = Date().addingTimeInterval(secondsToWait)
        while Date() < deadline {
            var stillGoing: Bool = false
            for stopping in running where stopping.process.isRunning {
                if stopping.courseCode.lowercased() == courseCode.lowercased()
                    && stopping.sectionNumber == sectionNumber {
                    stillGoing = true
                }
            }
            if !stillGoing {
                return
            }
            try? await Task.sleep(for: .milliseconds(120))
        }
    }
}

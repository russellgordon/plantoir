import Foundation

/// The container behind a working folder, and when to let it rest.
///
/// Each working folder has its own container, named after a hash of the
/// folder's path — the launchers derive the same name with
/// `pwd -P | shasum -a 256`, so the trailing newline is part of the hashed
/// input here too. When the last window using a folder closes, that
/// folder's container is stopped: it holds no content (everything lives on
/// the host) and restarts in about a second on the next preview, so keeping
/// it running for nobody would only spend the teacher's memory.
@MainActor
enum FolderContainers {

    // MARK: - Types

    /// Everything the generated script can find to say, and — through
    /// `event(for:)` — which line of the trail each one is.
    ///
    /// The script writes its own trail lines, because by the time it knows
    /// the answer the app is gone. That is the launchers' arrangement too
    /// (`note_on_the_trail` in `preview.sh`), and it is why the sentences are
    /// built HERE: a sentence in a shell script is a sentence nothing can
    /// pin, and `contracts/shared-rules.json` → `activityTrail.mustRecord`
    /// names the events this list has to cover.
    enum Outcome: CaseIterable {
        case stoppedAFoldersBuilder
        case leftAFoldersBuilderRunning
        case couldNotStopAFoldersBuilder
        case stoppedTheSharedSetup
        case leftTheSharedSetupRunning
        case couldNotStopTheSharedSetup
        case couldNotFindThePrograms
        case couldNotAskWhatElseIsRunning
        case ranOutOfTime
    }

    /// Why a container is being released, which is the half of the sentence a
    /// teacher would use to describe what they just did.
    enum Occasion {
        case quitting
        case theLastWindowOnTheFolderClosed
    }

    // MARK: - Stored properties

    /// How long the script waits for a folder's own work to finish before
    /// giving up and leaving the builder alone.
    ///
    /// A wait on an observable condition — the container going idle and the
    /// folder's launchers going away — rather than a settle delay: the app's
    /// own preview stops are fired a moment earlier, and without this the
    /// quit would race them and the race would resolve towards freeing
    /// nothing.
    static let secondsToWaitForWorkToFinish: Int = 20

    /// How long the script gives itself beyond the waiting it was asked to do.
    ///
    /// A `docker` talking to a wedged daemon can block for ever, which is
    /// exactly how this Mac came to have two quit shells that had been asleep
    /// for 27 days: a detached script with no deadline is a process nobody
    /// will ever notice again. The allowance covers the calls that are not
    /// the per-folder wait — a `docker stop` grace of two seconds each, and a
    /// `colima stop` that takes ten to twenty.
    static let secondsAllowedBeyondTheWaiting: Int = 60

    /// The whole script's deadline, which has to GROW with the number of
    /// folders or it becomes the thing that stops the work.
    ///
    /// A fixed two minutes was the first shape and it was wrong: six folders
    /// each waiting twenty seconds is already two minutes, so the sixth
    /// folder would be killed in the middle of being dealt with and the
    /// teacher would be told nothing about any of them.
    static func secondsBeforeGivingUp(folderCount: Int, secondsToWaitForWork: Int) -> Int {
        let waiting: Int = max(1, folderCount) * max(0, secondsToWaitForWork)
        return waiting + secondsAllowedBeyondTheWaiting
    }

    // MARK: - Functions

    /// The name the launchers give this folder's container.
    ///
    /// The identifier itself lives in `BuildOutputLocation`, which needs the
    /// same eight characters to name the folder a working folder's builds go
    /// in — one derivation, so a container and its builds folder can never
    /// disagree about which folder they belong to.
    static func containerName(forFolder path: String) -> String {
        return "teaching-quartz-" + BuildOutputLocation.folderIdentifier(forWorkingFolder: path)
    }

    /// Which line of the trail an outcome belongs to.
    static func event(for outcome: Outcome) -> ActivityTrail.Event {
        switch outcome {
        case .stoppedAFoldersBuilder, .stoppedTheSharedSetup:
            return .websiteBuilderStopped
        case .leftAFoldersBuilderRunning, .leftTheSharedSetupRunning:
            return .websiteBuilderLeftRunning
        case .couldNotStopAFoldersBuilder, .couldNotStopTheSharedSetup,
             .couldNotFindThePrograms, .couldNotAskWhatElseIsRunning, .ranOutOfTime:
            return .websiteBuilderCouldNotBeStopped
        }
    }

    /// The sentence the trail gets, in words a teacher would recognise.
    ///
    /// `folderName` is the working folder's LAST component and never its
    /// path: the script appends to the trail directly, so `LogRedactor` —
    /// which redacts on the way in — never sees these lines, and the safe
    /// answer is a sentence with nothing in it that would need redacting.
    static func sentence(
        for outcome: Outcome,
        occasion: Occasion,
        folderName: String = "",
        reasonSomethingElseIsUsingIt: String = ""
    ) -> String {
        let because: String = occasion == .quitting
            ? "because Plantoir was quitting"
            : "because no window was working in that folder any more"
        let when: String = occasion == .quitting
            ? "when Plantoir quit"
            : "when the last window on that folder closed"
        switch outcome {
        case .stoppedAFoldersBuilder:
            return "stopped the website builder for “\(folderName)” \(because)"
        case .leftAFoldersBuilderRunning:
            return "left the website builder for “\(folderName)” running because "
                + "a publish or preview for that folder is still going"
        case .couldNotStopAFoldersBuilder:
            return "tried to stop the website builder for “\(folderName)” \(because), "
                + "and it would not stop"
        case .stoppedTheSharedSetup:
            return "stopped this Mac’s website-building setup too, \(because), "
                + "so the memory it was holding is back"
        case .leftTheSharedSetupRunning:
            return "left this Mac’s website-building setup running because "
                + reasonSomethingElseIsUsingIt
        case .couldNotStopTheSharedSetup:
            return "tried to stop this Mac’s website-building setup, and it would not stop, "
                + "so the memory it was holding is still spoken for"
        case .couldNotFindThePrograms:
            return "could not find the programs that run your website builder, "
                + "so nothing was stopped \(when)"
        case .couldNotAskWhatElseIsRunning:
            return "could not check what else was using this Mac’s website-building setup, "
                + "so it was left running"
        case .ranOutOfTime:
            return "stopped waiting for an answer about your website builder \(when), "
                + "so anything still running was left alone"
        }
    }

    /// Everything to run when work on a folder is finished, as one detached
    /// script.
    ///
    /// **What it does, and what it deliberately refuses to do.** For each
    /// folder it waits — up to `secondsToWaitForWorkToFinish` — for that
    /// folder to have no launcher of its own running on this Mac AND for its
    /// container to be idle, and only then stops the container. Then, if
    /// asked to, it stops the shared virtual machine, but only when four
    /// things are true at once: `colima` can be found, the socket Colima owns
    /// is there, asking THAT socket what is running SUCCEEDED and came back
    /// empty, and no launcher for any folder is running on the host.
    ///
    /// Every one of those is a way of erring towards leaving things alone.
    /// Before 2026-09-19 this script had never run on a teacher's Mac at all
    /// (issue #220), so making it work turns a silent no-op into a real
    /// `docker stop` and a real `colima stop` — and the two cases where that
    /// hurts are the two the old `docker ps -q` check could not see: a
    /// launcher BETWEEN its calls into the container, and a launcher that has
    /// not reached the container yet, which on a first run of the day is
    /// minutes of building an image and starting the VM with nothing running
    /// in it. The host-side check is what sees both.
    ///
    /// **`docker ps -q` failing is not the same as nothing running**, and it
    /// used to be treated as though it were. `DOCKER_CONTEXT=default docker
    /// ps -q` exits 1 and prints nothing; so does a daemon that did not
    /// answer. Rule 7 says the shared VM must never be stopped out from under
    /// another project's containers, and "I could not ask" has to count as
    /// "do not".
    static func quitScript(
        folderPaths: [String],
        occasion: Occasion = .quitting,
        includingTheSharedSetup: Bool = true,
        secondsToWaitForWork: Int = secondsToWaitForWorkToFinish,
        inHomeFolder homeFolder: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        var lines: [String] = []
        lines.append(HelperPrograms.exportLine(inHomeFolder: homeFolder))
        lines.append(trailFunction(inHomeFolder: homeFolder))
        lines.append(launcherFunctions())
        lines.append(releaseFunction(secondsToWaitForWork: secondsToWaitForWork))

        var body: [String] = []
        body.append("  oursLeftRunning=''")
        body.append("  if ! command -v docker >/dev/null 2>&1; then")
        // Only worth saying when there was something to do. A teacher who has
        // never set anything up has no folder open, and a line on every quit
        // of their first week saying nothing could be stopped would bury the
        // one quit where something was.
        if !folderPaths.isEmpty {
            body.append("    " + noteCall(.couldNotFindThePrograms, occasion: occasion))
        }
        body.append("    return 0")
        body.append("  fi")

        for path in folderPaths {
            let folderName: String = URL(fileURLWithPath: path).lastPathComponent
            body.append(
                "  release "
                + HelperPrograms.shellQuoted(path) + " "
                + HelperPrograms.shellQuoted(containerName(forFolder: path)) + " "
                + HelperPrograms.shellQuoted(sentence(
                    for: .stoppedAFoldersBuilder, occasion: occasion, folderName: folderName
                )) + " "
                + HelperPrograms.shellQuoted(sentence(
                    for: .leftAFoldersBuilderRunning, occasion: occasion, folderName: folderName
                )) + " "
                + HelperPrograms.shellQuoted(sentence(
                    for: .couldNotStopAFoldersBuilder, occasion: occasion, folderName: folderName
                ))
                + " || oursLeftRunning=1"
                + "  # " + event(for: .stoppedAFoldersBuilder).rawValue
                + " / " + event(for: .leftAFoldersBuilderRunning).rawValue
                + " / " + event(for: .couldNotStopAFoldersBuilder).rawValue
            )
        }

        if includingTheSharedSetup {
            for line in sharedSetupLines(occasion: occasion, inHomeFolder: homeFolder) {
                body.append("  " + line)
            }
        }

        lines.append("body() {")
        for line in body {
            lines.append(line)
        }
        lines.append("}")
        lines.append(watchdogLines(
            seconds: secondsBeforeGivingUp(
                folderCount: folderPaths.count, secondsToWaitForWork: secondsToWaitForWork
            ),
            occasion: occasion
        ))
        return lines.joined(separator: "\n")
    }

    /// The command that runs the quit script — as a value, so a test can read
    /// what would be handed to `Process` without anything being started.
    ///
    /// `/bin/sh`, not `/bin/zsh -l`. A login shell was chosen so that "docker
    /// is on PATH wherever it was installed", which was never true on a
    /// teacher's Mac and cost this fix its whole existence; and `zsh` blocks
    /// in `init_io` — its terminal setup, before it reads the script at all —
    /// when it is handed a pty whose other end has gone, which is what an app
    /// launched from Xcode or iTerm hands its children. Two of those shells
    /// had been asleep on this Mac for 27 days, stuck in `open()`, having
    /// never run a line. `/bin/sh` does not do that, and the null device
    /// below means no helper is ever handed a terminal again.
    static func quitCommand(
        folderPaths: [String],
        occasion: Occasion = .quitting,
        includingTheSharedSetup: Bool = true,
        inheriting inherited: [String: String] = ProcessInfo.processInfo.environment,
        inHomeFolder homeFolder: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> HelperPrograms.Command {
        return HelperPrograms.Command(
            executablePath: "/bin/sh",
            arguments: ["-c", quitScript(
                folderPaths: folderPaths,
                occasion: occasion,
                includingTheSharedSetup: includingTheSharedSetup,
                inHomeFolder: homeFolder
            )],
            environment: HelperPrograms.environment(basedOn: inherited, inHomeFolder: homeFolder),
            currentDirectoryPath: nil
        )
    }

    /// Runs the quit script detached, so quitting does not wait on it.
    static func releaseEverythingAtQuit(folderPaths: [String]) {
        if WorkspaceModel.isRunningTests {
            return
        }
        var uniquePaths: [String] = []
        for path in folderPaths {
            if !uniquePaths.contains(path) {
                uniquePaths.append(path)
            }
        }
        run(quitCommand(folderPaths: uniquePaths))
    }

    /// Stops the folder's container, quietly, without waiting on it.
    ///
    /// `docker stop`, not `rm`: the container restarts far faster than it
    /// recreates, and the next preview starts it again automatically. The
    /// shared virtual machine is NOT touched here — one window closing says
    /// nothing about the rest of the Mac.
    static func stopContainer(forFolder path: String) {
        if WorkspaceModel.isRunningTests {
            return
        }
        run(quitCommand(
            folderPaths: [path],
            occasion: .theLastWindowOnTheFolderClosed,
            includingTheSharedSetup: false
        ))
    }

    /// Starts a command and lets it outlive the app.
    ///
    /// The three handles are set to the null device explicitly. Inheriting
    /// them is what stranded the old quit shells: a child given the app's own
    /// pty keeps that terminal open, and when the app goes the child is left
    /// holding one end of something with no other end. A child with
    /// `/dev/null` is reparented to `launchd` and finishes on its own —
    /// measured, an 18-second job completing well after its parent had gone.
    private static func run(_ command: HelperPrograms.Command) {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: command.executablePath)
        process.arguments = command.arguments
        process.environment = command.environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    // MARK: - The script, a piece at a time

    /// Appends one line to the trail, the way the launchers do.
    private static func trailFunction(inHomeFolder homeFolder: URL) -> String {
        let trailFolder: String = homeFolder
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
            .appendingPathComponent("Plantoir")
            .path
        var lines: [String] = []
        lines.append("note() {")
        lines.append("  trail=" + HelperPrograms.shellQuoted(trailFolder))
        lines.append("  mkdir -p \"$trail\" 2>/dev/null || return 0")
        lines.append("  printf '%s · %s\\n' \"$(date '+%Y-%m-%d %H:%M:%S')\" \"$1\""
            + " >> \"$trail/activity.txt\" 2>/dev/null || true")
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    /// One `note` call, with the sentence already built in Swift and the
    /// contract's event key left beside it as a comment.
    ///
    /// The comment is the launchers' own convention (`preview.sh:448`), and
    /// it is what makes a line in a generated script traceable back to
    /// `contracts/shared-rules.json` → `activityTrail.mustRecord` by somebody
    /// reading a `ps` line months from now.
    private static func noteCall(
        _ outcome: Outcome,
        occasion: Occasion,
        reasonSomethingElseIsUsingIt: String = "",
        endingTheLine: Bool = true
    ) -> String {
        let text: String = sentence(
            for: outcome,
            occasion: occasion,
            reasonSomethingElseIsUsingIt: reasonSomethingElseIsUsingIt
        )
        let call: String = "note " + HelperPrograms.shellQuoted(text)
        // A `#` comment runs to the end of the LINE, so it can only be added
        // where this call is the last thing on one. The watchdog's note sits
        // mid-line between a `sleep` and a `kill`, and a comment there would
        // swallow the kill.
        if !endingTheLine {
            return call
        }
        return call + "  # " + event(for: outcome).rawValue
    }

    /// Is anything of ours running on the HOST for this folder — or for any
    /// folder at all?
    ///
    /// `ps -Ao args=` prints whole command lines untruncated (measured: the
    /// longest on this Mac was 2,766 characters), and both places the app
    /// starts a launcher pass an ABSOLUTE path — `ScriptRunner` passes
    /// `scriptURL.path`, a scheduled publish passes a quoted script path — so
    /// `<folder>/preview.sh` appears verbatim and a fixed-string match finds
    /// it. `grep -F` rather than `pgrep -f`, because `pgrep` takes a REGULAR
    /// EXPRESSION and a folder called `C++ 26(27)` would need escaping;
    /// getting that wrong fails OPEN, and failing open here means stopping
    /// something mid-publish.
    ///
    /// Its known limit, stated rather than hidden: a teacher who types
    /// `./preview.sh` in Terminal is not matched, because the relative path
    /// never appears. The idle check below covers that one while a build is
    /// actually inside the container.
    ///
    /// A `--stop` run is deliberately NOT counted. Quitting fires the app's
    /// own `preview.sh … --stop` for every live preview a moment before this
    /// script starts, and counting it would make every quit-with-a-preview
    /// decide that something was busy and free nothing at all.
    private static func launcherFunctions() -> String {
        var lines: [String] = []
        lines.append("launcherRunning() {")
        lines.append("  seen=$(ps -Ao args= 2>/dev/null)")
        lines.append("  for launcher in preview.sh deploy.sh setup.sh; do")
        lines.append("    if printf '%s\\n' \"$seen\" | grep -F \"$1/$launcher\""
            + " | grep -Fv -- ' --stop' >/dev/null 2>&1; then")
        lines.append("      return 0")
        lines.append("    fi")
        lines.append("  done")
        lines.append("  return 1")
        lines.append("}")
        lines.append("anyLauncherRunning() {")
        lines.append("  seen=$(ps -Ao args= 2>/dev/null)")
        lines.append("  printf '%s\\n' \"$seen\" | grep -E '/(preview|deploy|setup)\\.sh( |$)'"
            + " | grep -Fv -- ' --stop' >/dev/null 2>&1")
        lines.append("}")
        lines.append("containerBusy() {")
        // Could not ask? Then say busy. An idle container costs one sleeping
        // process; stopping one that somebody is using costs their publish.
        lines.append("  inside=$(docker top \"$1\" 2>/dev/null) || return 0")
        lines.append("  count=$(printf '%s\\n' \"$inside\" | tail -n +2 | grep -c .)")
        lines.append("  [ \"$count\" -gt 1 ]")
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    /// Stops one folder's container once nothing is using it.
    ///
    /// A container that is not running says nothing on the trail: a line
    /// every quit reporting that there was nothing to stop would bury the
    /// one quit where something happened.
    private static func releaseFunction(secondsToWaitForWork: Int) -> String {
        var lines: [String] = []
        lines.append("release() {")
        lines.append("  state=$(docker inspect -f '{{.State.Running}}' \"$2\" 2>/dev/null) || state=''")
        lines.append("  if [ \"$state\" != 'true' ]; then")
        lines.append("    return 0")
        lines.append("  fi")
        lines.append("  waited=0")
        lines.append("  while [ \"$waited\" -lt \(secondsToWaitForWork) ]; do")
        lines.append("    if ! launcherRunning \"$1\" && ! containerBusy \"$2\"; then")
        // A stop that FAILED must not be written down as a stop. It is the
        // same fault this whole piece exists to fix, one level down: a line
        // saying the memory came back, on a day it did not.
        lines.append("      if docker stop -t 2 \"$2\" >/dev/null 2>&1; then")
        lines.append("        note \"$3\"")
        lines.append("        return 0")
        lines.append("      fi")
        // A REFUSED stop leaves one of ours running just as surely as a
        // deliberate refusal does, and the shared-machine question below has
        // to hear about it: our container is in `docker ps -q` either way,
        // and a builder that would not stop would otherwise be reported as
        // "other software on this Mac".
        lines.append("      note \"$5\"")
        lines.append("      return 1")
        lines.append("    fi")
        lines.append("    sleep 1")
        lines.append("    waited=$((waited + 1))")
        lines.append("  done")
        lines.append("  note \"$4\"")
        // A non-zero return is how the caller learns one of OURS was left
        // running — which the shared-machine question below has to know,
        // because a builder we left up is itself in `docker ps -q` and would
        // otherwise be reported as "other software on this Mac".
        lines.append("  return 1")
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    /// The shared virtual machine: asked about, and stopped only on a clear
    /// answer.
    private static func sharedSetupLines(occasion: Occasion, inHomeFolder homeFolder: URL) -> [String] {
        let socketPath: String = homeFolder
            .appendingPathComponent(".colima")
            .appendingPathComponent("default")
            .appendingPathComponent("docker.sock")
            .path
        var lines: [String] = []
        lines.append("if command -v colima >/dev/null 2>&1; then")
        lines.append("  if [ -S " + HelperPrograms.shellQuoted(socketPath) + " ]; then")
        lines.append("    sharing=$(DOCKER_HOST="
            + HelperPrograms.shellQuoted("unix://" + socketPath)
            + " docker ps -q 2>/dev/null)")
        lines.append("    asked=$?")
        lines.append("    if [ \"$asked\" -ne 0 ]; then")
        lines.append("      " + noteCall(.couldNotAskWhatElseIsRunning, occasion: occasion))
        // OUR OWN first, then anybody's launcher, then everything else. A
        // builder this script has just decided to leave running is in
        // `docker ps -q` too, so asking "is anything in there?" first would
        // report a teacher's own unfinished publish as "other software on
        // this Mac" — on a Mac that has no other software in it at all, which
        // is every teacher's.
        lines.append("    elif [ -n \"$oursLeftRunning\" ]; then")
        lines.append("      " + noteCall(
            .leftTheSharedSetupRunning,
            occasion: occasion,
            // "running", not "working": this branch is reached both by a
            // builder deliberately left alone mid-publish and by one that
            // refused to stop, and only the first of those is working.
            reasonSomethingElseIsUsingIt: "this folder’s own website builder is still running"
        ))
        lines.append("    elif anyLauncherRunning; then")
        lines.append("      " + noteCall(
            .leftTheSharedSetupRunning,
            occasion: occasion,
            reasonSomethingElseIsUsingIt: "a publish or preview is still going"
        ))
        lines.append("    elif [ -n \"$sharing\" ]; then")
        lines.append("      " + noteCall(
            .leftTheSharedSetupRunning,
            occasion: occasion,
            reasonSomethingElseIsUsingIt: "other software on this Mac is still using it"
        ))
        lines.append("    else")
        lines.append("      if colima stop >/dev/null 2>&1; then")
        lines.append("        " + noteCall(.stoppedTheSharedSetup, occasion: occasion))
        lines.append("      else")
        lines.append("        " + noteCall(.couldNotStopTheSharedSetup, occasion: occasion))
        lines.append("      fi")
        lines.append("    fi")
        lines.append("  fi")
        lines.append("fi")
        return lines
    }

    /// Runs the body with a deadline it cannot outlive.
    ///
    /// **The deadline writes its own line before it fires**, because the one
    /// ending that reported nothing is the whole fault this piece exists to
    /// fix, and a script killed at its deadline is exactly that ending. Its
    /// honest limit, said rather than hidden: `kill -9` on the body does not
    /// take a wedged `docker` grandchild with it — measured, a `docker` stuck
    /// on a dead socket was still there afterwards. What the deadline buys is
    /// that PLANTOIR's own shell goes away and says so; a hung `docker` is
    /// the engine's problem and killing it would not unwedge anything.
    ///
    /// `kill "$guard"` after `wait` is the part that must not be dropped: a
    /// guard left behind would fire its `kill -9` at whatever process had
    /// been given that number by then. Killing the guard does NOT take its
    /// own `sleep` with it — measured, the `sleep` lingers out its full term
    /// as an orphan doing nothing — so do not "fix" the kill when you see
    /// one.
    private static func watchdogLines(seconds: Int, occasion: Occasion) -> String {
        var lines: [String] = []
        lines.append("body & work=$!")
        lines.append("( sleep \(seconds); "
            + noteCall(.ranOutOfTime, occasion: occasion, endingTheLine: false)
            + "; kill -9 \"$work\" 2>/dev/null ) >/dev/null 2>&1 & guard=$!")
        lines.append("wait \"$work\"")
        lines.append("kill \"$guard\" 2>/dev/null")
        return lines.joined(separator: "\n")
    }
}

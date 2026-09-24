import Foundation

/// "Deploy tomorrow's class at 6:30 AM."
///
/// A launchd user agent runs `deploy.sh <CODE> <N>` at a set time with
/// nothing of ours running — that is the whole point, so the plist must be
/// self-sufficient: the working folder, the arguments, and the PATH the
/// launcher needs are all written into it. Plantoir can be closed, and
/// usually is at half six in the morning.
///
/// The decision of WHETHER to schedule, and every word the teacher reads,
/// lives here in the app. The launchd layer below only runs the thing.
///
/// **No wake timer, deliberately.** `pmset schedule` needs administrator
/// rights and depends on the hardware and the power settings, and when it
/// fails it fails SILENTLY. Rather than promise a wake-up that may not
/// happen, the plan states the conditions and says what launchd really
/// does with a job whose time passed while the Mac was asleep: it runs it
/// at the next wake, which could be well after the class it was for.
enum ScheduledDeploy {

    // MARK: - Stored properties

    /// The prefix every one of our agents' labels carries, so an agent of
    /// ours is never mistaken for anything else in the teacher's
    /// `LaunchAgents` folder.
    nonisolated static let labelPrefix: String = "ca.russellgordon.Plantoir.deploy"

    /// The environment key carrying the moment the agent was set for.
    ///
    /// `StartCalendarInterval` has no year — the same month and day come
    /// round again — so the plist alone cannot say which day it meant. launchd
    /// passes `EnvironmentVariables` through untouched, so the full moment
    /// rides there: it is what the sidebar reads back, what the RUN re-checks
    /// its own lateness against (`ScheduledDeployLateness`), and it also lands
    /// in the agent's own log.
    ///
    /// Since 2026-09-20 a job whose moment is further from now than the course
    /// allows stands down instead of deploying, so the annual return is closed
    /// rather than merely unlikely — but it is closed by THIS value, which is
    /// why a plist that does not carry one fails open.
    nonisolated static let scheduledForKey: String = "PLANTOIR_SCHEDULED_FOR"

    // MARK: - Functions

    /// This section's agent label — the course code AND the section number,
    /// so two sections of one course can never collide, nor two courses.
    nonisolated static func agentLabel(courseCode: String, sectionNumber: Int) -> String {
        let code: String = sanitizedCode(courseCode)
        return "\(labelPrefix).\(code).section\(sectionNumber)"
    }

    /// A course code reduced to what a launchd label may carry. Codes are
    /// already letters and digits, so in practice this changes nothing —
    /// it is here so that a club named with a space cannot produce a label
    /// launchd refuses.
    nonisolated static func sanitizedCode(_ courseCode: String) -> String {
        var result: String = ""
        for character in courseCode.uppercased() {
            if character.isLetter || character.isNumber {
                result.append(character)
            } else {
                result.append("-")
            }
        }
        return result.isEmpty ? "COURSE" : result
    }

    /// A folder to write the one-shot scripts into instead of the teacher's
    /// own, and the other half of `launchAgentsDirectoryOverride`.
    ///
    /// **It was missing until 2026-09-20, and the gap had teeth.**
    /// `cancelScheduledDeploy` deletes the wrapper script whatever runner it
    /// was handed, so a test that moved only the AGENTS folder still deleted
    /// `~/Library/Application Support/Plantoir/scheduled/<label>.sh` for real —
    /// for `ICS3U`, the fixture code, chosen precisely because it is "a course
    /// a teacher plausibly has". The teacher's alarm would survive (its plist
    /// was in the test's folder) and fire on its date at a script that is no
    /// longer there: a scheduled deploy failing for a reason nothing explains,
    /// caused by somebody running the suite weeks earlier.
    nonisolated(unsafe) static var scheduledScriptsDirectoryOverride: URL?

    /// Where the one-shot scripts live.
    ///
    /// **The structural guard**: setting the agents override and forgetting
    /// this one is the mistake that deletes a teacher's file, so it is trapped
    /// rather than written down. A test that has moved one and not the other
    /// fails on the spot in a Debug build, and falls back to a throwaway folder
    /// in any build where assertions are off — so the real folder is not
    /// reached either way. In the app both overrides are always nil and neither
    /// branch is live.
    nonisolated static func scheduledScriptsDirectoryURL() -> URL {
        if let scheduledScriptsDirectoryOverride {
            return scheduledScriptsDirectoryOverride
        }
        if launchAgentsDirectoryOverride != nil {
            assertionFailure(
                "A test has moved the agents folder and not the scheduled-scripts folder. "
                + "Set ScheduledDeploy.scheduledScriptsDirectoryOverride too, or cancelling "
                + "will delete a real teacher's wrapper script."
            )
            return quarantinedScriptsDirectoryURL
        }
        // Under the suite with neither override set: never the real folder
        // either (issue #240). The per-run home is the same one every other
        // scheduled note under test resolves against.
        return homeForScheduledNotes
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Plantoir")
            .appendingPathComponent("scheduled")
    }

    /// The home folder a scheduled deploy's notes — the success and findings
    /// sentinels, the wrapper scripts, the agent's log — are resolved against
    /// when a caller names none: the real one in the app and in a run launchd
    /// fired, and ONE throwaway folder per test run under the suite.
    ///
    /// **Why a redirect and not the trap issue #240 proposed.** The issue
    /// asked for a Debug trap "when `launchAgentsDirectoryOverride` is set and
    /// the home has not been moved" — but neither test that reached the real
    /// sentinels sets that override, so the trap would have fired for neither
    /// of the paths it was written for. The condition that identifies them is
    /// "under the suite, and nobody passed a home", and that is what this
    /// answers. It is the device `BuildOutputLocation.buildsRoot` already
    /// uses, keyed on the same `isRunningTests`, so the two cannot disagree
    /// about whether a test is driving.
    ///
    /// Every resolver that uses it takes `URL? = nil` rather than a default
    /// of the real home, on purpose: a default argument is evaluated at the
    /// CALL site, so `= homeDirectoryForCurrentUser` could not be redirected
    /// from inside the function. A caller that passes a home explicitly —
    /// `oneShotCommand`, writing the real path into the script launchd will
    /// run — gets exactly that home, test or not.
    nonisolated static var homeForScheduledNotes: URL {
        if BuildOutputLocation.isRunningTests {
            return homeWhileTesting
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// The one throwaway home for a whole test run, so a test that writes a
    /// sentinel and then reads it back through another function still finds
    /// it.
    nonisolated static let homeWhileTesting: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("plantoir-home-under-test-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)

    /// Where the guard above sends a test that forgot, so that even with
    /// assertions off nothing real is touched. One folder per process, so a
    /// test that wrote and then read back still finds what it wrote.
    nonisolated static let quarantinedScriptsDirectoryURL: URL = FileManager.default
        .temporaryDirectory
        .appendingPathComponent("Plantoir-scheduled-quarantine-" + UUID().uuidString, isDirectory: true)

    /// Where this section's one-shot script is written.
    ///
    /// A file rather than a line inside the plist, because launchd no longer
    /// runs it directly — see `agentPlist` for why. The app runs this file.
    nonisolated static func scriptURL(courseCode: String, sectionNumber: Int) -> URL {
        let label: String = agentLabel(courseCode: courseCode, sectionNumber: sectionNumber)
        return scheduledScriptsDirectoryURL().appendingPathComponent("\(label).sh")
    }

    /// The flag the agent launches the app with.
    nonisolated static let runFlag: String = "--run-scheduled-deploy"

    /// The flag carrying which section the run belongs to, so the app can
    /// mark that section's pages as published once the script has
    /// finished. Without it a scheduled deploy publishes perfectly and
    /// leaves the window saying " — Edited" until somebody publishes again
    /// by hand — the flagship "publish tomorrow's class overnight" feature
    /// quietly disagreeing with the title bar.
    nonisolated static let sectionFlag: String = "--scheduled-section"

    /// Where the script says every destination succeeded. A file rather
    /// than an exit code because the script ends by booting its own agent
    /// out of launchd, so its status is `launchctl`'s and not the
    /// deploy's.
    nonisolated static func successSentinelURL(
        courseCode: String,
        sectionNumber: Int,
        inHomeFolder home: URL? = nil
    ) -> URL {
        let label: String = agentLabel(courseCode: courseCode, sectionNumber: sectionNumber)
        return (home ?? homeForScheduledNotes)
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Plantoir")
            .appendingPathComponent("scheduled")
            .appendingPathComponent("\(label).succeeded")
    }

    /// The course folder and section a `--scheduled-section` invocation
    /// names, or nil when it names none.
    nonisolated static func requestedSection(
        from arguments: [String]
    ) -> (courseDirectory: URL, courseCode: String, sectionNumber: Int)? {
        guard let index = arguments.firstIndex(of: sectionFlag), index + 3 < arguments.count,
              let sectionNumber = Int(arguments[index + 3]) else {
            return nil
        }
        let workspace: URL = URL(fileURLWithPath: arguments[index + 1])
        let courseCode: String = arguments[index + 2]
        return (
            workspace.appendingPathComponent("courses").appendingPathComponent(courseCode),
            courseCode,
            sectionNumber
        )
    }

    /// Take the fired agent out of launchd, now that its work is finished.
    ///
    /// Best effort on purpose: the plist is already gone by this point, so an
    /// agent left registered cannot fire again — it is untidy rather than
    /// dangerous, and a failure here must not take a publish's own exit code
    /// with it.
    nonisolated static func bootOutAgent(courseCode: String?, sectionNumber: Int?) {
        guard let courseCode, let sectionNumber else {
            return
        }
        bootOutAgent(label: agentLabel(courseCode: courseCode, sectionNumber: sectionNumber))
    }

    /// The same, for a caller that has the LABEL and not the pair.
    ///
    /// A plist written before v1.2.0 carries no course code and no section
    /// number — three `ProgramArguments`, no `--scheduled-section` — so the
    /// stand-down path has only the label, taken from the wrapper script's own
    /// name. Every plist any release ever wrote is named after its label.
    ///
    /// It runs `/bin/launchctl` directly rather than through `LaunchControl`,
    /// so the refusal that guards every other launchctl call does not guard
    /// this one. That is safe only because its callers (`runScheduled`,
    /// `standDown`) end the process and no test can reach them — route it
    /// through `LaunchControl.run` before calling it from anywhere else.
    nonisolated static func bootOutAgent(label: String) {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    /// The script a `--run-scheduled-deploy` invocation should run, or nil
    /// when this is an ordinary launch.
    nonisolated static func requestedScript(from arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: runFlag), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    /// Where this section's agent is written. `~/Library/LaunchAgents` is
    /// the teacher's own folder — no administrator rights, and nothing of
    /// ours outside it.
    nonisolated static func plistURL(courseCode: String, sectionNumber: Int) -> URL {
        let label: String = agentLabel(courseCode: courseCode, sectionNumber: sectionNumber)
        return launchAgentsDirectoryURL().appendingPathComponent("\(label).plist")
    }

    /// A folder to write agents into instead of the teacher's own.
    ///
    /// Set only by tests. A test that wrote into the real `LaunchAgents`
    /// folder would leave a deploy scheduled on the machine running the
    /// suite — which is exactly the kind of surprise this feature exists
    /// to make deliberate. `LaunchControl.run` refuses outright while it is
    /// set, so a test that forgets `FakeLaunchControl` fails rather than
    /// reaching the teacher's own agents.
    ///
    /// `nonisolated(unsafe)` so that the run fired by launchd — which is
    /// `nonisolated` and never becomes an app — can ask where the agents are
    /// through the same two functions everything else uses, rather than
    /// carrying a second answer to that question. It is written by tests, on
    /// one thread, before anything reads it; `ActivityTrail.store` is
    /// replaceable on the same terms and for the same reason.
    nonisolated(unsafe) static var launchAgentsDirectoryOverride: URL?

    /// Where the agents are.
    ///
    /// **Under the suite with no override, an empty throwaway folder** — never
    /// the teacher's real `~/Library/LaunchAgents` (issue #240). Every test
    /// that points a `WorkspaceModel` at a folder runs the sweep for deploys
    /// that are too late, every sidebar row asks for its clock, and every
    /// scheduling card asks what it would replace; on 2026-09-23 a probe
    /// counted about 344 reaches of the real folder in one run of the suite,
    /// each passing whatever that Mac happened to have scheduled. Reads only,
    /// but a transcript that depends on the machine running it is not a test.
    ///
    /// The half that makes this safe rather than dangerous is in
    /// `LaunchControl.run`: it refuses under the suite whether or not the
    /// override is set, so a plist a test writes here can never be handed to
    /// the real `launchd`.
    nonisolated static func launchAgentsDirectoryURL() -> URL {
        if let launchAgentsDirectoryOverride {
            return launchAgentsDirectoryOverride
        }
        return homeForScheduledNotes
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
    }

    /// Where the agent's own output goes. A deploy that ran at half six
    /// with nobody watching has to have left something behind, or a
    /// failure is invisible until a student says the site is stale.
    nonisolated static func logURL(
        courseCode: String,
        sectionNumber: Int,
        inHomeFolder home: URL? = nil
    ) -> URL {
        let label: String = agentLabel(courseCode: courseCode, sectionNumber: sectionNumber)
        return (home ?? homeForScheduledNotes)
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
            .appendingPathComponent("Plantoir")
            .appendingPathComponent("\(label).log")
    }

    // MARK: - Planning

    /// Why this deploy cannot be scheduled, or nil when it can be.
    ///
    /// Everything refused here is something that would ASK A QUESTION at
    /// the scheduled moment. Attended, those questions get answered;
    /// scheduled, they wait at half six with nobody there, and the class
    /// site is not updated. So the questions are put now instead.
    static func problem(
        course: Course,
        sectionNumber: Int,
        when: Date,
        now: Date,
        cloudflareAccountID: String,
        locale: Locale = Locale.current
    ) -> String? {
        // FIRST, before "that time has already passed": a course kept for
        // reference is refused whatever time was asked for, and telling the
        // teacher to pick a different time would send them round a loop that
        // ends in the same place.
        if course.isKeptForReference {
            return AssistWording.deployRefusedForAReferenceCourse(course: course.displayCode)
        }
        if when <= now {
            return "\(dayAndTimeText(when, locale: locale)) has already passed. Pick a time still to come."
        }

        let configuration: CourseConfiguration = course.configuration

        // The PRIMARY destination — unchanged wording and order from
        // before a course could have more than one, so every existing
        // check against this function still passes byte for byte.
        if configuration.deployTarget == "local_folder" {
            if let folderProblem = CourseConfiguration.deployFolderProblem(forPath: configuration.deployFolderPath) {
                return "\(course.code) deploys to a folder, and that folder needs attention first: \(folderProblem)"
            }
        }

        // Cloudflare needs an Account ID that only the app has. Unlike the
        // Windows app — where the scheduled task cannot be handed one —
        // the plist carries `--account`, so the question is asked HERE and
        // answered once rather than making Cloudflare unschedulable.
        if configuration.deploysToCloudflare {
            if let accountProblem = CourseConfiguration.cloudflareAccountProblem(forID: cloudflareAccountID) {
                return "\(course.code) deploys to Cloudflare Pages, which needs your Account ID. \(accountProblem) Add it in this course’s settings, under Deploying, then schedule this again."
            }
        }

        // Every ADDITIONAL destination gets the same two checks — a
        // redundancy target with no valid folder or credential would
        // otherwise sit silently broken until the scheduled moment,
        // exactly the surprise asking everything up front exists to
        // prevent.
        for target in configuration.additionalDeployTargets {
            if target.type == "local_folder" {
                if let folderProblem = CourseConfiguration.deployFolderProblem(forPath: target.path) {
                    return "\(course.code) also deploys to a folder, and that folder needs attention first: \(folderProblem)"
                }
            }
            if target.type == "cloudflare_pages" {
                if let accountProblem = CourseConfiguration.cloudflareAccountProblem(forID: cloudflareAccountID) {
                    return "\(course.code) also deploys to Cloudflare Pages, which needs your Account ID. \(accountProblem) Add it in this course’s settings, under Deploying, then schedule this again."
                }
            }
        }

        if !DeployCommand.hasDeployedBefore(section: sectionNumber, in: course) {
            return "\(course.code) Section \(sectionNumber) has never been deployed, so deploying it asks what to call the website. Nobody would be there to answer that at the scheduled time, and it would wait. Deploy it once from Plantoir, and after that it can be scheduled."
        }

        // Same reasoning, for any additional destination that has never
        // gone out — a brand-new Netlify or Cloudflare destination also
        // asks what to call the site, and local_folder never does
        // (`hasDeployedBefore` reports it as always ready).
        for target in configuration.additionalDeployTargets {
            if !DeployCommand.hasDeployedBefore(section: sectionNumber, in: course, destinationType: target.type) {
                let destinationName: String = DeployCommand.destinationDescription(
                    for: CourseConfiguration.DeployDestination(type: target.type, path: target.path)
                )
                return "\(course.code) Section \(sectionNumber) has never been deployed to \(destinationName), so deploying it there asks what to call that site. Nobody would be there to answer that at the scheduled time, and it would wait. Deploy it there once from Plantoir, and after that it can be scheduled."
            }
        }

        return nil
    }

    /// Describes what scheduling would do, changing nothing.
    ///
    /// The words are meant to be read aloud, so they say what has to be
    /// true of the Mac and what happens when it isn't.
    static func plan(
        course: Course,
        sectionNumber: Int,
        when: Date,
        now: Date,
        cloudflareAccountID: String,
        locale: Locale = Locale.current
    ) -> ScheduledDeployPlan {
        return ScheduledDeployPlan(
            courseCode: course.code,
            sectionNumber: sectionNumber,
            when: when,
            destination: DeployCommand.destinationDescription(for: course.configuration),
            unpublishedClasses: unpublishedClasses(course: course, sectionNumber: sectionNumber),
            problem: problem(
                course: course,
                sectionNumber: sectionNumber,
                when: when,
                now: now,
                cloudflareAccountID: cloudflareAccountID,
                locale: locale
            ),
            replacing: momentBeingReplaced(
                courseCode: course.code, sectionNumber: sectionNumber, by: when, now: now
            ),
            locale: locale
        )
    }

    /// The section's class pages students cannot see yet, by name.
    ///
    /// Not a refusal — a teacher may well be deploying deliberately
    /// without them — but worth saying before a site goes out on its own.
    static func unpublishedClasses(course: Course, sectionNumber: Int) -> [String] {
        var held: [String] = []
        for page in ClassPages.list(forSection: sectionNumber, in: course) {
            guard let text = try? String(contentsOf: page.fileURL, encoding: .utf8) else {
                continue
            }
            let isVisible: Bool = AssistPageVisibility.publishes(
                in: text,
                forSection: sectionNumber
            )
            if !isVisible {
                held.append(page.title)
            }
        }
        return held
    }

    // MARK: - The launchd agent

    /// The agent, as a property list.
    ///
    /// Built separately from anything that writes or loads it, so the
    /// exact plist a teacher would get can be inspected in a test without
    /// touching the real launchd.
    static func propertyList(
        courseCode: String,
        sectionNumber: Int,
        when: Date,
        workspaceURL: URL,
        deployArguments: [String],
        calendar: Calendar = Calendar.current,
        homeFolder: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String: Any] {
        let label: String = agentLabel(courseCode: courseCode, sectionNumber: sectionNumber)
        let components: DateComponents = calendar.dateComponents([.month, .day, .hour, .minute], from: when)

        var schedule: [String: Any] = [:]
        schedule["Month"] = components.month ?? 1
        schedule["Day"] = components.day ?? 1
        schedule["Hour"] = components.hour ?? 0
        schedule["Minute"] = components.minute ?? 0

        var environment: [String: String] = [:]
        // A launchd agent starts with a bare PATH; the launcher needs to find
        // docker and colima the way a Terminal session does. Same definition
        // ScriptRunner uses when the app runs a launcher itself, and the same
        // one the quit path uses — and it begins with the folder the
        // launchers download the pinned copies into, which this list used to
        // leave out entirely. A scheduled publish on a Mac without Homebrew
        // was reaching the engine only because the launcher re-exports that
        // folder itself.
        environment["PATH"] = HelperPrograms.pathValue(inheriting: nil, inHomeFolder: homeFolder)
        environment[scheduledForKey] = ISO8601DateFormatter().string(from: when)

        var plist: [String: Any] = [:]
        plist["Label"] = label
        // **Launched through PLANTOIR, not through bash, and this is the
        // whole reason a scheduled deploy works at all.**
        //
        // It used to be `/bin/bash -c <script>`, which failed in two ways at
        // once, both reported by a teacher on the same evening:
        //
        // 1. **macOS could not name it.** The Background Activity notice said
        //    `"bash" can run in the background`, which tells somebody nothing
        //    about which of their applications asked for it, and reads like
        //    something that should be turned off.
        // 2. **It had no permission to read the teacher's files.** A launchd
        //    agent running a bare interpreter has no application identity, so
        //    macOS's privacy system grants it nothing — and a working folder
        //    on the Desktop is protected. The log from a real 9:49 PM run is
        //    `Operation not permitted` on every path, including `getcwd`,
        //    while the identical deploy from the app seven minutes earlier
        //    finished in 144 seconds. Same files, same script, different
        //    caller.
        //
        // Running the app's own signed binary fixes the second outright and
        // the first as far as macOS allows.
        //
        // **What the notice actually says is the signing certificate's
        // ORGANISATION — "Russell Gordon" — not "Plantoir", and that is Apple's
        // design rather than a fault here.** Background Task Management lists
        // background items by developer, which is why that pane shows "Google
        // LLC" and "Dropbox, Inc." rather than Chrome and Dropbox. Verified
        // against the certificate: `O=Russell Gordon`, and that is the string
        // shown. It is a large improvement on "bash", which named nobody.
        //
        // **Getting the app's own name there would mean `SMAppService.agent`,
        // and it cannot work here.** That API associates an agent with the app
        // bundle, but only for a plist BAKED INTO the bundle at build time —
        // and this plist's whole content is a `StartCalendarInterval` chosen
        // by the teacher, one per course and section. A bundled plist cannot
        // carry a time that changes. Rejected for that reason, not overlooked;
        // do not propose it again without a way to express a per-section alarm.
        //
        // The permission half is what actually mattered: a script the APP
        // spawns is attributed to the app, which is exactly why pressing
        // Deploy has always worked.
        plist["ProgramArguments"] = [
            Bundle.main.executableURL?.path ?? "/bin/bash",
            runFlag,
            scriptURL(courseCode: courseCode, sectionNumber: sectionNumber).path,
            sectionFlag,
            workspaceURL.path,
            courseCode,
            String(sectionNumber),
        ]
        plist["StartCalendarInterval"] = schedule
        plist["WorkingDirectory"] = workspaceURL.path
        plist["EnvironmentVariables"] = environment
        plist["StandardOutPath"] = logURL(courseCode: courseCode, sectionNumber: sectionNumber).path
        plist["StandardErrorPath"] = logURL(courseCode: courseCode, sectionNumber: sectionNumber).path
        // Loading the agent must not deploy on the spot: the teacher's
        // "Go ahead" set an alarm, it did not consent to a deploy now.
        plist["RunAtLoad"] = false
        return plist
    }

    /// What the agent actually runs: the deploy, once, and then itself out
    /// of existence.
    ///
    /// `StartCalendarInterval` has no "just this once" — a month and day
    /// come round again every year — so a fired agent that did not clear
    /// itself away would sit in launchd for twelve months and then deploy
    /// a course that may not exist any more. The plist is removed FIRST,
    /// so even a Mac that restarts mid-deploy comes back with nothing
    /// pending, and the job boots itself out LAST, once the deploy is done.
    ///
    /// **This is still the FIRST line of defence and not the only one.** It
    /// only ever helped a job that RAN; a job whose moment passed while the Mac
    /// was off never reached this script at all and came due a year later
    /// anyway. Since 2026-09-20 the run re-checks its own moment before the
    /// script is reached, and stands down past the course's window — so the
    /// annual return is closed for a job that never ran too. See
    /// `ScheduledDeployLateness` and `standDown`.
    static func oneShotCommand(
        courseCode: String,
        sectionNumber: Int,
        workspaceURL: URL,
        deployArgumentsList: [[String]],
        destinationTypes: [String] = [],
        destinationDescriptions: [String] = [],
        // Defaulted to the real home, and takeable so a test can drive the
        // GENERATED SHELL for real without writing into the teacher's own
        // Application Support. BuildOutputLocation.buildsRoot takes one for
        // the same reason, and the comment there says why it had to.
        homeFolder: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        let label: String = agentLabel(courseCode: courseCode, sectionNumber: sectionNumber)
        let plistPath: String = plistURL(courseCode: courseCode, sectionNumber: sectionNumber).path
        let scriptPath: String = workspaceURL.appendingPathComponent(DeployCommand.scriptName).path
        let logDirectory: String = logURL(
            courseCode: courseCode, sectionNumber: sectionNumber, inHomeFolder: homeFolder
        ).deletingLastPathComponent().path

        // One line per configured destination. Deliberately NOT chained
        // with `&&` — a destination failing must not stop the others from
        // running, which is the entire point of a course having more than
        // one. Only a failed BUILD (below, `$READY`) skips every line.
        var deployLines: [String] = []
        for arguments in deployArgumentsList {
            var deployLine: String = "/bin/bash \(shellQuoted(scriptPath))"
            for argument in arguments {
                deployLine += " \(shellQuoted(argument))"
            }
            deployLines.append(deployLine)
        }

        // BUILD IF STALE, THEN DEPLOY — exactly what the Deploy button does.
        //
        // `deploy.sh` never builds; it refuses outright when there is no
        // built site. So an agent that ran it alone would either fail at
        // half six or send whatever was last previewed.
        //
        // The staleness test is `BuildFreshness.needsRebuild` written out in
        // shell, because the app is closed when this runs and cannot be
        // asked. It has to stay in step with the Swift, so all three of its
        // parts are here — and the second is the one that matters most.
        let previewPath: String = workspaceURL.appendingPathComponent("preview.sh").path
        let builtIndexPath: String = workspaceURL
            .appendingPathComponent("courses")
            .appendingPathComponent(courseCode)
            .appendingPathComponent(".merged_output")
            .appendingPathComponent("section\(sectionNumber)")
            .appendingPathComponent("public")
            .appendingPathComponent("index.html")
            .path
        let courseDirectoryPath: String = workspaceURL
            .appendingPathComponent("courses")
            .appendingPathComponent(courseCode)
            .path

        // --non-interactive on the BUILD leg as well as the deploy, and this
        // is the half that is easy to miss: the agent runs preview.sh
        // DIRECTLY, so a question there is asked with nobody in front of it
        // just as surely as one from deploy.sh. preview.sh has no `set -e`,
        // so without the flag its 'Open' course-code guard reads at end of
        // input, takes the [Y/n] DEFAULT, and builds a DIFFERENT course —
        // which then publishes successfully against the wrong course. A
        // refusal is the better failure.
        let buildLine: String = "/bin/bash \(shellQuoted(previewPath)) "
            + "\(shellQuoted(courseCode)) \(shellQuoted(String(sectionNumber))) "
            + "--build-only --non-interactive"

        var lines: [String] = []
        lines.append("/bin/mkdir -p \(shellQuoted(logDirectory))")
        lines.append("/bin/rm -f \(shellQuoted(plistPath))")

        lines.append("NEEDS_BUILD=1")
        lines.append("if [ -f \(shellQuoted(builtIndexPath)) ]; then")
        // A PREVIEW's build is never deploy-fresh. Serve mode bakes a
        // live-reload client pointed at ws://localhost into every page, and
        // deploying that makes a visitor's browser knock on their own
        // machine. Rebuilding is the only way to be rid of it, however
        // recent the build looks.
        lines.append("  if /usr/bin/grep -q 'ws://localhost:' \(shellQuoted(builtIndexPath)); then")
        lines.append("    NEEDS_BUILD=1")
        lines.append("  elif [ -z \"$(/usr/bin/find \(shellQuoted(courseDirectoryPath))"
            + " -type f -newer \(shellQuoted(builtIndexPath)) -not -path '*/.*' -print -quit)\" ]; then")
        // Nothing under the course is newer than the built page, so the site
        // on disk already says what the teacher means. Rebuilding it at half
        // six would cost a container start and a full Quartz run to produce
        // the same bytes.
        lines.append("    NEEDS_BUILD=0")
        lines.append("  fi")
        lines.append("fi")

        // `-not -path '*/.*'` is the shell's version of skipsHiddenFiles,
        // and it earns its place: without it, .merged_output is itself
        // newer than the page it contains, so the site would look stale the
        // instant it was built and rebuild every single time.
        let stoppedDirectory: String = ScheduledPublishOutcome
            .directory(inHomeFolder: homeFolder).path
        let stoppedRecord: String = ScheduledPublishOutcome.recordURL(
            inHomeFolder: homeFolder,
            course: courseCode,
            section: sectionNumber
        ).path
        // Every record is assembled here and MOVED into place, so the app's
        // watch on the record folder sees one event carrying a whole file. See
        // `recordCompletionLines` and `ScheduledPublishOutcome.partialRecordURL`
        // — including why this sits beside the record folder rather than in it.
        let stoppedPartialRecord: String = ScheduledPublishOutcome.partialRecordURL(
            inHomeFolder: homeFolder,
            course: courseCode,
            section: sectionNumber
        ).path

        // Clear LAST time's record before this run does anything.
        //
        // Without this, "the first destination that stopped wins" quietly
        // becomes "the first destination that stopped SINCE THE LAST CLEARED
        // RUN wins": a record from last week that nobody dismissed blocks
        // tonight's from being written at all, so tonight's failure — a
        // different destination, possibly a different kind — reaches neither
        // the teacher nor the trail. Within one run the first still wins,
        // which is what was meant.
        lines.append("/bin/rm -f \(shellQuoted(stoppedRecord))")

        lines.append("READY=1")
        lines.append("if [ \"$NEEDS_BUILD\" = \"1\" ]; then")
        lines.append("  \(buildLine)")
        lines.append("  BUILD_RC=$?")
        lines.append("  if [ $BUILD_RC -ne 0 ]; then")
        lines.append("    READY=0")
        // A failed BUILD is a stopped scheduled publish too, and this is the
        // case the flag itself created: preview.sh --non-interactive REFUSES
        // the course-code guard and exits 3, and every deploy line below is
        // skipped when READY=0 — so without this the teacher would be told
        // nothing at all about the one failure this change introduced.
        //
        // Exit 3 HERE is its own kind, and not the one a destination gets.
        // Nothing was published because nothing was reached, so the sentence
        // names no destination and sends the teacher to Preview — previewing
        // is what asks the question. Until GitHub issue #132, proposed from
        // Windows, this wrote `neededAnAnswer` with a stand-in destination and
        // told a teacher that publishing to a site nobody had contacted needed
        // an answer.
        lines.append("    /bin/mkdir -p \(shellQuoted(stoppedDirectory))")
        lines.append("    if [ $BUILD_RC -eq 3 ]; then")
        lines.append("      /bin/echo \(shellQuoted(ScheduledPublishOutcome.Kind.buildNeededAnAnswer.rawValue))"
            + " > \(shellQuoted(stoppedPartialRecord))")
        lines.append("    else")
        lines.append("      /bin/echo \(shellQuoted(ScheduledPublishOutcome.Kind.didNotFinish.rawValue))"
            + " > \(shellQuoted(stoppedPartialRecord))")
        lines.append("    fi")
        // Written for BOTH build branches. The outright failure puts it in
        // the teacher's sentence; buildNeededAnAnswer never shows it, and it
        // is written anyway so every record has one shape for the reader — see
        // ScheduledPublishOutcome.buildDestinationName.
        for completion in recordCompletionLines(
            indentedBy: "    ",
            destination: ScheduledPublishOutcome.buildDestinationName,
            temporaryPath: stoppedPartialRecord,
            recordPath: stoppedRecord
        ) {
            lines.append(completion)
        }
        lines.append("  fi")
        lines.append("fi")
        // Deploy only if there is something good to deploy — the button
        // returns early on a failed build rather than sending the previous
        // one, and an unattended run must not be less careful.
        // Every destination's own result is tracked, because the section
        // is only marked as published when EVERY one of them worked — a
        // course publishing to two hosts, one of which failed, has not
        // published. The sentinel is what tells the app that, since this
        // script's own exit status belongs to `launchctl bootout` below.
        let sentinelPath: String = successSentinelURL(
            courseCode: courseCode, sectionNumber: sectionNumber, inHomeFolder: homeFolder
        ).path
        lines.append("/bin/rm -f \(shellQuoted(sentinelPath))")
        lines.append("ALL_OK=\"$READY\"")
        // A stopped run leaves a note the app reads: at once, if the teacher is
        // looking at that section (`ScheduledPublishWatcher` watches the folder
        // these are moved into), and otherwise the next time they open it.
        // Until this existed, an overnight publish that did not
        // get through said so in the section's own log and NOWHERE else — so
        // "my site did not update on Tuesday and I do not know why" had no
        // answer, and a run that stopped looked exactly like one that was never
        // scheduled.
        //
        // Exit 3 is deploy.sh and deploy.py's NEEDS_AN_ANSWER and means that
        // alone; it is tested BEFORE the general non-zero branch because it is
        // also non-zero. Any other failure is recorded too — a revoked token, a
        // network that was down — because the SILENCE is the teacher's
        // complaint, not the cause. Where the two platforms stand on this is
        // compared in contracts/shared-rules.json → scheduledPublishStopped →
        // platformDifferences, and nowhere else, so it cannot rot in four
        // places at once.
        //
        // This is the DESTINATION leg, so exit 3 here is `neededAnAnswer` and
        // not the build's own kind: deploy.sh was reached, and the question it
        // refused is one the Publish button asks.
        //
        // ONE path through deploy.sh escapes that and is filed rather than
        // fixed here (GitHub issue #136). Publishing to a FOLDER — and only to
        // a folder — reruns preview.sh --build-only itself when any page under
        // the section's `public/` carries `ws://localhost:`, and passes its
        // exit 3 straight through: a BUILD question, reported from here as
        // though the folder had asked it. Netlify and Cloudflare go through
        // deploy.py, whose rebuild runs build_site.py directly, asks nothing
        // and fails with 1, so they land in `didNotFinish` honestly. It needs
        // NEEDS_BUILD=0 above, which is BuildFreshness.needsRebuild written
        // out in shell and looks at `index.html` ALONE, while deploy.sh greps
        // the whole tree. So a clean front page in front of a stale preview
        // page reaches it. Bringing the two checks into step is a change to
        // BuildFreshness as well as to this script and belongs to its own
        // piece of work; the exit code cannot tell the two apart, and giving
        // the rebuild its own code is a launcher contract change Windows
        // shares.
        //
        // The FIRST destination that stopped is the one kept: a course can
        // publish to several and only one may have gone wrong, so overwriting
        // would report the last thing rather than the first.
        lines.append("if [ \"$READY\" = \"1\" ]; then")
        var legIndex: Int = 0
        for deployLine in deployLines {
            var name: String = "your website"
            if legIndex < destinationDescriptions.count {
                name = destinationDescriptions[legIndex]
            } else if legIndex < destinationTypes.count {
                name = destinationTypes[legIndex]
            }
            lines.append("  \(deployLine)")
            lines.append("  RC=$?")
            lines.append("  if [ $RC -ne 0 ]; then")
            lines.append("    ALL_OK=0")
            lines.append("    if [ ! -f \(shellQuoted(stoppedRecord)) ]; then")
            lines.append("      /bin/mkdir -p \(shellQuoted(stoppedDirectory))")
            lines.append("      if [ $RC -eq 3 ]; then")
            lines.append("        /bin/echo \(shellQuoted(ScheduledPublishOutcome.Kind.neededAnAnswer.rawValue))"
                + " > \(shellQuoted(stoppedPartialRecord))")
            lines.append("      else")
            lines.append("        /bin/echo \(shellQuoted(ScheduledPublishOutcome.Kind.didNotFinish.rawValue))"
                + " > \(shellQuoted(stoppedPartialRecord))")
            lines.append("      fi")
            for completion in recordCompletionLines(
                indentedBy: "      ",
                destination: name,
                temporaryPath: stoppedPartialRecord,
                recordPath: stoppedRecord
            ) {
                lines.append(completion)
            }
            lines.append("    fi")
            lines.append("  fi")
            legIndex += 1
        }
        lines.append("fi")
        // Cleared only by a run that got all the way through — every
        // destination, exit zero — and only after every destination has run.
        // The teacher can also dismiss it in the app, which is where this side
        // differs from Windows: clearing only on success leaves the message
        // standing after somebody has already fixed the problem by hand, and
        // the next scheduled run that would clear it could be a week away.
        // A run that got through records that it DID, rather than only
        // deleting the evidence that it did not. Same reason as the failures:
        // a scheduled publish leaving no trace cannot be told from one that
        // never happened, so the trail could answer "why did my site not
        // update?" and could not answer "did it?".
        lines.append("if [ \"$ALL_OK\" = \"1\" ]; then")
        lines.append("  /bin/mkdir -p \(shellQuoted(stoppedDirectory))")
        lines.append("  /bin/echo \(shellQuoted(ScheduledPublishOutcome.Kind.succeeded.rawValue))"
            + " > \(shellQuoted(stoppedPartialRecord))")
        var whereItWent: String = destinationDescriptions.joined(separator: ", ")
        if destinationDescriptions.isEmpty {
            whereItWent = destinationTypes.joined(separator: ", ")
        }
        for completion in recordCompletionLines(
            indentedBy: "  ",
            destination: whereItWent,
            temporaryPath: stoppedPartialRecord,
            recordPath: stoppedRecord
        ) {
            lines.append(completion)
        }
        lines.append("fi")
        // The sentinel carries WHERE it went, so the record a scheduled
        // publish leaves is the same shape as the button's.
        lines.append(
            "if [ \"$ALL_OK\" = \"1\" ]; then /bin/echo "
            + shellQuoted(destinationTypes.joined(separator: " "))
            + " > \(shellQuoted(sentinelPath)); fi"
        )
        // NO `launchctl bootout` here, and that is a fix rather than an
        // omission. It used to be this script's last line, and it killed the
        // publish's own parent: the agent runs THIS APP, which runs this
        // script and then does its post-run work — recording the publish,
        // reading folder problems out of the log, and writing the trail line
        // for a run that stopped. Booting the job out from inside the script
        // ends the job, and the app IS the job, so none of that work ever ran.
        //
        // Measured 2026-09-09 with a real scheduled deploy: the wrapper wrote
        // its stopped record at 05:38:09 and the trail got nothing. Running
        // the identical app arguments against a script that does NOT boot out
        // wrote the line immediately, and dated it 05:38:09 — the run's own
        // time, not the moment of reading.
        //
        // So the app boots the job out itself, after its work is done. The
        // property the old line was protecting is kept: the PLIST is still
        // removed first, so a Mac that restarts mid-deploy comes back with
        // nothing pending, whatever happens to the job afterwards.
        return lines.joined(separator: "\n")
    }

    /// The two shell lines that finish a record and put it in the folder the
    /// app watches, in ONE move.
    ///
    /// Only the TAIL of the write, deliberately: two of the three places that
    /// record an outcome choose the kind in shell rather than in Swift
    /// (`if [ $BUILD_RC -eq 3 ]`, `if [ $RC -eq 3 ]`), so a helper that took the
    /// kind as an argument could serve only the third — or would need a `$KIND`
    /// expression, which must not go through `shellQuoted` since that would
    /// quote the dollar sign. Each branch writes its own kind into the temporary
    /// file with `>`; this adds the destination line and moves the finished file
    /// into place.
    ///
    /// **Why a temporary file and a move rather than two `echo`s** — and why the
    /// temporary file sits in the PARENT of the record folder — is measured, with
    /// the numbers, in `ScheduledPublishOutcome.partialRecordURL`. The short
    /// version: the app watches that folder so the notice can appear while the
    /// teacher is looking at the section, and a record written in two steps was
    /// delivered as one event carrying half a file, 0 times out of 40.
    ///
    /// Nothing about FAILURE changes. The generated wrapper has no `set -e`, so a
    /// write that fails leaves an empty temporary file, which `mv` then installs,
    /// and an empty record reads as no record at all — exactly what a failed
    /// `echo` straight into the record produced before. A failed `mv` leaves no
    /// record, likewise.
    static func recordCompletionLines(
        indentedBy indent: String,
        destination: String,
        temporaryPath: String,
        recordPath: String
    ) -> [String] {
        var result: [String] = []
        result.append(
            "\(indent)/bin/echo \(shellQuoted(destination)) >> \(shellQuoted(temporaryPath))"
        )
        result.append(
            "\(indent)/bin/mv \(shellQuoted(temporaryPath)) \(shellQuoted(recordPath))"
        )
        return result
    }

    /// One argument, safe to paste into a shell command.
    ///
    /// The rule itself moved to `HelperPrograms`, which had to quote a home
    /// folder into a generated script for the same reason; this stays as the
    /// name the rest of this file and its tests already use, because two
    /// implementations of "how is a path put into a script" is one more than
    /// anybody can keep in step.
    static func shellQuoted(_ value: String) -> String {
        return HelperPrograms.shellQuoted(value)
    }

    // MARK: - Applying

    /// Sets the alarm. Returns nil on success, or what went wrong in words
    /// the teacher can act on.
    ///
    /// Scheduling the same section twice replaces rather than stacks: the
    /// label is fixed per section, and the previous agent is booted out
    /// before the new one is written.
    @discardableResult
    static func scheduleDeploy(
        course: Course,
        sectionNumber: Int,
        when: Date,
        workspaceURL: URL,
        cloudflareAccountID: String,
        runner: LaunchControlRunning = LaunchControl()
    ) -> String? {
        // The BACKSTOP on the act, not on the advice. `problem()` is
        // advisory — a caller may read it and go ahead anyway — and this is
        // the function that actually writes a plist into the teacher's
        // LaunchAgents folder. Both callers check `problem()` first today, so
        // there is no hole; the guard is here because one guard in one caller
        // is one edit away from being gone, which is the same argument the
        // headless deploy path's backstop was written under.
        if course.isKeptForReference {
            return AssistWording.deployRefusedForAReferenceCourse(course: course.displayCode)
        }
        let scriptURL: URL = workspaceURL.appendingPathComponent(DeployCommand.scriptName)
        if !FileManager.default.fileExists(atPath: scriptURL.path) {
            return "This working folder is missing a piece it needs (\(DeployCommand.scriptName)), so there is nothing to schedule."
        }

        // One argument list per configured destination — the same order
        // `CourseConfiguration.allDeployDestinations` deploys in: the
        // primary first, then each additional destination.
        var deployArgumentsList: [[String]] = []
        var destinationDescriptions: [String] = []
        for destination in course.configuration.allDeployDestinations {
            destinationDescriptions.append(DeployCommand.destinationDescription(for: destination))
            deployArgumentsList.append(DeployCommand.arguments(
                courseCode: course.code,
                sectionNumber: sectionNumber,
                destination: destination,
                cloudflareAccountID: cloudflareAccountID,
                // The one caller that passes this. Nobody is at the Mac at
                // the scheduled moment, so the launcher must refuse a
                // question rather than wait for an answer or pick one.
                unattended: true
            ))
        }
        let plist: [String: Any] = propertyList(
            courseCode: course.code,
            sectionNumber: sectionNumber,
            when: when,
            workspaceURL: workspaceURL,
            deployArguments: deployArgumentsList.first ?? []
        )
        let destinationURL: URL = plistURL(courseCode: course.code, sectionNumber: sectionNumber)

        // What is about to be replaced, read BEFORE it goes (issue #195): once
        // the old agent is booted out and its plist overwritten, nothing
        // anywhere remembers it was ever set. Read here, in the one function
        // the sheet, the assistant and an outside assistant all reach, so the
        // trail line cannot be missing from one of them.
        let replacing: Date? = momentBeingReplaced(
            courseCode: course.code, sectionNumber: sectionNumber, by: when
        )
        // What is on this Mac for the section AT ALL, same minute included —
        // for the record of a replacement that fails, which must say what was
        // lost even when the card rightly said nothing.
        let alreadySet: Date? = momentAlreadySet(
            courseCode: course.code, sectionNumber: sectionNumber
        )

        // Anything already scheduled for this section goes first, so the
        // replacement is never briefly a second agent.
        runner.bootOut(label: agentLabel(courseCode: course.code, sectionNumber: sectionNumber))

        do {
            // The script the app will run, written beside nothing else and
            // executable, so launchd's job is only "start Plantoir with this
            // file" and every decision stays in one place.
            let commandURL: URL = ScheduledDeploy.scriptURL(
                courseCode: course.code, sectionNumber: sectionNumber
            )
            try FileManager.default.createDirectory(
                at: commandURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let command: String = "#!/bin/bash\n" + oneShotCommand(
                courseCode: course.code,
                sectionNumber: sectionNumber,
                workspaceURL: workspaceURL,
                deployArgumentsList: deployArgumentsList,
                destinationTypes: scheduledDestinationTypes(course: course),
                destinationDescriptions: destinationDescriptions
            ) + "\n"
            try command.write(to: commandURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: commandURL.path
            )

            try FileManager.default.createDirectory(
                at: launchAgentsDirectoryURL(),
                withIntermediateDirectories: true
            )
            let data: Data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            try data.write(to: destinationURL, options: [.atomic])
        } catch {
            // Every step that can throw comes before, or IS, the atomic plist
            // write — so the OLD plist is still on disk, only booted out. Put
            // it back in front of macOS, so that "it still stands" is true now
            // rather than from the next login, and say so.
            noteTheOldDeployAfterAFailedWrite(
                alreadySet, at: destinationURL, runner: runner,
                when: when, course: course, sectionNumber: sectionNumber
            )
            return "The scheduled deploy could not be written: \(error.localizedDescription)"
        }

        if let failure = runner.bootstrap(plistURL: destinationURL) {
            try? FileManager.default.removeItem(at: destinationURL)
            ActivityTrail.note(
                .scheduledDeployCouldNotBeSet,
                "could not set a scheduled deploy for \(dayAndTimeText(when)): macOS would not accept it",
                course: course.code,
                section: sectionNumber
            )
            noteTheReplacedDeployWasLost(alreadySet, course: course, sectionNumber: sectionNumber)
            return "macOS would not accept the scheduled deploy: \(failure)"
        }
        if let replacing {
            // "It went on Saturday; I set it for Friday" is otherwise a report
            // nothing can answer: the old job leaves no file behind.
            ActivityTrail.note(
                .scheduledDeployReplaced,
                "replaced the deploy set for \(dayAndTimeText(replacing)) "
                    + "with one set for \(dayAndTimeText(when))",
                course: course.code,
                section: sectionNumber
            )
        }
        return nil
    }

    /// The new deploy's files could not be written. The old one's plist is
    /// untouched on disk (the write that failed is atomic, and everything
    /// before it writes elsewhere), but it was booted out a moment ago — so it
    /// is handed back to macOS, and the trail says what is TRUE: the deploy
    /// already set still stands, or, if macOS would not take it back, that it
    /// was turned off. Silent when nothing was set.
    ///
    /// Known and left as it was: the one-shot script is written BEFORE the
    /// plist, at the same path for the section, so an old plist restored here
    /// runs whatever script the failed attempt managed to write.
    private static func noteTheOldDeployAfterAFailedWrite(
        _ alreadySet: Date?,
        at plistURL: URL,
        runner: LaunchControlRunning,
        when: Date,
        course: Course,
        sectionNumber: Int
    ) {
        let notSet: String = "could not set a scheduled deploy for \(dayAndTimeText(when))"
        guard let alreadySet else {
            ActivityTrail.note(
                .scheduledDeployCouldNotBeSet, notSet, course: course.code, section: sectionNumber
            )
            return
        }
        if FileManager.default.fileExists(atPath: plistURL.path)
            && runner.bootstrap(plistURL: plistURL) == nil {
            ActivityTrail.note(
                .scheduledDeployCouldNotBeSet,
                notSet + "; the one set for \(dayAndTimeText(alreadySet)) still stands",
                course: course.code,
                section: sectionNumber
            )
            return
        }
        ActivityTrail.note(
            .scheduledDeployCouldNotBeSet, notSet, course: course.code, section: sectionNumber
        )
        noteTheReplacedDeployWasLost(alreadySet, course: course, sectionNumber: sectionNumber)
    }

    /// The old deploy was booted out to make way for a new one, and the new
    /// one then failed — so the teacher has NEITHER, and the refusal they are
    /// shown speaks only of the new one (issue #195's review). Filed under
    /// `scheduled deploy turned off`, whose job is exactly this: a deploy
    /// turned off by something other than the teacher asking. Silent when
    /// nothing was set — and NOT silent for the same minute, which the card
    /// rightly leaves unsaid but whose loss is still a loss.
    private static func noteTheReplacedDeployWasLost(
        _ replacing: Date?,
        course: Course,
        sectionNumber: Int
    ) {
        guard let replacing else {
            return
        }
        ActivityTrail.note(
            .scheduledDeployTurnedOff,
            "turned off the scheduled deploy set for \(dayAndTimeText(replacing)) "
                + "to make way for a new one that could not be set",
            course: course.code,
            section: sectionNumber
        )
    }

    /// Run the one-shot script and leave, without ever becoming an app.
    ///
    /// Never returns. Same shape as `AssistMCPServer.serve` for the same
    /// reason: a process launched to do one job must not put a window on
    /// screen, register fonts, or touch the teacher's saved window state.
    ///
    /// Output is not captured here — launchd already points the agent's
    /// stdout and stderr at the section's log, and this process inherits
    /// them, so the script's own output lands where it always did.
    nonisolated static func runScheduled(
        script: String,
        section: (courseDirectory: URL, courseCode: String, sectionNumber: Int)? = nil,
        now: Date = Date()
    ) -> Never {
        // IS THIS STILL THE DAY IT WAS FOR? Asked before anything else
        // happens, because the answer can be no.
        //
        // `StartCalendarInterval` carries no year, and `RunAtLoad` is false,
        // so a job whose moment passed while the Mac was OFF is simply loaded
        // again at the next login and comes due on the same date TWELVE MONTHS
        // LATER — against whatever is in the working folder by then. Russell's
        // decision, 2026-09-20: a scheduled deploy is a one-off and must never
        // recur annually.
        //
        // This check reaches plists ALREADY ON DISK, which is why it is the
        // load-bearing half rather than the sweep: every released plist's
        // `ProgramArguments[0]` is the app's own binary, so an upgraded app
        // runs the new check for an old job the moment it next tries to fire.
        let moment: Date? = intendedMoment(forScript: script)
        let allowedDays: Int = allowedLatenessDays(forSection: section)
        if !ScheduledDeployLateness.mayStillRun(
            intendedMoment: moment, now: now, allowedDays: allowedDays
        ) {
            standDown(script: script, section: section, now: now)
        }

        // Taken BEFORE anything runs, for the same reason the Deploy
        // button takes it before its own build: a page edited while an
        // overnight publish is running did not go out, and stamping the
        // finishing state would mark it published.
        var fingerprintBeforeRunning: String?
        var logSizeBeforeRunning: UInt64 = 0
        if let section {
            fingerprintBeforeRunning = SectionPublishState.fingerprint(
                courseDirectory: section.courseDirectory,
                sectionNumber: section.sectionNumber
            )
            // launchd APPENDS to this log and nothing truncates it, so where it
            // ends now is where this run's own output begins.
            logSizeBeforeRunning = logSize(
                courseCode: section.courseCode, sectionNumber: section.sectionNumber
            )
        }

        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script]
        // This is the script that runs deploy.sh at half six, so it needs to
        // find the same programs the app does. It would inherit them from the
        // agent's own PATH today — but only because the plist above sets one,
        // and a second answer to "where are the helpers" is how the first one
        // drifts.
        process.environment = HelperPrograms.environment()
        do {
            try process.run()
            process.waitUntilExit()
            recordScheduledPublish(section: section, fingerprint: fingerprintBeforeRunning)
            // Publishes regardless; the findings are kept for somebody to read
            // when they are next at the machine.
            recordFolderProblems(section: section, fromByteOffset: logSizeBeforeRunning)
            // The trail line for a run that stopped, written HERE rather than
            // when a teacher opens the section. This process IS Plantoir
            // (--run-scheduled-deploy), so the redactor and the trail are
            // loaded — and a teacher who never opens the section is exactly
            // the one who reports "my site did not update", so a line that
            // waits for them to look is a line they never get.
            if let section {
                ScheduledPublishOutcome.noteOnTrail(
                    inHomeFolder: FileManager.default.homeDirectoryForCurrentUser,
                    course: section.courseCode,
                    section: section.sectionNumber
                )
            }
            // LAST, once the work above is done. See the note in
            // oneShotCommand: this used to be the wrapper's final line, which
            // killed this process before any of the three calls above ran.
            bootOutAgent(courseCode: section?.courseCode, sectionNumber: section?.sectionNumber)
            exit(process.terminationStatus)
        } catch {
            FileHandle.standardError.write(Data(
                "Plantoir could not run the scheduled deploy: \(error.localizedDescription)\n".utf8
            ))
            exit(1)
        }
    }

    // MARK: - Standing down: a job whose day has gone by

    /// The label a wrapper script's own path carries.
    ///
    /// `…/Application Support/Plantoir/scheduled/<label>.sh`, so the basename
    /// IS the label and `<label>.plist` is the agent. Taken from the SCRIPT
    /// rather than rebuilt from a course code and a section, because a plist
    /// written before v1.2.0 carries neither — and this has to work for every
    /// plist any release ever wrote, since those are exactly the jobs that
    /// have been sitting on teachers' Macs waiting to fire a year late.
    nonisolated static func label(fromScriptPath script: String) -> String? {
        let name: String = URL(fileURLWithPath: script).lastPathComponent
        guard name.hasSuffix(".sh") else {
            return nil
        }
        let label: String = String(name.dropLast(3))
        guard label.hasPrefix(labelPrefix) else {
            return nil
        }
        return label
    }

    /// The moment this run was set for.
    ///
    /// launchd hands the plist's `EnvironmentVariables` to the process it
    /// starts, so the stamp is normally right here in the environment. The
    /// plist is read as a fallback — it is still on disk at this instant,
    /// because only the wrapper deletes it and the wrapper has not run yet.
    ///
    /// nil when neither says, and `ScheduledDeployLateness` FAILS OPEN on a
    /// nil: a deploy the teacher asked for beats a refusal nobody sees.
    nonisolated static func intendedMoment(
        forScript script: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Date? {
        if let stamp = environment[scheduledForKey],
           let moment = ISO8601DateFormatter().date(from: stamp) {
            return moment
        }
        guard let label = label(fromScriptPath: script) else {
            return nil
        }
        let plistURL: URL = launchAgentsDirectoryURL()
            .appendingPathComponent("\(label).plist")
        return agent(readingPlistAt: plistURL)?.scheduledFor
    }

    /// How late this course lets a deploy be, read at the moment it fires.
    ///
    /// From the course's own settings in the working folder the job named, so
    /// a teacher who changed the setting after scheduling changes what the
    /// job already on disk does. A pre-v1.2.0 plist names no section and no
    /// folder, so it gets the default.
    nonisolated static func allowedLatenessDays(
        forSection section: (courseDirectory: URL, courseCode: String, sectionNumber: Int)?
    ) -> Int {
        guard let section else {
            return ScheduledDeployLateness.defaultDays
        }
        let workingFolderURL: URL = section.courseDirectory
            .deletingLastPathComponent()   // courses
            .deletingLastPathComponent()   // the working folder
        return ScheduledDeployLateness.days(
            forCourseCode: section.courseCode, inWorkingFolder: workingFolderURL
        )
    }

    /// Deploys nothing, clears the job away, and leaves the teacher a note.
    ///
    /// The order is the wrapper's own, for the wrapper's own reason: the
    /// PLIST goes first, so a Mac that restarts in the middle of this comes
    /// back with nothing pending, and the job is booted out LAST, because
    /// booting it out ends this very process.
    ///
    /// The note goes through the machinery a scheduled deploy that did not get
    /// through already has — a record the section shows, and a line on the
    /// trail — rather than through anything new: a teacher whose site did not
    /// update looks in one place, and this is that place.
    nonisolated static func standDown(
        script: String,
        section: (courseDirectory: URL, courseCode: String, sectionNumber: Int)?,
        now: Date = Date()
    ) -> Never {
        let fileManager: FileManager = FileManager.default
        if let label = label(fromScriptPath: script) {
            try? fileManager.removeItem(
                at: launchAgentsDirectoryURL().appendingPathComponent("\(label).plist")
            )
        }
        // The wrapper goes with it, for the reason `cancelScheduledDeploy`
        // takes it: a job that is off must not leave a runnable copy of
        // itself on disk.
        try? fileManager.removeItem(at: URL(fileURLWithPath: script))

        if let section {
            let home: URL = fileManager.homeDirectoryForCurrentUser
            // Anything an earlier run left is cleared first — the same thing
            // the wrapper does with its own first line, and for the same
            // reason: `recordStopped` keeps the FIRST record, so last week's
            // would block today's from being written at all.
            ScheduledPublishOutcome.clear(
                inHomeFolder: home, course: section.courseCode, section: section.sectionNumber
            )
            ScheduledPublishOutcome.recordStopped(
                ScheduledPublishOutcome.Stopped(
                    kind: .tooLateToRun,
                    destination: ScheduledPublishOutcome.nothingWasDeployedName,
                    when: now
                ),
                inHomeFolder: home,
                course: section.courseCode,
                section: section.sectionNumber
            )
            ScheduledPublishOutcome.noteOnTrail(
                inHomeFolder: home, course: section.courseCode, section: section.sectionNumber
            )
        }

        if let label = label(fromScriptPath: script) {
            bootOutAgent(label: label)
        }
        // Zero, not a failure: nothing went wrong. The job was asked to do
        // something that no longer made sense and declined, which is the
        // feature rather than a fault, and a non-zero exit here would land in
        // the section's log as an error nobody can act on.
        exit(0)
    }

    /// Which destination types this course publishes to, in deploy order.
    static func scheduledDestinationTypes(course: Course) -> [String] {
        var result: [String] = []
        for destination in course.configuration.allDeployDestinations {
            result.append(destination.type)
        }
        return result
    }

    /// Where a scheduled run leaves the folder problems it found, for the app
    /// to read the next time it opens.
    ///
    /// Beside the success sentinel and consumed the same way, because the
    /// shape is already proven here: a one-shot run writes a small file, the
    /// app reads it and deletes it.
    nonisolated static func findingsSentinelURL(
        courseCode: String,
        sectionNumber: Int,
        inHomeFolder home: URL? = nil
    ) -> URL {
        let label: String = agentLabel(courseCode: courseCode, sectionNumber: sectionNumber)
        return (home ?? homeForScheduledNotes)
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Plantoir")
            .appendingPathComponent("scheduled")
            .appendingPathComponent("\(label).findings")
    }

    /// Keeps whatever the run said about this course's folders, so it can be
    /// shown when somebody is next there to read it.
    ///
    /// **A scheduled deploy never refuses on a finding** — it publishes and
    /// reports afterwards. A slightly inaccurate curriculum map is a paper cut;
    /// a site update a teacher was counting on that silently did not happen is
    /// not. See `contracts/shared-rules.json` →
    /// `siteHealth.scheduledDeployPublishesAnyway`.
    ///
    /// The findings are read back out of the LOG rather than from a pipe.
    /// `runScheduled` deliberately does not capture the child's output —
    /// launchd points its stdout and stderr at that log and the process
    /// inherits them — and an unread pipe is exactly what wedged the Windows
    /// assistant's server, so this reads the file launchd already wrote.
    nonisolated static func recordFolderProblems(
        section: (courseDirectory: URL, courseCode: String, sectionNumber: Int)?,
        fromByteOffset offset: UInt64,
        inHomeFolder home: URL? = nil
    ) {
        guard let section else {
            return
        }
        let log: URL = logURL(
            courseCode: section.courseCode, sectionNumber: section.sectionNumber, inHomeFolder: home
        )
        guard let text = textOfLog(at: log, fromByteOffset: offset) else {
            return
        }
        var markerLines: [String] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line: String = String(rawLine).trimmingCharacters(in: .whitespaces)
            if SiteHealthFinding.isMarkerLine(line) {
                markerLines.append(line)
            }
        }
        let sentinel: URL = findingsSentinelURL(
            courseCode: section.courseCode, sectionNumber: section.sectionNumber, inHomeFolder: home
        )
        if markerLines.isEmpty {
            // Nothing wrong this time: clear anything an earlier run left, so
            // a problem that has since been put right stops being reported.
            try? FileManager.default.removeItem(at: sentinel)
            return
        }
        try? FileManager.default.createDirectory(
            at: sentinel.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? markerLines.joined(separator: "\n").write(to: sentinel, atomically: true, encoding: .utf8)
    }

    /// How big the log is right now.
    ///
    /// Taken BEFORE the run so that afterwards only THIS run's output is read.
    /// launchd opens `StandardOutPath` with O_APPEND and nothing rotates or
    /// truncates it, so the file still holds every previous night's output —
    /// reading the whole thing meant last week's findings were rewritten into
    /// the sentinel every night, and the "nothing wrong this time" branch
    /// became unreachable the moment a single problem had ever been logged. A
    /// teacher who fixed the folder would have gone on being told about it
    /// forever.
    nonisolated static func logSize(
        courseCode: String,
        sectionNumber: Int,
        inHomeFolder home: URL? = nil
    ) -> UInt64 {
        let log: URL = logURL(courseCode: courseCode, sectionNumber: sectionNumber, inHomeFolder: home)
        let attributes = try? FileManager.default.attributesOfItem(atPath: log.path)
        return (attributes?[.size] as? UInt64) ?? 0
    }

    /// The log from `offset` onward, or the whole file when it is SHORTER than
    /// the offset — which means somebody rotated or deleted it mid-run, and
    /// reading from a stale offset would return nothing at all.
    nonisolated static func textOfLog(at log: URL, fromByteOffset offset: UInt64) -> String? {
        guard let data = try? Data(contentsOf: log) else {
            return nil
        }
        if offset == 0 || UInt64(data.count) < offset {
            return String(data: data, encoding: .utf8)
        }
        return String(data: data.suffix(from: Int(offset)), encoding: .utf8)
    }

    /// What the last scheduled run found, if anything, consuming the record so
    /// it is reported once rather than every time the app opens.
    nonisolated static func takeFolderProblems(
        courseCode: String,
        sectionNumber: Int,
        inHomeFolder home: URL? = nil
    ) -> [SiteHealthFinding] {
        let sentinel: URL = findingsSentinelURL(
            courseCode: courseCode, sectionNumber: sectionNumber, inHomeFolder: home
        )
        guard let text = try? String(contentsOf: sentinel, encoding: .utf8) else {
            return []
        }
        try? FileManager.default.removeItem(at: sentinel)
        return SiteHealthFinding.findings(in: text)
    }

    /// Marks the section's pages as published, if the script said every
    /// destination worked. The sentinel is consumed either way, so a run
    /// that failed cannot be read as a success by the next one.
    nonisolated static func recordScheduledPublish(
        section: (courseDirectory: URL, courseCode: String, sectionNumber: Int)?,
        fingerprint: String?,
        inHomeFolder home: URL? = nil
    ) {
        guard let section, let fingerprint else {
            return
        }
        let sentinel: URL = successSentinelURL(
            courseCode: section.courseCode, sectionNumber: section.sectionNumber, inHomeFolder: home
        )
        guard let written = try? String(contentsOf: sentinel, encoding: .utf8) else {
            return
        }
        try? FileManager.default.removeItem(at: sentinel)
        var destinations: [String] = []
        for name in written.split(separator: " ") {
            destinations.append(String(name).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        SectionPublishState.recordPublish(
            courseDirectory: section.courseDirectory,
            sectionNumber: section.sectionNumber,
            fingerprint: fingerprint,
            destinations: destinations
        )
    }

    /// Takes the alarm off. Returns nil on success.
    ///
    /// **The working folder is REQUIRED, and that is the point of it.** A
    /// label is the course code and the section number and nothing else, so
    /// this names one file per code and section for the whole Mac — and a
    /// caller that did not think about which folder it meant would cancel
    /// another working folder's live deploy and report success. Every caller
    /// used to have to remember to ask first; one of them did not
    /// (`AssistToolRunner.turnOffAnyScheduledPublish`, the rollover path, until
    /// 2026-09-20), and a rule enforced by everybody remembering is a rule
    /// with a hole in it. Making the parameter mandatory means the unscoped
    /// form cannot be written by accident.
    ///
    /// **A job belonging to another folder is LEFT ALONE and reported as
    /// success**, deliberately. It is not a failure — there is nothing of this
    /// folder's to turn off, which is the same answer as "there was never one
    /// set", and that is already what this returns for a missing agent. Saying
    /// otherwise would put a problem in front of a teacher about a course they
    /// are not looking at. In practice no caller reaches it: each one asks
    /// `ScheduledDeployCleanup.agentsOwnedBy` or a folder-scoped `nextRun`
    /// first, and this is the backstop under those.
    @discardableResult
    static func cancelScheduledDeploy(
        courseCode: String,
        sectionNumber: Int,
        inWorkingFolder workingFolderURL: URL,
        runner: LaunchControlRunning = LaunchControl()
    ) -> String? {
        let destinationURL: URL = plistURL(courseCode: courseCode, sectionNumber: sectionNumber)
        if let agent = agent(readingPlistAt: destinationURL) {
            if physicalPath(agent.workingFolderPath) != physicalPath(workingFolderURL.path) {
                return nil
            }
        }
        runner.bootOut(label: agentLabel(courseCode: courseCode, sectionNumber: sectionNumber))
        // The script goes with the alarm. A cancelled deploy that left its
        // command behind would leave a runnable copy of itself on disk.
        try? FileManager.default.removeItem(
            at: scriptURL(courseCode: courseCode, sectionNumber: sectionNumber)
        )
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            do {
                try FileManager.default.removeItem(at: destinationURL)
            } catch {
                return "The scheduled deploy could not be removed: \(error.localizedDescription)"
            }
        }
        return nil
    }

    /// When this section is next set to deploy on its own, or nil when
    /// nothing is scheduled.
    ///
    /// Read back from the agent itself rather than from a note of our own.
    /// The teacher can delete the agent from `~/Library/LaunchAgents`
    /// without telling us, and a badge promising a deploy that will never
    /// happen is worse than no badge at all.
    ///
    /// **Pass the working folder wherever there is one.** A label is the
    /// course code and section and nothing else, so without it this answers
    /// about the one agent that code and section have Mac-wide — which, for a
    /// teacher holding last year's working folder and this year's, is a clock
    /// shown in the folder that does not own it and a Cancel item beside it.
    /// It stays optional because a few tests ask the question with no folder
    /// in hand.
    static func nextRun(
        courseCode: String,
        sectionNumber: Int,
        now: Date = Date(),
        inWorkingFolder workingFolderURL: URL? = nil
    ) -> Date? {
        let destinationURL: URL = plistURL(courseCode: courseCode, sectionNumber: sectionNumber)
        guard let data = try? Data(contentsOf: destinationURL) else {
            return nil
        }
        guard let decoded = try? PropertyListSerialization.propertyList(from: data, format: nil) else {
            return nil
        }
        guard let plist = decoded as? [String: Any] else {
            return nil
        }
        if let workingFolderURL {
            let named: String = plist["WorkingDirectory"] as? String ?? ""
            if physicalPath(named) != physicalPath(workingFolderURL.path) {
                return nil
            }
        }
        guard let environment = plist["EnvironmentVariables"] as? [String: String] else {
            return nil
        }
        guard let stamp = environment[scheduledForKey] else {
            return nil
        }
        guard let moment = ISO8601DateFormatter().date(from: stamp) else {
            return nil
        }
        // An agent whose moment has passed has either just fired and is
        // clearing itself away, or was left behind by a Mac that was off.
        // Either way it is not a promise worth showing.
        if moment <= now {
            return nil
        }
        return moment
    }

    /// When the one deploy this section has on this Mac is set for — from
    /// ANY working folder — or nil when there is none or its moment has gone
    /// by. The reading behind both `momentBeingReplaced` (which then leaves
    /// out the same minute, for what a teacher is TOLD) and the record of a
    /// replacement that failed (which must not: a same-minute job lost is
    /// still lost).
    ///
    /// Under the test suite this reads ONLY a folder a test chose. The card
    /// reads this whenever a scheduled deploy is proposed, and tests that put
    /// one up without moving the agents folder would otherwise read the real
    /// `~/Library/LaunchAgents` of whoever runs the suite — passing whatever
    /// that Mac has scheduled, which is the #240 fault arriving through a new
    /// door. A test that wants one sets `launchAgentsDirectoryOverride`, as
    /// every scheduling test already does. (Since #240
    /// `launchAgentsDirectoryURL()` itself answers an empty throwaway folder
    /// under the suite, so this is now the second of two guards; it stays
    /// because it also keeps a plist some other test left in that shared
    /// throwaway folder from being read as a deploy to replace.)
    static func momentAlreadySet(
        courseCode: String,
        sectionNumber: Int,
        now: Date = Date()
    ) -> Date? {
        if WorkspaceModel.isRunningTests && launchAgentsDirectoryOverride == nil {
            return nil
        }
        return nextRun(
            courseCode: courseCode,
            sectionNumber: sectionNumber,
            now: now,
            inWorkingFolder: nil
        )
    }

    /// When the deploy that scheduling this section for `when` would REPLACE
    /// is set for — or nil when there is none, or when it is set for that
    /// same minute and so replaces nothing a teacher would notice (issue #195).
    ///
    /// **Deliberately NOT scoped to a working folder**, unlike every other
    /// reader of `nextRun` that has a folder in hand. `scheduleDeploy` writes
    /// to `plistURL`, which is one file per course code and section for the
    /// whole Mac, so the job it overwrites may have been set from ANOTHER
    /// working folder — last year's, holding the same code. Asking with this
    /// folder would answer nil in exactly that case, and stay silent about
    /// the replacement nobody could see coming. A moment already past is nil
    /// here as it is in `nextRun`: a job that has fired, or was left by a Mac
    /// that was off, is not a promise being broken.
    static func momentBeingReplaced(
        courseCode: String,
        sectionNumber: Int,
        by when: Date,
        now: Date = Date(),
        calendar: Calendar = Calendar.current
    ) -> Date? {
        guard let existing = momentAlreadySet(
            courseCode: courseCode, sectionNumber: sectionNumber, now: now
        ) else {
            return nil
        }
        if calendar.isDate(existing, equalTo: when, toGranularity: .minute) {
            return nil
        }
        return existing
    }

    // MARK: - Which agents belong to this working folder

    /// One scheduled deploy as it stands on disk, read back from its own
    /// agent.
    nonisolated struct Agent: Equatable {

        // MARK: - Stored properties

        /// The agent's label, which is also the name of its plist and of its
        /// wrapper script.
        let label: String

        /// The course code the job names. Un-sanitised when the plist carries
        /// it (v1.2.0 and later); recovered from the LABEL, and so in
        /// `sanitizedCode` form, for anything older.
        let courseCode: String

        let sectionNumber: Int

        /// Which working folder the job belongs to.
        let workingFolderPath: String

        /// The moment it was set for, or nil when the plist does not say.
        let scheduledFor: Date?

        let plistURL: URL
    }

    /// Every scheduled deploy that belongs to ONE working folder.
    ///
    /// **Scoped by the plist's `WorkingDirectory`, and this is the half that
    /// is easy to leave out.** A label is the course code and the section
    /// number and nothing else, so `plistURL` names ONE file per code and
    /// section for the whole Mac. A teacher with last year's working folder
    /// and this year's, both holding ICS3U section 1, has one alarm between
    /// them — and asking "does this course have a scheduled deploy?" by
    /// looking for a file would answer yes in the folder that does not own it.
    /// Removing the course there would then cancel THIS year's deploy and
    /// report success.
    ///
    /// (That the two folders share one alarm at all is a separate fault, filed
    /// as its own issue: a folder-scoped label would orphan every plist a
    /// teacher already holds, which is its own migration. What is fixed here
    /// is that nothing acts on, or shows, a job belonging to a folder that is
    /// not open.)
    ///
    /// Nothing is asked of launchd and nothing outside `labelPrefix` is read —
    /// the prefix exists for exactly this reason.
    nonisolated static func agents(inWorkingFolder workingFolderURL: URL) -> [Agent] {
        let wanted: String = physicalPath(workingFolderURL.path)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: launchAgentsDirectoryURL(),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var found: [Agent] = []
        for entry in entries {
            let name: String = entry.lastPathComponent
            if !name.hasPrefix(labelPrefix) || !name.hasSuffix(".plist") {
                continue
            }
            guard let agent = agent(readingPlistAt: entry) else {
                continue
            }
            if physicalPath(agent.workingFolderPath) != wanted {
                continue
            }
            found.append(agent)
        }
        found.sort { first, second in
            if first.courseCode == second.courseCode {
                return first.sectionNumber < second.sectionNumber
            }
            return first.courseCode < second.courseCode
        }
        return found
    }

    /// One agent, read out of its own plist — or nil when the file is not one
    /// of ours, or says too little to act on.
    nonisolated static func agent(readingPlistAt plistURL: URL) -> Agent? {
        guard let data = try? Data(contentsOf: plistURL) else {
            return nil
        }
        guard let decoded = try? PropertyListSerialization.propertyList(from: data, format: nil) else {
            return nil
        }
        guard let plist = decoded as? [String: Any] else {
            return nil
        }
        guard let label = plist["Label"] as? String, label.hasPrefix(labelPrefix) else {
            return nil
        }
        guard let workingFolderPath = plist["WorkingDirectory"] as? String,
              !workingFolderPath.isEmpty else {
            // A job that does not say which folder it belongs to cannot be
            // scoped to one, and acting on it would be acting blind.
            return nil
        }

        var courseCode: String?
        var sectionNumber: Int?
        // The plist's OWN copy first: `--scheduled-section <folder> <CODE> <N>`
        // carries the course code as the teacher spells it.
        if let arguments = plist["ProgramArguments"] as? [String] {
            if let index = arguments.firstIndex(of: sectionFlag), index + 3 < arguments.count {
                courseCode = arguments[index + 2]
                sectionNumber = Int(arguments[index + 3])
            }
        }
        // Anything written before v1.2.0 has three `ProgramArguments` and no
        // section flag, so the label is the only route — and the code comes
        // back in `sanitizedCode` form, which is why every comparison against
        // a course's own code sanitises both sides.
        if courseCode == nil || sectionNumber == nil {
            let recovered = codeAndSection(fromLabel: label)
            courseCode = recovered?.courseCode
            sectionNumber = recovered?.sectionNumber
        }
        guard let courseCode, let sectionNumber else {
            return nil
        }

        var scheduledFor: Date?
        if let environment = plist["EnvironmentVariables"] as? [String: String],
           let stamp = environment[scheduledForKey] {
            scheduledFor = ISO8601DateFormatter().date(from: stamp)
        }

        return Agent(
            label: label,
            courseCode: courseCode,
            sectionNumber: sectionNumber,
            workingFolderPath: workingFolderPath,
            scheduledFor: scheduledFor,
            plistURL: plistURL
        )
    }

    /// The course code and section a LABEL carries, for a plist that does not
    /// carry them itself.
    nonisolated static func codeAndSection(fromLabel label: String) -> (courseCode: String, sectionNumber: Int)? {
        guard label.hasPrefix(labelPrefix + ".") else {
            return nil
        }
        let remainder: String = String(label.dropFirst(labelPrefix.count + 1))
        guard let separator = remainder.range(of: ".section", options: .backwards) else {
            return nil
        }
        let code: String = String(remainder[remainder.startIndex..<separator.lowerBound])
        guard let sectionNumber = Int(remainder[separator.upperBound...]), !code.isEmpty else {
            return nil
        }
        return (courseCode: code, sectionNumber: sectionNumber)
    }

    /// A path with every symlink resolved, POSIX-style.
    ///
    /// `realpath` rather than Foundation's `resolvingSymlinksInPath()`, which
    /// strips the `/private` prefix from `/var` and `/tmp` paths where the
    /// POSIX call keeps it — the same trap the container naming met. Two
    /// spellings of one folder comparing as DIFFERENT would quietly scope
    /// every job out, and nothing would be cancelled or shown at all.
    ///
    /// A path that does not exist comes back as it went in, so a working
    /// folder on an unmounted volume compares by its plain text rather than
    /// matching nothing.
    nonisolated static func physicalPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else {
            return path
        }
        let physical: String = String(cString: resolved)
        free(resolved)
        return physical
    }

    // MARK: - Wording

    /// "Tuesday 12 August, 6:30 AM" — the whole moment.
    static func dayAndTimeText(_ date: Date, locale: Locale = Locale.current) -> String {
        return "\(dayText(date, locale: locale)), \(timeText(date, locale: locale))"
    }

    /// "Tuesday 12 August".
    static func dayText(_ date: Date, locale: Locale = Locale.current) -> String {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter.string(from: date)
    }

    /// "6:30 AM", in whatever way this Mac writes times.
    static func timeText(_ date: Date, locale: Locale = Locale.current) -> String {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = locale
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

/// A deploy that has not been scheduled yet, described in full.
///
/// The plan half of the plan/apply pair: making one changes nothing at all,
/// which is what lets the app — or the assistant — read it out and wait for
/// a yes before anything is set.
struct ScheduledDeployPlan {

    // MARK: - Stored properties

    let courseCode: String
    let sectionNumber: Int
    let when: Date

    /// Where the site would go: "Netlify", "Cloudflare Pages", or a folder.
    let destination: String

    /// Class pages students cannot see yet, by name.
    let unpublishedClasses: [String]

    /// Why this cannot be scheduled, or nil when it can be.
    let problem: String?

    /// When the deploy this would replace is set for, or nil when it replaces
    /// nothing (issue #195). Read Mac-wide — see
    /// `ScheduledDeploy.momentBeingReplaced`.
    let replacing: Date?

    let locale: Locale

    // MARK: - Computed properties

    /// True when scheduling this would work.
    var isSchedulable: Bool {
        return problem == nil
    }

    /// The whole plan, in words meant to be read aloud.
    var description: String {
        if let problem {
            return problem
        }

        var lines: [String] = []
        lines.append("Deploy \(courseCode) Section \(sectionNumber) to \(destination) at \(ScheduledDeploy.dayAndTimeText(when, locale: locale)).")
        if let replacing {
            lines.append(AssistWording.scheduleReplaces(
                moment: ScheduledDeploy.dayAndTimeText(replacing, locale: locale)
            ))
        }
        lines.append("")
        lines.append("For this to happen, at that moment this Mac must be:")
        lines.append("  • switched on, and awake — not asleep or shut down")
        lines.append("  • plugged in, if it is a laptop")
        lines.append("  • with the lid open, if closing it puts it to sleep")
        lines.append("")
        lines.append("Plantoir does not wake this Mac up. If it is asleep or switched off at that time, macOS runs the deploy at the next wake instead — which could be well after the class it was meant for.")
        lines.append("")
        // The agent rebuilds only when something has changed and then
        // deploys, which is what the Deploy button does. So a page written
        // after the alarm was set IS in what goes out, and the teacher is
        // told that plainly — otherwise they would keep previewing out of
        // caution the night before.
        lines.append("Anything you write between now and then goes out with it: if the section has changed since it was last built, it is rebuilt first. If that build fails, nothing is deployed and the site students see stays exactly as it is.")

        if !unpublishedClasses.isEmpty {
            lines.append("")
            let count: Int = unpublishedClasses.count
            let isSingle: Bool = count == 1
            lines.append("One thing first — \(count) class\(isSingle ? " is" : "es are") not published yet:")
            var shown: Int = 0
            for title in unpublishedClasses {
                if shown >= 8 {
                    break
                }
                lines.append("  \(title)")
                shown += 1
            }
            if count > 8 {
                lines.append("  …and \(count - 8) more.")
            }
            lines.append("Deploying now would put the site up without \(isSingle ? "it" : "them"). Publish first, look the preview over, then schedule this.")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Initializer

    init(
        courseCode: String,
        sectionNumber: Int,
        when: Date,
        destination: String,
        unpublishedClasses: [String],
        problem: String?,
        replacing: Date? = nil,
        locale: Locale = Locale.current
    ) {
        self.courseCode = courseCode
        self.sectionNumber = sectionNumber
        self.when = when
        self.destination = destination
        self.unpublishedClasses = unpublishedClasses
        self.problem = problem
        self.replacing = replacing
        self.locale = locale
    }
}

/// The two `launchctl` calls a scheduled deploy needs.
///
/// Behind a protocol so a test can watch what would be asked of launchd
/// without asking it — a test that really bootstrapped an agent would leave
/// one in the person running the suite.
protocol LaunchControlRunning {

    // MARK: - Functions

    /// Loads an agent into the logged-in user's own launchd domain.
    /// Returns nil on success, or what launchctl said.
    func bootstrap(plistURL: URL) -> String?

    /// Removes an agent from that domain. Silent about an agent that was
    /// not there — cancelling something already gone is not a failure.
    func bootOut(label: String)
}

/// The real `launchctl`.
///
/// `bootstrap` and `bootout` rather than the deprecated `load`/`unload`:
/// the modern pair names the domain explicitly (`gui/<uid>`, the logged-in
/// user's session), reports real errors, and is what launchd's own
/// documentation has told people to use for years.
struct LaunchControl: LaunchControlRunning {

    // MARK: - Computed properties

    /// The logged-in user's GUI domain, e.g. "gui/501".
    var domainTarget: String {
        return "gui/\(getuid())"
    }

    // MARK: - Functions

    func bootstrap(plistURL: URL) -> String? {
        let result = LaunchControl.run(arguments: ["bootstrap", domainTarget, plistURL.path])
        if result.exitCode == 0 {
            return nil
        }
        let message: String = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "launchctl exited with code \(result.exitCode)." : message
    }

    func bootOut(label: String) {
        _ = LaunchControl.run(arguments: ["bootout", "\(domainTarget)/\(label)"])
    }

    /// What this says when it refuses to run, because a test is driving.
    static let refusedUnderATestRun: String =
        "launchctl was not run: this app is writing its agents somewhere other than "
        + "~/Library/LaunchAgents, which only a test does. Pass FakeLaunchControl."

    /// Runs launchctl and collects what it said.
    ///
    /// **It refuses outright while `launchAgentsDirectoryOverride` is set**,
    /// which is set by tests and by nothing else. Every test that can reach an
    /// agent is supposed to pass `FakeLaunchControl`, and that was a rule for
    /// whoever writes the test — exactly the kind that holds until somebody
    /// adds the eleventh one. The cost of forgetting is not a red test: the
    /// suite builds an ICS3U fixture, and "a course a teacher plausibly has"
    /// means the forgotten default would boot out and delete Russell's own
    /// ICS3U schedule on the machine running it. So the guard is structural
    /// rather than written down.
    ///
    /// **And it refuses under the suite even with NO override**, since issue
    /// #240: `ScheduledDeploy.launchAgentsDirectoryURL()` now answers a
    /// throwaway folder there, so a test that forgot the override would
    /// otherwise write its plist somewhere harmless and then hand that plist
    /// to the REAL launchd — the redirect would have un-guarded the one call
    /// it most needed to keep guarded.
    static func run(arguments: [String]) -> (exitCode: Int32, output: String) {
        if ScheduledDeploy.launchAgentsDirectoryOverride != nil || BuildOutputLocation.isRunningTests {
            return (exitCode: -1, output: refusedUnderATestRun)
        }
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe: Pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (exitCode: -1, output: error.localizedDescription)
        }
        let data: Data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (exitCode: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}

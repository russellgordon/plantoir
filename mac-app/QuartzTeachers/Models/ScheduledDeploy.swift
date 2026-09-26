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

    /// The environment key carrying where the deploy was SET to go, as a JSON
    /// array of the destinations' descriptions (GitHub #323).
    ///
    /// A note of what the teacher was told, and nothing more: the run reads
    /// WHERE to deploy from the course's own settings at the moment it fires,
    /// and a test pins that this value never decides it. It exists because
    /// the wrapper is written afresh at the run, so the wrapper can no longer
    /// be where "what was promised" is kept.
    nonisolated static let scheduledToKey: String = "PLANTOIR_SCHEDULED_TO"

    // MARK: - Functions

    /// This section's agent label, in the working folder it is set from:
    /// `…deploy.<CODE>.section<N>.<folder id>` (GitHub #237).
    ///
    /// The course code AND the section number, so two sections of one course
    /// can never collide, nor two courses — and, since #237, the working
    /// folder's id, so the same course in two working folders (last year's
    /// and this year's, or a restored copy) is two alarms rather than one.
    /// Until then the label ended at the section, so scheduling ICS3U section
    /// 1 in one folder booted out and overwrote the other folder's job.
    ///
    /// **The id is `BuildOutputLocation.folderIdentifier`** — the eight hex
    /// characters the folder's container and builds folder are already named
    /// by, from `FolderIdentity.canonicalPath` (#189). ONE derivation of
    /// "which folder" across the product, rather than a second one here that
    /// could disagree with it; two spellings of one folder give one label.
    ///
    /// **The id is a way of keeping two folders' files apart, not how a job
    /// is FOUND.** Every reader finds a folder's jobs by the plist's
    /// `WorkingDirectory` (`agents(inWorkingFolder:courseCode:sectionNumber:)`),
    /// never by rebuilding this label — so a job set before #237, or one
    /// whose id a later change to `canonicalPath` would compute differently,
    /// is still shown, cancelled and replaced.
    ///
    /// The working folder is REQUIRED, the argument #236 made for the cancel:
    /// an unscoped form of this must not compile.
    nonisolated static func agentLabel(
        courseCode: String,
        sectionNumber: Int,
        workingFolder workingFolderURL: URL
    ) -> String {
        let folderID: String = BuildOutputLocation.folderIdentifier(
            forWorkingFolder: workingFolderURL.path
        )
        return legacyAgentLabel(courseCode: courseCode, sectionNumber: sectionNumber) + "." + folderID
    }

    /// The label every release before #237 wrote: the course code and the
    /// section and nothing else, one per section for the whole Mac.
    ///
    /// **Never written any more; kept because such jobs are still on
    /// teachers' Macs.** A deploy set before the update is left exactly as it
    /// is on disk — not re-registered, not renamed — and it keeps working:
    /// it is found by the folder scan like any other, shown, cancelled,
    /// swept when too late, run, and replaced by the next schedule in its
    /// own folder. One-shot jobs delete their own plist, so the old spelling
    /// drains away by itself. See documentation/07-deployment.md, "One alarm
    /// per working folder (#237)", for the three migrations rejected.
    nonisolated static func legacyAgentLabel(courseCode: String, sectionNumber: Int) -> String {
        let code: String = sanitizedCode(courseCode)
        return "\(labelPrefix).\(code).section\(sectionNumber)"
    }

    /// The working folder's id a label ends with, or nil for a label written
    /// before #237 (which ends `section<N>`).
    ///
    /// Exactly eight lowercase hex characters after the last dot. A legacy
    /// label's last component always begins `section`, and course codes are
    /// upper-cased by `sanitizedCode`, so the two spellings cannot be taken
    /// for each other.
    nonisolated static func folderID(fromLabel label: String) -> String? {
        guard let lastDot = label.range(of: ".", options: .backwards) else {
            return nil
        }
        let tail: String = String(label[lastDot.upperBound...])
        if tail.count != 8 {
            return nil
        }
        for character in tail {
            let isDigit: Bool = character >= "0" && character <= "9"
            let isLowerHex: Bool = character >= "a" && character <= "f"
            if !isDigit && !isLowerHex {
                return nil
            }
        }
        return tail
    }

    /// The id a scheduled RUN keeps its notes under: the one baked into its
    /// own label, or — for a job set before #237, whose label carries none —
    /// the id of the working folder it names.
    ///
    /// The second is computed by the same `folderIdentifier` the app's
    /// readers use on the open folder, so a record a pre-#237 job leaves is
    /// filed where that folder's badge looks for it and nowhere else.
    nonisolated static func folderIDForRun(
        label: String?,
        section: (courseDirectory: URL, courseCode: String, sectionNumber: Int)
    ) -> String {
        if let label, let baked = folderID(fromLabel: label) {
            return baked
        }
        let workingFolder: URL = workingFolderURL(forCourseDirectory: section.courseDirectory)
        return BuildOutputLocation.folderIdentifier(forWorkingFolder: workingFolder.path)
    }

    /// The working folder a course directory sits in: `<folder>/courses/<CODE>`.
    /// One step, used by the id above and by the notification a run posts,
    /// which carries the folder's path so a click can open it (#306).
    nonisolated static func workingFolderURL(forCourseDirectory courseDirectory: URL) -> URL {
        return courseDirectory
            .deletingLastPathComponent()   // courses
            .deletingLastPathComponent()   // the working folder
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
    /// sentinels, the wrapper scripts, the agent's log, and the stopped-run
    /// records the sidebar badge, the section's notice (and its Dismiss, which
    /// DELETES one) and `ScheduledPublishWatcher` read — are resolved against
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
    /// CALL site, so it could not be redirected from inside the function. A
    /// caller that passes a home explicitly gets exactly that home, test or
    /// not.
    ///
    /// **Since issue #264 the real answer comes from `RealHome.forFiles`**,
    /// the one place allowed to ask the system, and so does every default
    /// that used to be `= homeDirectoryForCurrentUser` — `oneShotCommand`'s
    /// included. Under the unit suite `forFiles` already answers the same
    /// throwaway home as this, so the check below matters only in the app a
    /// UI test drives, which has no XCTest in it but was moved here by #240
    /// and stays moved.
    nonisolated static var homeForScheduledNotes: URL {
        if BuildOutputLocation.isRunningTests {
            return RealHome.homeWhileTesting
        }
        return RealHome.forFiles
    }

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
    ///
    /// Named by its LABEL, as every per-job file is: the label is the one
    /// name a job carries on disk, and a job set before #237 has the old one.
    nonisolated static func scriptURL(label: String) -> URL {
        return scheduledScriptsDirectoryURL().appendingPathComponent("\(label).sh")
    }

    /// The same, for the job this working folder would set now.
    nonisolated static func scriptURL(
        courseCode: String,
        sectionNumber: Int,
        inWorkingFolder workingFolderURL: URL
    ) -> URL {
        return scriptURL(label: agentLabel(
            courseCode: courseCode, sectionNumber: sectionNumber, workingFolder: workingFolderURL
        ))
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
    ///
    /// Keyed by the job's LABEL: the wrapper has this path baked into it, so
    /// the run that reads it back must take the label from the script it was
    /// started with (`label(fromScriptPath:)`) and never rebuild one — a job
    /// set before #237 writes the old name.
    nonisolated static func successSentinelURL(
        label: String,
        inHomeFolder home: URL? = nil
    ) -> URL {
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
    ///
    /// By the LABEL, taken from the wrapper script's own name, and never
    /// rebuilt from a course and section. A plist written before v1.2.0
    /// carries no course code and no section number — three
    /// `ProgramArguments`, no `--scheduled-section` — and one written before
    /// #237 has the label without the folder id, so a rebuilt one would boot
    /// out a job that does not exist and leave the real one loaded. Every
    /// plist any release ever wrote is named after its label.
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
    nonisolated static func plistURL(label: String) -> URL {
        return launchAgentsDirectoryURL().appendingPathComponent("\(label).plist")
    }

    /// The same, for the job this working folder would set now. A job
    /// already on disk is found by `agents(inWorkingFolder:…)` and carries
    /// its own `plistURL`; rebuilding a name here would miss one set before
    /// #237.
    nonisolated static func plistURL(
        courseCode: String,
        sectionNumber: Int,
        inWorkingFolder workingFolderURL: URL
    ) -> URL {
        return plistURL(label: agentLabel(
            courseCode: courseCode, sectionNumber: sectionNumber, workingFolder: workingFolderURL
        ))
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
    ///
    /// Keyed by the LABEL, because launchd writes to the path baked into the
    /// plist's `StandardOutPath` — the old name, for a job set before #237.
    nonisolated static func logURL(
        label: String,
        inHomeFolder home: URL? = nil
    ) -> URL {
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
        return destinationRefusal(
            course: course, sectionNumber: sectionNumber, cloudflareAccountID: cloudflareAccountID
        )?.sentence(course: course, section: sectionNumber)
    }

    /// Why a deploy of this section cannot go ahead the way the course is set
    /// NOW, or nil when it can — everything `problem()` refuses except a time
    /// already passed (GitHub #323).
    ///
    /// Asked at three moments: when the deploy is SET (`problem()`), when it
    /// RUNS (`readAtTheRun`, because the destination is read then) and after
    /// a Save in Course Settings (`SettingsSaveNotice`). One function, so the
    /// three cannot disagree about what would ask a question at half six. In
    /// `problem()`'s order, which `scheduledDeployRefusals.cases` pins: the
    /// first match is what the teacher is told.
    static func destinationRefusal(
        course: Course,
        sectionNumber: Int,
        cloudflareAccountID: String
    ) -> ScheduledDeployRefusal? {
        if course.isKeptForReference {
            return .keptForReference
        }
        let configuration: CourseConfiguration = course.configuration

        // A folder deploy with no usable folder would fail at the scheduled
        // moment, so it is refused now, with the same reasons the settings
        // screen gives.
        if configuration.deployTarget == "local_folder" {
            if let folderProblem = CourseConfiguration.deployFolderProblem(forPath: configuration.deployFolderPath) {
                return .deployFolderNeedsAttention(problem: folderProblem)
            }
        }

        // Cloudflare needs an Account ID that only the app has. Unlike the
        // Windows app — where the scheduled task cannot be handed one —
        // the wrapper carries `--account`, so the question is asked HERE and
        // answered once rather than making Cloudflare unschedulable.
        if configuration.deploysToCloudflare {
            if let accountProblem = CourseConfiguration.cloudflareAccountProblem(forID: cloudflareAccountID) {
                return .cloudflareAccountMissing(problem: accountProblem)
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
                    return .additionalDeployFolderNeedsAttention(problem: folderProblem)
                }
            }
            if target.type == "cloudflare_pages" {
                if let accountProblem = CourseConfiguration.cloudflareAccountProblem(forID: cloudflareAccountID) {
                    return .additionalCloudflareAccountMissing(problem: accountProblem)
                }
            }
        }

        if !DeployCommand.hasDeployedBefore(section: sectionNumber, in: course) {
            // Names the destination (#322): the refusal only fires for a
            // Netlify or Cloudflare primary — a folder keeps no marker and
            // `hasDeployedBefore` calls it always ready.
            return .neverDeployed(destination: DeployCommand.destinationDescription(for: configuration))
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
                return .additionalDestinationNeverDeployed(destination: destinationName)
            }
        }

        return nil
    }

    /// Describes what scheduling would do, changing nothing.
    ///
    /// The words are meant to be read aloud, so they say what has to be
    /// true of the Mac and what happens when it isn't.
    ///
    /// The working folder is the one the deploy would be set from: what it
    /// would replace is read there and nowhere else (#237).
    static func plan(
        course: Course,
        sectionNumber: Int,
        when: Date,
        now: Date,
        cloudflareAccountID: String,
        inWorkingFolder workingFolderURL: URL,
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
                courseCode: course.code, sectionNumber: sectionNumber, by: when,
                inWorkingFolder: workingFolderURL, now: now
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
        scheduledTo: [String] = [],
        calendar: Calendar = Calendar.current,
        homeFolder: URL = RealHome.forFiles
    ) -> [String: Any] {
        let label: String = agentLabel(
            courseCode: courseCode, sectionNumber: sectionNumber, workingFolder: workspaceURL
        )
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
        // Where the teacher was told it would go (#323) — a NOTE, never read
        // to decide where to deploy: the run reads the course's settings for
        // that. Kept so the trail can say "set to deploy to Netlify; the
        // course deploys to … now" when the two differ. Absent for a job set
        // before #323, and then nothing is compared.
        if !scheduledTo.isEmpty,
           let encoded = try? JSONSerialization.data(withJSONObject: scheduledTo),
           let text = String(data: encoded, encoding: .utf8) {
            environment[scheduledToKey] = text
        }

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
            scriptURL(label: label).path,
            sectionFlag,
            workspaceURL.path,
            courseCode,
            String(sectionNumber),
        ]
        plist["StartCalendarInterval"] = schedule
        plist["WorkingDirectory"] = workspaceURL.path
        plist["EnvironmentVariables"] = environment
        plist["StandardOutPath"] = logURL(label: label).path
        plist["StandardErrorPath"] = logURL(label: label).path
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
        // Takeable so a test can drive the GENERATED SHELL for real without
        // writing into the teacher's own Application Support. The default is
        // RealHome.forFiles (#264): the real home in the app, the suite's
        // throwaway one under XCTest — so a test that EXECUTES a script built
        // with the default writes its records there, not into real ones.
        homeFolder: URL = RealHome.forFiles
    ) -> String {
        let label: String = agentLabel(
            courseCode: courseCode, sectionNumber: sectionNumber, workingFolder: workspaceURL
        )
        // The folder's id, baked in once, so every record this wrapper writes
        // is the one THIS folder's badge reads (#237). Taken from the label
        // rather than computed a second time, so the two cannot differ.
        return oneShotCommand(
            label: label,
            folderID: folderID(fromLabel: label) ?? "",
            courseCode: courseCode,
            sectionNumber: sectionNumber,
            workspaceURL: workspaceURL,
            deployArgumentsList: deployArgumentsList,
            destinationTypes: destinationTypes,
            destinationDescriptions: destinationDescriptions,
            homeFolder: homeFolder
        )
    }

    /// The wrapper for a job whose NAME is given rather than worked out —
    /// what the run uses when it writes its wrapper afresh (GitHub #323).
    ///
    /// **The label and the folder id are parameters, and that is the #237
    /// trap.** A job set before #237 carries the old label, with no folder id
    /// in it: its plist, log and success note are under that name, so the
    /// wrapper written at its run must use THAT name, not the one `agentLabel`
    /// would compute today. And its record must be filed under the id of the
    /// folder the job names (`folderIDForRun`), not under
    /// `folderID(fromLabel:) ?? ""`, which would make a third spelling
    /// (`ICS3U-section1..txt`) that no badge reads.
    static func oneShotCommand(
        label: String,
        folderID thisFolderID: String,
        courseCode: String,
        sectionNumber: Int,
        workspaceURL: URL,
        deployArgumentsList: [[String]],
        destinationTypes: [String],
        destinationDescriptions: [String],
        homeFolder: URL = RealHome.forFiles
    ) -> String {
        let plistPath: String = plistURL(label: label).path
        let scriptPath: String = workspaceURL.appendingPathComponent(DeployCommand.scriptName).path
        let logDirectory: String = logURL(
            label: label, inHomeFolder: homeFolder
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
        // Its preview check reads the same tree as the Swift's
        // (`contracts/app-rules.json` → `buildFreshness.previewBuild`), and
        // `ScheduledPublishOutcomeTests` runs it against every case there.
        let previewPath: String = workspaceURL.appendingPathComponent("preview.sh").path
        let builtIndexPath: String = workspaceURL
            .appendingPathComponent("courses")
            .appendingPathComponent(courseCode)
            .appendingPathComponent(".merged_output")
            .appendingPathComponent("section\(sectionNumber)")
            .appendingPathComponent("public")
            .appendingPathComponent("index.html")
            .path
        // The whole built site, for the preview check (issue #136).
        let builtPublicPath: String = workspaceURL
            .appendingPathComponent("courses")
            .appendingPathComponent(courseCode)
            .appendingPathComponent(".merged_output")
            .appendingPathComponent("section\(sectionNumber)")
            .appendingPathComponent("public")
            .path
        // Where the build notes when it STARTED (issue #265) — the time the
        // course's files are compared with, so a Save made while an earlier
        // publish was building still counts as unpublished. Beside `public/`.
        let buildStartedPath: String = workspaceURL
            .appendingPathComponent("courses")
            .appendingPathComponent(courseCode)
            .appendingPathComponent(".merged_output")
            .appendingPathComponent("section\(sectionNumber)")
            .appendingPathComponent(BuildFreshness.buildStartedMarkerName)
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
        // What the course is compared with: the START of the build that made
        // the site, when the build noted it and it is not newer than the page
        // — `BuildFreshness.referenceDate` in shell. The page's own time
        // otherwise, as before the start was noted. The page's time alone
        // missed a Save made while a publish was building: that Save is
        // older than the page the build writes at its end.
        lines.append("FRESH_SINCE=\(shellQuoted(builtIndexPath))")
        lines.append("if [ -f \(shellQuoted(buildStartedPath)) ] && [ -f \(shellQuoted(builtIndexPath)) ]"
            + " && ! [ \(shellQuoted(buildStartedPath)) -nt \(shellQuoted(builtIndexPath)) ]; then")
        lines.append("  FRESH_SINCE=\(shellQuoted(buildStartedPath))")
        lines.append("fi")
        lines.append("if [ -f \(shellQuoted(builtIndexPath)) ]; then")
        // A PREVIEW's build is never deploy-fresh. Serve mode bakes a
        // live-reload client pointed at ws://localhost into every page, and
        // deploying that makes a visitor's browser knock on their own
        // machine. Rebuilding is the only way to be rid of it, however
        // recent the build looks.
        //
        // EVERY page, not the front page alone (issue #136) — the same tree
        // `BuildFreshness.builtForPreview` reads and deploy.sh greps, or a
        // clean front page in front of a preview's pages skips this build and
        // deploy.sh rebuilds it under the DESTINATION's leg below. The three
        // parts of the line are each the Swift's:
        //   `! [ -r index ]` — a front page that cannot be read is rebuilt,
        //     which grep alone cannot say (its exit 2 reads as "no" in an if);
        //   `-s` — any other page that cannot be read is passed over quietly:
        //     measured, BSD grep exits 0 on a match elsewhere and 2 otherwise;
        //   `LC_ALL=C` — a byte match. Under a UTF-8 locale macOS's grep does
        //     not find the signature on a line that also holds a byte that is
        //     not valid UTF-8 (measured, grep 2.6.0-FreeBSD), and the Swift
        //     compares bytes.
        lines.append("  if ! [ -r \(shellQuoted(builtIndexPath)) ] || LC_ALL=C /usr/bin/grep -rqs"
            + " --include='*.html' \(shellQuoted(BuildFreshness.liveReloadSignature))"
            + " \(shellQuoted(builtPublicPath)); then")
        lines.append("    NEEDS_BUILD=1")
        lines.append("  elif [ -z \"$(/usr/bin/find \(shellQuoted(courseDirectoryPath))"
            + " -type f -newer \"$FRESH_SINCE\" -not -path '*/.*' -print -quit)\" ]; then")
        // Nothing under the course is newer than the start of the build that
        // made the page (or the page, for a site built before that was noted), so the site
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
        // Per working folder since #237. Once two folders can each hold ICS3U
        // section 1, both wrappers can run the same morning, and the line
        // below that clears LAST time's record would otherwise erase the
        // other folder's failure — whichever finished last wearing the badge
        // in both sidebars.
        let stoppedRecord: String = ScheduledPublishOutcome.recordURL(
            inHomeFolder: homeFolder,
            course: courseCode,
            section: sectionNumber,
            folderID: thisFolderID
        ).path
        // Every record is assembled here and MOVED into place, so the app's
        // watch on the record folder sees one event carrying a whole file. See
        // `recordCompletionLines` and `ScheduledPublishOutcome.partialRecordURL`
        // — including why this sits beside the record folder rather than in it.
        let stoppedPartialRecord: String = ScheduledPublishOutcome.partialRecordURL(
            inHomeFolder: homeFolder,
            course: courseCode,
            section: sectionNumber,
            folderID: thisFolderID
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
        // Any OTHER code from the build is its own kind too (#137): the
        // pages could not be built, nothing was contacted, and the sentence
        // names no destination and sends the teacher to Preview. `else`, not
        // `-eq 1` — a launcher that could not be run at all, or was stopped
        // by a signal, exits with another code, and
        // `scheduledPublishStopped.whichKind` carries a case for exactly
        // that. Until #137 this wrote `didNotFinish`, whose sentence put
        // buildDestinationName where a destination goes and said Publish.
        lines.append("      /bin/echo \(shellQuoted(ScheduledPublishOutcome.Kind.buildDidNotFinish.rawValue))"
            + " > \(shellQuoted(stoppedPartialRecord))")
        lines.append("    fi")
        // Written for BOTH build branches and shown by NEITHER: it is written
        // anyway so every record has one shape for the reader — see
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
            label: label, inHomeFolder: homeFolder
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
        // ONE path through deploy.sh could escape that, and no longer can
        // from here (GitHub issue #136). Publishing to a FOLDER — and only to
        // a folder — reruns preview.sh --build-only itself when any page under
        // the section's `public/` carries the live-reload client, and passes
        // its exit 3 straight through: a BUILD question, which from here would
        // read as though the folder had asked it. (Netlify and Cloudflare go
        // through deploy.py, whose rebuild runs build_site.py directly, asks
        // nothing and fails with 1, so they land in `didNotFinish` honestly.)
        // It needs NEEDS_BUILD=0 above, and the check above now reads the same
        // tree deploy.sh greps, so whenever deploy.sh would rebuild, this
        // script has already built — and a build question is `buildNeeded-
        // AnAnswer`, from the build leg. The rerun in deploy.sh stays: it is
        // what protects `./preview.sh` then `./deploy.sh --to-folder` typed at
        // a command line. Rejected: giving that rerun its own exit code, a
        // launcher contract change Windows shares for a fault that was this
        // check being narrower than the launcher's.
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

    /// What a scheduled run hands `deploy.sh`, one entry per destination, in
    /// `allDeployDestinations`' order: the primary first, then each
    /// additional one.
    struct DeployPlan: Equatable {

        // MARK: - Stored properties

        let argumentsList: [[String]]
        let types: [String]
        let descriptions: [String]
    }

    /// The deploy lines a scheduled run makes for this course AS IT IS SET —
    /// at scheduling, and again at the run (#323). ONE function, so the
    /// wrapper written when the deploy is set and the one written when it
    /// fires cannot drift apart (the byte-identical test pins it).
    static func deployPlan(course: Course, sectionNumber: Int, cloudflareAccountID: String) -> DeployPlan {
        var argumentsList: [[String]] = []
        var types: [String] = []
        var descriptions: [String] = []
        for destination in course.configuration.allDeployDestinations {
            types.append(destination.type)
            descriptions.append(DeployCommand.destinationDescription(for: destination))
            argumentsList.append(DeployCommand.arguments(
                courseCode: course.code,
                sectionNumber: sectionNumber,
                destination: destination,
                cloudflareAccountID: cloudflareAccountID,
                // Nobody is at the Mac at the scheduled moment, so the
                // launcher must refuse a question rather than wait for an
                // answer or pick one.
                unattended: true
            ))
        }
        return DeployPlan(argumentsList: argumentsList, types: types, descriptions: descriptions)
    }

    // MARK: - Applying

    /// Sets the alarm. Returns nil on success, or what went wrong in words
    /// the teacher can act on.
    ///
    /// Scheduling the same section twice IN ONE WORKING FOLDER replaces rather
    /// than stacks: the label is fixed per section and folder, and the
    /// previous agent is booted out before the new one is written. The same
    /// section in another working folder is another alarm, and is left alone
    /// (#237).
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

        // Written now so the job on disk is runnable on its own (an older
        // copy of the app, a downgrade) — and written AGAIN, from the settings
        // as they are then, when it runs (#323). The same function builds
        // both, so they cannot drift.
        let deploying: DeployPlan = deployPlan(
            course: course, sectionNumber: sectionNumber, cloudflareAccountID: cloudflareAccountID
        )
        let plist: [String: Any] = propertyList(
            courseCode: course.code,
            sectionNumber: sectionNumber,
            when: when,
            workspaceURL: workspaceURL,
            scheduledTo: deploying.descriptions
        )
        let label: String = agentLabel(
            courseCode: course.code, sectionNumber: sectionNumber, workingFolder: workspaceURL
        )
        let destinationURL: URL = plistURL(label: label)

        // What is about to be replaced, read BEFORE it goes (issue #195): once
        // the old agent is booted out and its plist overwritten, nothing
        // anywhere remembers it was ever set. Read here, in the one function
        // the sheet, the assistant and an outside assistant all reach, so the
        // trail line cannot be missing from one of them. THIS folder's only
        // since #237 — another folder's deploy of the same section is not
        // touched by what follows, so it is not being replaced.
        let replacing: Date? = momentBeingReplaced(
            courseCode: course.code, sectionNumber: sectionNumber, by: when,
            inWorkingFolder: workspaceURL
        )
        // What is on this Mac for the section in this folder AT ALL, same
        // minute included — for the record of a replacement that fails, which
        // must say what was lost even when the card rightly said nothing.
        let alreadySet: Date? = momentAlreadySet(
            courseCode: course.code, sectionNumber: sectionNumber, inWorkingFolder: workspaceURL
        )
        // Every job THIS folder already has for the section, found by the
        // folder scan rather than by name: the one under this label, and one
        // set before #237 under the old label, which would otherwise be left
        // beside the new one and publish the section twice. Another folder's
        // job of the same section is not in this list, and is left standing —
        // that is the fix.
        let existing: [Agent] = agents(
            inWorkingFolder: workspaceURL, courseCode: course.code, sectionNumber: sectionNumber
        )

        // Anything already scheduled for this section goes first, so the
        // replacement is never briefly a second agent. Booted out only: the
        // plists stay on disk until the new job is ACCEPTED, so a failure
        // below can hand them straight back to macOS (#237's review, M1).
        runner.bootOut(label: label)
        for agent in existing where agent.label != label {
            runner.bootOut(label: agent.label)
        }

        do {
            // The script the app will run, written beside nothing else and
            // executable, so launchd's job is only "start Plantoir with this
            // file" and every decision stays in one place.
            let commandURL: URL = ScheduledDeploy.scriptURL(label: label)
            try FileManager.default.createDirectory(
                at: commandURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let command: String = "#!/bin/bash\n" + oneShotCommand(
                courseCode: course.code,
                sectionNumber: sectionNumber,
                workspaceURL: workspaceURL,
                deployArgumentsList: deploying.argumentsList,
                destinationTypes: deploying.types,
                destinationDescriptions: deploying.descriptions
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
            // write — so every OLD plist is still on disk, only booted out.
            // Put them back in front of macOS, so that "it still stands" is
            // true now rather than from the next login, and say so.
            noteTheOldDeployAfterAFailedWrite(
                alreadySet, plists: plistURLs(of: existing), runner: runner,
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
            // A job under ANOTHER name — one set before #237 — still has its
            // plist, because nothing is deleted until the new job is accepted.
            // Hand it back rather than lose it. A job under THIS label was
            // overwritten by the write above and is gone, as it always was.
            //
            // Each line names the job it is about (#237 review, L3): in the
            // rare folder holding BOTH — an older copy of the app still
            // running — the one that STANDS is the old-named job, and the one
            // LOST is the one under this label, whichever is earlier.
            var handedBack: [Agent] = []
            var overwritten: [Agent] = []
            for agent in existing {
                if agent.label == label {
                    overwritten.append(agent)
                } else {
                    handedBack.append(agent)
                }
            }
            if !handedBack.isEmpty && bootstrapEveryOne(of: plistURLs(of: handedBack), runner: runner) {
                if let standing = earliestUpcoming(of: handedBack) {
                    ActivityTrail.note(
                        .scheduledDeployCouldNotBeSet,
                        "could not set a scheduled deploy for \(dayAndTimeText(when)); "
                            + "the one set for \(dayAndTimeText(standing)) still stands",
                        course: course.code,
                        section: sectionNumber
                    )
                }
                noteTheReplacedDeployWasLost(
                    earliestUpcoming(of: overwritten), course: course, sectionNumber: sectionNumber
                )
            } else {
                noteTheReplacedDeployWasLost(alreadySet, course: course, sectionNumber: sectionNumber)
            }
            return "macOS would not accept the scheduled deploy: \(failure)"
        }

        // The new job is in. NOW the old ones under other names go — plist and
        // wrapper both, the way a cancel takes them, so no runnable copy is
        // left on disk.
        for agent in existing where agent.label != label {
            try? FileManager.default.removeItem(at: agent.plistURL)
            try? FileManager.default.removeItem(at: ScheduledDeploy.scriptURL(label: agent.label))
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

    /// The earliest moment still ahead among some jobs, or nil — the same
    /// reading `nextRun` makes, for a list already in hand.
    private static func earliestUpcoming(of agents: [Agent], now: Date = Date()) -> Date? {
        var earliest: Date?
        for agent in agents {
            guard let moment = agent.scheduledFor, moment > now else {
                continue
            }
            if let soonestSoFar = earliest, soonestSoFar <= moment {
                continue
            }
            earliest = moment
        }
        return earliest
    }

    /// The plist of every job in a list.
    private static func plistURLs(of agents: [Agent]) -> [URL] {
        var result: [URL] = []
        for agent in agents {
            result.append(agent.plistURL)
        }
        return result
    }

    /// Hands every plist still on disk back to macOS. True only when there was
    /// at least one and every one was accepted.
    private static func bootstrapEveryOne(of plists: [URL], runner: LaunchControlRunning) -> Bool {
        var anyRestored: Bool = false
        var allRestored: Bool = true
        for plist in plists {
            if !FileManager.default.fileExists(atPath: plist.path) {
                continue
            }
            if runner.bootstrap(plistURL: plist) == nil {
                anyRestored = true
            } else {
                allRestored = false
            }
        }
        return anyRestored && allRestored
    }

    /// A scheduled deploy was ASKED FOR and refused before anything was
    /// written — by the schedule sheet's button, or by `schedule_deploy`
    /// from either assistant (GitHub #322). Not by the approval card or
    /// `plan_scheduled_deploy`: those are advisory and repeat.
    ///
    /// Names the destination the refusal was reached for, because that is
    /// what #322 needed and nothing on the trail said: the teacher had saved
    /// the course as deploying to a folder, and the assistant refused it as
    /// "never deployed" from a copy that still said Netlify. With this line
    /// the contradiction sits two lines under "saved the settings", readable
    /// without the code. The destination is named by KIND — a folder's path
    /// is not written here — and only the refusal's first sentence is kept.
    static func noteRefusedBeforeAnythingWasWritten(
        course: Course,
        sectionNumber: Int,
        when: Date,
        refusal: String
    ) {
        ActivityTrail.note(
            .scheduledDeployCouldNotBeSet,
            "could not set a scheduled deploy for \(dayAndTimeText(when)): refused before anything was written, "
                + "deploying to \(destinationKind(of: course.configuration)): \(firstSentence(of: refusal))",
            course: course.code,
            section: sectionNumber
        )
    }

    /// Where the course's primary destination is, by kind rather than by
    /// path: "Netlify", "Cloudflare Pages" or "a folder".
    static func destinationKind(of configuration: CourseConfiguration) -> String {
        if configuration.deployTarget == "local_folder" {
            return "a folder"
        }
        return DeployCommand.destinationDescription(for: configuration)
    }

    /// The text up to and including its first full stop followed by a
    /// space, or all of it when there is none.
    static func firstSentence(of text: String) -> String {
        guard let end = text.range(of: ". ") else {
            return text
        }
        return String(text[text.startIndex..<end.lowerBound]) + "."
    }

    /// The new deploy's files could not be written. The old ones' plists are
    /// untouched on disk (the write that failed is atomic, and everything
    /// before it writes elsewhere), but they were booted out a moment ago — so
    /// they are handed back to macOS, and the trail says what is TRUE: the
    /// deploy already set still stands, or, if macOS would not take it back,
    /// that it was turned off. Silent when nothing was set.
    ///
    /// Known and left as it was: the one-shot script is written BEFORE the
    /// plist, at the same path for the section, so an old plist restored here
    /// runs whatever script the failed attempt managed to write. (Only for a
    /// job under THIS label; one set before #237 has its own script.)
    private static func noteTheOldDeployAfterAFailedWrite(
        _ alreadySet: Date?,
        plists: [URL],
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
        if bootstrapEveryOne(of: plists, runner: runner) {
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

        // IS ANOTHER PROGRAM BUILDING THIS COURSE? (#156) An assistant working
        // from another app, the teacher's own window, another copy of
        // Plantoir: two builds of one section clear the same folder, so this
        // waits for the other to finish — up to ten minutes, looking every
        // fifteen seconds — and then takes `build` and `publish` leases of its
        // own so the others wait for IT. Still busy after ten minutes, it
        // stands down and says so rather than spoil both. A pre-v1.2.0 plist
        // names no section, so there is no course to ask about and it goes
        // ahead as it always did.
        var leasesTaken: [URL] = []
        if let section {
            let coursesDirectory: URL = section.courseDirectory.deletingLastPathComponent()
            let answer: CourseWait = waitForTheCourse(
                courseCode: section.courseCode, coursesDirectory: coursesDirectory
            )
            switch answer {
            case .goAhead(let leases, let waited, let waitedFor):
                leasesTaken = leases
                if let waitedFor {
                    ActivityTrail.note(
                        .scheduledPublishWaitedForTheCourse,
                        "a scheduled publish waited \(Int(waited.rounded())) seconds while the course was "
                        + WorkLeaseFiles.describe(waitedFor) + ", then went ahead",
                        course: section.courseCode,
                        section: section.sectionNumber
                    )
                }
            case .standDown(let holding, let waited):
                ActivityTrail.note(
                    .scheduledPublishWaitedForTheCourse,
                    "a scheduled publish waited \(Int(waited.rounded())) seconds while the course was "
                    + WorkLeaseFiles.describe(holding) + ", and stood down",
                    course: section.courseCode,
                    section: section.sectionNumber
                )
                standDown(script: script, section: section, now: Date(), kind: .courseWasBusy)
            }
        }

        // WHERE DOES THE COURSE DEPLOY NOW? (#323) Read after the lateness
        // check and after the wait, so a Save made while this run waited
        // counts. The wrapper is written afresh from the settings as they are
        // and run; one that would be refused now is not run at all. A plist
        // from before v1.2.0 names no section, so there is nothing to read
        // and it runs its wrapper as written — the one stale path left.
        if let section, let jobLabel = ScheduledDeploy.label(fromScriptPath: script) {
            let environment: [String: String] = ProcessInfo.processInfo.environment
            // This process IS the app (same bundle, same defaults domain), so
            // the Account ID is the one the teacher set; measured under
            // launchd before this shipped — docs 07, "#323".
            let reading: RunReading = MainActor.assumeIsolated {
                let accountID: String = UserDefaults.standard.string(forKey: AppSettings.cloudflareAccountIDKey) ?? ""
                return readAtTheRun(
                    label: jobLabel,
                    section: section,
                    scheduledTo: scheduledDestinations(from: environment),
                    cloudflareAccountID: accountID
                )
            }
            let stands: Bool = jobStillStands(label: jobLabel, environment: environment)
            var wrapper: WrapperWrite?
            if stands, case .deploy(let command, _, _) = reading {
                wrapper = writeTheRunsWrapper(command, to: URL(fileURLWithPath: script))
            }
            let step: RunStep = whatTheRunDoes(reading: reading, jobStillStands: stands, wrapper: wrapper)
            if let line = trailLineAtTheRun(step: step, reading: reading) {
                ActivityTrail.note(
                    .scheduledPublishReadTheSettings, line,
                    course: section.courseCode, section: section.sectionNumber
                )
            }
            switch step {
            case .run:
                clearTheOldNamedRecord(label: jobLabel, section: section, homeFolder: RealHome.forFiles)
            case .leaveQuietly:
                for lease in leasesTaken {
                    WorkLeaseFiles.remove(at: lease)
                }
                exit(0)
            case .standDown(let refusal):
                // The leases go FIRST: `standDown` never returns, and until
                // #323 it was only ever reached holding none, so a refusal
                // here would otherwise leave the course reading as busy until
                // they went stale.
                for lease in leasesTaken {
                    WorkLeaseFiles.remove(at: lease)
                }
                standDown(
                    script: script, section: section, now: Date(),
                    kind: .couldNotRunAsSetNow, reason: refusal.reasonClause
                )
            }
        }

        // The job's own name, from the script it was started with — NEVER
        // rebuilt from the course, section and folder (#237). On a Mac that
        // has just been updated every pending job carries the label from
        // before #237, and its wrapper has that label's log and success note
        // baked in: a rebuilt label would read an empty log, miss the success
        // note (the section left " — Edited" after a good publish) and boot
        // out a job that does not exist, leaving the real one loaded.
        let label: String? = ScheduledDeploy.label(fromScriptPath: script)

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
            if let label {
                logSizeBeforeRunning = logSize(label: label)
            }
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
            recordScheduledPublish(
                label: label, section: section, fingerprint: fingerprintBeforeRunning
            )
            // Publishes regardless; the findings are kept for somebody to read
            // when they are next at the machine.
            recordFolderProblems(
                label: label, section: section, fromByteOffset: logSizeBeforeRunning
            )
            // The trail line for a run that stopped, written HERE rather than
            // when a teacher opens the section. This process IS Plantoir
            // (--run-scheduled-deploy), so the redactor and the trail are
            // loaded — and a teacher who never opens the section is exactly
            // the one who reports "my site did not update", so a line that
            // waits for them to look is a line they never get.
            if let section {
                let folderID: String = folderIDForRun(label: label, section: section)
                // A job set before #237 ran a wrapper that wrote the record
                // under the old, folder-less name. File it under this folder's
                // before anything reads it, so the badge that shows it is this
                // folder's and never another's.
                ScheduledPublishOutcome.fileUnderTheFolder(
                    inHomeFolder: RealHome.forFiles,
                    course: section.courseCode,
                    section: section.sectionNumber,
                    folderID: folderID,
                    jobLabel: label
                )
                ScheduledPublishOutcome.noteOnTrail(
                    inHomeFolder: RealHome.forFiles,
                    course: section.courseCode,
                    section: section.sectionNumber,
                    folderID: folderID
                )
            }
            // The build and the publish are over, so the leases go before
            // anything that could end this process — booting the job out
            // below ends it.
            for lease in leasesTaken {
                WorkLeaseFiles.remove(at: lease)
            }
            // LAST, once the work above is done. See the note in
            // oneShotCommand: this used to be the wrapper's final line, which
            // killed this process before any of the three calls above ran.
            // The notification (#212) goes out first, for the same reason.
            // The job is booted out by the LABEL it was started with (#237).
            let status: Int32 = process.terminationStatus
            let courseCode: String? = section?.courseCode
            let sectionNumber: Int? = section?.sectionNumber
            var noticeFolderID: String?
            var noticeFolderPath: String?
            if let section {
                noticeFolderID = folderIDForRun(label: label, section: section)
                noticeFolderPath = workingFolderURL(forCourseDirectory: section.courseDirectory).path
            }
            announceThenLeave(
                courseCode: courseCode, sectionNumber: sectionNumber, folderID: noticeFolderID,
                workingFolderPath: noticeFolderPath
            ) {
                if let label {
                    bootOutAgent(label: label)
                }
                exit(status)
            }
        } catch {
            for lease in leasesTaken {
                WorkLeaseFiles.remove(at: lease)
            }
            FileHandle.standardError.write(Data(
                "Plantoir could not run the scheduled deploy: \(error.localizedDescription)\n".utf8
            ))
            exit(1)
        }
    }

    // MARK: - Where it deploys is read when it runs (#323)

    /// Why a run could not deploy the way the course is set now.
    nonisolated enum RunRefusal: Equatable, Sendable {

        // MARK: - Cases

        /// Something the schedule sheet would refuse now.
        case refused(ScheduledDeployRefusal)

        /// The course's settings file was gone or would not parse. Fails
        /// CLOSED, the opposite of the lateness window's default, because a
        /// destination has no safe default: guessing where to deploy is the
        /// fault #323 is about.
        case settingsCouldNotBeRead

        /// The settings were read, but the run could not write its wrapper
        /// (the #323 plan review's M2). Said as what happened, never as "could
        /// not read the settings", which would be false.
        case wrapperCouldNotBeWritten

        // MARK: - Computed properties

        /// The clause the record carries as its second line, and the trail
        /// line's reason. True at the run, with no remedy and no path.
        var reasonClause: String {
            switch self {
            case .refused(let refusal):
                return refusal.reasonClause
            case .settingsCouldNotBeRead:
                return ScheduledDeployWording.settingsCouldNotBeRead
            case .wrapperCouldNotBeWritten:
                return ScheduledDeployWording.wrapperCouldNotBeWritten
            }
        }
    }

    /// What the settings said at the run: deploy with this wrapper, or not.
    nonisolated enum RunReading: Equatable, Sendable {
        case deploy(command: String, destinations: [String], scheduledTo: [String]?)
        case refuse(RunRefusal, destinationsNow: [String], scheduledTo: [String]?)
    }

    /// What writing the run's wrapper did.
    nonisolated enum WrapperWrite: Equatable, Sendable {

        /// Written, over the job's own wrapper.
        case written

        /// There was no wrapper to write over: the job was cancelled a moment
        /// ago (cancelling deletes the wrapper before the plist). Nothing is
        /// written, so a cancelled deploy cannot be brought back to life.
        case wasGone

        /// The write failed.
        case failed
    }

    /// The one decision the run makes after reading the settings.
    nonisolated enum RunStep: Equatable, Sendable {

        /// Run the wrapper just written.
        case run

        /// Deploy nothing, clear the job away, and say why.
        case standDown(RunRefusal)

        /// The job was cancelled or replaced while the run waited: deploy
        /// nothing, write no record and no notification, and leave — the
        /// teacher did this, and a new job under the same name must not be
        /// booted out.
        case leaveQuietly
    }

    /// Reads the course's settings AT THE RUN and writes the wrapper from
    /// them, or says why it will not (GitHub #323).
    ///
    /// Until #323 the wrapper written at scheduling was what ran, with every
    /// destination's `deploy.sh` arguments baked into it — so a course moved
    /// to a folder after scheduling published to the OLD place at half six
    /// and reported success. Everything `destinationRefusal` refuses is asked
    /// again here: reading the destination WITHOUT the refusals would let a
    /// course switched to a Cloudflare Pages destination never deployed to
    /// publish to a guessed project name and report success, because
    /// `publish_to_cloudflare` never refuses a first deploy.
    ///
    /// Pure apart from reading the settings file, so it is tested directly;
    /// the run (`runScheduled`, which never returns) only acts on the answer.
    /// `scheduledTo` is passed through for the trail and NEVER used to decide.
    static func readAtTheRun(
        label: String,
        section: (courseDirectory: URL, courseCode: String, sectionNumber: Int),
        scheduledTo: [String]?,
        cloudflareAccountID: String,
        homeFolder: URL = RealHome.forFiles
    ) -> RunReading {
        let coursesFolder: URL = section.courseDirectory.deletingLastPathComponent()
        // Found the way the lateness window finds it: the exact name first,
        // then a UNIQUE sanitised match (a job set before the course code went
        // into the plist carries only its label's spelling).
        guard let folderName = ScheduledDeployLateness.courseFolderName(
            matching: section.courseCode, inCoursesFolder: coursesFolder
        ) else {
            return .refuse(.settingsCouldNotBeRead, destinationsNow: [], scheduledTo: scheduledTo)
        }
        let courseDirectory: URL = coursesFolder.appendingPathComponent(folderName)
        guard let configuration = try? CourseConfiguration(
            contentsOf: courseDirectory.appendingPathComponent("course_config.json")
        ) else {
            return .refuse(.settingsCouldNotBeRead, destinationsNow: [], scheduledTo: scheduledTo)
        }
        let course: Course = Course(code: folderName, directoryURL: courseDirectory, configuration: configuration)
        let deploying: DeployPlan = deployPlan(
            course: course, sectionNumber: section.sectionNumber, cloudflareAccountID: cloudflareAccountID
        )
        if let refusal = destinationRefusal(
            course: course, sectionNumber: section.sectionNumber, cloudflareAccountID: cloudflareAccountID
        ) {
            return .refuse(.refused(refusal), destinationsNow: deploying.descriptions, scheduledTo: scheduledTo)
        }
        let command: String = "#!/bin/bash\n" + oneShotCommand(
            label: label,
            folderID: folderIDForRun(label: label, section: section),
            courseCode: course.code,
            sectionNumber: section.sectionNumber,
            workspaceURL: workingFolderURL(forCourseDirectory: courseDirectory),
            deployArgumentsList: deploying.argumentsList,
            destinationTypes: deploying.types,
            destinationDescriptions: deploying.descriptions,
            homeFolder: homeFolder
        ) + "\n"
        return .deploy(command: command, destinations: deploying.descriptions, scheduledTo: scheduledTo)
    }

    /// Whether the job this run was started for still stands: its plist is
    /// still on disk AND still names this run's moment (the #323 plan
    /// review's M1).
    ///
    /// Only the wrapper's own first line removes the plist, and it has not
    /// run yet, so a missing plist means the teacher cancelled it while this
    /// run waited (#156 waits up to ten minutes). A plist naming another
    /// moment means it was scheduled again under the same name. Either way
    /// this run must not deploy — and, now that it writes its wrapper afresh,
    /// the deleted wrapper is no longer what stops it, so this is.
    nonisolated static func jobStillStands(
        label: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        let plistURL: URL = launchAgentsDirectoryURL().appendingPathComponent("\(label).plist")
        if !FileManager.default.fileExists(atPath: plistURL.path) {
            return false
        }
        guard let stamp = environment[scheduledForKey],
              let thisRunsMoment = ISO8601DateFormatter().date(from: stamp) else {
            // A job set before the moment was recorded: the plist being there
            // is all there is to go on.
            return true
        }
        guard let standing = agent(readingPlistAt: plistURL)?.scheduledFor else {
            return false
        }
        return standing == thisRunsMoment
    }

    /// Writes the run's wrapper over the job's own — only if it is still
    /// there — and says what happened.
    ///
    /// Write-if-exists, so a job cancelled a moment ago (its wrapper deleted
    /// first) is not brought back. The permissions are not a condition: the
    /// run starts `/bin/bash <script>`, so the executable bit does not matter,
    /// and a failure to set it must not cancel a publish over nothing.
    nonisolated static func writeTheRunsWrapper(_ command: String, to scriptURL: URL) -> WrapperWrite {
        if !FileManager.default.fileExists(atPath: scriptURL.path) {
            return .wasGone
        }
        do {
            try command.write(to: scriptURL, atomically: true, encoding: .utf8)
        } catch {
            return .failed
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return .written
    }

    /// The run's decision, as a pure function (the #323 plan review's M2).
    ///
    /// **The only way to `.run` is a wrapper written from the settings just
    /// read.** There is no path that runs the wrapper left on disk from
    /// scheduling: that is the stale deploy #323 exists to stop.
    nonisolated static func whatTheRunDoes(
        reading: RunReading,
        jobStillStands: Bool,
        wrapper: WrapperWrite?
    ) -> RunStep {
        if !jobStillStands {
            return .leaveQuietly
        }
        switch reading {
        case .refuse(let refusal, _, _):
            return .standDown(refusal)
        case .deploy:
            guard let wrapper else {
                return .standDown(.wrapperCouldNotBeWritten)
            }
            switch wrapper {
            case .written:
                return .run
            case .wasGone:
                return .leaveQuietly
            case .failed:
                return .standDown(.wrapperCouldNotBeWritten)
            }
        }
    }

    /// The line `scheduled publish read the course's settings` carries, or
    /// nil when there is nothing to say.
    ///
    /// Written ONLY when something differs from what the teacher was told:
    /// a run that went ahead somewhere other than where it was set to go
    /// (shape A), or one that stood down (shape B). A run that went where it
    /// was set to writes nothing here — `scheduled publish finished` already
    /// names where it went, and a line per run saying "the same as before" is
    /// noise. A job set before #323 recorded no promise, so it is never
    /// "somewhere else".
    nonisolated static func trailLineAtTheRun(step: RunStep, reading: RunReading) -> String? {
        switch step {
        case .leaveQuietly:
            return nil
        case .run:
            guard case .deploy(_, let destinations, let scheduledTo) = reading,
                  let scheduledTo, scheduledTo != destinations else {
                return nil
            }
            return "a scheduled publish was set to deploy to " + scheduledTo.joined(separator: ", ")
                + "; the course deploys to " + destinations.joined(separator: ", ")
                + " now, so it is deploying there"
        case .standDown(let refusal):
            var line: String = "a scheduled publish could not deploy the way the course is set now ("
                + refusal.reasonClause + ")"
            var now: [String] = []
            var then: [String]?
            switch reading {
            case .refuse(_, let destinationsNow, let scheduledTo):
                now = destinationsNow
                then = scheduledTo
            case .deploy(_, let destinations, let scheduledTo):
                now = destinations
                then = scheduledTo
            }
            if let then, !now.isEmpty, then != now {
                line += "; it was set to deploy to " + then.joined(separator: ", ")
                    + ", and the course deploys to " + now.joined(separator: ", ") + " now"
            }
            return line
        }
    }

    /// Where the deploy was set to go, from the environment launchd hands the
    /// run — or nil for a job set before #323, or a value that does not read.
    nonisolated static func scheduledDestinations(from environment: [String: String]) -> [String]? {
        guard let text = environment[scheduledToKey],
              let data = text.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data),
              let list = decoded as? [String] else {
            return nil
        }
        return list
    }

    /// Before the run's own wrapper runs, for a job set before #237: remove
    /// the record under the OLD, folder-less name (the #323 plan review's H1).
    ///
    /// That job's own wrapper used to clear it as its first act. The wrapper
    /// written at the run files its record under the folder's name instead,
    /// so nothing would clear the old one — and `fileUnderTheFolder`, which
    /// runs after every such job, would then move LAST WEEK's record over
    /// tonight's: a failed run announced as last week's success. Removing it
    /// here does what the old first line did, and drains the orphan.
    nonisolated static func clearTheOldNamedRecord(
        label: String,
        section: (courseDirectory: URL, courseCode: String, sectionNumber: Int),
        homeFolder: URL
    ) {
        if folderID(fromLabel: label) != nil {
            return
        }
        try? FileManager.default.removeItem(at: ScheduledPublishOutcome.legacyRecordURL(
            inHomeFolder: homeFolder, course: section.courseCode, section: section.sectionNumber
        ))
    }

    // MARK: - Waiting for another build of the course (#156)

    /// What `waitForTheCourse` decided.
    enum CourseWait: Equatable {

        /// The course is free and this run's own leases are on disk.
        /// `waitedFor` is the holding it waited on, or nil when it did not
        /// have to wait at all.
        case goAhead(leases: [URL], waited: TimeInterval, waitedFor: WorkLeaseFiles.Holding?)

        /// Still busy at the cap. Nothing of this run's is on disk.
        case standDown(WorkLeaseFiles.Holding, waited: TimeInterval)
    }

    /// The longest a publish set for later waits for another build of its
    /// course: ten minutes (#156, director's ruling, 2026-09-25 — reversible).
    /// Long enough for any ordinary build or deploy to finish; short enough
    /// that a run which then stands down is still early in the teacher's
    /// morning, when there is time to publish by hand.
    nonisolated static let longestWaitForTheCourse: TimeInterval = 600

    /// How often it looks again while waiting.
    nonisolated static let lookAgainEvery: TimeInterval = 15

    /// Waits until no other live program holds `build` or `publish` on the
    /// course, then takes this run's own `build` and `publish` leases and
    /// looks once more — take, then check — so that two runs, or a run and
    /// the window, cannot both go ahead.
    ///
    /// **The cap is measured on the WALL clock** (`now`, a `Date`): a Mac
    /// that sleeps part way through would otherwise pause the count, and a
    /// run woken at eight would still be "waiting" for the build it found at
    /// half six. It is synchronous because the scheduled run is (it never
    /// returns and has no app around it); the pause between looks is a
    /// blocking sleep of the interval, which is the intended behaviour — a
    /// paced re-check — rather than a guess at when something settles.
    ///
    /// Holds NOTHING while it waits, so the program it is waiting for is not
    /// itself made to wait. Every seam is injectable so a test can run the
    /// whole ten minutes in no time and stage the race exactly.
    nonisolated static func waitForTheCourse(
        courseCode: String,
        coursesDirectory: URL,
        now: () -> Date = { return Date() },
        pause: (TimeInterval) -> Void = { seconds in Thread.sleep(forTimeInterval: seconds) },
        heldElsewhere: (() -> [WorkLeaseFiles.Holding])? = nil,
        longest: TimeInterval = ScheduledDeploy.longestWaitForTheCourse,
        every: TimeInterval = ScheduledDeploy.lookAgainEvery
    ) -> CourseWait {
        let started: Date = now()
        let deadline: Date = started.addingTimeInterval(longest)
        var lastSeen: WorkLeaseFiles.Holding? = nil

        while true {
            let holdings: [WorkLeaseFiles.Holding] = ScheduledDeploy.readHoldings(
                heldElsewhere: heldElsewhere, courseCode: courseCode, coursesDirectory: coursesDirectory
            )
            if let inTheWay = WorkLeaseFiles.blocking(among: holdings, asker: .aScheduledPublish, claim: nil) {
                lastSeen = inTheWay
            } else {
                // Free: take, then check.
                var taken: [URL] = []
                var claim: WorkLeaseFiles.Claim? = nil
                if let build = WorkLeaseFiles.write(
                    kind: WorkLeaseFiles.buildKind, courseCode: courseCode, coursesDirectory: coursesDirectory
                ) {
                    taken.append(build.url)
                    claim = WorkLeaseFiles.Claim(moment: build.moment, pid: getpid())
                }
                if let publish = WorkLeaseFiles.write(
                    kind: WorkLeaseFiles.publishKind, courseCode: courseCode, coursesDirectory: coursesDirectory
                ) {
                    taken.append(publish.url)
                }
                let waited: TimeInterval = now().timeIntervalSince(started)
                guard let claim else {
                    // Nothing could be written. A lease that cannot be written
                    // must not stop the publish (Windows' rule too).
                    return .goAhead(leases: taken, waited: waited, waitedFor: lastSeen)
                }
                let afterTaking: [WorkLeaseFiles.Holding] = ScheduledDeploy.readHoldings(
                    heldElsewhere: heldElsewhere, courseCode: courseCode, coursesDirectory: coursesDirectory
                )
                if let earlier = WorkLeaseFiles.blocking(
                    among: afterTaking, asker: .aScheduledPublish, claim: claim
                ) {
                    for url in taken {
                        WorkLeaseFiles.remove(at: url)
                    }
                    lastSeen = earlier
                } else {
                    return .goAhead(leases: taken, waited: waited, waitedFor: lastSeen)
                }
            }

            let current: Date = now()
            if current >= deadline, let lastSeen {
                return .standDown(lastSeen, waited: current.timeIntervalSince(started))
            }
            let remaining: TimeInterval = deadline.timeIntervalSince(current)
            pause(min(every, max(remaining, 0)))
        }
    }

    /// The other programs' holdings, from the injected source or from disk.
    nonisolated private static func readHoldings(
        heldElsewhere: (() -> [WorkLeaseFiles.Holding])?,
        courseCode: String,
        coursesDirectory: URL
    ) -> [WorkLeaseFiles.Holding] {
        if let heldElsewhere {
            return heldElsewhere()
        }
        return WorkLeaseFiles.heldElsewhere(courseCode: courseCode, coursesDirectory: coursesDirectory)
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
        now: Date = Date(),
        kind: ScheduledPublishOutcome.Kind = .tooLateToRun,
        reason: String? = nil
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
            let home: URL = RealHome.forFiles
            let folderID: String = folderIDForRun(label: label(fromScriptPath: script), section: section)
            // Anything an earlier run left is cleared first — the same thing
            // the wrapper does with its own first line, and for the same
            // reason: `recordStopped` keeps the FIRST record, so last week's
            // would block today's from being written at all.
            ScheduledPublishOutcome.clear(
                inHomeFolder: home, course: section.courseCode, section: section.sectionNumber,
                folderID: folderID
            )
            ScheduledPublishOutcome.recordStopped(
                ScheduledPublishOutcome.Stopped(
                    kind: kind,
                    // The record's second line: the unshown stand-in for the
                    // kinds that attempted nothing, and — for
                    // `couldNotRunAsSetNow` — the reason, which IS shown
                    // (#323). One shape for every record either way.
                    destination: reason ?? ScheduledPublishOutcome.nothingWasDeployedName,
                    when: now
                ),
                inHomeFolder: home,
                course: section.courseCode,
                section: section.sectionNumber,
                folderID: folderID
            )
            ScheduledPublishOutcome.noteOnTrail(
                inHomeFolder: home, course: section.courseCode, section: section.sectionNumber,
                folderID: folderID
            )
        }

        let jobLabel: String? = label(fromScriptPath: script)
        var noticeFolderID: String?
        var noticeFolderPath: String?
        if let section {
            noticeFolderID = folderIDForRun(label: jobLabel, section: section)
            noticeFolderPath = workingFolderURL(forCourseDirectory: section.courseDirectory).path
        }
        announceThenLeave(
            courseCode: section?.courseCode, sectionNumber: section?.sectionNumber, folderID: noticeFolderID,
            workingFolderPath: noticeFolderPath
        ) {
            if let jobLabel {
                bootOutAgent(label: jobLabel)
            }
            // Zero, not a failure: nothing went wrong. The job was asked to do
            // something that no longer made sense and declined, which is the
            // feature rather than a fault, and a non-zero exit here would land
            // in the section's log as an error nobody can act on.
            exit(0)
        }
    }

    /// Tell the teacher how the run went (#212), then leave. Never returns.
    ///
    /// Called with the record written and the trail line down, and BEFORE the
    /// job is booted out, because booting it out ends this process. A plist
    /// written before v1.2.0 names no section, writes no record, and so has
    /// nothing to announce: it leaves at once, as it always did.
    ///
    /// **`dispatchMain()` is a deliberate exception to the no-GCD rule**, the
    /// same one `AssistMCPServer.serve` makes and #216's `DispatchSource`
    /// was given. This function is synchronous and never returns — it runs
    /// inside `App.init`, before any run loop exists — and the notification
    /// centre only answers asynchronously. Something has to keep the process
    /// alive while it does, and parking the main thread in `dispatchMain()`
    /// is what lets the task below (and the main actor) run at all.
    /// REJECTED: `RunLoop.main.run()`, which returns at once when no input
    /// source is attached; a semaphore, which is worse GCD and would block the
    /// very thread the answer may need.
    ///
    /// The wait is bounded (`ScheduledPublishNotice.ceiling`), so a
    /// notification service that never answers cannot keep a finished run
    /// alive.
    ///
    /// `folderID` is the working folder's id the run's record is filed under
    /// (`folderIDForRun`, #237) — the notification is keyed by it too.
    /// `workingFolderPath` is that folder's path, which the notification
    /// carries so a click on it opens the section (#306).
    nonisolated static func announceThenLeave(
        courseCode: String?,
        sectionNumber: Int?,
        folderID: String?,
        workingFolderPath: String?,
        leave: @escaping @Sendable () -> Never
    ) -> Never {
        guard let courseCode, let sectionNumber, let folderID, let workingFolderPath else {
            leave()
        }
        Task { @MainActor in
            await ScheduledPublishNotice.announce(
                inHomeFolder: RealHome.forFiles, course: courseCode, section: sectionNumber,
                folderID: folderID, workingFolderPath: workingFolderPath
            )
            leave()
        }
        dispatchMain()
    }

    /// Where a scheduled run leaves the folder problems it found, for the app
    /// to read the next time it opens.
    ///
    /// Beside the success sentinel and consumed the same way, because the
    /// shape is already proven here: a one-shot run writes a small file, the
    /// app reads it and deletes it.
    ///
    /// Named after the section AND the working folder (#237), whatever label
    /// the run that wrote it had: the run writes it in Swift, so a job set
    /// before #237 files its findings under the new name too
    /// (`folderIDForRun`), and the section's window reads only that. Two
    /// folders holding the same section therefore never read — and consume —
    /// each other's.
    nonisolated static func findingsSentinelURL(
        courseCode: String,
        sectionNumber: Int,
        folderID: String,
        inHomeFolder home: URL? = nil
    ) -> URL {
        let label: String = legacyAgentLabel(courseCode: courseCode, sectionNumber: sectionNumber)
            + "." + folderID
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
    ///
    /// **It also leaves the `folder problem found` trail line, here, at the
    /// end of the run (#153)** — one per distinct finding. Until then a
    /// scheduled run's findings reached the trail only if somebody later
    /// opened the section, and `takeFolderProblems` noted nothing even then,
    /// so the overnight path — the one the check exists for — left no line at
    /// all. Written by THIS process rather than when the section is opened
    /// (Windows' shape), for the reason `scheduledPublishStopped.trail`
    /// gives: a problem found at half six must be dated to half six, and a
    /// teacher who never opens that section must still get the line. Two
    /// imprecisions accepted: the line is stamped when the run FINISHES, not
    /// when the build printed the finding (minutes apart, the same as
    /// `notePagesDatedByTheBuild`); and a log found SHORTER than the offset
    /// is read whole (`textOfLog`), so after a rotation mid-run an older
    /// night's findings are noted again — the sentinel has always had the
    /// same edge.
    ///
    /// The LOG is the job's own (its label, from the script); the findings go
    /// under the section and the working FOLDER (`folderIDForRun`), so that a
    /// job set before #237 files them where this folder's window looks.
    nonisolated static func recordFolderProblems(
        label: String?,
        section: (courseDirectory: URL, courseCode: String, sectionNumber: Int)?,
        fromByteOffset offset: UInt64,
        inHomeFolder home: URL? = nil
    ) {
        guard let label, let section else {
            return
        }
        let log: URL = logURL(label: label, inHomeFolder: home)
        guard let text = textOfLog(at: log, fromByteOffset: offset) else {
            return
        }
        notePagesDatedByTheBuild(in: text)
        // A launcher of this run that waited for, or refused on, something
        // running in the folder's workspace before remaking it (#94) — read
        // from the log for the same reason as the line above: nobody is
        // watching a console at half six in the morning.
        WorkspaceInUseReport.noteOnTheTrail(from: text)
        noteFolderProblems(in: text)
        var markerLines: [String] = []
        // Split on scalars, not Characters: Swift folds "\r\n" into one
        // Character, so `split(separator: "\n")` would not split a PTY's
        // output at all. launchd hands the child a plain file, so the log has
        // "\n" endings today (the launchers ask for a terminal only when they
        // have one) — this is hardening, not a fix for something seen.
        for rawLine in SiteHealthFinding.linesOf(text) {
            let line: String = rawLine.trimmingCharacters(in: .whitespaces)
            // Once each: a finding the build printed twice is one problem,
            // and the dialog listed it twice (#153 review).
            if SiteHealthFinding.isMarkerLine(line) && !markerLines.contains(line) {
                markerLines.append(line)
            }
        }
        let sentinel: URL = findingsSentinelURL(
            courseCode: section.courseCode,
            sectionNumber: section.sectionNumber,
            folderID: folderIDForRun(label: label, section: section),
            inHomeFolder: home
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

    /// The pages this run's build gave their class's date (#275, #276), on
    /// the activity trail — the same line a preview or a publish from the app
    /// leaves, read from the same `PLANTOIR_DATED:` line, but out of this
    /// run's own log rather than a console, because nobody is watching one.
    ///
    /// Recorded here rather than left out because a scheduled publish is
    /// often the FIRST build after a class goes visible, so it is the build
    /// likeliest to rewrite a teacher's files — and a change to their files
    /// nobody asked for in so many words is what "why did this page's date
    /// change?" is asked about, long after the night it ran.
    nonisolated static func notePagesDatedByTheBuild(in text: String) {
        for report in PagesDatedByTheBuild.reports(in: text) {
            ActivityTrail.note(
                .pagesDatedByTheBuild, report.trailSentence,
                course: report.course, section: report.section
            )
        }
    }

    /// This run's folder problems, on the activity trail: one
    /// `folder problem found` line per DISTINCT finding, in the words the
    /// console path writes (`SiteHealthFinding.trailSentence`). Why here and
    /// not when the section is opened: `recordFolderProblems`.
    nonisolated static func noteFolderProblems(in text: String) {
        var noted: [SiteHealthFinding] = []
        for finding in SiteHealthFinding.findings(in: text) {
            if noted.contains(finding) {
                continue
            }
            noted.append(finding)
            ActivityTrail.note(
                .folderProblemFound, finding.trailSentence,
                course: finding.course, section: finding.section
            )
        }
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
        label: String,
        inHomeFolder home: URL? = nil
    ) -> UInt64 {
        let log: URL = logURL(label: label, inHomeFolder: home)
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
    ///
    /// Notes NOTHING on the trail: the run itself already did, dated to the
    /// run (`recordFolderProblems`), so a finding is one trail line whether or
    /// not anybody ever opens the section.
    ///
    /// THIS working folder's only (#237): another folder holding the same
    /// section keeps its own, and is not robbed of it by this one opening
    /// first. A findings file written before #237 carries no folder and is not
    /// read — it would be another folder's as often as this one's.
    nonisolated static func takeFolderProblems(
        courseCode: String,
        sectionNumber: Int,
        inWorkingFolder workingFolderURL: URL,
        inHomeFolder home: URL? = nil
    ) -> [SiteHealthFinding] {
        let sentinel: URL = findingsSentinelURL(
            courseCode: courseCode,
            sectionNumber: sectionNumber,
            folderID: BuildOutputLocation.folderIdentifier(forWorkingFolder: workingFolderURL.path),
            inHomeFolder: home
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
    ///
    /// Read under the job's own LABEL — the name its wrapper wrote — never a
    /// rebuilt one (#237; see `runScheduled`).
    nonisolated static func recordScheduledPublish(
        label: String?,
        section: (courseDirectory: URL, courseCode: String, sectionNumber: Int)?,
        fingerprint: String?,
        inHomeFolder home: URL? = nil
    ) {
        guard let label, let section, let fingerprint else {
            return
        }
        let sentinel: URL = successSentinelURL(label: label, inHomeFolder: home)
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
    /// caller that did not think about which folder it meant would once have
    /// cancelled another working folder's live deploy and reported success.
    /// Every caller used to have to remember to ask first; one of them did not
    /// (`AssistToolRunner.turnOffAnyScheduledPublish`, the rollover path, until
    /// 2026-09-20), and a rule enforced by everybody remembering is a rule
    /// with a hole in it. Making the parameter mandatory means the unscoped
    /// form cannot be written by accident.
    ///
    /// **Everything this folder has for the section goes**, found by the
    /// folder scan: the job under this folder's label and one set before #237
    /// under the old label, each by the name it really has. **A job belonging
    /// to another folder is LEFT ALONE and reported as success**, deliberately
    /// — there is nothing of this folder's to turn off, which is the same
    /// answer as "there was never one set".
    @discardableResult
    static func cancelScheduledDeploy(
        courseCode: String,
        sectionNumber: Int,
        inWorkingFolder workingFolderURL: URL,
        runner: LaunchControlRunning = LaunchControl()
    ) -> String? {
        let ours: [Agent] = agents(
            inWorkingFolder: workingFolderURL, courseCode: courseCode, sectionNumber: sectionNumber
        )
        if ours.isEmpty {
            // Nothing on disk, but a job can still be LOADED with its plist
            // already gone — a wrapper removes its own plist first. Only this
            // folder's own label is safe to boot out blind: since #237 it
            // cannot name another folder's job.
            let label: String = agentLabel(
                courseCode: courseCode, sectionNumber: sectionNumber, workingFolder: workingFolderURL
            )
            runner.bootOut(label: label)
            try? FileManager.default.removeItem(at: scriptURL(label: label))
            return nil
        }
        for agent in ours {
            if let problem = cancel(agent: agent, runner: runner) {
                return problem
            }
        }
        return nil
    }

    /// Takes one job off, by the name it really has — its own label and its
    /// own plist, read off disk — rather than one rebuilt from the course,
    /// which for a job set before #237 would name a job that does not exist.
    @discardableResult
    static func cancel(agent: Agent, runner: LaunchControlRunning) -> String? {
        runner.bootOut(label: agent.label)
        // The script goes with the alarm. A cancelled deploy that left its
        // command behind would leave a runnable copy of itself on disk.
        try? FileManager.default.removeItem(at: scriptURL(label: agent.label))
        if FileManager.default.fileExists(atPath: agent.plistURL.path) {
            do {
                try FileManager.default.removeItem(at: agent.plistURL)
            } catch {
                return "The scheduled deploy could not be removed: \(error.localizedDescription)"
            }
        }
        return nil
    }

    /// When this section is next set to deploy on its own IN THIS WORKING
    /// FOLDER, or nil when nothing is scheduled there.
    ///
    /// Read back from the agents themselves rather than from a note of our
    /// own. The teacher can delete an agent from `~/Library/LaunchAgents`
    /// without telling us, and a badge promising a deploy that will never
    /// happen is worse than no badge at all.
    ///
    /// **Found by the folder scan, not by rebuilding the label** (#237): a
    /// job set before #237 has the old label and is shown all the same. When
    /// the folder somehow holds two jobs for the section — one set before the
    /// update, left by an older copy of the app still running — the EARLIER
    /// is the one shown, since that is the next thing that will happen.
    static func nextRun(
        courseCode: String,
        sectionNumber: Int,
        now: Date = Date(),
        inWorkingFolder workingFolderURL: URL
    ) -> Date? {
        var earliest: Date?
        for agent in agents(
            inWorkingFolder: workingFolderURL, courseCode: courseCode, sectionNumber: sectionNumber
        ) {
            // An agent whose moment has passed has either just fired and is
            // clearing itself away, or was left behind by a Mac that was off.
            // Either way it is not a promise worth showing.
            guard let moment = agent.scheduledFor, moment > now else {
                continue
            }
            if let soonestSoFar = earliest, soonestSoFar <= moment {
                continue
            }
            earliest = moment
        }
        return earliest
    }

    /// When the deploy this section has in THIS working folder is set for, or
    /// nil when there is none or its moment has gone by. The reading behind
    /// both `momentBeingReplaced` (which then leaves out the same minute, for
    /// what a teacher is TOLD) and the record of a replacement that failed
    /// (which must not: a same-minute job lost is still lost).
    ///
    /// **Folder-scoped since #237, reversing #195's "read Mac-wide, on
    /// purpose".** That reading existed because scheduling overwrote the one
    /// job the section had on the whole Mac, whichever folder set it; now it
    /// cannot, so a Mac-wide reading would name, on this folder's card, a
    /// deploy this folder's scheduling no longer touches.
    ///
    /// Under the test suite this reads ONLY a folder a test chose. The card
    /// reads this whenever a scheduled deploy is proposed, and tests that put
    /// one up without moving the agents folder would otherwise read the real
    /// `~/Library/LaunchAgents` of whoever runs the suite — the #240 fault
    /// arriving through a new door. (Since #240 `launchAgentsDirectoryURL()`
    /// itself answers an empty throwaway folder under the suite, so this is
    /// the second of two guards; it stays because it also keeps a plist some
    /// other test left in that shared throwaway folder from being read.)
    static func momentAlreadySet(
        courseCode: String,
        sectionNumber: Int,
        inWorkingFolder workingFolderURL: URL,
        now: Date = Date()
    ) -> Date? {
        if WorkspaceModel.isRunningTests && launchAgentsDirectoryOverride == nil {
            return nil
        }
        return nextRun(
            courseCode: courseCode,
            sectionNumber: sectionNumber,
            now: now,
            inWorkingFolder: workingFolderURL
        )
    }

    /// When the deploy that scheduling this section for `when` in this working
    /// folder would REPLACE is set for — or nil when there is none, or when it
    /// is set for that same minute and so replaces nothing a teacher would
    /// notice (issue #195).
    ///
    /// **Scoped to the working folder since #237.** It used to be read
    /// Mac-wide on purpose, because `scheduleDeploy` overwrote the one job a
    /// section had on the whole Mac; now another folder's job of the same
    /// section is a different alarm that scheduling here leaves standing, so
    /// saying it is "replaced" would be false. A moment already past is nil
    /// here as it is in `nextRun`.
    static func momentBeingReplaced(
        courseCode: String,
        sectionNumber: Int,
        by when: Date,
        inWorkingFolder workingFolderURL: URL,
        now: Date = Date(),
        calendar: Calendar = Calendar.current
    ) -> Date? {
        guard let existing = momentAlreadySet(
            courseCode: courseCode, sectionNumber: sectionNumber,
            inWorkingFolder: workingFolderURL, now: now
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
    /// is easy to leave out.** Until #237 a label was the course code and the
    /// section number and nothing else, so one file per code and section
    /// stood for the whole Mac, and asking "does this course have a scheduled
    /// deploy?" by looking for a file answered yes in the folder that did not
    /// own it. Since #237 a new label carries the folder's id — but a job set
    /// before the update still has the old one, and the id is a way of keeping
    /// two folders' files apart, never how a folder's jobs are FOUND. This
    /// scan is how they are found, by every reader: the clock, the card, the
    /// cancel, a removal, a rename, the sweep.
    ///
    /// Nothing is asked of launchd and nothing outside `labelPrefix` is read —
    /// the prefix exists for exactly this reason.
    nonisolated static func agents(inWorkingFolder workingFolderURL: URL) -> [Agent] {
        return agents(inWorkingFolder: workingFolderURL, courseCode: nil, sectionNumber: nil)
    }

    /// The same, for one course — and, given one, one section.
    ///
    /// A file whose NAME names another course or section is passed over
    /// without being opened (both codes sanitised, since a pre-v1.2.0 plist's
    /// code comes back only from its label), so the sidebar's clock reads the
    /// one or two plists that can be this section's rather than every one.
    nonisolated static func agents(
        inWorkingFolder workingFolderURL: URL,
        courseCode: String?,
        sectionNumber: Int?
    ) -> [Agent] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: launchAgentsDirectoryURL(),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var wantedCode: String?
        if let courseCode {
            wantedCode = sanitizedCode(courseCode)
        }
        let wanted: String = physicalPath(workingFolderURL.path)

        var found: [Agent] = []
        for entry in entries {
            let name: String = entry.lastPathComponent
            if !name.hasPrefix(labelPrefix) || !name.hasSuffix(".plist") {
                continue
            }
            if wantedCode != nil || sectionNumber != nil {
                let labelFromName: String = String(name.dropLast(".plist".count))
                guard let named = codeAndSection(fromLabel: labelFromName) else {
                    continue
                }
                if let wantedCode, sanitizedCode(named.courseCode) != wantedCode {
                    continue
                }
                if let sectionNumber, named.sectionNumber != sectionNumber {
                    continue
                }
            }
            // Named in the agents folder's own spelling, the one every other
            // path here is built from, rather than the listing's (which can
            // come back with `/private` added).
            guard let agent = agent(readingPlistAt: launchAgentsDirectoryURL().appendingPathComponent(name)) else {
                continue
            }
            if physicalPath(agent.workingFolderPath) != wanted {
                continue
            }
            found.append(agent)
        }
        found.sort { first, second in
            if first.courseCode == second.courseCode {
                if first.sectionNumber == second.sectionNumber {
                    return first.label < second.label
                }
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
    ///
    /// Reads both spellings: `…<CODE>.section<N>` (before #237) and
    /// `…<CODE>.section<N>.<folder id>`, whose id is taken off first.
    nonisolated static func codeAndSection(fromLabel label: String) -> (courseCode: String, sectionNumber: Int)? {
        guard label.hasPrefix(labelPrefix + ".") else {
            return nil
        }
        var remainder: String = String(label.dropFirst(labelPrefix.count + 1))
        if let idAtTheEnd = folderID(fromLabel: label) {
            remainder = String(remainder.dropLast(idAtTheEnd.count + 1))
        }
        guard let separator = remainder.range(of: ".section", options: .backwards) else {
            return nil
        }
        let code: String = String(remainder[remainder.startIndex..<separator.lowerBound])
        guard let sectionNumber = Int(remainder[separator.upperBound...]), !code.isEmpty else {
            return nil
        }
        return (courseCode: code, sectionNumber: sectionNumber)
    }

    /// A path in the disk's own spelling — `FolderIdentity.canonicalPath`,
    /// the one answer the container naming and every other folder comparison
    /// use (#189).
    ///
    /// Not Foundation's `resolvingSymlinksInPath()`, which strips the
    /// `/private` prefix from `/var` and `/tmp` paths and folds neither case
    /// nor Unicode form. Two spellings of one folder comparing as DIFFERENT
    /// would quietly scope every job out, and nothing would be cancelled or
    /// shown at all.
    ///
    /// A path that does not exist comes back as it went in, so a working
    /// folder on an unmounted volume compares by its plain text rather than
    /// matching nothing.
    nonisolated static func physicalPath(_ path: String) -> String {
        return FolderIdentity.canonicalPath(path)
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
    /// nothing (issue #195). Read in the working folder the deploy would be
    /// set from (Mac-wide until #237) — see `ScheduledDeploy.momentBeingReplaced`.
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

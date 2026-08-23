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
    /// `StartCalendarInterval` has no year — it repeats annually — so the
    /// plist alone cannot say which day it meant. launchd passes
    /// `EnvironmentVariables` through untouched, so the full moment rides
    /// there: it is what the sidebar reads back, and it also lands in the
    /// agent's own log.
    static let scheduledForKey: String = "PLANTOIR_SCHEDULED_FOR"

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

    /// Where this section's one-shot script is written.
    ///
    /// A file rather than a line inside the plist, because launchd no longer
    /// runs it directly — see `agentPlist` for why. The app runs this file.
    static func scriptURL(courseCode: String, sectionNumber: Int) -> URL {
        let label: String = agentLabel(courseCode: courseCode, sectionNumber: sectionNumber)
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Plantoir")
            .appendingPathComponent("scheduled")
            .appendingPathComponent("\(label).sh")
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
    nonisolated static func successSentinelURL(courseCode: String, sectionNumber: Int) -> URL {
        let label: String = agentLabel(courseCode: courseCode, sectionNumber: sectionNumber)
        return FileManager.default.homeDirectoryForCurrentUser
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
    static func plistURL(courseCode: String, sectionNumber: Int) -> URL {
        let label: String = agentLabel(courseCode: courseCode, sectionNumber: sectionNumber)
        return launchAgentsDirectoryURL().appendingPathComponent("\(label).plist")
    }

    /// A folder to write agents into instead of the teacher's own.
    ///
    /// Set only by tests. A test that wrote into the real `LaunchAgents`
    /// folder would leave a deploy scheduled on the machine running the
    /// suite — which is exactly the kind of surprise this feature exists
    /// to make deliberate.
    static var launchAgentsDirectoryOverride: URL?

    static func launchAgentsDirectoryURL() -> URL {
        if let launchAgentsDirectoryOverride {
            return launchAgentsDirectoryOverride
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
    }

    /// Where the agent's own output goes. A deploy that ran at half six
    /// with nobody watching has to have left something behind, or a
    /// failure is invisible until a student says the site is stale.
    nonisolated static func logURL(courseCode: String, sectionNumber: Int) -> URL {
        let label: String = agentLabel(courseCode: courseCode, sectionNumber: sectionNumber)
        return FileManager.default.homeDirectoryForCurrentUser
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
                forSection: sectionNumber,
                isSectionLocal: true
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
        calendar: Calendar = Calendar.current
    ) -> [String: Any] {
        let label: String = agentLabel(courseCode: courseCode, sectionNumber: sectionNumber)
        let components: DateComponents = calendar.dateComponents([.month, .day, .hour, .minute], from: when)

        var schedule: [String: Any] = [:]
        schedule["Month"] = components.month ?? 1
        schedule["Day"] = components.day ?? 1
        schedule["Hour"] = components.hour ?? 0
        schedule["Minute"] = components.minute ?? 0

        var environment: [String: String] = [:]
        // A launchd agent starts with a bare PATH; the launcher needs to
        // find docker and colima the way a Terminal session does. Same
        // list ScriptRunner prepends when the app runs a script itself.
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
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
    static func oneShotCommand(
        courseCode: String,
        sectionNumber: Int,
        workspaceURL: URL,
        deployArgumentsList: [[String]],
        destinationTypes: [String] = []
    ) -> String {
        let label: String = agentLabel(courseCode: courseCode, sectionNumber: sectionNumber)
        let plistPath: String = plistURL(courseCode: courseCode, sectionNumber: sectionNumber).path
        let scriptPath: String = workspaceURL.appendingPathComponent(DeployCommand.scriptName).path
        let logDirectory: String = logURL(courseCode: courseCode, sectionNumber: sectionNumber)
            .deletingLastPathComponent().path

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

        let buildLine: String = "/bin/bash \(shellQuoted(previewPath)) "
            + "\(shellQuoted(courseCode)) \(shellQuoted(String(sectionNumber))) --build-only"

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
        lines.append("READY=1")
        lines.append("if [ \"$NEEDS_BUILD\" = \"1\" ]; then")
        lines.append("  if ! \(buildLine); then READY=0; fi")
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
            courseCode: courseCode, sectionNumber: sectionNumber
        ).path
        lines.append("/bin/rm -f \(shellQuoted(sentinelPath))")
        lines.append("ALL_OK=\"$READY\"")
        lines.append("if [ \"$READY\" = \"1\" ]; then")
        for deployLine in deployLines {
            lines.append("  if ! \(deployLine); then ALL_OK=0; fi")
        }
        lines.append("fi")
        // The sentinel carries WHERE it went, so the record a scheduled
        // publish leaves is the same shape as the button's.
        lines.append(
            "if [ \"$ALL_OK\" = \"1\" ]; then /bin/echo "
            + shellQuoted(destinationTypes.joined(separator: " "))
            + " > \(shellQuoted(sentinelPath)); fi"
        )
        // Cleanup runs either way: a failed build must still leave nothing
        // pending, or the agent fires again at the same time tomorrow.
        lines.append("/bin/launchctl bootout gui/$(/usr/bin/id -u)/\(shellQuoted(label))")
        return lines.joined(separator: "\n")
    }

    /// One argument, safe to paste into a shell command.
    static func shellQuoted(_ value: String) -> String {
        let escaped: String = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
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
        let scriptURL: URL = workspaceURL.appendingPathComponent(DeployCommand.scriptName)
        if !FileManager.default.fileExists(atPath: scriptURL.path) {
            return "This working folder is missing a piece it needs (\(DeployCommand.scriptName)), so there is nothing to schedule."
        }

        // One argument list per configured destination — the same order
        // `CourseConfiguration.allDeployDestinations` deploys in: the
        // primary first, then each additional destination.
        var deployArgumentsList: [[String]] = []
        for destination in course.configuration.allDeployDestinations {
            deployArgumentsList.append(DeployCommand.arguments(
                courseCode: course.code,
                sectionNumber: sectionNumber,
                destination: destination,
                cloudflareAccountID: cloudflareAccountID
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
                destinationTypes: scheduledDestinationTypes(course: course)
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
            return "The scheduled deploy could not be written: \(error.localizedDescription)"
        }

        if let failure = runner.bootstrap(plistURL: destinationURL) {
            try? FileManager.default.removeItem(at: destinationURL)
            return "macOS would not accept the scheduled deploy: \(failure)"
        }
        return nil
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
        section: (courseDirectory: URL, courseCode: String, sectionNumber: Int)? = nil
    ) -> Never {
        // Taken BEFORE anything runs, for the same reason the Deploy
        // button takes it before its own build: a page edited while an
        // overnight publish is running did not go out, and stamping the
        // finishing state would mark it published.
        var fingerprintBeforeRunning: String?
        if let section {
            fingerprintBeforeRunning = SectionPublishState.fingerprint(
                courseDirectory: section.courseDirectory,
                sectionNumber: section.sectionNumber
            )
        }

        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script]
        do {
            try process.run()
            process.waitUntilExit()
            recordScheduledPublish(section: section, fingerprint: fingerprintBeforeRunning)
            // Publishes regardless; the findings are kept for somebody to read
            // when they are next at the machine.
            recordFolderProblems(section: section)
            exit(process.terminationStatus)
        } catch {
            FileHandle.standardError.write(Data(
                "Plantoir could not run the scheduled deploy: \(error.localizedDescription)\n".utf8
            ))
            exit(1)
        }
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
    nonisolated static func findingsSentinelURL(courseCode: String, sectionNumber: Int) -> URL {
        let label: String = agentLabel(courseCode: courseCode, sectionNumber: sectionNumber)
        return FileManager.default.homeDirectoryForCurrentUser
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
        section: (courseDirectory: URL, courseCode: String, sectionNumber: Int)?
    ) {
        guard let section else {
            return
        }
        let log: URL = logURL(
            courseCode: section.courseCode, sectionNumber: section.sectionNumber
        )
        guard let text = try? String(contentsOf: log, encoding: .utf8) else {
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
            courseCode: section.courseCode, sectionNumber: section.sectionNumber
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

    /// What the last scheduled run found, if anything, consuming the record so
    /// it is reported once rather than every time the app opens.
    nonisolated static func takeFolderProblems(
        courseCode: String, sectionNumber: Int
    ) -> [SiteHealthFinding] {
        let sentinel: URL = findingsSentinelURL(
            courseCode: courseCode, sectionNumber: sectionNumber
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
        fingerprint: String?
    ) {
        guard let section, let fingerprint else {
            return
        }
        let sentinel: URL = successSentinelURL(
            courseCode: section.courseCode, sectionNumber: section.sectionNumber
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
    @discardableResult
    static func cancelScheduledDeploy(
        courseCode: String,
        sectionNumber: Int,
        runner: LaunchControlRunning = LaunchControl()
    ) -> String? {
        let destinationURL: URL = plistURL(courseCode: courseCode, sectionNumber: sectionNumber)
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
    static func nextRun(courseCode: String, sectionNumber: Int, now: Date = Date()) -> Date? {
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
        locale: Locale = Locale.current
    ) {
        self.courseCode = courseCode
        self.sectionNumber = sectionNumber
        self.when = when
        self.destination = destination
        self.unpublishedClasses = unpublishedClasses
        self.problem = problem
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

    /// Runs launchctl and collects what it said.
    static func run(arguments: [String]) -> (exitCode: Int32, output: String) {
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

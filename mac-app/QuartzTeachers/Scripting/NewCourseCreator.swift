import Foundation
import Observation

/// Creates a new course by driving the real setup wizard.
///
/// The app writes the teacher's chosen settings to
/// `courses/<CODE>/course_config.json` first, then runs `./setup.sh`. The
/// wizard treats that file as its saved answers and offers each one as a
/// default, so this type simply watches the output and "presses Return" at
/// every prompt (typing the course code at the one prompt that needs it).
/// All folder scaffolding, backups, and Quartz patching happen inside the
/// real script — the app adds no logic of its own.
@Observable
class NewCourseCreator {

    // MARK: - Stored properties

    let runner: ScriptRunner = ScriptRunner()

    /// True from start until setup.sh finishes.
    var isCreating: Bool = false

    /// A problem preparing the run (before the script started), if any.
    var preparationProblem: String?

    /// The code of the example course that was installed, once it has been.
    /// The example is normally EXC2O, but installs under another code when
    /// that one is taken — so the app has to be told which it got.
    var installedExampleCode: String?

    /// The course code being created, uppercased.
    private var courseCode: String = ""

    /// How much of the transcript the pump has already responded to.
    private var respondedLength: Int = 0

    /// Safety valve so a confused run cannot send input forever.
    private var responsesSent: Int = 0

    // MARK: - Functions

    /// Writes the config, then starts `setup.sh` and the answer pump.
    func createCourse(configuration: [String: Any], workspaceURL: URL) {
        preparationProblem = nil

        guard let storedCode = configuration["course_code"] as? String else {
            preparationProblem = "The course needs a code."
            return
        }
        courseCode = storedCode.uppercased()

        let courseDirectoryURL: URL = workspaceURL
            .appendingPathComponent("courses")
            .appendingPathComponent(courseCode)
        let configFileURL: URL = courseDirectoryURL.appendingPathComponent("course_config.json")

        do {
            try FileManager.default.createDirectory(at: courseDirectoryURL, withIntermediateDirectories: true)
            let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            var data: Data = try JSONSerialization.data(withJSONObject: configuration, options: options)
            data.append(contentsOf: [0x0A])
            try data.write(to: configFileURL, options: [.atomic])
        } catch {
            preparationProblem = "Could not write the course configuration: \(error.localizedDescription)"
            return
        }

        ActivityTrail.note(
            .courseCreated,
            NewCourseCreator.startingContentLine(
                courseCode: courseCode,
                takesExampleContent: configuration["prepopulate_example_content"] as? Bool ?? false,
                usesSkeleton: configuration["use_skeleton"] as? Bool ?? false,
                skeletonSubject: NewCourseCreator.skeletonSubject(forCode: courseCode),
                withCurriculumPages: configuration["include_curriculum_pages"] as? Bool ?? false
            )
        )

        respondedLength = 0
        responsesSent = 0
        isCreating = true
        runner.milestones = TaskMilestones.courseCreation
        runner.run(scriptNamed: "setup.sh", arguments: [], workingDirectory: workspaceURL)

        Task {
            await pumpAnswers()
        }
    }

    /// Installs the example course. Nothing is asked of the teacher: the
    /// setup script is run with the flag that installs it outright.
    func installExampleCourse(workspaceURL: URL) {
        preparationProblem = nil
        installedExampleCode = nil
        respondedLength = 0
        responsesSent = 0
        isCreating = true
        runner.milestones = TaskMilestones.exampleCourse
        runner.run(
            scriptNamed: "setup.sh",
            arguments: ["--", "--install-example"],
            workingDirectory: workspaceURL
        )

        Task {
            await runner.waitUntilFinished()
            installedExampleCode = NewCourseCreator.exampleCourseCode(in: runner.transcript.displayText)
            // The same line a course made through the wizard leaves, because
            // this button makes a course too — one a teacher will later ask
            // about by name. It is written AFTER the run and from the run's
            // own output, never before and never guessed: the example
            // normally installs as EXC2O but takes another code when that one
            // is taken, so the code is not known until the script says it. A
            // run that installed nothing says nothing, which is why this sits
            // inside the `if let`.
            if let installedCode = installedExampleCode {
                ActivityTrail.note(
                    .courseCreated,
                    NewCourseCreator.startingContentLine(
                        courseCode: installedCode,
                        takesExampleContent: true,
                        usesSkeleton: false,
                        skeletonSubject: nil
                    )
                )
            }
            isCreating = false
        }
    }

    /// The line the trail keeps for a new course: the code, and which of
    /// the three starting points it began from.
    ///
    /// Written as a sentence a teacher would recognise rather than as the
    /// three config keys it is read from — "created ICS4U from the computer
    /// studies skeleton", never "use_skeleton=true". Pure, so it can be
    /// tested without creating a course; the flags come straight out of
    /// the configuration the wizard just wrote, so the line says what was
    /// actually asked for rather than what the interface last showed.
    ///
    /// A skeleton course now has two outcomes that differ by fifty-nine
    /// pages and by whether the curriculum coverage map works at all
    /// (GitHub issue #251), so `withCurriculumPages` tells them apart. The
    /// report this line exists to answer is "my new course came out
    /// wrong"; one that could not say which of the two happened could not
    /// answer it. The example-content sentence is untouched — those pages
    /// have always carried their own curriculum.
    static func startingContentLine(courseCode: String,
                                    takesExampleContent: Bool,
                                    usesSkeleton: Bool,
                                    skeletonSubject: String?,
                                    withCurriculumPages: Bool = false) -> String {
        if takesExampleContent {
            return "created \(courseCode) from the ready-made pages written for it"
        }
        if usesSkeleton {
            var line: String
            if let skeletonSubject, !skeletonSubject.isEmpty {
                line = "created \(courseCode) from the \(skeletonSubject.lowercased()) skeleton"
            } else {
                line = "created \(courseCode) from the general course skeleton"
            }
            if withCurriculumPages {
                line += " with the \(courseCode) curriculum pages"
            }
            return line
        }
        return "created \(courseCode) with empty folders"
    }

    /// The subject a code's skeleton is shaped for, or nil for the general
    /// family — which has no subject to name.
    static func skeletonSubject(forCode code: String) -> String? {
        guard let family = SkeletonCatalog.family(forCode: code) else {
            return nil
        }
        if family.name == SkeletonCatalog.generalFamilyName {
            return nil
        }
        return family.label
    }

    /// Reads the installed example's code out of the output.
    static func exampleCourseCode(in output: String) -> String? {
        let marker: String = "EXAMPLE_COURSE_CODE="
        var found: String?
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line: String = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard let markerRange = line.range(of: marker) else {
                continue
            }
            let code: String = String(line[markerRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !code.isEmpty {
                found = code
            }
        }
        return found
    }

    /// Watches the wizard's output; whenever a prompt is waiting, answers
    /// it — the course code at the code prompt, Return everywhere else.
    private func pumpAnswers() async {
        while runner.isRunning {
            try? await Task.sleep(for: .milliseconds(400))

            if responsesSent > 300 {
                // Something is looping; stop feeding it.
                runner.terminate()
                break
            }

            let displayText: String = runner.transcript.displayText
            if displayText.count == respondedLength {
                // No new output since our last response; the script is
                // either busy working or waiting at a prompt we already
                // answered. Only answer when NEW output ends in a prompt.
                continue
            }

            let lastLine: String = currentPromptLine(in: displayText)
            if !looksLikePrompt(lastLine) {
                continue
            }

            respondedLength = displayText.count
            responsesSent += 1

            if lastLine.contains("Enter the course code") {
                runner.send(line: courseCode)
            } else {
                runner.send(line: "")
            }
        }
        isCreating = false
    }

    /// The last non-empty line of output — the prompt currently waiting.
    private func currentPromptLine(in text: String) -> String {
        let lines: [Substring] = text.split(separator: "\n", omittingEmptySubsequences: false)
        var index: Int = lines.count - 1
        while index >= 0 {
            let line: String = String(lines[index]).trimmingCharacters(in: .whitespaces)
            if !line.isEmpty {
                return line
            }
            index -= 1
        }
        return ""
    }

    /// Heuristics for "the wizard is waiting for input on this line" —
    /// matched to the actual prompt shapes in setup_course.py.
    private func looksLikePrompt(_ line: String) -> Bool {
        if line.hasSuffix(":") {
            return true
        }
        if line.hasSuffix(": ") {
            return true
        }
        if line == ">" {
            return true
        }
        if line.hasPrefix("Use ← / →") {
            // The colour scheme picker: Return accepts the saved default.
            return true
        }
        if line.hasSuffix("?") {
            return true
        }
        return false
    }
}

import SwiftUI

/// The sheet that renames a course's word for a unit after the course is in
/// use — the half of `unit_word` that waited for an undo.
///
/// It reads like the folder rename sheet next to it and behaves the same
/// way: it commits to disk straight away and says so. What it adds is the
/// plan — how many pages, in which sections, how many links — shown BEFORE
/// the teacher agrees, because this renames pages their links point at.
/// The survey is made when the sheet opens and again after a failure, from
/// the course's CURRENT word alone: it is a preview made before a word has
/// been typed, so when a stopped rename is being finished it counts the
/// pages still to move rather than the links the plan will also follow.
/// What depends on the word — a page already sitting where a renamed page
/// would go — is checked when Rename is pressed.
///
/// The walks leave the main actor (`Task.detached`), for the reason the
/// folder rename gives: reading every page in an iCloud-backed vault
/// downloads the evicted ones, one network round trip per page. The backup
/// and the configuration write stay on the main actor, and the sheet cannot
/// be dismissed while the work is under way, so a failure always has a view
/// to land on.
struct UnitWordRenameSheet: View {

    // MARK: - Stored properties

    let course: Course

    /// Told the sentence to show once the sheet has closed on a success.
    let onRenamed: (String) -> Void

    @Environment(\.dismiss) var dismiss

    @State var proposedWord: String = ""
    @State var survey: UnitWordSurvey? = nil
    @State var interruptedTarget: String? = nil
    @State var failure: String? = nil
    @State var isRenaming: Bool = false

    // MARK: - Computed properties

    var currentWord: String {
        return course.configuration.unitWord
    }

    /// The live objection under the field, or nil when the word is usable.
    var problem: String? {
        return UnitWordRenamer.problem(
            renaming: currentWord, to: proposedWord, interruptedTarget: interruptedTarget
        )
    }

    var coursesDirectoryURL: URL {
        return course.directoryURL.deletingLastPathComponent()
    }

    /// The working folder, which is how the preview and deploy leases name
    /// the folder they are busy in.
    var workingFolderPath: String {
        return coursesDirectoryURL.deletingLastPathComponent().path
    }

    /// The proposal in the word typed so far, so "Unit 1, Day 1 becomes
    /// Module 1, Day 1" follows the field.
    var previewLines: [String] {
        guard let survey else {
            return []
        }
        let typed: String = ClassPageTerm.cleaned(proposedWord)
        var lines: [String] = [
            UnitWordRenameWording.previewPages(
                courseCode: course.code, pages: survey.pages,
                sections: survey.sections, old: currentWord, new: typed
            ),
        ]
        if survey.pages > 0 {
            lines.append(UnitWordRenameWording.previewLinks(count: survey.links))
        }
        return lines
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(UnitWordRenameWording.sheetTitle(for: currentWord))
                .font(.headline)

            if let interruptedTarget {
                Text(UnitWordRenameWording.interruptedRename(from: currentWord, to: interruptedTarget))
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("unitWordInterrupted")
            }

            LabeledContent(UnitWordRenameWording.fieldLabel) {
                TextField(ClassPageTerm.standard, text: $proposedWord, prompt: Text(ClassPageTerm.standard))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("unitWordRenameField")
                    .disabled(isRenaming)
                    .onChange(of: proposedWord) {
                        // A failure is about the word it was tried with; a
                        // new word gets the live objection instead.
                        failure = nil
                    }
                    .onSubmit {
                        Task { await performRename() }
                    }
            }

            if survey != nil {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(previewLines, id: \.self) { line in
                        Text(line)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("unitWordPreview")
            } else {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(UnitWordRenameWording.lookingOver)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Text(UnitWordRenameWording.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(UnitWordRenameWording.proseIsLeftAlone)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let sentence = failure ?? problem {
                Text(sentence)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("unitWordRenameProblem")
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isRenaming)
                if isRenaming {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                }
                Button("Rename") {
                    Task { await performRename() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(problem != nil || survey == nil || isRenaming)
                .accessibilityIdentifier("unitWordRenameButton")
            }
        }
        .padding(20)
        .frame(width: 460)
        .interactiveDismissDisabled(isRenaming)
        .task {
            await lookOverTheCourse()
        }
    }

    // MARK: - Functions

    /// Fills the field and makes the survey — off the main actor, because it
    /// reads every page in the course. Run when the sheet opens, and AGAIN
    /// after a rename fails part way, so the sheet's own rules about a
    /// stopped rename apply to its own failure: without that, a teacher
    /// could retry with a different word and leave three words in one course.
    func lookOverTheCourse() async {
        if proposedWord.isEmpty {
            proposedWord = currentWord
        }
        let facts: UnitWordRenameCourseFacts = UnitWordRenamer.facts(for: course)
        let interrupted: String? = await Task.detached(priority: .userInitiated) {
            return UnitWordRenamer.interruptedRenameTarget(facts: facts)
        }.value
        interruptedTarget = interrupted
        if let interrupted {
            proposedWord = interrupted
        }
        survey = await Task.detached(priority: .userInitiated) {
            return UnitWordRenamer.survey(facts: facts)
        }.value
    }

    func performRename() async {
        if problem != nil || survey == nil || isRenaming {
            return
        }
        failure = nil
        if CourseActivity.courseIsBusy(folderPath: workingFolderPath, courseCode: course.code) {
            failure = UnitWordRenameWording.problemBusy(courseCode: course.code)
            return
        }
        isRenaming = true
        defer { isRenaming = false }

        let oldWord: String = currentWord
        let newWord: String = ClassPageTerm.cleaned(proposedWord)
        let facts: UnitWordRenameCourseFacts = UnitWordRenamer.facts(for: course)

        // 1. Planned again with the real word — the survey on screen was made
        //    when the sheet opened, and Obsidian may be open — and every page
        //    read, both off the main actor. Nothing has changed yet.
        let planned: Result<(UnitWordRenamePlan, [String]), Error> = await Task.detached(priority: .userInitiated) {
            let freshPlan: UnitWordRenamePlan = UnitWordRenamer.plan(from: oldWord, to: newWord, facts: facts)
            if let refusal = freshPlan.problems.first {
                return .failure(UnitWordRenameProblem(
                    sentence: refusal, pagesRenamed: 0, linksRewritten: 0, changedTheCourse: false
                ))
            }
            do {
                return .success((freshPlan, try UnitWordRenamer.readEveryPage(of: freshPlan)))
            } catch {
                return .failure(error)
            }
        }.value
        let freshPlan: UnitWordRenamePlan
        let texts: [String]
        switch planned {
        case .success(let pair):
            freshPlan = pair.0
            texts = pair.1
        case .failure(let error):
            failure = error.localizedDescription
            return
        }

        // 2. The way back, on the main actor: the archiver is.
        let backupURL: URL
        do {
            backupURL = try CourseArchiver.backUpCourse(course, coursesDirectoryURL: coursesDirectoryURL)
        } catch {
            failure = error.localizedDescription
            return
        }

        // 3. The work, off the main actor.
        let carried: Result<UnitWordRenameOutcome, Error> = await Task.detached(priority: .userInitiated) {
            do {
                return .success(try UnitWordRenamer.carryOut(
                    freshPlan, texts: texts, facts: facts, backupURL: backupURL
                ))
            } catch {
                return .failure(error)
            }
        }.value
        let outcome: UnitWordRenameOutcome
        switch carried {
        case .success(let done):
            outcome = done
        case .failure(let error):
            let sentence: String = error.localizedDescription
            // A rename that touched the course and stopped is the one outcome
            // the trail exists for: from here the course has two words in it.
            // Owed whenever anything on disk changed, which is not the same as
            // whether a page was counted — the first page can be retitled and
            // then fail to move.
            var changedTheCourse: Bool = false
            var renamedSoFar: Int = 0
            if let problem = error as? UnitWordRenameProblem {
                changedTheCourse = problem.changedTheCourse
                renamedSoFar = problem.pagesRenamed
            }
            if changedTheCourse {
                ActivityTrail.note(
                    .unitWordRenamed,
                    "started renaming the word for a unit in " + course.code + " from " + oldWord
                    + " to " + newWord + " and stopped after " + String(renamedSoFar)
                    + " class pages (backup " + backupURL.lastPathComponent + ") — " + sentence
                )
            }
            failure = sentence
            // The course may now be part way through a rename; look again so
            // the field is held to that rename's word.
            survey = nil
            await lookOverTheCourse()
            failure = sentence
            return
        }

        // 4. The settings, on the main actor: the model is observable.
        do {
            try UnitWordRenamer.record(freshPlan, in: course)
        } catch {
            ActivityTrail.note(
                .unitWordRenamed,
                "renamed the word for a unit in " + course.code + " from " + oldWord + " to " + newWord
                + " (" + String(outcome.pagesRenamed) + " class pages, " + String(outcome.linksRewritten)
                + " links, backup " + outcome.backupURL.lastPathComponent
                + ") but could not write it to this course's settings — " + error.localizedDescription
            )
            failure = error.localizedDescription
            survey = nil
            await lookOverTheCourse()
            failure = error.localizedDescription
            return
        }

        var line: String = "renamed the word for a unit in " + course.code + " from " + oldWord + " to " + newWord
            + " (" + String(outcome.pagesRenamed) + " class pages renamed, "
            + String(outcome.linksRewritten) + " links updated, backup "
            + outcome.backupURL.lastPathComponent + ")"
        if outcome.pagesNotWritten > 0 {
            line += " — " + String(outcome.pagesNotWritten) + " pages could not be written, so their links still use the old names"
        }
        ActivityTrail.note(.unitWordRenamed, line)
        let sentence: String = UnitWordRenameWording.doneSentence(
            from: oldWord, to: newWord, pages: outcome.pagesRenamed,
            links: outcome.linksRewritten, pagesNotWritten: outcome.pagesNotWritten
        )
        dismiss()
        onRenamed(sentence)
    }
}

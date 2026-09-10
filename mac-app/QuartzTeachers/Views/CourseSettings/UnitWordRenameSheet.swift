import SwiftUI

/// The sheet that renames a course's word for a unit after the course is in
/// use — the half of `unit_word` that waited for an undo.
///
/// It reads like the folder rename sheet next to it and behaves the same
/// way: it commits to disk straight away and says so. What it adds is the
/// plan — how many pages, in which sections, how many links — shown BEFORE
/// the teacher agrees, because this renames pages their links point at.
/// The plan is worked out once, when the sheet opens; the counts do not
/// depend on the word typed. What does depend on it — a page already sitting
/// where a renamed page would go — is checked when Rename is pressed.
struct UnitWordRenameSheet: View {

    // MARK: - Stored properties

    let course: Course

    /// Told the sentence to show once the sheet has closed on a success.
    let onRenamed: (String) -> Void

    @Environment(\.dismiss) var dismiss

    @State var proposedWord: String = ""
    @State var plan: UnitWordRenamePlan? = nil
    @State var interruptedTarget: String? = nil
    @State var failure: String? = nil
    @State var isRenaming: Bool = false

    // MARK: - Computed properties

    var currentWord: String {
        return course.configuration.unitWord
    }

    /// The live objection under the field, or nil when the word is usable.
    var problem: String? {
        // Finishing an interrupted rename types the same word the record
        // holds; that is not "unchanged", because the settings still say the
        // old one.
        if let interruptedTarget, proposedWord.trimmingCharacters(in: .whitespaces) == interruptedTarget {
            return nil
        }
        return UnitWordRenamer.problem(renaming: currentWord, to: proposedWord)
    }

    var coursesDirectoryURL: URL {
        return course.directoryURL.deletingLastPathComponent()
    }

    /// The working folder, which is how the preview and deploy leases name
    /// the folder they are busy in.
    var workingFolderPath: String {
        return coursesDirectoryURL.deletingLastPathComponent().path
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
                    .onSubmit {
                        Task { await performRename() }
                    }
            }

            if let plan {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(previewLines(for: plan), id: \.self) { line in
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
                    Text("Looking over the course’s pages…")
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
                if isRenaming {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                }
                Button("Rename") {
                    Task { await performRename() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(problem != nil || plan == nil || isRenaming)
                .accessibilityIdentifier("unitWordRenameButton")
            }
        }
        .padding(20)
        .frame(width: 460)
        .task {
            await lookOverTheCourse()
        }
    }

    // MARK: - Functions

    /// The preview in the word typed so far, so "Unit 1, Day 1 becomes
    /// Module 1, Day 1" follows the field.
    func previewLines(for plan: UnitWordRenamePlan) -> [String] {
        let typed: String = ClassPageTerm.cleaned(proposedWord)
        var lines: [String] = [
            UnitWordRenameWording.previewPages(
                courseCode: plan.courseCode, pages: plan.renames.count,
                sections: plan.sectionsTouched, old: plan.from, new: typed
            ),
        ]
        if !plan.renames.isEmpty {
            lines.append(UnitWordRenameWording.previewLinks(count: plan.linksToRewrite))
        }
        return lines
    }

    /// Fills the field and works out the plan. Yields to the run loop first
    /// so the sheet is on screen before the course's pages are read.
    func lookOverTheCourse() async {
        let interrupted: String? = UnitWordRenamer.interruptedRenameTarget(in: course)
        interruptedTarget = interrupted
        proposedWord = interrupted ?? currentWord
        await Task.yield()
        // Planned against the CURRENT word on both sides: the counts are the
        // same whatever is typed, and the destination check is redone on
        // Rename with the real word.
        plan = UnitWordRenamer.plan(from: currentWord, to: currentWord + " ", in: course)
    }

    func performRename() async {
        if problem != nil || isRenaming {
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
        // Let the spinner draw before the pages are read.
        await Task.yield()

        // Planned again with the real word — the plan on screen was made when
        // the sheet opened, and Obsidian may be open — then carried out.
        let freshPlan: UnitWordRenamePlan = UnitWordRenamer.plan(from: oldWord, to: newWord, in: course)
        let outcome: UnitWordRenameOutcome
        do {
            outcome = try UnitWordRenamer.rename(
                freshPlan, in: course, coursesDirectoryURL: coursesDirectoryURL
            )
        } catch {
            let sentence: String = error.localizedDescription
            var renamedSoFar: Int = 0
            if let problem = error as? UnitWordRenameProblem {
                renamedSoFar = problem.pagesRenamed
            }
            // A rename that moved pages and stopped is the one outcome the
            // trail exists for: from here the course has two words in it.
            if renamedSoFar > 0 {
                ActivityTrail.note(
                    .unitWordRenamed,
                    "started renaming the word for a unit in " + course.code + " from " + oldWord
                    + " to " + newWord + " and stopped after " + String(renamedSoFar)
                    + " class pages — " + sentence
                )
            }
            failure = sentence
            return
        }

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
            return
        }

        ActivityTrail.note(
            .unitWordRenamed,
            "renamed the word for a unit in " + course.code + " from " + oldWord + " to " + newWord
            + " (" + String(outcome.pagesRenamed) + " class pages renamed, "
            + String(outcome.linksRewritten) + " links updated, backup "
            + outcome.backupURL.lastPathComponent + ")"
        )
        let sentence: String = UnitWordRenameWording.doneSentence(
            from: oldWord, to: newWord, pages: outcome.pagesRenamed, links: outcome.linksRewritten
        )
        dismiss()
        onRenamed(sentence)
    }
}

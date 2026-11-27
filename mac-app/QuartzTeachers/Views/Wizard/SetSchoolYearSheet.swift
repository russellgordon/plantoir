import SwiftUI

/// Changing which school year a reference course is filed under.
///
/// **The one thing a frozen course still lets a teacher change**, and it is
/// not a page: it is a label on the shelf. `course_config.json` is
/// deliberately outside the lock for exactly this and for the build's own
/// bookkeeping.
///
/// The same uniqueness rule applies to the destination group — two ICS3Us
/// under one year is the row a teacher cannot read — so moving one year into
/// another can be refused, with the same sentence it would have been refused
/// with at the moment the copy was made.
struct SetSchoolYearSheet: View {

    // MARK: - Stored properties

    let course: Course

    /// Called once the year has been written, so the sidebar can regroup.
    let onSet: () -> Void

    @Environment(\.dismiss) var dismiss
    @Environment(WorkspaceModel.self) var workspace

    @State var schoolYear: Int?
    @State var problem: String?

    /// A change that stopped part way and could not be finished at once:
    /// the alert offering to put it back (#899).
    @State var putBackOffer: SettingPutBackOffer?

    let today: CalendarDay

    // MARK: - Computed properties

    var offeredYears: [Int] {
        return SchoolYear.offeredStartingYears(on: today)
    }

    var entryProblem: String? {
        if let problem {
            return problem
        }
        // A course the teacher put in a group of their own stays in it
        // whatever its year (#572, third piece): the year changes what its
        // summary says, not where it sits, so no year group is asked.
        if case .made = workspace.referenceShelfPlace(of: course, on: today) {
            return nil
        }
        // `ignoring` this course's own folder: moving a course into the year
        // it is already in must not find the course itself sitting there.
        if let trouble = ReferenceCourseRule.trouble(
            placing: course.displayCode,
            inYear: schoolYear,
            among: workspace.shelvedReferenceCourses(on: today),
            ignoring: course.code
        ) {
            return trouble.sentence
        }
        return nil
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("School year", selection: $schoolYear) {
                ForEach(offeredYears, id: \.self) { year in
                    Text(SchoolYear.label(forStartingYear: year)).tag(Int?.some(year))
                }
                // The no-year group under the name the shelf shows it by.
                Text(workspace.referenceShelf.arrangement.noYearTitle).tag(Int?.none)
            }
            .onChange(of: schoolYear) {
                problem = nil
            }

            if let entryProblem {
                StatusColour.blocking.sentence(entryProblem)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("setSchoolYearProblem")
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Set School Year") {
                    setSchoolYear()
                }
                .defaultButton(isEnabled: entryProblem == nil)
                .accessibilityIdentifier("setSchoolYearButton")
            }
        }
        .padding([.horizontal, .bottom], 20)
        .sheetTitle("Which school year was \(course.displayCode) taught in?")
        .frame(width: 420)
        .settingPutBackAlert(offer: $putBackOffer) { answer in
            answerTheOffer(answer)
        }
    }

    // MARK: - Initializer

    init(course: Course, today: CalendarDay = CalendarDay.today(), onSet: @escaping () -> Void) {
        self.course = course
        self.today = today
        self.onSet = onSet
        _schoolYear = State(initialValue: course.schoolYear(on: today))
    }

    // MARK: - Functions

    func setSchoolYear() {
        let before: Int? = course.schoolYear(on: today)
        switch SetSchoolYearSheet.writeJudged(schoolYear, to: course, on: today) {
        case .saved:
            dismiss()
            onSet()
        case .refused(let sentence):
            problem = sentence
        case .couldNotFinish(let seq):
            putBackOffer = SettingPutBackOffer(
                seq: seq,
                setting: "school year",
                valueBefore: yearLabel(before)
            )
        }
    }

    /// A year as the picker shows it, the no-year group by its title.
    func yearLabel(_ year: Int?) -> String {
        if let year {
            return SchoolYear.label(forStartingYear: year)
        }
        return workspace.referenceShelf.arrangement.noYearTitle
    }

    /// Put It Back, or Not Now (#899).
    func answerTheOffer(_ answer: SettingPutBackAnswer) {
        guard let offer = putBackOffer else {
            return
        }
        putBackOffer = nil
        switch answer {
        case .notNow:
            // Left in flight: recovery settles it at the next launch.
            break
        case .putItBack:
            if let refused = SetSchoolYearSheet.putBack(offer, course: course) {
                problem = refused
            }
        }
    }

    /// Put It Back for the school year: the old value written back through
    /// the door as recovery would, the step closed, the copy in memory
    /// read from the file again; the sentence for a save that failed when
    /// that fails too (`couldNotSetSchoolYear`, true there).
    static func putBack(_ offer: SettingPutBackOffer, course: Course) -> String? {
        let verdict: UndoPutBackVerdict = UndoStoppedStep.putBackAtOnce(
            seq: offer.seq, in: UndoJournalLocation.standardJournal()
        )
        try? course.configuration.reloadFromDisk(url: course.configFileURL)
        if verdict == .putBack {
            return nil
        }
        return ReferenceWording.couldNotSetSchoolYear(course: course.displayCode)
    }

    /// Writes the year to the course's settings and leaves the trail line,
    /// or answers the sentence the sheet shows when it could not be written
    /// (the year in memory then put back). ONE step on the list, its one
    /// `editJSON` the school year (#899 U4a).
    static func write(_ schoolYear: Int?, to course: Course, on today: CalendarDay) -> String? {
        switch writeJudged(schoolYear, to: course, on: today) {
        case .saved:
            return nil
        case .refused(let sentence):
            return sentence
        case .couldNotFinish:
            return ReferenceWording.settingCouldNotBeChanged(setting: "school year")
        }
    }

    /// `write`, with a change that stopped part way and could not be
    /// finished told apart (#899): a stop the door finished by content is
    /// `.saved`, one it put back is `.refused`, as any refused change is.
    static func writeJudged(_ schoolYear: Int?, to course: Course, on today: CalendarDay) -> SettingWriteResult {
        let before: Int? = course.schoolYear(on: today)
        course.configuration.referenceSchoolYear = schoolYear
        do {
            try course.configuration.writeAsOneStep(
                to: course.configFileURL, madeBy: UndoStepMaker.sheet("setSchoolYear")
            )
        } catch JournaledStepError.couldNotFinish(let seq, _) {
            course.configuration.referenceSchoolYear = before
            return .couldNotFinish(seq: seq)
        } catch {
            // Never the raw Foundation string. A teacher reads a sentence
            // about their course, not "NSCocoaErrorDomain Code=513".
            course.configuration.referenceSchoolYear = before
            return .refused(ReferenceWording.couldNotSetSchoolYear(course: course.displayCode))
        }
        ActivityTrail.note(
            .referenceCourseSchoolYearChanged,
            ReferenceWording.schoolYearTrailLine(
                course: course.displayCode, folderName: course.code,
                from: before, to: schoolYear
            )
        )
        return .saved
    }
}

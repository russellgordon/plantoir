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

    let today: CalendarDay

    // MARK: - Computed properties

    var offeredYears: [Int] {
        return SchoolYear.offeredStartingYears(on: today)
    }

    var entryProblem: String? {
        if let problem {
            return problem
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
            Text("Which school year was \(course.displayCode) taught in?")
                .font(.headline)

            Picker("School year", selection: $schoolYear) {
                ForEach(offeredYears, id: \.self) { year in
                    Text(SchoolYear.label(forStartingYear: year)).tag(Int?.some(year))
                }
                Text(SchoolYear.otherGroupName).tag(Int?.none)
            }
            .onChange(of: schoolYear) {
                problem = nil
            }

            if let entryProblem {
                Text(entryProblem)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("setSchoolYearProblem")
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Button("Set School Year") {
                    setSchoolYear()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(entryProblem != nil)
                .accessibilityIdentifier("setSchoolYearButton")
            }
        }
        .padding(20)
        .frame(width: 420)
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
        course.configuration.referenceSchoolYear = schoolYear
        do {
            try course.configuration.write(to: course.configFileURL)
            dismiss()
            onSet()
        } catch {
            problem = error.localizedDescription
        }
    }
}

import SwiftUI

/// What a teacher lands on when they click a reference course's row: a short
/// READ-ONLY summary, never the settings form.
///
/// **Why not the ordinary form.** It carries a "Deploying" section, and a
/// reference course is deliberately left with no deploy folder — so the form
/// said *"Choose the folder this course deploys into."* on a course the app
/// had just told the teacher is never deployed, and greyed Save for ever with
/// no explanation. Worse, Save WORKED for everything else: `course_config.json`
/// is never locked (the school year has to be changeable, and the build's own
/// preflight rewrites it), so a teacher could rename a frozen course, change
/// its graded folders, or quietly undo the neutralisation that makes an older
/// Plantoir refuse it. The contract's `frozen.rule` — "Plantoir itself offers
/// nothing that changes a page, a setting or the shape of the course" — was
/// false as shipped. This makes it true.
///
/// The one thing that still changes is the school year, and it changes through
/// its own action, which is what the contract says.
struct ReferenceCourseSummaryView: View {

    // MARK: - Stored properties

    let course: Course

    /// Opens the "Set School Year…" sheet. Held by the sidebar, which owns
    /// every sheet in this window.
    let setSchoolYear: () -> Void

    let today: CalendarDay

    // MARK: - Computed properties

    var schoolYearText: String {
        guard let startingYear = course.schoolYear(on: today) else {
            return SchoolYear.otherGroupName
        }
        return SchoolYear.label(forStartingYear: startingYear)
    }

    var sectionsText: String {
        var spelled: [String] = []
        for number in course.sectionNumbers {
            spelled.append(String(number))
        }
        if spelled.isEmpty {
            return "none"
        }
        return spelled.joined(separator: ", ")
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(course.displayCode)
                        .font(.largeTitle)
                    Text(course.configuration.courseName)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                // Facts, not fields. Nothing here is editable, and nothing
                // here is a control that can never become available.
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("School year").foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Text(schoolYearText)
                                .accessibilityIdentifier("referenceSchoolYear")
                            Button(ReferenceWording.setSchoolYearMenuItem) {
                                setSchoolYear()
                            }
                            .buttonStyle(.link)
                            .accessibilityIdentifier("referenceSetSchoolYear")
                        }
                    }
                    GridRow {
                        Text("Sections").foregroundStyle(.secondary)
                        Text(sectionsText)
                    }
                    GridRow {
                        Text("Folder").foregroundStyle(.secondary)
                        // The one place the folder name IS the fact.
                        Text(course.code)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("referenceFolderName")
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(ReferenceWording.neverDeployed(course: course.displayCode))
                    Text(ReferenceWording.pagesAreLocked)
                    Text(ReferenceWording.aCopyTakenOutStaysLocked)
                }
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(course.displayCode)
    }

    // MARK: - Initializer

    init(course: Course, today: CalendarDay = CalendarDay.today(), setSchoolYear: @escaping () -> Void) {
        self.course = course
        self.today = today
        self.setSchoolYear = setSchoolYear
    }
}

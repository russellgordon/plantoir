import SwiftUI

/// "Keep a Copy for Reference…" — one of the two ways a reference course is
/// made. The other is "Import Courses for Reference…"
/// (`ImportCoursesForReferenceSheet`), which is the same act with a different
/// source and ends in the same function.
///
/// A school year, a folder name, and two sentences saying what the copy IS.
/// The course the teacher is teaching is not touched and not mentioned again:
/// they keep teaching it, and they remove it themselves when the time comes.
struct KeepACopyForReferenceSheet: View {

    // MARK: - Stored properties

    let course: Course

    /// Called with the new folder's name once the copy is made, so the
    /// sidebar can reload and select it.
    let onCopy: (String) -> Void

    @Environment(\.dismiss) var dismiss
    @Environment(WorkspaceModel.self) var workspace

    /// The school year the copy is filed under, or nil for "Other".
    ///
    /// **Pre-selected to the CURRENT school year** (Russell's decision): the
    /// teacher is copying the course they are teaching NOW, so "now" is the
    /// year the copy records. "No year" is one click away in the same list,
    /// for a course full of example content.
    @State var schoolYear: Int?

    @State var folderName: String = ""
    @State var problem: String?
    @State var isCopying: Bool = false

    /// What of the course's `.obsidian` the copy leaves behind (#255). Read
    /// once when the sheet appears — one `lstat` or two and one listing —
    /// rather than on every redraw of `body`.
    @State var addOns: ObsidianAddOns.Found = ObsidianAddOns.Found()

    /// The day the year list is built from. A stored property rather than a
    /// call to the clock inside the body, so the list cannot change under
    /// the teacher mid-sheet — and so a test can move it.
    let today: CalendarDay

    // MARK: - Computed properties

    var offeredYears: [Int] {
        return SchoolYear.offeredStartingYears(on: today)
    }

    /// What is wrong with the choices as they stand, or nil.
    var entryProblem: String? {
        if let problem {
            return problem
        }
        if let trouble = ReferenceCourseRule.trouble(
            placing: course.displayCode,
            inYear: schoolYear,
            among: workspace.shelvedReferenceCourses(on: today)
        ) {
            return trouble.sentence
        }
        return CourseCodeRule.problem(folderName, existingCodes: existingFolderNames)
    }

    var existingFolderNames: [String] {
        var names: [String] = []
        for candidate in workspace.courses {
            names.append(candidate.code)
        }
        return names
    }

    var canCopy: Bool {
        return entryProblem == nil && !folderName.isEmpty && !isCopying
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(ReferenceWording.keepACopyTitle(course: course.displayCode))
                .font(.headline)

            Text(ReferenceWording.copyIsASnapshot(course: course.displayCode))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("School year", selection: $schoolYear) {
                ForEach(offeredYears, id: \.self) { year in
                    Text(SchoolYear.label(forStartingYear: year)).tag(Int?.some(year))
                }
                Text(SchoolYear.otherGroupName).tag(Int?.none)
            }
            .onChange(of: schoolYear) {
                problem = nil
                folderName = proposedFolderName()
            }

            LabeledContent("Folder name") {
                TextField("Folder name", text: $folderName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("keepACopyFolderName")
            }

            if let entryProblem {
                Text(entryProblem)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("keepACopyProblem")
            }

            // The calm note, said where the teacher is deciding rather than
            // after the fact. No icon, and no "cannot".
            //
            // Said here BEFORE the copy exists, so there is nothing to census
            // yet — what the copy's own pane says afterwards is gated on
            // whether the locking actually took, which is where a volume that
            // cannot carry the flag shows up.
            VStack(alignment: .leading, spacing: 4) {
                if let addOnsNote = KeepACopyForReferenceSheet.addOnsNote(
                    course: course.displayCode, found: addOns
                ) {
                    Text(addOnsNote)
                        .accessibilityIdentifier("keepACopyAddOnsNote")
                }
                Text(ReferenceWording.pagesAreLocked)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Button("Keep a Copy") {
                    keepACopy()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCopy)
                .accessibilityIdentifier("keepACopyButton")
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            if folderName.isEmpty {
                folderName = proposedFolderName()
            }
            addOns = ObsidianAddOns.found(inCourseAt: course.directoryURL)
        }
    }

    // MARK: - Initializer

    init(course: Course, today: CalendarDay = CalendarDay.today(), onCopy: @escaping (String) -> Void) {
        self.course = course
        self.today = today
        self.onCopy = onCopy
        _schoolYear = State(initialValue: SchoolYear.startingYear(on: today))
    }

    // MARK: - Functions

    /// The sentence about add-ons, or nil when the course has none — an
    /// empty add-ons folder says nothing, because telling a teacher their
    /// add-ons stay behind when they have none would be false (#255).
    static func addOnsNote(course: String, found: ObsidianAddOns.Found) -> String? {
        if found.isEmpty {
            return nil
        }
        return ReferenceWording.keepACopyLeavesAddOnsBehind(course: course)
    }

    func proposedFolderName() -> String {
        return ReferenceCourseRule.proposedFolderName(
            forCode: course.displayCode,
            schoolYear: schoolYear,
            existingFolderNames: existingFolderNames
        )
    }

    func keepACopy() {
        guard let coursesDirectoryURL = workspace.coursesDirectoryURL else {
            return
        }
        isCopying = true
        do {
            let made: ReferenceCopier.Made = try ReferenceCopier.keepACopy(
                of: course,
                named: CourseCodeRule.normalized(folderName),
                schoolYear: schoolYear,
                coursesDirectoryURL: coursesDirectoryURL
            )
            dismiss()
            onCopy(made.folderName)
        } catch {
            isCopying = false
            problem = error.localizedDescription
        }
    }
}

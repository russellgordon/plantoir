import SwiftUI
import UniformTypeIdentifiers

/// "When does this class meet?" — asked once, and then never again.
///
/// The assistant puts this on screen when a teacher asks for something that
/// needs the class dates and there are none recorded yet: laying down
/// placeholder pages for a unit, inserting a class and pushing the rest along.
/// It is a sheet rather than a conversation because the answer is a column of
/// dates, and a column of dates is a miserable thing to dictate.
///
/// Three routes in, because teachers keep their timetable in three different
/// places and none of them is wrong. Whichever they pick, the reading is done
/// by `SectionScheduleSource` in Swift — the assistant's model never sees the
/// column and so can never invent a date that was not in it.
struct SectionScheduleSheet: View {

    // MARK: - Types

    /// Which of the three ways in the teacher is using.
    enum Route: String, CaseIterable, Identifiable {
        case typed
        case file
        case googleSheet

        var id: String {
            return rawValue
        }

        var label: String {
            switch self {
            case .typed:
                return "Type or paste"
            case .file:
                return "A file"
            case .googleSheet:
                return "A Google Sheet"
            }
        }
    }

    // MARK: - Stored properties

    let course: Course
    let sectionNumber: Int

    /// Why the assistant asked, in its own words — "Laying down placeholder
    /// pages needs the class dates first." Empty when a teacher opened this
    /// themselves.
    var reason: String = ""

    /// Called once the dates really are written down, so whatever was waiting
    /// on them can carry on.
    var onRemembered: (SectionTimetable) -> Void = { _ in }

    @State var route: Route = .typed

    /// The pasted column, as typed.
    @State var typed: String = ""

    /// The file picked, and whether the picker is open.
    @State var pickedFileURL: URL?
    @State var isPickingFile: Bool = false

    /// The address pasted out of a browser's address bar.
    @State var googleSheetLink: String = ""

    /// Where these came from, in the teacher's own words. Pre-filled from
    /// whichever route was used, and meant to be improved on.
    @State var source: String = ""

    /// True while the sheet is being fetched — the one step that is not
    /// instant.
    @State var isFetching: Bool = false

    /// The one question a column sometimes cannot answer for itself, waiting
    /// on the teacher. Nil the rest of the time, which is most of the time.
    @State var question: SectionScheduleSource.OrderingQuestion?

    /// What was read, ready to be confirmed. Nothing is on disk until the
    /// teacher says so.
    @State var plan: RememberTimetablePlan?

    /// The refusal, when there was one.
    @State var failure: String?

    @Environment(\.dismiss) var dismiss

    // MARK: - Computed properties

    /// The types the file picker offers. A `.ics` has no built-in type on
    /// every Mac, so it is named by its extension as well.
    var readableFileTypes: [UTType] {
        var types: [UTType] = [UTType.commaSeparatedText]
        if let calendar = UTType(filenameExtension: "ics") {
            types.append(calendar)
        }
        return types
    }

    var canRead: Bool {
        if isFetching {
            return false
        }
        switch route {
        case .typed:
            return !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .file:
            return pickedFileURL != nil
        case .googleSheet:
            return !googleSheetLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()

            if let plan {
                confirmation(of: plan)
            } else if let question {
                orderingQuestion(question)
            } else {
                routePicker
                routeFields
                sourceField
            }

            if let failure {
                ScrollView {
                    Text(failure)
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("sectionScheduleFailure")
                }
                .frame(maxHeight: 110)
            }

            Divider()
            buttons
        }
        .padding(20)
        .frame(width: 560)
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: readableFileTypes
        ) { result in
            switch result {
            case .success(let url):
                pickedFileURL = url
                failure = nil
                if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    source = url.lastPathComponent
                }
            case .failure:
                break
            }
        }
    }

    // MARK: - Computed properties — the parts of the sheet

    var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("When does \(course.displayCode) section \(sectionNumber) meet?")
                .font(.title2)
                .accessibilityIdentifier("sectionScheduleTitle")

            // The one sentence that has to be here: a teacher being asked
            // for a column of dates deserves to know what it buys them.
            Text("Give Plantoir the class dates once, so it can date new class pages for you. They are kept inside the course folder, so they travel with it through backup, archive and restore.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("sectionSchedulePurpose")

            if !reason.isEmpty {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("sectionScheduleReason")
            }
        }
    }

    var routePicker: some View {
        Picker("Where the dates are", selection: $route) {
            ForEach(Route.allCases) { choice in
                Text(choice.label).tag(choice)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("sectionScheduleRoutePicker")
        .onChange(of: route) {
            failure = nil
        }
    }

    @ViewBuilder
    var routeFields: some View {
        switch route {
        case .typed:
            VStack(alignment: .leading, spacing: 6) {
                Text("One date per line. A heading row and blank lines are fine.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextEditor(text: $typed)
                    .font(.body.monospaced())
                    .frame(minHeight: 150)
                    .border(Color.secondary.opacity(0.3))
                    .accessibilityIdentifier("sectionScheduleTypedField")
            }

        case .file:
            VStack(alignment: .leading, spacing: 6) {
                Text("A .csv file with one column of dates, or a .ics calendar export.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Choose a file…") {
                        isPickingFile = true
                    }
                    .accessibilityIdentifier("sectionScheduleChooseFileButton")

                    if let pickedFileURL {
                        Text(pickedFileURL.lastPathComponent)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .accessibilityIdentifier("sectionScheduleChosenFile")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            }

        case .googleSheet:
            VStack(alignment: .leading, spacing: 6) {
                Text("Paste the sheet's address, straight out of your browser's address bar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("https://docs.google.com/spreadsheets/d/…/edit", text: $googleSheetLink)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("sectionScheduleGoogleSheetField")

                // Said plainly, and before the button is pressed. Everything
                // else the assistant does happens on this Mac; this one step
                // does not, and a teacher should meet that as a sentence
                // rather than work it out afterwards.
                Label(
                    "Reading a Google Sheet sends the link to Google over the internet. It is the only thing Plantoir's assistant does that leaves this Mac — the other two ways above stay here.",
                    systemImage: "globe"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
                .accessibilityIdentifier("sectionScheduleNetworkNotice")

                Text("The sheet has to be shared: in the sheet, Share ▸ General access ▸ “Anyone with the link”.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        }
    }

    var sourceField: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Where these came from", text: $source)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("sectionScheduleSourceField")
            Text("In your own words — “timetable.xlsx, block H”. This is what you will read months from now when you wonder where these dates came from.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The one question the file cannot answer for itself.
    ///
    /// It quotes one of the teacher's own dates, written out both ways, so
    /// the answer is about their timetable rather than about notation. Their
    /// spreadsheet is not wrong here — it just does not say — so this is a
    /// question with two buttons, not a refusal that sends them away.
    func orderingQuestion(_ question: SectionScheduleSource.OrderingQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(question.prompt)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("sectionScheduleOrderingQuestion")

            HStack(spacing: 12) {
                Button("Day first (\(question.dayFirstShort))") {
                    answer(question, with: .dayThenMonth)
                }
                .accessibilityIdentifier("sectionScheduleDayFirstButton")

                Button("Month first (\(question.monthFirstShort))") {
                    answer(question, with: .monthThenDay)
                }
                .accessibilityIdentifier("sectionScheduleMonthFirstButton")
            }

            Text("Whichever you pick is used for every date in the column, and is written down beside them — so months from now it is clear which way they were read.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
    }

    func confirmation(of plan: RememberTimetablePlan) -> some View {
        ScrollView {
            Text(plan.description)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("sectionSchedulePlan")
        }
        .frame(minHeight: 180)
    }

    var buttons: some View {
        HStack {
            if isFetching {
                ProgressView()
                    .controlSize(.small)
                Text("Fetching the sheet…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            if plan != nil || question != nil {
                Button("Back") {
                    plan = nil
                    question = nil
                    failure = nil
                }
                .accessibilityIdentifier("sectionScheduleBackButton")
            }

            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .accessibilityIdentifier("sectionScheduleCancelButton")

            if let plan {
                Button("Remember these dates") {
                    remember(plan)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("sectionScheduleRememberButton")
            } else if question == nil {
                Button("Read the dates") {
                    Task { await read() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canRead)
                .accessibilityIdentifier("sectionScheduleReadButton")
            }
        }
    }

    // MARK: - Functions

    /// Read whichever route the teacher chose. What comes back is either the
    /// dates, or the ordering question. Nothing touches disk either way.
    func read() async {
        failure = nil
        plan = nil
        question = nil

        var outcome: SectionScheduleSource.Outcome?
        do {
            switch route {
            case .typed:
                outcome = try SectionScheduleSource.read(fromTypedText: typed)
            case .file:
                guard let pickedFileURL else {
                    return
                }
                outcome = try SectionScheduleSource.read(fromFileAt: pickedFileURL)
            case .googleSheet:
                isFetching = true
                outcome = try await SectionScheduleSource.read(fromGoogleSheetLink: googleSheetLink)
                isFetching = false
            }
        } catch {
            isFetching = false
            failure = error.localizedDescription
            return
        }

        switch outcome {
        case .dates(let reading):
            propose(reading)
        case .question(let raised):
            question = raised
        case nil:
            return
        }
    }

    /// The teacher's answer to the ordering question, applied to the whole
    /// column at once.
    func answer(_ question: SectionScheduleSource.OrderingQuestion, with ordering: SectionScheduleSource.ColumnOrdering) {
        failure = nil
        do {
            let reading: SectionScheduleSource.Reading = try question.answered(ordering)
            self.question = nil
            propose(reading)
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Turn dates that were read into a plan the teacher can look at before
    /// anything is written down.
    func propose(_ reading: SectionScheduleSource.Reading) {
        let described: String = description(of: reading)
        source = described
        do {
            // Straight through the existing store, so its refusals — above
            // all "a partial list is refused whole" — apply to every route
            // in here exactly as they do to a dictated list.
            plan = try SectionTimetableStore.planRememberTimetable(
                dates: reading.datesText,
                source: described,
                forSection: sectionNumber,
                in: course
            )
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Where these came from, in the teacher's words where they gave any.
    ///
    /// When they answered the ordering question, that answer is written in
    /// too. Months later "a Google Sheet, day first" explains a date somebody
    /// is squinting at; "a Google Sheet" leaves them guessing all over again.
    func description(of reading: SectionScheduleSource.Reading) -> String {
        var described: String = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if described.isEmpty {
            described = reading.suggestedSource
        }
        if let ordering = reading.chosenOrdering, !described.lowercased().contains(ordering.note) {
            described += ", \(ordering.note)"
        }
        return described
    }

    func remember(_ plan: RememberTimetablePlan) {
        do {
            try SectionTimetableStore.applyRememberTimetable(plan)
        } catch {
            failure = error.localizedDescription
            return
        }
        onRemembered(SectionTimetable(
            sectionNumber: plan.sectionNumber,
            dates: plan.dates,
            source: plan.source,
            recorded: plan.recorded
        ))
        dismiss()
    }
}

/// The way anything else in the app asks for this sheet.
///
/// The assistant runs its tools in a model that knows nothing about windows,
/// so it cannot present a sheet itself. It puts a request here instead, and
/// whichever assistant window is showing that section notices and opens it.
/// Keeping the request outside the window means the tool that needed the
/// dates does not have to reach into the view layer to ask for them.
@Observable
final class SectionSchedulePrompt {

    // MARK: - Types

    /// Who is being asked, and why.
    struct Request: Identifiable, Equatable {

        // MARK: - Stored properties

        let courseCode: String
        let sectionNumber: Int
        let workingFolder: URL

        /// The assistant's own sentence about why it needs the dates.
        let reason: String

        // MARK: - Computed properties

        var id: String {
            return "\(workingFolder.path)#\(courseCode)#\(sectionNumber)"
        }
    }

    // MARK: - Stored properties

    /// One at a time. A second ask before the first is answered replaces it,
    /// because two sheets stacked on one window is not a thing a teacher can
    /// make sense of.
    private(set) var request: Request?

    /// A request the assistant would LIKE to make, waiting on the teacher.
    ///
    /// **The sheet used to open the instant something needed dates, on top of
    /// the answer explaining why** — so the teacher was handed a form before
    /// they had read the sentence that asked for it, and the sentence was
    /// behind it. A form is a demand; this makes it an offer. The assistant
    /// says what it needs and waits for Yes, which is the same courtesy every
    /// other write in the window already gets.
    private(set) var offer: Request?

    static let shared: SectionSchedulePrompt = SectionSchedulePrompt()

    // MARK: - Functions

    /// Say that dates are needed, WITHOUT putting a form on screen. The
    /// teacher answers, and only a Yes opens the sheet.
    func offerToAsk(
        courseCode: String,
        sectionNumber: Int,
        workingFolder: URL,
        because reason: String = ""
    ) {
        offer = Request(
            courseCode: courseCode,
            sectionNumber: sectionNumber,
            workingFolder: workingFolder,
            reason: reason
        )
    }

    /// The teacher said yes: now the sheet may open.
    func acceptOffer() {
        guard let offer else {
            return
        }
        request = offer
        self.offer = nil
    }

    /// The teacher said no. Nothing opens, and nothing is asked again until
    /// something needs the dates afresh.
    func declineOffer() {
        offer = nil
    }

    /// Ask a teacher for a section's class dates.
    ///
    /// Opens the sheet immediately, so it is for the case where the teacher
    /// ASKED — "I have a revised list of class dates" — rather than for
    /// something that merely discovered it needed them.
    func ask(
        courseCode: String,
        sectionNumber: Int,
        workingFolder: URL,
        because reason: String = ""
    ) {
        request = Request(
            courseCode: courseCode,
            sectionNumber: sectionNumber,
            workingFolder: workingFolder,
            reason: reason
        )
    }

    /// Answered, or waved away.
    func stopAsking() {
        request = nil
        offer = nil
    }

    /// The course a request is about, read from the working folder it names.
    /// Nil when the folder no longer holds it — a request that arrives after
    /// the course has been moved is dropped rather than shown against the
    /// wrong course.
    func course(for request: Request) -> Course? {
        let courseURL: URL = request.workingFolder
            .appendingPathComponent("courses")
            .appendingPathComponent(request.courseCode)
        let configURL: URL = courseURL.appendingPathComponent("course_config.json")
        guard let configuration = try? CourseConfiguration(contentsOf: configURL) else {
            return nil
        }
        return Course(code: request.courseCode, directoryURL: courseURL, configuration: configuration)
    }
}

extension View {

    /// Attach to a window that is about one section: when something asks for
    /// that section's class dates, the sheet appears here.
    func sectionSchedulePrompt(
        courseCode: String,
        sectionNumber: Int,
        workingFolder: URL,
        onRemembered: @escaping (SectionTimetable) -> Void = { _ in }
    ) -> some View {
        return modifier(SectionSchedulePromptModifier(
            courseCode: courseCode,
            sectionNumber: sectionNumber,
            workingFolder: workingFolder,
            onRemembered: onRemembered
        ))
    }
}

/// Presents `SectionScheduleSheet` when — and only when — the outstanding
/// request is for the section this window is about.
struct SectionSchedulePromptModifier: ViewModifier {

    // MARK: - Stored properties

    let courseCode: String
    let sectionNumber: Int
    let workingFolder: URL
    let onRemembered: (SectionTimetable) -> Void

    @State var prompt = SectionSchedulePrompt.shared

    // MARK: - Computed properties

    /// The outstanding request, when it is this window's to answer.
    var mine: SectionSchedulePrompt.Request? {
        guard let request = prompt.request else {
            return nil
        }
        if request.courseCode != courseCode || request.sectionNumber != sectionNumber {
            return nil
        }
        if request.workingFolder.path != workingFolder.path {
            return nil
        }
        return request
    }

    // MARK: - Functions

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(
                get: { return mine },
                set: { newValue in
                    if newValue == nil {
                        prompt.stopAsking()
                    }
                }
            )) { request in
                if let course = prompt.course(for: request) {
                    SectionScheduleSheet(
                        course: course,
                        sectionNumber: request.sectionNumber,
                        reason: request.reason,
                        onRemembered: onRemembered
                    )
                } else {
                    SectionScheduleCourseMissingView(courseCode: request.courseCode)
                }
            }
    }
}

/// Shown in place of the sheet when the course a request names is no longer
/// where it said it was.
struct SectionScheduleCourseMissingView: View {

    // MARK: - Stored properties

    let courseCode: String

    @Environment(\.dismiss) var dismiss

    // MARK: - Computed properties

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(courseCode) could not be found in this working folder, so there is nothing to record class dates against.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("sectionScheduleCourseMissing")
            HStack {
                Spacer()
                Button("OK") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

import AppKit
import SwiftUI

/// "Copy a Page from This Course…" — one page of one course, with the
/// pictures and files it shows, landing in a course the teacher teaches.
///
/// Three questions, then what will happen, then what did. The copy ALWAYS
/// arrives hidden from students in every section of the course it lands in,
/// and nothing already there is ever changed or written over — those two are
/// the whole shape of this sheet and are said on screen rather than assumed.
///
/// **The backup is taken once per sheet, not once per press.** A real course
/// zips to 467 MB in about ten seconds, so five presses of "Copy another"
/// would be fifty seconds of waiting and 2.3 GB of copies — and a second
/// backup taken after the first copy is a way back that already contains the
/// first copy, which is worth less than the one before it.
struct CopyPageSheet: View {

    // MARK: - Types

    /// Where the sheet is.
    enum Stage: Equatable {
        case choosing
        case working
        case checking
        case savingACopy
        case copying
        case finished
    }

    // MARK: - Stored properties

    /// The course the menu item was chosen on — live or kept for reference.
    /// It is only ever READ.
    let source: Course

    @Environment(\.dismiss) var dismiss
    @Environment(WorkspaceModel.self) var workspace

    @State var picker: PagePickerModel = PagePickerModel()
    @State var sourceFacts: CopyCourseFacts?

    /// The destination's facts, read ONCE per choice of course rather than
    /// during every body evaluation.
    ///
    /// Reading them asks the file system whether each shared folder is really
    /// on disk, and a computed property doing that is a `stat` per folder per
    /// redraw — eleven of them on a real course, for every keystroke in the
    /// page field.
    @State var destinationFacts: CopyCourseFacts?
    @State var destinationCode: String = ""
    @State var destinationFolderName: String = ""
    @State var stage: Stage = .choosing

    /// The backup taken before the first write of this sheet session, by its
    /// file name — which is also what is shown at the end and what goes on
    /// the trail.
    @State var backupFileName: String?

    @State var outcome: CoursePageCopyOutcome?
    @State var problem: String?

    /// Whether the pages this page links to come along. Russell's one
    /// checkbox, on by default.
    @State var alsoCopiesLinkedPages: Bool = true

    /// The plan the teacher is looking at, when there is a checklist to show.
    @State var shownPlan: CoursePageCopyPlan?

    /// The linked pages still ticked, by lowercased title.
    @State var keptLinkedPages: Set<String> = []

    /// Every linked page the FIRST plan found — the checklist's ROWS, which
    /// never change while the sheet is open. Unticking used to remove a page
    /// from the plan and therefore from the list, so it could not be put back
    /// or even seen.
    @State var candidates: [CopiedPagePlacement] = []

    // MARK: - Computed properties

    /// The courses a copy may land in: the ones the teacher teaches, never a
    /// course kept for reference, never the source itself, and never one with
    /// no shared folder to land in.
    var destinations: [Course] {
        var result: [Course] = []
        for candidate in workspace.courses {
            if candidate.isKeptForReference {
                continue
            }
            if candidate.code == source.code {
                continue
            }
            // The comment above is the rule, so it is applied rather than
            // described: a course whose shared folders are all missing from
            // disk has nowhere for a page to land, and offering it leads to a
            // disabled Copy button with no sentence beside it.
            if CopyCourseFacts.read(from: candidate).sharedFolderNames.isEmpty {
                continue
            }
            result.append(candidate)
        }
        result.sort { first, second in
            return first.displayCode.localizedStandardCompare(second.displayCode) == .orderedAscending
        }
        return result
    }

    var destinationCourse: Course? {
        for candidate in destinations where candidate.code == destinationCode {
            return candidate
        }
        return nil
    }

    var destinationFolderNames: [String] {
        return destinationFacts?.sharedFolderNames ?? []
    }

    /// Why Copy is not available right now, or nil.
    var refusal: String? {
        if picker.pages.isEmpty {
            return CopyPageWording.thisCourseHasNoPagesToCopy(
                course: sourceFacts?.displayName ?? source.displayCode
            )
        }
        guard let destinationCourse else {
            return CopyPageWording.thereIsNoCourseToCopyInto
        }
        if destinationFolderNames.isEmpty {
            return CopyPageWording.thatCourseHasNowhereToPutIt(
                course: destinationCourse.displayCode
            )
        }
        if let workspaceURL = workspace.workspaceURL,
           CourseActivity.coursePublishIsRunning(
            folderPath: workspaceURL.path, courseCode: destinationCourse.code
           ) {
            return CopyPageWording.thatCourseIsDeployingRightNow(
                course: destinationCourse.displayCode
            )
        }
        return nil
    }

    var canCopy: Bool {
        return stage == .choosing
            && picker.chosenPage != nil
            && destinationCourse != nil
            && !destinationFolderName.isEmpty
            && refusal == nil
    }

    var request: CoursePageCopyRequest? {
        guard let sourceFacts, let destinationFacts, let page = picker.chosenPage else {
            return nil
        }
        return CoursePageCopyRequest(
            source: sourceFacts,
            page: page,
            destination: destinationFacts,
            destinationFolderName: destinationFolderName,
            alsoCopiesLinkedPages: alsoCopiesLinkedPages,
            keptLinkedPages: stage == .checking ? keptLinkedPages : nil
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(CopyPageWording.sheetTitle(course: sourceFacts?.displayName ?? source.displayCode))
                .font(.headline)

            if stage == .finished, let outcome {
                result(outcome)
            } else if stage == .checking, let shownPlan {
                checklist(shownPlan)
            } else {
                questions
            }

            if let problem {
                Text(problem)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("copyPageProblem")
            }

            buttons
        }
        .padding(20)
        .frame(width: 480)
        // The work is started as a Task that outlives this view, so a sheet
        // dismissed mid-backup would go on writing files, reloading the
        // sidebar and putting a line on the trail after the teacher believed
        // they had stopped. Cancel is already disabled then; this closes the
        // other ways out.
        .interactiveDismissDisabled(stage == .savingACopy || stage == .copying || stage == .working)
        // The list is rendered HERE, at the top level of the sheet — never
        // inside the form above. See `SearchablePicker`'s header for what
        // happens otherwise: the card renders at a stuck zero frame and is
        // simply invisible.
        .overlayPreferenceValue(SearchablePickerAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if picker.isShowingSuggestions, let anchor, stage == .choosing {
                    SearchablePickerOverlay(
                        fieldFrame: proxy[anchor],
                        sections: picker.sections,
                        highlightedRowId: picker.highlightedRowId,
                        emptyMessage: CopyPageWording.noPagesMatch,
                        onSelect: { page in
                            picker.choose(page)
                            proposeAFolder()
                        },
                        rowIdentifier: { page in
                            return "copyPageRow-\(page.id)"
                        },
                        row: { page, isHighlighted in
                            PagePickerRow(page: page, isHighlighted: isHighlighted)
                        }
                    )
                    .transition(.opacity.combined(with: .offset(y: -6)))
                }
            }
            .animation(
                .easeOut(duration: 0.12),
                value: PagePickerListChange(
                    isShown: picker.isShowingSuggestions, rowIds: picker.visibleRowIds
                )
            )
        }
        .onAppear {
            loadTheSource()
        }
    }

    // MARK: - The three questions

    @ViewBuilder
    var questions: some View {
        LabeledContent(CopyPageWording.whichPage) {
            SearchablePickerField(
                text: $picker.searchText,
                isFocused: $picker.isFieldFocused,
                prompt: CopyPageWording.pagePickerPrompt,
                fieldIdentifier: "copyPagePicker",
                onEscape: {
                    picker.dismissSuggestions()
                },
                onRevealRequested: {
                    // A toggle, not an open: a real combo box's arrow closes
                    // its popup as readily as it opens it.
                    if picker.isShowingSuggestions {
                        picker.dismissSuggestions()
                    } else {
                        picker.reveal()
                    }
                },
                onMoveHighlight: { delta in
                    return picker.moveHighlight(by: delta)
                },
                onCommitHighlight: {
                    let took: Bool = picker.commitHighlight()
                    if took {
                        proposeAFolder()
                    }
                    return took
                }
            )
            .onChange(of: picker.searchText) {
                picker.noteTyping()
            }
        }

        Picker(CopyPageWording.whichCourse, selection: $destinationCode) {
            ForEach(destinations) { candidate in
                Text(candidate.displayCode).tag(candidate.code)
            }
        }
        .accessibilityIdentifier("copyPageDestinationCourse")
        .onChange(of: destinationCode) {
            readTheDestination()
        }

        Picker(CopyPageWording.whichFolder, selection: $destinationFolderName) {
            ForEach(destinationFolderNames, id: \.self) { name in
                Text(name).tag(name)
            }
        }
        .accessibilityIdentifier("copyPageDestinationFolder")

        Toggle(CopyPageWording.alsoCopyLinkedPages, isOn: $alsoCopiesLinkedPages)
            .accessibilityIdentifier("copyPageAlsoLinked")

        VStack(alignment: .leading, spacing: 4) {
            Text(CopyPageWording.copiesStartHidden)
            Text(CopyPageWording.nothingIsWrittenOver)
            Text(CopyPageWording.datesAreKept)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

        if let refusal {
            Text(refusal)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("copyPageRefusal")
        }

        if stage == .savingACopy {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(CopyPageWording.savingACopyFirst(
                    course: destinationCourse?.displayCode ?? ""
                ))
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - The pages this one links to

    /// The checklist, as its own view so it can be rendered — and LOOKED at
    /// — without a window, a workspace or a sheet around it.
    @ViewBuilder
    func checklist(_ plan: CoursePageCopyPlan) -> some View {
        CopyPageChecklist(
            candidates: candidates,
            chosenPage: picker.chosenPage?.pageName ?? "",
            plan: plan,
            courseName: destinationFacts?.displayName ?? "",
            folderName: destinationFolderName,
            kept: Binding(
                get: { return keptLinkedPages },
                set: { updated in
                    keptLinkedPages = updated
                    replan()
                }
            )
        )
    }

    // MARK: - What happened

    @ViewBuilder
    func result(_ outcome: CoursePageCopyOutcome) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if outcome.createdNothing {
                Text(CopyPageWording.nothingWasCopied)
            } else {
                Text(CopyPageWording.copiedInto(
                    pages: outcome.pagesCreated.count,
                    course: destinationCourse?.displayCode ?? "",
                    folder: destinationFolderName
                ))
                Text(CopyPageWording.copiesStartHidden)
                    .foregroundStyle(.secondary)
            }

            if outcome.mediaCreated > 0 {
                Text(CopyPageWording.willBringPicturesAndFiles(
                    count: outcome.mediaCreated,
                    size: ReferenceImportWording.size(outcome.bytesCopied)
                ))
                .foregroundStyle(.secondary)
            }
            if outcome.mediaReused > 0 {
                Text(CopyPageWording.picturesAlreadyThere(count: outcome.mediaReused))
                    .foregroundStyle(.secondary)
            }
            if !outcome.renamed.isEmpty {
                Text(CopyPageWording.picturesBroughtInUnderANewName(count: outcome.renamed.count))
                    .foregroundStyle(.secondary)
            }
            ForEach(outcome.skipped.indices, id: \.self) { index in
                Text(CopyPageSheet.sentence(
                    for: outcome.skipped[index], couldNotBeRemoved: outcome.couldNotBeRemoved
                ))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            if !outcome.sourceSettingsUnreadable.isEmpty {
                Text(CopyPageWording.theSourcesSettingsCouldNotBeRead(
                    names: outcome.sourceSettingsUnreadable
                ))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            if !outcome.linksLeadingNowhere.isEmpty {
                Text(CopyPageWording.theseLinksWillNotLeadAnywhereYet(
                    names: outcome.linksLeadingNowhere
                ))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let backupFileName {
                Text(CopyPageWording.theBackupTaken(
                    course: destinationCourse?.displayCode ?? "", named: backupFileName
                ))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let folderURL = destinationFacts?.directoryURL
                .appendingPathComponent(destinationFolderName) {
                Button("Show in Finder", systemImage: "finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([folderURL])
                }
                .accessibilityIdentifier("copyPageShowInFinder")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("copyPageResult")
    }

    // MARK: - The buttons

    @ViewBuilder
    var buttons: some View {
        HStack {
            Spacer()
            if stage == .finished {
                Button(CopyPageWording.copyAnother) {
                    copyAnother()
                }
                .accessibilityIdentifier("copyPageCopyAnother")
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .disabled(stage != .choosing && stage != .checking)
                Button("Copy") {
                    if stage == .checking {
                        copy()
                    } else {
                        lookAtWhatItWouldDo()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCopy && stage != .checking)
                .accessibilityIdentifier("copyPageButton")
            }
        }
    }

    // MARK: - Functions

    /// What a skip reads as. The sentence is chosen here rather than carried
    /// on the skip, so the rule and the wording stay in separate places.
    static func sentence(for skip: CopySkip, couldNotBeRemoved: [String] = []) -> String {
        if skip.reason == .theCopyIsStillThereAndMustBeRemoved {
            var path: String = ""
            for candidate in couldNotBeRemoved
            where candidate.contains("/" + skip.name + ".md") {
                path = candidate
            }
            if path.isEmpty, let first = couldNotBeRemoved.first {
                path = first
            }
            return CopyPageWording.theCopyIsStillThereAndMustBeRemoved(
                page: skip.name, at: path
            )
        }
        return CopyPageSheet.plainSentence(for: skip)
    }

    static func plainSentence(for skip: CopySkip) -> String {
        switch skip.reason {
        case .aPageOfThatNameIsAlreadyHere:
            return CopyPageWording.aPageOfThatNameIsAlreadyHere(page: skip.name)
        case .theCopyCouldNotBeMadeHidden:
            return CopyPageWording.theCopyCouldNotBeMadeHidden(page: skip.name)
        case .thePageIsWrittenInAWayPlantoirCannotBeSureOf:
            return CopyPageWording.thePageIsWrittenInAWayPlantoirCannotBeSureOf(page: skip.name)
        case .theCopyIsStillThereAndMustBeRemoved:
            // The path is filled in by the caller, which has the outcome's
            // list; this is the fallback when it cannot be matched up.
            return CopyPageWording.theCopyIsStillThereAndMustBeRemoved(
                page: skip.name, at: ""
            )
        case .thePicturesCouldNotBePointedAtTheirNewNames:
            return CopyPageWording.thePicturesCouldNotBePointedAtTheirNewNames(page: skip.name)
        case .thePageCouldNotBeRead, .thePageCouldNotBeWritten:
            return CopyPageWording.thePageCouldNotBeWritten(page: skip.name)
        case .aPictureCouldNotBeCopied:
            return CopyPageWording.aPictureCouldNotBeCopied(name: skip.name)
        case .aClassPageWasLeftAlone:
            return CopyPageWording.aClassPageWasLeftAlone(page: skip.name)
        case .anIndexPageIsNotCopied:
            return CopyPageWording.anIndexPageIsNotCopied(page: skip.name)
        case .aPageAtTheCourseRootIsNotCopied:
            return CopyPageWording.aPageAtTheCourseRootIsNotCopied(page: skip.name)
        case .aPageInsideOneSectionsFolderIsNotCopied:
            return CopyPageWording.aPageInsideOneSectionsFolderIsNotCopied(page: skip.name)
        }
    }

    func loadTheSource() {
        let facts: CopyCourseFacts = CopyCourseFacts.read(from: source)
        sourceFacts = facts
        picker.show(CoursePageCopyPlanner.copyablePages(in: facts))
        if destinationCode.isEmpty, let first = destinations.first {
            destinationCode = first.code
        }
        readTheDestination()
    }

    /// Reads the chosen destination's facts, and then proposes a folder.
    func readTheDestination() {
        guard let destinationCourse else {
            destinationFacts = nil
            destinationFolderName = ""
            return
        }
        destinationFacts = CopyCourseFacts.read(from: destinationCourse)
        proposeAFolder()
    }

    /// The folder question starts on the source page's own folder when the
    /// destination has one of that name, and on the first otherwise.
    func proposeAFolder() {
        let names: [String] = destinationFolderNames
        if names.isEmpty {
            destinationFolderName = ""
            return
        }
        if let page = picker.chosenPage {
            for name in names where name == page.folderName {
                destinationFolderName = name
                return
            }
        }
        if names.contains(destinationFolderName) {
            return
        }
        destinationFolderName = names[0]
    }

    /// Works out what the copy WOULD do, and shows the checklist when there
    /// is something to tick. Nothing is written by this.
    func lookAtWhatItWouldDo() {
        guard let request else {
            return
        }
        problem = nil
        stage = .working
        Task { @MainActor in
            let plan: CoursePageCopyPlan = await CoursePageCopyPlanner.planning(request)
            if plan.linkedPages.isEmpty {
                stage = .choosing
                copy()
                return
            }
            var ticked: Set<String> = []
            for linked in plan.linkedPages {
                ticked.insert(linked.pageName.lowercased())
            }
            keptLinkedPages = ticked
            candidates = plan.linkedPages
            shownPlan = plan
            stage = .checking
        }
    }

    /// Works the plan out again from the ticks as they stand now.
    func replan() {
        guard let request else {
            return
        }
        Task { @MainActor in
            shownPlan = await CoursePageCopyPlanner.planning(request)
        }
    }

    func copy() {
        guard let request, let destinationCourse else {
            return
        }
        guard let coursesDirectoryURL = workspace.coursesDirectoryURL else {
            return
        }
        problem = nil

        // Asked AGAIN here, on the main actor, immediately before anything is
        // written — the sheet may have been open while a deploy started.
        if let refusal {
            problem = refusal
            return
        }

        let destinationDirectoryPath: String = destinationCourse.directoryURL.path
        let destinationFolderCode: String = destinationCourse.code
        let sourceFolderName: String = source.code
        let takeABackup: Bool = backupFileName == nil

        Task { @MainActor in
            if takeABackup {
                stage = .savingACopy
                do {
                    let backupURL: URL = try await CoursePageCopier.backingUp(
                        courseDirectoryPath: destinationDirectoryPath,
                        code: destinationFolderCode,
                        coursesDirectoryPath: coursesDirectoryURL.path
                    )
                    backupFileName = backupURL.lastPathComponent
                } catch {
                    // NEVER the file system's own words: the one error that
                    // reaches here carried `/usr/bin/zip`'s stderr and the
                    // word "archive", which is machinery a teacher has never
                    // met.
                    stage = .choosing
                    problem = CopyPageWording.theCopyOfTheCourseCouldNotBeSaved(
                        course: destinationCourse.displayCode
                    )
                    return
                }
            }
            stage = .copying
            let done: CoursePageCopyOutcome = await CoursePageCopier.copying(request)
            outcome = done
            stage = .finished
            workspace.reloadCourses()
            ActivityTrail.note(
                .pagesCopiedFromAnotherCourse,
                CopyPageSheet.trailLine(
                    for: done,
                    fromCourseFolder: sourceFolderName,
                    intoCourse: destinationFolderCode,
                    folder: destinationFolderName,
                    backupNamed: backupFileName
                )
            )
        }
    }

    func copyAnother() {
        outcome = nil
        problem = nil
        shownPlan = nil
        keptLinkedPages = []
        candidates = []
        stage = .choosing
        picker.startOver()
        loadTheSource()
        // The caret is deliberately NOT forced back into the field here.
        // Measured by driving the real app: asking for it while the whole
        // step is being rebuilt put the keyboard ring on the CHEVRON instead,
        // which is worse than no focus at all — typing went nowhere and the
        // ring said it should have worked. Clicking the field works (see the
        // tap target in `SearchablePickerField`), and that is the honest
        // behaviour until the focus can be placed without guessing at when
        // the field joins the responder chain.
    }

    /// The one line the trail keeps: which course the pages came from, where
    /// they went and how many there were.
    ///
    /// Course FOLDER names, because that is what tells last year's ICS4U from
    /// this year's, and the destination folder's name, which is structural
    /// the way `sectionRestored`'s backup file name is. Never a page's title
    /// and never anything from inside a page.
    static func trailLine(
        for outcome: CoursePageCopyOutcome,
        fromCourseFolder sourceFolderName: String,
        intoCourse destinationCode: String,
        folder destinationFolderName: String,
        backupNamed: String?
    ) -> String {
        var line: String = "copied \(outcome.pagesCreated.count) pages"
        line += " and \(outcome.mediaCreated) pictures and files"
        line += " from \(sourceFolderName) into \(destinationCode) → \(destinationFolderName)"
        if outcome.mediaReused > 0 {
            line += "; \(outcome.mediaReused) already there"
        }
        if !outcome.renamed.isEmpty {
            line += "; \(outcome.renamed.count) under a new name"
        }
        if !outcome.skipped.isEmpty {
            line += "; \(outcome.skipped.count) not copied"
        }
        if !outcome.sourceSettingsUnreadable.isEmpty {
            line += "; \(outcome.sourceSettingsUnreadable.count) copied hidden because the settings they came with could not be read"
        }
        if !outcome.couldNotBeRemoved.isEmpty {
            // The one thing in this line that asks the teacher to DO
            // something: a page that could not be proved hidden and could not
            // be taken away again is still in their course.
            line += "; \(outcome.couldNotBeRemoved.count) could not be removed and must not be deployed"
        }
        if let backupNamed {
            line += "; saved \(backupNamed) first"
        }
        return line
    }
}

// MARK: - What a change to the list looks like

/// Compared frame to frame to decide whether the list deserves an animated
/// transition: whether it is shown at all, and which rows are in it.
struct PagePickerListChange: Equatable {

    // MARK: - Stored properties

    let isShown: Bool
    let rowIds: [String]
}

// MARK: - One row

/// The page's name, with the folder it sits in underneath — Russell's
/// "show enough of the path to tell same-named pages apart".
struct PagePickerRow: View {

    // MARK: - Stored properties

    let page: CopyablePage
    let isHighlighted: Bool

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // No trailing `Spacer`, deliberately. A `Spacer` leaves this
            // `Text` an unbounded width proposal, so a long page name renders
            // at its full intrinsic width — wider than the card — and the
            // untruncated width can flash visible during the list's appear
            // transition.
            Text(page.pageName)
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(page.folderName)
                .font(.caption)
                .foregroundStyle(
                    isHighlighted ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary)
                )
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .frame(
            height: SearchablePickerOverlay<CopyablePage, EmptyView>.rowHeight,
            alignment: .leading
        )
        .contentShape(Rectangle())
        .background(isHighlighted ? Color.accentColor : Color.clear)
        .foregroundStyle(isHighlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
    }
}

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
    @State var destinationCode: String = ""
    @State var destinationFolderName: String = ""
    @State var stage: Stage = .choosing

    /// The backup taken before the first write of this sheet session, by its
    /// file name — which is also what is shown at the end and what goes on
    /// the trail.
    @State var backupFileName: String?

    @State var outcome: CoursePageCopyOutcome?
    @State var problem: String?

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

    var destinationFacts: CopyCourseFacts? {
        guard let destinationCourse else {
            return nil
        }
        return CopyCourseFacts.read(from: destinationCourse)
    }

    var destinationFolderNames: [String] {
        return destinationFacts?.sharedFolderNames ?? []
    }

    /// Why Copy is not available right now, or nil.
    var refusal: String? {
        guard let destinationCourse else {
            return CopyPageWording.thereIsNoCourseToCopyInto
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
            destinationFolderName: destinationFolderName
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(CopyPageWording.sheetTitle(course: source.displayCode))
                .font(.headline)

            if stage == .finished, let outcome {
                result(outcome)
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
                    if picker.isShowingSuggestions {
                        picker.dismissSuggestions()
                    } else {
                        picker.noteFocusGained()
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
            .onChange(of: picker.isFieldFocused) {
                if picker.isFieldFocused {
                    picker.noteFocusGained()
                }
            }
        }

        Picker(CopyPageWording.whichCourse, selection: $destinationCode) {
            ForEach(destinations) { candidate in
                Text(candidate.displayCode).tag(candidate.code)
            }
        }
        .accessibilityIdentifier("copyPageDestinationCourse")
        .onChange(of: destinationCode) {
            proposeAFolder()
        }

        Picker(CopyPageWording.whichFolder, selection: $destinationFolderName) {
            ForEach(destinationFolderNames, id: \.self) { name in
                Text(name).tag(name)
            }
        }
        .accessibilityIdentifier("copyPageDestinationFolder")

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
                Text(CopyPageSheet.sentence(for: outcome.skipped[index]))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !outcome.linksLeadingNowhere.isEmpty {
                Text(CopyPageWording.theseLinksWillNotLeadAnywhereYet(
                    names: outcome.linksLeadingNowhere.joined(separator: ", ")
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
                .disabled(stage != .choosing)
                Button("Copy") {
                    copy()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCopy)
                .accessibilityIdentifier("copyPageButton")
            }
        }
    }

    // MARK: - Functions

    /// What a skip reads as. The sentence is chosen here rather than carried
    /// on the skip, so the rule and the wording stay in separate places.
    static func sentence(for skip: CopySkip) -> String {
        switch skip.reason {
        case .aPageOfThatNameIsAlreadyHere:
            return CopyPageWording.aPageOfThatNameIsAlreadyHere(page: skip.name)
        case .theCopyCouldNotBeMadeHidden:
            return CopyPageWording.theCopyCouldNotBeMadeHidden(page: skip.name)
        case .thePicturesCouldNotBePointedAtTheirNewNames:
            return CopyPageWording.thePicturesCouldNotBePointedAtTheirNewNames(page: skip.name)
        case .thePageCouldNotBeRead, .thePageCouldNotBeWritten:
            return CopyPageWording.thePageCouldNotBeWritten(page: skip.name)
        case .aPictureCouldNotBeCopied:
            return CopyPageWording.aPictureCouldNotBeCopied(name: skip.name)
        }
    }

    func loadTheSource() {
        let facts: CopyCourseFacts = CopyCourseFacts.read(from: source)
        sourceFacts = facts
        picker.show(CoursePageCopyPlanner.copyablePages(in: facts))
        if destinationCode.isEmpty, let first = destinations.first {
            destinationCode = first.code
        }
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
                    stage = .choosing
                    problem = error.localizedDescription
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
        stage = .choosing
        picker.clearSelection()
        picker.searchText = ""
        loadTheSource()
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

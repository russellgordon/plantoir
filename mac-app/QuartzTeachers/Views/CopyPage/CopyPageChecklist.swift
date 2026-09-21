import SwiftUI

/// What the copy WILL do, before it does any of it — the screen whose whole
/// purpose is to let a teacher change their mind.
///
/// **Every sentence on it is in the future**, including the skips. It was
/// headed with the result sentence ("Copied 11 pages…") above a Copy button,
/// and it still said "…so it was left as it is" about a page nothing had yet
/// been done to. Each of those has a twin in `CopyPageWording`, keyed
/// separately from the result screen's: the two screens are one word apart and
/// that word is the whole difference.
///
/// **The ROWS come from the first plan; the NUMBERS come from the latest
/// one.** That split is the fix for the fault a teacher met first: the list
/// used to be drawn from the plan, so unticking a page removed its row — and
/// with the row gone there was no way to put it back, or even to see what had
/// been turned off. The candidate set is settled once, in a stable order, and
/// every later plan feeds the header, the size line, the skips and the dead
/// links.
///
/// **A page shown inside another is ticked and cannot be unticked WHILE
/// anything that shows it is ticked**, and becomes an ordinary row when
/// nothing does. Leaving it behind would put a hole in the page that shows
/// it; keeping it locked after that page is gone would be a row a teacher
/// cannot explain.
struct CopyPageChecklist: View {

    // MARK: - Stored properties

    /// Every linked page the FIRST plan found, in its order. The rows.
    let candidates: [CopiedPagePlacement]

    /// The page the teacher named, shown first so the header's count and the
    /// list agree — it said "3 pages" over two rows.
    let chosenPage: String

    /// The latest plan. The numbers and the sentences below the list.
    let plan: CoursePageCopyPlan

    let courseName: String
    let folderName: String

    /// The linked pages still ticked, by lowercased page name.
    @Binding var kept: Set<String>

    // MARK: - Computed properties

    /// Enough for about twelve rows. The largest linked set in a real course
    /// is ten, so nothing today scrolls; the cap is here because a sheet that
    /// grows without limit puts its own buttons off the bottom of the screen.
    static var tallestList: CGFloat {
        return 380
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(CopyPageWording.willCopy(
                pages: plan.pages.count, course: courseName, folder: folderName
            ))

            // An explicit height, never `maxHeight` on a bare `ScrollView`:
            // the first attempt reserved its cap whether the rows needed it
            // or not and drew an empty hole where they should have been.
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 2) {
                    row(named: chosenPage, second: CopyPageWording.thePageYouChose,
                        isOn: .constant(true), isLocked: true, identifier: "chosen")
                    ForEach(candidates) { linked in
                        row(
                            named: linked.pageName,
                            second: secondLine(for: linked),
                            isOn: tick(for: linked),
                            isLocked: isShownInsideSomethingTicked(linked),
                            identifier: linked.pageName
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: min(
                CGFloat(candidates.count + 1) * CopyPageChecklist.rowHeight,
                CopyPageChecklist.tallestList
            ))

            if !plan.media.isEmpty {
                Text(CopyPageWording.willBringPicturesAndFilesInAll(
                    count: plan.mediaToCreate.count,
                    size: ReferenceImportWording.size(plan.totalBytes)
                ))
                .foregroundStyle(.secondary)
            }
            if !plan.mediaUnderANewName.isEmpty {
                Text(CopyPageWording.picturesWillComeInUnderANewName(
                    count: plan.mediaUnderANewName.count
                ))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(plan.skipped.indices, id: \.self) { index in
                Text(CopyPageChecklist.sentence(for: plan.skipped[index]))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !plan.linksLeadingNowhere.isEmpty {
                Text(CopyPageWording.theseLinksWillNotLeadAnywhereYet(
                    names: plan.linksLeadingNowhere
                ))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Text(CopyPageWording.copiesStartHidden)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("copyPageChecklist")
    }

    // MARK: - Functions

    static var rowHeight: CGFloat {
        return 32
    }

    /// One row. The identifier and the label go on the CONTROL, not on the
    /// label view: an identifier bound to a `Toggle`'s content is merged into
    /// the toggle's element and the two overwrite each other — the same trap
    /// `SearchablePickerOverlay`'s own comment records — so every checkbox
    /// reported `copyPageChecklist` and VoiceOver said only "checkbox".
    @ViewBuilder
    func row(
        named name: String, second: String, isOn: Binding<Bool>, isLocked: Bool,
        identifier: String
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                Text(second)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(isLocked)
        .accessibilityLabel(name)
        .accessibilityValue(second)
        .accessibilityIdentifier("copyPageLinked-\(identifier)")
    }

    /// The folder ALWAYS, and the "comes along" note as well — a page that
    /// cannot be unticked is the one row whose landing folder a teacher
    /// cannot influence, so it is the one they most want to see.
    func secondLine(for linked: CopiedPagePlacement) -> String {
        if isShownInsideSomethingTicked(linked) {
            return linked.destinationFolderName + " · "
                + CopyPageWording.embeddedPagesAlwaysComeAlong
        }
        return linked.destinationFolderName
    }

    /// True while any page that SHOWS this one is coming along.
    func isShownInsideSomethingTicked(_ linked: CopiedPagePlacement) -> Bool {
        let key: String = linked.pageName.lowercased()
        guard let showers = plan.pagesThatShowEachPage[key] else {
            return false
        }
        for shower in showers {
            if shower == chosenPage.lowercased() {
                return true
            }
            if kept.contains(shower) {
                return true
            }
        }
        return false
    }

    func tick(for linked: CopiedPagePlacement) -> Binding<Bool> {
        let key: String = linked.pageName.lowercased()
        return Binding(
            get: {
                return isShownInsideSomethingTicked(linked) || kept.contains(key)
            },
            set: { isOn in
                if isOn {
                    kept.insert(key)
                } else {
                    kept.remove(key)
                }
            }
        )
    }

    /// What a skip reads as on THIS screen — in the future, because nothing
    /// has happened yet.
    static func sentence(for skip: CopySkip) -> String {
        switch skip.reason {
        case .aPageOfThatNameIsAlreadyHere:
            return CopyPageWording.willBeLeftAsItIs(page: skip.name)
        case .aClassPageWasLeftAlone:
            return CopyPageWording.aClassPageWillBeLeftAlone(page: skip.name)
        case .anIndexPageIsNotCopied:
            return CopyPageWording.anIndexPageWillNotBeCopied(page: skip.name)
        case .aPageAtTheCourseRootIsNotCopied:
            return CopyPageWording.aPageAtTheCourseRootWillNotBeCopied(page: skip.name)
        case .aPageInsideOneSectionsFolderIsNotCopied:
            return CopyPageWording.aPageInsideOneSectionsFolderWillNotBeCopied(page: skip.name)
        case .thePageCouldNotBeRead:
            return CopyPageWording.thePageCouldNotBeRead(page: skip.name)
        case .thePicturesCouldNotBePointedAtTheirNewNames:
            return CopyPageWording.thePicturesCouldNotBePointedAtTheirNewNames(page: skip.name)
        case .theCopyCouldNotBeMadeHidden, .theCopyIsStillThereAndMustBeRemoved,
             .thePageIsWrittenInAWayPlantoirCannotBeSureOf, .thePageCouldNotBeWritten,
             .aPictureCouldNotBeCopied:
            // Reached only by the executor, so a plan never carries one; the
            // result screen's own sentence is the right one if it ever does.
            return CopyPageSheet.plainSentence(for: skip)
        }
    }
}

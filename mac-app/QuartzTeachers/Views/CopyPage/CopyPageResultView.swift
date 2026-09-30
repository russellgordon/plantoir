import SwiftUI

/// What one press of Copy did — the screen after the checklist.
///
/// **The per-page sentences scroll inside a capped area (#365).** One
/// sentence per skipped page follows the page count exactly as the
/// checklist's did, so after Copy the result screen overflowed the same way
/// and for the same reason. The first sentence, "Copies start hidden", the
/// backup line and Show in Finder stay outside it, so the answer to "did it
/// work?" and the way to go and look are always on the screen.
struct CopyPageResultView: View {

    // MARK: - Stored properties

    let outcome: CoursePageCopyOutcome
    let courseCode: String
    let folderName: String
    let backupFileName: String?
    let folderURL: URL?

    // MARK: - Computed properties

    /// Lower than the checklist's 380, because this screen carries more
    /// fixed lines around its area — the backup sentence and Show in Finder
    /// — and at 380 it measured 612 pt, eight points under the 620 pt rule
    /// (`CopyPageChecklist.tallestSheet`). At 320 it is ≈ 552 pt, which
    /// leaves room for the orange problem line the sheet can add below.
    static var tallestSentenceList: CGFloat {
        return 320
    }

    /// True when there is anything to put in the scroll area — so a copy
    /// with nothing to report leaves no empty region behind.
    var hasSentencesThatGrowWithThePages: Bool {
        if outcome.mediaCreated > 0 || outcome.mediaReused > 0 {
            return true
        }
        if !outcome.renamed.isEmpty || !outcome.skipped.isEmpty {
            return true
        }
        if !outcome.sourceSettingsUnreadable.isEmpty || !outcome.linksLeadingNowhere.isEmpty {
            return true
        }
        return false
    }

    /// The pictures lines, one sentence per skip, the pages whose settings
    /// could not be read, and the links leading nowhere.
    @ViewBuilder
    var sentencesThatGrowWithThePages: some View {
        VStack(alignment: .leading, spacing: 8) {
            if outcome.mediaCreated > 0 {
                Text(CopyPageWording.willBringPicturesAndFiles(
                    count: outcome.mediaCreated,
                    size: ReferenceImportWording.size(outcome.bytesCopied)
                ))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            if outcome.mediaReused > 0 {
                Text(CopyPageWording.picturesAlreadyThere(count: outcome.mediaReused))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !outcome.renamed.isEmpty {
                Text(CopyPageWording.picturesBroughtInUnderANewName(count: outcome.renamed.count))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if outcome.createdNothing {
                Text(CopyPageWording.nothingWasCopied)
            } else {
                Text(CopyPageWording.copiedInto(
                    pages: outcome.pagesCreated.count,
                    course: courseCode,
                    folder: folderName
                ))
                Text(CopyPageWording.copiesStartHidden)
                    .foregroundStyle(.secondary)
            }

            if hasSentencesThatGrowWithThePages {
                CappedScrollArea(cap: CopyPageResultView.tallestSentenceList) {
                    sentencesThatGrowWithThePages
                }
            }

            if let backupFileName {
                Text(CopyPageWording.theBackupTaken(course: courseCode, named: backupFileName))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let folderURL {
                Button("Show in Finder", systemImage: "finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([folderURL])
                }
                .accessibilityIdentifier("copyPageShowInFinder")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        // A container element with its own identifier (#353): without `.contain`
        // SwiftUI applies an identifier on a stack to every element inside it,
        // and the inner identifiers (copyPageShowInFinder) never reach the tree.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("copyPageResult")
    }
}

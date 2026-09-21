import SwiftUI

/// What the copy WILL do, before it does any of it — the screen whose whole
/// purpose is to let a teacher change their mind.
///
/// **Every sentence on it is in the future.** It used to be headed "Copied 11
/// pages into ICS4U, in Concepts." with a Copy button underneath, which is the
/// result sentence shown before the result.
///
/// **And the numbers follow the ticks.** They are read off the plan the host
/// hands over, and the host works that plan out again whenever a tick changes:
/// unticking one page of a real eleven-page set moved them by 67 MB, two files
/// and one dead link, and the screen used to go on showing the old ones.
///
/// A view of its own rather than a method on the sheet, so it can be rendered
/// to an image and looked at without a window, a workspace or a sheet — which
/// is how it was first seen at all.
struct CopyPageChecklist: View {

    // MARK: - Stored properties

    let plan: CoursePageCopyPlan
    let courseName: String
    let folderName: String

    /// The linked pages still ticked, by lowercased page name. A page shown
    /// inside another is not in here and cannot be taken out.
    @Binding var kept: Set<String>

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(CopyPageWording.willCopy(
                pages: plan.pages.count, course: courseName, folder: folderName
            ))

            // **A plain stack, not a `ScrollView`.** The worst real page
            // measured across a whole course brings ten rows, which fits in
            // the sheet; a `ScrollView` reserved its cap whether or not the
            // rows needed it, and — found by rendering this screen to an
            // image and LOOKING at it — drew a 320 pt hole with the rows
            // nowhere in it. A list a teacher cannot see is worse than a
            // sheet that grows, so the rows are drawn and the growth is
            // accepted. `CopyPageChecklist.tallestList` records the number a
            // cap would use if a course ever needs one.
            VStack(alignment: .leading, spacing: 2) {
                ForEach(plan.linkedPages) { linked in
                    Toggle(isOn: tick(for: linked)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(linked.pageName)
                            Text(secondLine(for: linked))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(linked.isRequired)
                    .accessibilityIdentifier("copyPageLinked-\(linked.id)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !plan.media.isEmpty {
                Text(CopyPageWording.willBringPicturesAndFilesInAll(
                    count: plan.mediaToCreate.count,
                    size: ReferenceImportWording.size(plan.totalBytes)
                ))
                .foregroundStyle(.secondary)
            }
            ForEach(plan.skipped.indices, id: \.self) { index in
                Text(CopyPageSheet.plainSentence(for: plan.skipped[index]))
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

    // MARK: - Computed properties

    /// Enough for ten rows, which is the worst real case measured.
    static var tallestList: CGFloat {
        return 320
    }

    // MARK: - Functions

    /// The folder ALWAYS, and the "comes along" note as well — a required
    /// page is the one row whose landing folder a teacher cannot change by
    /// unticking it, so it is the one they most want to see.
    func secondLine(for linked: CopiedPagePlacement) -> String {
        if linked.isRequired {
            return linked.destinationFolderName + " · "
                + CopyPageWording.embeddedPagesAlwaysComeAlong
        }
        return linked.destinationFolderName
    }

    func tick(for linked: CopiedPagePlacement) -> Binding<Bool> {
        let key: String = linked.pageName.lowercased()
        return Binding(
            get: {
                return linked.isRequired || kept.contains(key)
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
}

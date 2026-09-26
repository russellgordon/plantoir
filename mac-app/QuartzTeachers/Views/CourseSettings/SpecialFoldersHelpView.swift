import SwiftUI

/// What Plantoir does with particular folders in THIS course.
///
/// **It names the folders this course actually has, never the rule that finds
/// them.** Saying "any folder whose name mentions the curriculum" invites a
/// teacher to get creative with it, and turns an implementation detail into a
/// promise the product then has to keep. Saying "your expectations live in
/// Ontario Curriculum" tells them the thing they can act on.
///
/// The other reason it is per-course: these answers genuinely differ. One
/// course grades "Tasks", another "Tests" and "Thinking Tasks"; one calls its
/// class folder "All Classes" and another "Lessons".
///
/// **Every name comes from the course's RESOLVED rules, never from a raw
/// configuration key.** `ClassFolder`, `CurriculumFolderRule` and the graded
/// pool below all answer the question the build asks; a key merely records an
/// answer somebody wrote down, and a course can perfectly well have the folder
/// without the key, or the key without the folder.
///
/// The rows, the sentences, the listing grammar and the banned vocabulary are
/// `contracts/shared-rules.json` → `specialFoldersHelp`, run here by
/// `SpecialFoldersHelpTests` and on Windows by
/// `SpecialFoldersHelpContractTests`.
struct SpecialFoldersHelpView: View {

    // MARK: - Stored properties

    /// The button in Course Settings that opens the sheet, the sheet's own
    /// title, and the sentence under it. Named rather than typed where they
    /// are used, so the contract can pin them: a sentence a teacher reads is
    /// shared with Windows, and a quoted copy is the one that keeps passing
    /// after the words change.
    nonisolated static let openedBy: String = "What else does Plantoir use my folders for?"

    /// The button that closes it. The MECHANISM differs — a sheet here, a
    /// dialog on Windows — but the label does not.
    nonisolated static let dismissedBy: String = "Done"

    nonisolated static let title: String = "Folders Plantoir uses"

    nonisolated static let intro: String =
        "Renaming or deleting one of these changes what appears on your site. "
        + "Everything else in your course is yours to arrange however you like."

    /// What the curriculum row says when the course has no curriculum folder
    /// at all. The single piece of text in this sheet allowed to describe
    /// rather than name, and only in that one case.
    nonisolated static let noCurriculumFolderYet: String = "Your curriculum folder"

    /// The coverage row's explanation, for one map page and for several.
    nonisolated static let coverageWhy: String =
        "Do not write your own page with this name — it is replaced "
        + "each time, so anything you put there would be lost."

    nonisolated static let coverageWhyForSeveral: String =
        "Do not write your own pages with these names — they are replaced "
        + "each time, so anything you put there would be lost."

    /// What a list of names reads as when there are none.
    nonisolated static let noneChosen: String = "None chosen"

    let course: Course

    @Environment(\.dismiss) private var dismiss

    // MARK: - Computed properties

    /// One row per thing a teacher can break by renaming it in Obsidian.
    var entries: [SpecialFolderEntry] {
        var rows: [SpecialFolderEntry] = []

        rows.append(SpecialFolderEntry(
            name: SpecialFoldersHelpView.listed(ClassFolder.names(for: course)),
            what: "Your lessons",
            why: "Each day's class page lives here. Plantoir puts new classes in "
                + "this folder, keeps them in date order, and uses them to work "
                + "out which pages your course actually teaches."
        ))

        // **The folders the build maps, not the names the course happens to
        // have recorded (#128).** A course can have several curriculum
        // folders, each with a coverage map of its own, and this row names
        // every one — found the way the build finds them: the folders the
        // course declares (`curriculum_folders`, then the legacy
        // `curriculum_folder`) that hold an expectation page on disk, or, when
        // none does, the one folder the old scan finds. While no folder holds
        // a page yet, it names the one folder the by-name rule gives, so a new
        // course is still told where its expectations go.
        //
        // Before #128 this was decided by NAME alone, and on a course keeping
        // both an "Ontario Curriculum" and a "College Board Curriculum" folder
        // it named College Board (alphabetically first) while the map was
        // built from Ontario — measured on this Mac on 2026-09-06, on two real
        // courses. Reading the disk, as the build does, is what closed it
        // (`contracts/shared-rules.json` → `specialNames.curriculumFoldersResolution`).
        //
        // A recorded name the course no longer has is never shown: a name a
        // teacher cannot find is worse than the placeholder, because it looks
        // like an answer.
        let resolvedCurriculum: [String] = CurriculumFolderRule.resolvedFolders(for: course)
        let curriculumName: String
        if !resolvedCurriculum.isEmpty {
            curriculumName = SpecialFoldersHelpView.listed(resolvedCurriculum)
        } else {
            curriculumName = SpecialFoldersHelpView.noCurriculumFolderYet
        }
        // One explanation, whichever name the row carries. A course with no
        // expectations needs to hear the same thing about what they are for,
        // and the sentence the placeholder branch used to add — "in a folder
        // whose name mentions the curriculum" — published the matching rule in
        // plain words, which is the exact thing naming a course's own folders
        // exists to avoid.
        rows.append(SpecialFolderEntry(
            name: curriculumName,
            what: "Your curriculum expectations",
            why: "One page per expectation. The curriculum map is built from "
                + "these — without them there is nothing to measure your "
                + "lessons against, and the map is left out."
        ))

        // "The curriculum map" here, "the curriculum coverage map" in
        // GradedFolderWording.caption — a DELIBERATE mixed state, not drift to
        // be tidied up. The caption follows the control it captions, this
        // sheet keeps the name it has always had, and
        // contracts/shared-rules.json -> gradedFolders.wording.why says so.
        rows.append(SpecialFolderEntry(
            name: SpecialFoldersHelpView.listed(gradedFolderNames),
            what: "Work that counts for marks",
            why: "The curriculum map shows an expectation as evaluated when a "
                + "page in one of these addresses it. You choose these above."
        ))

        rows.append(SpecialFolderEntry(
            name: "Media",
            what: "Images and files you add to pages",
            why: "Plantoir looks after this one itself and keeps it out of your "
                + "sidebar. If it goes missing, pictures stop appearing on your "
                + "site."
        ))

        rows.append(SpecialFolderEntry(
            name: "index.md",
            what: "The page a folder opens on",
            why: "Every section has one, and so does each folder. It is the way "
                + "in, not a lesson."
        ))

        rows.append(SpecialFolderEntry(
            name: "Key Links.md",
            what: "The shortcuts in your sidebar",
            why: "Plantoir adds the curriculum map to this list when it builds "
                + "your site. Your own copy is left exactly as you wrote it."
        ))

        // Every map page the course has (#128), primary first — so a teacher
        // with two maps knows both names they must not write.
        let mapTitles: [String] = coveragePageTitles
        rows.append(SpecialFolderEntry(
            name: mapTitles.isEmpty
                ? CurriculumFolderRule.primaryMapTitle
                : SpecialFoldersHelpView.listed(mapTitles),
            what: "Written for you, every time you build",
            why: mapTitles.count > 1
                ? SpecialFoldersHelpView.coverageWhyForSeveral
                : SpecialFoldersHelpView.coverageWhy
        ))

        return rows
    }

    /// The title of every coverage map this course has, from the disk.
    var coveragePageTitles: [String] {
        let configuration: CourseConfiguration = course.configuration
        return CurriculumFolderRule.coveragePageTitles(
            declared: configuration.curriculumFolders,
            in: configuration.sharedFolders,
            withPages: CurriculumFolderRule.foldersWithPages(for: course)
        )
    }

    /// The graded folders as a teacher would say them, including the case where
    /// they have never been asked and Plantoir is still working it out.
    var gradedFolderNames: [String] {
        if let chosen = course.configuration.gradedFolders {
            return chosen
        }
        return GradedFolderRule.inferredPool(
            from: course.configuration.sharedFolders
                + course.configuration.perSectionFolders
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(SpecialFoldersHelpView.title)
                    .font(.title2).bold()
                Text(SpecialFoldersHelpView.intro)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.name)
                                .font(.headline)
                            Text(entry.what)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(entry.why)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Button(SpecialFoldersHelpView.dismissedBy) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 560)
    }

    // MARK: - Functions

    /// Several folder names, said the way a person would say them.
    static func listed(_ names: [String]) -> String {
        var kept: [String] = []
        for name in names {
            if !name.isEmpty {
                kept.append(name)
            }
        }
        if kept.isEmpty {
            return noneChosen
        }
        if kept.count == 1 {
            return kept[0]
        }
        return kept.dropLast().joined(separator: ", ") + " and " + (kept.last ?? "")
    }
}

/// One row of the help sheet.
struct SpecialFolderEntry: Identifiable {

    // MARK: - Stored properties

    let name: String
    let what: String
    let why: String

    // MARK: - Computed properties

    var id: String { return name + what }
}

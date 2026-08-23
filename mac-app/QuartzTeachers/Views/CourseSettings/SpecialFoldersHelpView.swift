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
struct SpecialFoldersHelpView: View {

    // MARK: - Stored properties

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

        if let curriculum = course.configuration.curriculumFolder, !curriculum.isEmpty {
            rows.append(SpecialFolderEntry(
                name: curriculum,
                what: "Your curriculum expectations",
                why: "One page per expectation. The curriculum map is built from "
                    + "these — without them there is nothing to measure your "
                    + "lessons against, and the map is left out."
            ))
        } else {
            rows.append(SpecialFolderEntry(
                name: "Your curriculum folder",
                what: "Your curriculum expectations",
                why: "One page per expectation, in a folder whose name mentions "
                    + "the curriculum. The curriculum map is built from these."
            ))
        }

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

        rows.append(SpecialFolderEntry(
            name: "Curriculum Coverage",
            what: "Written for you, every time you build",
            why: "Do not write your own page with this name — it is replaced "
                + "each time, so anything you put there would be lost."
        ))

        return rows
    }

    /// The graded folders as a teacher would say them, including the case where
    /// they have never been asked and Plantoir is still working it out.
    var gradedFolderNames: [String] {
        if let chosen = course.configuration.gradedFolders {
            return chosen
        }
        var counted: [String] = []
        for folder in course.configuration.sharedFolders
            + course.configuration.perSectionFolders {
            if folder.lowercased().contains("task") && !counted.contains(folder) {
                counted.append(folder)
            }
        }
        return counted
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Folders Plantoir uses")
                    .font(.title2).bold()
                Text("Renaming or deleting one of these changes what appears on "
                     + "your site. Everything else in your course is yours to "
                     + "arrange however you like.")
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
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 560)
    }

    // MARK: - Functions

    /// Several folder names, said the way a person would say them.
    static func listed(_ names: [String]) -> String {
        let kept: [String] = names.filter { name in return !name.isEmpty }
        if kept.isEmpty {
            return "None chosen"
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

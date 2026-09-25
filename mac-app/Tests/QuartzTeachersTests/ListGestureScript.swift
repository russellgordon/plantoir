import Foundation
import SwiftUI
@testable import QuartzTeachers

/// The lists a gesture can land on — the twelve on-screen folder and file
/// lists of Course Settings and the New Course wizard, named by what they
/// hold rather than by the view that draws them.
enum GestureList {
    case sharedFolders
    case sharedFiles
    case perSectionFolders
    case perSectionFiles
}

/// What a teacher can DO to the folder and file lists, independent of how the
/// lists are drawn.
///
/// Issue #266 redrew every one of these lists as a table. The redraw must not
/// change a byte of what is saved, so the same fixed script of gestures is run
/// through the code as it was (captured once, into `Tests/Goldens/266-*.json`,
/// before any of the redraw was written) and through the code as it is now
/// (`ListTableGoldenTests`). Each side supplies its own adapter; the script,
/// the fixture and the serialisation are this file, shared by both, so the
/// only thing that can differ between the two runs is the code under test.
@MainActor
protocol ListGestureAdapter {

    /// Ticks (or unticks) Hide in the site's sidebar for one item.
    func setHidden(_ item: String, to isHidden: Bool)

    /// Ticks (or unticks) Expandable in the site's sidebar for one item.
    func setExpandable(_ item: String, to isExpandable: Bool)

    /// Ticks (or unticks) one folder in the marks list — the gesture a
    /// teacher makes, which a protected folder may refuse.
    func setCountsForMarks(_ folder: String, to counts: Bool)

    /// Asks to remove one name from a list, and confirms the question if
    /// one is asked. A blocked name stays.
    func remove(_ item: String, from list: GestureList)

    /// Types a name into a list's add control and submits it.
    func add(typing typedName: String, to list: GestureList)
}

/// The fixture and the fixed script for the Course Settings golden.
@MainActor
enum CourseSettingsGestureScript {

    // MARK: - Functions

    /// A disposable ICS3U-shaped course under the temporary directory — never
    /// a real working folder (issue #240).
    ///
    /// Chosen to reach every path the redraw could disturb: `graded_folders`
    /// ABSENT, so the first marks tick materialises the pool; a `hidden`
    /// member no list shows (`Media`), which a tick must preserve; a name in
    /// BOTH the shared and the per-section folders (`Tasks`), which the
    /// sidebar table shows once; a nested `Portfolios/Tasks` on disk, which
    /// the marks list offers; and a curriculum folder with coverage on, so
    /// removing it is blocked.
    static func makeCourse(in root: URL) throws -> Course {
        let courseURL: URL = root.appendingPathComponent("courses").appendingPathComponent("ICS3U")
        let folders: [String] = [
            "section1/All Classes", "section1/Tasks", "Concepts", "Curriculum", "Tasks", "Tests",
            "Portfolios/Tasks",
        ]
        for folder in folders {
            try FileManager.default.createDirectory(
                at: courseURL.appendingPathComponent(folder), withIntermediateDirectories: true
            )
        }
        let configuration: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Introduction to Computer Science",
            "section_numbers": [1],
            "num_sections": 1,
            "shared_folders": ["Concepts", "Curriculum", "Tasks", "Tests"],
            "shared_files": ["Learning Goals.md"],
            "per_section_folders": ["All Classes", "Tasks"],
            "per_section_files": ["index.md", "Announcements.md"],
            "hidden": ["Media", "Tasks"],
            "expandable": ["Concepts"],
            "include_curriculum_coverage": true,
            "curriculum_folder": "Curriculum",
        ]
        let data: Data = try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted, .sortedKeys])
        let configURL: URL = courseURL.appendingPathComponent("course_config.json")
        try data.write(to: configURL)
        let loaded: CourseConfiguration = try CourseConfiguration(contentsOf: configURL)
        return Course(code: "ICS3U", directoryURL: courseURL, configuration: loaded)
    }

    /// The fixed script. Every gesture is one a teacher can make in Course
    /// Settings; the comments say which path of the code each one reaches.
    static func run(through gestures: ListGestureAdapter) {
        // Sidebar visibility: a tick, an untick, the duplicated name, a file.
        gestures.setHidden("Concepts", to: true)
        gestures.setHidden("Tasks", to: false)
        gestures.setExpandable("Tasks", to: true)
        gestures.setHidden("Learning Goals.md", to: true)
        gestures.setExpandable("Concepts", to: false)

        // Marks: the first tick materialises the inferred pool.
        gestures.setCountsForMarks("Tests", to: true)
        gestures.setCountsForMarks("Concepts", to: true)
        gestures.setCountsForMarks("Concepts", to: false)

        // A graded folder: consequential, confirmed. Leaves the pool with
        // one folder, and drops Tests from it.
        gestures.remove("Tests", from: .sharedFolders)
        // The last graded folder with coverage on: blocked, nothing changes.
        gestures.setCountsForMarks("Tasks", to: false)
        // Blocked removals: the class folder, the curriculum folder, the
        // section index page.
        gestures.remove("All Classes", from: .perSectionFolders)
        gestures.remove("Curriculum", from: .sharedFolders)
        gestures.remove("index.md", from: .perSectionFiles)

        // Adding: `.md` appended to a file, the reserved name refused, a
        // name already there ignored.
        gestures.add(typing: "Field Trips", to: .sharedFiles)
        gestures.add(typing: "media", to: .sharedFolders)
        gestures.add(typing: "Tasks", to: .sharedFolders)
        gestures.add(typing: "  Labs  ", to: .perSectionFolders)

        // An ordinary removal and its re-add: the `excluded_items` round trip.
        gestures.remove("Concepts", from: .sharedFolders)
        gestures.add(typing: "Concepts", to: .sharedFolders)
        gestures.remove("Announcements.md", from: .perSectionFiles)
        gestures.remove("Learning Goals.md", from: .sharedFiles)

        // Ticks on names that arrived by the gestures above.
        gestures.setHidden("Field Trips.md", to: true)
        gestures.setExpandable("Labs", to: true)
        gestures.setHidden("All Classes", to: true)
    }

    /// The list editor exactly as `CourseSettingsView` builds it for that
    /// list — the same binding, closures and protection — so a gesture
    /// through it runs what the page runs. Shared by both adapters, since the
    /// editor's initialiser did not change.
    static func editor(for list: GestureList, of view: CourseSettingsView) -> StringListEditorView {
        let configuration: CourseConfiguration = view.course.configuration
        switch list {
        case .sharedFolders:
            return StringListEditorView(
                title: "Shared folders (all sections)",
                items: Binding(
                    get: { return configuration.sharedFolders },
                    set: { newValue in configuration.sharedFolders = newValue }
                ),
                onRemove: { name in view.folderWasRemoved(name, scope: .shared) },
                onAdd: { name in view.folderWasAdded(name, scope: .shared) },
                protection: view.sharedFolderProtection,
                noticeAfterChange: { name, change in
                    return view.noticeAfterFolderChange(name, change: change, scope: .shared)
                }
            )
        case .sharedFiles:
            return StringListEditorView(
                title: "Shared files (all sections)",
                hidesMarkdownExtension: true,
                items: Binding(
                    get: { return configuration.sharedFiles },
                    set: { newValue in configuration.sharedFiles = newValue }
                ),
                onRemove: { name in view.fileWasRemoved(name, scope: .shared) },
                onAdd: { name in view.fileWasAdded(name, scope: .shared) }
            )
        case .perSectionFolders:
            return StringListEditorView(
                title: "Per-section folders",
                items: Binding(
                    get: { return configuration.perSectionFolders },
                    set: { newValue in configuration.perSectionFolders = newValue }
                ),
                onRemove: { name in view.folderWasRemoved(name, scope: .perSection) },
                onAdd: { name in view.folderWasAdded(name, scope: .perSection) },
                protection: view.perSectionFolderProtection,
                noticeAfterChange: { name, change in
                    return view.noticeAfterFolderChange(name, change: change, scope: .perSection)
                }
            )
        case .perSectionFiles:
            return StringListEditorView(
                title: "Per-section files",
                hidesMarkdownExtension: true,
                items: Binding(
                    get: { return configuration.perSectionFiles },
                    set: { newValue in configuration.perSectionFiles = newValue }
                ),
                onRemove: { name in view.fileWasRemoved(name, scope: .perSection) },
                onAdd: { name in view.fileWasAdded(name, scope: .perSection) },
                protection: view.perSectionFileProtection
            )
        }
    }

    /// The bytes Save writes for this course, as text.
    static func savedFile(for course: Course, in root: URL) throws -> String {
        let outputURL: URL = root.appendingPathComponent("saved-course_config.json")
        try course.configuration.write(to: outputURL)
        return try String(contentsOf: outputURL, encoding: .utf8)
    }
}

/// The five lists the wizard keeps before a course exists — the wizard's
/// state, held outside a view so a script can change it and read it back.
@MainActor
final class WizardListState {

    // MARK: - Stored properties

    var sharedFolders: [String] = WizardDefaults.sharedFolders
    var sharedFiles: [String] = WizardDefaults.sharedFiles
    var perSectionFolders: [String] = WizardDefaults.perSectionFolders
    var perSectionFiles: [String] = WizardDefaults.perSectionFiles
    var gradedFolders: [String] = ["Tasks"]

    // MARK: - Functions

    /// ICS4U, declining its ready-made pages and keeping the skeleton, with
    /// the factory lists on screen: the curriculum pages and coverage map
    /// stay on (#251), so the last-graded-folder block is live.
    ///
    /// A wizard showing exactly these lists, so its protection rules and its
    /// Create output are asked about the current state. A SwiftUI `@State`
    /// cannot be changed from outside a view on screen, so a fresh wizard is
    /// made from these lists whenever it is asked something.
    func wizard() -> NewCourseWizardView {
        return NewCourseWizardView(
            courseCode: "ICS4U",
            prepopulatesExampleContent: false,
            startsFromSkeleton: true,
            includesCurriculumPages: true,
            includesCurriculumCoverage: true,
            sharedFolders: sharedFolders,
            sharedFiles: sharedFiles,
            perSectionFolders: perSectionFolders,
            perSectionFiles: perSectionFiles,
            gradedFolders: gradedFolders
        )
    }

    /// What the wizard's `onRemove` does for a folder list:
    /// `reconcileGradedFolders()`, asked of the lists as they now are.
    func reconcileGradedFolders() {
        gradedFolders = NewCourseWizardView.reconciledGradedFolders(
            from: gradedFolders, validChoices: wizard().gradedFolderChoices
        )
    }
}

extension WizardListState {

    // MARK: - Functions

    /// The list editor exactly as the wizard builds it for that list, over
    /// this state instead of the wizard's `@State`.
    func editor(for list: GestureList) -> StringListEditorView {
        switch list {
        case .sharedFolders:
            return StringListEditorView(
                title: "Shared folders",
                items: Binding(
                    get: { return self.sharedFolders },
                    set: { newValue in self.sharedFolders = newValue }
                ),
                onRemove: { _ in self.reconcileGradedFolders() },
                protection: { folder in return self.wizard().wizardSharedFolderProtection(for: folder) }
            )
        case .sharedFiles:
            return StringListEditorView(
                title: "Shared files",
                hidesMarkdownExtension: true,
                items: Binding(
                    get: { return self.sharedFiles },
                    set: { newValue in self.sharedFiles = newValue }
                )
            )
        case .perSectionFolders:
            return StringListEditorView(
                title: "Per-section folders",
                items: Binding(
                    get: { return self.perSectionFolders },
                    set: { newValue in self.perSectionFolders = newValue }
                ),
                onRemove: { _ in self.reconcileGradedFolders() },
                protection: { folder in return self.wizard().wizardPerSectionFolderProtection(for: folder) }
            )
        case .perSectionFiles:
            return StringListEditorView(
                title: "Per-section files",
                hidesMarkdownExtension: true,
                items: Binding(
                    get: { return self.perSectionFiles },
                    set: { newValue in self.perSectionFiles = newValue }
                ),
                protection: { file in return self.wizard().wizardPerSectionFileProtection(for: file) }
            )
        }
    }

    /// The wizard's marks binding, over this state.
    var gradedFoldersBinding: Binding<[String]> {
        return Binding(
            get: { return self.gradedFolders },
            set: { newValue in self.gradedFolders = newValue }
        )
    }
}

/// The fixed script for the wizard golden.
@MainActor
enum WizardGestureScript {

    // MARK: - Functions

    static func run(through gestures: ListGestureAdapter) {
        // Marks: tick, untick the default, then the last one (blocked).
        gestures.setCountsForMarks("Examples", to: true)
        gestures.setCountsForMarks("Tasks", to: false)
        gestures.setCountsForMarks("Examples", to: false)

        // Removals: ordinary, blocked (class folder), blocked (last graded
        // folder), blocked (section index page), consequential confirmed.
        gestures.remove("Tutorials", from: .sharedFolders)
        gestures.remove("All Classes", from: .perSectionFolders)
        gestures.remove("Examples", from: .sharedFolders)
        gestures.remove("index.md", from: .perSectionFiles)
        gestures.setCountsForMarks("Recaps", to: true)
        gestures.remove("Examples", from: .sharedFolders)

        // Adding.
        gestures.add(typing: "Field Trips", to: .sharedFiles)
        gestures.add(typing: "Media", to: .sharedFolders)
        gestures.add(typing: "Labs", to: .perSectionFolders)
        gestures.add(typing: "Concepts", to: .sharedFolders)
    }

    /// What Create would write, serialised the way the #248 goldens are.
    static func createdFile(from state: WizardListState) throws -> String {
        let dictionary: [String: Any] = state.wizard().buildConfigurationDictionary(
            code: "ICS4U", name: "Golden Course"
        )
        let data: Data = try JSONSerialization.data(
            withJSONObject: dictionary, options: [.sortedKeys, .prettyPrinted]
        )
        return String(data: data, encoding: .utf8) ?? ""
    }
}

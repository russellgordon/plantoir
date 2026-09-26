import Foundation

/// Whether the website builder on this Mac can reach a working folder (#290).
///
/// The builder runs in a virtual machine that is handed the home folder and
/// nothing else, so a working folder outside it — on an external drive, in
/// `/Users/Shared`, under `/private/tmp` — cannot produce a website. Since
/// #221 the launchers refuse such a folder at the first preview; this is the
/// app refusing it at the moment a window takes it on (chosen in the picker,
/// or reopened at launch), before anything is written into it.
///
/// **Inside** means the folder's canonical path — `FolderIdentity.canonicalPath`,
/// the same disk spelling the launchers get from `/bin/pwd -P` — equals the
/// canonical home or lies under it, compared by whole folder names. The same
/// test is applied to `<folder>/courses` when that is a link, because
/// `courses` is what the launcher actually hands the virtual machine.
///
/// Measured on 2026-09-26 (plans/290-plan.md §0): iCloud Drive and
/// `~/Library/CloudStorage/*` are inside; `/Volumes/Macintosh HD/Users/…` is
/// inside, because `/Volumes/Macintosh HD` is a link to `/` — which is why a
/// "refuse anything under /Volumes" rule was rejected; external drives,
/// `/Users/Shared` and `/private/tmp` are outside.
nonisolated enum WorkingFolderReach {

    // MARK: - Types

    /// Which of the two paths leads outside.
    enum WhichPath: String, Equatable, Sendable {
        case workingFolder
        case coursesFolder
    }

    /// A folder the builder cannot reach, and why.
    struct Refusal: Equatable, Sendable {
        let folderPath: String
        let folderName: String
        let whichPath: WhichPath
    }

    // MARK: - Stored properties

    /// Replaces the home folder the check compares against — for tests,
    /// which point it at a throwaway `home/` beside a throwaway `outside/`.
    /// Nil in the product.
    nonisolated(unsafe) static var homeFolderOverride: URL?

    // MARK: - Computed properties

    /// The home folder the builder is handed.
    ///
    /// Under the unit suite this is the TEMPORARY directory, not a switch
    /// that lets everything through: every fixture folder is made there, so
    /// every `chooseWorkspace` a test makes still runs the real comparison
    /// and passes it honestly. (`RealHome.forFiles` would not do: it is a
    /// folder INSIDE the temporary directory, and the fixtures are beside
    /// it, not in it.)
    static var homeFolder: URL {
        if let homeFolderOverride {
            return homeFolderOverride
        }
        if RealHome.isInsideTestBundle {
            return FileManager.default.temporaryDirectory
        }
        return RealHome.forFiles
    }

    // MARK: - Functions

    /// The pure half: whether one canonical path lies inside another.
    ///
    /// Compared name by name, as bytes. `String.hasPrefix` is grapheme-based
    /// and was measured to answer false for `/Users/ann/` + a name that
    /// begins with a combining mark (the mark fuses with the slash), which
    /// would be a false refusal with no way round it; and a plain prefix
    /// would call `/Users/ann2` inside `/Users/ann`.
    static func isInside(canonicalFolderPath folder: String, canonicalHomePath home: String) -> Bool {
        let folderNames: [[UInt8]] = WorkingFolderReach.names(in: folder)
        let homeNames: [[UInt8]] = WorkingFolderReach.names(in: home)
        if folderNames.count < homeNames.count {
            return false
        }
        var index: Int = 0
        while index < homeNames.count {
            if folderNames[index] != homeNames[index] {
                return false
            }
            index += 1
        }
        return true
    }

    /// A path's folder names as bytes, skipping the empty ones a leading or
    /// trailing slash leaves.
    static func names(in path: String) -> [[UInt8]] {
        var result: [[UInt8]] = []
        var current: [UInt8] = []
        for byte in path.utf8 {
            if byte == UInt8(ascii: "/") {
                if !current.isEmpty {
                    result.append(current)
                    current = []
                }
            } else {
                current.append(byte)
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    /// The live half: nil when the builder can reach the folder, otherwise
    /// why not.
    ///
    /// `courses` is checked when it is a LINK, read with the link's own
    /// attributes rather than `fileExists`, which follows links — a
    /// `courses` link to a drive that is not plugged in would otherwise
    /// read as absent and pass. An ordinary `courses` folder inside an
    /// inside folder is inside by definition, and a missing one is fine
    /// (an empty folder being set up has none yet).
    static func refusal(forFolder url: URL, homeFolder: URL = WorkingFolderReach.homeFolder) -> Refusal? {
        // A folder that is not there is not this check's to judge: the disk
        // cannot be asked its spelling, so the answer would be about the
        // TEXT (`/var/…` rather than `/private/var/…`), and a missing folder
        // has its own sentence on the reopening route.
        if !FileManager.default.fileExists(atPath: url.path) {
            return nil
        }
        let canonicalHome: String = FolderIdentity.canonicalPath(homeFolder.path)
        let canonicalFolder: String = FolderIdentity.canonicalPath(url.path)
        if !isInside(canonicalFolderPath: canonicalFolder, canonicalHomePath: canonicalHome) {
            return Refusal(folderPath: url.path, folderName: url.lastPathComponent, whichPath: .workingFolder)
        }
        let coursesPath: String = url.appendingPathComponent("courses").path
        guard let destination = WorkingFolderReach.linkDestination(atPath: coursesPath) else {
            return nil
        }
        // The link's target, made absolute against the folder it sits in,
        // then asked of the disk. A target that cannot be opened (a drive not
        // plugged in) comes back as its text, and its text is outside too.
        var target: String = destination
        if !destination.hasPrefix("/") {
            target = url.appendingPathComponent(destination).path
        }
        let canonicalCourses: String = FolderIdentity.canonicalPath(target)
        if !isInside(canonicalFolderPath: canonicalCourses, canonicalHomePath: canonicalHome) {
            return Refusal(folderPath: url.path, folderName: url.lastPathComponent, whichPath: .coursesFolder)
        }
        return nil
    }

    /// Where a link points, or nil when the path is not a link.
    static func linkDestination(atPath path: String) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return nil
        }
        guard let type = attributes[FileAttributeKey.type] as? FileAttributeType,
              type == FileAttributeType.typeSymbolicLink else {
            return nil
        }
        return try? FileManager.default.destinationOfSymbolicLink(atPath: path)
    }
}

/// What a teacher is told about a folder the builder cannot reach. The one
/// home for these sentences; `contracts/shared-rules.json` →
/// `workingFolderReach.wording` is generated to match and pinned by a test.
nonisolated enum WorkingFolderReachWording {

    // MARK: - Stored properties

    /// Word for word the clause in `app-rules.json` → `failureExplanations`
    /// ("bind source path does not exist"), which the launchers also say: a
    /// teacher meets one piece of advice whether it comes from the picker,
    /// the app's explanation of a failed preview, or the command line. A
    /// test pins it against both.
    static let sharedClause: String = "inside your home folder — on your Desktop or in Documents, for example — and not on an external drive or in a shared location"

    static let whatToDo: String = "Keep your working folder " + sharedClause + ", then choose it again."

    static let whatToDoForCourses: String = "Keep your working folder and the courses in it " + sharedClause + ", then choose it again."

    static let alertOKButton: String = "OK"

    // MARK: - Functions

    /// The headline for a folder chosen in the picker.
    static func headline(folderName: String) -> String {
        return "Plantoir cannot build websites from “\(folderName)”, because it is not inside your home folder."
    }

    /// The headline for a folder chosen in the picker whose `courses` link
    /// leads outside — the folder itself IS in the home folder, and saying
    /// otherwise would be the one untrue sentence in the message.
    static func coursesHeadline(folderName: String) -> String {
        return "Plantoir cannot build websites from “\(folderName)”, because the courses in it are not inside your home folder."
    }

    /// Everything said about a chosen folder, in the order it is shown.
    static func sentences(for refusal: WorkingFolderReach.Refusal) -> (headline: String, whatToDo: String) {
        switch refusal.whichPath {
        case .workingFolder:
            return (headline(folderName: refusal.folderName), whatToDo)
        case .coursesFolder:
            return (coursesHeadline(folderName: refusal.folderName), whatToDoForCourses)
        }
    }
}

import Foundation

/// Answers one question for the new-course wizard: does ready-made example
/// content exist for a course code? The content itself lives in the bundled
/// `support/example_content/<CODE>/` folders — one per course code, each
/// with a `manifest.json` — and is installed by the real setup wizard, not
/// by the app. The app only needs to know whether to offer it.
enum ExampleContentCatalog {

    // MARK: - Functions

    /// The bundled manifest for a course code, or nil when no example
    /// content exists for it. Lookup is case-insensitive, matching how
    /// course codes are normalized everywhere else.
    static func manifestURL(forCode code: String) -> URL? {
        let normalized: String = code.trimmingCharacters(in: .whitespaces).uppercased()
        if normalized.isEmpty {
            return nil
        }
        return Bundle.main.url(
            forResource: "manifest",
            withExtension: "json",
            subdirectory: "support/example_content/\(normalized)"
        )
    }

    /// True when example content is bundled for this course code.
    static func hasContent(forCode code: String) -> Bool {
        return manifestURL(forCode: code) != nil
    }

    /// The curriculum folder name defined in the manifest, or nil when none is defined.
    static func curriculumFolder(forCode code: String) -> String? {
        guard let url = manifestURL(forCode: code) else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        guard let decoded = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        guard let manifest = decoded as? [String: Any] else {
            return nil
        }
        return manifest["curriculum_folder"] as? String
    }

    /// True when the example content for this code includes the official
    /// curriculum pages — the wizard only shows the curriculum toggle when
    /// there are curriculum pages to include.
    static func includesCurriculum(forCode code: String) -> Bool {
        guard let folderName = curriculumFolder(forCode: code) else {
            return false
        }
        return !folderName.isEmpty
    }

    /// Which folders count for marks in a course made from this code's
    /// ready-made pages: the manifest's own pool, reconciled against the
    /// payload's folders exactly as the command line does it — or nil when
    /// no payload is bundled for the code or its manifest cannot be read.
    ///
    /// The wizard writes this into the `course_config.json` it creates for
    /// a pre-populated course, because setup runs over that saved file and
    /// never works the pool out for itself when one exists (GitHub issue
    /// #292, `contracts/shared-rules.json` → `gradedFolders.newCourse`).
    static func marksPool(forCode code: String) -> [String]? {
        guard let url = manifestURL(forCode: code) else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        guard let decoded = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        guard let manifest = decoded as? [String: Any] else {
            return nil
        }
        return marksPool(fromManifest: manifest)
    }

    /// The marks pool a payload manifest gives a new course — a mirror of
    /// `setup_course.graded_folders_for` as setup calls it for a payload,
    /// kept to it by `gradedFolders.newCourse.manifestCases`.
    ///
    /// The folders are the shared ones without `Media` (setup never makes
    /// that a shared folder), then the per-section ones. When the manifest
    /// declares `graded_folders`, each declared name is kept as written if
    /// it names a folder exactly, respelled to the folder's own spelling if
    /// it names one only ignoring case, and dropped otherwise; blanks,
    /// nulls, non-names and repeats go too, and a declared null or empty
    /// list gives an empty pool. Only when the key is ABSENT is the
    /// historical rule applied to the folders.
    ///
    /// Deliberately NOT `GradedFolderRule.reconciled`: that reconciles a
    /// teacher's own ticks and matches exactly, while this reproduces what
    /// the command line writes for the same payload, which matches
    /// ignoring case.
    nonisolated static func marksPool(fromManifest manifest: [String: Any]) -> [String] {
        let sharedFolders: [String] = manifest["shared_folders"] as? [String] ?? []
        let perSectionFolders: [String] = manifest["per_section_folders"] as? [String] ?? []

        var courseFolders: [String] = []
        for folder in sharedFolders {
            if folder != "Media" {
                courseFolders.append(folder)
            }
        }
        for folder in perSectionFolders {
            courseFolders.append(folder)
        }

        guard let declaredValue = manifest["graded_folders"] else {
            return GradedFolderRule.inferredPool(from: courseFolders)
        }
        // A declared null (NSNull) reads as an empty declaration, as
        // Python's `manifest.get(...) or []` does. Other malformed shapes —
        // a pool that is a string or an object, a number whose text names a
        // folder — cannot pass `lint_payload.py`, and this mirror does not
        // follow Python into them: it reads them as empty or drops them.
        let declaredEntries: [Any] = declaredValue as? [Any] ?? []

        // A later folder with the same name ignoring case wins the
        // spelling, as it does in Python's dictionary built the same way.
        var spellingIgnoringCase: [String: String] = [:]
        for folder in courseFolders {
            if folder.isEmpty {
                continue
            }
            spellingIgnoringCase[folder.lowercased()] = folder
        }

        var pool: [String] = []
        for entry in declaredEntries {
            guard let declaredName = entry as? String else {
                continue
            }
            if declaredName.isEmpty {
                continue
            }
            var folderName: String? = nil
            if courseFolders.contains(declaredName) {
                folderName = declaredName
            } else if let respelled = spellingIgnoringCase[declaredName.lowercased()] {
                folderName = respelled
            }
            guard let matchedFolder = folderName else {
                continue
            }
            if !pool.contains(matchedFolder) {
                pool.append(matchedFolder)
            }
        }
        return pool
    }

    /// The jurisdiction name for the example content, e.g. "Ontario" or "British Columbia".
    static func jurisdictionName(forCode code: String) -> String {
        guard let url = manifestURL(forCode: code) else {
            return "Ontario"
        }
        guard let data = try? Data(contentsOf: url) else {
            return "Ontario"
        }
        guard let decoded = try? JSONSerialization.jsonObject(with: data) else {
            return "Ontario"
        }
        guard let manifest = decoded as? [String: Any] else {
            return "Ontario"
        }
        if let explicit = manifest["jurisdiction_name"] as? String, !explicit.isEmpty {
            return explicit
        }
        if let jurisdiction = manifest["jurisdiction"] as? String {
            if jurisdiction.uppercased() == "BC" {
                return "British Columbia"
            }
            if jurisdiction.uppercased() == "ON" {
                return "Ontario"
            }
            return jurisdiction
        }
        return "Ontario"
    }
}

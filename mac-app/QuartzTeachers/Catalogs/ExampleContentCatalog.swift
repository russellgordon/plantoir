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

    /// True when the example content for this code includes the official
    /// curriculum pages — the wizard only shows the curriculum toggle when
    /// there are curriculum pages to include.
    static func includesCurriculum(forCode code: String) -> Bool {
        guard let url = manifestURL(forCode: code) else {
            return false
        }
        guard let data = try? Data(contentsOf: url) else {
            return false
        }
        guard let decoded = try? JSONSerialization.jsonObject(with: data) else {
            return false
        }
        guard let manifest = decoded as? [String: Any] else {
            return false
        }
        guard let folderName = manifest["curriculum_folder"] as? String else {
            return false
        }
        return !folderName.isEmpty
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

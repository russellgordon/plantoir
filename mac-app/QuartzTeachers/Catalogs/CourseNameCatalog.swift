import Foundation

/// Looks up Ontario course names by course code, using the same
/// `ontario_secondary_courses.json` the command-line wizard consults
/// (bundled as an app resource). The wizard offers a formal name and a
/// short name for known codes; the app does the same.
enum CourseNameCatalog {

    // MARK: - Stored properties

    static let entries: [String: CourseNames] = loadEntries()

    // MARK: - Functions

    /// The known names for a course code, or nil for unknown codes
    /// (including club codes). Lookup is case-insensitive, matching the
    /// wizard's behaviour of uppercasing the code first.
    static func names(forCode code: String) -> CourseNames? {
        let normalized: String = code.trimmingCharacters(in: .whitespaces).uppercased()
        return entries[normalized]
    }

    /// The name a new course starts with when its code is recognised, or
    /// nil for a code the lookup does not know.
    ///
    /// It is the SHORT name. The formal name is the ministry's string —
    /// "Introduction to Computer Science, Grade 11, U" — which is correct
    /// and which almost nobody wants on a website: it is what a teacher
    /// then has to delete before typing what they actually call the
    /// course. The short name is closer to that in nearly every case, and
    /// the formal one is still a single button away for the teacher who
    /// wants it. Defaulting to the longer string only to have it thrown
    /// away is the wrong way round.
    static func defaultName(forCode code: String) -> String? {
        return names(forCode: code)?.short
    }

    private static func loadEntries() -> [String: CourseNames] {
        var result: [String: CourseNames] = [:]
        let catalogFiles: [String] = [
            "ontario_secondary_courses",
            "british_columbia_secondary_courses"
        ]
        for fileName in catalogFiles {
            guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else {
                continue
            }
            guard let data = try? Data(contentsOf: url) else {
                continue
            }
            guard let decoded = try? JSONSerialization.jsonObject(with: data) else {
                continue
            }
            guard let dictionary = decoded as? [String: Any] else {
                continue
            }

            for (code, rawEntry) in dictionary {
                guard let entry = rawEntry as? [String: Any] else {
                    continue
                }
                guard let formalName = entry["formal_name"] as? String else {
                    continue
                }
                guard let shortName = entry["short_name"] as? String else {
                    continue
                }
                result[code] = CourseNames(formal: formalName, short: shortName)
            }
        }
        return result
    }
}

/// The two name variants the lookup file offers for each course code.
struct CourseNames: Equatable {

    // MARK: - Stored properties

    let formal: String
    let short: String
}

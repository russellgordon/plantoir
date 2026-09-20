import Foundation

/// One row in a province's course catalog — what the new-course wizard's
/// code picker searches and browses.
struct CourseCatalogEntry: Identifiable, Equatable {

    // MARK: - Stored properties

    let code: String
    let shortName: String
    let formalName: String

    /// "ON" or "BC".
    let province: String

    // MARK: - Computed properties

    var id: String { return province + ":" + code }

    /// Whether Plantoir ships ready-made pages for this code — the same
    /// question `ExampleContentCatalog` answers everywhere else in the
    /// wizard, asked here so the picker can mark it.
    var hasExampleContent: Bool {
        return ExampleContentCatalog.hasContent(forCode: code)
    }
}

/// The two province course lists the new-course wizard's code picker
/// offers, so a teacher who doesn't already know course codes can find
/// one by typing what the course is called instead.
///
/// Reads the same `ontario_secondary_courses.json` and
/// `british_columbia_secondary_courses.json` files `CourseNameCatalog`
/// reads for names, loaded again here WITH which province each code
/// belongs to — `CourseNameCatalog` merges both files into one
/// code-only lookup and has no reason to keep the provinces apart, but
/// a picker that offers "Ontario" or "British Columbia" does.
enum CourseCatalog {

    // MARK: - Stored properties

    static let ontarioEntries: [CourseCatalogEntry] = loadEntries(
        fileName: "ontario_secondary_courses", province: "ON"
    )
    static let britishColumbiaEntries: [CourseCatalogEntry] = loadEntries(
        fileName: "british_columbia_secondary_courses", province: "BC"
    )

    // MARK: - Functions

    static func entries(forProvince province: String) -> [CourseCatalogEntry] {
        if province == "BC" {
            return britishColumbiaEntries
        }
        return ontarioEntries
    }

    static func provinceName(forCode province: String) -> String {
        if province == "BC" {
            return "British Columbia"
        }
        return "Ontario"
    }

    /// Entries from one province's catalog matching `query` against
    /// code, short name, and formal name (case-insensitive substring) —
    /// codes the query PREFIXES lead the list, so typing "sch" surfaces
    /// SCH3U and SCH4U before some unrelated course whose formal name
    /// merely mentions chemistry. An empty query returns the whole
    /// catalog alphabetically by code, for browsing rather than
    /// searching. Capped at `limit`, since Ontario alone lists nearly
    /// 2,000 codes.
    static func matching(_ query: String, inProvince province: String, limit: Int) -> [CourseCatalogEntry] {
        let allEntries: [CourseCatalogEntry] = entries(forProvince: province)
        let trimmed: String = query.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            var sorted: [CourseCatalogEntry] = allEntries.sorted { firstEntry, secondEntry in
                return firstEntry.code < secondEntry.code
            }
            if sorted.count > limit {
                sorted = Array(sorted.prefix(limit))
            }
            return sorted
        }

        let needle: String = trimmed.uppercased()
        var codeStartsWithMatches: [CourseCatalogEntry] = []
        var otherMatches: [CourseCatalogEntry] = []
        for entry in allEntries {
            if entry.code.hasPrefix(needle) {
                codeStartsWithMatches.append(entry)
                continue
            }
            let matchesElsewhere: Bool = entry.code.contains(needle)
                || entry.shortName.uppercased().contains(needle)
                || entry.formalName.uppercased().contains(needle)
            if matchesElsewhere {
                otherMatches.append(entry)
            }
        }
        codeStartsWithMatches.sort { firstEntry, secondEntry in
            return firstEntry.code < secondEntry.code
        }
        otherMatches.sort { firstEntry, secondEntry in
            return firstEntry.code < secondEntry.code
        }

        var combined: [CourseCatalogEntry] = []
        combined.append(contentsOf: codeStartsWithMatches)
        combined.append(contentsOf: otherMatches)
        if combined.count > limit {
            combined = Array(combined.prefix(limit))
        }
        return combined
    }

    private static func loadEntries(fileName: String, province: String) -> [CourseCatalogEntry] {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else {
            return []
        }
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        guard let decoded = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        guard let dictionary = decoded as? [String: Any] else {
            return []
        }

        var result: [CourseCatalogEntry] = []
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
            result.append(CourseCatalogEntry(
                code: code,
                shortName: shortName,
                formalName: formalName,
                province: province
            ))
        }
        return result
    }
}

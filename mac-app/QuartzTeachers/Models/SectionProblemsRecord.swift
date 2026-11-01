import Foundation

/// A section's record of its problems, as the build left it (#717):
/// `<builds root>/<COURSE>/section<N>/.problems.json`, written by the shared
/// Python (`scripts/section_problems.py`) and read here, never written.
///
/// The format is `contracts/shared-rules.json` → `sectionProblems.file`.
/// Read with `JSONSerialization` and tolerant of anything missing, the way
/// every other file the build writes is read here: a record this app cannot
/// read is no record, never a crash.
nonisolated struct SectionProblemsRecord: Equatable, Sendable {

    // MARK: - Stored properties

    /// The name of the file beside the section's built site.
    static let fileName: String = ".problems.json"

    /// The only version this app reads.
    static let version: Int = 1

    let course: String
    let section: Int
    let buildId: String
    let builtAt: Date?
    /// `preview` or `deploy` — which kind of build wrote it.
    let occasion: String
    let rows: [SectionProblemRow]
    /// The pages the build showed, by place in the course folder.
    let pagesShown: [String]
    let newIDs: [String]
    let goneIDs: [String]
    let siteSaidComplete: Bool
    /// What an answer to the alert is remembered by (`sectionProblems.alert`).
    let alertKey: String

    // MARK: - Computed properties

    /// Whether this build met a problem new since the build before it.
    var hasNewProblems: Bool {
        return !newIDs.isEmpty
    }

    /// Whether the set changed at all — new or gone.
    var setChanged: Bool {
        return !newIDs.isEmpty || !goneIDs.isEmpty
    }

    // MARK: - Functions

    /// Where a section's record is: the section's built output, reached
    /// through the course's `.merged_output` link (the place
    /// `PreviewedPageSource.listURL` reads `.page-sources.json` from).
    static func url(courseFolder: URL, sectionNumber: Int) -> URL {
        return courseFolder
            .appendingPathComponent(BuildOutputLocation.linkName)
            .appendingPathComponent("section\(sectionNumber)")
            .appendingPathComponent(SectionProblemsRecord.fileName)
    }

    /// The record at `url`, or nil when there is none this app can read.
    static func read(_ url: URL) -> SectionProblemsRecord? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return SectionProblemsRecord.parse(data)
    }

    /// The record in `data`, or nil.
    static func parse(_ data: Data) -> SectionProblemsRecord? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard (object["version"] as? Int) == SectionProblemsRecord.version,
              let rowObjects = object["rows"] as? [[String: Any]] else {
            return nil
        }
        var rows: [SectionProblemRow] = []
        for rowObject in rowObjects {
            if let row = SectionProblemRow(rowObject) {
                rows.append(row)
            }
        }
        let changed: [String: Any] = (object["changed"] as? [String: Any]) ?? [:]
        let buildId: String = (object["buildId"] as? String) ?? ""
        return SectionProblemsRecord(
            course: (object["course"] as? String) ?? "",
            section: (object["section"] as? Int) ?? 0,
            buildId: buildId,
            builtAt: SectionProblemsRecord.date(object["builtAt"]),
            occasion: (object["occasion"] as? String) ?? "preview",
            rows: rows,
            pagesShown: (object["pagesShown"] as? [String]) ?? [],
            newIDs: (changed["new"] as? [String]) ?? [],
            goneIDs: (changed["gone"] as? [String]) ?? [],
            siteSaidComplete: (object["siteSaidComplete"] as? Bool) ?? false,
            alertKey: (object["alertKey"] as? String) ?? buildId
        )
    }

    /// A time the build wrote (UTC, ISO 8601), or nil.
    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else {
            return nil
        }
        let formatter: ISO8601DateFormatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    /// The kind an id names: everything before its first `|` or `#`.
    static func kind(ofID id: String) -> String {
        var kind: String = ""
        for character in id {
            if character == "|" || character == "#" {
                break
            }
            kind.append(character)
        }
        return kind
    }
}

/// One problem a build of a section met (`sectionProblems.file.fields`).
nonisolated struct SectionProblemRow: Equatable, Hashable, Identifiable, Sendable {

    // MARK: - Stored properties

    let id: String
    let kind: String
    /// The page by its place in the course folder, or empty for a
    /// whole-section or whole-course problem.
    let page: String
    /// The item's reason key, or empty.
    let reason: String
    /// The one piece of the folder problem's list that names this item.
    let item: String
    let sentence: String
    let detail: String
    let fixable: Bool
    /// One bounded line for an outside assistant (717b).
    let prompt: String
    /// `build`, `site` or `deploy`: which writer owns it.
    let source: String
    let firstSeen: Date?
    let lastSeen: Date?
    /// True when the build that wrote the record did not check it.
    let carried: Bool

    // MARK: - Initializer

    init?(_ object: [String: Any]) {
        guard let id = object["id"] as? String, !id.isEmpty else {
            return nil
        }
        self.id = id
        self.kind = (object["kind"] as? String) ?? SectionProblemsRecord.kind(ofID: id)
        self.page = (object["page"] as? String) ?? ""
        self.reason = (object["reason"] as? String) ?? ""
        self.item = (object["item"] as? String) ?? ""
        self.sentence = (object["sentence"] as? String) ?? ""
        self.detail = (object["detail"] as? String) ?? ""
        self.fixable = (object["fixable"] as? Bool) ?? false
        self.prompt = (object["prompt"] as? String) ?? ""
        self.source = (object["from"] as? String) ?? "build"
        self.firstSeen = SectionProblemsRecord.date(object["firstSeen"])
        self.lastSeen = SectionProblemsRecord.date(object["lastSeen"])
        self.carried = (object["carried"] as? Bool) ?? false
    }

    init(id: String, kind: String, page: String, reason: String = "", source: String = "build") {
        self.id = id
        self.kind = kind
        self.page = page
        self.reason = reason
        self.item = ""
        self.sentence = ""
        self.detail = ""
        self.fixable = false
        self.prompt = ""
        self.source = source
        self.firstSeen = nil
        self.lastSeen = nil
        self.carried = false
    }
}

/// The build's word that a section's record changed (`sectionProblems.marker`):
/// counts only, never a row.
nonisolated struct SectionProblemsMarker: Equatable, Sendable {

    // MARK: - Stored properties

    static let prefix: String = "PLANTOIR_PROBLEMS:"

    let course: String
    let section: Int
    let buildId: String
    let alertKey: String
    let rows: Int
    let new: Int
    let gone: Int

    // MARK: - Functions

    /// Every marker in `text`, read from the prefix onward (#153's rule:
    /// half a line glued in front of it does not hide it).
    static func markers(in text: String) -> [SectionProblemsMarker] {
        var found: [SectionProblemsMarker] = []
        for line in SiteHealthFinding.linesOf(text) {
            guard let prefixRange = line.range(of: SectionProblemsMarker.prefix) else {
                continue
            }
            let payload: String = String(line[prefixRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let course = object["course"] as? String,
                  let section = object["section"] as? Int else {
                continue
            }
            let buildId: String = (object["buildId"] as? String) ?? ""
            found.append(SectionProblemsMarker(
                course: course,
                section: section,
                buildId: buildId,
                alertKey: (object["alertKey"] as? String) ?? buildId,
                rows: (object["rows"] as? Int) ?? 0,
                new: (object["new"] as? Int) ?? 0,
                gone: (object["gone"] as? Int) ?? 0
            ))
        }
        return found
    }
}

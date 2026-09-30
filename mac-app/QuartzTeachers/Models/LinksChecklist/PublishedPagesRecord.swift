import Foundation

/// What has been on a site students could reach, per section (#379): the
/// fragments `deploy.py` and `deploy.sh`'s folder branch write after each
/// destination succeeded, in `courses/<CODE>/.publish_state/section<N>.published-pages/`
/// (`contracts/file-formats.json` → `publishedPagesRecord`).
///
/// **Why a record and not a date on the page.** A date is on 7,114 of the
/// 7,118 payload pages that carry a publish flag, so "has a date" cannot mean
/// "was published" (`class-planning.json` → `datingPagesAClassBrings.
/// publishedBeforeIsRecorded`). A page this record lists keeps its date when
/// it is published again — from the links checklist and from the assistant's
/// publish alike (Russell's decision 4; the plan's Q5).
nonisolated enum PublishedPagesRecord {

    // MARK: - Functions

    static func folderURL(courseDirectory: URL, section: Int) -> URL {
        return courseDirectory
            .appendingPathComponent(".publish_state")
            .appendingPathComponent("section\(section).published-pages", isDirectory: true)
    }

    /// Every place any fragment lists — the union. An unreadable fragment is
    /// skipped rather than trusted.
    static func places(courseDirectory: URL, section: Int) -> Set<String> {
        var found: Set<String> = []
        let folder: URL = folderURL(courseDirectory: courseDirectory, section: section)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return found
        }
        for name in names where name.hasSuffix(".json") && !name.hasPrefix(".") {
            let url: URL = folder.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            for entry in (object["places"] as? [Any]) ?? [] {
                if let place = entry as? String {
                    found.insert(place.precomposedStringWithCanonicalMapping)
                }
            }
        }
        return found
    }

    /// Whether a page is in the record — matched by its file ending in the
    /// recorded place, which is its path inside the course folder.
    static func lists(_ fileURL: URL, in places: Set<String>) -> Bool {
        if places.isEmpty {
            return false
        }
        let path: String = fileURL.standardizedFileURL.path.precomposedStringWithCanonicalMapping
        for place in places {
            if path.hasSuffix("/" + place + ".md") {
                return true
            }
        }
        return false
    }

    /// Sets the record aside at a rollover (`publishedPagesRecord.
    /// releasedWhenASectionRollsOver`): every fragment moves into
    /// `section<N>.published-pages.previous-<stamp>/`, beside the folder, and
    /// the folder itself STAYS, so the rollover's undo can write the
    /// fragments back where they were. Returns the files for that undo.
    ///
    /// On EVERY rollover, whichever website answer the teacher gave (plan
    /// review, finding 12): a new year's site has published nothing yet,
    /// so the pages Get Ready hid take this year's class dates.
    static func release(courseDirectory: URL, section: Int, at moment: Date = Date()) -> [AssistSavedFile] {
        var saved: [AssistSavedFile] = []
        // Last year's answers to the links checklist go too
        // (`linksChecklistAnswered`: removed on rollover).
        let answered: URL = LinksChecklistAnswered.fileURL(courseDirectory: courseDirectory, section: section)
        if let contents = try? String(contentsOf: answered, encoding: .utf8),
           (try? FileManager.default.removeItem(at: answered)) != nil {
            saved.append(AssistSavedFile(fileURL: answered, before: contents, after: nil))
        }
        let folder: URL = folderURL(courseDirectory: courseDirectory, section: section)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return saved
        }
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let kept: URL = folder.deletingLastPathComponent().appendingPathComponent(
            "section\(section).published-pages.previous-" + formatter.string(from: moment), isDirectory: true
        )
        for name in names.sorted() where name.hasSuffix(".json") && !name.hasPrefix(".") {
            let from: URL = folder.appendingPathComponent(name)
            let to: URL = kept.appendingPathComponent(name)
            guard let contents = try? String(contentsOf: from, encoding: .utf8) else {
                continue
            }
            do {
                try FileManager.default.createDirectory(at: kept, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: from, to: to)
            } catch {
                continue
            }
            saved.append(AssistSavedFile(fileURL: from, before: contents, after: nil))
            saved.append(AssistSavedFile(fileURL: to, before: nil, after: contents))
        }
        return saved
    }
}

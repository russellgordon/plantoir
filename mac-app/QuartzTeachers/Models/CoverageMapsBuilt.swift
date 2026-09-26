import Foundation

/// The curriculum coverage maps a build wrote, as the build reported them
/// (#128).
///
/// A course can have one map per curriculum folder, so "my College Board map
/// is missing" is a question somebody will ask. Every build whose section
/// wants the map prints one `PLANTOIR_MAPS: {json}` line naming the maps it
/// wrote — including none — and this reads it so the answer is on the
/// activity trail. The line is machinery: the console a teacher reads leaves
/// it out (`BuildMarkerLine`), and the build prints a plain sentence per map
/// above it. `contracts/shared-rules.json` → `coverageMapsBuilt`.
struct CoverageMapsBuilt: Equatable {

    // MARK: - Stored properties

    struct Map: Equatable {
        let title: String
        let folder: String
        let expectations: Int
    }

    let course: String
    let section: Int
    let maps: [Map]

    /// The marker the build prints. Pinned by
    /// `contracts/shared-rules.json` → `coverageMapsBuilt.marker.prefix`.
    nonisolated static let markerPrefix: String = "PLANTOIR_MAPS:"

    // MARK: - Computed properties

    /// The trail line, in the shape `coverageMapsBuilt.trailLine` gives: the
    /// count first, then each map as a teacher would say it — its title, the
    /// folder it came from, and how many expectations it shows.
    nonisolated var trailSentence: String {
        if maps.isEmpty {
            return "the build made no curriculum map: no curriculum folder holds an expectation page"
        }
        var described: [String] = []
        for map in maps {
            let noun: String = map.expectations == 1 ? "expectation" : "expectations"
            described.append("\(map.title) from \(map.folder) (\(map.expectations) \(noun))")
        }
        let count: String = maps.count == 1 ? "1 curriculum map" : "\(maps.count) curriculum maps"
        return "the build made \(count): " + described.joined(separator: ", ")
    }

    // MARK: - Functions

    /// Every report in a stretch of output, read as it arrives and from the
    /// prefix onward — the way `PagesDatedByTheBuild.reports(in:)` reads its
    /// own line, and for the same reason: a marker glued to the tail of
    /// somebody else's half line must still be read (#153).
    nonisolated static func reports(in text: String) -> [CoverageMapsBuilt] {
        var found: [CoverageMapsBuilt] = []
        for line in SiteHealthFinding.linesOf(text) {
            guard let prefixRange = line.range(of: markerPrefix) else {
                continue
            }
            let payload: String = String(line[prefixRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let course = object["course"] as? String,
                  let section = object["section"] as? Int,
                  let entries = object["maps"] as? [[String: Any]] else {
                continue
            }
            var maps: [Map] = []
            for entry in entries {
                guard let title = entry["title"] as? String,
                      let folder = entry["folder"] as? String,
                      let expectations = entry["expectations"] as? Int else {
                    continue
                }
                maps.append(Map(title: title, folder: folder, expectations: expectations))
            }
            found.append(CoverageMapsBuilt(course: course, section: section, maps: maps))
        }
        return found
    }

    /// Every report in `text`, on the activity trail. Called by the console
    /// reader of a run the app starts (`ScriptRunner`) and by the scheduled
    /// publish's log reader (`ScheduledDeploy.recordFolderProblems`) — the
    /// build nobody watches is the one this line is likeliest to be asked
    /// about.
    nonisolated static func noteOnTheTrail(from text: String) {
        for report in reports(in: text) {
            ActivityTrail.note(
                .coverageMapsBuilt, report.trailSentence,
                course: report.course, section: report.section
            )
        }
    }
}

/// Whether a line of console output is one of the build's machine-readable
/// lines — ANY of them: `PLANTOIR_` then capital letters or underscores and a
/// colon, anywhere in the line (#128).
///
/// Each marker used to be hidden by its own name, so a NEW marker printed by
/// the shared Python reached every teacher's console as raw JSON until each
/// app learned it — what `PLANTOIR_DATED:` still does on Windows (#279). One
/// rule for every marker closes that for the next one.
/// `contracts/shared-rules.json` → `transcriptStripping.machineLines`.
enum BuildMarkerLine {

    // MARK: - Functions

    nonisolated static func isMachineLine(_ line: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: "PLANTOIR_[A-Z_]+:") else {
            return false
        }
        let whole: NSRange = NSRange(line.startIndex..<line.endIndex, in: line)
        return expression.firstMatch(in: line, range: whole) != nil
    }
}

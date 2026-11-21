import Foundation

/// Which Netlify record a deploy of a section would read right now: the
/// ONE question that decides which record is the section's website (#899
/// U3b; the review of U3b's fixes, round three). `deploy.py`'s rule exactly
/// (`load_netlify_marker`): a current record (`.netlify_sites/section<N>.json`)
/// that parses wins; else a legacy record in the built output
/// (`.merged_output/section<N>/.netlify_site.json`) that parses, which a
/// deploy would migrate; else none (a deploy starts a new website). The
/// raw values are the contract's words (`undo.netlifyRecordCases`).
nonisolated enum NetlifyRecordADeployReads: String, Equatable, Sendable {
    case current
    case legacy
    case none
}

/// The legacy Netlify record in a section's built output
/// (`.merged_output/section<N>/.netlify_site.json`), brought into the
/// working folder before a rollover's step (#899 U3b, Russell's rulings of
/// 2026-11-20). Its own file because its writes are NOT a step and never
/// will be (`UndoWriterScanTests`: notAStep): the built output is outside
/// the working folder, where no step can name a place, and the bring-in is
/// the change a deploy's own migration makes (`load_netlify_marker`).
extension DeployCommand {

    // MARK: - Stored properties

    /// A test stops the bring-in right after a record's bytes are written
    /// beside their place and before the rename, as a process that died
    /// there would (the hook may truncate the file, as a death mid-write
    /// leaves it); true stops it. Nil in the app.
    nonisolated(unsafe) static var bringInDiesAfterWriting: ((URL) -> Bool)?

    // MARK: - Types

    /// Why a rollover could not bring the legacy Netlify marker into the
    /// working folder (`moveTheLegacyMarkerIn`): it could not be read,
    /// written in its new place or removed from the old one. The rollover
    /// is refused before anything of it is changed, and this is what is
    /// said after "Nothing was changed:".
    struct LegacyMarkerNotMovedIn: Error, LocalizedError, Equatable {

        // MARK: - Stored properties

        /// The legacy marker, as a teacher would find it.
        let legacyName: String

        /// Where it was to go, as a teacher would find it.
        let placeName: String

        // MARK: - Computed properties

        var errorDescription: String? {
            return "the website record “\(legacyName)” could not be moved to “\(placeName)”."
        }
    }

    /// The families of LEFTOVER a bring-in makes in `.netlify_sites`: files
    /// no deploy reads (deploy.py reads `section<N>.json` by its exact
    /// name), set aside by the rollover's step as `setAside` ops, never one
    /// of the section's website records.
    nonisolated enum LeftoverFamily: String, CaseIterable, Sendable {
        /// An old-format record from the built output that no deploy would
        /// read: a current record wins, or it is not JSON.
        case fromBuiltOutput = "from-built-output"
        /// A current record no deploy can read (it is not JSON), moved out
        /// of the way so a good legacy record can take its place, as a
        /// deploy's own migration would write over it.
        case unreadable = "unreadable"
    }

    /// What a bring-in that a refused step could not wholly undo left
    /// moved (`LegacyMarkerBroughtIn.putBack`).
    nonisolated struct LegacyMarkerNotPutBack: Equatable, Sendable {

        // MARK: - Stored properties

        /// Where the legacy record's bytes still are in the working folder,
        /// or nil when it is back in the built output.
        let recordStillAt: URL?

        /// Where a current record no deploy could read still is, set aside,
        /// or nil when it is back in its place (or there was none).
        let unreadableStillAt: URL?
    }

    /// What `moveTheLegacyMarkerIn` did, so a rollover whose step is then
    /// refused can put it back and "Nothing was changed" stays true
    /// (`putBack`), or, when that cannot be done, say what moved.
    nonisolated struct LegacyMarkerBroughtIn: Equatable, Sendable {

        // MARK: - Stored properties

        /// Where the legacy marker was, in the built output.
        let legacyURL: URL

        /// Where its bytes are now, in `.netlify_sites`: the current
        /// record's place, or a leftover's. Nil when the legacy marker was
        /// only REMOVED, because a record already in the working folder says
        /// the same (a migration that stopped before its removal, finished).
        let placeURL: URL?

        /// The current record's place.
        let currentURL: URL

        /// Where a current record no deploy could read was moved to free
        /// its place for the legacy record, or nil.
        let unreadableSetAsideAt: URL?

        /// Its bytes.
        let bytes: Data

        /// Whether this bring-in made the `.netlify_sites` folder.
        let madeTheFolder: Bool

        // MARK: - Computed properties

        /// The legacy marker, as a teacher would find it.
        var legacyName: String {
            return ".merged_output/" + DeployCommand.nameForTeacher(legacyURL)
        }

        // MARK: - Functions

        /// Puts the legacy marker back in the built output, and a current
        /// record set aside back in its place, for a step that was then
        /// REFUSED (nothing of it made). Never over anything, and only while
        /// its new place still holds exactly these bytes. The `.netlify_sites`
        /// folder this bring-in made is removed when it is empty again (the
        /// review of U3b's fixes, LOW 6). Nil when everything went back;
        /// otherwise what is still moved.
        func putBack() -> LegacyMarkerNotPutBack? {
            let everythingStillMoved: LegacyMarkerNotPutBack = LegacyMarkerNotPutBack(
                recordStillAt: placeURL, unreadableStillAt: unreadableSetAsideAt
            )
            if FileManager.default.fileExists(atPath: legacyURL.path) {
                return everythingStillMoved
            }
            if !DeployCommand.placeWhole(bytes, at: legacyURL) {
                return everythingStillMoved
            }
            if let placeURL {
                guard let there = try? Data(contentsOf: placeURL), there == bytes,
                      (try? FileManager.default.removeItem(at: placeURL)) != nil else {
                    try? FileManager.default.removeItem(at: legacyURL)
                    return everythingStillMoved
                }
            }
            if let unreadableSetAsideAt, !UndoSwap.renameExclusively(unreadableSetAsideAt, onto: currentURL) {
                return LegacyMarkerNotPutBack(recordStillAt: nil, unreadableStillAt: unreadableSetAsideAt)
            }
            if madeTheFolder {
                DeployCommand.removeIfEmpty(currentURL.deletingLastPathComponent())
            }
            return nil
        }
    }

    // MARK: - Functions: which record a deploy reads

    /// The current Netlify record's place, `.netlify_sites/section<N>.json`.
    nonisolated static func currentNetlifyRecordURL(forSection sectionNumber: Int, in courseDirectory: URL) -> URL {
        return courseDirectory
            .appendingPathComponent(".netlify_sites")
            .appendingPathComponent("section\(sectionNumber).json")
    }

    /// What a record's bytes parse to as `deploy.py` reads them
    /// (`json.loads(path.read_text(encoding="utf-8"))`), or nil when they
    /// do not parse: strict UTF-8, no byte order mark (Python's `json`
    /// refuses one), any JSON value, `null` included (NSNull). Known to
    /// differ only on what no tool writes: Python also takes `NaN` and
    /// `Infinity`, and numbers too large for a double (documentation 09).
    nonisolated static func parsedRecord(_ data: Data) -> NSObject? {
        if data.count >= 3 && data[data.startIndex] == 0xEF
            && data[data.startIndex + 1] == 0xBB && data[data.startIndex + 2] == 0xBF {
            return nil
        }
        if String(data: data, encoding: .utf8) == nil {
            return nil
        }
        guard let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        return parsed as? NSObject
    }

    /// Which record a deploy of the section would read now
    /// (`NetlifyRecordADeployReads`): `load_netlify_marker`, read for read.
    /// A place that holds something that cannot be read counts as not
    /// parsing, as Python's `except Exception` takes it.
    static func netlifyRecordADeployReads(forSection sectionNumber: Int, in course: Course) -> NetlifyRecordADeployReads {
        let currentURL: URL = currentNetlifyRecordURL(forSection: sectionNumber, in: course.directoryURL)
        if FileManager.default.fileExists(atPath: currentURL.path),
           let data = try? Data(contentsOf: currentURL), parsedRecord(data) != nil {
            return .current
        }
        let legacyURL: URL = legacyMarkerURL(forSection: sectionNumber, in: course)
        if FileManager.default.fileExists(atPath: legacyURL.path),
           let data = try? Data(contentsOf: legacyURL), parsedRecord(data) != nil {
            return .legacy
        }
        return .none
    }

    // MARK: - Functions: leftovers

    /// A leftover's name: `section<N>.<family>.json`, then
    /// `section<N>.<family>.<k>.json` for k from 2.
    nonisolated static func leftoverName(_ family: LeftoverFamily, forSection sectionNumber: Int, number: Int) -> String {
        if number <= 1 {
            return "section\(sectionNumber).\(family.rawValue).json"
        }
        return "section\(sectionNumber).\(family.rawValue).\(number).json"
    }

    /// The first leftover name of the family that is free, so a leftover
    /// already there never stops a rollover (the review of U3b's fixes,
    /// LOW 5).
    static func nextFreeLeftoverURL(_ family: LeftoverFamily, forSection sectionNumber: Int, in course: Course) -> URL {
        let folder: URL = course.directoryURL.appendingPathComponent(".netlify_sites")
        var number: Int = 1
        while true {
            let url: URL = folder.appendingPathComponent(leftoverName(family, forSection: sectionNumber, number: number))
            if !FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            number += 1
        }
    }

    /// Every leftover of the section in `.netlify_sites`, of every family,
    /// by name: never a kept copy (`….previous-<stamp>.json`).
    static func leftoverURLs(forSection sectionNumber: Int, in course: Course) -> [URL] {
        let folder: URL = course.directoryURL.appendingPathComponent(".netlify_sites")
        let entries: [String] = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        var leftovers: [URL] = []
        for entry in entries where isALeftoverName(entry, forSection: sectionNumber) {
            leftovers.append(folder.appendingPathComponent(entry))
        }
        return leftovers
    }

    /// Whether a name in `.netlify_sites` is one of the section's leftovers.
    nonisolated static func isALeftoverName(_ name: String, forSection sectionNumber: Int) -> Bool {
        for family in LeftoverFamily.allCases {
            let start: String = "section\(sectionNumber).\(family.rawValue)."
            guard name.hasPrefix(start), name.hasSuffix(".json") else {
                continue
            }
            let middle: String = String(name.dropFirst(start.count).dropLast(".json".count))
            if middle.isEmpty {
                return true
            }
            if let number = Int(middle), number >= 2, String(number) == middle {
                return true
            }
        }
        return false
    }

    /// The name a leftover is kept under when the rollover's step sets it
    /// aside: `.previous-<stamp>` before its `.json`. A current record no
    /// deploy can read is kept as `section<N>.unreadable.previous-<stamp>.json`.
    static func keptLeftoverURL(_ leftoverURL: URL, forSection sectionNumber: Int, stamp: String) -> URL {
        var base: String = String(leftoverURL.lastPathComponent.dropLast(".json".count))
        if leftoverURL.lastPathComponent == "section\(sectionNumber).json" {
            base = "section\(sectionNumber).\(LeftoverFamily.unreadable.rawValue)"
        }
        return leftoverURL.deletingLastPathComponent().appendingPathComponent(base + ".previous-" + stamp + ".json")
    }

    // MARK: - Functions: bringing the legacy record in

    /// Brings the LEGACY Netlify marker out of the built output into the
    /// working folder, before a rollover's step is planned (#899 U3b,
    /// Russell's rulings of 2026-11-20), so the step can name it like any
    /// other record and an Undo puts it back whole. Decided by ONE question,
    /// which record a deploy reads now (`netlifyRecordADeployReads`), so a
    /// deploy reads the same website before the rollover and after its Undo
    /// in every state (the review of U3b's fixes, round three, MEDIUM 1):
    ///
    /// - **the legacy record** (no current record that parses, the legacy
    ///   one does): it IS the section's website. It is written in the current
    ///   record's place (its bytes, mode 0600) and removed from the built
    ///   output, as a deploy's migration does. A current record there that
    ///   does not parse is a leftover: it is first moved out of the way, to
    ///   `section<N>.unreadable.json` (the next free name), where the
    ///   migration would have written over it;
    /// - **the current record**: the legacy record is a leftover. When it
    ///   says the same as the current record (parsed, never by bytes:
    ///   deploy.py rewrites a record it migrates, the review's LOW 7), it is
    ///   what a migration that stopped before its removal leaves, and it is
    ///   only removed; otherwise it is brought in as
    ///   `section<N>.from-built-output.json` (the next free name, LOW 5);
    /// - **none** (the legacy record does not parse): it is a leftover,
    ///   brought in the same way.
    ///
    /// A leftover brought in that holds the same bytes as one already there
    /// (a bring-in that died before its removal) is only removed. The
    /// step sets every leftover aside (`setAside`), never as one of the
    /// section's records. Every record is placed WHOLE (`placeWhole`), so a
    /// death part way through leaves no partial record where a deploy reads
    /// one.
    ///
    /// Refused only when a record cannot be read, written, moved or
    /// removed (or the current record is there and cannot be read at all,
    /// when what a deploy reads cannot be known): what this call changed is
    /// changed back first, and a `.netlify_sites` folder it made removed, so
    /// the folder is as it was. Nil when there is no legacy marker.
    static func moveTheLegacyMarkerIn(
        forSection sectionNumber: Int, in course: Course
    ) throws(LegacyMarkerNotMovedIn) -> LegacyMarkerBroughtIn? {
        let legacyURL: URL = legacyMarkerURL(forSection: sectionNumber, in: course)
        guard FileManager.default.fileExists(atPath: legacyURL.path) else {
            return nil
        }
        let currentURL: URL = currentNetlifyRecordURL(forSection: sectionNumber, in: course.directoryURL)
        let legacyName: String = ".merged_output/" + nameForTeacher(legacyURL)
        let refusedAtTheCurrentPlace: LegacyMarkerNotMovedIn = LegacyMarkerNotMovedIn(
            legacyName: legacyName, placeName: nameForTeacher(currentURL)
        )
        guard let legacyData = try? Data(contentsOf: legacyURL) else {
            throw refusedAtTheCurrentPlace
        }
        var currentData: Data? = nil
        if FileManager.default.fileExists(atPath: currentURL.path) {
            guard let data = try? Data(contentsOf: currentURL) else {
                throw refusedAtTheCurrentPlace
            }
            currentData = data
        }
        let folder: URL = currentURL.deletingLastPathComponent()
        let madeTheFolder: Bool = !FileManager.default.fileExists(atPath: folder.path)
        removeHalfWrittenCopies(forSection: sectionNumber, in: folder)

        if netlifyRecordADeployReads(forSection: sectionNumber, in: course) == .legacy {
            return try bringInTheSectionsRecord(
                legacyData, from: legacyURL, to: currentURL, setAsideFirst: currentData != nil,
                forSection: sectionNumber, in: course, madeTheFolder: madeTheFolder, refusal: refusedAtTheCurrentPlace
            )
        }

        // A leftover. One that says what the current record says, or that
        // a leftover already brought in holds byte for byte, is only removed.
        var sameAsARecordThere: Bool = false
        if let currentData, let current = parsedRecord(currentData), let legacy = parsedRecord(legacyData),
           current.isEqual(legacy) {
            sameAsARecordThere = true
        }
        for leftover in leftoverURLs(forSection: sectionNumber, in: course) {
            if let there = try? Data(contentsOf: leftover), there == legacyData {
                sameAsARecordThere = true
            }
        }
        if sameAsARecordThere {
            if (try? FileManager.default.removeItem(at: legacyURL)) == nil {
                throw refusedAtTheCurrentPlace
            }
            return LegacyMarkerBroughtIn(
                legacyURL: legacyURL, placeURL: nil, currentURL: currentURL,
                unreadableSetAsideAt: nil, bytes: legacyData, madeTheFolder: false
            )
        }
        let placeURL: URL = nextFreeLeftoverURL(.fromBuiltOutput, forSection: sectionNumber, in: course)
        let refusal: LegacyMarkerNotMovedIn = LegacyMarkerNotMovedIn(legacyName: legacyName, placeName: nameForTeacher(placeURL))
        if !placeWhole(legacyData, at: placeURL, mode: 0o600) {
            if madeTheFolder {
                removeIfEmpty(folder)
            }
            throw refusal
        }
        if (try? FileManager.default.removeItem(at: legacyURL)) == nil {
            try? FileManager.default.removeItem(at: placeURL)
            if madeTheFolder {
                removeIfEmpty(folder)
            }
            throw refusal
        }
        return LegacyMarkerBroughtIn(
            legacyURL: legacyURL, placeURL: placeURL, currentURL: currentURL,
            unreadableSetAsideAt: nil, bytes: legacyData, madeTheFolder: madeTheFolder
        )
    }

    /// The legacy record a deploy reads, written in the current record's
    /// place and removed from the built output; a current record there that
    /// no deploy can read moved out of the way first. Each part that fails
    /// changes back what came before it.
    private static func bringInTheSectionsRecord(
        _ legacyData: Data,
        from legacyURL: URL,
        to currentURL: URL,
        setAsideFirst: Bool,
        forSection sectionNumber: Int,
        in course: Course,
        madeTheFolder: Bool,
        refusal: LegacyMarkerNotMovedIn
    ) throws(LegacyMarkerNotMovedIn) -> LegacyMarkerBroughtIn {
        let folder: URL = currentURL.deletingLastPathComponent()
        var asideURL: URL? = nil
        if setAsideFirst {
            let aside: URL = nextFreeLeftoverURL(.unreadable, forSection: sectionNumber, in: course)
            if !UndoSwap.renameExclusively(currentURL, onto: aside) {
                throw refusal
            }
            asideURL = aside
        }
        func changeBack() {
            if let asideURL {
                _ = UndoSwap.renameExclusively(asideURL, onto: currentURL)
            }
            if madeTheFolder {
                removeIfEmpty(folder)
            }
        }
        if !placeWhole(legacyData, at: currentURL, mode: 0o600) {
            changeBack()
            throw refusal
        }
        if (try? FileManager.default.removeItem(at: legacyURL)) == nil {
            try? FileManager.default.removeItem(at: currentURL)
            changeBack()
            throw refusal
        }
        return LegacyMarkerBroughtIn(
            legacyURL: legacyURL, placeURL: currentURL, currentURL: currentURL,
            unreadableSetAsideAt: asideURL, bytes: legacyData, madeTheFolder: madeTheFolder
        )
    }

    // MARK: - Functions: placing a record whole

    /// The start of the name a record is written under beside its place.
    nonisolated static func halfWrittenPrefix(for placeURL: URL) -> String {
        return "." + placeURL.lastPathComponent + ".bringing-in-"
    }

    /// Writes `data` beside `url` under a name of its own (mode `mode`),
    /// then renames it in, never over anything: the place holds the whole
    /// record or nothing. Makes the folder when it is missing. False, with
    /// the written copy removed, when any part fails.
    nonisolated static func placeWhole(_ data: Data, at url: URL, mode: Int = 0o644) -> Bool {
        let folder: URL = url.deletingLastPathComponent()
        let id: String = String(UUID().uuidString.prefix(8)).lowercased()
        let besideURL: URL = folder.appendingPathComponent(halfWrittenPrefix(for: url) + id)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: besideURL, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: besideURL.path)
        } catch {
            try? FileManager.default.removeItem(at: besideURL)
            return false
        }
        if let dies = bringInDiesAfterWriting, dies(besideURL) {
            return false
        }
        if !UndoSwap.renameExclusively(besideURL, onto: url) {
            try? FileManager.default.removeItem(at: besideURL)
            return false
        }
        return true
    }

    /// Removes every copy of one of the section's records left half written
    /// in `.netlify_sites` by a bring-in that died (`.section<N>.….bringing-in-<id>`),
    /// each by its own path, whichever place it was being written for.
    nonisolated static func removeHalfWrittenCopies(forSection sectionNumber: Int, in folder: URL) {
        let start: String = ".section\(sectionNumber)."
        let entries: [String] = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for entry in entries where entry.hasPrefix(start) && entry.contains(".json.bringing-in-") {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(entry))
        }
    }

    /// Removes a folder only when it is empty (`rmdir`).
    nonisolated static func removeIfEmpty(_ folder: URL) {
        _ = folder.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return Int32(-1)
            }
            return rmdir(path)
        }
    }
}

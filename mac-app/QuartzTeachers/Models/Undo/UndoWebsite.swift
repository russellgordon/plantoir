import Foundation

/// Whether the website shows what an Undo or a Redo is about to take back:
/// the question ruling 19 asks before Plantoir offers to deploy (#899). U1
/// states the rule and answers it; U6 makes the offer.
///
/// **Read from the published-pages record, never from the journal.** Every
/// deploy path already writes the section's published-pages record
/// (`contracts/file-formats.json` → `publishedPagesRecord`): `deploy.py`
/// after each Netlify or Cloudflare upload, and `deploy.sh` / `deploy.ps1`
/// after a folder publish, so the app's button, a deploy set for later and a
/// deploy typed in Terminal all leave the same trace. Each fragment names
/// every page the uploaded site shows. The journal is written by neither
/// launcher and is not told about deploys: a `deployed` event in it was
/// rejected because it would be missing for every deploy the app did not
/// start (the director's ruling 1 on U1's second reviews).
///
/// **Only where the section deploys NOW.** A destination the section no
/// longer deploys to is never read: its last fragment would stay the newest
/// for good, because deploying elsewhere never refreshes it (the contract
/// review of U1's second round, I1).
///
/// **What it compares: content, not times.** For each destination the newest
/// fragment (by the moment in its own name) says which pages that website
/// shows now. A move (an Undo or a Redo) offers to deploy when, for some page
/// whose visibility the move changes, that website shows the page as the
/// course has it BEFORE the move: after the move the two differ. No time in
/// the journal is read, so a clock that moved between the step and the
/// deploy cannot mislead it.
///
/// **What it cannot tell.** The record holds which pages a site shows, not
/// what they say. A move that changes a page's content without changing
/// whether students can see it (a body edit, from U2) is `cannotTell`: the
/// record does not hold it, and U6 must not guess. So is a destination whose
/// newest fragment cannot be read, and one with a site marker and no
/// fragment at all: a section last deployed before the record existed
/// (v1.4.1), or rolled over with the "same website" answer, which moves every
/// fragment aside and keeps the marker.
///
/// **Places in one form.** A place is compared after both sides are put in
/// Unicode normalization form C, then code point for code point, so a name
/// spelled decomposed on one side and composed on the other is one page on
/// both platforms (measured by the contract review: Swift's `Set` matched
/// them, Python's `in` did not).
nonisolated enum UndoWebsite {

    // MARK: - Stored properties

    /// One page a move changes, and whether students can see it in the
    /// course before and after the move, by the build's own hide rule
    /// (worked out by the caller from the page's text).
    struct PageMove: Equatable, Sendable {

        // MARK: - Stored properties

        /// Its place in the course folder without `.md`, as the record
        /// spells it (`UndoWebsite.place(ofPath:)`).
        let place: String

        let visibleBeforeTheMove: Bool

        let visibleAfterTheMove: Bool
    }

    /// One file of the section's `section<N>.published-pages/` folder.
    struct Fragment: Equatable, Sendable {

        // MARK: - Stored properties

        /// The file's name: `<yyyyMMddTHHmmssZ>-<destination>.json`.
        let name: String

        /// The pages its site shows; nil when the file could not be read.
        let places: [String]?
    }

    /// What the record says about one move.
    enum Answer: String, Equatable, Sendable {
        /// A website shows what the move takes back: offer to deploy.
        case offerToDeploy
        /// Every website already shows what the move leaves, or the section
        /// has never been deployed where it deploys now (no fragment and no
        /// site marker there).
        case noOffer
        /// The record cannot say.
        case cannotTell
    }

    /// The site-marker folder of each destination that keeps one
    /// (`file-formats.json` → `firstDeployMarkers`); a folder keeps none.
    static let markerFolders: [String: String] = [
        "netlify": ".netlify_sites",
        "cloudflare": ".cloudflare_sites",
    ]

    // MARK: - Functions

    /// The answer for one move of one section.
    ///
    /// - `moves`: every page the step changes, visibility before and after.
    /// - `changesMoreThanVisibility`: the step also changes what some page
    ///   says (or a file that is not a page), which the record does not hold.
    /// - `record`: every file in the section's published-pages folder.
    /// - `destinations`: the destination types the section deploys to NOW
    ///   (`netlify`, `cloudflare`, `folder`): its primary and any additional.
    /// - `siteMarkers`: those of them that have a site marker.
    static func answer(
        moves: [PageMove],
        changesMoreThanVisibility: Bool,
        record: [Fragment],
        destinations: [String],
        siteMarkers: Set<String>
    ) -> Answer {
        var newestByDestination: [String: Fragment] = [:]
        var newestStamp: [String: String] = [:]
        for fragment in record {
            guard let parts = UndoWebsite.parts(ofFragmentNamed: fragment.name) else {
                continue
            }
            if !destinations.contains(parts.destination) {
                continue
            }
            if let known = newestStamp[parts.destination], known >= parts.stamp {
                continue
            }
            newestStamp[parts.destination] = parts.stamp
            newestByDestination[parts.destination] = fragment
        }
        var everDeployed: Bool = false
        var sawSomethingItCannotTell: Bool = false
        var asked: Set<String> = []
        for destination in destinations {
            if asked.contains(destination) {
                continue
            }
            asked.insert(destination)
            guard let fragment = newestByDestination[destination] else {
                if siteMarkers.contains(destination) {
                    // Deployed, before the record existed or since a
                    // rollover moved its fragments aside.
                    everDeployed = true
                    sawSomethingItCannotTell = true
                }
                continue
            }
            everDeployed = true
            guard let places = fragment.places else {
                sawSomethingItCannotTell = true
                continue
            }
            var shown: Set<String> = []
            for place in places {
                shown.insert(UndoWebsite.comparable(place))
            }
            for move in moves where move.visibleBeforeTheMove != move.visibleAfterTheMove {
                if shown.contains(UndoWebsite.comparable(move.place)) == move.visibleBeforeTheMove {
                    return .offerToDeploy
                }
            }
        }
        if !everDeployed {
            return .noOffer
        }
        if sawSomethingItCannotTell || changesMoreThanVisibility {
            return .cannotTell
        }
        return .noOffer
    }

    /// A place in the one form both platforms compare: Unicode
    /// normalization form C.
    static func comparable(_ place: String) -> String {
        return place.precomposedStringWithCanonicalMapping
    }

    /// The moment and the destination in a fragment's name, or nil for any
    /// file that is not a fragment (a temporary file, a folder).
    static func parts(ofFragmentNamed name: String) -> (stamp: String, destination: String)? {
        let suffix: String = ".json"
        if !name.hasSuffix(suffix) || name.hasPrefix(".") {
            return nil
        }
        let characters: [Character] = Array(name.dropLast(suffix.count))
        // yyyyMMddTHHmmssZ is sixteen characters, then a hyphen.
        if characters.count < 18 || characters[16] != "-" {
            return nil
        }
        var index: Int = 0
        while index < 16 {
            let character: Character = characters[index]
            let shouldBe: Character? = index == 8 ? "T" : (index == 15 ? "Z" : nil)
            if let shouldBe {
                if character != shouldBe {
                    return nil
                }
            } else if !(character.isASCII && character.isNumber) {
                return nil
            }
            index += 1
        }
        let stamp: String = String(characters[0..<16])
        let destination: String = String(characters[17...])
        if destination.isEmpty {
            return nil
        }
        return (stamp: stamp, destination: destination)
    }

    /// A page's place in its course folder, as the record names it, from an
    /// op's path inside the working folder: `courses/<CODE>/<place>.md`.
    /// Nil for a path that is not a page of a course.
    static func place(ofPath path: String) -> String? {
        let parts: [Substring] = path.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count < 3 || parts[0] != "courses" {
            return nil
        }
        var rest: [String] = []
        var index: Int = 2
        while index < parts.count {
            rest.append(String(parts[index]))
            index += 1
        }
        let joined: String = rest.joined(separator: "/")
        if !joined.lowercased().hasSuffix(".md") {
            return nil
        }
        return String(joined.dropLast(3))
    }

    /// The destinations among these that have a site marker for the section.
    static func siteMarkers(courseFolder: URL, section: Int, among destinations: [String]) -> Set<String> {
        var found: Set<String> = []
        for destination in destinations {
            guard let folder = markerFolders[destination] else {
                continue
            }
            let marker: URL = courseFolder
                .appendingPathComponent(folder, isDirectory: true)
                .appendingPathComponent("section\(section).json")
            if FileManager.default.fileExists(atPath: marker.path) {
                found.insert(destination)
            }
        }
        return found
    }

    /// Every file of a section's published-pages folder, read. A file that
    /// cannot be read as the record's JSON has nil places.
    static func readRecord(courseFolder: URL, section: Int) -> [Fragment] {
        let folder: URL = courseFolder
            .appendingPathComponent(".publish_state", isDirectory: true)
            .appendingPathComponent("section\(section).published-pages", isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return []
        }
        var fragments: [Fragment] = []
        for name in names {
            if UndoWebsite.parts(ofFragmentNamed: name) == nil {
                continue
            }
            var places: [String]? = nil
            if let data = try? Data(contentsOf: folder.appendingPathComponent(name)),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let listed = object["places"] as? [String] {
                places = listed
            }
            fragments.append(Fragment(name: name, places: places))
        }
        return fragments
    }
}

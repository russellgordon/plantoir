import Foundation

/// Whether the website shows what an Undo or a Redo is about to take back:
/// the question ruling 19 asks before Plantoir offers to deploy (#899). U1
/// states the rule and answers it; U6 makes the offer.
///
/// **Read from the deploy markers, never from the journal.** Every deploy
/// path already writes the section's published-pages record
/// (`contracts/file-formats.json` → `publishedPagesRecord`): `deploy.py`
/// after each Netlify or Cloudflare upload, and `deploy.sh` / `deploy.ps1`
/// after a folder publish, so the app's button, a deploy set for later and a
/// deploy typed in Terminal all leave the same trace. Each fragment names
/// every page the uploaded site shows. The journal is written by neither
/// launcher and is not told about deploys: a `deployed` event in it was
/// rejected because it would be missing for every deploy the app did not
/// start (the director's ruling 1 on U1's second reviews).
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
/// markers do not hold it, and U6 must not guess. So is a destination whose
/// newest fragment cannot be read.
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

    /// What the markers say about one move.
    enum Answer: String, Equatable, Sendable {
        /// A website shows what the move takes back: offer to deploy.
        case offerToDeploy
        /// Every website already shows what the move leaves, or the
        /// section has never been deployed (no fragment at all).
        case noOffer
        /// The markers cannot say.
        case cannotTell
    }

    // MARK: - Functions

    /// The answer for one move of one section.
    ///
    /// - `moves`: every page the step changes, visibility before and after.
    /// - `changesMoreThanVisibility`: the step also changes what some page
    ///   says (or a file that is not a page), which no marker records.
    /// - `record`: every file in the section's published-pages folder.
    static func answer(moves: [PageMove], changesMoreThanVisibility: Bool, record: [Fragment]) -> Answer {
        var newestByDestination: [String: Fragment] = [:]
        var newestStamp: [String: String] = [:]
        for fragment in record {
            guard let parts = UndoWebsite.parts(ofFragmentNamed: fragment.name) else {
                continue
            }
            if let known = newestStamp[parts.destination], known >= parts.stamp {
                continue
            }
            newestStamp[parts.destination] = parts.stamp
            newestByDestination[parts.destination] = fragment
        }
        if newestByDestination.isEmpty {
            return .noOffer
        }
        var sawSomethingItCannotTell: Bool = false
        for (_, fragment) in newestByDestination {
            guard let places = fragment.places else {
                sawSomethingItCannotTell = true
                continue
            }
            var shown: Set<String> = []
            for place in places {
                shown.insert(place)
            }
            for move in moves where move.visibleBeforeTheMove != move.visibleAfterTheMove {
                if shown.contains(move.place) == move.visibleBeforeTheMove {
                    return .offerToDeploy
                }
            }
        }
        if sawSomethingItCannotTell || changesMoreThanVisibility {
            return .cannotTell
        }
        return .noOffer
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

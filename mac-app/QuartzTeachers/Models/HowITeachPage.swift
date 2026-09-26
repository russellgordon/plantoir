import CryptoKit
import Foundation

/// The teacher's "How I Teach" page: one per course, `How I Teach.md` at the
/// top of the course folder, saying how the course is taught (#209).
///
/// The teacher writes it in Obsidian, or an outside assistant (Claude, Codex)
/// drafts it from the course's own pages and saves it once the teacher agrees;
/// both outside doors ask the session to read it. It is NEVER on the website —
/// and that is kept by the BUILD, in shared Python (`scripts/how_i_teach.py`),
/// by the page's LOCATION rather than by any setting on it, because a later
/// `publishForSection<N>: true` beats `publish: false`. The whole rule, with
/// what was measured and rejected, is `contracts/shared-rules.json` →
/// `howITeachPage`, and `HowITeachTests` runs its `nameCases` against this.
///
/// What lives here is the app's half: recognising the page, finding a
/// course's page on disk by its real name, and the text rules the write tool
/// keeps (the settings block it preserves, the fence it refuses, the mark a
/// replacement must carry).
enum HowITeachPage {

    // MARK: - Stored properties

    /// `howITeachPage.fileName`.
    nonisolated static let fileName: String = "How I Teach.md"

    /// The name a teacher and a model call it by.
    nonisolated static let title: String = "How I Teach"

    /// `howITeachPage.tools.mostCharacters`: the longest page the write tool
    /// saves, and the most of one the read tool hands over at once.
    nonisolated static let mostCharacters: Int = 8000

    /// What a new page opens with. Not the guarantee — the location is — but
    /// it means a page later MOVED into a folder in Obsidian, where it becomes
    /// an ordinary page, arrives hidden rather than published.
    static let newPageSettings: String = "---\npublish: false\n---\n"

    // MARK: - Functions

    /// A name as the rule compares it: NFC, then ONLY A–Z folded to a–z.
    ///
    /// Deliberately not `lowercased()`, whose folding and Python's `casefold`
    /// disagree on a handful of letters; with only ASCII folded, the two
    /// implementations of this rule cannot disagree about any name
    /// (`howITeachPage.matching`).
    static func folded(_ name: String) -> String {
        var result: String = ""
        for scalar in name.precomposedStringWithCanonicalMapping.unicodeScalars {
            if scalar.value >= 65 && scalar.value <= 90, let lower = Unicode.Scalar(scalar.value + 32) {
                result.unicodeScalars.append(lower)
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    /// Whether one file NAME is the page. Nothing is trimmed.
    static func isTheHowITeachPageName(_ name: String) -> Bool {
        return folded(name) == folded(fileName)
    }

    /// Whether a title a teacher or a model used means the page — "How I
    /// Teach", in any capitals, with or without `.md`.
    static func isItsTitle(_ title: String) -> Bool {
        let wanted: String = folded(title.trimmingCharacters(in: .whitespacesAndNewlines))
        return wanted == folded(self.title) || wanted == folded(fileName)
    }

    /// Whether a page is the course's page or the same name at the top of a
    /// section folder — the two places the build keeps off the site, and the
    /// two places the assistant's page listings leave out.
    static func isTheHowITeachPage(_ url: URL, in course: Course) -> Bool {
        if !isTheHowITeachPageName(url.lastPathComponent) {
            return false
        }
        let folder: URL = url.deletingLastPathComponent().standardizedFileURL
        let courseFolder: URL = course.directoryURL.standardizedFileURL
        if folder.path == courseFolder.path {
            return true
        }
        if folder.deletingLastPathComponent().path != courseFolder.path {
            return false
        }
        return isASectionFolderName(folder.lastPathComponent)
    }

    /// `section` followed by one or more ASCII digits.
    static func isASectionFolderName(_ name: String) -> Bool {
        let prefix: String = "section"
        if !name.hasPrefix(prefix) {
            return false
        }
        let digits: Substring = name.dropFirst(prefix.count)
        if digits.isEmpty {
            return false
        }
        for character in digits {
            if !("0"..."9").contains(character) {
                return false
            }
        }
        return true
    }

    /// The course's page, found by LISTING the course folder rather than by
    /// building a URL from the name — so the teacher's own spelling ("how i
    /// teach.md") is what gets read, reported and replaced, and a
    /// case-sensitive volume cannot end up holding two of them. Nil when there
    /// is none. When two spellings coexist (possible only on a case-sensitive
    /// volume), the first in name order, every time.
    static func existingURL(for course: Course) -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: course.directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else {
            return nil
        }
        var matches: [URL] = []
        for entry in entries where isTheHowITeachPageName(entry.lastPathComponent) {
            let isFile: Bool = (try? entry.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            if isFile {
                matches.append(entry)
            }
        }
        matches.sort { first, second in
            return first.lastPathComponent < second.lastPathComponent
        }
        return matches.first
    }

    /// Whether a page with the name sits at either reserved place for one
    /// section — the top of the course, or the top of that section's folder.
    static func isThere(forSection sectionNumber: Int, in course: Course) -> Bool {
        if existingURL(for: course) != nil {
            return true
        }
        let sectionFolder: URL = course.sectionDirectoryURL(forSection: sectionNumber)
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: sectionFolder.path) else {
            return false
        }
        for entry in entries where isTheHowITeachPageName(entry) {
            return true
        }
        return false
    }

    /// A page's bytes as text, keeping a leading byte-order mark.
    ///
    /// Foundation's UTF-8 decoding DROPS a byte-order mark, so a page read the
    /// ordinary way and written back loses it — and "kept byte for byte" is
    /// the promise for a replaced page's settings (`howITeachPage.tools.
    /// replacingKeepsTheirFrontmatter`). Nil when the bytes are not UTF-8.
    static func text(of data: Data) -> String? {
        guard let decoded = String(data: data, encoding: .utf8) else {
            return nil
        }
        let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]
        if data.starts(with: byteOrderMark) && decoded.unicodeScalars.first != "\u{FEFF}" {
            return "\u{FEFF}" + decoded
        }
        return decoded
    }

    /// Where a new page goes.
    static func newPageURL(for course: Course) -> URL {
        return course.directoryURL.appendingPathComponent(fileName)
    }

    /// The page's MARK: the first eight lowercase hexadecimal digits of the
    /// SHA-256 of the file's bytes (`howITeachPage.tools.replacingIsAMarkNotABoolean`).
    ///
    /// What `write_how_i_teach` must be handed to replace a page. A boolean
    /// would be an argument the model decides; this it can only copy from the
    /// plan it showed the teacher — and it stops a replace when the teacher
    /// has edited the page since that plan.
    static func mark(of data: Data) -> String {
        let digest: SHA256.Digest = SHA256.hash(data: data)
        var hex: String = ""
        for byte in digest {
            hex += String(format: "%02x", byte)
            if hex.count >= 8 {
                break
            }
        }
        return String(hex.prefix(8))
    }

    /// Words in the page's body, for the plan and the trail — never the words
    /// themselves.
    static func wordCount(of text: String) -> Int {
        var count: Int = 0
        for piece in body(of: text).components(separatedBy: .whitespacesAndNewlines) where !piece.isEmpty {
            count += 1
        }
        return count
    }

    /// The page without its settings block.
    static func body(of text: String) -> String {
        guard let block = settingsBlock(of: text) else {
            return text
        }
        return String(String.UnicodeScalarView(text.unicodeScalars.dropFirst(block.unicodeScalars.count)))
    }

    /// The settings block at the top of a page — a leading byte-order mark,
    /// an opening `---` line, and everything up to and including the next
    /// `---` line and its line ending — or nil when the page has none, or
    /// opens one and never closes it (then there is nothing to keep).
    ///
    /// Worked on Unicode scalars rather than Characters, because Swift folds
    /// "\r\n" into ONE Character and a CRLF page (a synced vault, a Windows
    /// editor) must be read the same as an LF one.
    static func settingsBlock(of text: String) -> String? {
        let lines: [String] = linesKeepingTheirEndings(text)
        guard let first = lines.first else {
            return nil
        }
        var opening: String = first
        var byteOrderMark: String = ""
        if opening.unicodeScalars.first == "\u{FEFF}" {
            byteOrderMark = "\u{FEFF}"
            opening = String(String.UnicodeScalarView(opening.unicodeScalars.dropFirst()))
        }
        if !isAFence(opening) {
            return nil
        }
        var block: String = byteOrderMark + opening
        var index: Int = 1
        while index < lines.count {
            block += lines[index]
            if isAFence(lines[index]) {
                return block
            }
            index += 1
        }
        return nil
    }

    /// Whether the text a caller wants saved OPENS with a settings fence —
    /// after a byte-order mark and any blank lines. Refused, so an agent
    /// cannot write `publish: true` into the page.
    static func opensWithAFence(_ text: String) -> Bool {
        var remaining: String = text
        if remaining.unicodeScalars.first == "\u{FEFF}" {
            remaining = String(String.UnicodeScalarView(remaining.unicodeScalars.dropFirst()))
        }
        for line in linesKeepingTheirEndings(remaining) {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }
            return isAFence(line)
        }
        return false
    }

    /// A NEW page, as it is written to disk
    /// (`howITeachPage.tools.newPageBytes`).
    static func newPageText(_ text: String) -> String {
        return newPageSettings + "\n" + trimmed(text) + "\n"
    }

    /// A REPLACED page: the existing settings block kept byte for byte, and
    /// only the body after it replaced. No key is added to a page that had
    /// none — the location is the guarantee.
    static func replacedPageText(existing: String, with text: String) -> String {
        guard let block = settingsBlock(of: existing) else {
            return trimmed(text) + "\n"
        }
        let lineEnding: String = block.hasSuffix("\r\n") ? "\r\n" : "\n"
        var kept: String = block
        // By scalar: "\r\n" is ONE Character, so `hasSuffix("\n")` is false
        // for a CRLF block and would add a second line ending.
        if block.unicodeScalars.last != "\n" {
            // A closing fence at the very end of the file, with nothing after it.
            kept += lineEnding
        }
        return kept + lineEnding + trimmed(text) + lineEnding
    }

    /// The text as it is saved: without blank lines or spaces around it.
    static func trimmed(_ text: String) -> String {
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The trail's words for a read (`activityTrail.mustRecord` → "How I
    /// Teach page read"): how many words, never which. `words` nil means no
    /// page was there.
    static func trailLineForARead(words: Int?, cutShort: Bool) -> String {
        guard let words else {
            return "an outside assistant found no How I Teach page yet"
        }
        var line: String = "an outside assistant read the How I Teach page (\(counted(words))"
        if cutShort {
            line += ", more than one answer carries"
        }
        return line + ")"
    }

    /// The trail's words for a write ("How I Teach page written"): created
    /// or replaced, the word counts, and the backup made first. Never the
    /// words — the one question this line answers is "did I write this, or
    /// did an assistant?".
    static func trailLineForAWrite(wordsBefore: Int?, wordsAfter: Int, backupName: String?) -> String {
        var line: String
        if let wordsBefore {
            line = "an outside assistant replaced the How I Teach page (\(wordsBefore) → \(counted(wordsAfter)))"
        } else {
            line = "an outside assistant wrote a new How I Teach page (\(counted(wordsAfter)))"
        }
        if let backupName {
            line += ", after backing up the course as \(backupName)"
        } else {
            line += ", with no backup, because one could not be made"
        }
        return line
    }

    /// "1 word", "380 words".
    private static func counted(_ words: Int) -> String {
        return words == 1 ? "1 word" : "\(words) words"
    }

    /// A `---` line, allowing trailing spaces and either line ending.
    private static func isAFence(_ line: String) -> Bool {
        var content: String = line
        while let last = content.unicodeScalars.last, last == "\n" || last == "\r" || last == " " || last == "\t" {
            content = String(String.UnicodeScalarView(content.unicodeScalars.dropLast()))
        }
        return content == "---"
    }

    /// The text cut into lines, each keeping its own "\n" or "\r\n".
    private static func linesKeepingTheirEndings(_ text: String) -> [String] {
        var lines: [String] = []
        var current: String.UnicodeScalarView = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            current.append(scalar)
            if scalar == "\n" {
                lines.append(String(current))
                current = String.UnicodeScalarView()
            }
        }
        if !current.isEmpty {
            lines.append(String(current))
        }
        return lines
    }
}

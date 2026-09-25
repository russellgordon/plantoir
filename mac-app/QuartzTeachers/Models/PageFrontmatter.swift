import Foundation

/// Reading and editing single keys in a page's YAML frontmatter, without
/// reserializing the YAML.
///
/// The teacher's frontmatter is theirs. Round-tripping it through a YAML
/// library would reorder keys, requote strings, reflow the tag list and strip
/// their comments — a diff full of changes nobody asked for, in files Obsidian
/// very likely has open. So every edit here is a line-level edit: find the
/// line, change the value after the colon, leave every other byte alone.
///
/// Which key carries a page's date is decided by where the page lives, not by
/// what the caller says:
///
/// * A page inside `section<N>/` belongs to exactly one section, so it carries
///   a plain `created:`.
/// * A page at course level is copied into EVERY section at build time, so it
///   carries `createdSection<N>:` — one per section.
enum PageFrontmatter {

    // MARK: - Functions

    /// The key carrying this page's date in this section.
    static func createdKey(forSection sectionNumber: Int, isSectionLocal: Bool) -> String {
        return isSectionLocal ? "created" : "createdSection\(sectionNumber)"
    }

    /// One key's value exactly as written, or nil when the key is absent.
    /// Top-level keys only: an indented `title:` belongs to some other mapping.
    nonisolated static func rawValue(forKey key: String, in pageText: String) -> String? {
        guard let block = block(in: pageText) else {
            return nil
        }
        let prefix: String = key + ":"
        for line in block.lines {
            let bare: String = trimmingCarriageReturn(line)
            if bare.hasPrefix(prefix) {
                return String(bare.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// The calendar day this page is scheduled for, or nil when it has none.
    ///
    /// The stored value carries a time and a UTC offset
    /// (`2026-09-08T07:00:00.000-0400`), but a teacher asking about "the class
    /// on the 8th" means the date as written. So the first ten characters are
    /// taken as they stand, in the page's OWN offset — converting to local time
    /// first would move an early-morning class onto the previous day for
    /// anybody east of the school.
    static func createdDay(in pageText: String, key: String) -> CalendarDay? {
        var raw: String? = rawValue(forKey: key, in: pageText)
        if raw == nil {
            raw = rawValue(forKey: "created", in: pageText)
        }
        guard var value = raw else {
            return nil
        }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard value.count >= 10 else {
            return nil
        }
        return CalendarDay(text: String(value.prefix(10)))
    }

    /// Everything after the calendar date in a stored timestamp
    /// (`T07:00:00.000-0400`), or nil when there is no date there at all.
    static func timeAndOffset(inRawValue raw: String) -> String? {
        let value: String = raw
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard value.count >= 10 else {
            return nil
        }
        let characters: [Character] = Array(value)
        for position in 0..<10 {
            if position == 4 || position == 7 {
                if characters[position] != "-" {
                    return nil
                }
            } else if !characters[position].isNumber {
                return nil
            }
        }
        return String(value.dropFirst(10))
    }

    /// The page text with `key` set to this day, and whether that changed
    /// anything. The time of day and UTC offset already on the page are kept —
    /// only the date in front of them moves.
    static func settingCreated(
        in pageText: String,
        key: String,
        to day: CalendarDay,
        fallbackTail: String = "T07:00:00.000-0400"
    ) -> (text: String, changed: Bool) {
        let existing: String = rawValue(forKey: key, in: pageText) ?? ""
        let tail: String = timeAndOffset(inRawValue: existing) ?? fallbackTail
        let value: String = day.text + tail
        if existing == value {
            return (pageText, false)
        }

        let line: String = key + ": " + value
        guard let block = block(in: pageText) else {
            // No frontmatter at all: give the page a block of its own.
            return ("---\n" + line + "\n---\n" + pageText, true)
        }

        var lines: [String] = pageText.components(separatedBy: "\n")
        let prefix: String = key + ":"
        for index in (block.openIndex + 1)..<block.closeIndex {
            if trimmingCarriageReturn(lines[index]).hasPrefix(prefix) {
                replacingKeyLine(
                    at: index, key: key, with: line, in: &lines, closeIndex: block.closeIndex
                )
                return (lines.joined(separator: "\n"), true)
            }
        }
        // Missing: inserted at the top of the block, where the course
        // installer puts it and where it can never land inside a nested list.
        lines.insert(line, at: block.openIndex + 1)
        return (lines.joined(separator: "\n"), true)
    }

    /// The page text with its `title:` set. A page with no title line is
    /// returned unchanged: Quartz falls back to the file name, which is
    /// already right after a rename, and inserting a key the teacher never had
    /// is not this function's business.
    nonisolated static func settingTitle(in pageText: String, to title: String) -> String {
        guard let block = block(in: pageText) else {
            return pageText
        }
        var lines: [String] = pageText.components(separatedBy: "\n")
        for index in (block.openIndex + 1)..<block.closeIndex {
            if trimmingCarriageReturn(lines[index]).hasPrefix("title:") {
                replacingKeyLine(
                    at: index, key: "title", with: "title: " + title,
                    in: &lines, closeIndex: block.closeIndex
                )
                return lines.joined(separator: "\n")
            }
        }
        return pageText
    }

    /// Puts `newLine` where a key's line is, and takes away the lines below it
    /// that were part of the key's OLD value — the one way to change a key
    /// whose value continues below it without leaving half of it behind.
    ///
    /// **What leaving it behind cost, measured (GitHub #199, python-frontmatter
    /// 1.3.0 / PyYAML 6.0.3):** a `created:` with its date on the line below,
    /// or folded (`created: >-`), re-dated by rewriting the key's line alone,
    /// read on the site as the NEW date and the OLD one joined into one string
    /// — while the app read the new date, so the two disagreed about the
    /// class's day in silence; with a `# note` between key and value the build
    /// STOPPED. A title the same way read `Unit 1, Day 2 Unit 1, Day 1`. Only
    /// the visibility writer took the value with the key (#176); this is the
    /// same rule, `PageVisibilityReader.continuationLineIndices`, for every
    /// other key.
    ///
    /// The continuation is asked for BEFORE the line is replaced (the new line
    /// always has a value, so asking afterwards always answers "nothing"), and
    /// removed from the bottom up so no index moves under another. The new
    /// line keeps the carriage return of the line it replaces. Returns how
    /// many lines were taken away, so a caller editing further down can move
    /// its own positions up by as many.
    @discardableResult
    nonisolated static func replacingKeyLine(
        at index: Int,
        key: String,
        with newLine: String,
        in lines: inout [String],
        closeIndex: Int
    ) -> Int {
        let wasEmpty: Bool = AssistPageVisibility.valueIsEmpty(ofKey: key, inLine: lines[index])
        let taken: [Int] = PageVisibilityReader.continuationLineIndices(
            belowKeyAt: index, in: lines, closeIndex: closeIndex, keyValueWasEmpty: wasEmpty
        )
        lines[index] = newLine + (lines[index].hasSuffix("\r") ? "\r" : "")
        var position: Int = taken.count - 1
        while position >= 0 {
            lines.remove(at: taken[position])
            position -= 1
        }
        return taken.count
    }

    /// Where the frontmatter block starts and ends, and the lines inside it.
    ///
    /// **The READER's idea of a block, so that a writer can never edit a
    /// different one.** `PageVisibilityReader.frontmatterBlock` follows
    /// python-frontmatter, which accepts three dashes OR MORE and tolerates
    /// blank lines before the opening fence. A writer that insisted on
    /// exactly `---` at line 0 saw no block on such a page and PREPENDED one
    /// of its own — leaving the teacher's real frontmatter behind it as body
    /// text, printed to their students. Measured 2026-09-19.
    ///
    /// A page with no fence at all still has no frontmatter to speak of, and
    /// that is what nil means here.
    nonisolated static func block(in pageText: String) -> (openIndex: Int, closeIndex: Int, lines: [String])? {
        guard let fences = PageVisibilityReader.fenceIndices(in: pageText) else {
            return nil
        }
        let lines: [String] = pageText.components(separatedBy: "\n")
        var inside: [String] = []
        for position in (fences.openIndex + 1)..<fences.closeIndex {
            inside.append(lines[position])
        }
        return (openIndex: fences.openIndex, closeIndex: fences.closeIndex, lines: inside)
    }

    /// A line without the carriage return a Windows-written file leaves on it.
    nonisolated static func trimmingCarriageReturn(_ line: String) -> String {
        if line.hasSuffix("\r") {
            return String(line.dropLast())
        }
        return line
    }
}

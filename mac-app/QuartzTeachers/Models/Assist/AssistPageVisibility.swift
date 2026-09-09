import Foundation

/// Whether students can see a page, and how to change that.
///
/// Which key carries the answer is decided by WHERE THE PAGE LIVES, exactly as
/// `PageFrontmatter` decides which key carries its date:
///
/// * a page inside `section<N>/` belongs to one section, so it carries a plain
///   `publish:`
/// * a course-level page is copied into every section at build time, so it
///   carries `publishForSection<N>:` — one flag per section
///
/// `draft:` and `draftSection<N>:` are the older spellings and mean the
/// OPPOSITE: `draft: true` is a page students cannot see. Both are read, and
/// the first time anything edits such a page's visibility the old key is
/// MIGRATED: the new key takes the old key's own line and the old line is
/// gone, so a teacher sees a one-line change in the file Obsidian has open
/// rather than reordered frontmatter, and their course converges on one
/// spelling instead of carrying two that mean opposite things.
///
/// Nothing converts a course in a sweep, and nothing needs to — the build
/// reads both spellings, so a page nobody edits goes on working exactly as it
/// did. The rule, and what was rejected, is in `contracts/file-formats.json`
/// → `pageVisibility.writingRules`.
///
/// A page that says nothing either way IS published. That is Quartz's own rule
/// here — `patches/publish.ts` drops a page only when it says `publish: false`
/// — and guessing the other way round would hide every page a teacher wrote
/// without thinking about frontmatter at all.
enum AssistPageVisibility {

    // MARK: - Functions

    /// The key that publishes this page in this section.
    static func publishKey(forSection sectionNumber: Int, isSectionLocal: Bool) -> String {
        return isSectionLocal ? "publish" : "publishForSection\(sectionNumber)"
    }

    /// The older key, which means the opposite.
    static func draftKey(forSection sectionNumber: Int, isSectionLocal: Bool) -> String {
        return isSectionLocal ? "draft" : "draftSection\(sectionNumber)"
    }

    /// Whether this section publishes this page, or nil when the page says
    /// nothing either way.
    ///
    /// Course-level pages go through `SectionAdder.publishValue(forSection:in:)`
    /// — the same reader that carries visibility across when a section is
    /// added, so the two can never disagree about what `draftSection2: true`
    /// meant.
    static func statedPublishing(
        in pageText: String,
        forSection sectionNumber: Int,
        isSectionLocal: Bool
    ) -> Bool? {
        if !isSectionLocal {
            guard let block = PageFrontmatter.block(in: pageText) else {
                return nil
            }
            var lines: [String] = []
            for line in block.lines {
                lines.append(PageFrontmatter.trimmingCarriageReturn(line))
            }
            guard let value = SectionAdder.publishValue(forSection: sectionNumber, in: lines) else {
                return nil
            }
            return isTrue(value)
        }

        if let value = PageFrontmatter.rawValue(forKey: "publish", in: pageText) {
            return isTrue(value)
        }
        if let value = PageFrontmatter.rawValue(forKey: "draft", in: pageText) {
            return !isTrue(value)
        }
        return nil
    }

    /// Whether students meet this page, with Quartz's own default applied to a
    /// page that says nothing.
    static func publishes(
        in pageText: String,
        forSection sectionNumber: Int,
        isSectionLocal: Bool
    ) -> Bool {
        return statedPublishing(
            in: pageText, forSection: sectionNumber, isSectionLocal: isSectionLocal
        ) ?? true
    }

    /// The page text with this section's visibility set, and whether that
    /// changed anything.
    ///
    /// A line-level edit, for the reason `PageFrontmatter` gives: the
    /// teacher's frontmatter is theirs, and round-tripping it through a YAML
    /// library would reorder keys and strip their comments.
    ///
    /// This is where a legacy page is migrated, and it is the one place that
    /// rewrites a page whose value is already right: a page spelled the old
    /// way is converted once even when nothing about its visibility moves.
    /// That is deliberate, and it is the single exception to "writing the
    /// value it already has changes nothing" — a page nobody ever flips would
    /// otherwise keep its legacy key forever, which is exactly the page the
    /// old rule left behind.
    static func setting(
        published: Bool,
        in pageText: String,
        forSection sectionNumber: Int,
        isSectionLocal: Bool
    ) -> (text: String, changed: Bool) {
        let key: String = publishKey(forSection: sectionNumber, isSectionLocal: isSectionLocal)
        let legacy: String = draftKey(forSection: sectionNumber, isSectionLocal: isSectionLocal)
        let carriesLegacyKey: Bool = PageFrontmatter.rawValue(forKey: legacy, in: pageText) != nil

        // Already saying the right thing in the current spelling: leave the
        // file alone, so its modification time does not move and the next
        // build is not fooled into thinking the content changed.
        let stated: Bool? = statedPublishing(
            in: pageText, forSection: sectionNumber, isSectionLocal: isSectionLocal
        )
        if stated == published && !carriesLegacyKey {
            return (pageText, false)
        }

        let line: String = key + ": " + (published ? "true" : "false")
        guard let block = PageFrontmatter.block(in: pageText) else {
            // No frontmatter at all: give the page a block of its own, the
            // way `PageFrontmatter.settingCreated` does.
            return ("---\n" + line + "\n---\n" + pageText, true)
        }

        var lines: [String] = pageText.components(separatedBy: "\n")
        var currentKeyIndex: Int? = nil
        var legacyKeyIndex: Int? = nil
        for index in (block.openIndex + 1)..<block.closeIndex {
            let bare: String = PageFrontmatter.trimmingCarriageReturn(lines[index])
            if currentKeyIndex == nil && bare.hasPrefix(key + ":") {
                currentKeyIndex = index
            }
            if legacyKeyIndex == nil && bare.hasPrefix(legacy + ":") {
                legacyKeyIndex = index
            }
        }

        if let index = currentKeyIndex {
            lines[index] = line + (lines[index].hasSuffix("\r") ? "\r" : "")
            // This page was migrated already, and a leftover legacy key now
            // says the opposite of the line above it. It goes.
            if let stale = legacyKeyIndex {
                lines.remove(at: stale)
            }
        } else if let index = legacyKeyIndex {
            // Migrating. The new key takes the old key's own line, so the
            // teacher's frontmatter keeps its order — moving it to the top of
            // the block would show up as a reordered diff in a file they very
            // likely have open.
            lines[index] = line + (lines[index].hasSuffix("\r") ? "\r" : "")
        } else {
            lines.insert(line, at: block.openIndex + 1)
        }
        return (lines.joined(separator: "\n"), true)
    }

    /// True when this page lives in one section's own folder, and so carries
    /// the plain keys rather than the per-section ones.
    static func isSectionLocal(pageAt url: URL, forSection sectionNumber: Int, in course: Course) -> Bool {
        let folder: String = course.sectionDirectoryURL(forSection: sectionNumber)
            .standardizedFileURL.path
        let page: String = url.standardizedFileURL.path
        return page.hasPrefix(folder + "/")
    }

    /// YAML's spelling of yes, as the toolchain reads it.
    static func isTrue(_ value: String) -> Bool {
        let tidied: String = value
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .lowercased()
        return tidied == "true" || tidied == "yes"
    }
}

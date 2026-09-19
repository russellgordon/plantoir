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
/// here — `patches/publish.ts` drops a page only for the boolean false or the
/// exact string `"false"` — and guessing the other way round would hide every
/// page a teacher wrote without thinking about frontmatter at all. What COUNTS
/// as saying false is not what reading the line suggests, because the build
/// round-trips every page through PyYAML first: `publish: no` hides,
/// `publish: true # why` and `publish: maybe` publish, and `publish: "False"`
/// is visible while `publish: FALSE` is not. `PageVisibilityReader` is the one
/// place that knows the table, and it is measured rather than reasoned.
///
/// **READING does not depend on where the page lives.** The build consults all
/// four keys, in order, on every page it copies, so `PageVisibilityReader`
/// does too and none of the reading here takes an `isSectionLocal`. Only
/// `setting` still does, because which key is WRITTEN is the one thing a
/// page's folder really decides. Until 2026-09-18 the reading branched as
/// well, and a course-level page carrying a plain `publish: false` was
/// therefore reported visible while the build hid it.
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

    /// What the build does with this page — including the case where this app
    /// will not say.
    ///
    /// The one reader. Everything below collapses this answer for its own
    /// purposes, and nothing else parses a visibility line.
    static func answer(in pageText: String, forSection sectionNumber: Int) -> PageVisibilityAnswer {
        return PageVisibilityReader.answer(in: pageText, forSection: sectionNumber)
    }

    /// Whether this section publishes this page, or nil when the page says
    /// nothing either way — the answer for anything REPORTING to a teacher.
    ///
    /// A page this app cannot read is reported as VISIBLE. That is the mild
    /// mistake of the two: listing a live page among the ones a teacher still
    /// has to publish costs them a second look, while calling a page hidden
    /// when students are already reading it is the failure that reports
    /// success. Nothing that WRITES uses this — see `setting`.
    static func statedPublishing(in pageText: String, forSection sectionNumber: Int) -> Bool? {
        switch answer(in: pageText, forSection: sectionNumber) {
        case .saysNothing:
            return nil
        case .visible:
            return true
        case .hidden:
            return false
        case .cannotTell:
            return true
        }
    }

    /// Whether students meet this page, with Quartz's own default applied to a
    /// page that says nothing.
    static func publishes(in pageText: String, forSection sectionNumber: Int) -> Bool {
        return statedPublishing(in: pageText, forSection: sectionNumber) ?? true
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
        //
        // The shortcut needs a CONFIDENT answer, which is why it asks
        // `answer` rather than `statedPublishing`. A value this app cannot
        // read is reported as visible, and a writer that believed that would
        // decline to publish a page on the strength of a guess — so a page
        // whose flag cannot be read gets the flag written out in full, in
        // whichever direction was asked for.
        let stated: PageVisibilityAnswer = answer(in: pageText, forSection: sectionNumber)
        let alreadySaysIt: Bool = (stated == .visible && published) || (stated == .hidden && !published)
        if alreadySaysIt && !carriesLegacyKey {
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
}

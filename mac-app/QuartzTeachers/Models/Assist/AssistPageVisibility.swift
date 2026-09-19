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
    /// It moves LINES, not just one line. A key's value can live on the lines
    /// below it, and those lines go wherever the key goes — see
    /// `PageVisibilityReader.continuationLineIndices` for what it costs when
    /// they are left behind, which is a page published while the teacher is
    /// told it was hidden.
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
        // Found with the READER's own key matcher, so the writer rewrites the
        // line the reader read. A `"publish": false` was invisible to a plain
        // prefix test, which meant this inserted a second `publish: true`
        // above it — and PyYAML keeps the LAST of two, so the page stayed
        // hidden while the teacher was told it had been published.
        let currentKeyLines: [Int] = topLevelLineIndices(ofKey: key, in: pageText)
        let legacyKeyLines: [Int] = topLevelLineIndices(ofKey: legacy, in: pageText)
        let carriesLegacyKey: Bool = !legacyKeyLines.isEmpty

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

        // Every line this write is going to take out, gathered before any of
        // them is removed so that each index still means what it said. A `Set`
        // and one descending pass, rather than removing inside each branch:
        // three separate walks contribute here, and deleting as it goes would
        // invalidate the indices the next walk returns.
        var removals: Set<Int> = []

        // The LAST line naming a key is the one the build reads, so it is the
        // one to rewrite: setting the first of two would leave the page saying
        // the opposite of what was asked for.
        if let index = currentKeyLines.last {
            // Asked BEFORE the line is rewritten — the rewrite always puts a
            // value there, and a column-0 sequence is only this key's value
            // while the key's own value is empty.
            let wasEmpty: Bool = valueIsEmpty(ofKey: key, inLine: lines[index])
            lines[index] = line + (lines[index].hasSuffix("\r") ? "\r" : "")
            for taken in PageVisibilityReader.continuationLineIndices(
                belowKeyAt: index, in: lines, closeIndex: block.closeIndex,
                keyValueWasEmpty: wasEmpty
            ) {
                removals.insert(taken)
            }
            // This page was migrated already, and a leftover legacy key now
            // says the opposite of the line above it. Every one of them goes,
            // and so does every line that was part of its value.
            for stale in legacyKeyLines {
                removals.insert(stale)
                for taken in PageVisibilityReader.continuationLineIndices(
                    belowKeyAt: stale, in: lines, closeIndex: block.closeIndex,
                    keyValueWasEmpty: valueIsEmpty(ofKey: legacy, inLine: lines[stale])
                ) {
                    removals.insert(taken)
                }
            }
        } else if let index = legacyKeyLines.last {
            // Migrating. The new key takes the old key's own line, so the
            // teacher's frontmatter keeps its order — moving it to the top of
            // the block would show up as a reordered diff in a file they very
            // likely have open. Any earlier copies of the legacy key go with
            // it, for the same reason a leftover does above.
            let wasEmpty: Bool = valueIsEmpty(ofKey: legacy, inLine: lines[index])
            lines[index] = line + (lines[index].hasSuffix("\r") ? "\r" : "")
            for taken in PageVisibilityReader.continuationLineIndices(
                belowKeyAt: index, in: lines, closeIndex: block.closeIndex,
                keyValueWasEmpty: wasEmpty
            ) {
                removals.insert(taken)
            }
            for stale in legacyKeyLines.dropLast() {
                removals.insert(stale)
                for taken in PageVisibilityReader.continuationLineIndices(
                    belowKeyAt: stale, in: lines, closeIndex: block.closeIndex,
                    keyValueWasEmpty: valueIsEmpty(ofKey: legacy, inLine: lines[stale])
                ) {
                    removals.insert(taken)
                }
            }
        } else {
            lines.insert(line, at: block.openIndex + 1)
        }

        // Last first, so the earlier indices stay put.
        var doomed: [Int] = []
        for index in removals {
            doomed.append(index)
        }
        doomed.sort()
        for index in doomed.reversed() {
            lines.remove(at: index)
        }
        return (lines.joined(separator: "\n"), true)
    }

    /// True when this line names the key with nothing after its colon — the
    /// one shape whose value can continue at COLUMN 0, as a block sequence.
    ///
    /// Asked with the reader's own matcher rather than a string test, so the
    /// writer answers about the line the reader read.
    static func valueIsEmpty(ofKey key: String, inLine line: String) -> Bool {
        guard let value = PageVisibilityReader.valuePart(
            ofKey: key, inLine: PageFrontmatter.trimmingCarriageReturn(line)
        ) else {
            return false
        }
        return PageVisibilityReader.trimmingYAMLSpaces(value).isEmpty
    }

    /// Every line of this page's frontmatter that names this key at the top
    /// level, in the order they appear.
    ///
    /// The same matcher `PageVisibilityReader` uses, so a key the reader can
    /// see is a key this can rewrite. A page with no frontmatter has none.
    static func topLevelLineIndices(ofKey key: String, in pageText: String) -> [Int] {
        guard let block = PageFrontmatter.block(in: pageText) else {
            return []
        }
        let lines: [String] = pageText.components(separatedBy: "\n")
        var found: [Int] = []
        for index in (block.openIndex + 1)..<block.closeIndex {
            let bare: String = PageFrontmatter.trimmingCarriageReturn(lines[index])
            if bare.hasPrefix(" ") || bare.hasPrefix("\t") {
                continue
            }
            if PageVisibilityReader.valuePart(ofKey: key, inLine: bare) != nil {
                found.append(index)
            }
        }
        return found
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

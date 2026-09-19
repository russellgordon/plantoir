using System.Text;

namespace Plantoir.Core.Models;

/// <summary>
/// Reading and editing the <c>publish:</c> flag in a page's YAML frontmatter,
/// without reserializing the YAML.
///
/// The teacher's frontmatter is theirs. Round-tripping it through a YAML
/// library would reorder keys, requote strings, reflow the tag list and strip
/// their comments — a diff full of changes nobody asked for, in files Obsidian
/// has open. So every edit here is a line-level edit: find the line, change
/// the value after the colon, leave every other byte alone.
///
/// The subtle part is WHICH key to write, and that is decided by where the
/// page lives rather than by anything the caller says:
///
/// * A page inside <c>section&lt;N&gt;/</c> belongs to exactly one section, so
///   it carries a plain <c>publish:</c>.
/// * A page at course level is copied into EVERY section at build time, so it
///   carries <c>publishForSection&lt;N&gt;:</c> — one flag per section, which
///   is what lets "Ohm's Law" be published in section 1 and still hidden in
///   section 2.
///
/// This mirrors <c>process_frontmatter</c> in build_site.py, which copies
/// <c>publishForSection&lt;N&gt;</c> over <c>publish</c> for the section being
/// built and then strips every per-section key from the built copy. The source
/// files keep them all; only the build output is flattened.
///
/// Both keys have a legacy spelling — <c>draft:</c> and
/// <c>draftSection&lt;N&gt;:</c> — with the opposite polarity. Those are still
/// READ, so a course nobody has touched behaves exactly as it did, but they
/// are never written: the first edit to a page migrates it.
/// </summary>
public static class PageFrontmatter
{
    /// <summary>
    /// The frontmatter key that decides whether students see this page.
    ///
    /// <c>publish: true</c> means visible; <c>publish: false</c> means not.
    /// A teacher says a page is or is not published — never that it is or is
    /// not a draft, which reads as "unfinished" and is a different thing.
    /// </summary>
    /// <param name="isSectionLocal">
    /// True when the page lives under <c>section&lt;N&gt;/</c>. Callers get
    /// this from <see cref="PagePaths"/> rather than deciding it themselves.
    /// </param>
    public static string PublishKeyFor(int sectionNumber, bool isSectionLocal) =>
        isSectionLocal ? "publish" : "publishForSection" + sectionNumber;

    /// <summary>
    /// What the same page used to use. Courses written before the change still
    /// carry these, and are read — inverted — until something touches the page
    /// and writes the new key.
    /// </summary>
    public static string LegacyDraftKeyFor(int sectionNumber, bool isSectionLocal) =>
        isSectionLocal ? "draft" : "draftSection" + sectionNumber;

    /// <summary>
    /// Whether this page is hidden in the given section, resolved the way the
    /// BUILD resolves it — which is not the same as reading the line.
    ///
    /// <para>The four keys are consulted in one order on every page the build
    /// copies — <c>publishForSection&lt;N&gt;</c>, <c>publish</c>,
    /// <c>draftSection&lt;N&gt;</c>, <c>draft</c> — and what each value MEANS is
    /// decided by the round trip through python-frontmatter that every page
    /// makes before Quartz sees it. <see cref="PageVisibilityReader"/> is the
    /// one place that knows the table.</para>
    ///
    /// <para>A page whose flag this app will not read collapses to NOT hidden
    /// here, because this answer is used for REPORTING: calling a page hidden
    /// while students are reading it is the failure that reports success.
    /// Anything that WRITES must ask <see cref="Visibility"/> and refuse to
    /// trust <see cref="PageVisibility.CannotTell"/> — see
    /// <see cref="SetDraft"/>.</para>
    /// </summary>
    public static bool IsDraft(string pageText, int sectionNumber) =>
        PageVisibilityReader.Answer(pageText, sectionNumber) == PageVisibility.Hidden;

    /// <summary>
    /// The three-way reading: what the build does with this page, including the
    /// case where this app will not say.
    /// </summary>
    internal static PageVisibility Visibility(string pageText, int sectionNumber) =>
        PageVisibilityReader.Answer(pageText, sectionNumber);

    /// <summary>
    /// The value literally stored under one key, or null when the key is
    /// absent. The caller needs the difference between "set to false" and
    /// "not set at all" to describe an edit honestly.
    /// </summary>
    public static bool? StoredValue(string pageText, string key) =>
        Block.Parse(pageText)?.BoolValue(key);

    /// <summary>One key's value exactly as written, or null when absent.</summary>
    public static string? StoredText(string pageText, string key) =>
        Block.Parse(pageText)?.RawValue(key);

    /// <summary>
    /// Whether this page is currently hidden, in DRAFT terms, or null when it
    /// says nothing either way — or when the flag is a form this app will not
    /// read, which collapses to "not hidden" in every caller's <c>?? false</c>.
    ///
    /// <para>Callers reason in "is it hidden" because that is the question a
    /// plan answers, while the file now stores the opposite. Reading the raw
    /// <c>publish</c> value into a field that means "draft" inverts every
    /// comparison that depends on it — which is exactly what happened, and
    /// what made a plan think an already-published page still needed
    /// publishing.</para>
    ///
    /// <para>Takes a SECTION rather than a key, since 2026-09-19: the build
    /// consults all four keys on every page it copies, so where a page lives
    /// decides which key is WRITTEN and nothing about what it says. Asking only
    /// about one key reported a course-level page carrying a plain
    /// <c>publish: false</c> as visible while the build hid it — the mac's own
    /// blind spot until the same day (issue #140).</para>
    /// </summary>
    public static bool? StoredDraft(string pageText, int sectionNumber) =>
        PageVisibilityReader.Answer(pageText, sectionNumber) switch
        {
            PageVisibility.Hidden => true,
            PageVisibility.Visible => false,
            _ => null,
        };

    /// <summary>
    /// The key carrying this page's date, following the same rule as the draft
    /// key: one section's page has a plain <c>created:</c>, a page shared
    /// across sections has one <c>createdSection&lt;N&gt;:</c> per section.
    /// </summary>
    public static string CreatedKeyFor(int sectionNumber, bool isSectionLocal) =>
        isSectionLocal ? "created" : "createdSection" + sectionNumber;

    /// <summary>
    /// The calendar date this page is scheduled for in this section, or null
    /// when it has none.
    ///
    /// The stored value carries a time and a UTC offset
    /// (<c>2026-09-08T07:00:00.000-0400</c>), but a teacher asking for
    /// "classes from September 15th" means the calendar date as written, so
    /// the date is taken in the page's OWN offset. Converting to local time
    /// first would move an early-morning class onto the previous day for
    /// anyone east of the school.
    /// </summary>
    public static DateOnly? CreatedOn(string pageText, int sectionNumber, bool isSectionLocal)
    {
        var block = Block.Parse(pageText);
        if (block is null) return null;
        return block.DateValue(CreatedKeyFor(sectionNumber, isSectionLocal))
            ?? block.DateValue("created");   // fall back to a plain date if the page carries one
    }

    /// <summary>
    /// The page text with its date moved to <paramref name="date"/>, keeping
    /// the time of day and UTC offset the page already carried.
    ///
    /// Only the calendar part is rewritten. A course's class times are the
    /// teacher's, and a re-date is about which DAY a lesson falls on — moving
    /// 07:00 to midnight because the code found it easier would change how the
    /// site sorts pages that share a day.
    /// </summary>
    /// <param name="fallbackTail">
    /// The time-and-offset to use when the page has no date yet — taken from a
    /// sibling class page, so a course keeps one convention.
    /// </param>
    /// <summary>
    /// Rewrite a page's <c>title:</c>, leaving every other line untouched.
    ///
    /// Needed when a class is renumbered: the file becomes "Unit 2, Day 4"
    /// and a title still reading "Unit 2, Day 3" would show the old name on
    /// the site, in the sidebar, and in every listing — a page whose name and
    /// title disagree is worse than either being wrong on its own.
    ///
    /// A page with no title line is returned unchanged: Quartz falls back to
    /// the file name, which is already correct after a rename, and inserting a
    /// key the teacher never had is not this method's business.
    /// </summary>
    public static string SetTitle(string pageText, string title)
    {
        var block = Block.Parse(pageText);
        if (block?.RawValue("title") is null) return pageText;

        string[] lines = pageText.Split('\n');
        for (int i = block.Open + 1; i < block.Close && i < lines.Length; i++)
        {
            string bare = lines[i].TrimEnd('\r');
            // Top level only: an indented title: belongs to some other mapping.
            if (!bare.StartsWith("title:", StringComparison.Ordinal)) continue;
            lines[i] = "title: " + title + (lines[i].EndsWith('\r') ? "\r" : "");
            return string.Join("\n", lines);
        }
        return pageText;
    }

    public static (string Text, bool Changed) SetCreated(
        string pageText, string key, DateOnly date, string fallbackTail = "T07:00:00.000-0400")
    {
        var block = Block.Parse(pageText);
        string stamp = date.ToString("yyyy-MM-dd");
        string existing = block?.RawValue(key) ?? "";
        string tail = TimeAndOffset(existing) ?? fallbackTail;
        string value = stamp + tail;

        if (string.Equals(existing.Trim(), value, StringComparison.Ordinal)) return (pageText, false);

        string newline = DominantNewline(pageText);
        string line = key + ": " + value;

        if (block is null)
            return ("---" + newline + line + newline + "---" + newline + pageText, true);

        var lines = new List<string>(block.Lines);
        if (block.IndexOf(key) is { } at)
            lines[at] = ReplaceRawValue(lines[at], value);
        else
            lines.Insert(block.FirstBodyLine, line);
        return (block.Rebuild(lines, newline), true);
    }

    /// <summary>Everything after the calendar date in an ISO timestamp, or null.</summary>
    private static string? TimeAndOffset(string raw)
    {
        string value = raw.Trim().Trim('"', '\'');
        if (value.Length < 10) return null;
        for (int i = 0; i < 10; i++)
            if (i is 4 or 7 ? value[i] != '-' : !char.IsDigit(value[i])) return null;
        return value[10..];
    }

    private static string ReplaceRawValue(string line, string value)
    {
        string carriageReturn = line.EndsWith('\r') ? "\r" : "";
        string body = line.TrimEnd('\r');
        int colon = body.IndexOf(':');
        if (colon < 0) return line;
        return body[..(colon + 1)] + " " + value + carriageReturn;
    }

    /// <summary>
    /// The page text with <paramref name="key"/> set to
    /// <paramref name="draft"/>, and a note of what that changed.
    ///
    /// An existing key is edited where it sits. A missing key is inserted at
    /// the top of the block, which is where the course installer puts it and
    /// which can never land inside a nested list or block scalar. A page with
    /// no frontmatter at all gets a block.
    /// </summary>
    /// <summary>
    /// Set a page's visibility, writing the <c>publish</c> key and clearing
    /// any leftover <c>draft</c> one.
    ///
    /// Migration happens here, a page at a time, as things are touched. There
    /// is no sweep and no flag day: build_site.py reads the old keys too, so a
    /// course that nobody has touched still builds exactly as it did, and a
    /// page converts the moment anything changes its visibility.
    /// </summary>
    /// <param name="key">The publish key, from <see cref="PublishKeyFor"/>.</param>
    /// <param name="draft">True to hide the page from students.</param>
    /// <param name="sectionNumber">
    /// The section this edit is for. REQUIRED, and it is not the same question
    /// as <paramref name="key"/>: the gate below has to ask what the BUILD
    /// makes of the whole page, which is all four keys in build order, while
    /// the write puts the answer in the one key a page's folder decides on.
    /// That asymmetry is the mac's too. Making it optional would make a second
    /// rule — a page carrying a stray <c>publishForSection&lt;N&gt;</c> beside
    /// a plain <c>publish:</c> would then be judged on the key alone, and the
    /// build reads the per-section one FIRST, so the write could be skipped in
    /// the dangerous direction.
    /// </param>
    public static (string Text, DraftEdit Edit) SetDraft(
        string pageText, string key, bool draft, int sectionNumber)
    {
        bool publish = !draft;
        // Reads the old keys too, so a page that predates the change reports
        // the state it actually has rather than "not set".
        bool? before = StoredDraft(pageText, sectionNumber);

        string legacy = LegacyKeyOf(key);
        // Found with the READER's own key matcher, so the writer rewrites the
        // line the reader read. A `"publish": false` was invisible to a plain
        // prefix test, which meant this inserted a second `publish: true` above
        // it — and PyYAML keeps the LAST of two, so the page stayed hidden
        // while the teacher was told it had been published.
        var currentKeyLines = PageVisibilityReader.TopLevelLineIndices(pageText, key);
        var legacyKeyLines = PageVisibilityReader.TopLevelLineIndices(pageText, legacy);
        bool hasLegacy = legacyKeyLines.Count > 0;

        // Already right AND already migrated: nothing to do.
        //
        // The shortcut needs a CONFIDENT answer. A value this app cannot read
        // is REPORTED as visible, and a writer that believed that would decline
        // to publish a page on the strength of a guess — so a page whose flag
        // cannot be read gets the flag written out in full, in whichever
        // direction was asked for. Never launder `cannot tell` into a literal
        // "already true".
        var stated = PageVisibilityReader.Answer(pageText, sectionNumber);
        bool alreadySaysIt = (stated == PageVisibility.Visible && publish)
            || (stated == PageVisibility.Hidden && !publish);
        if (alreadySaysIt && !hasLegacy)
            return (pageText, new DraftEdit(key, before, draft, Changed: false));

        string newline = DominantNewline(pageText);
        string line = key + ": " + (publish ? "true" : "false");

        if (PageVisibilityReader.FenceIndices(pageText) is not { } fences)
        {
            string text = "---" + newline + line + newline + "---" + newline + pageText;
            return (text, new DraftEdit(key, null, draft, Changed: true));
        }

        var lines = new List<string>(pageText.Split('\n'));

        if (currentKeyLines.Count > 0)
        {
            // The LAST line naming a key is the one the build reads, so it is
            // the one to rewrite: setting the first of two would leave the page
            // saying the opposite of what was asked for.
            lines[currentKeyLines[^1]] = ReplaceValue(lines[currentKeyLines[^1]], publish);
            // Already migrated; every leftover legacy line is noise that now
            // says the opposite of the line above it. Removed last first, so
            // the earlier indices stay put.
            for (int i = legacyKeyLines.Count - 1; i >= 0; i--) lines.RemoveAt(legacyKeyLines[i]);
        }
        else if (hasLegacy)
        {
            // Migrating: put the new key exactly where the old one sat, so the
            // teacher's frontmatter keeps its order. Moving it to the top would
            // show up as a reordered diff in a file Obsidian has open.
            int old = legacyKeyLines[^1];
            lines[old] = line + (lines[old].EndsWith('\r') ? "\r" : "");
            for (int i = legacyKeyLines.Count - 2; i >= 0; i--) lines.RemoveAt(legacyKeyLines[i]);
        }
        else
        {
            lines.Insert(fences.Open + 1, line);
        }

        return (Rebuild(lines, newline), new DraftEdit(key, before, draft, Changed: true));
    }

    /// <summary>The pre-change key that answers the same question as <paramref name="key"/>.</summary>
    private static string LegacyKeyOf(string key) =>
        key.StartsWith("publishForSection", StringComparison.Ordinal)
            ? "draftSection" + key["publishForSection".Length..]
            : "draft";

    /// <summary>
    /// Rewrites the value after the colon while preserving whatever came
    /// before it — indentation, the key's own spelling, and any spacing the
    /// teacher used. An inline <c># comment</c> after the value survives.
    /// </summary>
    /// <remarks>
    /// The comment is found with the READER's quote-aware scan, not with the
    /// first <c>#</c> on the line. A hash inside quotes is not a comment, and
    /// splitting <c>publish: "false # why"</c> at it left an unbalanced quote
    /// in the teacher's file — frontmatter the build cannot parse at all.
    /// </remarks>
    private static string ReplaceValue(string line, bool publish)
    {
        // A CRLF file's lines still carry their '\r' here; rebuilding the line
        // without putting it back would quietly convert that one line to LF.
        string carriageReturn = line.EndsWith('\r') ? "\r" : "";
        string body = line.TrimEnd('\r');

        int colon = body.IndexOf(':');
        if (colon < 0) return line;   // not a mapping line; leave it alone
        string head = body[..(colon + 1)];
        string tail = body[(colon + 1)..];

        string beforeComment = PageVisibilityReader.StripComment(tail);
        string comment = tail.Length > beforeComment.Length
            ? tail[beforeComment.Length..].TrimEnd(' ', '\t')
            : "";
        string spacing = tail.Length > 0 && tail[0] == ' ' ? " " : "";
        string gap = comment.Length > 0 ? " " : "";

        return head + spacing + (publish ? "true" : "false") + gap + comment + carriageReturn;
    }

    /// <summary>
    /// The lines joined back together, keeping each one's own ending and giving
    /// an INSERTED line the file's dominant one.
    /// </summary>
    private static string Rebuild(List<string> lines, string newline)
    {
        // Split/join on '\n' alone would strip the '\r' from CRLF files, so
        // the lines still carry theirs; only an INSERTED line needs one.
        var builder = new StringBuilder();
        for (int i = 0; i < lines.Count; i++)
        {
            builder.Append(lines[i]);
            if (i < lines.Count - 1)
                builder.Append(lines[i].EndsWith('\r') || newline == "\n" ? "\n" : newline);
        }
        return builder.ToString();
    }

    private static string DominantNewline(string text) =>
        text.Contains("\r\n", StringComparison.Ordinal) ? "\r\n" : "\n";

    /// <summary>
    /// The frontmatter block as raw lines, with just enough structure to find
    /// a top-level key. Deliberately not a YAML parser: it understands the
    /// shape of the files this toolchain writes and declines to guess at
    /// anything else.
    /// </summary>
    private sealed class Block
    {
        public required string[] Lines { get; init; }
        public required int Open { get; init; }      // index of the opening ---
        public required int Close { get; init; }     // index of the closing ---
        public required string Original { get; init; }

        /// <summary>Where a newly inserted key goes: straight after the opening fence.</summary>
        public int FirstBodyLine => Open + 1;

        /// <remarks>
        /// ONE fence finder, shared with the reader. python-frontmatter's
        /// boundary is <c>^-{3,}\s*$</c> — three dashes or more, at either end
        /// — and it tolerates blank lines before the opening one. Insisting on
        /// exactly <c>---</c> at line 0 made the writers prepend a block of
        /// their own on a page fenced with <c>----</c>, leaving the teacher's
        /// real frontmatter behind it as BODY TEXT, printed to their students.
        /// <c>...</c> is not accepted as a closing fence, because
        /// python-frontmatter does not accept one either.
        /// </remarks>
        public static Block? Parse(string text)
        {
            if (PageVisibilityReader.FenceIndices(text) is not { } fences) return null;
            return new Block
            {
                Lines = text.Split('\n'),
                Open = fences.Open,
                Close = fences.Close,
                Original = text,
            };
        }

        /// <summary>
        /// The index of a TOP-LEVEL key's line, or null. Indentation matters:
        /// an indented <c>draft:</c> is a field of some other mapping, not the
        /// page's own flag, and editing it would change something else.
        /// </summary>
        /// <remarks>
        /// The reader's own matcher, so the three legal spellings of a key
        /// (<c>created:</c>, <c>created :</c>, <c>"created":</c>) are all
        /// found and a colon with no space after it is not a mapping at all.
        /// The indentation test is by hand, because <c>char.IsWhiteSpace</c>
        /// counts a non-breaking space and YAML does not.
        /// </remarks>
        public int? IndexOf(string key)
        {
            for (int i = Open + 1; i < Close; i++)
            {
                string raw = PageVisibilityReader.TrimCarriageReturn(Lines[i]);
                if (raw.Length == 0 || raw[0] == ' ' || raw[0] == '\t') continue;   // blank or nested
                if (raw[0] == '#') continue;
                if (PageVisibilityReader.ValuePart(key, raw) is not null) return i;
            }
            return null;
        }

        public bool? BoolValue(string key)
        {
            if (RawValue(key) is not { } value) return null;
            int hash = value.IndexOf('#');
            if (hash >= 0) value = value[..hash];
            value = value.Trim();
            if (value.Equals("true", StringComparison.OrdinalIgnoreCase)) return true;
            if (value.Equals("false", StringComparison.OrdinalIgnoreCase)) return false;
            return null;   // a non-boolean draft value is not ours to interpret
        }

        /// <summary>The text after the key's colon, exactly as written.</summary>
        public string? RawValue(string key)
        {
            if (IndexOf(key) is not { } at) return null;
            string raw = PageVisibilityReader.TrimCarriageReturn(Lines[at]);
            return PageVisibilityReader.ValuePart(key, raw)?.Trim();
        }

        /// <summary>
        /// A date value, read in the offset the page itself states. Quoting is
        /// tolerated because YAML writers vary; anything unparseable is null
        /// rather than a guess.
        /// </summary>
        public DateOnly? DateValue(string key)
        {
            if (RawValue(key) is not { } raw) return null;
            string value = raw.Trim('"', '\'');
            if (value.Length == 0) return null;
            if (DateTimeOffset.TryParse(value, System.Globalization.CultureInfo.InvariantCulture,
                    System.Globalization.DateTimeStyles.None, out var stamp))
                return DateOnly.FromDateTime(stamp.Date);
            if (DateOnly.TryParse(value, System.Globalization.CultureInfo.InvariantCulture,
                    System.Globalization.DateTimeStyles.None, out var plain))
                return plain;
            return null;
        }

        public string Rebuild(List<string> lines, string newline) =>
            PageFrontmatter.Rebuild(lines, newline);
    }
}

/// <summary>
/// What one draft edit did, in terms the confirmation panel can put into a
/// sentence: which key, what it was, what it became.
/// </summary>
public readonly record struct DraftEdit(string Key, bool? Before, bool After, bool Changed)
{
    /// <summary>Plain words for a teacher, in the app's voice.</summary>
    public string Describe(string pageTitle) => Changed
        ? After ? $"Hide “{pageTitle}”" : $"Publish “{pageTitle}”"
        : After ? $"“{pageTitle}” is already hidden" : $"“{pageTitle}” is already published";
}

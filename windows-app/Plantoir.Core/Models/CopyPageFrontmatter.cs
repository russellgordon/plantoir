using System.Text.RegularExpressions;

namespace Plantoir.Core.Models;

/// <summary>
/// What makes a copied page HIDDEN, and the check that the website builder
/// will read it the same way (#247, mac #207;
/// <c>shared-rules.json → copyingAPageBetweenCourses.hidden / builderAgreement</c>).
///
/// <para><b>The four steps, in this order, and the order is load-bearing.</b>
/// (1) Strip the source's own <c>publishForSection&lt;N&gt;</c>,
/// <c>draftSection&lt;N&gt;</c> and <c>createdSection&lt;N&gt;</c>.
/// (2) Strip the plain <c>publish:</c> and <c>draft:</c> — and the 2024-25
/// layout's <c>draftSectionTwo</c>/<c>createdForSectionTwo</c> (#258) — with
/// the READER's key matcher and continuation rule, never a prefix test: a
/// naive strip of <c>draft:</c> whose value sits on the line below orphans it,
/// and YAML folds it into "false true", which the build PUBLISHES.
/// (3) Write <c>publishForSection&lt;N&gt;: false</c> for every destination
/// section, through <see cref="PageFrontmatter.SetDraft"/>.
/// (4) A plain <c>publish: false</c> LAST, which is what keeps the copy hidden
/// in a section the course gains later. Writing (4) first makes (3) a no-op:
/// SetDraft's "already says it" gate reads the plain key and returns.</para>
///
/// <para><b>The guard is a small regular language, not a YAML parser.</b> This
/// app has no YAML library; the build's reader is python-frontmatter/PyYAML.
/// So <see cref="BuilderAgrees"/> REFUSES anything outside a narrow grammar
/// derived from what real pages contain — no anchors, aliases, tags, block
/// scalars, flow mappings, directives, extra documents or indented fences —
/// and so "certified" is true by construction for what it accepts. That the
/// restriction is sound is FUZZ-BACKED against the real Python reader
/// (<c>CopyAPageFuzzTests</c>), not proven. Every test runs ordinally over
/// UTF-16 code units: the culture-sensitive comparisons are what would fuse a
/// combining mark with the space after a colon, the trap Swift met.</para>
/// </summary>
public static class CopyPageFrontmatter
{
    /// <summary>The 2024-25 website-folder layout's section-2 keys, stripped by exact name (#258).</summary>
    public static readonly IReadOnlyList<string> PlainKeysStripped =
        new[] { "publish", "draft", "draftSectionTwo", "createdForSectionTwo" };

    /// <summary>
    /// The page text a copy is written with: hidden in every one of
    /// <paramref name="sections"/> and in any section added later. Null when
    /// there was no room for a key (a block with no column-0 level), which the
    /// caller reports as a page that could not be made hidden.
    /// </summary>
    public static string? Compose(string source, IReadOnlyList<int> sections)
    {
        string text = source;
        // A source with no block the BUILD can see — none at all, or one only
        // closed by an indented fence (#188) — is given a block of its own,
        // and its own lines become body text, as they already are on its site.
        if (PageVisibilityReader.FenceIndices(text) is null)
            text = "---\n---\n" + text;

        text = PageFrontmatter.WithoutPerSectionKeys(text);                    // step 1
        text = WithoutTopLevelKeys(text, PlainKeysStripped);                   // step 2
        foreach (int section in sections.Distinct().OrderBy(n => n))           // step 3
        {
            var (written, edit) = PageFrontmatter.SetDraft(
                text, PageFrontmatter.PublishKeyFor(section, isSectionLocal: false), draft: true, section);
            if (edit.NoRoomForAKey) return null;
            text = written;
        }
        return WithPlainPublishFalseLast(text);                                // step 4
    }

    /// <summary>The page without any top-level line naming one of <paramref name="keys"/>, each with its continuation lines.</summary>
    internal static string WithoutTopLevelKeys(string text, IEnumerable<string> keys)
    {
        if (PageVisibilityReader.FenceIndices(text) is not { } fences) return text;
        var lines = new List<string>(text.Split('\n'));
        var removals = new SortedSet<int>();
        foreach (string key in keys)
        {
            foreach (int index in PageVisibilityReader.TopLevelLineIndices(text, key))
            {
                removals.Add(index);
                bool valueWasEmpty = PageVisibilityReader.ValuePart(key, PageVisibilityReader.TrimCarriageReturn(lines[index])) is { } value
                                     && PageVisibilityReader.TrimYamlSpaces(value).Length == 0;
                int follow = PageFrontmatter.ContinuationLineCount(lines, index, fences.Close, valueWasEmpty);
                for (int extra = 1; extra <= follow; extra++) removals.Add(index + extra);
            }
        }
        foreach (int index in removals.Reverse()) lines.RemoveAt(index);
        return string.Join("\n", lines);
    }

    /// <summary>Puts <c>publish: false</c> as the last line of the block, before the closing fence.</summary>
    private static string? WithPlainPublishFalseLast(string text)
    {
        if (PageVisibilityReader.FenceIndices(text) is not { } fences) return null;
        var lines = new List<string>(text.Split('\n'));
        string ending = lines[fences.Close].EndsWith('\r') ? "\r" : "";
        lines.Insert(fences.Close, "publish: false" + ending);
        return string.Join("\n", lines);
    }

    // ---- The builder-agreement guard --------------------------------------

    private static readonly Regex Key = new(@"^[A-Za-z][A-Za-z0-9_-]*$", RegexOptions.CultureInvariant);

    /// <summary>YAML 1.1's bool and null words: as a KEY they load as True/None, and the build raises.</summary>
    private static readonly HashSet<string> BoolOrNullWords = new(StringComparer.OrdinalIgnoreCase)
    {
        "y", "n", "yes", "no", "true", "false", "on", "off", "null",
    };

    /// <summary>PyYAML's implicit timestamp resolver: a value matching it must also be a real date and time.</summary>
    private static readonly Regex Timestamp = new(
        @"^(?<y>[0-9]{4})-(?<m>[0-9]{1,2})-(?<d>[0-9]{1,2})(?:(?:[Tt]|[ \t]+)(?<h>[0-9]{1,2}):(?<min>[0-9]{2}):(?<s>[0-9]{2})(?:\.[0-9]*)?(?:[ \t]*(?:Z|[-+][0-9]{1,2}(?::[0-9]{2})?))?)?$",
        RegexOptions.CultureInvariant);

    private static readonly Regex ShortDate = new(@"^[0-9]{4}-[0-9]{2}-[0-9]{2}$", RegexOptions.CultureInvariant);

    /// <summary>A visibility key, which only OUR lines may carry inside the region.</summary>
    private static readonly Regex VisibilityKey = new(@"^(publish|draft)", RegexOptions.CultureInvariant);

    private static readonly Regex OurSectionKey = new(@"^publishForSection([0-9]+)$", RegexOptions.CultureInvariant);

    /// <summary>
    /// Whether the website builder reads this composed page's settings block
    /// exactly as this app does — and so whether the copy is CERTAINLY hidden.
    /// The invariant: every key that hides the copy lies inside the region the
    /// build reads as frontmatter; that region carries no OTHER visibility
    /// key; both readers agree where it ends; and every line in it is a shape
    /// in the language below. Anything else is refused, and a refused page is
    /// one a teacher can still copy by hand.
    /// </summary>
    public static bool BuilderAgrees(string text)
    {
        string[] lines = text.Split('\n');

        // Leading blank lines are skipped by both readers; the opening fence
        // must then be at column 0.
        int open = 0;
        while (open < lines.Length && Bare(lines[open]).Trim(' ').Length == 0 && !lines[open].Contains('\t')) open++;
        if (open >= lines.Length || !IsColumnZeroFence(lines[open])) return false;
        int close = -1;
        for (int index = open + 1; index < lines.Length; index++)
        {
            if (IsColumnZeroFence(lines[index])) { close = index; break; }
        }
        if (close < 0) return false;

        // Nothing before the close may carry a character either reader sees
        // differently: a lone CR (a line break to the build only), a C0
        // control, DEL, the Unicode line breaks, a BOM, a replacement char.
        for (int index = 0; index <= close; index++)
        {
            string line = Bare(lines[index]);
            if (line.Any(IsForbidden)) return false;
        }

        int plainPublishFalse = 0;
        var sectionKeys = new HashSet<int>();
        int? listIndent = null;
        bool listMayFollow = false;

        for (int index = open + 1; index < close; index++)
        {
            string line = Bare(lines[index]);
            if (line.Contains('\t')) return false;                          // YAML forbids a tab in indentation; none in real data
            string trimmed = line.Trim(' ');
            if (trimmed.Length == 0) continue;                              // a blank line ends nothing
            if (IsDashesOnly(trimmed)) return false;                        // an indented fence: the readers would split differently
            if (line.StartsWith('#')) continue;                             // a comment at column 0
            if (line.StartsWith(' '))
            {
                if (trimmed.StartsWith('#')) continue;                      // an indented comment
                // An indented "- VALUE" under a "key:" line, every item at the first item's indent.
                if (!listMayFollow || !trimmed.StartsWith("- ", StringComparison.Ordinal)) return false;
                int indent = line.Length - line.TrimStart(' ').Length;
                listIndent ??= indent;
                if (indent != listIndent) return false;
                if (!IsValue(trimmed[2..].Trim(' '))) return false;
                continue;
            }

            listIndent = null;
            listMayFollow = false;
            int colon = line.IndexOf(':');
            if (colon <= 0) return false;
            string key = line[..colon];
            if (!Key.IsMatch(key) || BoolOrNullWords.Contains(key)) return false;
            string rest = line[(colon + 1)..];
            if (rest.Trim(' ').Length == 0)
            {
                if (VisibilityKey.IsMatch(key)) return false;               // a visibility key with no value is not ours
                listMayFollow = true;
                continue;
            }
            if (!rest.StartsWith(' ')) return false;                        // key:value is one scalar, not a mapping
            string value = rest.Trim(' ');
            if (!IsValue(value)) return false;

            if (VisibilityKey.IsMatch(key))
            {
                if (key == "publish" && value == "false") { plainPublishFalse++; continue; }
                if (OurSectionKey.Match(key) is { Success: true } ours && value == "false"
                    && int.TryParse(ours.Groups[1].Value, out int section) && sectionKeys.Add(section))
                    continue;
                return false;                                               // any other visibility key, or a second of ours
            }
        }
        return plainPublishFalse == 1;
    }

    /// <summary>A VALUE in the language: a narrow plain scalar, a simple quoted one, or <c>[]</c>.</summary>
    private static bool IsValue(string value)
    {
        if (value.Length == 0) return false;
        if (value == "[]") return true;
        if (value[0] == '"')
            return value.Length >= 2 && value[^1] == '"' && !value[1..^1].Contains('"') && !value.Contains('\\');
        if (value[0] == '\'')
            return value.Length >= 2 && value[^1] == '\'' && !value[1..^1].Contains('\'');
        char first = value[0];
        if (!(char.IsAsciiLetterOrDigit(first) || first == '_')) return false;
        if (value.Contains(": ", StringComparison.Ordinal) || value.Contains(" #", StringComparison.Ordinal) || value.EndsWith(':'))
            return false;
        if (char.IsAsciiDigit(first) && !Constructible(value)) return false;
        return true;
    }

    /// <summary>
    /// A digit-led value PyYAML can construct. Resolving and constructing are
    /// two steps and only the second fails: <c>2025-09-93</c> resolves as a
    /// timestamp and raises. A value with a colon-less offset is not resolved
    /// at all, and stays a string (<c>2026-02-29T07:00:00.000-0400</c> on a real page).
    /// </summary>
    private static bool Constructible(string value)
    {
        var match = Timestamp.Match(value);
        if (match.Success && (ShortDate.IsMatch(value) || match.Groups["h"].Success))
        {
            int year = int.Parse(match.Groups["y"].Value), month = int.Parse(match.Groups["m"].Value), day = int.Parse(match.Groups["d"].Value);
            if (month is < 1 or > 12 || day < 1 || day > DateTime.DaysInMonth(year == 0 ? 2000 : year, month) || year == 0) return false;
            if (match.Groups["h"].Success
                && (int.Parse(match.Groups["h"].Value) > 23 || int.Parse(match.Groups["min"].Value) > 59 || int.Parse(match.Groups["s"].Value) > 59))
                return false;
        }
        // 0b / 0x with no digit once the underscores are gone: int('', base) raises.
        if (Regex.IsMatch(value, @"^0[bx]_*$", RegexOptions.CultureInvariant)) return false;
        return true;
    }

    private static string Bare(string line) => line.EndsWith('\r') ? line[..^1] : line;

    private static bool IsColumnZeroFence(string line)
    {
        string bare = Bare(line).TrimEnd(' ', '\t');
        return bare.Length >= 3 && bare.All(c => c == '-');
    }

    private static bool IsDashesOnly(string trimmed) => trimmed.Length >= 3 && trimmed.All(c => c == '-');

    private static bool IsForbidden(char c) =>
        (c < 0x20 && c != '\t') || c == '\r' || c == 0x7F || c == '\u0085' || c == 0x2028 || c == 0x2029
        || c == 0xFEFF || c == 0xFFFD;

    // ---- The read-back ---------------------------------------------------------

    /// <summary>
    /// Whether this app's reader calls the text NOT VISIBLE — "hidden", never
    /// "cannot tell" — in every one of <paramref name="sections"/> and in one
    /// section the course does not have.
    /// </summary>
    public static bool IsHiddenEverywhere(string text, IReadOnlyList<int> sections)
    {
        int beyond = (sections.Count == 0 ? 0 : sections.Max()) + 1;
        return sections.Append(beyond).All(section => PageVisibilityReader.Answer(text, section) == PageVisibility.Hidden);
    }

    /// <summary>The whole certification: the guard AND the read-back.</summary>
    public static bool IsCertainlyHidden(string text, IReadOnlyList<int> sections) =>
        BuilderAgrees(text) && IsHiddenEverywhere(text, sections);
}

using System.Text;

namespace Plantoir.Core.Models;

/// <summary>
/// What the built website does with a page — the only question this reader is
/// trying to answer.
///
/// <para><c>CannotTell</c> is not a fourth kind of visibility. It is this
/// reader saying that a key IS on the page and it will not guess what the build
/// makes of it. What happens next depends on who asked: something REPORTING to
/// a teacher treats it as visible, because the one mistake that must never be
/// made is calling a page hidden while students are reading it; something
/// WRITING to the page never treats it as anything at all, and writes the flag
/// out in full instead.</para>
/// </summary>
internal enum PageVisibility
{
    /// <summary>The page carries no key this section's build would look at.</summary>
    SaysNothing,

    /// <summary>The build publishes this page.</summary>
    Visible,

    /// <summary>The build holds this page back.</summary>
    Hidden,

    /// <summary>There is a key, and this reader will not claim to know what it means.</summary>
    CannotTell,
}

/// <summary>
/// Whether the built site shows a page, read from the teacher's own text.
///
/// <para><b>The rule is the BUILD'S rule, not YAML's and not Quartz's.</b> A
/// page never reaches Quartz as the teacher typed it: <c>scripts/build_site.py</c>
/// → <c>process_frontmatter</c> loads it with python-frontmatter (PyYAML, YAML
/// 1.1), resolves this section's per-section keys onto a plain <c>publish:</c>,
/// and writes it back out. Quartz then parses THAT with js-yaml on its JSON
/// schema, and <c>patches/publish.ts</c> drops the page only when the value it
/// gets is the boolean false or the exact string <c>"false"</c>.</para>
///
/// <para>Three consequences fall out of the round trip, and each of them is a
/// page a hand-rolled reader gets wrong in the direction that matters:</para>
/// <list type="bullet">
///   <item><c>publish: no</c> and <c>publish: off</c> HIDE the page — PyYAML
///   reads YAML 1.1's nine spellings of no as the boolean, and writes
///   <c>false</c> back.</item>
///   <item><c>publish: true # why</c> PUBLISHES it, because the comment is gone
///   by the time Quartz looks. So does <c>publish: maybe</c>, and anything else
///   PyYAML cannot make a boolean of.</item>
///   <item>Case matters, in opposite directions on either side of the round
///   trip. <c>publish: FALSE</c> hides the page, while <c>publish: "False"</c>
///   does NOT — the quotes keep it a string, and <c>publish.ts</c> compares
///   strings exactly. Do not "simplify" either compare into a case-insensitive
///   one: that publishes a page the teacher held back.</item>
/// </list>
///
/// <para><b>Which key answers is decided by the BUILD ORDER, never by where the
/// page lives.</b> <c>process_frontmatter</c> consults
/// <c>publishForSection&lt;N&gt;</c>, then <c>publish</c>, then
/// <c>draftSection&lt;N&gt;</c>, then <c>draft</c>, on every page it copies,
/// wherever that page came from. So this reader walks all four in that order
/// too. A page's folder decides which key is WRITTEN — that is
/// <see cref="PageFrontmatter.PublishKeyFor"/>'s business — and nothing
/// else.</para>
///
/// <para>This is the same rule as <c>scripts/page_visibility.py</c> and the
/// mac's <c>PageVisibilityReader.swift</c>;
/// <c>contracts/file-formats.json</c> → <c>pageVisibility.readingCases</c> is
/// the list all three are run against, and the measured table is in
/// <c>documentation/08-course-config-reference.md</c>.</para>
///
/// <para><b>.NET traps this file is written around.</b> Every comparison here
/// is <see cref="StringComparison.Ordinal"/>, because the framework defaults
/// are culture-sensitive and will match strings that differ by an ignorable
/// character. And YAML's whitespace is a space and a tab and nothing else, so
/// nothing here uses <c>Trim()</c>, <c>TrimEnd()</c> or
/// <c>char.IsWhiteSpace</c>: those also strip the non-breaking space
/// Option-Space types on a Mac, and <c>publish: false&lt;NBSP&gt;</c> is the
/// STRING "false " to the build and the page is PUBLISHED.</para>
/// </summary>
internal static class PageVisibilityReader
{
    /// <summary>One key's value, as far as this reader is willing to read it.</summary>
    /// <param name="Value">The text of the value, with quotes and any comment removed.</param>
    /// <param name="WasQuoted">
    /// Whether the teacher put quotes around it — which changes the answer,
    /// because quotes stop PyYAML resolving <c>no</c> or <c>false</c> into a
    /// boolean.
    /// </param>
    internal readonly record struct ScalarReading(string Value, bool WasQuoted);

    /// <summary>The four keys the build consults, in the order it consults them.</summary>
    /// <remarks>
    /// A key naming ANOTHER section is not on this list, because the build
    /// deletes it without reading it.
    /// </remarks>
    internal static (string Name, bool IsDraftFamily)[] KeysInBuildOrder(int sectionNumber) =>
    [
        ("publishForSection" + sectionNumber, false),
        ("publish", false),
        ("draftSection" + sectionNumber, true),
        ("draft", true),
    ];

    /// <summary>
    /// YAML 1.1's nine spellings of yes, as PyYAML resolves them. Written out
    /// one per line so the table can be read off rather than inferred: these
    /// are exactly the spellings, and case matters — <c>tRue</c> is not here,
    /// and PyYAML leaves it an ordinary string.
    /// </summary>
    internal static bool IsYamlTrue(string value) => value switch
    {
        "true" or "True" or "TRUE" => true,
        "yes" or "Yes" or "YES" => true,
        "on" or "On" or "ON" => true,
        _ => false,
    };

    /// <summary>
    /// YAML 1.1's nine spellings of no. Note what is NOT here: <c>n</c>,
    /// <c>N</c>, <c>0</c>. PyYAML deliberately does not read single-letter
    /// <c>y</c>/<c>n</c> as booleans, so <c>publish: n</c> is the string "n"
    /// and the page is published.
    /// </summary>
    internal static bool IsYamlFalse(string value) => value switch
    {
        "false" or "False" or "FALSE" => true,
        "no" or "No" or "NO" => true,
        "off" or "Off" or "OFF" => true,
        _ => false,
    };

    // ---- The answer ------------------------------------------------------

    /// <summary>What the build does with this page, in this section.</summary>
    internal static PageVisibility Answer(string pageText, int sectionNumber) =>
        Answer(pageText, KeysInBuildOrder(sectionNumber));

    /// <summary>
    /// The same question, asked of a named list of keys — used by the writers,
    /// which care about one key and its legacy spelling.
    /// </summary>
    internal static PageVisibility Answer(
        string pageText, IReadOnlyList<(string Name, bool IsDraftFamily)> keys)
    {
        if (FenceIndices(pageText) is not { } fences)
            return OpensAFence(pageText) ? PageVisibility.CannotTell : PageVisibility.SaysNothing;

        string[] lines = pageText.Split('\n');
        var inside = new List<string>();
        for (int i = fences.Open + 1; i < fences.Close; i++)
            inside.Add(lines[i]);

        // A tab used as INDENTATION is the one thing YAML forbids outright:
        // the build's own parser throws on it and stops the whole build, so
        // there is no site verdict to mirror.
        foreach (string line in inside)
        {
            if (TrimCarriageReturn(line).StartsWith('\t'))
                return PageVisibility.CannotTell;
        }

        return AnswerFromLines(inside, keys);
    }

    /// <summary>The same question, asked of the frontmatter lines on their own.</summary>
    internal static PageVisibility AnswerFromLines(
        IReadOnlyList<string> lines, IReadOnlyList<(string Name, bool IsDraftFamily)> keys)
    {
        foreach (var key in keys)
        {
            if (LastTopLevelEntry(key.Name, lines) is not { } entry) continue;
            ScalarReading? scalar = ReadScalar(entry.Value, entry.NextLine);
            return key.IsDraftFamily ? DraftFamilyAnswer(scalar) : PublishFamilyAnswer(scalar);
        }

        // No key of this page's own, but one of the names appears indented —
        // nested inside some other mapping, or inside a block of text. It may
        // be nothing to do with this page, and it may be everything; either
        // way this reader is not the one to decide.
        foreach (var key in keys)
        {
            if (HasIndentedLine(key.Name, lines)) return PageVisibility.CannotTell;
        }
        return PageVisibility.SaysNothing;
    }

    /// <summary>
    /// What <c>publish:</c> and <c>publishForSection&lt;N&gt;:</c> mean.
    ///
    /// <para>The value reaches Quartz as whatever PyYAML made of it, and
    /// <c>patches/publish.ts</c> holds the page back for exactly two of those:
    /// the boolean false, and the string <c>"false"</c> spelled that way and no
    /// other.</para>
    /// </summary>
    internal static PageVisibility PublishFamilyAnswer(ScalarReading? scalar)
    {
        if (scalar is not { } reading) return PageVisibility.CannotTell;
        if (reading.WasQuoted)
        {
            // Quoted, so PyYAML keeps it a string and hands that string on.
            // `"false"` is the one string that hides a page; `"False"` is a
            // page students CAN see, which looks like a typo and is the
            // measured behaviour.
            return string.Equals(reading.Value, "false", StringComparison.Ordinal)
                ? PageVisibility.Hidden
                : PageVisibility.Visible;
        }
        if (IsYamlFalse(reading.Value)) return PageVisibility.Hidden;
        // Everything else — `true`, `maybe`, `0`, `oN`, nothing at all — is
        // published. Forgetting the flag, or writing something the build cannot
        // make a boolean of, leaves a page visible.
        return PageVisibility.Visible;
    }

    /// <summary>
    /// What <c>draft:</c> and <c>draftSection&lt;N&gt;:</c> mean — the older
    /// spelling, with the OPPOSITE polarity.
    ///
    /// <para>The build asks <c>build_site.py</c> → <c>_as_bool</c> whether the
    /// page is a draft: a real boolean counts as itself, and anything else is
    /// turned into text, trimmed and lowercased, and compared with "true". So
    /// an unquoted <c>yes</c> hides the page and a quoted <c>"yes"</c> does
    /// not, while <c>TrUe</c> hides it either way.</para>
    /// </summary>
    internal static PageVisibility DraftFamilyAnswer(ScalarReading? scalar)
    {
        if (scalar is not { } reading) return PageVisibility.CannotTell;
        if (!reading.WasQuoted && IsYamlTrue(reading.Value)) return PageVisibility.Hidden;
        // Trim() here on purpose, and it is the ONE place in this file where a
        // framework trim is right: this mirrors Python's `str(value).strip()`
        // inside `_as_bool`, which strips every kind of whitespace including
        // the non-breaking space. The build really does read `draft: "true "`
        // as a draft.
        if (string.Equals(reading.Value.Trim().ToLowerInvariant(), "true", StringComparison.Ordinal))
            return PageVisibility.Hidden;
        return PageVisibility.Visible;
    }

    /// <summary>
    /// Can this value be copied onto another key's line exactly as written?
    ///
    /// <para>Anything a teacher fits on one line can: copying the characters
    /// means the build makes the same thing of the copy as it made of the
    /// original, whatever that turns out to be, and no reader can invert it by
    /// misreading it. A value that CONTINUES onto the next line cannot — the
    /// copy would be a key with nothing after it, which is a different page,
    /// and for a block scalar it is YAML the build cannot read at all.</para>
    /// </summary>
    internal static bool IsCompleteOnItsOwnLine(string rawValue)
    {
        string value = TrimYamlSpaces(rawValue);
        if (value.Length == 0) return false;
        return !value.StartsWith('|') && !value.StartsWith('>');
    }

    // ---- Reading one value ------------------------------------------------

    /// <summary>
    /// Everything after a key's colon, read — or null when this reader will not
    /// guess.
    /// </summary>
    /// <param name="nextLine">
    /// The first line below the key that could be a VALUE — blank lines and
    /// comments already stepped over, at any indent — or null when there is
    /// none before the end of the block.
    /// <para>If it is INDENTED, the key's value continues onto it, and this
    /// reader does not follow it: the answer is <c>null</c>. That holds
    /// however complete the key's own line looks, which is the whole point —
    /// see the body.</para>
    /// </param>
    internal static ScalarReading? ReadScalar(string rawValue, string? nextLine)
    {
        string value = TrimYamlSpaces(rawValue);

        // A value CONTINUES onto the next line whenever the next line that
        // could be one is indented — and that is true however complete the
        // key's own line looks.
        //
        // `publish:` on its own is null, and null publishes the page, UNLESS
        // the value is sitting below it. But so is `publish: false` with an
        // indented `false` under it: YAML folds the two into the one plain
        // scalar "false false", a STRING that is not "false", and the page is
        // PUBLISHED. Measured, python-frontmatter 1.3.0 / PyYAML 6.0.3 —
        // `false`, `no`, `off` and `FALSE` all behave that way.
        //
        // Reading the key's line alone therefore called such a page HIDDEN,
        // confidently, while students could read it. Confidently is the part
        // that bit: the writer's "already right, change nothing" gate believed
        // it, so asking to hide the page changed nothing at all and the
        // teacher was told it was already hidden. That is the dangerous
        // direction — this reader will not guess at it. `nextLine` is the
        // first line below that could be a VALUE, so blank lines and comments
        // have already been stepped over and cannot trigger this.
        bool continuesBelow = nextLine is not null
            && (nextLine.StartsWith(' ') || nextLine.StartsWith('\t'));
        if (continuesBelow) return null;

        if (value.Length == 0) return new ScalarReading("", false);

        // A tag (`!!str false`), an anchor (`&flag false`), an alias (`*flag`)
        // or a block scalar (`>-` and the value on the next line) all change
        // what the value IS, and a flow collection (`[false]`) can run over
        // several lines. The last three are characters YAML RESERVES: measured,
        // `publish: %`, `publish: @x` and `` publish: `x `` each STOP THE
        // BUILD, so there is no site verdict to mirror.
        char first = value[0];
        if (first is '!' or '&' or '*' or '|' or '>' or '[' or '{' or '%' or '@' or '`') return null;
        if (value == "-" || value.StartsWith("- ", StringComparison.Ordinal)) return null;

        string withoutComment = TrimYamlSpaces(StripComment(value));
        if (withoutComment.Length == 0)
        {
            // The whole value was a comment, so the key is null.
            return new ScalarReading("", false);
        }

        if (withoutComment.StartsWith('"'))
        {
            if (withoutComment.Length < 2 || !withoutComment.EndsWith('"')) return null;
            string inside = withoutComment[1..^1];
            // A backslash is an escape and a second quote is a second string;
            // either way the characters here are not the value.
            if (inside.Contains('\\') || inside.Contains('"')) return null;
            return new ScalarReading(inside, true);
        }

        if (withoutComment.StartsWith('\''))
        {
            if (withoutComment.Length < 2 || !withoutComment.EndsWith('\'')) return null;
            string inside = withoutComment[1..^1];
            // `''` is how a single-quoted string spells one quote. A backslash
            // is NOT an escape inside single quotes, so `publish: 'fal\se'` is
            // the string "fal\se" and the page is published — measured.
            if (inside.Contains('\'')) return null;
            return new ScalarReading(inside, true);
        }

        // An unquoted value carrying its own `key: value` is a second mapping
        // where YAML expects a scalar. Measured: `publish: false: true` stops
        // the build.
        if (withoutComment.Contains(": ", StringComparison.Ordinal) || withoutComment.EndsWith(':'))
            return null;

        return new ScalarReading(withoutComment, false);
    }

    /// <summary>
    /// A value with its trailing <c># comment</c> taken off.
    ///
    /// <para>A <c>#</c> only starts a comment when it is outside quotes and
    /// something other than text comes before it — <c>publish: true#x</c> is
    /// the string "true#x", which was measured rather than assumed.</para>
    /// </summary>
    internal static string StripComment(string value)
    {
        var kept = new StringBuilder();
        char? openingQuote = null;
        char? previous = null;
        foreach (char character in value)
        {
            if (openingQuote is { } quote)
            {
                if (character == quote) openingQuote = null;
                kept.Append(character);
                previous = character;
                continue;
            }
            if (character is '"' or '\'')
            {
                openingQuote = character;
                kept.Append(character);
                previous = character;
                continue;
            }
            if (character == '#' && (previous is null || previous is ' ' or '\t'))
                return kept.ToString();
            kept.Append(character);
            previous = character;
        }
        return kept.ToString();
    }

    /// <summary>
    /// A string without the spaces and tabs at either end of it, and without a
    /// Windows line ending's carriage return.
    /// </summary>
    /// <remarks>
    /// Written out rather than using <c>Trim()</c>, which strips every Unicode
    /// space — including the non-breaking space Option-Space types on a Mac.
    /// YAML's whitespace is a space and a tab and nothing else.
    /// </remarks>
    internal static string TrimYamlSpaces(string text)
    {
        string bare = TrimCarriageReturn(text);
        int start = 0;
        int end = bare.Length;
        while (start < end && (bare[start] == ' ' || bare[start] == '\t')) start++;
        while (end > start && (bare[end - 1] == ' ' || bare[end - 1] == '\t')) end--;
        return bare[start..end];
    }

    /// <summary>A line without the carriage return a Windows-written file leaves on it.</summary>
    internal static string TrimCarriageReturn(string line) =>
        line.EndsWith('\r') ? line[..^1] : line;

    // ---- Finding the key --------------------------------------------------

    /// <summary>
    /// A key's line inside the block: where it is, the text after its colon,
    /// and the first non-blank line below it. The LAST such line wins, because
    /// that is the one PyYAML keeps when a page carries the same key twice.
    /// </summary>
    internal static (int Index, string Value, string? NextLine)? LastTopLevelEntry(
        string key, IReadOnlyList<string> lines)
    {
        (int Index, string Value, string? NextLine)? found = null;
        for (int index = 0; index < lines.Count; index++)
        {
            string bare = TrimCarriageReturn(lines[index]);
            if (bare.StartsWith(' ') || bare.StartsWith('\t')) continue;
            if (ValuePart(key, bare) is not { } value) continue;
            found = (index, value, FirstNonBlankLine(index, lines));
        }
        return found;
    }

    /// <summary>
    /// The first line below this one that could be a VALUE, or null when there
    /// is none before the end of the block.
    /// </summary>
    /// <remarks>
    /// Blank lines and comment lines are skipped, because YAML skips them: a
    /// value indented under its key still belongs to that key with an empty
    /// line or a <c># note</c> in between. Both measured — <c>publish:</c>
    /// followed by an indented comment is a null and PUBLISHES the page, while
    /// the same comment with an indented <c>false</c> under it hides it.
    /// </remarks>
    internal static string? FirstNonBlankLine(int index, IReadOnlyList<string> lines)
    {
        for (int position = index + 1; position < lines.Count; position++)
        {
            string bare = TrimCarriageReturn(lines[position]);
            string content = TrimYamlSpaces(bare);
            if (content.Length > 0 && !content.StartsWith('#')) return bare;
        }
        return null;
    }

    /// <summary>Does one of the four names appear INDENTED anywhere in the block?</summary>
    internal static bool HasIndentedLine(string key, IReadOnlyList<string> lines)
    {
        foreach (string line in lines)
        {
            string bare = TrimCarriageReturn(line);
            if (!bare.StartsWith(' ') && !bare.StartsWith('\t')) continue;
            int start = 0;
            while (start < bare.Length && (bare[start] == ' ' || bare[start] == '\t')) start++;
            if (ValuePart(key, bare[start..]) is not null) return true;
        }
        return false;
    }

    /// <summary>
    /// Everything after this key's colon on this line, or null when the line
    /// names some other key.
    /// </summary>
    /// <remarks>
    /// <para>Three spellings of the key itself are accepted, because all three
    /// are the same key to YAML and each is cheap to recognise: <c>publish:</c>,
    /// <c>publish :</c> and <c>"publish":</c>. <c>publishForSection1:</c> is NOT
    /// <c>publish:</c>, which is why the colon has to be found rather than
    /// assumed.</para>
    /// <para>And the colon must be FOLLOWED by a space, a tab or the end of the
    /// line, because that is what makes the line a mapping at all. Measured:
    /// <c>publish:false</c> is one plain scalar, so a page whose whole
    /// frontmatter is that line arrives at Quartz with no keys and is PUBLISHED
    /// — and a page with another key beside it stops the build. Either way it is
    /// not this page's flag, and reading it as one called a live page
    /// hidden.</para>
    /// </remarks>
    internal static string? ValuePart(string key, string line)
    {
        string rest;
        if (line.StartsWith("\"" + key + "\"", StringComparison.Ordinal))
            rest = line[(key.Length + 2)..];
        else if (line.StartsWith("'" + key + "'", StringComparison.Ordinal))
            rest = line[(key.Length + 2)..];
        else if (line.StartsWith(key, StringComparison.Ordinal))
            rest = line[key.Length..];
        else
            return null;

        int at = 0;
        while (at < rest.Length && (rest[at] == ' ' || rest[at] == '\t')) at++;
        if (at >= rest.Length || rest[at] != ':') return null;
        at++;
        if (at < rest.Length && rest[at] != ' ' && rest[at] != '\t') return null;
        return rest[at..];
    }

    /// <summary>
    /// Every line of this page's frontmatter that names this key at the top
    /// level, in the order they appear.
    /// </summary>
    /// <remarks>
    /// The same matcher the reading uses, so a key the reader can see is a key
    /// a writer can rewrite. A <c>"publish": false</c> was invisible to a plain
    /// prefix test, which meant the writer inserted a SECOND <c>publish: true</c>
    /// above it — and PyYAML keeps the LAST of two, so the page stayed hidden
    /// while the teacher was told it had been published.
    /// </remarks>
    internal static List<int> TopLevelLineIndices(string pageText, string key)
    {
        var found = new List<int>();
        if (FenceIndices(pageText) is not { } fences) return found;
        string[] lines = pageText.Split('\n');
        for (int index = fences.Open + 1; index < fences.Close; index++)
        {
            string bare = TrimCarriageReturn(lines[index]);
            if (bare.StartsWith(' ') || bare.StartsWith('\t')) continue;
            if (ValuePart(key, bare) is not null) found.Add(index);
        }
        return found;
    }

    // ---- Finding the block ------------------------------------------------

    /// <summary>
    /// Is this line one of the fences around a page's frontmatter?
    /// </summary>
    /// <remarks>
    /// Three dashes OR MORE, with nothing after them but spaces and tabs —
    /// which is python-frontmatter's own boundary (<c>^-{3,}\s*$</c>), and
    /// therefore the build's. A page fenced with <c>----</c> really does have
    /// frontmatter, and reading it as an ordinary page said a hidden page was
    /// visible. Note that <c>...</c> is NOT a fence here: python-frontmatter
    /// does not accept one, and accepting it read the block as ending early.
    /// </remarks>
    internal static bool IsFence(string line)
    {
        string bare = TrimYamlSpaces(line);
        if (bare.Length < 3) return false;
        foreach (char character in bare)
        {
            if (character != '-') return false;
        }
        return true;
    }

    /// <summary>
    /// Where a page's two fences are, whatever is between them — or null when
    /// there is no complete block.
    /// </summary>
    /// <remarks>
    /// Leading blank lines are skipped before the opening fence:
    /// python-frontmatter accepts them, so the build reads the block and this
    /// reader had better read the same one. Kept separate from
    /// <see cref="Answer(string, int)"/> because a WRITER still needs to find
    /// the block on a page the build cannot parse: editing the line in place
    /// leaves the teacher's own frontmatter where they put it, while treating
    /// the page as having none would prepend a second block and turn theirs
    /// into body text on the student's site.
    /// </remarks>
    internal static (int Open, int Close)? FenceIndices(string pageText)
    {
        string[] lines = pageText.Split('\n');
        int open = 0;
        while (open < lines.Length && TrimYamlSpaces(lines[open]).Length == 0) open++;
        if (open >= lines.Length || !IsFence(lines[open])) return null;
        for (int index = open + 1; index < lines.Length; index++)
        {
            if (IsFence(lines[index])) return (open, index);
        }
        return null;
    }

    /// <summary>
    /// True when the page starts with a fence that is never closed — there IS
    /// frontmatter here, and it is not something to answer about.
    /// </summary>
    internal static bool OpensAFence(string pageText)
    {
        foreach (string line in pageText.Split('\n'))
        {
            if (TrimYamlSpaces(line).Length == 0) continue;
            return IsFence(line);
        }
        return false;
    }
}

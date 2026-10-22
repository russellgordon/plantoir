namespace Plantoir.Core.Models;

/// <summary>
/// Which figure fences a page holds (#581, the mac's #495) — a C# port of
/// <c>scripts/markdown_code.py</c> → <c>fenced_blocks</c>, by way of the mac's
/// <c>FigureFenceScan.swift</c>, so the app, the build and the mac agree on
/// <c>contracts/shared-rules.json</c> → <c>figureFences.fences.cases</c>.
/// </summary>
/// <remarks>
/// <para><b>Why a walker of its own, not <see cref="MarkdownCode.CodeRanges"/></b>
/// (the mac's plan review S1). The #313 rule opens a fence only when a line's
/// body STARTS with the fence characters, so <c>- ```tikz</c> is paragraph
/// text there, and its closing <c>```</c> then OPENS a fence that runs to the
/// end of the page. The Python has the same split: <c>code_ranges</c> keeps
/// #313's rule and <c>fenced_blocks</c> is this walker.</para>
/// <para>The rule, each step the Python's: every <c>%%…%%</c> comment is removed
/// first (lazy, across lines, an unpaired <c>%%</c> is text); a line's quote
/// markers give its depth; a fence opens on a body that starts with three or
/// more backticks or tildes — or does so after a list marker, or after further
/// containers on that line, which marks the block NESTED; backticks with
/// another backtick later on the line are not a fence; it closes at its own
/// depth on a run of the same character at least as long with only
/// whitespace after it; the language is the info string's first word, exactly
/// (<c>TikZ</c> is not <c>tikz</c>).</para>
/// <para>Lines are split on <c>\n</c> ONLY, one trailing <c>\r</c> taken off, as
/// <c>str.find("\n")</c> splits them — a lone <c>\r</c> is text. Everything the
/// rule looks at is ASCII, so it works on UTF-16 units; the caller decodes the
/// page so that a byte-order mark stays a character, as Python's
/// <c>utf-8</c> reader keeps it (<see cref="ObsidianFigureAddOns.KindsUsed"/>).</para>
/// </remarks>
public static class FigureFenceScan
{
    /// <summary>One fenced block: the info string's first word as written, the 1-based line of its opening fence, and whether it opened after a second container.</summary>
    public sealed record Block(string Lang, int Line, bool Nested);

    private readonly record struct FenceRun(char Character, int Length, int RestStart);

    /// <summary>Python's <c>str.split()</c> whitespace: what <c>info.split(None, 1)</c> splits the first word off at.</summary>
    private static readonly HashSet<int> PythonWhitespace = new()
    {
        0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x85, 0xA0, 0x1680,
        0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A,
        0x2028, 0x2029, 0x202F, 0x205F, 0x3000,
    };

    /// <summary>The kinds among <paramref name="kinds"/> the page holds as fences that are not nested — what the build would draw.</summary>
    public static ISet<string> Kinds(string text, IReadOnlySet<string> kinds)
    {
        var found = new HashSet<string>(StringComparer.Ordinal);
        foreach (var block in Blocks(text))
            if (!block.Nested && kinds.Contains(block.Lang)) found.Add(block.Lang);
        return found;
    }

    /// <summary>Every fenced block on the page, in order.</summary>
    public static List<Block> Blocks(string original)
    {
        var (text, origin) = WithoutComments(original);
        var found = new List<Block>();
        (char Character, int Length, int Depth)? open = null;

        int lineStart = 0, length = text.Length;
        while (lineStart <= length)
        {
            int newlineAt = text.IndexOf('\n', lineStart);
            int lineEnd = newlineAt < 0 ? length : newlineAt;
            int end = lineEnd;
            if (end > lineStart && text[end - 1] == '\r') end--;
            var (depth, bodyStart) = QuoteDepthAndBody(text, lineStart, end);

            if (open is { } closing && depth < closing.Depth) open = null;

            if (open is { } fence)
            {
                int contentStart = AfterQuoteMarkers(text, lineStart, end, fence.Depth);
                if (depth == fence.Depth && FenceRunAt(text, contentStart, end) is { } run
                    && run.Character == fence.Character && run.Length >= fence.Length
                    && IsBlank(text, run.RestStart, end))
                    open = null;
            }
            else
            {
                var run = FenceRunAt(text, bodyStart, end);
                bool nested = false;
                int quotesAfterMarker = 0;
                if (run is null && MarkerEnd(text, bodyStart, end, leadingSpaces: true) is int afterMarker)
                {
                    int marker = afterMarker;
                    run = FenceRunAt(text, marker, end);
                    while (run is null)
                    {
                        if (NestedContainer(text, marker, end) is not { } container) break;
                        nested = true;
                        if (container.IsQuote) quotesAfterMarker++;
                        marker = container.End;
                        run = FenceRunAt(text, marker, end);
                    }
                }
                if (run is { } opener && !(opener.Character == '`' && HoldsABacktick(text, opener.RestStart, end)))
                {
                    int place = origin is null ? lineStart : origin[lineStart];
                    found.Add(new Block(FirstWord(text, opener.RestStart, end), LineNumber(original, place), nested));
                    open = (opener.Character, opener.Length, depth + quotesAfterMarker);
                }
            }

            if (newlineAt < 0) break;
            lineStart = lineEnd + 1;
        }
        return found;
    }

    private static (string Text, int[]? Origin) WithoutComments(string text)
    {
        var comments = new List<(int Start, int End)>();
        int position = 0;
        while (true)
        {
            int start = text.IndexOf("%%", position, StringComparison.Ordinal);
            if (start < 0) break;
            int close = text.IndexOf("%%", start + 2, StringComparison.Ordinal);
            if (close < 0) break;
            comments.Add((start, close + 2));
            position = close + 2;
        }
        if (comments.Count == 0) return (text, null);
        var kept = new System.Text.StringBuilder(text.Length);
        var origin = new List<int>(text.Length + 1);
        int last = 0;
        foreach (var (start, end) in comments)
        {
            for (int i = last; i < start; i++) { kept.Append(text[i]); origin.Add(i); }
            last = end;
        }
        for (int i = last; i < text.Length; i++) { kept.Append(text[i]); origin.Add(i); }
        origin.Add(text.Length);
        return (kept.ToString(), origin.ToArray());
    }

    private static int LineNumber(string text, int offset)
    {
        int line = 1;
        for (int i = 0; i < offset && i < text.Length; i++) if (text[i] == '\n') line++;
        return line;
    }

    private static bool IsSpaceOrTab(char c) => c == ' ' || c == '\t';

    /// <summary><c>_WHITESPACE</c>: ASCII only, so every language agrees.</summary>
    private static bool IsRuleWhitespace(char c) => c is ' ' or '\t' or '\r' or '\f' or '\v';

    private static bool IsBlank(string text, int start, int end)
    {
        for (int i = start; i < end; i++) if (!IsRuleWhitespace(text[i])) return false;
        return true;
    }

    private static bool HoldsABacktick(string text, int start, int end)
    {
        for (int i = start; i < end; i++) if (text[i] == '`') return true;
        return false;
    }

    private static int AfterSpacesAndTabs(string text, int start, int end)
    {
        int i = start;
        while (i < end && IsSpaceOrTab(text[i])) i++;
        return i;
    }

    private static bool IsDigit(char c) => c >= '0' && c <= '9';

    /// <summary><c>_QUOTE_MARKERS</c>: <c>^(?:[ \t]*&gt;)+ ?</c>.</summary>
    private static (int Depth, int BodyStart) QuoteDepthAndBody(string text, int start, int end)
    {
        int depth = 0, position = start;
        while (true)
        {
            int next = AfterSpacesAndTabs(text, position, end);
            if (next < end && text[next] == '>') { depth++; position = next + 1; continue; }
            break;
        }
        if (depth == 0) return (0, start);
        if (position < end && text[position] == ' ') position++;
        return (depth, position);
    }

    /// <summary><c>_strip_quote_markers</c>: the first <paramref name="depth"/> markers (and one space after each) taken off.</summary>
    private static int AfterQuoteMarkers(string text, int start, int end, int depth)
    {
        int position = start;
        for (int taken = 0; taken < depth; taken++)
        {
            int scan = AfterSpacesAndTabs(text, position, end);
            if (scan >= end || text[scan] != '>') break;
            position = scan + 1;
            if (position < end && text[position] == ' ') position++;
        }
        return position;
    }

    /// <summary><c>_FENCE</c>: <c>^[ \t]*(`{3,}|~{3,})(.*)$</c>.</summary>
    private static FenceRun? FenceRunAt(string text, int start, int end)
    {
        int runStart = AfterSpacesAndTabs(text, start, end);
        if (runStart >= end) return null;
        char character = text[runStart];
        if (character != '`' && character != '~') return null;
        int runEnd = runStart;
        while (runEnd < end && text[runEnd] == character) runEnd++;
        if (runEnd - runStart < 3) return null;
        return new FenceRun(character, runEnd - runStart, runEnd);
    }

    /// <summary>A bullet (<c>[-*+]</c>) or one to nine digits and <c>.</c> or <c>)</c>, then at least one space or tab.</summary>
    private static int? MarkerEnd(string text, int start, int end, bool leadingSpaces)
    {
        int position = leadingSpaces ? AfterSpacesAndTabs(text, start, end) : start;
        if (position >= end) return null;
        char first = text[position];
        if (first is '-' or '*' or '+') position++;
        else if (IsDigit(first))
        {
            int digits = 0;
            while (position < end && IsDigit(text[position])) { digits++; position++; }
            if (digits > 9 || position >= end) return null;
            if (text[position] != '.' && text[position] != ')') return null;
            position++;
        }
        else return null;
        if (position >= end || !IsSpaceOrTab(text[position])) return null;
        return AfterSpacesAndTabs(text, position, end);
    }

    /// <summary><c>_NESTED_CONTAINER</c>: a second marker, or <c>&gt;</c> and one optional space or tab.</summary>
    private static (int End, bool IsQuote)? NestedContainer(string text, int start, int end)
    {
        if (MarkerEnd(text, start, end, leadingSpaces: false) is int afterMarker) return (afterMarker, false);
        if (start < end && text[start] == '>')
        {
            int position = start + 1;
            if (position < end && IsSpaceOrTab(text[position])) position++;
            return (position, true);
        }
        return null;
    }

    /// <summary>The info string's first word: ASCII whitespace trimmed, then split at Python's whitespace.</summary>
    private static string FirstWord(string text, int start, int end)
    {
        int first = start, last = end;
        while (first < last && IsRuleWhitespace(text[first])) first++;
        while (last > first && IsRuleWhitespace(text[last - 1])) last--;
        var word = new System.Text.StringBuilder();
        bool started = false;
        foreach (var rune in text[first..last].EnumerateRunes())
        {
            if (PythonWhitespace.Contains(rune.Value))
            {
                if (started) break;
                continue;
            }
            started = true;
            word.Append(rune.ToString());
        }
        return word.ToString();
    }
}

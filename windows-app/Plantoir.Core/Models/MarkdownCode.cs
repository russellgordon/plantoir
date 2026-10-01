using System.Text;
using System.Text.RegularExpressions;

namespace Plantoir.Core.Models;

/// <summary>
/// Where a page's CODE and <c>%%</c> COMMENTS are, so that a link written
/// inside either is not read — or rewritten — as a link (#339, the mac's #313
/// and #331). One definition for every link reader and rewriter in this app.
/// </summary>
/// <remarks>
/// <para>A port, rule for rule, of the shared <c>scripts/markdown_code.py</c>
/// (the build's and the installer's reader) and of the mac's
/// <c>MarkdownCode.swift</c>; the rule is written down to be implemented from
/// in <c>contracts/shared-rules.json → readingALink.whatIsCode</c> and
/// <c>whatIsAComment</c>, with its cases in <c>readingALink.cases</c>. In short:
/// a fence opens on a line whose body (quote markers off, then leading blanks)
/// starts with three or more backticks or tildes — unless backticks with
/// another backtick later on the line — belongs to its opener's quote depth,
/// and closes on a line at that depth with a run of the same character at
/// least as long and nothing but blanks after it; paragraphs break at blank
/// lines, fences, a deeper quote, list items, headings, table rows and rule
/// lines; inside a paragraph a run of N backticks closes at the next run of
/// EXACTLY N. Comments are masked FIRST, as Quartz does: code is found in the
/// page with every comment removed and mapped back.</para>
/// <para>Offsets are UTF-16 positions in the page as written. Every character
/// the rule looks at is ASCII, so they agree with the Python's code points on
/// everything that matters. The page is never changed: a rewriter skips by
/// offset. (Blanking code with spaces, as <c>WikiLinks.WithoutCode</c> used to,
/// is fine for reading and a trap for writing: every "was it renamed?" check
/// passes while the teacher's example is replaced by spaces.)</para>
/// <para>Rejected, as on the mac: a real Markdown parser (the Swift and C#
/// apps cannot share it, and three readers that disagree at exactly the
/// contract's edges is what #313 was filed to end).</para>
/// </remarks>
public static class MarkdownCode
{
    private static readonly Regex QuoteMarkers = new(@"^(?:[ \t]*>)+ ?", RegexOptions.Compiled);
    private static readonly Regex Fence = new(@"^[ \t]*(`{3,}|~{3,})(.*)$", RegexOptions.Compiled);
    private static readonly Regex BlockStart = new(
        @"^[ \t]*(?:[-*+](?:[ \t]|$)|[0-9]{1,9}[.)](?:[ \t]|$)|#{1,6}(?:[ \t]|$)|\|" +
        @"|(?:-[ \t]*){3,}$|(?:\*[ \t]*){3,}$|(?:_[ \t]*){3,}$|(?:=[ \t]*){3,}$)", RegexOptions.Compiled);
    private static readonly Regex Heading = new(@"^[ \t]*#{1,6}(?:[ \t]|$)", RegexOptions.Compiled);
    private const string Whitespace = " \t\r\f\v";

    /// <summary>Every <c>%%…%%</c> comment, lazy, left to right, across lines; a last unpaired <c>%%</c> is text.</summary>
    public static List<(int Start, int End)> CommentRanges(string text)
    {
        var found = new List<(int, int)>();
        int position = 0;
        while (true)
        {
            int start = text.IndexOf("%%", position, StringComparison.Ordinal);
            if (start < 0) break;
            int end = text.IndexOf("%%", start + 2, StringComparison.Ordinal);
            if (end < 0) break;
            found.Add((start, end + 2));
            position = end + 2;
        }
        return found;
    }

    /// <summary>
    /// Every stretch that is CODE — comments are NOT in it (a curriculum
    /// marker is a comment, and asking whether one is in code must not answer
    /// yes). Found with the comments removed, mapped back to the page.
    /// </summary>
    public static List<(int Start, int End)> CodeRanges(string text)
    {
        var comments = CommentRanges(text);
        if (comments.Count == 0) return CodeRangesAsWritten(text);
        var kept = new StringBuilder();
        var origin = new List<int>();
        int last = 0;
        foreach (var (start, end) in comments)
        {
            kept.Append(text, last, start - last);
            for (int i = last; i < start; i++) origin.Add(i);
            last = end;
        }
        kept.Append(text, last, text.Length - last);
        for (int i = last; i < text.Length; i++) origin.Add(i);
        origin.Add(text.Length);
        return CodeRangesAsWritten(kept.ToString())
            .Select(range => (origin[range.Start], origin[range.End - 1] + 1))
            .ToList();
    }

    /// <summary>Code and comments together, sorted and merged: where a <c>[[</c> does not start a link.</summary>
    public static List<(int Start, int End)> NotALinkRanges(string text) =>
        Merge(CodeRanges(text).Concat(CommentRanges(text)).OrderBy(r => r.Start).ThenBy(r => r.End));

    /// <summary>Whether <paramref name="position"/> falls inside one of <paramref name="ranges"/>.</summary>
    public static bool IsIn(IReadOnlyList<(int Start, int End)> ranges, int position) =>
        RangeHolding(ranges, position) is not null;

    /// <summary>
    /// The matches of <paramref name="pattern"/> that do not START inside code
    /// or a comment. A match that does is not merely dropped: the search
    /// starts again where that range ENDS, so "Type <c>`[[`</c> to start one:
    /// [[Real Page]]" still finds the real link.
    /// </summary>
    public static List<Match> MatchesOutside(Regex pattern, string text, IReadOnlyList<(int Start, int End)>? ranges = null)
    {
        ranges ??= NotALinkRanges(text);
        var found = new List<Match>();
        int position = 0;
        while (position <= text.Length)
        {
            var match = pattern.Match(text, position);
            if (!match.Success) break;
            if (RangeHolding(ranges, match.Index) is { } holding)
            {
                position = holding.End;
                continue;
            }
            found.Add(match);
            position = match.Length > 0 ? match.Index + match.Length : match.Index + 1;
        }
        return found;
    }

    private static (int Start, int End)? RangeHolding(IReadOnlyList<(int Start, int End)> ranges, int position)
    {
        int low = 0, high = ranges.Count - 1;
        while (low <= high)
        {
            int middle = (low + high) / 2;
            if (ranges[middle].Start <= position) low = middle + 1; else high = middle - 1;
        }
        if (high < 0) return null;
        var range = ranges[high];
        return range.Start <= position && position < range.End ? range : null;
    }

    private static (int Depth, string Body) QuoteDepthAndBody(string line)
    {
        var markers = QuoteMarkers.Match(line);
        if (!markers.Success) return (0, line);
        return (markers.Value.Count(c => c == '>'), line[markers.Length..]);
    }

    private static bool IsBlank(string text) => text.Trim(Whitespace.ToCharArray()).Length == 0;

    private static void SpansInParagraph(string text, int start, int end, List<(int, int)> ranges)
    {
        int position = start;
        while (position < end)
        {
            char character = text[position];
            if (character == '\\' && position + 1 < end) { position += 2; continue; }
            if (character != '`') { position++; continue; }
            int runEnd = position;
            while (runEnd < end && text[runEnd] == '`') runEnd++;
            int runLength = runEnd - position;
            int closingEnd = -1;
            int scan = runEnd;
            while (scan < end)
            {
                if (text[scan] != '`') { scan++; continue; }
                int otherEnd = scan;
                while (otherEnd < end && text[otherEnd] == '`') otherEnd++;
                if (otherEnd - scan == runLength) { closingEnd = otherEnd; break; }
                scan = otherEnd;
            }
            if (closingEnd < 0) { position = runEnd; continue; }
            ranges.Add((position, closingEnd));
            position = closingEnd;
        }
    }

    private static List<(int Start, int End)> CodeRangesAsWritten(string text)
    {
        var ranges = new List<(int, int)>();
        char? fenceCharacter = null;
        int fenceLength = 0, fenceDepth = 0;
        int paragraphStart = -1, paragraphEnd = -1, paragraphDepth = 0;

        void CloseParagraph()
        {
            if (paragraphStart >= 0) SpansInParagraph(text, paragraphStart, paragraphEnd, ranges);
            paragraphStart = -1;
            paragraphEnd = -1;
        }

        int lineStart = 0;
        int length = text.Length;
        while (lineStart <= length)
        {
            int newline = text.IndexOf('\n', lineStart);
            int lineEnd = newline < 0 ? length : newline;
            int nextStart = lineEnd + 1;
            string line = text[lineStart..lineEnd];
            if (line.EndsWith('\r')) line = line[..^1];
            var (depth, body) = QuoteDepthAndBody(line);

            if (fenceCharacter is not null && depth < fenceDepth) fenceCharacter = null;

            if (fenceCharacter is { } open)
            {
                ranges.Add((lineStart, Math.Min(nextStart, length)));
                var fence = Fence.Match(body);
                if (depth == fenceDepth && fence.Success && fence.Groups[1].Value[0] == open
                    && fence.Groups[1].Value.Length >= fenceLength && IsBlank(fence.Groups[2].Value))
                    fenceCharacter = null;
            }
            else
            {
                var fence = Fence.Match(body);
                if (fence.Success && !(fence.Groups[1].Value[0] == '`' && fence.Groups[2].Value.Contains('`')))
                {
                    CloseParagraph();
                    fenceCharacter = fence.Groups[1].Value[0];
                    fenceLength = fence.Groups[1].Value.Length;
                    fenceDepth = depth;
                    ranges.Add((lineStart, Math.Min(nextStart, length)));
                }
                else if (IsBlank(body))
                {
                    CloseParagraph();
                }
                else
                {
                    if (BlockStart.IsMatch(body) || (paragraphStart >= 0 && depth > paragraphDepth))
                        CloseParagraph();
                    if (paragraphStart < 0)
                    {
                        paragraphStart = lineStart;
                        paragraphDepth = depth;   // the paragraph's FIRST line decides
                    }
                    paragraphEnd = lineEnd;
                    if (Heading.IsMatch(body)) CloseParagraph();
                }
            }

            if (newline < 0) break;
            lineStart = nextStart;
        }
        CloseParagraph();

        return Merge(ranges.Where(r => r.Item1 < r.Item2).OrderBy(r => r.Item1).ThenBy(r => r.Item2)
            .Select(r => (r.Item1, r.Item2)));
    }

    private static List<(int Start, int End)> Merge(IEnumerable<(int Start, int End)> sorted)
    {
        var merged = new List<(int Start, int End)>();
        foreach (var (start, end) in sorted)
        {
            if (merged.Count > 0 && start <= merged[^1].End)
            {
                if (end > merged[^1].End) merged[^1] = (merged[^1].Start, end);
                continue;
            }
            merged.Add((start, end));
        }
        return merged;
    }
}

using System.Text;

namespace Plantoir.Core.Scripting;

/// <summary>
/// Turns raw terminal output into clean display lines.
///
/// A pseudo console converts every "\n" the script prints into "\r\n", so
/// CR followed by LF is an ordinary line ending. Only a LONE carriage
/// return is a spinner redrawing its line — it restarts the current line.
/// ANSI escape sequences (colours, cursor movement, OSC titles) are
/// stripped before the line machine runs.
/// </summary>
public sealed class TranscriptBuilder
{
    public const int MaximumRetainedLines = 4000;

    private readonly List<string> _lines = new();
    private readonly StringBuilder _currentLine = new();
    private bool _hasPendingCarriageReturn;
    private string? _cachedDisplayText;
    private long _version;

    /// <summary>Completed lines, oldest first (capped at MaximumRetainedLines).</summary>
    public IReadOnlyList<string> Lines => _lines;

    /// <summary>The unterminated line under construction.</summary>
    public string CurrentLine => VisibleCurrentLine;

    /// <summary>
    /// The line under construction, unless it is machinery.
    ///
    /// <para>A <c>PLANTOIR_HEALTH:</c> line is a JSON blob, and a teacher
    /// reads this console (CLAUDE.md rule 1). Nothing is lost by hiding it:
    /// <c>scripts/site_health.py</c> prints the human sentence separately,
    /// beside the marker, and that sentence is left alone.</para>
    ///
    /// <para>Hidden here rather than only at <see cref="PushLine"/> because a
    /// pseudo console hands over whatever bytes are ready — the marker and its
    /// payload sit in the current line for as long as it takes the rest of the
    /// line to arrive, and the console renders it in the meantime.</para>
    /// </summary>
    private string VisibleCurrentLine
    {
        get
        {
            string line = _currentLine.ToString();
            return CarriesTheHealthMarker(line) ? "" : line;
        }
    }

    /// <summary>
    /// Whether this line is a health finding's machine-readable half.
    ///
    /// <para>The whole line goes, not just the marker onward: the launchers can
    /// glue the marker to the tail of their own chatter, and what precedes it
    /// there is progress noise rather than a sentence a teacher needs. The
    /// findings themselves are never at risk — <c>ScriptRunner.ReceiveOutput</c>
    /// hands the RAW text to <c>CollectHealthFindings</c>, and only then to
    /// this builder.</para>
    /// </summary>
    private static bool CarriesTheHealthMarker(string line) =>
        line.Contains(Plantoir.Core.Models.SiteHealthFinding.Marker, StringComparison.Ordinal);

    /// <summary>Monotonic counter bumped on every append — cheap change detection.</summary>
    public long Version => _version;

    public void Append(string rawText)
    {
        _cachedDisplayText = null;
        _version++;
        string cleaned = StripControlSequences(rawText);
        foreach (char c in cleaned)
        {
            if (_hasPendingCarriageReturn)
            {
                _hasPendingCarriageReturn = false;
                if (c == '\n') { PushLine(); continue; }
                _currentLine.Clear();               // lone CR: spinner redraw
            }
            if (c == '\n') { PushLine(); }
            else if (c == '\r') { _hasPendingCarriageReturn = true; }
            else { _currentLine.Append(c); }
        }
    }

    private void PushLine()
    {
        string line = _currentLine.ToString();
        _currentLine.Clear();
        // Dropped rather than retained-and-filtered-on-read, so it cannot reach
        // the problem report either: SaveRunTranscript copies Lines wholesale
        // into the report store, and a payload a teacher may not see is not one
        // support should be handed. The trail keeps the check's NAME, which is
        // the part anybody reading the report back would search for.
        if (CarriesTheHealthMarker(line)) return;
        _lines.Add(line);
        if (_lines.Count > MaximumRetainedLines)
            _lines.RemoveRange(0, _lines.Count - MaximumRetainedLines);
    }

    public string DisplayText
    {
        get
        {
            if (_cachedDisplayText is null)
            {
                string current = VisibleCurrentLine;
                var all = current.Length > 0
                    ? _lines.Append(current)
                    : _lines;
                _cachedDisplayText = string.Join("\n", all);
            }
            return _cachedDisplayText;
        }
    }

    /// <summary>The tail of the transcript, built without joining everything.</summary>
    public string RecentText(int maximumCharacters)
    {
        var collected = new List<string>();
        int budget = maximumCharacters;
        string current = VisibleCurrentLine;
        if (current.Length > 0) { collected.Add(current); budget -= current.Length + 1; }
        for (int i = _lines.Count - 1; i >= 0 && budget > 0; i--)
        {
            collected.Add(_lines[i]);
            budget -= _lines[i].Length + 1;
        }
        collected.Reverse();
        return string.Join("\n", collected);
    }

    /// <summary>
    /// Strips ANSI CSI (ESC [ ... final letter), OSC (ESC ] ... BEL), other
    /// two-byte escapes, and control characters below 0x20 except \n \r \t.
    /// </summary>
    public static string StripControlSequences(string text)
    {
        var result = new StringBuilder(text.Length);
        int i = 0;
        while (i < text.Length)
        {
            char c = text[i];
            if (c == '\x1b')
            {
                if (i + 1 < text.Length && text[i + 1] == '[')
                {
                    int j = i + 2;
                    while (j < text.Length && !char.IsAsciiLetter(text[j])) j++;
                    i = j + 1;
                    continue;
                }
                if (i + 1 < text.Length && text[i + 1] == ']')
                {
                    int j = i + 2;
                    while (j < text.Length && text[j] != '\x07') j++;
                    i = j + 1;
                    continue;
                }
                i += 2;
                continue;
            }
            if (c < ' ' && c != '\n' && c != '\r' && c != '\t') { i++; continue; }
            result.Append(c);
            i++;
        }
        return result.ToString();
    }
}

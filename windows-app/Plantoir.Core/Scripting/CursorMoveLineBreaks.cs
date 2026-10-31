using System.Text;

namespace Plantoir.Core.Scripting;

/// <summary>
/// Puts back the line break ConPTY replaces with a cursor move (#623).
///
/// <para><b>What was measured.</b> Under a pseudo console, a script that
/// prints a blank line and then more text in one go - deploy.py's
/// <c>print("…only asked once.\n")</c> followed by <c>input("First time
/// setup…")</c> - does not come out as CR LF CR LF. While the screen has not
/// yet scrolled (PtyDriver's screen is 30 rows, ConPty.cs), ConPTY draws the
/// frame by jumping the cursor: <c>…only asked once.\e[8;1HFirst time
/// setup…</c>. <see cref="TranscriptBuilder.StripControlSequences"/> removes
/// the escape and the two lines become one, so the prompt PtyDriver matched
/// was "…only asked once.First time setup… (letters only):" and
/// verify-deploy.ps1's anchored questions refused it. The same script with
/// the output arriving in separate flushes, or after the screen has
/// scrolled, gets ordinary CR LF and never joins. Bytes recorded with
/// PtyDriver's <c>--bytes-log</c>; documentation/12-windows-app.md →
/// verify-deploy.ps1.</para>
///
/// <para><b>The rule, and why it is this narrow.</b> A cursor position
/// (<c>CSI row;1 H</c> / <c>f</c>) or cursor-next-line (<c>CSI n E</c>) that
/// lands in column 1 while the current line already has text ENDS that line:
/// a CR LF is inserted before the escape, and the escape is passed on for the
/// stripper to remove as before. Nothing else changes. Row tracking (inserting
/// one LF per row skipped, which would also restore the blank line) was
/// rejected: it has to model scrolling and repaints to be right, and getting
/// it wrong duplicates lines. A blank line lost is harmless to every reader of
/// these logs; a line joined to the next is not.</para>
///
/// <para><b>Two users.</b> PtyDriver (#623), so the harnesses match the
/// prompt alone; and, since #661, <see cref="ScriptRunner.ReceiveOutput"/>,
/// the app's single entry point for a launcher's output, so the console, the
/// saved transcript, the question box and the PLANTOIR_HEALTH reader all see
/// the restored breaks. #661 confirmed the joins in the app's own window
/// (x64 Debug, 2026-10-28, i5-8365U): a fresh section's
/// <c>preview.ps1 --build-only</c> saved "📋 Timetable sections for this
/// course: [1]🔎 Preflight: …" and "… course_config.json unchanged.📁 Shared
/// folders …" as one line each, from build_site.py's own
/// <c>print("\n…")</c>. #662's 8192 columns does not help: the jump depends
/// on the screen's ROWS. A question was affected too: <c>print("\nGot
/// x.\n")</c> then <c>input("Continue anyway? [y/N] ")</c> left "Got
/// x.Continue anyway? [y/N] " as the line the question box reads. The setup
/// wizard's colour picker was measured through this stage as well: its
/// footer arrives as <c>\e[24;1HUse ← / → …</c>, becomes its own line, and
/// NewCourseCreator still answers it. documentation/12-windows-app.md →
/// "Line breaks ConPTY draws as cursor moves (#623, #661)".</para>
///
/// <para>Stateful because a read can end in the middle of an escape: an
/// unfinished one is held back until the next <see cref="Process"/> call (or
/// <see cref="Flush"/>).</para>
/// </summary>
public sealed class CursorMoveLineBreaks
{
    private const char Escape = (char)27;
    private readonly StringBuilder _heldBack = new();
    private bool _lineHasText;

    /// <summary>The text with a CR LF put before every cursor move that ends a line.</summary>
    public string Process(string chunk)
    {
        string text = _heldBack.Length > 0 ? _heldBack + chunk : chunk;
        _heldBack.Clear();
        var output = new StringBuilder(text.Length + 8);
        int i = 0;
        while (i < text.Length)
        {
            char c = text[i];
            if (c == Escape)
            {
                int end = EndOfEscape(text, i);
                if (end < 0)
                {
                    // Unfinished: hold it for the next read.
                    _heldBack.Append(text, i, text.Length - i);
                    break;
                }
                string sequence = text.Substring(i, end - i + 1);
                if (_lineHasText && MovesToColumnOne(sequence))
                {
                    output.Append((char)13).Append((char)10);
                    _lineHasText = false;
                }
                output.Append(sequence);
                i = end + 1;
                continue;
            }
            if (c == (char)10 || c == (char)13) _lineHasText = false;
            else if (c >= ' ') _lineHasText = true;
            output.Append(c);
            i++;
        }
        return output.ToString();
    }

    /// <summary>Whatever was held back, at the end of the output.</summary>
    public string Flush()
    {
        string rest = _heldBack.ToString();
        _heldBack.Clear();
        return rest;
    }

    // The index of the escape's last character, or -1 when the text ends first.
    // CSI ends at its final byte (0x40-0x7E); OSC at BEL or ST; anything else
    // is two characters, as StripControlSequences treats it.
    private static int EndOfEscape(string text, int start)
    {
        if (start + 1 >= text.Length) return -1;
        char kind = text[start + 1];
        if (kind == '[')
        {
            for (int j = start + 2; j < text.Length; j++)
                if (text[j] >= (char)0x40 && text[j] <= (char)0x7E) return j;
            return -1;
        }
        if (kind == ']')
        {
            for (int j = start + 2; j < text.Length; j++)
            {
                if (text[j] == (char)7) return j;
                if (text[j] == Escape && j + 1 < text.Length && text[j + 1] == '\\') return j + 1;
            }
            return -1;
        }
        return start + 1;
    }

    // CSI [row][;col] H|f with col 1 or omitted, or CSI [n] E.
    private static bool MovesToColumnOne(string sequence)
    {
        if (sequence.Length < 3 || sequence[1] != '[') return false;
        char final = sequence[^1];
        string parameters = sequence[2..^1];
        foreach (char p in parameters)
            if (!(char.IsAsciiDigit(p) || p == ';')) return false;   // private modes (?25l) and the like
        if (final == 'E') return true;
        if (final != 'H' && final != 'f') return false;
        string[] parts = parameters.Split(';');
        if (parts.Length < 2) return true;                           // no column: column 1
        return parts[1].Length == 0 || parts[1] == "1";
    }
}

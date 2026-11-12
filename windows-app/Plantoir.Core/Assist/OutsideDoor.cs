using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Assist;

/// <summary>
/// How both outside doors (Revise With ▸ Claude… and Codex…, and Fix with
/// Claude… and Fix with Codex… on a section's Problems tab, #736) START their
/// program: one process, built here, so the two doors and the two flows
/// cannot quote differently.
/// </summary>
/// <remarks>
/// <para><b>What everything handed over is: HOSTILE text.</b> The message
/// carries the course's name, page names and what a build said about them;
/// a course imported from somebody else's zip carries its own name. Until
/// 1.9.3 the Claude door joined its command line by hand and ran it under
/// <c>cmd /k</c> (through Windows Terminal when it was there), and cmd's
/// quote rule (more than two quotes, no <c>/s</c>: strip the first and the
/// last) left the message OUTSIDE quotes, so cmd read the course's name as
/// part of the command. Measured with a stub program on 2026-11-11, and the
/// old builder is kept in the tests as the must-fail.</para>
///
/// <para><b>An <c>.exe</c> is started DIRECTLY</b>, with no command
/// interpreter and no Windows Terminal in front: its command line is the
/// standard quoting of each argument (<see cref="ScriptRunner.QuotedArgument"/>)
/// and nothing parses it but the program itself, so <c>&amp; | &lt; &gt; ^ ! %</c>
/// are ordinary characters. ShellExecute opens it in a console window of its
/// own, which on Windows 11 is Windows Terminal anyway when that is the
/// default terminal.</para>
///
/// <para><b>Rejected: <c>wt.exe</c> with an argument vector.</b> Measured on
/// this PC (Windows Terminal from the Store, 2026-11-11): Windows Terminal
/// expands <c>%NAME%</c> in the command line it is given, quoted or not, with
/// no escape for it, and re-joins the arguments with its own quoting, which
/// loses an escaped quote and a trailing backslash; and it splits at every
/// <c>;</c>. Each would need neutralising in the message, and the first
/// cannot be without changing the text.</para>
///
/// <para><b>A <c>.cmd</c>/<c>.bat</c> shim</b> (npm's <c>claude.cmd</c> and
/// <c>codex.cmd</c>) cannot be started without cmd, so it goes through
/// <c>cmd.exe /v:off /s /k "…"</c> (<see cref="CmdArguments"/>), still with
/// no Windows Terminal in front. <c>/v:off</c> makes <c>!</c> ordinary even
/// for a teacher whose registry turns delayed expansion on; cmd's
/// metacharacters get a caret wherever cmd reads them unquoted, once per cmd
/// parse (twice for a shim: its <c>%*</c> is parsed again); and every
/// <c>%</c> is followed by a quote (<see cref="ForCmd"/>), which keeps cmd
/// from reading <c>%NAME%</c> as a variable (it has no escape for <c>%</c>
/// on a command line, and none inside quotes at all). A line break,
/// which a command line cannot carry, becomes a space on this path only.</para>
/// </remarks>
public static class OutsideDoor
{
    /// <summary>cmd itself, by its full path, never whatever is called cmd.exe on PATH.</summary>
    public static string Cmd => Path.Combine(Environment.SystemDirectory, "cmd.exe");

    /// <summary>A program cmd has to run: npm's shims are <c>.cmd</c> files.</summary>
    public static bool IsBatch(string program) =>
        program.EndsWith(".cmd", StringComparison.OrdinalIgnoreCase) ||
        program.EndsWith(".bat", StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// The process that opens a door on <paramref name="program"/> with
    /// <paramref name="arguments"/>, in <paramref name="folder"/>.
    /// <paramref name="keepOpen"/> is false only for a test, which needs cmd
    /// to end (<c>/c</c>) where a teacher's window stays (<c>/k</c>).
    /// </summary>
    public static ProcessStartInfo StartInfo(string program, IReadOnlyList<string> arguments, string folder,
                                             bool keepOpen = true)
    {
        // EVERY argument and the working folder are cleaned of the control
        // characters that break a command line BEFORE any quoting (Clean), so
        // neither shape and neither start mode can be split by one. The
        // program's own path is ours (FindClaude/FindCodex), never hostile
        // input, so it is not touched.
        var clean = new List<string>(arguments.Count);
        foreach (string argument in arguments) clean.Add(Clean(argument));
        string workingFolder = Clean(folder);
        if (IsBatch(program))
            return new ProcessStartInfo
            {
                FileName = Cmd,
                Arguments = CmdArguments(program, clean, keepOpen),
                WorkingDirectory = workingFolder,
                UseShellExecute = true,
            };
        return new ProcessStartInfo
        {
            FileName = program,
            Arguments = CommandLine(clean),
            WorkingDirectory = workingFolder,
            UseShellExecute = true,
        };
    }

    /// <summary>
    /// Every C0 control but tab, and DEL, replaced with a space before any
    /// quoting. A NUL (U+0000) is the dangerous one: CreateProcess and
    /// ShellExecute both END the command line at it, which through the shim's
    /// <c>/s /k "…"</c> wrapper drops the wrapper's closing quote, so
    /// <c>/s</c> strips the message's OPENING quote instead and the tail runs
    /// unquoted and uncareted (a second command). Through an <c>.exe</c> a NUL
    /// only truncates, which is still wrong. A newline is cleaned here too, so
    /// the old line-only handling is gone. **Left as they are:** C1 controls
    /// (U+0080–U+009F), the line/paragraph separators U+2028/2029 and the
    /// bidi overrides — none of them ends or splits a Windows command line
    /// (measured 2026-11-12), and they are characters a name might carry; what
    /// a control character does on a page, in the title or on the trail is a
    /// separate matter (issue-control-characters-in-course-name, drafted).
    /// </summary>
    public static string Clean(string value)
    {
        var text = new StringBuilder(value.Length);
        foreach (char c in value) text.Append((c < 0x20 && c != '\t') || c == 0x7F ? ' ' : c);
        return text.ToString();
    }

    /// <summary>
    /// What a shim's own expansion may add beyond its folder's length: inside
    /// an npm shim <c>%*</c> is expanded again into a longer line carrying the
    /// shim's own text (its script's path, <c>%dp0%</c>, <c>title %COMSPEC%</c>),
    /// and cmd's 8,191 applies to THAT line. Measured 2026-11-12 with stub shims
    /// whose script path is short (<c>cli.js</c>): the longest outer line that
    /// arrived whole was 8,087 (modern shape) and 8,160 (old) from a 61-character
    /// shim folder, 7,908 and 7,981 from a 240-character one — a loss of one
    /// folder length plus 43 (modern) or minus 30 (old). npm's real script path
    /// (<c>node_modules\@anthropic-ai\claude-code\cli.js</c>,
    /// <c>node_modules\@openai\codex\bin\codex.js</c>) is up to about 40
    /// characters longer, so 128 covers the worst measured shape with that room
    /// and more.
    /// </summary>
    public const int ShimExpansionAllowance = 128;

    /// <summary>
    /// The longest outer line (<see cref="LineLength"/>) this program can be
    /// handed: cmd's 8,191 for an <c>.exe</c>, and for a shim 8,191 less its
    /// folder's length and <see cref="ShimExpansionAllowance"/>, because cmd
    /// fails on the line the shim expands to, not on the one Plantoir builds.
    /// </summary>
    public static int LimitFor(string program) =>
        IsBatch(program)
            ? FixWithAssistant.CommandLineMaxUtf16 - (Path.GetDirectoryName(program)?.Length ?? 0) - ShimExpansionAllowance
            : FixWithAssistant.CommandLineMaxUtf16;

    /// <summary>
    /// Whether this door's whole command line, as <see cref="StartInfo"/> would
    /// build it, is within <see cref="LimitFor"/>. Over it the shim path fails
    /// SILENTLY — cmd says the line is too long and leaves a prompt — so a door
    /// refuses rather than start into that, and Fix with…'s <c>fits</c> uses
    /// this SAME function, so rows are dropped to the real bound.
    /// </summary>
    public static bool WithinCommandLineLimit(string program, IReadOnlyList<string> arguments) =>
        LineLength(program, arguments) <= LimitFor(program);

    /// <summary>
    /// Starts it. False when nothing started, so the caller says
    /// <c>couldNotStart</c>. When the program started is NOT cmd (an
    /// <c>.exe</c> door), it also watches BRIEFLY: ShellExecute returns success
    /// and the window closes before a teacher could read an error, so a program
    /// gone within the grace with a non-zero code is reported as a door that did
    /// NOT open. A shim's start is cmd, under <c>/k</c>, which never exits by
    /// itself, so it is not watched at all (watching would only freeze the
    /// click). What the watch cannot see: a program that exits 0 at once, one
    /// that fails after the grace, and anything behind a shim. Rejected: a
    /// multi-second wait (it freezes every successful click) and an off-thread
    /// watch (Open is synchronous and its result is what shows the
    /// could-not-start sentence).
    /// </summary>
    public static bool Start(ProcessStartInfo info, TimeSpan? watchFor = null)
    {
        try
        {
            var process = Process.Start(info);
            if (process is null) return false;
            if (string.Equals(info.FileName, Cmd, StringComparison.OrdinalIgnoreCase)) { process.Dispose(); return true; }
            try
            {
                int grace = (int)(watchFor ?? TimeSpan.FromMilliseconds(400)).TotalMilliseconds;
                if (process.WaitForExit(grace) && process.ExitCode != 0) { process.Dispose(); return false; }
            }
            catch { /* cannot watch it (no handle through the shell): assume it started */ }
            process.Dispose();
            return true;
        }
        catch { return false; }
    }

    /// <summary>
    /// The whole command line <see cref="StartInfo"/> starts, in UTF-16 units:
    /// what <c>fixWith.charactersAre</c> keeps under cmd's 8,191 (the program
    /// and its arguments for an <c>.exe</c>; cmd and everything after it for a
    /// shim, carets and added quotes included).
    /// </summary>
    public static int LineLength(string program, IReadOnlyList<string> arguments)
    {
        var info = StartInfo(program, arguments, ".");
        return ScriptRunner.QuotedArgument(info.FileName).Length + 1 + info.Arguments.Length;
    }

    /// <summary>A program's arguments, each quoted by the standard Windows rule and nothing else.</summary>
    public static string CommandLine(IEnumerable<string> arguments) =>
        string.Join(" ", arguments.Select(ScriptRunner.QuotedArgument));

    /// <summary>One argument quoted so the C runtime (and Rust's, Node's and Bun's argv parsers) read it back exactly.</summary>
    public static string ArgvQuote(string argument) => ScriptRunner.QuotedArgument(argument);

    /// <summary>
    /// What follows <c>cmd.exe</c>: <c>/v:off /s /k "…"</c> (or <c>/c</c>, for a
    /// test). <c>/s</c> makes cmd strip exactly the outer pair of quotes and
    /// nothing else. A <c>.cmd</c>/<c>.bat</c> target is parsed by cmd a
    /// SECOND time (its <c>%*</c>), so its arguments are made safe for two
    /// parses; an <c>.exe</c> for one. <c>%</c> is handled on the OUTER parse
    /// only: cmd expands variables when it reads a line, and the text a
    /// batch file's <c>%*</c> becomes is not read for them again.
    /// </summary>
    public static string CmdArguments(string executable, IEnumerable<string> arguments, bool keepOpen)
    {
        string argv = string.Join(" ", arguments.Select(argument => ArgvQuote(OneLine(argument))));
        if (IsBatch(executable)) argv = ForCmd(argv);
        string line = ForCmd("\"" + executable + "\" " + argv, outermost: true);
        return (keepOpen ? "/v:off /s /k \"" : "/v:off /s /c \"") + line + "\"";
    }

    /// <summary>
    /// A command line made safe for ONE cmd parse: every cmd metacharacter that
    /// cmd would read as unquoted — following cmd's own quote toggling, which
    /// knows nothing of <c>\"</c> — gets a caret. Inside a region cmd sees as
    /// quoted a caret would be kept literally, so none is added there.
    /// <paramref name="outermost"/> also writes each run of <c>%</c> between
    /// two added quotes, <c>"%"</c>, unless a quote follows it already: cmd
    /// reads a variable's name from the character after a <c>%</c>, and no
    /// variable's name begins with a quote, so <c>%NAME%</c> is left as
    /// written. The pair toggles cmd's quoting twice and the program's parser
    /// twice, which reads <c>a"%"b</c> as <c>a%b</c> — so nothing else in the
    /// line changes, and backslashes just before the first added quote are
    /// doubled, which the program reads back as the backslashes they were.
    /// </summary>
    public static string ForCmd(string line, bool outermost = false)
    {
        var text = new StringBuilder();
        bool quoted = false;
        for (int i = 0; i < line.Length; i++)
        {
            char c = line[i];
            if (c == '"') { quoted = !quoted; text.Append(c); continue; }
            if (outermost && c == '%')
            {
                int end = i;
                while (end < line.Length && line[end] == '%') end++;
                string run = line[i..end];
                if (end < line.Length && line[end] == '"')
                {
                    text.Append(run);
                }
                else
                {
                    int backslashes = 0;
                    while (backslashes < text.Length && text[text.Length - 1 - backslashes] == '\\') backslashes++;
                    text.Append('\\', backslashes).Append('"').Append(run).Append('"');
                }
                i = end - 1;
                continue;
            }
            if (!quoted && "^&|<>()".IndexOf(c) >= 0) text.Append('^');
            text.Append(c);
        }
        return text.ToString();
    }

    /// <summary>A line break, which a cmd command line cannot carry, as a space.</summary>
    private static string OneLine(string argument) =>
        argument.IndexOfAny(new[] { '\r', '\n' }) < 0 ? argument : argument.Replace("\r\n", " ").Replace('\r', ' ').Replace('\n', ' ');
}

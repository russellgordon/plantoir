using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Assist;

/// <summary>
/// "Revise with Codex…" (#210, mac #205): the second outside door. Finds
/// <c>codex</c>, and starts it in a terminal in the working folder with
/// Plantoir's server described ON THE COMMAND LINE — five dotted <c>-c</c>
/// overrides and the greeting — so nothing at all is written for the
/// connection (<c>contracts/app-rules.json</c> → <c>outsideAgents.agents[codex]</c>).
/// The fifth (#468) names the course to the server's ENVIRONMENT
/// (<see cref="AssistWorkspace.DoorCourseVariable"/>), so a Codex session
/// HOLDS its course, never locks it, exactly as a Claude one does.
/// </summary>
/// <remarks>
/// <para><b>The trap is the escaping, and it fails SILENTLY.</b> Each value is
/// a TOML basic string inside an argument; Codex does not reject a malformed
/// value, it treats it as a raw string, so <c>args</c> stops being a list and
/// the door greets the teacher and then cannot start its server. On Windows
/// the argument then passes through <c>cmd</c> — TWICE when <c>codex</c> is
/// npm's <c>codex.cmd</c> shim, whose <c>%*</c> is parsed again inside the
/// batch file. So the layers are: TOML (<see cref="TomlBasicString"/>), the
/// C runtime's argv quoting (<see cref="ArgvQuote"/>), and cmd's own
/// metacharacters once per cmd parse (<see cref="ForCmd"/>). Each is its own
/// function, and <c>CodexLauncherTests</c> sends the result through a real
/// <c>cmd.exe</c> and a stub <c>codex.cmd</c>.</para>
///
/// <para><b>Rejected: going through <c>wt.exe</c></b>, as the Claude door
/// does. Windows Terminal parses its own command line — <c>;</c> splits it
/// into tabs and it re-joins arguments with its own quoting — which is a THIRD
/// layer no test here can run without opening a window. This door starts
/// <c>cmd.exe</c> directly; on Windows 11, where Windows Terminal is the
/// default terminal, the window it opens in is Windows Terminal anyway.</para>
///
/// <para><b>Not isolated, and that is structural</b>
/// (<c>isolatesTheTeachersOwnServers: false</c>): Codex has no
/// <c>--strict-mcp-config</c>, and the <c>-c</c> layer merges with the
/// teacher's own configuration, so their own MCP servers load beside
/// Plantoir's.</para>
/// </remarks>
public static class CodexLauncher
{
    /// <summary>Both halves: the assistant, and the server it drives.</summary>
    public static bool IsAvailable => FindCodex() is not null && ClaudeCodeLauncher.FindServer() is not null;

    /// <summary>
    /// Where Codex is, or null: PATH first, then where its installers put it
    /// (<c>outsideAgents.searchedForInOrder</c>, the Windows half of it).
    /// </summary>
    public static string? FindCodex()
    {
        foreach (string name in new[] { "codex.exe", "codex.cmd", "codex.bat" })
            if (OnPath(name) is { } found) return found;

        string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        foreach (string candidate in new[]
                 {
                     Path.Combine(home, ".local", "bin", "codex.exe"),
                     Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "npm", "codex.cmd"),
                     Path.Combine(home, ".bun", "bin", "codex.exe"),
                 })
            if (File.Exists(candidate)) return candidate;
        return null;
    }

    /// <summary>
    /// Open a session for one course. False when it could not be started, so
    /// the caller can say <c>couldNotStart</c> rather than show nothing.
    /// </summary>
    public static bool Open(string workspacePath, string courseCode, string courseName)
    {
        string? codex = FindCodex();
        string? server = ClaudeCodeLauncher.FindServer();
        if (codex is null || server is null) return false;

        var info = new ProcessStartInfo
        {
            FileName = "cmd.exe",
            Arguments = CmdArguments(codex, Arguments(server, workspacePath, courseCode,
                                                      ClaudeCodeLauncher.Greeting(courseCode, courseName)), keepOpen: true),
            WorkingDirectory = workspacePath,
            UseShellExecute = true,
        };
        try
        {
            if (Process.Start(info) is null) return false;
        }
        catch { return false; }

        // outsideAgents.agents[codex].trailLine. A course-wide door carries
        // no section.
        ActivityTrail.Note(ActivityTrail.Event.AssistantOpened, $"started Codex for {courseCode}");
        return true;
    }

    /// <summary>
    /// The argv the contract states, in order: five dotted overrides and the
    /// greeting as the first message. No sandbox, approval or cd flag — Codex
    /// asks the teacher itself before a change, and a flag would quietly widen
    /// what they set for themselves.
    /// </summary>
    /// <remarks>
    /// The fifth override, <c>mcp_servers.plantoir.env.PLANTOIR_DOOR_COURSE</c>,
    /// is #468 (Russell's decision on mac #458, 2026-10-07: BOTH doors hold
    /// their course). Until it, a Codex session held nothing — its backup could
    /// be deleted under it, a second session could start on the course, and
    /// Rename Course could move the folder out from under it — while looking to
    /// the teacher exactly like a Claude one. The value goes through the same
    /// three layers as every other element. Codex 0.155.1 reads this form into
    /// the server's <c>env</c> (measured on the mac with <c>codex mcp get
    /// --json</c>); Codex is not installed on the Windows test PC, so here only
    /// the argv round trip through cmd and a stub shim is tested.
    /// </remarks>
    public static IReadOnlyList<string> Arguments(string server, string folder, string courseCode, string greeting) => new[]
    {
        "-c", "mcp_servers.plantoir.command=" + TomlBasicString(server),
        "-c", "mcp_servers.plantoir.args=[" + TomlBasicString("--mcp-stdio") + "," + TomlBasicString(folder) + "]",
        "-c", "mcp_servers.plantoir.startup_timeout_sec=60",
        "-c", "mcp_servers.plantoir.tool_timeout_sec=1800",
        "-c", "mcp_servers.plantoir.env." + AssistWorkspace.DoorCourseVariable + "=" + TomlBasicString(courseCode),
        greeting.Replace("\"", "'"),
    };

    /// <summary>
    /// A TOML basic string: backslash, double quote and control characters
    /// escaped; everything else — an apostrophe, a space, Français 🎓 — as it is.
    /// </summary>
    public static string TomlBasicString(string value)
    {
        var text = new StringBuilder("\"");
        foreach (char c in value)
        {
            switch (c)
            {
                case '\\': text.Append("\\\\"); break;
                case '"': text.Append("\\\""); break;
                case '\b': text.Append("\\b"); break;
                case '\t': text.Append("\\t"); break;
                case '\n': text.Append("\\n"); break;
                case '\f': text.Append("\\f"); break;
                case '\r': text.Append("\\r"); break;
                default:
                    if (c < 0x20 || c == 0x7F) text.Append($"\\u{(int)c:X4}");
                    else text.Append(c);
                    break;
            }
        }
        return text.Append('"').ToString();
    }

    /// <summary>
    /// One argument quoted so the C runtime (and Rust's and Node's argv
    /// parsers) read it back exactly: backslashes doubled only where they
    /// precede a quote.
    /// </summary>
    public static string ArgvQuote(string argument)
    {
        if (argument.Length > 0 && argument.IndexOfAny(new[] { ' ', '\t', '\n', '\v', '"' }) < 0) return argument;
        var text = new StringBuilder("\"");
        for (int i = 0; i < argument.Length; i++)
        {
            int backslashes = 0;
            while (i < argument.Length && argument[i] == '\\') { backslashes++; i++; }
            if (i == argument.Length) { text.Append('\\', backslashes * 2); break; }
            if (argument[i] == '"') text.Append('\\', backslashes * 2 + 1).Append('"');
            else text.Append('\\', backslashes).Append(argument[i]);
        }
        return text.Append('"').ToString();
    }

    /// <summary>
    /// A command line made safe for ONE cmd parse: every cmd metacharacter that
    /// cmd would read as unquoted — following cmd's own quote toggling, which
    /// knows nothing of <c>\"</c> — gets a caret. Inside a region cmd sees as
    /// quoted a caret would be kept literally, so none is added there.
    /// </summary>
    public static string ForCmd(string line)
    {
        var text = new StringBuilder();
        bool quoted = false;
        foreach (char c in line)
        {
            if (c == '"') { quoted = !quoted; text.Append(c); continue; }
            if (!quoted && "^&|<>()".IndexOf(c) >= 0) text.Append('^');
            text.Append(c);
        }
        return text.ToString();
    }

    /// <summary>
    /// What follows <c>cmd.exe</c>: <c>/s /k "…"</c> (or <c>/c</c>, for a
    /// test). <c>/s</c> makes cmd strip exactly the outer pair of quotes and
    /// nothing else. A <c>.cmd</c>/<c>.bat</c> target is parsed by cmd a
    /// SECOND time (its <c>%*</c>), so its arguments are made safe for two
    /// parses; an <c>.exe</c> for one.
    /// </summary>
    public static string CmdArguments(string executable, IEnumerable<string> arguments, bool keepOpen)
    {
        string argv = string.Join(" ", arguments.Select(ArgvQuote));
        bool batch = executable.EndsWith(".cmd", StringComparison.OrdinalIgnoreCase) ||
                     executable.EndsWith(".bat", StringComparison.OrdinalIgnoreCase);
        if (batch) argv = ForCmd(argv);
        string line = ForCmd("\"" + executable + "\" " + argv);
        return (keepOpen ? "/s /k \"" : "/s /c \"") + line + "\"";
    }

    private static string? OnPath(string name)
    {
        foreach (string directory in (Environment.GetEnvironmentVariable("PATH") ?? "")
                     .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            try
            {
                string candidate = Path.Combine(directory.Trim(), name);
                if (File.Exists(candidate)) return candidate;
            }
            catch { }
        }
        return null;
    }
}

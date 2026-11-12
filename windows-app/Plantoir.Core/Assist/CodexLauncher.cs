using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Assist;

/// <summary>
/// Revise With ▸ Codex… (named "Revise with Codex…" until #491 item 8; #210, mac #205): the second outside door. Finds
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
/// the door greets the teacher and then cannot start its server. So the
/// layers are: TOML (<see cref="TomlBasicString"/>), the C runtime's argv
/// quoting (<see cref="OutsideDoor.ArgvQuote"/>), and — only when
/// <c>codex</c> is npm's <c>codex.cmd</c> shim, which needs cmd — cmd's own
/// metacharacters once per cmd parse, twice for the shim's <c>%*</c>
/// (<see cref="OutsideDoor.ForCmd"/>). A <c>codex.exe</c> is started
/// directly, with no cmd at all (since 1.9.3, #736; until then every Codex
/// session went through <c>cmd.exe /s /k</c>, and a <c>%NAME%</c> in a
/// course's name was expanded). <c>CodexLauncherTests</c> and
/// <c>OutsideDoorTests</c> send the result through the real start and a stub
/// program that writes down what it was given.</para>
///
/// <para><b>Rejected: going through <c>wt.exe</c></b>. Windows Terminal
/// parses its own command line — <c>;</c> splits it into tabs, it re-joins
/// arguments with its own quoting, and it expands <c>%NAME%</c> (measured,
/// <see cref="OutsideDoor"/>) — a layer with no escape for the last. Since
/// 1.9.3 the Claude door does not go through it either. On Windows 11, where
/// Windows Terminal is the default terminal, the window opens in it
/// anyway.</para>
///
/// <para><b>Not isolated, and that is structural</b>
/// (<c>isolatesTheTeachersOwnServers: false</c>): Codex has no
/// <c>--strict-mcp-config</c>, and the <c>-c</c> layer merges with the
/// teacher's own configuration, so their own MCP servers load beside
/// Plantoir's.</para>
/// </remarks>
public static class CodexLauncher
{
    /// <summary>The item's title inside Revise With ▸ (<c>outsideAgents.agents[codex].menuItem</c>; #491 item 8).</summary>
    public const string MenuItemTitle = "Codex…";

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
    /// <paramref name="greeting"/> is Fix with Codex…'s message (#736); null
    /// is Revise With ▸'s plain greeting.
    /// </summary>
    public static bool Open(string workspacePath, string courseCode, string courseName, string? greeting = null)
    {
        string? codex = FindCodex();
        string? server = ClaudeCodeLauncher.FindServer();
        if (codex is null || server is null) return false;

        var arguments = Arguments(server, workspacePath, courseCode,
                                  greeting ?? ClaudeCodeLauncher.Greeting(courseCode, courseName));
        if (!OutsideDoor.Start(OutsideDoor.StartInfo(codex, arguments, workspacePath))) return false;

        // outsideAgents.agents[codex].trailLine. A course-wide door carries
        // no section.
        ActivityTrail.Note(ActivityTrail.Event.AssistantOpened, $"started Codex for {courseCode}");
        return true;
    }

    /// <summary>
    /// Whether a message would keep this door's whole command line under
    /// cmd's 8,191 UTF-16 units (<c>fixWith.charactersAre</c>); null when the
    /// door is not here.
    /// </summary>
    public static Func<string, bool>? Fits(string workspacePath, string courseCode)
    {
        if (FindCodex() is not { } codex || ClaudeCodeLauncher.FindServer() is not { } server) return null;
        return message => OutsideDoor.LineLength(codex, Arguments(server, workspacePath, courseCode, message))
                          <= FixWithAssistant.CommandLineMaxUtf16;
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

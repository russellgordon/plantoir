using System.Reflection;
using System.Text.Json;
using ModelContextProtocol.Server;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;

namespace Plantoir.Mcp;

/// <summary>
/// Nothing writes to a course kept for reference, whichever client is calling
/// (#241; <c>shared-rules.json → referenceCourses.refusal</c>, doors 5 and 7).
/// Asked FIRST, before a tool is dispatched at all — a refusal that arrives
/// after the work has started is not a refusal — by a call-tool filter on the
/// server (Program.cs), so it covers the local assistant's window and every
/// outside session alike, and all 42 tools this server serves, not the 22 the
/// mac's runner holds.
///
/// <para><b>Gated on each tool's OWN ReadOnly flag</b>, read off its
/// <c>[McpServerTool]</c> attribute, never a hand-kept list of names: adding a
/// write tool gates it by default. The exemptions are the contract's
/// (<c>refusal.toolsStillAllowed</c>): previewing and backing up only READ the
/// course, and cancelling a scheduled deploy is gate by DIRECTION — the act
/// that STOPS a deploy is never refused. <c>undo_last_change</c> names no
/// course, so it is gated by the course its pending change touched.</para>
/// </summary>
public static class ReferenceWriteGate
{
    /// <summary><c>refusal.toolsStillAllowed</c>, by name; a test holds this equal to the contract's list.</summary>
    public static readonly IReadOnlySet<string> StillAllowed =
        new HashSet<string>(StringComparer.Ordinal) { "rebuild_preview", "back_up_course", "cancel_scheduled_deploy" };

    /// <summary>The tools whose refusal says "never deployed" rather than "stays as it is".</summary>
    public static readonly IReadOnlySet<string> ToolsThatDeploy =
        new HashSet<string>(StringComparer.Ordinal) { "deploy_section", "schedule_deploy" };
    // plan_scheduled_deploy is ReadOnly, so it is never gated here: its refusal
    // is ScheduledDeploy.Problem's, asked inside the tool (door 10).

    /// <summary>Every tool this server serves, with its own ReadOnly flag.</summary>
    public static IReadOnlyDictionary<string, bool> ServedTools(Type? toolType = null) =>
        (toolType ?? typeof(PlantoirTools)).GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static)
            .Select(method => method.GetCustomAttribute<McpServerToolAttribute>())
            .OfType<McpServerToolAttribute>()
            .Where(attribute => attribute.Name is not null)
            .ToDictionary(attribute => attribute.Name!, attribute => attribute.ReadOnly, StringComparer.Ordinal);

    /// <summary>The tools the gate refuses on a reference course: every non-read-only tool but the exemptions.</summary>
    public static IReadOnlySet<string> Gated(Type? toolType = null) =>
        ServedTools(toolType).Where(tool => !tool.Value && !StillAllowed.Contains(tool.Key))
            .Select(tool => tool.Key).ToHashSet(StringComparer.Ordinal);

    /// <summary>
    /// The sentence refusing <paramref name="tool"/> on a reference course, or
    /// null to let it run. Two sentences, chosen by what was ASKED FOR: a
    /// deploy is told it is never deployed; anything else that it stays as it is.
    /// </summary>
    public static string? Refusal(string tool, IReadOnlyDictionary<string, JsonElement>? arguments, AssistWorkspace workspace,
        Type? toolType = null)
    {
        if (!Gated(toolType).Contains(tool)) return null;
        string? code = tool == "undo_last_change"
            ? PendingChangesCourse(workspace)
            : arguments is not null && arguments.TryGetValue("course", out var value) && value.ValueKind == JsonValueKind.String
                ? value.GetString()
                : null;
        if (string.IsNullOrWhiteSpace(code)) return null;

        // Read the named course's settings directly, and FAIL SAFE: a settings
        // file that is there and cannot be read is refused with the launchers'
        // own "cannot tell" sentence (review L5, ruling 4) — the shell's
        // stance — rather than let a write through to a course that might be
        // frozen. A course with no settings file is no course: the tool's own
        // lookup answers that.
        string wanted = code.Trim();
        string folder = Path.Combine(Workspace.CoursesDirectory(workspace.FolderPath), wanted);
        string settings = Path.Combine(folder, "course_config.json");
        if (wanted.StartsWith('.') || wanted.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0 || !File.Exists(settings)) return null;
        Course course;
        try { course = new Course(Path.GetFileName(folder), folder, CourseConfiguration.Load(settings)); }
        catch
        {
            return ReferenceCourse.Wording["cannotTellHeadline"].Replace("{course}", wanted)
                   + " — " + ReferenceCourse.Wording["cannotTellBecauseUnreadable"] + ".";
        }
        if (!ReferenceCourse.IsKeptForReference(course)) return null;
        string shown = ReferenceCourse.ShownCode(course);
        return ToolsThatDeploy.Contains(tool)
            ? AssistWording.DeployRefusedForAReferenceCourse(shown)
            : ReferenceCourse.StaysAsItIs(shown);
    }

    /// <summary>The course folder the newest recorded change touched, read from its own file paths.</summary>
    internal static string? PendingChangesCourse(AssistWorkspace workspace)
    {
        if (workspace.History?.Entries is not { Count: > 0 } entries) return null;
        string courses = Path.GetFullPath(Workspace.CoursesDirectory(workspace.FolderPath));
        foreach (string file in entries[^1].Files.Keys)
        {
            string relative = Path.GetRelativePath(courses, Path.GetFullPath(file));
            if (relative.StartsWith("..", StringComparison.Ordinal) || Path.IsPathRooted(relative)) continue;
            return relative.Split(Path.DirectorySeparatorChar)[0];
        }
        return null;
    }
}

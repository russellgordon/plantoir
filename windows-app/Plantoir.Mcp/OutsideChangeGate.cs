using System.Text.Json;
using Plantoir.Core.Assist;
using Plantoir.Core.Scripting;

namespace Plantoir.Mcp;

/// <summary>
/// What an OUTSIDE assistant's change meets at the server's door (#436, the
/// mac's #433; <c>shared-rules.json → workLeases.declining.outsideChanges</c>).
/// </summary>
/// <remarks>
/// <para><b>Held back ONLY while a site of the course is being BUILT</b> — another
/// program holds a build or publish lease (a preview still building holds build
/// beside preview; a deploy holds both). A preview that is only being SERVED
/// holds nothing back: the change is written and the open preview left as it
/// is (<see cref="AssistWorkspace"/> says so where the preview would have been
/// refreshed). Assist and import leases hold nothing.</para>
///
/// <para><b>Asked at the door, before any backup</b> — a call-tool filter in
/// Program.cs, beside <see cref="ReferenceWriteGate"/> — so a held-back change
/// has written nothing, not even a copy. Until #436 Windows refused writes
/// inside the workspace, and only <c>if (plan.Publishes)</c>: an unpublish,
/// a re-date or a new class went ahead mid-build.</para>
///
/// <para><b>Which tools.</b> Every tool that is not read-only, read off its own
/// <c>[McpServerTool]</c> flag (a new write tool is gated by default), except
/// the six the contract names: <c>rebuild_preview</c> and <c>deploy_section</c>
/// decide for themselves (a served preview builds nothing / goes ahead), the
/// deploy-later pair, <c>back_up_course</c> and <c>remember_timetable</c>
/// touch no page.</para>
///
/// <para><b>Plantoir's own window is not covered</b> (director's ruling): it
/// keeps #289's rule, as the mac's in-app assistant keeps #156's. It is told
/// apart by <c>PLANTOIR_LOCAL_WINDOW=1</c>, never by <c>--course</c>, which it
/// still passes and the outside doors no longer do (#430).</para>
/// </remarks>
public static class OutsideChangeGate
{
    /// <summary>The writing tools that are NOT held back here (<c>outsideChanges.rule</c>).</summary>
    public static readonly IReadOnlySet<string> NotAChange = new HashSet<string>(StringComparer.Ordinal)
    {
        "rebuild_preview", "deploy_section", "schedule_deploy", "cancel_scheduled_deploy",
        "back_up_course", "remember_timetable",
    };

    /// <summary>The tools this gate holds back while the course is being built.</summary>
    public static IReadOnlySet<string> Gated(Type? toolType = null) =>
        ReferenceWriteGate.ServedTools(toolType).Where(tool => !tool.Value && !NotAChange.Contains(tool.Key))
            .Select(tool => tool.Key).ToHashSet(StringComparer.Ordinal);

    /// <summary>
    /// The sentence holding <paramref name="tool"/> back, or null to let it run.
    /// </summary>
    public static string? Refusal(string tool, IReadOnlyDictionary<string, JsonElement>? arguments, AssistWorkspace workspace,
        Type? toolType = null)
    {
        if (!workspace.IsOutside || !Gated(toolType).Contains(tool)) return null;
        string? code = tool == "undo_last_change"
            ? ReferenceWriteGate.PendingChangesCourse(workspace)
            : arguments is not null && arguments.TryGetValue("course", out var value) && value.ValueKind == JsonValueKind.String
                ? value.GetString()
                : null;
        if (string.IsNullOrWhiteSpace(code)) return null;
        string course = code.Trim();

        if (WorkLease.WhatAnOutsideChangeMeets(workspace.FolderPath, course) != WorkLease.OutsideMeeting.ABuild) return null;

        int section = arguments is not null && arguments.TryGetValue("section", out var given) &&
                      given.ValueKind == JsonValueKind.Number && given.TryGetInt32(out int number) ? number : 0;
        string line = $"an outside assistant's {tool} held back, before anything was backed up or written — " +
                      $"another program on this computer is building {course}";
        if (section > 0) ActivityTrail.Note(ActivityTrail.Event.BuildDeclinedCourseBusyElsewhere, line, course, section);
        else ActivityTrail.Note(ActivityTrail.Event.BuildDeclinedCourseBusyElsewhere, line);
        return AssistWording.CourseIsBeingBuilt(course.ToUpperInvariant());
    }
}

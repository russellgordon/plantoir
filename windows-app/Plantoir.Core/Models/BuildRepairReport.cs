using Plantoir.Core.Scripting;

namespace Plantoir.Core.Models;

/// <summary>
/// Something the build put right in the teacher's own files without being
/// asked, because Plantoir itself wrote it wrong (#584, mac #645).
///
/// <para>The shared build prints one <c>PLANTOIR_REPAIRED: {json}</c> line per
/// repair it WROTE into a teacher's page (<c>shared-rules.json</c> →
/// <c>buildRepairs.marker</c>), and this reads it so the repair goes on the
/// trail as <c>folder problem repaired</c> — the same event a repair the
/// teacher asked for leaves, since both record that something wrong was put
/// right. Read from the same three places as <see cref="PagesDatedByTheBuild"/>:
/// the console of a run the app started (<c>ScriptRunner</c>), a scheduled
/// publish's own record (<c>ScheduledHealthFindings</c>), and a run
/// <c>plantoir-mcp</c> started (<c>LauncherRunner</c>) - all three through
/// <see cref="Scripting.BuildMachineLines"/> since #660.</para>
///
/// <para>Not printed when the build could quote only its own copy (a course
/// kept for reference, a linked page, a locked one), so such a course leaves
/// no line on every build. A repair key this app does not know — a newer
/// build's — is parsed but writes nothing, rather than a wrong line. The mac's
/// reader is <c>BuildRepairReport.swift</c>.</para>
/// </summary>
public sealed record BuildRepairReport(string Course, int Section, string Repair, string Page)
{
    /// <summary><c>buildRepairs.marker.prefix</c>.</summary>
    public const string Marker = "PLANTOIR_REPAIRED:";

    /// <summary>The key of the front page's title repair in <c>buildRepairs</c>.</summary>
    public const string FrontPageTitleQuoted = "frontPageTitleQuoted";

    /// <summary>
    /// <c>buildRepairs.frontPageTitleQuoted.trailLine</c> with <c>{page}</c>
    /// filled, or null for a repair this app does not know.
    /// </summary>
    public string? TrailSentence => Repair switch
    {
        FrontPageTitleQuoted => $"the build put quotes around the title of the front page ({Page}) so it could be read",
        _ => null,
    };

    public static bool IsMarkerLine(string line) => line.Contains(Marker, StringComparison.Ordinal);

    /// <summary>
    /// The report on this line, read from the prefix onward so a marker glued
    /// to the tail of somebody else's half line is still read; null when the
    /// line carries none, or one missing a field or with an empty page.
    /// </summary>
    public static BuildRepairReport? Parse(string? line)
    {
        if (string.IsNullOrWhiteSpace(line)) return null;
        int at = line.IndexOf(Marker, StringComparison.Ordinal);
        if (at < 0) return null;
        try
        {
            if (System.Text.Json.Nodes.JsonNode.Parse(line[(at + Marker.Length)..].Trim())
                is not System.Text.Json.Nodes.JsonObject obj) return null;
            string course = obj["course"]?.GetValue<string>() ?? "";
            int section = obj["section"]?.GetValue<int>() ?? 0;
            string repair = obj["repair"]?.GetValue<string>() ?? "";
            string page = obj["page"]?.GetValue<string>() ?? "";
            if (course.Length == 0 || section <= 0 || repair.Length == 0 || page.Length == 0) return null;
            return new BuildRepairReport(course, section, repair, page);
        }
        catch (Exception error) when (error is System.Text.Json.JsonException or InvalidOperationException or FormatException)
        {
            return null;
        }
    }

    public static IReadOnlyList<BuildRepairReport> ReportsIn(IEnumerable<string> lines) =>
        lines.Select(Parse).Where(report => report is not null).Select(report => report!).ToList();

    /// <summary>
    /// Writes this repair on the trail as <c>folder problem repaired</c>, when
    /// this app knows how to word it; a repair it does not know writes nothing.
    /// </summary>
    public void Record(DateTime? moment = null)
    {
        if (TrailSentence is not { } sentence) return;
        ActivityTrail.Note(ActivityTrail.Event.FolderProblemRepaired, sentence, Course, Section, moment);
    }
}

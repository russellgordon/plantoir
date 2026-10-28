using Plantoir.Core.Assist;
using Plantoir.Core.Models;

namespace Plantoir.Core.Scripting;

/// <summary>
/// The ONE place a build's machine lines are read and written on the trail
/// (#660). Three readers see a build's output - the app's console
/// (<see cref="ScriptRunner"/>), a run <c>plantoir-mcp</c> starts
/// (<c>Plantoir.Mcp/LauncherRunner</c>), and a scheduled publish's record
/// (<see cref="ScheduledHealthFindings"/>) - and until #660 each had its own
/// hand-written list. The MCP door's list had fallen behind by five markers
/// (<c>PLANTOIR_MAPS:</c>, <c>PLANTOIR_MY_PROGRESS:</c>, <c>PLANTOIR_SWIFT:</c>,
/// <c>PLANTOIR_DATED:</c>, <c>PLANTOIR_KEPT_OFF:</c>), so a build the
/// assistant started through Claude Code or Codex left none of those lines on
/// the trail. With one dispatch, a sixth marker cannot be added to one reader
/// and not the others. (The mac never had the split: its MCP door runs
/// through its own ScriptRunner.)
/// <para>What stays with the caller: keeping the links checklist and the
/// findings, under whatever lock the caller holds. Deduplicating a finding
/// and noting it is <see cref="AddFinding"/>, so its trail text cannot drift
/// either.</para>
/// </summary>
public static class BuildMachineLines
{
    /// <summary>What one line turned out to be.</summary>
    /// <param name="Checklist">The links checklist's marker (#392), for the caller to keep.</param>
    /// <param name="Finding">A folder problem (<c>PLANTOIR_HEALTH:</c>), for the caller to
    /// keep and note through <see cref="AddFinding"/>.</param>
    /// <param name="WasMachineLine">Whether the line is machinery
    /// (<c>transcriptStripping.machineLines</c>), read or not: such a line
    /// never reaches a teacher's console or the assistant's progress text.</param>
    public sealed record Read(LinksChecklistMarker? Checklist, SiteHealthFinding? Finding, bool WasMachineLine);

    /// <summary>The markers this helper writes on the trail itself, in the order it tries them.</summary>
    public static readonly IReadOnlyList<string> TrailMarkers = new[]
    {
        CoverageMapsBuilt.Marker, MyProgressBuilt.Marker, SwiftGotReady.Marker,
        PagesDatedByTheBuild.Marker, HowITeachKeptOffReport.Marker,
        BuildRepairReport.Marker, CloudflareProjectRemade.Marker,
    };

    /// <summary>
    /// What a scheduled publish's wrapper keeps from its build's log, for
    /// <see cref="ScheduledHealthFindings"/> to read in the morning:
    /// <c>PLANTOIR_HEALTH:</c> first (the wrapper tests anchor on it), then
    /// every trail marker except <c>PLANTOIR_CLOUDFLARE_REMADE:</c>, which the
    /// wrapper's Cloudflare leg appends itself. The links checklist has no
    /// meaning overnight, so it is not kept.
    /// </summary>
    public static IReadOnlyList<string> ScheduledRecordMarkers =>
        new[] { SiteHealthFinding.Marker }
            .Concat(TrailMarkers.Where(marker => marker != CloudflareProjectRemade.Marker))
            .ToList();

    /// <summary>
    /// Reads one line: writes its trail line when it is one of
    /// <see cref="TrailMarkers"/>, dated <paramref name="moment"/> when given
    /// (a scheduled record's time), and hands back what the caller keeps.
    /// </summary>
    public static Read Record(string? line, DateTime? moment = null)
    {
        if (string.IsNullOrWhiteSpace(line)) return new Read(null, null, false);

        if (LinksChecklistMarker.Parse(line) is { } checklist)
            return new Read(checklist, null, true);

        // PLANTOIR_MAPS: (#345): which coverage maps the build wrote.
        if (CoverageMapsBuilt.Parse(line) is { } maps)
        {
            ActivityTrail.Note(ActivityTrail.Event.CurriculumMapsBuilt, maps.TrailSentence, maps.Course, maps.Section, moment);
            return new Read(null, null, true);
        }

        // PLANTOIR_MY_PROGRESS: (#599): whether it made the section's My
        // Progress page, and why not when it did not.
        if (MyProgressBuilt.Parse(line) is { } progress)
        {
            ActivityTrail.Note(ActivityTrail.Event.MyProgressPageBuilt, progress.TrailSentence, progress.Course, progress.Section, moment);
            return new Read(null, null, true);
        }

        // PLANTOIR_SWIFT: (#570): Swift got ready on this PC, or why not.
        if (SwiftGotReady.Parse(line) is { } swift)
        {
            swift.Record(moment);
            return new Read(null, null, true);
        }

        // PLANTOIR_DATED: (#279): the teacher's pages the build rewrote with
        // their class's date; the trail is the only place that survives.
        if (PagesDatedByTheBuild.Parse(line) is { } dated)
        {
            ActivityTrail.Note(ActivityTrail.Event.PagesDatedByTheBuild, dated.TrailSentence, dated.Course, dated.Section, moment);
            return new Read(null, null, true);
        }

        // PLANTOIR_KEPT_OFF: (#340): a How I Teach page the course's settings
        // had listed is now kept off the site.
        if (HowITeachKeptOffReport.Parse(line) is { } keptOff)
        {
            ActivityTrail.Note(ActivityTrail.Event.HowITeachPageKeptOff, keptOff.TrailSentence, keptOff.Course, keptOff.Section, moment);
            return new Read(null, null, true);
        }

        // PLANTOIR_REPAIRED: (#584, mac #645): something the build put right
        // in the teacher's own page without being asked.
        if (BuildRepairReport.Parse(line) is { } repaired)
        {
            repaired.Record(moment);
            return new Read(null, null, true);
        }

        // deploy.py's PLANTOIR_CLOUDFLARE_REMADE: (#395): a section's
        // Cloudflare project was gone and was made again.
        if (CloudflareProjectRemade.Parse(line) is { } remade)
        {
            ActivityTrail.Note(ActivityTrail.Event.CloudflareProjectMadeAgain, remade.TrailSentence, remade.Course, remade.Section, moment);
            return new Read(null, null, true);
        }

        if (SiteHealthFinding.Parse(line) is { } finding)
            return new Read(null, finding, true);

        return new Read(null, null, TranscriptBuilder.IsMachineLine(line));
    }

    /// <summary>
    /// Keeps a folder problem once per run - the same section rebuilt in one
    /// task reports the same problem twice, and that is one problem - keyed
    /// by the record's own <see cref="SiteHealthFinding.Identity"/>, and notes
    /// it on the trail. Whether it was new.
    /// </summary>
    public static bool AddFinding(SiteHealthFinding finding, ISet<string> seen, DateTime? moment = null)
    {
        if (!seen.Add(finding.Identity)) return false;
        ActivityTrail.Note(ActivityTrail.Event.FolderProblemFound, finding.TrailSentence, finding.Course, finding.Section, moment);
        return true;
    }

    /// <summary>
    /// Whether text that has not met a newline yet may still hold a machine
    /// line: <c>transcriptStripping.machineLines</c>' one rule, so a marker
    /// added tomorrow is covered too rather than listed by hand.
    /// </summary>
    public static bool MayHoldOne(string text) => TranscriptBuilder.IsMachineLine(text);
}

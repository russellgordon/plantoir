using System;
using System.Collections.Generic;
using System.IO;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Assist;

/// <summary>
/// What last night's scheduled deploy found wrong with a course's folders.
///
/// <para><b>A scheduled deploy never refuses on a folder problem.</b> A
/// slightly inaccurate curriculum map is a paper cut; a site update a teacher
/// was counting on that silently did not happen is not. So the run publishes
/// anyway and leaves what it found here, for the next time there is somebody
/// to tell — <c>contracts/shared-rules.json</c> -&gt;
/// <c>siteHealth.scheduledDeployPublishesAnyway</c>.</para>
///
/// <para>The wrapper <see cref="TaskScheduling"/> generates writes the raw
/// <c>PLANTOIR_HEALTH:</c> lines here; this reads them back with the parser a
/// live build uses, so the two paths cannot disagree about what a finding is.
/// Nothing interprets JSON in PowerShell.</para>
///
/// <para><b>A DIFFERENT directory from the completion sentinels, and that is
/// not tidiness.</b> <see cref="ScheduledDeployCompletion.ConsumePendingFrom"/>
/// enumerates <c>scheduled\pending\*.json</c> and deletes every file it
/// touches, parsed or not — so a findings record filed beside a completion
/// record would be swept away before anything read it. Both are read when the
/// window becomes active, so which one won would have been a race.</para>
///
/// <para>Two properties shared with the mac's version, both load-bearing: the
/// record is CONSUMED when read, so a problem is reported once rather than
/// every time the app opens; and a clean run CLEARS it, so a problem the
/// teacher has since put right stops being reported.</para>
/// </summary>
public static class ScheduledHealthFindings
{
    /// <summary>
    /// <c>%LOCALAPPDATA%\Plantoir\scheduled\folder-problems</c> — beside the
    /// wrapper scripts rather than in a temp folder, for the same reason they
    /// are: nothing here should be swept away before the app looks at it.
    /// </summary>
    public static string Directory() =>
        Plantoir.Core.Models.AppDataRoot.Combine("scheduled", "folder-problems");

    /// <summary>
    /// One record per course and section, because that is how it is read: a
    /// section's own view asks for its own.
    ///
    /// <para>Named by <see cref="TaskScheduling.HealthRecordName"/>, which the
    /// generated wrapper also uses — one function, so the writer and the reader
    /// cannot drift into disagreeing about the filename. A mismatch there fails
    /// in the quietest way available: the record is written every night and
    /// read never.</para>
    /// </summary>
    public static string SentinelPath(string courseCode, int sectionNumber, string workingFolder) =>
        Path.Combine(Directory(), TaskScheduling.HealthRecordName(courseCode, sectionNumber, workingFolder));

    /// <summary>
    /// What the last scheduled run found for this section, consuming the record
    /// so it is reported once rather than every time the app opens.
    ///
    /// <para>Each finding leaves a <c>folder problem found</c> line on the
    /// activity trail as it is read, dated to when the RUN wrote the record
    /// rather than to this morning — a trail that dated an overnight problem to
    /// whenever somebody happened to open the app would file it under the wrong
    /// night. Nothing else records these at all: the run happened with the app
    /// closed. (The mac does not write this line; proposed back to it in
    /// <c>contracts/shared-rules.json</c> → <c>siteHealth</c>.)</para>
    /// </summary>
    public static IReadOnlyList<SiteHealthFinding> Take(string courseCode, int sectionNumber, string workingFolder)
    {
        // A record a task set before #309 wrote under the folder-less name is
        // filed under its folder's name first, as the outcome records are.
        ScheduledPublishOutcome.RefileOldNamedRecordsIn(Directory());
        return TakeFrom(Directory(), courseCode, sectionNumber, workingFolder);
    }

    /// <summary>The same, against an arbitrary directory — what the tests use.</summary>
    public static IReadOnlyList<SiteHealthFinding> TakeFrom(
        string directory, string courseCode, int sectionNumber, string? workingFolder = null)
    {
        string path = ScheduledPublishOutcome.RecordPath(directory, courseCode, sectionNumber, workingFolder);
        string[] lines;
        DateTime writtenAt;
        try
        {
            if (!File.Exists(path)) return Array.Empty<SiteHealthFinding>();
            lines = File.ReadAllLines(path);
            writtenAt = File.GetLastWriteTime(path);
        }
        catch
        {
            return Array.Empty<SiteHealthFinding>();
        }

        // Consumed whether or not a single line parses. A record that cannot be
        // read is litter, and leaving it would have the app retry it every
        // morning for ever.
        //
        // One consequence shared with the mac, named rather than hidden: the
        // wrapper treats "no markers in the output" as "nothing wrong", so a
        // run that died BEFORE the checks — a missing runtime, an archived
        // section, a crash — clears a genuine record from the night before.
        // The alternative is worse: a record that only ever grows stale.
        try { File.Delete(path); } catch { }

        // Every machine line the wrapper kept goes through the ONE dispatch the
        // app's console and plantoir-mcp use (#660), dated to the record: a
        // scheduled publish is often the first build after a class goes
        // visible (PLANTOIR_DATED:, #279), the build nobody watched is the one
        // "my second map is missing" (PLANTOIR_MAPS:, #345) or "my students
        // have no My Progress page" (#599) is asked about, it can be the first
        // run that gets Swift ready (#570), and nobody watched it put a front
        // page's title right (#584) or remake a Cloudflare project (#395,
        // appended by the wrapper's Cloudflare leg). Since #660 the trail
        // takes them in the record's LINE order rather than grouped by kind.
        var findings = new List<SiteHealthFinding>();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (string line in lines)
        {
            if (BuildMachineLines.Record(line, writtenAt).Finding is { } finding &&
                BuildMachineLines.AddFinding(finding, seen, writtenAt))
                findings.Add(finding);
        }
        return findings;
    }
}

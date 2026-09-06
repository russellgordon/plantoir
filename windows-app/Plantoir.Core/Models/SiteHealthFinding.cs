using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Plantoir.Core.Models;

/// <summary>
/// One problem a build found with a course's folders, lifted out of the
/// console transcript the app is already reading.
///
/// <para><b>The sentence travels in the line, and that is the point.</b>
/// <c>scripts/site_health.py</c> prints one <c>PLANTOIR_HEALTH:</c> line per
/// finding, carrying the teacher-facing sentence and detail with it, so the two
/// apps cannot word the same problem differently. Nothing here re-authors a
/// sentence; this type only parses and classifies. Pinned by
/// <c>contracts/shared-rules.json</c> -> <c>siteHealth</c>.</para>
/// </summary>
public sealed record SiteHealthFinding(
    string Name,
    string Sentence,
    string Detail,
    bool Fixable,
    string Course,
    int Section)
{
    /// <summary>The fixed prefix the build prints in front of the JSON.</summary>
    public const string Marker = "PLANTOIR_HEALTH:";

    /// <summary>
    /// The checks THIS app can actually put right.
    ///
    /// <para>Decided from the check's NAME, never from <see cref="Fixable"/>
    /// alone: the flag means "this kind of thing is repairable", while what has
    /// to be true is that this app has a repair for THIS check. Recreating an
    /// empty curriculum folder would silence "the curriculum map could not be
    /// built" and leave the map missing, because the folder only counts once it
    /// holds a page named for an expectation code -- a button that makes a
    /// warning go away without fixing anything is worse than no button.</para>
    ///
    /// <para>Pinned by <c>SiteHealthContractTests</c> against BOTH halves of
    /// <c>siteHealth.repair</c>: this list must equal <c>offered.checks</c>,
    /// and must share no name with <c>neverOffered.checks</c>. So a check
    /// added to the contract on either platform fails here rather than
    /// quietly acquiring -- or quietly losing -- a Fix button.</para>
    /// </summary>
    public static readonly IReadOnlyList<string> RepairableChecks =
        new[] { "mediaFolderMissing", "sectionIndexMissing" };

    /// <summary>Whether a Fix button may be offered for this finding.</summary>
    public bool CanBeRepaired => RepairableChecks.Contains(Name, StringComparer.Ordinal);

    /// <summary>
    /// What makes this the SAME problem as another: the check, the course and
    /// the section. One build reporting a rebuilt section twice is one
    /// problem; the same check in two sections is two.
    ///
    /// <para>Lives on the record so the two places that de-duplicate --
    /// <see cref="FindingsIn"/> over a finished transcript, and
    /// <c>ScriptRunner</c> over a live one -- cannot drift into disagreeing
    /// about what a duplicate is.</para>
    /// </summary>
    public string Identity => $"{Name} {Course} {Section}";

    /// <summary>
    /// Parse one console line, or null when it is not a finding.
    ///
    /// <para>Tolerant of anything before the marker on the line: the launchers
    /// interleave this output with ordinary build chatter, and a finding that
    /// arrived glued to the tail of another line is still a finding. A line
    /// carrying the marker but malformed JSON returns null rather than
    /// throwing -- a build must never fail because a health line was odd.</para>
    /// </summary>
    public static SiteHealthFinding? Parse(string? line)
    {
        if (string.IsNullOrWhiteSpace(line)) return null;
        int at = line.IndexOf(Marker, StringComparison.Ordinal);
        if (at < 0) return null;

        string payload = line[(at + Marker.Length)..].Trim();
        if (payload.Length == 0) return null;

        try
        {
            if (JsonNode.Parse(payload) is not JsonObject obj) return null;
            string name = obj["name"]?.ToString() ?? "";
            if (name.Length == 0) return null;
            return new SiteHealthFinding(
                name,
                obj["sentence"]?.ToString() ?? "",
                obj["detail"]?.ToString() ?? "",
                obj["fixable"]?.GetValue<bool>() ?? false,
                obj["course"]?.ToString() ?? "",
                obj["section"]?.GetValue<int>() ?? 0);
        }
        catch (JsonException)
        {
            return null;
        }
        catch (FormatException)
        {
            return null;
        }
        catch (InvalidOperationException)
        {
            // A value of the wrong JSON type -- "section": "1" -- reaches here
            // from GetValue<T>. Same answer as malformed JSON: not a finding.
            return null;
        }
    }

    /// <summary>
    /// Every finding in a transcript, in the order the build printed them,
    /// with duplicates from a rebuilt section collapsed.
    ///
    /// <para>De-duplicated on name + course + section because a transcript can
    /// hold more than one build -- the app appends to one console -- and
    /// telling a teacher the same folder is missing three times reads as three
    /// problems.</para>
    /// </summary>
    public static IReadOnlyList<SiteHealthFinding> FindingsIn(IEnumerable<string>? transcriptLines)
    {
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var found = new List<SiteHealthFinding>();
        foreach (string line in transcriptLines ?? Enumerable.Empty<string>())
        {
            var finding = Parse(line);
            if (finding is null) continue;
            if (!seen.Add(finding.Identity)) continue;
            found.Add(finding);
        }
        return found;
    }

    /// <summary>
    /// The sentence recorded on the activity trail -- the stable check NAME in
    /// brackets, never the product wording, and never anything written on a
    /// page.
    ///
    /// <para>The wording will be reworded; the name is what somebody searching
    /// the trail six months later can match against the contract.
    /// <c>shared-rules.json</c> -> <c>activityTrail.mustRecord</c> ->
    /// "folder problem found".</para>
    /// </summary>
    public string TrailSentence => $"found a problem with this course’s folders ({Name})";

    /// <summary>
    /// A message with what the build found about the folders added to the end
    /// of it, or the message unchanged when it found nothing.
    ///
    /// <para>How a folder problem reaches somebody talking to the ASSISTANT,
    /// which has no dialog to raise and no window to raise it in. The sentence
    /// and the detail are the payload's own, exactly as in the app's dialog —
    /// the whole point of the wording travelling in the line is that the same
    /// problem cannot be worded three different ways.</para>
    ///
    /// <para>Appended rather than headlined: the teacher asked for something,
    /// and the answer to what they asked comes first. Matches the mac's
    /// <c>SiteHealthFinding.appending(to:from:)</c>.</para>
    /// </summary>
    public static string Appending(string message, IReadOnlyList<SiteHealthFinding>? findings)
    {
        if (findings is null || findings.Count == 0) return message;
        var parts = new List<string> { message };
        foreach (var finding in findings) parts.Add(finding.Sentence + " " + finding.Detail);
        return string.Join("\n\n", parts);
    }
}

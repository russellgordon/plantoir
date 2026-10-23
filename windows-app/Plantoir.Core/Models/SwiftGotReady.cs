using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Models;

/// <summary>
/// <c>swift_windows_fetch.py</c>'s <c>PLANTOIR_SWIFT:</c> line (GitHub #570;
/// <c>shared-rules.json</c> → <c>codeRunnerBlocks.swift.windows.marker</c>):
/// the first preview with a Swift block got Swift ready on this PC, or could
/// not, and why. Turned into ONE trail line — <c>Swift got ready on this
/// computer</c> or <c>Swift could not be got ready</c> (<c>activityTrail.
/// mustRecord</c>) — read from the console of a run the app starts
/// (<c>ScriptRunner</c>) and from a scheduled publish's record
/// (<c>ScheduledHealthFindings</c>), the <see cref="MyProgressBuilt"/> pattern.
/// Printed only when getting Swift ready finished or failed, never when it was
/// already ready.
/// </summary>
public sealed record SwiftGotReady(bool Ready, int Seconds, long DownloadedBytes, string Reason, string? Course, int Section)
{
    public const string Marker = "PLANTOIR_SWIFT:";

    /// <summary>The contract's <c>whyWords</c> for "Swift could not be got ready".</summary>
    public static readonly IReadOnlyDictionary<string, string> WhyWords = new Dictionary<string, string>
    {
        ["offline"] = "no internet connection, or the download stopped",
        ["noRoom"] = "not enough free space",
        ["damaged"] = "the download was not what was expected and was thrown away",
        ["busy"] = "another installation was running",
        ["unpack"] = "it could not be unpacked",
        ["waited"] = "another preview was still getting it ready after 20 minutes",
    };

    public ActivityTrail.Event Event => Ready
        ? ActivityTrail.Event.SwiftGotReady
        : ActivityTrail.Event.SwiftCouldNotBeGotReady;

    /// <summary>The line after the course and section (each event's <c>line</c>).</summary>
    public string TrailSentence => Ready
        ? $"got Swift ready on this computer in {Seconds.ToString(CultureInfo.InvariantCulture)} s " +
          $"({(DownloadedBytes / 1e9).ToString("0.0", CultureInfo.InvariantCulture)} GB downloaded, once)"
        : $"Swift could not be got ready on this computer: {(WhyWords.TryGetValue(Reason, out var why) ? why : Reason)}";

    /// <summary>Writes the line, with the course and section when the launcher named them.</summary>
    public void Record(DateTime? moment = null)
    {
        bool named = Course is { Length: > 0 } && Section > 0;
        if (Ready && named)
            ActivityTrail.Note(ActivityTrail.Event.SwiftGotReady, TrailSentence, Course!, Section, moment);
        else if (Ready)
            ActivityTrail.Note(ActivityTrail.Event.SwiftGotReady, TrailSentence, moment);
        else if (named)
            ActivityTrail.Note(ActivityTrail.Event.SwiftCouldNotBeGotReady, TrailSentence, Course!, Section, moment);
        else
            ActivityTrail.Note(ActivityTrail.Event.SwiftCouldNotBeGotReady, TrailSentence, moment);
    }

    /// <summary>The report on one line, read from the marker onward, or null when it is not one.</summary>
    public static SwiftGotReady? Parse(string? line)
    {
        if (string.IsNullOrWhiteSpace(line)) return null;
        int at = line.IndexOf(Marker, StringComparison.Ordinal);
        if (at < 0) return null;
        string payload = line[(at + Marker.Length)..].Trim();
        try
        {
            if (JsonNode.Parse(payload) is not JsonObject obj) return null;
            if (obj["ready"] is not JsonValue ready) return null;
            string? course = obj["course"] is JsonValue c ? c.GetValue<string>() : null;
            int section = obj["section"] is JsonValue s ? s.GetValue<int>() : 0;
            if (ready.GetValue<bool>())
            {
                int seconds = obj["seconds"] is JsonValue sec ? sec.GetValue<int>() : 0;
                long bytes = obj["downloadedBytes"] is JsonValue b ? b.GetValue<long>() : 0;
                return new SwiftGotReady(true, seconds, bytes, "", course, section);
            }
            if (obj["reason"] is not JsonValue reason) return null;
            return new SwiftGotReady(false, 0, 0, reason.GetValue<string>(), course, section);
        }
        catch (Exception exception) when (exception is JsonException or InvalidOperationException or FormatException)
        {
            return null;
        }
    }

    public static IReadOnlyList<SwiftGotReady> ReportsIn(IEnumerable<string> lines) =>
        lines.Select(Parse).Where(report => report is not null).Select(report => report!).ToList();
}

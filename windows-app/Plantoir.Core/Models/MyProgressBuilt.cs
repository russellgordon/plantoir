using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Plantoir.Core.Models;

/// <summary>
/// The build's <c>PLANTOIR_MY_PROGRESS:</c> line (<c>shared-rules.json</c> →
/// <c>myProgressBuilt</c>; GitHub issue #599, the mac's #545 and its
/// <c>MyProgressBuilt.swift</c>): whether a build made a section's My Progress
/// page, how many pages count, and — when it made none — why, turned into ONE
/// <c>my progress page built</c> line on the trail. Read from the console of a
/// run the app starts (<c>ScriptRunner</c>) and from a scheduled publish's
/// record (<c>ScheduledHealthFindings</c>), the <see cref="CoverageMapsBuilt"/>
/// pattern. Counts and reasons are course structure, never anything written
/// on a page.
/// </summary>
public sealed record MyProgressBuilt(string Course, int Section, bool Built, int Pages, string Reason)
{
    public const string Marker = "PLANTOIR_MY_PROGRESS:";

    /// <summary><c>trailLine.shapes</c>: built, teachersOwnPage, or (any other reason) noSuccessCriteria.</summary>
    public string TrailSentence => Built
        ? $"the build made the My Progress page: {Pages.ToString(CultureInfo.InvariantCulture)} {(Pages == 1 ? "page" : "pages")} with success criteria to tick"
        : Reason == "teachersOwnPage"
            ? "the build made no My Progress page: the course has its own page called My Progress"
            : "the build made no My Progress page: no page students can see has boxes to tick under a success-criteria heading";

    /// <summary>The report on one line, read from the marker onward, or null when it is not one.</summary>
    public static MyProgressBuilt? Parse(string? line)
    {
        if (string.IsNullOrWhiteSpace(line)) return null;
        int at = line.IndexOf(Marker, StringComparison.Ordinal);
        if (at < 0) return null;
        string payload = line[(at + Marker.Length)..].Trim();
        try
        {
            if (JsonNode.Parse(payload) is not JsonObject obj) return null;
            if (obj["course"] is not JsonValue course || obj["section"] is not JsonValue section
                || obj["built"] is not JsonValue built || obj["pages"] is not JsonValue pages
                || obj["reason"] is not JsonValue reason) return null;
            string code = course.GetValue<string>();
            int number = section.GetValue<int>();
            if (code.Length == 0 || number <= 0) return null;
            return new MyProgressBuilt(code, number, built.GetValue<bool>(), pages.GetValue<int>(), reason.GetValue<string>());
        }
        catch (Exception exception) when (exception is JsonException or InvalidOperationException or FormatException)
        {
            return null;
        }
    }

    public static IReadOnlyList<MyProgressBuilt> ReportsIn(IEnumerable<string> lines) =>
        lines.Select(Parse).Where(report => report is not null).Select(report => report!).ToList();
}

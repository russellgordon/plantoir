using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Plantoir.Core.Models;

/// <summary>
/// The build's <c>PLANTOIR_MAPS:</c> line (<c>shared-rules.json</c> →
/// <c>coverageMapsBuilt</c>; GitHub issue #345, the mac's #128 and its
/// <c>CoverageMapsBuilt.swift</c>): which curriculum coverage maps a build
/// wrote, turned into ONE <c>curriculum maps built</c> line on the trail.
/// Read from the console of a run the app starts (<c>ScriptRunner</c>) and
/// from a scheduled publish's record (<c>ScheduledHealthFindings</c>) — the
/// build nobody watches is exactly the one "my second map is missing" will be
/// asked about. Titles, folder names and counts are course structure, never
/// anything written on a page.
/// </summary>
public sealed record CoverageMapsBuilt(string Course, int Section, IReadOnlyList<CoverageMapsBuilt.Map> Maps)
{
    public sealed record Map(string Title, string Folder, int Expectations);

    public const string Marker = "PLANTOIR_MAPS:";

    /// <summary><c>trailLine.shape</c>: the count first, then each map as a teacher would say it.</summary>
    public string TrailSentence => Maps.Count == 0
        ? "the build made no curriculum map: no curriculum folder holds an expectation page"
        : $"the build made {Maps.Count} curriculum {(Maps.Count == 1 ? "map" : "maps")}: " +
          string.Join(", ", Maps.Select(map =>
              $"{map.Title} from {map.Folder} ({map.Expectations.ToString(CultureInfo.InvariantCulture)} {(map.Expectations == 1 ? "expectation" : "expectations")})"));

    public static CoverageMapsBuilt? Parse(string? line)
    {
        if (string.IsNullOrWhiteSpace(line)) return null;
        int at = line.IndexOf(Marker, StringComparison.Ordinal);
        if (at < 0) return null;
        string payload = line[(at + Marker.Length)..].Trim();
        try
        {
            if (JsonNode.Parse(payload) is not JsonObject obj) return null;
            string course = obj["course"]?.GetValue<string>() ?? "";
            int section = obj["section"]?.GetValue<int>() ?? 0;
            if (course.Length == 0 || section <= 0 || obj["maps"] is not JsonArray maps) return null;
            var parsed = maps.OfType<JsonObject>()
                .Select(map => new Map(
                    map["title"]?.GetValue<string>() ?? "",
                    map["folder"]?.GetValue<string>() ?? "",
                    map["expectations"]?.GetValue<int>() ?? 0))
                .Where(map => map.Title.Length > 0)
                .ToList();
            return new CoverageMapsBuilt(course, section, parsed);
        }
        catch (Exception exception) when (exception is JsonException or InvalidOperationException or FormatException)
        {
            return null;
        }
    }

    public static IReadOnlyList<CoverageMapsBuilt> ReportsIn(IEnumerable<string> lines) =>
        lines.Select(Parse).Where(report => report is not null).Select(report => report!).ToList();
}

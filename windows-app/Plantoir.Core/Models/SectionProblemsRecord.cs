using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Plantoir.Core.Models;

/// <summary>
/// A section's record of its problems, as the build left it (#734, the mac's
/// #717): <c>&lt;builds root&gt;\&lt;COURSE&gt;\section&lt;N&gt;\.problems.json</c>,
/// written by the shared Python (<c>scripts/section_problems.py</c>,
/// <c>site_said.py</c>, <c>deploy.py</c>) and READ here, never written.
/// </summary>
/// <remarks>
/// <para>The format is <c>contracts/shared-rules.json</c> →
/// <c>sectionProblems.file</c>. Read tolerantly, the way every other file the
/// build writes is read here: a record this app cannot read is NO record,
/// never an exception. The mac's <c>SectionProblemsRecord.swift</c> reads the
/// same fields with the same defaults.</para>
/// </remarks>
public sealed class SectionProblemsRecord
{
    /// <summary>The name of the file beside the section's built site (<c>file.name</c>).</summary>
    public const string FileName = ".problems.json";

    /// <summary>The only version this app reads (<c>file.version</c>).</summary>
    public const int Version = 1;

    public required string Course { get; init; }
    public required int Section { get; init; }
    public required string BuildId { get; init; }
    public DateTimeOffset? BuiltAt { get; init; }

    /// <summary><c>preview</c> or <c>deploy</c> — which kind of build wrote it.</summary>
    public string Occasion { get; init; } = "preview";

    public IReadOnlyList<SectionProblemRow> Rows { get; init; } = Array.Empty<SectionProblemRow>();

    /// <summary>The pages the build showed, by place in the course folder.</summary>
    public IReadOnlyList<string> PagesShown { get; init; } = Array.Empty<string>();

    public IReadOnlyList<string> NewIds { get; init; } = Array.Empty<string>();
    public IReadOnlyList<string> GoneIds { get; init; } = Array.Empty<string>();
    public bool SiteSaidComplete { get; init; }

    /// <summary>What an answer to the alert is remembered by (<c>sectionProblems.alert</c>).</summary>
    public string AlertKey { get; init; } = "";

    /// <summary>Whether this build met a problem new since the build before it.</summary>
    public bool HasNewProblems => NewIds.Count > 0;

    /// <summary>Whether the set changed at all — new or gone.</summary>
    public bool SetChanged => NewIds.Count > 0 || GoneIds.Count > 0;

    /// <summary>Whether this record was written by a deploy rather than a preview.</summary>
    public bool CameFromADeploy => Occasion == "deploy";

    /// <summary>The rows this record found new, in the record's order.</summary>
    public IReadOnlyList<SectionProblemRow> NewRows =>
        Rows.Where(row => NewIds.Contains(row.Id, StringComparer.Ordinal)).ToList();

    /// <summary>
    /// Where a section's record is: beside its built site, under the builds
    /// root the LAUNCHERS wrote it to
    /// (<see cref="BuildOutputLocation.WhereTheLaunchersBuild"/>).
    /// </summary>
    public static string PathFor(string buildsRoot, string courseCode, int sectionNumber) =>
        Path.Combine(BuildOutputLocation.ForSection(buildsRoot, courseCode, sectionNumber), FileName);

    /// <summary>The record at <paramref name="path"/>, or null when there is none this app can read. Never throws.</summary>
    public static SectionProblemsRecord? Read(string path)
    {
        try
        {
            if (!File.Exists(path)) return null;
            using var stream = OpenShared(path);
            using var reader = new StreamReader(stream, System.Text.Encoding.UTF8);
            return Parse(reader.ReadToEnd());
        }
        catch (Exception) { return null; }
    }

    /// <summary>
    /// Opens the record for reading WITHOUT standing in the writer's way:
    /// sharing read, write and DELETE. The shared Python replaces the file
    /// with <c>os.replace</c> (<c>section_problems.py</c>), which Windows
    /// refuses while another handle has it open without delete sharing — and
    /// its caller swallows the refusal, so a read at the wrong moment would
    /// lose a build's record silently (#734 implementation review, finding 2;
    /// <c>File.ReadAllText</c> shares read only).
    /// </summary>
    public static FileStream OpenShared(string path) =>
        new(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);

    /// <summary>The record in <paramref name="text"/>, or null. Never throws.</summary>
    public static SectionProblemsRecord? Parse(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        try
        {
            if (JsonNode.Parse(text) is not JsonObject root) return null;
            if (Int(root["version"]) != Version) return null;
            if (root["rows"] is not JsonArray rowArray) return null;
            var rows = new List<SectionProblemRow>();
            foreach (var node in rowArray)
                if (node is JsonObject rowObject && SectionProblemRow.Parse(rowObject) is { } row) rows.Add(row);
            var changed = root["changed"] as JsonObject;
            string buildId = Text(root["buildId"]);
            string alertKey = Text(root["alertKey"]);
            return new SectionProblemsRecord
            {
                Course = Text(root["course"]),
                Section = Int(root["section"]) ?? 0,
                BuildId = buildId,
                BuiltAt = Date(root["builtAt"]),
                Occasion = Text(root["occasion"]) is { Length: > 0 } occasion ? occasion : "preview",
                Rows = rows,
                PagesShown = Texts(root["pagesShown"]),
                NewIds = Texts(changed?["new"]),
                GoneIds = Texts(changed?["gone"]),
                SiteSaidComplete = Bool(root["siteSaidComplete"]),
                AlertKey = alertKey.Length > 0 ? alertKey : buildId,
            };
        }
        catch (Exception) { return null; }
    }

    /// <summary>The kind an id names: everything before its first <c>|</c> or <c>#</c>.</summary>
    public static string KindOfId(string id)
    {
        int end = id.IndexOfAny(new[] { '|', '#' });
        return end < 0 ? id : id[..end];
    }

    // ---- Tolerant readers ------------------------------------------------

    internal static string Text(JsonNode? node) =>
        node is JsonValue value && value.TryGetValue(out string? text) ? text ?? "" : "";

    internal static int? Int(JsonNode? node) =>
        node is JsonValue value && value.TryGetValue(out int number) ? number : null;

    internal static bool Bool(JsonNode? node) =>
        node is JsonValue value && value.TryGetValue(out bool flag) && flag;

    internal static IReadOnlyList<string> Texts(JsonNode? node) =>
        node is JsonArray array
            ? array.OfType<JsonValue>().Select(Text).ToList()
            : Array.Empty<string>();

    /// <summary>A time the build wrote (UTC, ISO 8601), or null.</summary>
    internal static DateTimeOffset? Date(JsonNode? node)
    {
        string text = Text(node);
        if (text.Length == 0) return null;
        return DateTimeOffset.TryParse(text, CultureInfo.InvariantCulture,
                                       DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var when)
            ? when
            : null;
    }
}

/// <summary>One problem a build of a section met (<c>sectionProblems.file.fields</c>).</summary>
public sealed record SectionProblemRow
{
    public required string Id { get; init; }
    public required string Kind { get; init; }

    /// <summary>The page by its place in the course folder, or empty for a whole-section or whole-course problem.</summary>
    public string Page { get; init; } = "";

    /// <summary>The item's reason key, or empty.</summary>
    public string Reason { get; init; } = "";

    /// <summary>The one piece of the folder problem's list that names this item.</summary>
    public string Item { get; init; } = "";
    public string Sentence { get; init; } = "";
    public string Detail { get; init; } = "";
    public bool Fixable { get; init; }

    /// <summary>One bounded line for an outside assistant (#736 hands it over).</summary>
    public string Prompt { get; init; } = "";

    /// <summary><c>build</c>, <c>site</c> or <c>deploy</c>: which writer owns it.</summary>
    public string From { get; init; } = "build";
    public DateTimeOffset? FirstSeen { get; init; }
    public DateTimeOffset? LastSeen { get; init; }

    /// <summary>True when the build that wrote the record did not check it.</summary>
    public bool Carried { get; init; }

    internal static SectionProblemRow? Parse(JsonObject row)
    {
        string id = SectionProblemsRecord.Text(row["id"]);
        if (id.Length == 0) return null;
        string kind = SectionProblemsRecord.Text(row["kind"]);
        string from = SectionProblemsRecord.Text(row["from"]);
        return new SectionProblemRow
        {
            Id = id,
            Kind = kind.Length > 0 ? kind : SectionProblemsRecord.KindOfId(id),
            Page = SectionProblemsRecord.Text(row["page"]),
            Reason = SectionProblemsRecord.Text(row["reason"]),
            Item = SectionProblemsRecord.Text(row["item"]),
            Sentence = SectionProblemsRecord.Text(row["sentence"]),
            Detail = SectionProblemsRecord.Text(row["detail"]),
            Fixable = SectionProblemsRecord.Bool(row["fixable"]),
            Prompt = SectionProblemsRecord.Text(row["prompt"]),
            From = from.Length > 0 ? from : "build",
            FirstSeen = SectionProblemsRecord.Date(row["firstSeen"]),
            LastSeen = SectionProblemsRecord.Date(row["lastSeen"]),
            Carried = SectionProblemsRecord.Bool(row["carried"]),
        };
    }

    /// <summary>The folder problem a row is, for the repair: the same name, words and course the build's own finding has.</summary>
    public SiteHealthFinding AsFinding(string courseCode, int sectionNumber) =>
        new(Kind, Sentence, Detail, Fixable, courseCode, sectionNumber);
}

/// <summary>
/// The build's word that a section's record changed
/// (<c>sectionProblems.marker</c>): counts only, never a row. Machinery
/// (<c>transcriptStripping.machineLines</c>), never shown.
/// </summary>
public sealed record SectionProblemsMarker(string Course, int Section, string BuildId, string AlertKey, int Rows, int New, int Gone)
{
    public const string Prefix = "PLANTOIR_PROBLEMS:";

    /// <summary>The marker in <paramref name="line"/>, read from the prefix onward (#153's rule: half a line glued in front of it does not hide it), or null.</summary>
    public static SectionProblemsMarker? Parse(string? line)
    {
        if (line is null) return null;
        int at = line.IndexOf(Prefix, StringComparison.Ordinal);
        if (at < 0) return null;
        try
        {
            if (JsonNode.Parse(line[(at + Prefix.Length)..].Trim()) is not JsonObject marker) return null;
            if (marker["course"] is not JsonValue) return null;
            if (SectionProblemsRecord.Int(marker["section"]) is not { } section) return null;
            string buildId = SectionProblemsRecord.Text(marker["buildId"]);
            string alertKey = SectionProblemsRecord.Text(marker["alertKey"]);
            return new SectionProblemsMarker(
                SectionProblemsRecord.Text(marker["course"]), section, buildId,
                alertKey.Length > 0 ? alertKey : buildId,
                SectionProblemsRecord.Int(marker["rows"]) ?? 0,
                SectionProblemsRecord.Int(marker["new"]) ?? 0,
                SectionProblemsRecord.Int(marker["gone"]) ?? 0);
        }
        catch (JsonException) { return null; }
    }
}

using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// The build's <c>PLANTOIR_LINKS_CHECKLIST:</c> line (<c>linksChecklist.marker</c>).
/// </summary>
public sealed record LinksChecklistMarker(string Course, int Section, string BuildId, int Pages)
{
    public const string Prefix = "PLANTOIR_LINKS_CHECKLIST:";

    public static LinksChecklistMarker? Parse(string? line)
    {
        if (line is null) return null;
        int at = line.IndexOf(Prefix, StringComparison.Ordinal);
        if (at < 0) return null;
        try
        {
            if (JsonNode.Parse(line[(at + Prefix.Length)..].Trim()) is not JsonObject marker) return null;
            string? course = marker["course"]?.ToString();
            string? buildId = marker["buildId"]?.ToString();
            if (course is null || buildId is null) return null;
            int section = marker["section"] is JsonValue s && s.TryGetValue(out int n) ? n : 0;
            int pages = marker["pages"] is JsonValue p && p.TryGetValue(out int count) ? count : 0;
            return new LinksChecklistMarker(course, section, buildId, pages);
        }
        catch (JsonException) { return null; }
    }
}

/// <summary>
/// WHEN the links checklist is shown (<c>linksChecklist.offeredWhen</c>, #392).
/// Logic, not pixels, so the section window and its tests ask the same rules.
/// </summary>
public static class LinksChecklistShowing
{
    /// <summary>
    /// After a build this window WATCHED: when the marker arrives naming an
    /// offer with pages and the file carries that marker's buildId — never on
    /// the #333 finding, which is announced before the offer exists.
    /// </summary>
    public static LinksChecklistOffer? AfterAWatchedBuild(Course course, int section, LinksChecklistMarker marker)
    {
        if (marker.Pages <= 0 || !string.Equals(marker.Course, course.Code, StringComparison.OrdinalIgnoreCase) ||
            marker.Section != section || IsKeptForReference(course))
            return null;
        var offer = LinksChecklistOffer.Read(LinksChecklistOffer.PathFor(course.DirectoryPath, section));
        if (offer is null || offer.Rows.Count == 0 || offer.BuildId != marker.BuildId) return null;
        return HoldsSomethingNew(course, section, offer) ? offer : null;
    }

    /// <summary>
    /// When the section window appears or becomes active, for a build it did
    /// not watch: only a FRESH offer (written after the course's newest change)
    /// holding a page the teacher has not answered.
    /// </summary>
    public static LinksChecklistOffer? ForABuildNotWatched(Course course, int section)
    {
        if (IsKeptForReference(course)) return null;
        var offer = Offer(course, section);
        if (offer is null || !IsFresh(course, section)) return null;
        return HoldsSomethingNew(course, section, offer) ? offer : null;
    }

    /// <summary>The offer on disk with pages in it, for the menu item, whatever was answered.</summary>
    public static LinksChecklistOffer? Offer(Course course, int section)
    {
        var offer = LinksChecklistOffer.Read(LinksChecklistOffer.PathFor(course.DirectoryPath, section));
        return offer is { Rows.Count: > 0 } ? offer : null;
    }

    /// <summary>offeredWhen.onlyWhenFresh: the offer is no older than the course's newest change.</summary>
    public static bool IsFresh(Course course, int section)
    {
        string path = LinksChecklistOffer.PathFor(course.DirectoryPath, section);
        if (!File.Exists(path)) return false;
        DateTime written = File.GetLastWriteTimeUtc(path);
        DateTime? newest = BuildFreshness.NewestContentDate(course.DirectoryPath);
        return newest is null || newest.Value.ToUniversalTime() <= written;
    }

    private static bool HoldsSomethingNew(Course course, int section, LinksChecklistOffer offer) =>
        LinksChecklist.HoldsSomethingNew(offer, LinksChecklist.ReadAnswered(course.DirectoryPath, section).Offered);

    private static bool IsKeptForReference(Course course) => ReferenceCourse.IsKeptForReference(course);
}

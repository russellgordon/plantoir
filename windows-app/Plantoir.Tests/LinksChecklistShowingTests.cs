using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// WHEN the links checklist is shown (<c>linksChecklist.offeredWhen</c>, #392):
/// on the marker carrying the file's buildId, never an older build's offer;
/// only a fresh offer for a build not watched; never once every page is answered.
/// </summary>
public class LinksChecklistShowingTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-checklist-showing").FullName;
    private readonly string _course;

    public LinksChecklistShowingTests()
    {
        _course = Path.Combine(_folder, "ICS3U");
        Directory.CreateDirectory(Path.Combine(_course, "section1", "All Classes"));
        File.WriteAllText(Path.Combine(_course, "course_config.json"),
            """{ "course_code": "ICS3U", "course_name": "A", "num_sections": 1, "per_section_folders": ["All Classes"], "section_numbers": [1] }""");
        File.WriteAllText(Path.Combine(_course, "section1", "All Classes", "Unit 1, Day 1.md"), "---\npublish: false\n---\nBody.\n");
        File.SetLastWriteTimeUtc(Path.Combine(_course, "section1", "All Classes", "Unit 1, Day 1.md"), DateTime.UtcNow.AddMinutes(-10));
        WriteOffer("build-2");
    }

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private Course Course => Workspace.DiscoverCourses(_folder).Count > 0
        ? Workspace.DiscoverCourses(_folder)[0]
        : new Course("ICS3U", _course, CourseConfiguration.FromBytes(File.ReadAllBytes(Path.Combine(_course, "course_config.json"))));

    private void WriteOffer(string buildId)
    {
        string path = LinksChecklistOffer.PathFor(_course, 1);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, $$"""
            { "version": 1, "course": "ICS3U", "section": 1, "buildId": "{{buildId}}",
              "pages": [ { "place": "Concepts/Worksheet", "group": "fromAClass", "ticked": true, "dependsOn": [] } ] }
            """);
    }

    [Fact]
    public void TheMarkerIsReadAsTheBuildPrintsIt()
    {
        var marker = LinksChecklistMarker.Parse(
            "PLANTOIR_LINKS_CHECKLIST: {\"course\": \"ICS4U\", \"section\": 1, \"buildId\": \"20260929T233000Z-1a2b3c4d\", \"pages\": 11, \"ticked\": 8}");
        Assert.Equal(new LinksChecklistMarker("ICS4U", 1, "20260929T233000Z-1a2b3c4d", 11), marker);
        Assert.Null(LinksChecklistMarker.Parse("PLANTOIR_HEALTH: {}"));
    }

    [Fact]
    public void AWatchedBuildShowsOnlyTheOfferItsOwnMarkerNames()
    {
        Assert.NotNull(LinksChecklistShowing.AfterAWatchedBuild(Course, 1, new LinksChecklistMarker("ICS3U", 1, "build-2", 1)));
        // The previous build's offer, read on the #333 finding, is the trap.
        Assert.Null(LinksChecklistShowing.AfterAWatchedBuild(Course, 1, new LinksChecklistMarker("ICS3U", 1, "build-1", 1)));
        Assert.Null(LinksChecklistShowing.AfterAWatchedBuild(Course, 1, new LinksChecklistMarker("ICS3U", 1, "build-2", 0)));
    }

    [Fact]
    public void ABuildNotWatchedShowsOnlyAFreshOfferWithSomethingNew()
    {
        Assert.NotNull(LinksChecklistShowing.ForABuildNotWatched(Course, 1));

        LinksChecklist.WriteAnswered(_course, 1, new[] { "Concepts/Worksheet" }, Array.Empty<string>(), DateTime.UtcNow);
        Assert.Null(LinksChecklistShowing.ForABuildNotWatched(Course, 1));
    }

    [Fact]
    public void AnOfferOlderThanTheCoursesNewestChangeIsNotShown()
    {
        File.SetLastWriteTimeUtc(LinksChecklistOffer.PathFor(_course, 1), DateTime.UtcNow.AddMinutes(-20));
        Assert.False(LinksChecklistShowing.IsFresh(Course, 1));
        Assert.Null(LinksChecklistShowing.ForABuildNotWatched(Course, 1));
        Assert.NotNull(LinksChecklistShowing.Offer(Course, 1));   // the menu still finds it, and asks for a preview
    }
}

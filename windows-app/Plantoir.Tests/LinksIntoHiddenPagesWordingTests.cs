using Plantoir.Core.Assist;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// #392 remainder (mac #379): the assistant says
/// <c>linksIntoHiddenPagesWillBeOffered</c> for the links-into-hidden-pages
/// finding ONLY when the same build printed the checklist marker, the offer
/// on disk is that build's and holds something new — otherwise the finding's
/// own words, so it never promises a sheet that will not come.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class LinksIntoHiddenPagesWordingTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("links-hidden-wording").FullName;
    private string Course => Path.Combine(_folder, "courses", "ICS3U");

    public LinksIntoHiddenPagesWordingTests()
    {
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        Directory.CreateDirectory(Path.Combine(Course, "section1", "All Classes"));
        File.WriteAllText(Path.Combine(Course, "course_config.json"),
            """{ "course_code": "ICS3U", "course_name": "A", "num_sections": 1, "per_section_folders": ["All Classes"], "section_numbers": [1] }""");
        string path = LinksChecklistOffer.PathFor(Course, 1);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, """
            { "version": 1, "course": "ICS3U", "section": 1, "buildId": "build-2",
              "pages": [ { "place": "Concepts/Worksheet", "group": "fromAClass", "ticked": true, "dependsOn": [] } ] }
            """);
    }

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private sealed class BuildThatFound(LinksChecklistMarker? marker) : ILauncherRunner
    {
        public Task<LaunchOutcome> Run(string launcher, IReadOnlyList<string> arguments, string workingFolder,
                                       IProgress<string>? progress, CancellationToken cancellation) =>
            Task.FromResult(new LaunchOutcome(true, "Done.", new[]
            {
                new SiteHealthFinding("linksIntoHiddenPages", "Some links lead to hidden pages.", "Unit 1 → Worksheet", false, "ICS3U", 1),
            }, 0, marker));
    }

    private async Task<string> Rebuilt(LinksChecklistMarker? marker) =>
        (await new AssistWorkspace(_folder, new BuildThatFound(marker)).RebuildPreview("ICS3U", 1)).Message;

    [Fact]
    public async Task TheSheetIsPromisedOnlyWhenThisBuildMadeIt()
    {
        string offered = AssistWording.LinksIntoHiddenPagesWillBeOffered("ICS3U", "1");
        Assert.Contains(offered, await Rebuilt(new LinksChecklistMarker("ICS3U", 1, "build-2", 1)));
        // An older build's marker, or none: the finding's own words.
        Assert.DoesNotContain(offered, await Rebuilt(new LinksChecklistMarker("ICS3U", 1, "build-1", 1)));
        string plain = await Rebuilt(null);
        Assert.DoesNotContain(offered, plain);
        Assert.Contains("Some links lead to hidden pages. Unit 1 → Worksheet", plain);
    }
}

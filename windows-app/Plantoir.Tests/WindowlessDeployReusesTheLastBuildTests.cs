using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// #799 (the #799 plan review's M2a): the assistant's and an MCP client's
/// deploy, with no window (<see cref="AssistWorkspace.Deploy"/>), asks
/// <see cref="BuildFreshness.WhyRebuild(Course, int, string, DateTime?)"/>
/// as the Deploy button does and as the mac's AssistSiteWork.deploy does: a
/// current build is deployed as it stands, with no build and no trail line;
/// anything changed builds once and leaves ONE "site built again before
/// deploying" line with its reason.
///
/// <para>In <see cref="SharedActivityState"/>: it redirects the
/// process-wide trail to read what was written.</para>
/// </summary>
[Collection(SharedActivityState.Name)]
public class WindowlessDeployReusesTheLastBuildTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-windowless-reuse").FullName;
    private readonly string _trail;
    private readonly FakeLauncher _launcher = new();

    public WindowlessDeployReusesTheLastBuildTests()
    {
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        string course = Path.Combine(_folder, "courses", "ICS3U");
        Directory.CreateDirectory(Path.Combine(course, "section1", "All Classes"));
        File.WriteAllText(Path.Combine(course, "course_config.json"),
            """{"course_code": "ICS3U", "course_name": "Computer Science", "deploy_target": "netlify", "num_sections": 1, "per_section_folders": ["All Classes"], "section_numbers": [1]}""");
        Directory.CreateDirectory(Path.Combine(course, ".netlify_sites"));
        File.WriteAllText(Path.Combine(course, ".netlify_sites", "section1.json"), """{"name": "ics3u-s1-2026-gordon"}""");
        File.WriteAllText(Path.Combine(course, "section1", "All Classes", "Day 1.md"), "---\npublish: true\n---\nBody.\n");
        _trail = Path.Combine(_folder + "-trail", "activity.txt");
        ActivityTrail.SetCustomLogPathForTesting(_trail);
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { Directory.Delete(BuildOutputLocation.BuildsRootFor(_folder), recursive: true); } catch { }
        try { Directory.Delete(_folder, recursive: true); } catch { }
        try { Directory.Delete(_folder + "-trail", recursive: true); } catch { }
    }

    private void BuildTheSite()
    {
        Thread.Sleep(FreshnessCases.PauseMilliseconds);
        string index = BuildOutputLocation.BuiltIndexFor(BuildOutputLocation.BuildsRootFor(_folder), "ICS3U", 1);
        Directory.CreateDirectory(Path.GetDirectoryName(index)!);
        File.WriteAllText(index, "<html>built</html>");
        Thread.Sleep(FreshnessCases.PauseMilliseconds);
    }

    private string[] TrailLines() => File.Exists(_trail)
        ? File.ReadAllLines(_trail).Where(l => l.Contains("before deploying it", StringComparison.Ordinal)).ToArray()
        : Array.Empty<string>();

    [Fact]
    public async Task ACurrentBuildIsDeployedAsItStandsAndAChangedCourseBuildsOnce()
    {
        BuildTheSite();
        var workspace = new AssistWorkspace(_folder, _launcher);

        var reused = await workspace.Deploy("ICS3U", 1);
        Assert.True(reused.Succeeded, reused.Message);
        Assert.Equal(new[] { "deploy" }, _launcher.Runs.Select(r => r.Launcher));
        Assert.Empty(TrailLines());

        _launcher.Runs.Clear();
        File.AppendAllText(Path.Combine(_folder, "courses", "ICS3U", "section1", "All Classes", "Day 1.md"), "\nedited\n");
        var built = await workspace.Deploy("ICS3U", 1);
        Assert.True(built.Succeeded, built.Message);
        Assert.Equal(new[] { "preview", "deploy" }, _launcher.Runs.Select(r => r.Launcher));
        Assert.EndsWith(BuiltBeforeDeployingTrailTests.ContractLine(BuildFreshness.ReasonPages).Replace("ICS4U/2", "ICS3U/1"),
            Assert.Single(TrailLines()));
    }

    [Fact]
    public async Task ABuildThatFailsWritesNoLine()
    {
        var workspace = new AssistWorkspace(_folder, _launcher);
        _launcher.FailOn = "preview";

        var result = await workspace.Deploy("ICS3U", 1);

        Assert.False(result.Succeeded);
        Assert.Equal(new[] { "preview" }, _launcher.Runs.Select(r => r.Launcher));
        Assert.Empty(TrailLines());
    }

    [Fact]
    public async Task ASectionNeverBuiltIsBuiltAndSaysSo()
    {
        var workspace = new AssistWorkspace(_folder, _launcher);

        var result = await workspace.Deploy("ICS3U", 1);

        Assert.True(result.Succeeded, result.Message);
        Assert.Equal(new[] { "preview", "deploy" }, _launcher.Runs.Select(r => r.Launcher));
        Assert.EndsWith(BuiltBeforeDeployingTrailTests.ContractLine(BuildFreshness.ReasonNeverBuilt).Replace("ICS4U/2", "ICS3U/1"),
            Assert.Single(TrailLines()));
    }
}

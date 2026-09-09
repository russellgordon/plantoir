using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The legacy Netlify marker, at the path THIS platform's <c>deploy.py</c>
/// actually reads.
///
/// <para><b>Its own class because it sets <c>PLANTOIR_BUILD_ROOT</c></b>, which
/// is process-wide: <c>BuildOutputLocation.BuildsRootFor</c> honours it, so a
/// test that sets it is invisible to every other class until one of them calls
/// the same function while it is set. Serialized in the
/// <c>ProcessEnvironment</c> collection for that reason.</para>
///
/// <para><b>What is being pinned, and why it is not obvious.</b>
/// <c>merged_output_root()</c> returns <c>PLANTOIR_BUILD_ROOT/&lt;CODE&gt;</c> —
/// with NO <c>.merged_output</c> level — whenever that variable is set, and
/// <c>deploy.ps1</c> sets it unconditionally in <c>Enter-NativeRuntime</c>. So
/// the legacy marker <c>deploy.py</c> reads here is
/// <c>&lt;build root&gt;\&lt;CODE&gt;\section&lt;N&gt;\.netlify_site.json</c>, and
/// releasing the MAC's literal <c>&lt;CODE&gt;/.merged_output/section&lt;N&gt;/…</c>
/// would release a path that has never held a marker under this layout — the
/// mac's own first-cut mistake, mirrored. The release would do nothing at all,
/// and the section would go on publishing over last year's site while being
/// told it had been cut loose.</para>
/// </summary>
[Collection(ProcessEnvironment.Name)]
public class RolloverLegacyMarkerInTheBuildRootTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-legacy").FullName;
    private readonly string _buildRoot = Directory.CreateTempSubdirectory("plantoir-builds").FullName;
    private readonly string? _before = Environment.GetEnvironmentVariable("PLANTOIR_BUILD_ROOT");
    private readonly FakeLauncher _launcher = new();

    public RolloverLegacyMarkerInTheBuildRootTests()
    {
        Environment.SetEnvironmentVariable("PLANTOIR_BUILD_ROOT", _buildRoot);

        string course = Path.Combine(_folder, "courses", "ICS3U");
        Directory.CreateDirectory(course);
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        File.WriteAllText(Path.Combine(course, "course_config.json"),
            """
            {
              "course_code": "ICS3U",
              "course_name": "A course",
              "deploy_target": "netlify",
              "num_sections": 1,
              "per_section_folders": ["All Classes"],
              "per_section_files": ["Key Links.md"],
              "section_numbers": [1]
            }
            """);
    }

    public void Dispose()
    {
        Environment.SetEnvironmentVariable("PLANTOIR_BUILD_ROOT", _before);
        try { Directory.Delete(_folder, recursive: true); } catch { }
        try { Directory.Delete(_buildRoot, recursive: true); } catch { }
        GC.SuppressFinalize(this);
    }

    [Fact]
    public void TheLegacyMarkerInTheBuildRootIsReleased()
    {
        string output = BuildOutputLocation.ForSection(
            BuildOutputLocation.BuildsRootFor(_folder), "ICS3U", 1);
        Directory.CreateDirectory(output);
        string marker = Path.Combine(output, ".netlify_site.json");
        File.WriteAllText(marker, "{\"site\":\"last-year\"}");

        var workspace = new AssistWorkspace(_folder, _launcher);
        var release = workspace.ReleaseSite(workspace.Course("ICS3U"), 1);

        Assert.False(File.Exists(marker),
            "This is the path deploy.py reads on Windows. Leaving it means the next publish " +
            "migrates it back and goes to last year's site.");
        string kept = Assert.Single(release.KeptFiles);
        Assert.Contains(".netlify_site.previous-", kept, StringComparison.Ordinal);
        Assert.True(release.ReleasedAnything);
        Assert.False(release.SomethingIsStillPinned);
    }

    /// <summary>
    /// The path is the one <c>deploy.py</c> computes, not the mac's spelling.
    /// </summary>
    /// <remarks>
    /// Asserted as a PATH rather than only through the release above, because
    /// this is the half that was got wrong on the mac and could be got wrong
    /// again here: a release that looks in <c>.merged_output</c> under a native
    /// build root finds nothing, reports "never published", and is green.
    /// </remarks>
    [Fact]
    public void TheMacsSpellingIsNotWhereThisPlatformKeepsIt()
    {
        string here = BuildOutputLocation.ForSection(
            BuildOutputLocation.BuildsRootFor(_folder), "ICS3U", 1);
        string macs = Path.Combine(_folder, "courses", "ICS3U", ".merged_output", "section1");

        Assert.StartsWith(_buildRoot, here, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(".merged_output", here, StringComparison.OrdinalIgnoreCase);
        Assert.NotEqual(macs, here, StringComparer.OrdinalIgnoreCase);
    }

    /// <summary>
    /// A folder with no legacy marker anywhere is not reported as pinned.
    /// </summary>
    /// <remarks>
    /// The overwhelmingly common case — the legacy path stopped being written
    /// long ago — and an absent file must be ordinary rather than a failure,
    /// or every rollover would tell a teacher something went wrong.
    /// </remarks>
    [Fact]
    public void NoLegacyMarkerAnywhereIsOrdinary()
    {
        var workspace = new AssistWorkspace(_folder, _launcher);
        var release = workspace.ReleaseSite(workspace.Course("ICS3U"), 1);

        Assert.False(release.ReleasedAnything);
        Assert.False(release.SomethingIsStillPinned);
    }
}

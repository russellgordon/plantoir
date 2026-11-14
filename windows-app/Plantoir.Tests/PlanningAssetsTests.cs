using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// <c>shared-rules.json</c> → <c>unitPlanning.tab.assetsMirror</c> (#801 item
/// 4): the planning folder's <c>assets</c> made the template's, never a
/// planning folder made, and never a mirror through a link (the mac's
/// <c>testTheRefreshLeavesALinkedPlanningFolderAlone</c>, rebuilt with
/// junctions, plus the deeper links .NET's walk would follow). The tab that
/// calls it is <c>PlanningTabView</c> (790b).
/// </summary>
public sealed class PlanningAssetsTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "plantoir-planning-assets-" + Guid.NewGuid().ToString("N"));

    public PlanningAssetsTests() => Directory.CreateDirectory(_root);

    public void Dispose() => ReferenceFixtures.Remove(_root);

    private static string TemplateAssets =>
        Path.Combine(ContractLoader.RepositoryRoot, "support", "agent_guidance", PlanningAssets.TemplateAssetsUnderGuidance);

    private static Dictionary<string, string> Files(string root) =>
        Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories).ToDictionary(
            f => Path.GetRelativePath(root, f),
            f => Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(f))),
            StringComparer.OrdinalIgnoreCase);

    /// <summary>
    /// The app reads the template's assets from its bundle's
    /// <c>Toolchain\support</c>, which <c>Plantoir.csproj</c> copies whole from
    /// the repository's <c>support</c>; the repository's copy has the 22 files.
    /// </summary>
    [Fact]
    public void TheBundledAssetsAreTheTemplates()
    {
        Assert.True(Files(TemplateAssets).Count >= 22, "the template's assets shrank");
        string csproj = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "Plantoir.csproj"));
        Assert.Contains(@"<Content Include=""..\..\support\**"" Link=""Toolchain\support\%(RecursiveDir)%(Filename)%(Extension)""", csproj);
        Assert.Equal(Path.Combine(@"C:\app\Toolchain", "support", "agent_guidance", "skills", "plantoir-unit-planning", "template", "assets"),
                     PlanningAssets.BundledTemplateAssets(@"C:\app\Toolchain"));
    }

    [Fact]
    public void TheRefreshMirrorsTheTemplateAndRemovesAStrayFile()
    {
        string planning = UnitPlans.PlanningFolder(Path.Combine(_root, "course"));
        string assets = Path.Combine(planning, PlanningAssets.FolderName);
        Directory.CreateDirectory(assets);
        File.WriteAllText(Path.Combine(assets, "plan.css"), "an old sheet");
        File.WriteAllText(Path.Combine(assets, "stray.css"), "not the app's");

        var outcome = PlanningAssets.Refresh(planning, TemplateAssets);
        Assert.NotNull(outcome);
        Assert.Equal(0, outcome!.Value.Failed);
        Assert.Equal(Files(TemplateAssets), Files(assets));

        var again = PlanningAssets.Refresh(planning, TemplateAssets);
        Assert.Equal(0, again!.Value.Changed);
    }

    [Fact]
    public void TheRefreshNeverMakesAPlanningFolder()
    {
        string planning = UnitPlans.PlanningFolder(Path.Combine(_root, "course"));
        Assert.Null(PlanningAssets.Refresh(planning, TemplateAssets));
        Assert.False(Directory.Exists(planning));
    }

    /// <summary>
    /// 790a review 2, M1: an <c>assets</c> file that is a HARD LINK to a
    /// teacher's file outside the course is replaced, never written through:
    /// the mirror deletes the name and writes a new file, so the file outside
    /// keeps its own words. (No privilege is needed for a hard link on one
    /// volume, so this is measured here, unlike a file symbolic link.)
    /// </summary>
    [Fact]
    public void AHardLinkedAssetIsReplacedNeverWrittenThrough()
    {
        string planning = UnitPlans.PlanningFolder(Path.Combine(_root, "course"));
        string assets = Path.Combine(planning, PlanningAssets.FolderName);
        Directory.CreateDirectory(assets);
        string templateFile = Directory.EnumerateFiles(TemplateAssets, "*.css").First();
        string inAssets = Path.Combine(assets, Path.GetFileName(templateFile));
        string teachers = Path.Combine(_root, "teachers-own.css");
        File.WriteAllText(teachers, "the teacher's own words");
        Assert.True(CreateHardLinkW(inAssets, teachers, nint.Zero), "could not make a hard link");

        var outcome = PlanningAssets.Refresh(planning, TemplateAssets);
        Assert.NotNull(outcome);
        Assert.Equal(0, outcome!.Value.Failed);
        Assert.Equal("the teacher's own words", File.ReadAllText(teachers));
        Assert.Equal(File.ReadAllBytes(templateFile), File.ReadAllBytes(inAssets));
        Assert.Equal(Files(TemplateAssets), Files(assets));
    }

    /// <summary>
    /// 790a review 2, L6: a DANGLING junction at <c>assets</c> (its target
    /// deleted) is refused by the link check like every other link shape, not
    /// left to whatever throws: nothing is counted as copied or failed, the
    /// junction is left as it was, and nothing is made where it pointed.
    /// </summary>
    [Fact]
    public void ADanglingJunctionAtAssetsIsRefusedAsALink()
    {
        string planning = UnitPlans.PlanningFolder(Path.Combine(_root, "course"));
        Directory.CreateDirectory(planning);
        string gone = Path.Combine(_root, "gone");
        Directory.CreateDirectory(gone);
        string assets = Path.Combine(planning, PlanningAssets.FolderName);
        ReferenceFixtures.Junction(assets, gone);
        Directory.Delete(gone);

        Assert.Null(PlanningAssets.Refresh(planning, TemplateAssets));
        Assert.Equal(PlanningAssets.Refusal.ALink, PlanningAssets.WhyNot(planning, TemplateAssets));
        Assert.NotNull(new DirectoryInfo(assets).LinkTarget);
        Assert.False(Directory.Exists(gone), "the mirror made the folder a dangling junction pointed at");
    }

    /// <summary>A planning folder with no <c>assets</c> yet is given one: the link check does not refuse a folder that is not there.</summary>
    [Fact]
    public void APlanningFolderWithNoAssetsYetIsGivenThem()
    {
        string planning = UnitPlans.PlanningFolder(Path.Combine(_root, "course"));
        Directory.CreateDirectory(planning);
        Assert.Null(PlanningAssets.WhyNot(planning, TemplateAssets));
        var outcome = PlanningAssets.Refresh(planning, TemplateAssets);
        Assert.Equal(0, outcome!.Value.Failed);
        Assert.Equal(Files(TemplateAssets), Files(Path.Combine(planning, PlanningAssets.FolderName)));
    }

    [System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    [return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.Bool)]
    private static extern bool CreateHardLinkW(string lpFileName, string lpExistingFileName, nint lpSecurityAttributes);

    /// <summary>
    /// A link anywhere on the way — the planning folder, <c>.internal</c>,
    /// <c>assets</c>, or a folder inside <c>assets</c> — leaves everything
    /// alone: a photo behind the link survives and nothing is written through it.
    /// </summary>
    [Theory]
    [InlineData("planning")]
    [InlineData(".internal")]
    [InlineData("assets")]
    [InlineData("assets/fonts")]
    public void TheRefreshLeavesALinkedFolderAlone(string linked)
    {
        string elsewhere = Path.Combine(_root, "elsewhere");
        Directory.CreateDirectory(elsewhere);
        string photo = Path.Combine(elsewhere, "photo.jpg");
        File.WriteAllText(photo, "a picture");
        string course = Path.Combine(_root, "course");
        string planning = UnitPlans.PlanningFolder(course);
        switch (linked)
        {
            case "planning":
                Directory.CreateDirectory(Path.Combine(course, ".internal"));
                ReferenceFixtures.Junction(planning, elsewhere);
                break;
            case ".internal":
                Directory.CreateDirectory(course);
                ReferenceFixtures.Junction(Path.Combine(course, ".internal"), elsewhere);
                Directory.CreateDirectory(Path.Combine(elsewhere, "planning"));
                break;
            case "assets":
                Directory.CreateDirectory(planning);
                ReferenceFixtures.Junction(Path.Combine(planning, PlanningAssets.FolderName), elsewhere);
                break;
            default:
                Directory.CreateDirectory(Path.Combine(planning, PlanningAssets.FolderName));
                ReferenceFixtures.Junction(Path.Combine(planning, PlanningAssets.FolderName, "fonts"), elsewhere);
                break;
        }

        Assert.Null(PlanningAssets.Refresh(planning, TemplateAssets));
        Assert.True(File.Exists(photo), "a file behind the link was removed");
        Assert.Equal(new[] { "photo.jpg" }, Directory.EnumerateFileSystemEntries(elsewhere, "*", SearchOption.AllDirectories)
            .Select(e => Path.GetRelativePath(elsewhere, e)).Where(e => e != "planning"));
    }
}

using System;
using System.IO;
using Plantoir.Core.Catalogs;
using Xunit;

namespace Plantoir.Tests;

public class SkeletonCatalogTests
{
    private static string SkeletonsRoot
    {
        get
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            for (int i = 0; i < 8 && dir is not null; i++, dir = dir.Parent)
            {
                string candidate = Path.Combine(dir.FullName, "support", "skeletons");
                if (Directory.Exists(candidate) && File.Exists(Path.Combine(candidate, "families.json")))
                    return candidate;
            }
            throw new DirectoryNotFoundException("Could not find support/skeletons directory.");
        }
    }

    private static string ExampleContentRoot
    {
        get
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            for (int i = 0; i < 8 && dir is not null; i++, dir = dir.Parent)
            {
                string candidate = Path.Combine(dir.FullName, "support", "example_content");
                if (Directory.Exists(candidate))
                    return candidate;
            }
            throw new DirectoryNotFoundException("Could not find support/example_content directory.");
        }
    }

    [Fact]
    public void FamilyNameForCodesResolvesCorrectly()
    {
        Assert.Equal("music", SkeletonCatalog.FamilyName(SkeletonsRoot, "AMU3M"));
        Assert.Equal("drama", SkeletonCatalog.FamilyName(SkeletonsRoot, "ADA2O"));
        Assert.Equal("biology", SkeletonCatalog.FamilyName(SkeletonsRoot, "SBI3U"));
        Assert.Equal("mathematics", SkeletonCatalog.FamilyName(SkeletonsRoot, "MCV4U"));
        Assert.Equal("hairstyling", SkeletonCatalog.FamilyName(SkeletonsRoot, "TXJ3E"));
        Assert.Equal("music", SkeletonCatalog.FamilyName(SkeletonsRoot, " amu3m "));
        Assert.Equal("general", SkeletonCatalog.FamilyName(SkeletonsRoot, "CODING"));
        Assert.Null(SkeletonCatalog.FamilyName(SkeletonsRoot, ""));
    }

    [Fact]
    public void FamilyManifestLoadsAndParsesCorrectly()
    {
        var music = SkeletonCatalog.GetFamily(SkeletonsRoot, "AMU3M");
        Assert.NotNull(music);
        Assert.Equal("music", music.Name);
        Assert.Equal("Music", music.Label);
        Assert.Contains("Repertoire", music.SharedFolders);
        Assert.Contains("Listening", music.SharedFolders);

        var chemistry = SkeletonCatalog.GetFamily(SkeletonsRoot, "SCH3U");
        Assert.NotNull(chemistry);
        Assert.Equal("chemistry", chemistry.Name);
        Assert.Contains("Investigations", chemistry.SharedFolders);
        Assert.DoesNotContain("Repertoire", chemistry.SharedFolders);
    }

    [Fact]
    public void HasSkeletonReturnsFalseWhenExampleContentExists()
    {
        Assert.False(SkeletonCatalog.HasSkeleton(ExampleContentRoot, SkeletonsRoot, "ADA1O"));
        Assert.True(SkeletonCatalog.HasSkeleton(ExampleContentRoot, SkeletonsRoot, "ADA2O"));
    }

    [Fact]
    public void EveryFamilyNameEnumeratesAllFamilies()
    {
        var names = SkeletonCatalog.EveryFamilyName(SkeletonsRoot);
        Assert.True(names.Count >= 50, $"Expected >= 50 families, found {names.Count}");
        Assert.Contains("music", names);
        Assert.Contains("drama", names);
        Assert.Contains("chemistry", names);
        Assert.Contains("mathematics", names);
        Assert.Contains("general", names);
    }

    /// <summary>
    /// A family's marks pool travels with it, so the wizard can seed
    /// <c>graded_folders</c> the way the mac does. Fifty manifests declare
    /// one; the rule for the rest is the build's own: every folder whose name
    /// contains "task".
    /// </summary>
    [Fact]
    public void AdoptedGradedFoldersComeFromTheManifestOrFallBackToTaskFolders()
    {
        var declared = SkeletonCatalog.GetFamilyByName(SkeletonsRoot, "science");
        Assert.NotNull(declared);
        Assert.NotEmpty(declared!.GradedFolders);
        Assert.Equal(declared.GradedFolders, SkeletonCatalog.AdoptedGradedFolders(declared));

        var undeclared = new SkeletonCatalog.Family(
            "made-up", "Made Up",
            SharedFolders: new[] { "Notes", "Tasks", "Thinking Tasks" },
            SharedFiles: Array.Empty<string>(),
            PerSectionFolders: new[] { "All Classes" },
            PerSectionFiles: Array.Empty<string>(),
            Hidden: Array.Empty<string>(),
            Expandable: Array.Empty<string>(),
            GradedFolders: Array.Empty<string>());
        Assert.Equal(new[] { "Tasks", "Thinking Tasks" }, SkeletonCatalog.AdoptedGradedFolders(undeclared));
    }

    /// <summary>
    /// The wizard adopts a skeleton only over a structure it is allowed to
    /// replace — the factory defaults, the LCS defaults, or another
    /// skeleton's — and never over a list the teacher has edited. The same
    /// guard, asked the other way, is what lets the toggle put the defaults
    /// back without discarding an edit.
    /// </summary>
    [Fact]
    public void AStructureTheTeacherEditedIsNeverReplacedInEitherDirection()
    {
        var defaults = new[] { "Notes", "Tasks" };
        var lcs = new[] { "Notes", "Tasks", "College Board Curriculum" };
        var theirs = new[] { "My Folder" };

        Assert.NotNull(SkeletonCatalog.StructureToAdopt(ExampleContentRoot, SkeletonsRoot, "SNC4M", defaults, defaults, lcs));
        Assert.Null(SkeletonCatalog.StructureToAdopt(ExampleContentRoot, SkeletonsRoot, "SNC4M", theirs, defaults, lcs));
        Assert.True(SkeletonCatalog.IsOffered(SkeletonsRoot, lcs, defaults, lcs));
        Assert.False(SkeletonCatalog.IsOffered(SkeletonsRoot, theirs, defaults, lcs));
    }
}

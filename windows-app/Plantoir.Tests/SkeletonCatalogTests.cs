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
}

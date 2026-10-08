using System;
using System.IO;
using System.Linq;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// <c>Plantoir.exe --stage-scene</c> (#380): the pictures on plantoir.app are
/// staged in real windows. What a launch asks for is read here; a teacher's
/// launch asks for nothing, and a request that cannot be carried out says why
/// instead of opening whatever it can.
/// </summary>
public class MarketingSceneTests
{
    [Fact]
    public void ATeachersLaunchIsNotAScene()
    {
        Assert.Null(MarketingScene.Parse(new[] { "Plantoir.exe" }));
        Assert.Null(MarketingScene.Parse(new[] { "Plantoir.exe", "--state-dir", @"C:\x" }));
    }

    [Fact]
    public void ASceneIsReadWithItsFolderThemeAndReadyFile()
    {
        var scene = MarketingScene.Parse(new[]
        {
            "Plantoir.exe", "--state-dir", @"C:\t", "--stage-scene", "courses", "--theme", "dark",
            "--folder", @"C:\Users\x\Desktop\Teaching\School Web Space", "--ready-file", @"C:\t\ready.txt",
        })!;
        Assert.Equal("courses", scene.Scene);
        Assert.True(scene.Dark);
        Assert.Equal(@"C:\Users\x\Desktop\Teaching\School Web Space", scene.Folder);
        Assert.Equal(@"C:\t\ready.txt", scene.ReadyFile);
        Assert.Empty(scene.Courses);
        Assert.Null(scene.ReferenceCopy);
    }

    [Fact]
    public void AnythingButDarkIsLight()
    {
        Assert.False(MarketingScene.Parse(new[] { "--stage-scene", "club", "--folder", "f" })!.Dark);
        Assert.False(MarketingScene.Parse(new[] { "--stage-scene", "club", "--folder", "f", "--theme", "light" })!.Dark);
    }

    [Fact]
    public void AnUnknownSceneOrAMissingFolderIsRefusedWithTheReason()
    {
        var unknown = Assert.Throws<ArgumentException>(() => MarketingScene.Parse(new[] { "--stage-scene", "nope", "--folder", "f" }));
        Assert.Contains("nope", unknown.Message);
        var noFolder = Assert.Throws<ArgumentException>(() => MarketingScene.Parse(new[] { "--stage-scene", "courses" }));
        Assert.Contains("--folder", noFolder.Message);
    }

    [Fact]
    public void ProvisioningReadsItsCoursesAndReferenceCopy()
    {
        var scene = MarketingScene.Parse(new[]
        {
            "--stage-scene", "provision", "--folder", "f", "--courses", "ICS3U:1, 2;ics4u:1", "--reference-copy", "ICS3U:2025",
        })!;
        Assert.Equal(new[] { ("ICS3U", "1, 2"), ("ICS4U", "1") }, scene.Courses.ToArray());
        Assert.Equal(("ICS3U", 2025), scene.ReferenceCopy);
        Assert.Equal("ICS3U-2025", MarketingScene.ReferenceFolderName("ICS3U", 2025));
    }

    [Theory]
    [InlineData("ICS3U")]
    [InlineData("ICS3U:")]
    [InlineData(":1")]
    public void ACourseWithoutSectionsIsRefused(string text) =>
        Assert.Throws<ArgumentException>(() => MarketingScene.CourseList(text));

    [Theory]
    [InlineData("ICS3U")]
    [InlineData("ICS3U:last")]
    [InlineData(":2025")]
    public void AReferenceCopyWithoutAYearIsRefused(string text) =>
        Assert.Throws<ArgumentException>(() => MarketingScene.ReferenceCopyOf(text));

    /// <summary>
    /// Every scene the capture script asks for is one the app stages — read
    /// from the script itself, so a scene added there without the app knowing
    /// it fails here rather than on a desktop forty minutes into a run.
    /// </summary>
    [Fact]
    public void EverySceneTheCaptureScriptAsksForIsOneTheAppStages()
    {
        string root = AppContext.BaseDirectory;
        while (!File.Exists(Path.Combine(root, "website", "shots", "app_scenes_windows.py")))
            root = Path.GetDirectoryName(root) ?? throw new InvalidOperationException("repository not found");
        string script = File.ReadAllText(Path.Combine(root, "website", "shots", "app_scenes_windows.py"));
        var asked = System.Text.RegularExpressions.Regex.Matches(script, @"\(""([a-z-]+)"", (?:DEMO|MARKETING)\)")
            .Select(m => m.Groups[1].Value).ToList();
        Assert.NotEmpty(asked);
        foreach (string scene in asked) Assert.Contains(scene, MarketingScene.Scenes);
        Assert.Contains("provision", MarketingScene.Scenes);
        Assert.Contains("hero", MarketingScene.Scenes);
    }
}

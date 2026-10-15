using System.Text.RegularExpressions;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #491 (the mac's #457 item 4): the Cloudflare Account ID is the teacher's,
/// edited only in File ▸ Settings ▸ Deploying, shown read-only by a course and
/// the wizard. What is pinned here: the pane's trail lines (the mac's three,
/// never the ID), what it calls a problem, the refusals that send the teacher
/// there, and — read from the source — that nothing else in the app writes
/// the ID. Driven through the window by <c>SettingsUiTests</c>.
/// </summary>
[Collection(SharedActivityState.Name)]
public class CloudflareAccountInSettingsTests
{
    private const string AValidId = "0123456789abcdef0123456789abcdef";

    // ---- The trail ------------------------------------------------------------

    [Fact]
    public void TheThreeLines_AreTheMacs()
    {
        Assert.Equal("Settings ▸ Deploying — the Cloudflare Account ID was cleared",
                     DeployingSettings.TrailLine(AValidId, ""));
        Assert.Equal("Settings ▸ Deploying — the Cloudflare Account ID was changed, and is not a valid ID yet",
                     DeployingSettings.TrailLine("", "abc"));
        Assert.Equal("Settings ▸ Deploying — the Cloudflare Account ID was changed",
                     DeployingSettings.TrailLine("", AValidId));
    }

    [Theory]
    [InlineData("", "")]
    [InlineData(AValidId, AValidId)]
    [InlineData(AValidId, "  " + AValidId + " ")]
    [InlineData("   ", "")]
    public void NothingChanged_WritesNoLine(string before, string after) =>
        Assert.Null(DeployingSettings.TrailLine(before, after));

    [Fact]
    public void NoLine_EverCarriesTheId()
    {
        foreach (string? line in new[]
                 {
                     DeployingSettings.TrailLine("", AValidId),
                     DeployingSettings.TrailLine(AValidId, "fedcba9876543210fedcba9876543210"),
                     DeployingSettings.TrailLine("", "abc123"),
                 })
        {
            Assert.NotNull(line);
            Assert.DoesNotContain(AValidId, line);
            Assert.DoesNotContain("fedcba", line);
            Assert.DoesNotContain("abc123", line);
        }
    }

    [Fact]
    public void TheEvent_IsTheContractsName()
    {
        Assert.Equal("Cloudflare account ID changed in Settings",
                     ActivityTrail.KeyFor(ActivityTrail.Event.CloudflareAccountIdChangedInSettings));
        Assert.Equal("opened Plantoir Help", ActivityTrail.KeyFor(ActivityTrail.Event.PlantoirHelpOpened));
    }

    // ---- The pane's problem line ----------------------------------------------

    [Fact]
    public void AnEmptyId_IsNoProblemInSettings_ButAShortOneIs()
    {
        Assert.Null(DeployingSettings.Problem(""));
        Assert.Null(DeployingSettings.Problem("   "));
        Assert.Null(DeployingSettings.Problem(AValidId));
        Assert.Equal(CourseConfiguration.CloudflareAccountProblem("abc"), DeployingSettings.Problem("abc"));
        Assert.NotNull(DeployingSettings.Problem("abc"));
    }

    [Fact]
    public void TheReadOnlyDisplay_ShowsNotSetYetInPlaceOfNothing()
    {
        Assert.Equal("Not set yet", DeployingSettings.Shown(""));
        Assert.Equal("Not set yet", DeployingSettings.Shown("  "));
        Assert.Equal(AValidId, DeployingSettings.Shown(" " + AValidId));
        Assert.Equal("Kept in File ▸ Settings ▸ Deploying, for every course that deploys to Cloudflare Pages.",
                     DeployingSettings.KeptIn);
    }

    // ---- The one writer -------------------------------------------------------

    [Fact]
    public void ChangingTheId_SavesItAndSaysSo_OnlyWhenItChanged()
    {
        string file = Path.Combine(Directory.CreateTempSubdirectory("plantoir-account").FullName, "settings.json");
        var settings = new AppSettings();
        int raised = 0;
        void Count() => raised++;
        AppSettings.CloudflareAccountIdChanged += Count;
        string? before = AppSettings.PathOverride;
        try
        {
            AppSettings.PathOverride = file;
            settings.ChangeCloudflareAccountId(AValidId);
            settings.ChangeCloudflareAccountId(AValidId);
            Assert.Equal(1, raised);
            Assert.Equal(AValidId, AppSettings.Load(file).CloudflareAccountId);
        }
        finally
        {
            AppSettings.PathOverride = before;
            AppSettings.CloudflareAccountIdChanged -= Count;
        }
    }

    /// <summary>
    /// The ID is written in ONE place: <c>Views/DeployingSettingsPane.cs</c>. A
    /// course's settings and the wizard each wrote it until #491 — typed in one
    /// course, it changed silently for every other. Read from the source, as
    /// <c>WindowThemeSourceTests</c> does, because the views live in the WinUI
    /// project this suite cannot load.
    /// </summary>
    [Fact]
    public void OnlyTheDeployingPane_WritesTheId()
    {
        string app = Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir");
        var writes = new Regex(@"\.CloudflareAccountId\s*=(?!=)|ChangeCloudflareAccountId\(");
        var writers = Directory.EnumerateFiles(app, "*.cs", SearchOption.AllDirectories)
            .Where(file => !file.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")
                           && !file.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}"))
            .Where(file => writes.IsMatch(File.ReadAllText(file)))
            .Select(file => Path.GetRelativePath(app, file).Replace('\\', '/'))
            .ToList();
        Assert.Equal(new[] { "Views/DeployingSettingsPane.cs" }, writers);
    }

    // ---- The refusals that send the teacher there -------------------------------

    [Fact]
    public void TheInAppDeploysRefusal_NamesSettings()
    {
        var cloudflare = new CourseConfiguration.DeployDestination("cloudflare_pages", "");
        Assert.Equal("Paste your Cloudflare Account ID. Add it in File ▸ Settings ▸ Deploying, then deploy again.",
                     MultiDestinationDeployRunner.RefusalReason(new[] { cloudflare }, ""));
    }

    [Fact]
    public void NoRefusalNamesACoursesSettingsForTheId()
    {
        foreach (string text in new[] { DeployingSettings.AddItThenDeployAgain, DeployingSettings.AddItThenScheduleAgain })
        {
            Assert.Contains("File ▸ Settings ▸ Deploying", text);
            Assert.DoesNotContain("course", text);
        }
    }
}

using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Tools;
using Plantoir.Core.Models;

namespace Plantoir.UiTests;

/// <summary>
/// #491 through the real windows: File ▸ Settings… is ONE window of its own,
/// its Deploying section is the only place the Cloudflare Account ID is
/// typed, and a course and the new-course wizard show it read-only — live, and
/// with Open Settings… raising the window while the wizard stays open (the
/// reason Settings is a window and not a dialog).
/// </summary>
[Collection("drives the real app")]
public class SettingsUiTests
{
    private const string Code = "UICFLARE";
    private const string AnId = "0123456789abcdef0123456789abcdef";

    private static void ACloudflareCourse(string coursesDir) =>
        EndToEnd.WriteCourse(coursesDir, Code, "Deploys to Cloudflare", new[] { "Concepts" },
                             config => config["deploy_target"] = "cloudflare_pages");

    /// <summary>Choose a section of the Settings window, by its navigation item, and wait until it says so.</summary>
    private static void ChooseSection(AutomationElement settings, string itemId)
    {
        var item = Retry.WhileNull(() => settings.FindFirstDescendant(cf => cf.ByAutomationId(itemId)),
                                   TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result
                   ?? throw new Xunit.Sdk.XunitException($"the Settings window has no {itemId}");
        if (item.Patterns.SelectionItem.IsSupported) item.Patterns.SelectionItem.Pattern.Select();
        else item.Patterns.Invoke.Pattern.Invoke();
        Assert.True(Retry.WhileFalse(() => item.Patterns.SelectionItem.Pattern.IsSelected.Value,
                                     TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result,
                    $"{itemId} never became the chosen section");
    }

    private static AutomationElement Field(AutomationElement settings) =>
        Retry.WhileNull(() => settings.FindFirstDescendant(cf => cf.ByAutomationId("cloudflareAccountField")),
                        TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result
        ?? throw new Xunit.Sdk.XunitException("the Deploying section has no Account ID field");

    private static string SettingsFile(DrivenApp app)
    {
        string path = Path.Combine(app.StateDirectory, "settings.json");
        try
        {
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            return new StreamReader(stream).ReadToEnd();
        }
        catch (IOException) { return ""; }
    }

    /// <summary>
    /// Typed in Settings ▸ Deploying: saved to this run's settings at once, one
    /// trail line when the teacher moves on — the mac's line, never the ID — and
    /// a course that deploys to Cloudflare shows the ID it now has.
    /// </summary>
    [UiFact]
    public void TheAccountIdIsEditedInSettingsAndShownInTheCourse()
    {
        using var app = new DrivenApp(ACloudflareCourse);

        EndToEnd.PressMenuBarItem(app, "File", "fileSettings");
        var settings = app.FindTopLevel("settingsWindow", "the Settings window");
        Assert.Equal("Settings", settings.Name);
        ChooseSection(settings, "settingsDeploying");

        Field(settings).Patterns.Value.Pattern.SetValue(AnId);
        Assert.True(Retry.WhileFalse(() => SettingsFile(app).Contains(AnId),
                                     TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result,
                    "the Account ID typed in Settings never reached this run's settings.json");

        // Moving to another section is leaving the field: the line is written then.
        ChooseSection(settings, "settingsAssistant");
        const string line = "Settings ▸ Deploying — the Cloudflare Account ID was changed";
        Assert.True(Retry.WhileFalse(() => MenuBar.Trail(app).Split('\n').Any(entry => entry.TrimEnd('\r').EndsWith(line)),
                                     TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result,
                    $"the trail never said \"{line}\"");
        Assert.DoesNotContain(AnId, MenuBar.Trail(app));

        settings.AsWindow().Close();
        Assert.True(Retry.WhileFalse(() =>
        {
            try { return app.Desktop.FindFirstDescendant(cf => cf.ByAutomationId("settingsWindow")) is null; }
            catch { return false; }
        }, TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(250)).Result, "the Settings window would not close");

        app.SelectCourse(Code);
        var shown = app.Find("cloudflareAccountValue", "the course's read-only Account ID");
        Assert.Equal(AnId, shown.Name);
        app.AssertAbsent("cloudflareAccountField", "a field for the Account ID in the course's settings");
    }

    /// <summary>
    /// The wizard with no Account ID: Cloudflare Pages chosen, Create refused
    /// with the contract's sentence beside Open Settings…; that button raises
    /// Settings on Deploying WHILE the wizard stays open, and a valid ID typed
    /// there enables Create without the wizard closing.
    /// </summary>
    [UiFact]
    public void TheWizardWaitsForTheIdTypedInSettings()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        NewCourseWizardUiTests.OpenWizard(app);
        NewCourseWizardUiTests.PutCodeIn(app, "MFM2P");
        app.Find("deployTargetPicker", "Deploy to").AsComboBox().Select(1);   // Cloudflare Pages

        var create = app.Find("PrimaryButton", "the wizard's Create button");
        string noId = CourseConfiguration.CloudflareAccountProblem("")!;
        Assert.True(Retry.WhileFalse(() => app.FindOrNull("cloudflareAccountProblem", TimeSpan.FromSeconds(1))?.Name == noId,
                                     TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result,
                    $"the wizard never said \"{noId}\"");
        Assert.False(create.IsEnabled, "Create was offered with no Account ID");
        Assert.Equal(DeployingSettings.ShownWhenEmpty, app.Find("cloudflareAccountValue", "the wizard's Account ID").Name);

        app.Find("cloudflareAccountOpenSettings", "Open Settings…").AsButton().Invoke();
        var settings = app.FindTopLevel("settingsWindow", "the Settings window");
        var deploying = settings.FindFirstDescendant(cf => cf.ByAutomationId("settingsDeploying"))!;
        Assert.True(Retry.WhileFalse(() => deploying.Patterns.SelectionItem.Pattern.IsSelected.Value,
                                     TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result,
                    "Open Settings… did not open on Deploying");
        Assert.NotNull(app.FindOrNull("newCourseDialog"));

        Field(settings).Patterns.Value.Pattern.SetValue(AnId);
        Assert.True(Retry.WhileFalse(() => create.IsEnabled, TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result,
                    "a valid ID typed in Settings never enabled Create");
        Assert.Equal(AnId, app.Find("cloudflareAccountValue", "the wizard's Account ID").Name);
        Assert.NotNull(app.FindOrNull("newCourseDialog"));

        settings.AsWindow().Close();
        MenuBar.CloseDialog(app);   // the wizard's Cancel: nothing is created
        Thread.Sleep(1000);
    }
}

/// <summary>
/// Help ▸ Plantoir Help (#491): the support page, in the browser — which a
/// redirected run records in <c>links-opened.txt</c> instead of opening — and
/// the trail line.
/// </summary>
[Collection("drives the real app")]
public class PlantoirHelpUiTests
{
    [UiFact]
    public void PlantoirHelpOpensTheSupportPage()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);

        EndToEnd.PressMenuBarItem(app, "Help", "helpPlantoirHelp");

        string opened = Path.Combine(app.StateDirectory, "links-opened.txt");
        Assert.True(Retry.WhileFalse(() => File.Exists(opened) && File.ReadAllText(opened).Contains(PlantoirHelp.SupportPage),
                                     TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result,
                    "Plantoir Help opened no page (links-opened.txt never named the support page)");
        Assert.True(Retry.WhileFalse(() => MenuBar.Trail(app).Contains(PlantoirHelp.TrailLine),
                                     TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result,
                    $"the trail never said \"{PlantoirHelp.TrailLine}\"");
    }
}

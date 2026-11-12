using System.Text.Json.Nodes;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Tools;
using Plantoir.Core.Models;

namespace Plantoir.UiTests;

/// <summary>
/// The destination picker, by destination rather than by position: the order
/// is the contract's (<c>publishingDestinations.pickerOrder</c>, #739), so a
/// test that selected "index 1" meant Cloudflare before #739 and Netlify after.
/// </summary>
internal static class DeployPicker
{
    private static int IndexOf(string type)
    {
        int index = PublishingDestinations.PickerOrder.ToList().IndexOf(type);
        if (index < 0) throw new Xunit.Sdk.XunitException($"the picker offers no {type}");
        return index;
    }

    public static void Choose(DrivenApp app, string type) =>
        app.Find("deployTargetPicker", "Deploy to").AsComboBox().Select(IndexOf(type));

    public static void AssertChosen(DrivenApp app, string type) =>
        Assert.True(Retry.WhileFalse(() => app.Find("deployTargetPicker", "Deploy to").AsComboBox().SelectedItem?.Name
                                           == app.Find("deployTargetPicker", "Deploy to").AsComboBox().Items[IndexOf(type)].Name,
                                     TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200)).Result,
                    $"the picker did not have {type} chosen");
}

/// <summary>
/// #739 (the mac's #668) through the real window: what a teacher is told while
/// choosing where a course deploys, and the first deploy's refusal over a
/// missing Account ID — Open Settings… beside OK, and the line on the trail.
/// Every sentence is read from <c>contracts/app-rules.json</c> →
/// <c>publishingDestinations</c>; the rules behind them are run case by case in
/// <c>PublishingDestinationsContractTests</c>, so this proves only what a unit
/// test cannot see: that the words are RENDERED where the teacher reads them,
/// and that the buttons are there and go where they say.
/// </summary>
/// <remarks>
/// Nothing here deploys or schedules anything: the refusal happens before any
/// launcher is started (that is the point of it), and Schedule a deploy is
/// cancelled. This run's settings hold no Account ID (<c>--state-dir</c>).
/// </remarks>
[Collection("drives the real app")]
public class PublishingDestinationsUiTests
{
    private const string CloudflareCode = "UICFDEF";
    private const string NoFolderCode = "UIFOLDR";
    private const string OldCode = "UIOLDNL";

    private static JsonNode Block => EndToEnd.Contract("app-rules.json")["publishingDestinations"]!;
    private static string Sentence(string key) => Block["sentences"]![key]!.ToString();

    private static void ThreeCourses(string coursesDir)
    {
        EndToEnd.WriteCourse(coursesDir, CloudflareCode, "Deploys to Cloudflare", new[] { "Concepts" },
                             config => config["deploy_target"] = "cloudflare_pages");
        // A folder with no folder chosen, then Cloudflare: refused for the folder first.
        EndToEnd.WriteCourse(coursesDir, NoFolderCode, "A folder not chosen", new[] { "Concepts" }, config =>
        {
            config["deploy_target"] = "local_folder";
            config["additional_deploy_targets"] = new JsonArray(new JsonObject { ["type"] = "cloudflare_pages" });
        });
        // Made before #668, or by setup.ps1 long ago: no deploy_target at all.
        EndToEnd.WriteCourse(coursesDir, OldCode, "Older than the other destinations", new[] { "Concepts" });
    }

    /// <summary>The dialog's text, button by button, and the dialog itself.</summary>
    private static (AutomationElement Dialog, string Said) RefusalAfterDeploy(DrivenApp app, string code)
    {
        app.SelectSection(code, 1);
        app.Find("deployButton", "the Deploy button").AsButton().Invoke();
        var dialog = MenuBar.Dialog(app, "Deploy");
        return (dialog, string.Join(" | ", DrivenApp.TextsUnder(dialog)));
    }

    /// <summary>
    /// <c>deployWithoutAnAccountID.cases[0]</c>: a course on the new-course
    /// default with no Account ID is refused at Deploy, the refusal offers
    /// Open Settings… beside OK, that button opens Settings on Deploying, and
    /// the trail says so by kind — the case's own line, under the course and
    /// section.
    /// </summary>
    [UiFact]
    public void TheDeployRefusalForAMissingIdOffersOpenSettingsAndIsOnTheTrail()
    {
        var c = Block["deployWithoutAnAccountID"]!["cases"]!.AsArray()
            .Single(item => item!["accountID"]!.ToString() == ""
                            && item["destinations"]!.AsArray().Select(d => d!.ToString()).SequenceEqual(new[] { "cloudflare_pages" }))!;
        Assert.True(c["expectOpenSettings"]!.GetValue<bool>(), "the case this test reads no longer offers Open Settings…");

        using var app = new DrivenApp(ThreeCourses);
        var (dialog, said) = RefusalAfterDeploy(app, CloudflareCode);
        Assert.Contains(c["expectRefusalStartsWith"]!.ToString(), said);

        var openSettings = dialog.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"))
                           ?? throw new Xunit.Sdk.XunitException($"the refusal offered no Open Settings…; it said {said}");
        Assert.Equal("Open Settings…", openSettings.Name);
        Assert.Equal("OK", dialog.FindFirstDescendant(cf => cf.ByAutomationId("CloseButton"))!.Name);

        string line = $"{CloudflareCode}/1 · {c["expectTrailLine"]}";
        Assert.True(Retry.WhileFalse(() => MenuBar.Trail(app).Contains(line), TimeSpan.FromSeconds(5)).Result,
                    $"the trail never said \"{line}\"");

        openSettings.AsButton().Invoke();
        var settings = app.FindTopLevel("settingsWindow", "the Settings window");
        var deploying = settings.FindFirstDescendant(cf => cf.ByAutomationId("settingsDeploying"))!;
        Assert.True(Retry.WhileFalse(() => deploying.Patterns.SelectionItem.Pattern.IsSelected.Value,
                                     TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result,
                    "Open Settings… did not open on Deploying");
        Assert.True(Retry.WhileFalse(() => app.OpenDialog() is null, TimeSpan.FromSeconds(10)).Result,
                    "the refusal stayed up after Open Settings…");
        settings.AsWindow().Close();
        Thread.Sleep(500);
    }

    /// <summary>
    /// <c>deployWithoutAnAccountID</c>'s folder case: refused for the folder
    /// first, which is put right in the course's own settings — so no Open
    /// Settings…, and no line for this event.
    /// </summary>
    [UiFact]
    public void AFolderRefusedFirstOffersNoOpenSettingsAndNoLine()
    {
        using var app = new DrivenApp(ThreeCourses);
        var (dialog, said) = RefusalAfterDeploy(app, NoFolderCode);
        string folderProblem = CourseConfiguration.DeployFolderProblem("")!;
        Assert.Contains(folderProblem, said);
        Assert.Null(dialog.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton")));
        MenuBar.CloseDialog(app);
        Assert.DoesNotContain("deploy refused: ", MenuBar.Trail(app));
    }

    /// <summary>
    /// The sentences where a teacher reads them: the new-course dialog's
    /// caption over Deploying and the Cloudflare caption on the default; Netlify
    /// chosen shows <c>netlifyNote</c> and no Cloudflare caption; and Netlify as
    /// an additional destination beside Cloudflare shows the note under its
    /// switch (<c>netlifyNoteCases</c>, "Netlify switched on as an additional
    /// destination"). The wizard is cancelled; nothing is created.
    /// </summary>
    [UiFact]
    public void TheNewCourseDialogSaysWhatTheContractSaysWhereItSaysIt()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        NewCourseWizardUiTests.OpenWizard(app);
        NewCourseWizardUiTests.PutCodeIn(app, "MFM2P");

        Assert.Equal(Sentence("wizardCaption"), app.Find("wizardDeployingCaption", "the caption over Deploying").Name);
        DeployPicker.AssertChosen(app, Block["newCourseDefault"]!.ToString());
        Assert.Equal(Sentence("cloudflareCaption"), app.Find("cloudflareCaption", "the Cloudflare caption").Name);
        app.AssertAbsent("netlifyNote", "Netlify's note with Cloudflare chosen");

        // Netlify as an additional destination: its note, under its switch.
        var netlifySwitch = app.Find("additionalDeployTarget-netlify", "Also deploy to Netlify").AsToggleButton();
        netlifySwitch.Toggle();
        Assert.Equal(Sentence("netlifyNote"), app.Find("additionalNetlifyNote", "Netlify's note under its switch").Name);
        netlifySwitch.Toggle();
        app.AssertAbsent("additionalNetlifyNote", "Netlify's note after its switch was turned off");

        DeployPicker.Choose(app, "netlify");
        Assert.Equal(Sentence("netlifyNote"), app.Find("netlifyNote", "Netlify's note").Name);
        app.AssertAbsent("cloudflareCaption", "the Cloudflare caption with Netlify chosen");

        MenuBar.CloseDialog(app);   // Cancel: nothing is created
        Thread.Sleep(1000);
    }

    /// <summary>
    /// A course whose file names no destination deploys to Netlify, and its
    /// Course Settings says so with Netlify's note (<c>netlifyNoteCases</c>, "No
    /// destination saved at all") — and its Schedule a deploy carries
    /// <c>netlifyScheduleNote</c>, which a Cloudflare course's does not. Both
    /// sheets are cancelled; nothing is scheduled.
    /// </summary>
    [UiFact]
    public void ACourseWithNoDestinationSavedGetsNetlifysNoteInSettingsAndScheduling()
    {
        using var app = new DrivenApp(ThreeCourses);
        app.SelectCourse(OldCode);
        DeployPicker.AssertChosen(app, Block["whenTheKeyIsAbsent"]!.ToString());
        Assert.Equal(Sentence("netlifyNote"), app.Find("netlifyNote", "Netlify's note in Course Settings").Name);

        app.SelectSection(OldCode, 1);
        EndToEnd.PressMenuBarItem(app, "Section", "sectionScheduleDeploy");
        var schedule = MenuBar.Dialog(app, "Section > Schedule Deploy…");
        Assert.Contains(Sentence("netlifyScheduleNote"), DrivenApp.TextsUnder(schedule));
        MenuBar.CloseDialog(app);

        app.SelectSection(CloudflareCode, 1);
        EndToEnd.PressMenuBarItem(app, "Section", "sectionScheduleDeploy");
        schedule = MenuBar.Dialog(app, "Section > Schedule Deploy… on a Cloudflare course");
        Assert.DoesNotContain(Sentence("netlifyScheduleNote"), DrivenApp.TextsUnder(schedule));
        MenuBar.CloseDialog(app);
    }
}

using System.Text.Json.Nodes;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// #1009 (the mac's #988): the two stop questions, their Don't ask again
/// boxes and Settings ▸ Deploying ▸ Stopping, against
/// <c>contracts/shared-rules.json</c> → <c>stopQuestions</c>: every word,
/// every case played through <see cref="StopQuestionAsking"/>, the trail line
/// <c>activityTrail.mustRecord</c> shows, and by source scan that the panel's
/// key is a <c>KeyboardAccelerator</c> on the visible Cancel and that the
/// question says the contract's words with Stop Deploy as its default.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class StopQuestionsContractTests : IDisposable
{
    private static JsonNode Contract => ContractLoader.LoadJson("shared-rules.json")["stopQuestions"]!;

    private static string AppSource(params string[] parts) =>
        File.ReadAllText(Path.Combine(new[] { ContractLoader.RepositoryRoot, "windows-app", "Plantoir" }.Concat(parts).ToArray()))
            .Replace("\r\n", "\n");

    private readonly string _folder = Path.Combine(Path.GetTempPath(), "plantoir-1009-" + Guid.NewGuid().ToString("N")[..8]);
    private readonly string? _settingsPathBefore = AppSettings.PathOverride;

    public StopQuestionsContractTests()
    {
        Directory.CreateDirectory(_folder);
        AppSettings.PathOverride = Path.Combine(_folder, "settings.json");
    }

    public void Dispose()
    {
        AppSettings.PathOverride = _settingsPathBefore;
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    // ---- the words ---------------------------------------------------------------

    [Fact]
    public void EveryWordIsTheContracts()
    {
        var deploy = Contract["questions"]!["deploy"]!;
        Assert.Equal(deploy["title"]!.ToString(), StopQuestionWording.Title(StopQuestion.Deploy));
        Assert.Equal(deploy["message"]!.ToString(), StopQuestionWording.Message(StopQuestion.Deploy));
        Assert.Equal(deploy["stopButton"]!.ToString(), StopQuestionWording.StopButton(StopQuestion.Deploy));
        Assert.Equal(deploy["cancelButton"]!.ToString(), StopQuestionWording.CancelButton);
        Assert.Equal(deploy["settingLabel"]!.ToString(), StopQuestionWording.SettingLabel(StopQuestion.Deploy));

        var share = Contract["questions"]!["share"]!;
        Assert.Equal(share["title"]!.ToString(), StopQuestionWording.Title(StopQuestion.Share));
        Assert.Equal(share["message"]!.ToString(), StopQuestionWording.Message(StopQuestion.Share));
        Assert.Equal(share["stopButton"]!.ToString(), StopQuestionWording.StopButton(StopQuestion.Share));
        Assert.Equal(share["cancelButton"]!.ToString(), StopQuestionWording.CancelButton);
        Assert.Equal(share["settingLabel"]!.ToString(), StopQuestionWording.SettingLabel(StopQuestion.Share));

        var wording = Contract["wording"]!;
        Assert.Equal(wording["dontAskAgain"]!.ToString(), StopQuestionWording.DontAskAgain);
        Assert.Equal(wording["sectionHeader"]!.ToString(), StopQuestionWording.SectionHeader);
        // Windows has no Command-Period: its footer is windowsWording's.
        Assert.Equal(Contract["windowsWording"]!["footer"]!.ToString(), StopQuestionWording.Footer);
        Assert.DoesNotContain("Command", StopQuestionWording.Footer);
        Assert.Contains("Command-Period", wording["footer"]!.ToString());
    }

    [Fact]
    public void TheTrailLinesAreTheContractsAndTheMustRecordExample()
    {
        var trail = Contract["trail"]!;
        Assert.Equal("stop question setting changed", trail["event"]!.ToString());
        Assert.Equal("stop question setting changed", Plantoir.Core.Scripting.ActivityTrail.KeyFor(Plantoir.Core.Scripting.ActivityTrail.Event.StopQuestionSettingChanged));
        foreach (var question in new[] { StopQuestion.Deploy, StopQuestion.Share })
        {
            foreach (bool asked in new[] { true, false })
            {
                string onOrOff = trail["onOrOff"]![asked ? "true" : "false"]!.ToString();
                string label = StopQuestionWording.SettingLabel(question);
                Assert.Equal(trail["fromSettings"]!.ToString().Replace("{settingLabel}", label).Replace("{onOrOff}", onOrOff),
                             StopQuestionWording.TrailLine(question, asked, StopQuestionChangedFrom.Settings));
                Assert.Equal(trail["fromDontAskAgain"]!.ToString().Replace("{settingLabel}", label).Replace("{onOrOff}", onOrOff)
                                 .Replace("{title}", StopQuestionWording.Title(question)),
                             StopQuestionWording.TrailLine(question, asked, StopQuestionChangedFrom.DontAskAgain));
            }
        }
        var mustRecord = ContractLoader.LoadJson("shared-rules.json")["activityTrail"]!["mustRecord"]!.AsArray()
            .Single(entry => entry!["event"]!.ToString() == "stop question setting changed")!;
        Assert.Null(mustRecord["appliesOn"]);
        Assert.Equal(mustRecord["line"]!.ToString(),
                     StopQuestionWording.TrailLine(StopQuestion.Deploy, false, StopQuestionChangedFrom.DontAskAgain));
    }

    // ---- the cases ---------------------------------------------------------------

    [Fact]
    public void EveryCaseHolds()
    {
        var cases = Contract["cases"]!.AsArray();
        Assert.True(cases.Count >= 14, $"only {cases.Count} stopQuestions cases");
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            var before = c["settingsBefore"]!;
            var settings = new AppSettings
            {
                AsksBeforeStoppingADeploy = before["deploy"]!.GetValue<bool>(),
                AsksBeforeStoppingAShare = before["share"]!.GetValue<bool>(),
            };
            StopQuestion? question = c["question"]?.ToString() switch
            {
                null => null,
                "deploy" => StopQuestion.Deploy,
                "share" => StopQuestion.Share,
                var other => throw new Xunit.Sdk.XunitException($"{name}: unknown question {other}"),
            };
            var written = new List<string>();
            var asking = new StopQuestionAsking(question, settings, written.Add);
            bool running = c["taskRunning"]!.GetValue<bool>();
            var steps = c["steps"]!.AsArray();
            for (int index = 0; index < steps.Count; index++)
            {
                string step = steps[index]!.ToString();
                bool stops = false;
                switch (step)
                {
                    case "pressCancel": stops = asking.PressCancel(running); break;
                    case "tickDontAskAgain": asking.DontAskAgain = true; break;
                    case "chooseStop": asking.ChooseStop(); stops = true; break;
                    case "chooseCancel": asking.ChooseCancel(); break;
                    case "taskEnded": asking.TaskEnded(); break;
                    case "settingsTurnOn": StopQuestionWording.SetAsked(question!.Value, true, settings, StopQuestionChangedFrom.Settings, written.Add); break;
                    case "settingsTurnOff": StopQuestionWording.SetAsked(question!.Value, false, settings, StopQuestionChangedFrom.Settings, written.Add); break;
                    default: throw new Xunit.Sdk.XunitException($"{name}: unknown step {step}");
                }
                Assert.True(c["stopsAfterStep"]![index]!.GetValue<bool>() == stops, $"{name}, step {index + 1} ({step}): stops {stops}");
                Assert.True(c["asksAfterStep"]![index]!.GetValue<bool>() == asking.IsAsking, $"{name}, step {index + 1} ({step}): asking {asking.IsAsking}");
            }
            var after = c["settingsAfter"]!;
            Assert.True(after["deploy"]!.GetValue<bool>() == settings.AsksBeforeStoppingADeploy, $"{name}: the deploy's setting");
            Assert.True(after["share"]!.GetValue<bool>() == settings.AsksBeforeStoppingAShare, $"{name}: the share's setting");
            Assert.Equal(c["trail"]!.AsArray().Select(line => line!.ToString()).ToList(), written);
        }
    }

    [Fact]
    public void BothQuestionsAreAskedUntilTheTeacherSaysOtherwise_AndTheAnswerIsKept()
    {
        var fresh = new AppSettings();
        Assert.True(fresh.AsksBeforeStoppingADeploy);
        Assert.True(fresh.AsksBeforeStoppingAShare);
        Assert.True(fresh.ChangeAsksBeforeStopping(StopQuestion.Deploy, false));
        Assert.False(fresh.ChangeAsksBeforeStopping(StopQuestion.Deploy, false));
        var loaded = AppSettings.Load();
        Assert.False(loaded.AsksBeforeStoppingADeploy);
        Assert.True(loaded.AsksBeforeStoppingAShare);
    }

    [Fact]
    public void TheEscapeKeyIsDecidedAsItArrives()
    {
        Assert.True(StopKey.GoesToCancel(cancelIsShown: true, taskIsRunning: true, aDialogIsOpen: false, anEditableTextBoxHasTheFocus: false));
        Assert.False(StopKey.GoesToCancel(cancelIsShown: true, taskIsRunning: true, aDialogIsOpen: false, anEditableTextBoxHasTheFocus: true));
        Assert.False(StopKey.GoesToCancel(cancelIsShown: false, taskIsRunning: true, aDialogIsOpen: false, anEditableTextBoxHasTheFocus: false));
        Assert.False(StopKey.GoesToCancel(cancelIsShown: true, taskIsRunning: false, aDialogIsOpen: false, anEditableTextBoxHasTheFocus: false));
        Assert.False(StopKey.GoesToCancel(cancelIsShown: true, taskIsRunning: true, aDialogIsOpen: true, anEditableTextBoxHasTheFocus: false));
    }

    // ---- the panel, by source ------------------------------------------------------

    [Fact]
    public void TheKeyIsAnAcceleratorOnTheVisibleCancel_AndNothingElseCatchesEscape()
    {
        string panel = AppSource("Views", "TaskProgressView.xaml.cs");
        Assert.Contains("TaskCancelButton.KeyboardAccelerators.Add(escape);", panel);
        Assert.Contains("new KeyboardAccelerator { Key = VirtualKey.Escape }", panel);
        // No key handler of its own: no PreviewKeyDown, no KeyDown on the panel.
        Assert.DoesNotContain("PreviewKeyDown", panel);
        Assert.DoesNotContain("this.KeyDown", panel);
        // A click and an accessibility press reach the same path, with no box check.
        Assert.Contains("private void TaskCancel_Click(object sender, RoutedEventArgs e) => _ = PressCancelAsync();", panel);
        string xaml = AppSource("Views", "TaskProgressView.xaml");
        Assert.Contains("x:Name=\"TaskCancelButton\" Content=\"Cancel\"", xaml);
        // Only a section's panel holds the key; the wizard's keeps Escape for its dialog (#979).
        Assert.Contains("Progress.GiveCancelTheEscapeKey();", AppSource("Views", "SectionDetailView.xaml.cs"));
        Assert.DoesNotContain("GiveCancelTheEscapeKey", AppSource("Views", "NewCourseDialog.cs"));
        Assert.Contains("stopQuestion: StopQuestion.Deploy", AppSource("Views", "SectionDetailView.xaml.cs"));
    }

    [Fact]
    public void TheQuestionSaysTheContractsWords_WithStopAsTheDefault()
    {
        string panel = AppSource("Views", "TaskProgressView.xaml.cs");
        int from = panel.IndexOf("private async System.Threading.Tasks.Task AskBeforeStoppingAsync(", StringComparison.Ordinal);
        Assert.True(from >= 0, "the stop question is not where this test looks");
        string question = panel.Substring(from, panel.IndexOf("ShowAsync()", from, StringComparison.Ordinal) - from);
        Assert.Contains("Title = StopQuestionWording.Title(question),", question);
        Assert.Contains("PrimaryButtonText = StopQuestionWording.StopButton(question),", question);
        Assert.Contains("CloseButtonText = StopQuestionWording.CancelButton,", question);
        Assert.Contains("DefaultButton = ContentDialogButton.Primary,", question);
        Assert.Contains("new CheckBox { Content = StopQuestionWording.DontAskAgain, IsChecked = false", question);
        Assert.DoesNotContain("Destructive", question);
        // The box is read only with Stop.
        string after = panel.Substring(panel.IndexOf("ShowAsync()", from, StringComparison.Ordinal));
        int stop = after.IndexOf("asking.ChooseStop();", StringComparison.Ordinal);
        int read = after.IndexOf("asking.DontAskAgain = dontAskAgain.IsChecked == true;", StringComparison.Ordinal);
        int cancel = after.IndexOf("asking.ChooseCancel();", StringComparison.Ordinal);
        Assert.True(read >= 0 && read < stop && stop < cancel, "the box is read somewhere other than just before Stop");
    }

    [Fact]
    public void SettingsDeployingOpensWithStopping_InTheContractsWords()
    {
        string pane = AppSource("Views", "DeployingSettingsPane.cs");
        int stopping = pane.IndexOf("AddStoppingSection(panel, settings);", StringComparison.Ordinal);
        int cloudflare = pane.IndexOf("SectionHeaderWithCaption(\"Cloudflare Pages\"", StringComparison.Ordinal);
        Assert.True(stopping >= 0 && stopping < cloudflare, "Stopping is not the first section of Settings ▸ Deploying");
        Assert.Contains("StopQuestionWording.SectionHeader", pane);
        Assert.Contains("StopQuestionWording.SettingLabel(question)", pane);
        Assert.Contains("StopQuestionWording.Footer", pane);
        Assert.Contains("StopQuestionWording.SetAsked(question, true, settings, StopQuestionChangedFrom.Settings)", pane);
        Assert.Contains("StopQuestionWording.SetAsked(question, false, settings, StopQuestionChangedFrom.Settings)", pane);
    }
}

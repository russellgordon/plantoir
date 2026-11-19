using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// #987: the two removal questions say the contract's words, and neither puts
/// up a default button. Removing a scheduled deploy is
/// <c>scheduledDeployCancellation.removingOne</c>; removing a downloaded
/// assistant is <c>assistantModelChoice.removal</c> (asksFirst, words). The
/// dialogs are WinUI, so the source that puts each one up is what is asserted
/// on, the way <see cref="DefaultButtonScanTests"/> does. The mac pins the
/// same words in <c>ScheduledDeployCleanupTests</c> and
/// <c>SharedRulesContractTests.testAssistantModelRemoval</c>.
/// </summary>
public class RemovalQuestionsContractTests
{
    private static JsonNode SharedRules => ContractLoader.LoadJson("shared-rules.json");

    private static string Source(params string[] parts) =>
        File.ReadAllText(Path.Combine(new[] { ContractLoader.RepositoryRoot, "windows-app", "Plantoir" }.Concat(parts).ToArray()))
            .Replace("\r\n", "\n");

    private static string Between(string text, string start, string end)
    {
        int from = text.IndexOf(start, StringComparison.Ordinal);
        Assert.True(from >= 0, $"\"{start}\" is not in the source");
        int to = text.IndexOf(end, from + start.Length, StringComparison.Ordinal);
        Assert.True(to > from, $"\"{end}\" does not follow \"{start}\"");
        return text.Substring(from, to - from);
    }

    [Fact]
    public void RemovingAScheduledDeploy_SaysTheContractsWords()
    {
        var words = SharedRules["scheduledDeployCancellation"]!["removingOne"]!["words"]!;
        Assert.Equal(words["menuItem"]!.ToString(), ScheduledDeployRemovalWording.MenuItem);
        Assert.Equal(words["question"]!.ToString(), ScheduledDeployRemovalWording.Question);
        Assert.Equal(words["cancelButton"]!.ToString(), ScheduledDeployRemovalWording.CancelButton);
        Assert.Equal(words["removeButton"]!.ToString(), ScheduledDeployRemovalWording.RemoveButton);
        Assert.Equal(words["messageWithoutTime"]!.ToString(), ScheduledDeployRemovalWording.MessageWithoutTime);
        string expected = words["message"]!.ToString()
            .Replace("{course}", "ICS3U").Replace("{section}", "2")
            .Replace("{time}", "6:30 AM").Replace("{day}", "Monday 23 November");
        Assert.Equal(expected, ScheduledDeployRemovalWording.Message("ICS3U", 2, "6:30 AM", "Monday 23 November"));
        Assert.DoesNotContain("automatically", ScheduledDeployRemovalWording.Message("ICS3U", 2, "6:30 AM", "Monday 23 November"));
    }

    [Fact]
    public void RemovingAScheduledDeploy_PutsUpNoDefaultButton()
    {
        string sidebar = Source("Views", "SidebarPane.xaml.cs");
        string question = Between(sidebar, "private async void ConfirmCancelScheduledDeploy(", "ShowDialogSafelyAsync(dialog)");
        Assert.Contains("Title = ScheduledDeployRemovalWording.Question,", question);
        Assert.Contains("Content = ScheduledDeployRemovalWording.Message(", question);
        Assert.Contains("PrimaryButtonText = ScheduledDeployRemovalWording.RemoveButton,", question);
        Assert.Contains("CloseButtonText = ScheduledDeployRemovalWording.CancelButton,", question);
        Assert.Contains("DefaultButton = ContentDialogButton.None,", question);
        // Both doors to it say the command's words.
        Assert.Contains("MenuItem(ScheduledDeployRemovalWording.MenuItem,", sidebar);
        Assert.Contains("Add(section, ScheduledDeployRemovalWording.MenuItem,", Source("MainWindow.Menus.cs"));
    }

    [Fact]
    public void RemovingADownloadedAssistant_AsksFirstInTheContractsWords()
    {
        var removal = SharedRules["assistantModelChoice"]!["removal"]!;
        Assert.True(removal["asksFirst"]!.GetValue<bool>());
        var words = removal["words"]!;
        string pc = SharedRules["specialNames"]!["platformWording"]!["machine"]!["windows"]!.ToString();
        foreach (var tier in new[] { AssistModelTier.Small, AssistModelTier.Large })
        {
            Assert.Equal(words["question"]!.ToString().Replace("{assistant}", tier.DisplayName()),
                         AssistModelRemovalWording.Question(tier));
        }
        Assert.Equal(words["message"]!.ToString().Replace("{size}", "2.33 GB").Replace("{machine}", pc),
                     AssistModelRemovalWording.Message("2.33 GB"));
        Assert.Equal(words["removeButton"]!.ToString(), AssistModelRemovalWording.RemoveButton);

        // The button beside a download asks; it no longer removes on a click.
        string pane = Source("Views", "AssistantSettingsPane.cs");
        Assert.Contains("button.Content = AssistModelRemovalWording.RemoveCommand;", pane);
        Assert.Contains("await AskThenRemove(", pane);
        Assert.DoesNotContain("button.Click += (_, _) => store.Remove();", pane);
        string question = Between(pane, "private static async Task AskThenRemove(", "store.Remove();");
        Assert.Contains("PrimaryButtonText = AssistModelRemovalWording.RemoveButton,", question);
        Assert.Contains("CloseButtonText = AssistModelRemovalWording.CancelButton,", question);
        Assert.Contains("DefaultButton = ContentDialogButton.None,", question);
        Assert.Contains("!= ContentDialogResult.Primary) return;", question);
    }
}

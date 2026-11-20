using System.Text.RegularExpressions;
using Plantoir.Core.Models;
using Xunit;
using Item = Plantoir.Core.Models.SubjectMenuRules.Item;
using ReviseTarget = Plantoir.Core.Models.SubjectMenuRules.ReviseTarget;

namespace Plantoir.Tests;

/// <summary>
/// #990 (the mac's D11, Russell's ruling Q9): an outside assistant this PC
/// does not have is DIMMED in the menu bar's Revise With ▸, never left out,
/// and still HIDDEN in a row's context menu. The contract's two keys
/// (<c>app-rules.json</c> → <c>outsideAgents.hiddenWhenNotInstalled</c> and
/// <c>hiddenInContextMenusWhenNotInstalled</c>) are read here, so either
/// flipping back turns this red; the rule is
/// <see cref="SubjectMenuRules.EnabledInTheMenuBar"/>, and the menu bar's
/// source is checked to draw every door whatever is installed.
/// </summary>
public class ReviseWithPresenceTests
{
    private static readonly Item[] OutsideDoorItems =
    {
        Item.CourseReviseWithClaude, Item.CourseReviseWithCodex, Item.SectionReviseWithClaude, Item.SectionReviseWithCodex,
    };

    private static string Source(params string[] parts) =>
        File.ReadAllText(Path.Combine(new[] { ContractLoader.RepositoryRoot, "windows-app" }.Concat(parts).ToArray()));

    [Fact]
    public void TheContractDimsInTheMenuBarAndHidesInContextMenus()
    {
        var outside = ContractLoader.LoadJson("app-rules.json")["outsideAgents"]!;
        Assert.False(outside["hiddenWhenNotInstalled"]!.GetValue<bool>());
        Assert.True(outside["hiddenInContextMenusWhenNotInstalled"]!.GetValue<bool>());
    }

    [Fact]
    public void AMissingDoorIsDimmedWhereTheRuleWouldAllowIt_AndEveryOtherItemFollowsTheRuleAlone()
    {
        var everything = Enum.GetValues<Item>().ToHashSet();
        var nothing = new HashSet<Item>();
        foreach (bool claude in new[] { false, true })
        foreach (bool codex in new[] { false, true })
        {
            bool Installed(ReviseTarget door) => door switch
            {
                ReviseTarget.Claude => claude,
                ReviseTarget.Codex => codex,
                _ => throw new InvalidOperationException($"{door} is not an outside door this test asks about"),
            };
            foreach (var item in Enum.GetValues<Item>())
            {
                // The rule says no: dimmed whatever is installed.
                Assert.False(SubjectMenuRules.EnabledInTheMenuBar(item, nothing, Installed), $"{item} with nothing allowed");
                bool expected = SubjectMenuRules.OutsideDoorOf(item) switch
                {
                    ReviseTarget.Claude => claude,
                    ReviseTarget.Codex => codex,
                    _ => true,
                };
                Assert.Equal(expected, SubjectMenuRules.EnabledInTheMenuBar(item, everything, Installed));
            }
        }
    }

    [Fact]
    public void OnlyTheOutsideDoorsDependOnWhatIsInstalled()
    {
        foreach (var item in Enum.GetValues<Item>())
            Assert.Equal(OutsideDoorItems.Contains(item), SubjectMenuRules.OutsideDoorOf(item) is not null);
        Assert.Null(SubjectMenuRules.OutsideDoorOf(Item.SectionReviseWithLocalAssistant));
        Assert.Null(SubjectMenuRules.OutsideDoorOf(Item.CourseReviseWithLocalAssistant));
    }

    /// <summary>
    /// The menu bar draws Claude… and Codex… unconditionally (no installed
    /// test around the <c>Add</c>), and greys through the rule above; a row's
    /// context menu still asks the door before it adds the item.
    /// </summary>
    [Fact]
    public void TheMenuBarDrawsEveryDoor_AndTheContextMenuStillAsks()
    {
        string menus = Source("Plantoir", "MainWindow.Menus.cs");
        var reviseWith = Regex.Match(menus, @"private void AddReviseWith\((?<body>.*?)\n    \}", RegexOptions.Singleline);
        Assert.True(reviseWith.Success, "AddReviseWith was not found in MainWindow.Menus.cs.");
        string body = reviseWith.Groups["body"].Value;
        Assert.DoesNotContain("IsAvailable", body);
        Assert.DoesNotContain("IsInstalled", body);
        Assert.Contains("Add(sub.Items, ClaudeCodeLauncher.MenuItemTitle,", body);
        Assert.Contains("Add(sub.Items, CodexLauncher.MenuItemTitle,", body);
        Assert.Contains("SubjectMenuRules.EnabledInTheMenuBar(item, enabled, IsInstalledHere)", menus);

        string sidebar = Source("Plantoir", "Views", "SidebarPane.xaml.cs");
        int start = sidebar.IndexOf("private List<MenuFlyoutItem> ReviseItems(", StringComparison.Ordinal);
        Assert.True(start > 0, "ReviseItems was not found in SidebarPane.xaml.cs.");
        string items = sidebar[start..sidebar.IndexOf("return items;", start, StringComparison.Ordinal)];
        Assert.Contains("if (ClaudeCodeLauncher.IsAvailable)", items);
        Assert.Contains("if (CodexLauncher.IsAvailable)", items);
    }

    /// <summary>
    /// #1017: <c>ApplyMenuEnablement</c>, which re-runs whenever presence
    /// changes, only DIMS the ruled items: the one line that touches them
    /// sets <c>IsEnabled</c> through the rule, and nothing in it collapses a
    /// view, a Revise With door included. The one <c>Visibility</c> it sets is
    /// Preview's alternate (hidden while Stop Preview shows), which no
    /// assistant decides. A change that hid a missing assistant's item there
    /// (a <c>Visibility</c> on <c>view</c>, or <c>IsInstalledHere</c> deciding
    /// anything but <c>IsEnabled</c>) turns this red.
    /// </summary>
    [Fact]
    public void ApplyMenuEnablementDimsAMissingDoorAndNeverHidesIt()
    {
        string menus = Source("Plantoir", "MainWindow.Menus.cs");
        var method = Regex.Match(menus, @"internal void ApplyMenuEnablement\(\)(?<body>.*?)\n    \}", RegexOptions.Singleline);
        Assert.True(method.Success, "ApplyMenuEnablement was not found in MainWindow.Menus.cs.");
        string body = method.Groups["body"].Value;
        Assert.Contains("foreach (var (item, view) in _ruled) view.IsEnabled = SubjectMenuRules.EnabledInTheMenuBar(item, enabled, IsInstalledHere);", body);

        var visibilityLines = new List<string>();
        var presenceLines = new List<string>();
        foreach (string line in body.Split('\n'))
        {
            string trimmed = line.Trim();
            if (trimmed.StartsWith("//", StringComparison.Ordinal)) continue;
            if (trimmed.Contains("Visibility", StringComparison.Ordinal)) visibilityLines.Add(trimmed);
            if (trimmed.Contains("IsInstalledHere", StringComparison.Ordinal) || trimmed.Contains("IsAvailable", StringComparison.Ordinal)
                || trimmed.Contains("OutsideAssistantPresence", StringComparison.Ordinal)) presenceLines.Add(trimmed);
        }
        Assert.Equal(new[] { "alternate.Visibility = stops ? Visibility.Collapsed : Visibility.Visible;" }, visibilityLines);
        Assert.Equal(new[] { "foreach (var (item, view) in _ruled) view.IsEnabled = SubjectMenuRules.EnabledInTheMenuBar(item, enabled, IsInstalledHere);" },
                     presenceLines);
        Assert.DoesNotContain("_ruled.Remove", body);
        Assert.DoesNotContain("Items.Remove", body);
    }

    /// <summary>No grey line of explanation in the Course or Section menu since #990 (the mac's ruling Q14).</summary>
    [Fact]
    public void TheMenuBarHoldsNoGreyTextRows()
    {
        string menus = Source("Plantoir", "MainWindow.Menus.cs");
        Assert.DoesNotContain("new MenuFlyoutItem { IsEnabled = false", menus);
        Assert.DoesNotContain("courseRenameReason", menus);
    }
}

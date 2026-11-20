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

    /// <summary>No grey line of explanation in the Course or Section menu since #990 (the mac's ruling Q14).</summary>
    [Fact]
    public void TheMenuBarHoldsNoGreyTextRows()
    {
        string menus = Source("Plantoir", "MainWindow.Menus.cs");
        Assert.DoesNotContain("new MenuFlyoutItem { IsEnabled = false", menus);
        Assert.DoesNotContain("courseRenameReason", menus);
    }
}

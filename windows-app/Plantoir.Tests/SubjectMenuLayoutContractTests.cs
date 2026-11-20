using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Item = Plantoir.Core.Models.SubjectMenuRules.Item;

namespace Plantoir.Tests;

/// <summary>
/// <c>contracts/shared-rules.json</c> → <c>subjectMenus.layout</c> (#990,
/// Russell's ruling of 2026-11-20: grouping A): which of Section and Classes
/// each section item is in, and in what order and groups, against
/// <see cref="SubjectMenuLayout"/>, which the menu bar draws both menus from.
/// The mac runs the same lists in <c>SubjectMenuLayoutTests</c>. An item this
/// app does not have yet is held open by name in <see cref="NamedGapLedger"/>
/// (<c>subjectMenus.items</c>) and is left out of the expected menu, its
/// neighbours keeping their order; Add Class… is expected under its older
/// name here, Add Next Class (#927). The menu bar's drawing of these lists is
/// <c>MenuBarUiTests</c>' <c>SectionAndClassesUiTests</c>.
/// </summary>
public class SubjectMenuLayoutContractTests
{
    private static JsonNode Layout => SubjectMenusContractTests.Rule["layout"]!;

    /// <summary>The contract's groups of one menu, as this app should draw them.</summary>
    internal static List<List<string>> ExpectedHere(JsonNode menu)
    {
        var held = NamedGapLedger.All.Where(entry => entry.Area == NamedGapLedger.SubjectMenuItems).Select(entry => entry.Key).ToHashSet();
        var olderNames = NamedGapLedger.All.Where(entry => entry.Area == NamedGapLedger.SubjectMenuItemsUnderAnOlderName)
            .ToDictionary(entry => entry.Key, entry => NamedGapLedger.SubjectMenuItemsOlderNames[entry.Key]);
        var groups = new List<List<string>>();
        foreach (var group in menu["groups"]!.AsArray())
        {
            var names = group!.AsArray().Select(n => n!.ToString())
                .Where(name => !held.Contains(name))
                .Select(name => olderNames.TryGetValue(name, out string? older) ? older : name)
                .ToList();
            if (names.Count > 0) groups.Add(names);   // a group held whole would draw nothing, and no separator
        }
        return groups;
    }

    /// <summary>This app's groups of one menu, in the contract's names.</summary>
    internal static List<List<string>> Here(SubjectMenuLayout.Menu menu) =>
        SubjectMenuLayout.Groups(menu).Select(group => group.Select(entry => entry switch
        {
            SubjectMenuLayout.Entry.OfItem(var item) => SubjectMenuRules.ContractName(item),
            SubjectMenuLayout.Entry.OfSubmenu(var submenu) => SubjectMenuLayout.ContractName(submenu),
            _ => throw new InvalidOperationException("an entry of no known kind"),
        }).ToList()).ToList();

    /// <summary>MUST FAIL with any item moved, any group split or joined (proved by moving Class Dates… after Re-date Classes…).</summary>
    [Fact]
    public void TheTwoMenusAreTheContractsGroups_LessWhatThisAppDoesNotHaveYet()
    {
        var menus = Layout["menus"]!.AsArray().Select(m => m!).ToList();
        Assert.Equal(menus.Select(m => m["menu"]!.ToString()), Enum.GetValues<SubjectMenuLayout.Menu>().Select(SubjectMenuLayout.ContractName));
        foreach (var menu in menus)
        {
            var here = Enum.GetValues<SubjectMenuLayout.Menu>().Single(m => SubjectMenuLayout.ContractName(m) == menu["menu"]!.ToString());
            Assert.Equal(menu["title"]!.ToString(), SubjectMenuLayout.Title(here));
            var expected = ExpectedHere(menu);
            var actual = Here(here);
            Assert.True(expected.Count == actual.Count && expected.Zip(actual).All(pair => pair.First.SequenceEqual(pair.Second)),
                $"{menu["menu"]}: expected {Describe(expected)}, drawn {Describe(actual)}");
        }
    }

    [Fact]
    public void TheReviseWithSubmenuIsTheContracts_LessWhatThisAppDoesNotHaveYet()
    {
        var held = NamedGapLedger.All.Where(entry => entry.Area == NamedGapLedger.SubjectMenuItems).Select(entry => entry.Key).ToHashSet();
        var submenus = Layout["submenus"]!.AsObject();
        Assert.Equal(submenus.Select(pair => pair.Key), Enum.GetValues<SubjectMenuLayout.Submenu>().Select(SubjectMenuLayout.ContractName));
        foreach (var submenu in Enum.GetValues<SubjectMenuLayout.Submenu>())
        {
            var entry = submenus[SubjectMenuLayout.ContractName(submenu)]!;
            Assert.Equal(entry["title"]!.ToString(), SubjectMenuLayout.Title(submenu));
            Assert.Equal(entry["items"]!.AsArray().Select(n => n!.ToString()).Where(name => !held.Contains(name)),
                         SubjectMenuLayout.ItemsOf(submenu).Select(SubjectMenuRules.ContractName));
        }
    }

    /// <summary>Every section item this app has is in exactly one of the two menus, once.</summary>
    [Fact]
    public void EverySectionItemIsInOneMenuOnce()
    {
        var placed = new List<Item>();
        foreach (var menu in Enum.GetValues<SubjectMenuLayout.Menu>())
            foreach (var group in SubjectMenuLayout.Groups(menu))
            {
                Assert.NotEmpty(group);
                foreach (var entry in group)
                {
                    if (entry is SubjectMenuLayout.Entry.OfItem(var item)) placed.Add(item);
                    else if (entry is SubjectMenuLayout.Entry.OfSubmenu(var submenu)) placed.AddRange(SubjectMenuLayout.ItemsOf(submenu));
                }
            }
        Assert.Equal(placed.Count, placed.Distinct().Count());
        // Every item from Preview on in the enum, short of View's, is a section item.
        var sectionItems = Enum.GetValues<Item>().SkipWhile(item => item != Item.Preview).TakeWhile(item => item != Item.Back).ToHashSet();
        Assert.Equal(sectionItems.OrderBy(i => i), placed.OrderBy(i => i));
        Assert.Equal(SubjectMenuLayout.Menu.Classes, SubjectMenuLayout.MenuContaining(Item.ClassDates));
        Assert.Equal(SubjectMenuLayout.Menu.Section, SubjectMenuLayout.MenuContaining(Item.SectionReviseWithCodex));
        Assert.Null(SubjectMenuLayout.MenuContaining(Item.AddSection));
    }

    /// <summary>Windows' menu bar order is the contract's, Classes after Section.</summary>
    [Fact]
    public void TheMenuBarOrderIsTheContracts()
    {
        Assert.Equal(new[] { "File", "Course", "Section", "Classes", "View", "Help" },
                     Layout["menuBar"]!["windows"]!.AsArray().Select(n => n!.ToString()));
        string xaml = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "MainWindow.xaml"));
        var order = new[] { "FileMenu", "CourseMenu", "SectionMenu", "ClassesMenu", "ViewMenu", "HelpMenu" }
            .Select(name => xaml.IndexOf($"x:Name=\"{name}\"", StringComparison.Ordinal)).ToList();
        Assert.DoesNotContain(-1, order);
        Assert.Equal(order.OrderBy(i => i), order);
    }

    /// <summary>A trail line names the menu the item is in now. MUST FAIL before #990, where all said Section.</summary>
    [Fact]
    public void MenuPathsNameTheMenuTheItemIsIn()
    {
        Assert.Equal("Classes ▸ Class Dates…", SubjectMenuLayout.Path(Item.ClassDates, "Class Dates…"));
        Assert.Equal("Classes ▸ Add Next Class", SubjectMenuLayout.Path(Item.AddNextClass, "Add Next Class"));
        Assert.Equal("Section ▸ Publish Pages…", SubjectMenuLayout.Path(Item.PublishPages, "Publish Pages…"));
        Assert.Equal("Rename", SubjectMenuLayout.Path(Item.Rename, "Rename"));
    }

    private static string Describe(List<List<string>> groups) => string.Join(" | ", groups.Select(g => string.Join(", ", g)));
}

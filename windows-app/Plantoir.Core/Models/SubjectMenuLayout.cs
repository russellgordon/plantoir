using Plantoir.Core.Assist;
using Plantoir.Core.Catalogs;
using Item = Plantoir.Core.Models.SubjectMenuRules.Item;

namespace Plantoir.Core.Models;

/// <summary>
/// Which of the two section menus each section item is in, and in what order
/// and groups (#990, Russell's ruling of 2026-11-20: grouping A; the mac's
/// <c>SubjectMenuLayout</c>). <b>Section</b> holds the website jobs, and
/// <b>Classes</b>, after it, the class calendar. The menu bar draws both
/// menus from these lists (<c>MainWindow.Menus.cs</c>), so the split is data:
/// <c>contracts/shared-rules.json</c> → <c>subjectMenus.layout</c> holds the
/// same lists, and <c>SubjectMenuLayoutContractTests</c> checks the two agree,
/// with the items this app does not have yet (the named gaps: Stop Showing
/// Deployed Folder, GitHub Copilot, Roll Over to a New Year…) left out and
/// Add Class… said under its older name, Add Next Class (#927). Which items
/// can be used is still <see cref="SubjectMenuRules"/>' job: every item here
/// is drawn in every situation and dimmed when it cannot be used, never
/// hidden.
/// </summary>
public static class SubjectMenuLayout
{
    /// <summary>The two menus that act on a selected section.</summary>
    public enum Menu { Section, Classes }

    /// <summary>A submenu inside one of the menus.</summary>
    public enum Submenu { SectionReviseWith }

    /// <summary>One line of a menu: an item, or a submenu of items.</summary>
    public abstract record Entry
    {
        /// <summary>An item of the rule.</summary>
        public sealed record OfItem(Item Item) : Entry;

        /// <summary>A submenu.</summary>
        public sealed record OfSubmenu(Submenu Submenu) : Entry;
    }

    private static Entry I(Item item) => new Entry.OfItem(item);

    /// <summary>
    /// Section ▸, group by group; a separator goes between groups. The two
    /// Undo items stay here, last in the publishing group, until the mac's
    /// #899 U7 (Windows' W11b) folds them into Edit ▸ Undo. Change Deploy
    /// Time… (#525) will go between Schedule Deploy… and Remove Scheduled
    /// Deploy (<c>subjectMenus.layout.reservedPlaces</c>).
    /// </summary>
    public static IReadOnlyList<IReadOnlyList<Entry>> SectionGroups { get; } = new List<IReadOnlyList<Entry>>
    {
        new[] { I(Item.Preview), I(Item.RebuildPreview), I(Item.OpenInBrowser) },
        new[]
        {
            I(Item.PublishClassForADate), I(Item.PublishPages), I(Item.HidePages), I(Item.PublishPagesLinksLeadTo),
            I(Item.UndoLastChange), I(Item.UndoGettingReady),
        },
        new[] { I(Item.Deploy), I(Item.ScheduleDeploy), I(Item.CancelScheduledDeploy) },
        new Entry[] { new Entry.OfSubmenu(Submenu.SectionReviseWith) },
        new[] { I(Item.SectionOpenInObsidian), I(Item.SectionShowInFinder), I(Item.SectionNewTerminalAtFolder) },
        new[] { I(Item.RemoveSection) },
    };

    /// <summary>Classes ▸, group by group.</summary>
    public static IReadOnlyList<IReadOnlyList<Entry>> ClassesGroups { get; } = new List<IReadOnlyList<Entry>>
    {
        new[] { I(Item.AddNextClass) },
        new[] { I(Item.ClassDates), I(Item.ReDateClasses), I(Item.MakeRoomForClasses) },
        new[] { I(Item.GetReadyForTheStartOfTheYear) },
    };

    /// <summary>The menu's groups.</summary>
    public static IReadOnlyList<IReadOnlyList<Entry>> Groups(Menu menu) => menu switch
    {
        Menu.Section => SectionGroups,
        _ => ClassesGroups,
    };

    /// <summary>
    /// The menu's title in the menu bar, for a course whose class pages are
    /// called <paramref name="noun"/>. Section is Section everywhere; Classes
    /// is titled Meetings in a course whose pages are meetings, a club
    /// (Russell's ruling on #990, 2026-11-20 evening: "in a club the menu
    /// itself is titled Meetings, on both platforms, so no sentence a club's
    /// teacher reads says 'class'"; <c>subjectMenus.layout</c> →
    /// <c>titleForAMeeting</c>). The noun, not the club code, decides it,
    /// because the noun is what every club sentence is chosen by, so a
    /// sentence that names the menu names the one on the screen. No default:
    /// a caller says which course's menu it means.
    /// </summary>
    public static string Title(Menu menu, ClassNoun noun) => menu switch
    {
        Menu.Section => "Section",
        _ => noun == ClassNoun.Meeting ? "Meetings" : "Classes",
    };

    /// <summary>
    /// What the course with <paramref name="code"/> calls its class pages, for
    /// a sentence about one of its backups: the course's own noun, or, for a
    /// backup of a course no longer in the folder, a club's code read as
    /// meetings (<see cref="ClubCodeRule"/>). The mac's
    /// <c>WorkspaceModel.classNoun(ofCourse:)</c>.
    /// </summary>
    public static ClassNoun NounOfCourse(string code, IEnumerable<Course> courses, CourseNameCatalog catalog)
    {
        foreach (var course in courses)
            if (string.Equals(course.Code, code, StringComparison.OrdinalIgnoreCase))
                return course.Configuration.ClassNoun;
        return ClubCodeRule.IsClub(code, catalog) ? ClassNoun.Meeting : ClassNoun.Class;
    }

    /// <summary>The submenu's title.</summary>
    public static string Title(Submenu submenu) => "Revise With";

    /// <summary>The submenu's items, in the order the doors are shown everywhere.</summary>
    public static IReadOnlyList<Item> ItemsOf(Submenu submenu) =>
        new[] { Item.SectionReviseWithClaude, Item.SectionReviseWithCodex, Item.SectionReviseWithLocalAssistant };

    /// <summary>The contract's name for a menu or a submenu.</summary>
    public static string ContractName(Menu menu) => menu == Menu.Section ? "section" : "classes";

    /// <inheritdoc cref="ContractName(Menu)"/>
    public static string ContractName(Submenu submenu) => "sectionReviseWith";

    /// <summary>Which of the two menus holds the item, directly or in a submenu; null for File, Course and View.</summary>
    public static Menu? MenuContaining(Item item)
    {
        foreach (var menu in Enum.GetValues<Menu>())
            foreach (var group in Groups(menu))
                foreach (var entry in group)
                    switch (entry)
                    {
                        case Entry.OfItem(var held) when held == item:
                            return menu;
                        case Entry.OfSubmenu(var submenu) when ItemsOf(submenu).Contains(item):
                            return menu;
                    }
        return null;
    }

    /// <summary>
    /// The words of an item of Section ▸ or Classes ▸ on Windows: the mac's,
    /// but for Show in File Explorer and Open in Terminal, and Add Next Class
    /// until #927 brings Add Class…. Remove Section and Remove Scheduled
    /// Deploy carry no ellipsis since #990: a command that only asks for a
    /// confirmation takes none.
    /// </summary>
    public static string? TitleHere(Item item) => item switch
    {
        Item.Preview => "Preview",
        Item.RebuildPreview => "Rebuild Preview",
        Item.OpenInBrowser => "Open in Browser",
        Item.PublishClassForADate => "Publish Class for a Date…",
        Item.PublishPages => "Publish Pages…",
        Item.HidePages => "Hide Pages…",
        Item.PublishPagesLinksLeadTo => LinksChecklistWording.MenuItem,
        Item.UndoLastChange => "Undo Last Change",
        Item.UndoGettingReady => StartOfYearWording.UndoMenuItem,
        Item.Deploy => "Deploy…",
        Item.ScheduleDeploy => "Schedule Deploy…",
        Item.CancelScheduledDeploy => ScheduledDeployRemovalWording.MenuItem,
        Item.SectionOpenInObsidian => "Open in Obsidian",
        Item.SectionShowInFinder => "Show in File Explorer",
        Item.SectionNewTerminalAtFolder => "Open in Terminal",
        Item.RemoveSection => "Remove Section",
        Item.AddNextClass => "Add Next Class",
        Item.ClassDates => "Class Dates…",
        Item.ReDateClasses => "Re-date Classes…",
        Item.MakeRoomForClasses => "Make Room for Classes…",
        Item.GetReadyForTheStartOfTheYear => StartOfYearWording.MenuItem,
        _ => null,   // not an item of Section or Classes: SubjectMenuLayoutContractTests fails on a layout item with none (#990 review, LOW c)
    };

    /// <summary>
    /// An item's AutomationId: its menu's contract name, then its own name
    /// (classesClassDates, sectionPublishPages). The Section ids are the ones
    /// #488 gave them, kept so every UI test still finds them.
    /// </summary>
    public static string AutomationIdHere(Menu layout, Item item)
    {
        string own = item switch
        {
            Item.Preview => "Preview",
            Item.RebuildPreview => "RebuildPreview",
            Item.OpenInBrowser => "OpenInBrowser",
            Item.PublishClassForADate => "PublishClassForADate",
            Item.PublishPages => "PublishPages",
            Item.HidePages => "HidePages",
            Item.PublishPagesLinksLeadTo => "PublishPagesLinksLeadTo",
            Item.UndoLastChange => "UndoLastChange",
            Item.UndoGettingReady => "UndoGettingReady",
            Item.Deploy => "Deploy",
            Item.ScheduleDeploy => "ScheduleDeploy",
            Item.CancelScheduledDeploy => "CancelScheduledDeploy",
            Item.SectionOpenInObsidian => "OpenInObsidian",
            Item.SectionShowInFinder => "ShowInFileExplorer",
            Item.SectionNewTerminalAtFolder => "OpenInTerminal",
            Item.RemoveSection => "RemoveSection",
            Item.AddNextClass => "AddNextClass",
            Item.ClassDates => "ClassDates",
            Item.ReDateClasses => "ReDateClasses",
            Item.MakeRoomForClasses => "MakeRoomForClasses",
            Item.GetReadyForTheStartOfTheYear => "GetReady",
            _ => item.ToString(),
        };
        return ContractName(layout) + own;
    }

    /// <summary>
    /// "Section or Classes" ("Section or Meetings" in a club): the two menus'
    /// titles in the layout's order, for a sentence that covers a change from
    /// either (#990, Russell's ruling "name the real menu").
    /// </summary>
    public static string EitherMenu(ClassNoun noun) =>
        string.Join(" or ", Enum.GetValues<Menu>().Select(menu => Title(menu, noun)));

    /// <summary>"Section and Classes" ("Section and Meetings" in a club), for the Backups list's sentence on what the two keep.</summary>
    public static string BothMenus(ClassNoun noun) =>
        string.Join(" and ", Enum.GetValues<Menu>().Select(menu => Title(menu, noun)));

    /// <summary>
    /// Where an item is, the way the trail says it: "Classes ▸ Class Dates…"
    /// ("Meetings ▸ Class Dates…" in a club). The menu's title comes from the
    /// layout, so the path moves with the item.
    /// </summary>
    public static string Path(Item item, string title, ClassNoun noun) =>
        MenuContaining(item) is { } menu ? $"{Title(menu, noun)} ▸ {title}" : title;
}

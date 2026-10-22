using System.Collections.Generic;
using System.Linq;

namespace Plantoir.Core.Assist;

/// <summary>
/// The plan's one-page pieces and the Section menu's plan table (#548, the
/// mac's #524).
/// </summary>
/// <remarks>
/// <para><see cref="PublishPlan.Describe"/> says each change as "“Bananas”
/// will become visible." and each page an unpublish keeps as "“Ohm's Law”
/// stays visible, because …"; the menu's table (<see cref="PlanTable"/>) shows
/// the same piece in a cell, without the page's name. ONE member for each, so
/// the card and the table are made of the same pieces and cannot drift. The
/// pieces moved here out of inline literals in <c>Describe()</c> byte for byte
/// (measured before and after, <c>documentation/12-windows-app.md</c> → "The
/// plan as a table").</para>
///
/// <para>The <c>…ForAMeeting</c>, <c>…Hiding</c> and <c>…OnePage</c> keys are
/// shapes of <see cref="MenuPlanStaysAsItIs"/> and <see cref="MenuPlanSummary"/>.
/// Each is a member of the key's own name that the dispatcher really returns,
/// the convention <c>PagesWhoseSettingsCannotBeAddedTo</c> → <c>…NamingSeveral</c>
/// already set; <c>ContractTests.AssistWording_MatchesContract</c> compares the
/// constants by value and renders the methods through the dispatcher.</para>
/// </remarks>
public static partial class AssistWording
{
    // ---- The plan's one-page pieces ---------------------------------------------

    /// <summary>"will become visible" — a page a publish shows.</summary>
    public const string PlanWillBecomeVisible = "will become visible";

    /// <summary>"will become hidden" — a page an unpublish takes down.</summary>
    public const string PlanWillBecomeHidden = "will become hidden";

    /// <summary>A plan in which no page would change.</summary>
    public const string PlanNothingWouldChange = "No page's visibility would change.";

    /// <summary>
    /// "will become visible, with the same date as “Unit 4, Day 24”" — once for
    /// each class whose date the page takes, in the plan's order.
    /// </summary>
    public static string PlanWillBecomeVisibleWithTheDateOf(IReadOnlyList<string> classes) =>
        PlanWillBecomeVisible + WithTheSameDateAs(classes);

    /// <summary>
    /// The mac's <c>planWillBecome(visible:withTheDatesOf:)</c>: one of the
    /// pieces above, then every class whose date the page takes. Keyless —
    /// <c>ContractTests</c>' <c>WindowsOnlyWording</c> says why.
    /// </summary>
    public static string PlanWillBecome(bool visible, IReadOnlyList<string> withTheDatesOf) =>
        !visible ? PlanWillBecomeHidden + WithTheSameDateAs(withTheDatesOf)
        : withTheDatesOf.Count == 0 ? PlanWillBecomeVisible
        : PlanWillBecomeVisibleWithTheDateOf(withTheDatesOf);

    /// <summary>"stays visible, because " and a reason that ends with its own full stop.</summary>
    public static string PlanStaysVisibleBecause(string reason) => $"stays visible, because {reason}";

    // Private, so the contract's reverse walk (public static only) never sees it.
    private static string WithTheSameDateAs(IReadOnlyList<string> classes) =>
        string.Concat(classes.Select(takenFrom => $", with the same date as “{takenFrom}”"));

    // ---- The Section menu's plan table --------------------------------------------

    public const string MenuPlanPageColumn = "Page";
    public const string MenuPlanFolderColumn = "Folder";
    public const string MenuPlanChangeColumn = "What changes";

    /// <summary>A page already the way it was asked to be.</summary>
    public const string MenuPlanAlreadyVisible = "already visible";

    /// <summary>A page already the way it was asked to be.</summary>
    public const string MenuPlanAlreadyHidden = "already hidden";

    /// <summary>
    /// A page whose settings have no room for a key — the row beside the
    /// no-room sentence, which names a few of them and says where to set them.
    /// </summary>
    public const string MenuPlanStaysExactlyAsItIs = "stays exactly as it is, because Plantoir cannot add to its settings.";

    /// <summary>
    /// A class a publish followed a link onto and left alone, as the card says
    /// it: "stays as it is", never "stays hidden" — a linked class whose flag
    /// this app will not read is listed too, and that page counts as visible.
    /// </summary>
    public const string MenuPlanStaysAsItIs = "stays as it is, because it is a class of its own.";

    /// <summary><see cref="MenuPlanStaysAsItIs"/> in a club.</summary>
    public const string MenuPlanStaysAsItIsForAMeeting = "stays as it is, because it is a meeting of its own.";

    /// <summary>The summary when one page changes and none is already right.</summary>
    public const string MenuPlanSummaryOnePage = "1 page would change.";

    /// <summary>
    /// The line above the table: "8 pages would change, 8 already visible."
    /// Counts the pages that change and the pages already the way asked; the
    /// pages an unpublish keeps are rows of their own, with their reason.
    /// </summary>
    public static string MenuPlanSummary(int changing, int already, bool publishing)
    {
        if (changing == 0) return PlanNothingWouldChange;
        if (changing == 1 && already == 0) return MenuPlanSummaryOnePage;
        string word = changing == 1 ? "page" : "pages";
        if (already == 0) return $"{changing} {word} would change.";
        return publishing ? $"{changing} {word} would change, {already} already visible."
                          : MenuPlanSummaryHiding(changing, already);
    }

    /// <summary>
    /// The disclosure under the plan table (#634, the mac's #622), closed to
    /// begin with: opening it adds the pages already the way they were asked
    /// to be to the same table. The mac's <c>menuPlanShowAlready(count:publishing:)</c>;
    /// it returns <see cref="MenuPlanShowAlreadyHiding"/>,
    /// <see cref="MenuPlanShowAlreadyOnePage"/> and <see cref="MenuPlanShowAlreadyOnePageHiding"/>,
    /// the members the contract's other three keys name.
    /// </summary>
    public static string MenuPlanShowAlready(int count, bool publishing)
    {
        if (count == 1) return publishing ? MenuPlanShowAlreadyOnePage : MenuPlanShowAlreadyOnePageHiding;
        return publishing ? $"Show the {count} pages already visible" : MenuPlanShowAlreadyHiding(count);
    }

    /// <summary><see cref="MenuPlanShowAlready"/> for a hide plan of more than one page already hidden.</summary>
    public static string MenuPlanShowAlreadyHiding(int count) => $"Show the {count} pages already hidden";

    /// <summary><see cref="MenuPlanShowAlready"/> for one page already visible.</summary>
    public const string MenuPlanShowAlreadyOnePage = "Show the page already visible";

    /// <summary><see cref="MenuPlanShowAlready"/> for one page already hidden.</summary>
    public const string MenuPlanShowAlreadyOnePageHiding = "Show the page already hidden";

    /// <summary><see cref="MenuPlanSummary"/> for a hide plan with pages already hidden.</summary>
    public static string MenuPlanSummaryHiding(int changing, int already) =>
        $"{changing} {(changing == 1 ? "page" : "pages")} would change, {already} already hidden.";
}

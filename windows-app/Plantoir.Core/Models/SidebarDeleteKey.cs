using Item = Plantoir.Core.Models.SubjectMenuRules.Item;
using Row = Plantoir.Core.Models.SubjectMenuRules.Row;

namespace Plantoir.Core.Models;

/// <summary>
/// Delete on a selected sidebar row, and the sidebar's − button (#491 items 5
/// and 6; <c>contracts/shared-rules.json</c> → <c>sidebarDeleteKey</c>, run by
/// <c>SidebarDeleteKeyContractTests</c>; the mac's <c>SubjectMenuRules.deleteKeyItem</c>
/// / <c>minusButtonItem</c>). Each RUNS a menu item, so its enablement is the
/// menu's (<see cref="SubjectMenuRules.Enabled"/>) and its question is the
/// menu's; where the item is greyed, nothing happens.
/// </summary>
public static class SidebarDeleteKey
{
    /// <summary>The item the Delete key runs on a row of this kind, or null (a group row, All Backups, nothing selected).</summary>
    public static Item? ItemFor(Row row) => row switch
    {
        Row.Course => Item.RemoveCourse,
        Row.Section => Item.RemoveSection,
        Row.Backup => Item.DeleteBackup,
        Row.Archived => Item.DeleteArchive,
        _ => null,
    };

    /// <summary>
    /// The item the − button runs: removal only. A backup or an archive is
    /// DELETED for good, which the − button never offers (the mac greys it
    /// there); only the Delete key and the row's own menu reach those.
    /// </summary>
    public static Item? MinusButtonItem(Row row) => row switch
    {
        Row.Course => Item.RemoveCourse,
        Row.Section => Item.RemoveSection,
        _ => null,
    };

    /// <summary>Whether the − button can be pressed: its item exists for the row and the menu would allow it.</summary>
    public static bool MinusButtonIsEnabled(SubjectMenuRules.Situation situation) =>
        MinusButtonItem(situation.Row) is { } item && SubjectMenuRules.Enabled(situation).Contains(item);

    /// <summary>The kind of row a sidebar selection is; the Backups group's own row is All Backups.</summary>
    public static Row RowOf(SidebarSelection? selection, bool isTheBackupsGroup) =>
        isTheBackupsGroup ? Row.AllBackups : selection switch
        {
            SidebarSelection.CourseItem => Row.Course,
            SidebarSelection.SectionItem => Row.Section,
            SidebarSelection.BackupEntry => Row.Backup,
            SidebarSelection.ArchivedEntry => Row.Archived,
            _ => Row.None,
        };
}

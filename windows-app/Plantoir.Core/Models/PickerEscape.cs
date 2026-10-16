namespace Plantoir.Core.Models;

/// <summary>
/// Escape is never trapped (#491 item 1; the mac's <c>PickerEscape.result(listWasOpen:)</c>).
/// A field with a drawn list (Copy a Page's page field, the wizard's Course
/// code) takes Escape ONLY while its list is open — that press closes the list
/// — and otherwise the press belongs to the dialog, which closes as Cancel would.
/// </summary>
/// <remarks>
/// MEASURED in WinUI (batch 3's spike, i5-8365U, Windows 11 26200, Windows App
/// SDK 1.8.260921001): an AutoSuggestBox inside a ContentDialog TRAPS Escape.
/// With its list closed, the inner TextBox marks Escape handled and a second
/// Escape is swallowed too; with it open, the first closes the list and the
/// second is swallowed. A ComboBox already behaves (closed: Escape closes the
/// dialog; open: the first closes the drop-down, the second the dialog), so
/// only the two AutoSuggestBoxes route through this.
/// </remarks>
public static class PickerEscape
{
    public enum Result
    {
        /// <summary>The list is drawn: this press closes it, and the dialog stays.</summary>
        CloseTheList,

        /// <summary>No list: the press goes to the dialog, which closes as Cancel would.</summary>
        LetTheDialogHaveIt,
    }

    public static Result For(bool listWasOpen) => listWasOpen ? Result.CloseTheList : Result.LetTheDialogHaveIt;
}

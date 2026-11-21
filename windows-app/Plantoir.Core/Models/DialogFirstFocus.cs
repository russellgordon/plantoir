namespace Plantoir.Core.Models;

/// <summary>
/// Which focus move a dialog may redirect to the box it opens in (#1024,
/// Class Dates; review 2's L4). Only the dialog's own first placement is
/// moved: the first move that comes into the dialog from outside it, lands
/// where the dialog itself puts its first focus, and was made neither by the
/// person's pointer nor by a key that moves focus in a direction (Tab,
/// Shift-Tab, an arrow). If the dialog opened without placing focus, the
/// person's own first click or key is that first move, and it is left where
/// they sent it. Every later move is left alone, whoever makes it. The view
/// reads the WinUI facts (<c>GettingFocusEventArgs</c>) into these flags; the
/// rule lives here so it can be tested without a window.
/// </summary>
public static class DialogFirstFocus
{
    /// <summary>Whether this focus move is the dialog's own first placement, the one move it may send to its box.</summary>
    public static bool IsTheDialogsOwnFirstPlacement(
        bool theFirstFocusHasArrived,
        bool landsInTheDialog,
        bool comesFromInsideTheDialog,
        bool landsWhereTheDialogPlacesItsFirstFocus,
        bool madeByThePersonsPointer,
        bool madeByAKeyThatMovesFocus)
    {
        if (theFirstFocusHasArrived) return false;
        if (!landsInTheDialog || comesFromInsideTheDialog) return false;
        if (!landsWhereTheDialogPlacesItsFirstFocus) return false;
        if (madeByThePersonsPointer || madeByAKeyThatMovesFocus) return false;
        return true;
    }

    /// <summary>Whether this focus move is the first to come into the dialog from outside it, whoever made it.</summary>
    public static bool IsTheFirstMoveIntoTheDialog(bool theFirstFocusHasArrived, bool landsInTheDialog, bool comesFromInsideTheDialog)
    {
        return !theFirstFocusHasArrived && landsInTheDialog && !comesFromInsideTheDialog;
    }
}

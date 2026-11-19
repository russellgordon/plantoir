namespace Plantoir.Core.Models;

/// <summary>How a dialog's main button may take Enter (#491 item 2).</summary>
public enum PrimaryKind
{
    /// <summary>The usual main button: the default (accent, Enter presses it) exactly while it can be pressed.</summary>
    TakesEnterWhenEnabled,

    /// <summary>
    /// Not the default and no accent, enabled or not: the new-course wizard's
    /// Create Course while <see cref="QuestionKeys.CreateCourseIsTheDefault"/>
    /// says no (its form not complete yet, or its code list drawn). The #979
    /// review, as #987 did on the mac ("The accent comes off while it is not
    /// the default or cannot be pressed"): a button in the accent that Enter
    /// does not press looks like the default and is not. Apple's HIG, Buttons:
    /// the default button is the one drawn prominent, and pressing Return
    /// activates it. Until #979 this was a kind that wore the accent without
    /// taking Enter. Measured on the mac (2026-10-08): as the default from
    /// the start, an Enter typed in the Course code field created a course
    /// named by the code with the rest of the form unread.
    /// </summary>
    NotTheDefaultYet,

    /// <summary>
    /// Not the dialog's default at all, enabled or not — All Backups' Delete…,
    /// a destructive button beside a Close that stays the default. Only its
    /// enablement changes.
    /// </summary>
    NotTheDefault,
}

/// <summary>What the dialog's default button should be after a change.</summary>
public enum DefaultChoice
{
    /// <summary>The main button is the default: it draws the accent and Enter presses it.</summary>
    Primary,

    /// <summary>No button is the default: nothing is drawn as one and Enter in a field presses nothing.</summary>
    None,

    /// <summary>Leave the dialog's default as it is (a Close that is the default stays so).</summary>
    Keep,
}

/// <summary>
/// The one rule for a ContentDialog's main button (#491 item 2; the mac's
/// <c>.defaultButton(isEnabled:)</c> / <c>.prominentButton(isEnabled:)</c>):
/// a button that cannot be pressed never looks like the default.
/// </summary>
/// <remarks>
/// MEASURED in WinUI (batch 3's spike, i5-8365U, Windows 11 26200, 150%,
/// Windows App SDK 1.8.260921001): a DISABLED button that is still the
/// dialog's default keeps the accent slab — #BFBFBF with white text in Light
/// (about 1.8:1), #434343 with #A7A7A7 text in Dark — and so still reads as
/// the primary slot, where a disabled plain button is #F5F5F5 on #F3F3F3
/// (Light) or #2A2A2A on #202020 (Dark). Worse, in a dialog with no
/// focusable content that same disabled default loses its accent, initial
/// focus lands on Close, and Enter dismisses the dialog. So while disabled the
/// button is NOT the default and carries no accent style; when it can be
/// pressed it is the default again (or, for <see cref="PrimaryKind.NotTheDefaultYet"/>,
/// stays plain and not the default). No kind wears the accent without being
/// the default (#979 review).
/// </remarks>
public static class PrimaryButtonLook
{
    /// <param name="Default">What the dialog's DefaultButton becomes.</param>
    /// <param name="AccentStyle">Whether the button is given the accent STYLE explicitly — needed only
    /// when it wears the accent without being the default (WinUI draws the default in the accent itself).</param>
    public sealed record Look(DefaultChoice Default, bool AccentStyle);

    public static Look For(bool enabled, PrimaryKind kind) => kind switch
    {
        PrimaryKind.TakesEnterWhenEnabled => new Look(enabled ? DefaultChoice.Primary : DefaultChoice.None, false),
        PrimaryKind.NotTheDefaultYet => new Look(DefaultChoice.None, false),
        _ => new Look(DefaultChoice.Keep, false),
    };
}

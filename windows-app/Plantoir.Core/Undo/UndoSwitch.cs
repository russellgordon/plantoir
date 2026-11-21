namespace Plantoir.Core.Undo;

/// <summary>
/// The one switch for Undo and Redo as one list for the whole app (#899 W4;
/// the mac's <c>UndoSwitch</c>).
///
/// <para><b>Off until every action is on the list.</b> Each piece merges on
/// its own behind it, and while it is off the list is written in SHADOW
/// (<c>rule.shadow</c>): whatever is recorded is never offered back to the
/// teacher, a failure to write the list never stops, slows noticeably or
/// alters the action, and recovery never writes into a working folder. Nothing
/// a teacher sees changes. W11a flips it, and only once the writer scan
/// (<c>UndoWriterScanTests</c>) has no <c>waitsFor</c> left:
/// <c>TheSwitchStaysOffWhileWritersWait</c> fails otherwise.</para>
///
/// <para><b>Why a field and not a setting.</b> A half-covered Undo is worse
/// than none, because the step it passes over silently is the one a teacher
/// needed back; nobody may turn it on early, from a test, a command line or
/// the settings file. <see cref="UndoJournalIsLive"/> is read in ONE place, <see cref="UndoForThisProcess"/>,
/// the composition root, which hands the mode to every journal and door it
/// makes (the plan review's H1: a test passes its own mode, never this).
/// <c>static readonly</c> rather than <c>const</c> only so that the code
/// behind a live switch is compiled and checked today without an
/// unreachable-code warning.</para>
/// </summary>
internal static class UndoSwitch
{
    /// <summary>False: the list is written in shadow and never offered.</summary>
    internal static readonly bool UndoJournalIsLive = false;

    /// <summary>
    /// Whether an Undo refused because content it needs is missing clears the
    /// list after saying so once, as a page changed by hand does (ruling 22;
    /// built before it as held question M9's recommended answer). Content
    /// that is missing never comes back, so otherwise the newest step would be
    /// offered and refused on every try until it aged out. A Redo refused this
    /// way drops only its redo branch either way (ruling 20).
    /// </summary>
    internal static readonly bool UndoRefusedForMissingContentClearsTheList = true;

    /// <summary>The mode the app's processes record in, read from the switch.</summary>
    internal static UndoMode CurrentMode => UndoJournalIsLive ? UndoMode.Live : UndoMode.Shadow;
}

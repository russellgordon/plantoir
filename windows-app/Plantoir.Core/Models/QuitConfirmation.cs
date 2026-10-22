namespace Plantoir.Core.Models;

/// <summary>
/// Whether quitting Plantoir asks first (#231, mac #220/#232;
/// <c>shared-rules.json</c> → <c>quittingWhileWorkIsUnderWay</c>).
/// </summary>
/// <remarks>
/// <para><b>Decided by Russell, 2026-09-25: match all three.</b> Quitting asks
/// when THIS app is in the middle of publishing or of BUILDING a preview; never
/// when a preview is merely open (its port is held for as long as it is open,
/// so it cannot tell a building section from one finished twenty minutes ago,
/// and asking on every quit teaches a teacher to dismiss the question unread);
/// and NEVER when Windows itself is logging off, restarting or shutting down,
/// where a question holds the whole session up until Windows names Plantoir as
/// the program that would not close. A publish is named before a preview build
/// when both are under way, because its loss reaches the class website.</para>
///
/// <para>Quitting on Windows is closing the LAST window. "Quit Anyway" does not
/// END the publish — the app does not set out to kill a teacher's work — but
/// its console goes with the window, so the sentence says it COULD be left
/// unfinished and promises neither outcome, as the mac's does.</para>
///
/// <para>A copy of a course being zipped (#351) is counted too, but this app
/// zips on the window's own thread today, so a quit cannot land mid-zip and
/// the count is always zero here.</para>
/// </remarks>
public static class QuitConfirmation
{
    /// <summary>Who asked for the quit.</summary>
    public enum Reason
    {
        /// <summary>The teacher closed the last window.</summary>
        TheTeacherAskedToQuit,

        /// <summary>Windows is logging off, restarting or shutting down (WM_QUERYENDSESSION).</summary>
        TheSystemIsEnding,
    }

    /// <summary>
    /// Why Plantoir closed, for the trail's <c>app closed</c> line (#565, mac
    /// #560). Finer than <see cref="Reason"/>: the question cares only whether
    /// Windows is ending the session, the trail also whether an install did it.
    /// </summary>
    public enum ClosingReason
    {
        /// <summary>The teacher closed the last window — including with an update ready, which installs as Plantoir quits: that quit is still theirs.</summary>
        ByTheTeacher,

        /// <summary>
        /// Plantoir's updater started the installer and quit for it
        /// (<c>App.QuitForUpdate</c>), or the installer closed Plantoir
        /// through Restart Manager: <c>WM_QUERYENDSESSION</c> /
        /// <c>WM_ENDSESSION</c> carrying <c>ENDSESSION_CLOSEAPP</c>
        /// (installer.iss <c>CloseApplications=yes</c>).
        /// </summary>
        ToInstallANewVersion,

        /// <summary>Windows is logging off, restarting or shutting down: the end-of-session messages WITHOUT <c>ENDSESSION_CLOSEAPP</c>.</summary>
        AskedByWindows,
    }

    /// <summary>The words on the trail, after "Plantoir closed — ".</summary>
    public static string Words(ClosingReason reason) => reason switch
    {
        ClosingReason.ToInstallANewVersion => "to install a new version",
        ClosingReason.AskedByWindows => "asked to close by Windows",
        _ => "quit by the teacher",
    };

    /// <summary><c>ENDSESSION_CLOSEAPP</c>: the lParam bit Restart Manager sets when it closes ONE application, as an installer asks it to.</summary>
    public const long EndSessionCloseApp = 0x1;

    /// <summary>Which reason a close is, from what the app knew at that moment. Installing wins: the updater's own exit, or Restart Manager closing this app for an installer.</summary>
    public static ClosingReason ClosingReasonFor(bool quittingForTheUpdater, bool sessionEnding, long endSessionFlags) =>
        quittingForTheUpdater || (sessionEnding && (endSessionFlags & EndSessionCloseApp) != 0)
            ? ClosingReason.ToInstallANewVersion
            : sessionEnding ? ClosingReason.AskedByWindows : ClosingReason.ByTheTeacher;

    /// <summary>What this app has under way at the moment of the quit.</summary>
    public sealed record UnderWay(int Publishes, int PreviewsOpen, int PreviewsBeingBuilt, int CopiesBeingSaved);

    /// <summary>The whole rule; the contract's cases run straight through it.</summary>
    public static bool ShouldAsk(UnderWay underWay, Reason reason) =>
        reason == Reason.TheTeacherAskedToQuit
        && (underWay.Publishes > 0 || underWay.PreviewsBeingBuilt > 0 || underWay.CopiesBeingSaved > 0);

    /// <summary>What is named, in the words the question uses — the publish first.</summary>
    public static string WhatIsUnderWay(UnderWay underWay) =>
        underWay.Publishes > 0 ? "a deploy"
        : underWay.PreviewsBeingBuilt > 0 ? "a preview being built"
        : "a copy of a course being saved";

    /// <summary>The question's title and its explanation.</summary>
    public static (string Title, string Message) Question(UnderWay underWay) =>
        underWay.Publishes > 0
            ? (underWay.Publishes == 1 ? "A deploy is still going" : "Deploys are still going",
               "Quitting now could leave it unfinished, and the class website may not get the new pages. " +
               "Keep working to let it finish.")
            : underWay.PreviewsBeingBuilt > 0
                ? ("A preview is still being built",
                   "Quitting now could leave it unfinished. Nothing on the class website changes.")
                : ("A copy of a course is still being saved",
                   "Quitting now could leave the copy unfinished. Nothing on the class website changes.");

    public const string KeepWorking = "Keep Working";
    public const string QuitAnyway = "Quit Anyway";

    /// <summary>The trail's line: what was under way, and which button was pressed.</summary>
    public static string TrailLine(UnderWay underWay, bool quitAnyway) =>
        $"asked before quitting with {WhatIsUnderWay(underWay)} under way — the teacher chose " +
        (quitAnyway ? QuitAnyway : KeepWorking);
}

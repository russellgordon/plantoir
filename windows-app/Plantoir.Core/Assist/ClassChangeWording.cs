using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// What the assistant says about duplicating a class, and about a change that
/// moved other classes along to make room for one.
///
/// <para><b>These are contract keys now</b> — <c>contracts/assist-wording.json</c>
/// carries them since the mac's #163 (Windows #200), and
/// <c>ContractTests.AssistWording_MatchesContract</c> finds each one by name on
/// this class or on <see cref="AssistWording"/>. They stay in their own class
/// because that is where Windows gathered them first and where a Windows
/// session looks for them; the words are the mac's, and
/// <c>DuplicationWordingTests</c> pins every rendering against the contract.
/// (Until bundle 2 this comment said the opposite — that no key could be made
/// from Windows. That stopped being true when the mac made them.)</para>
///
/// <para>Where Windows says more than the contract pins, it is named in the
/// member's own remarks.</para>
/// </summary>
public static class ClassChangeWording
{
    // ---- Duplicating a class ----------------------------------------------

    /// <summary>The one line a teacher reads in the chat when a copy is made.</summary>
    public static string Duplicated(string sourceTitle, string newTitle) =>
        $"Duplicated “{sourceTitle}” as “{newTitle}”.";

    /// <summary>What the copy is, where it landed, and that nobody can see it yet.</summary>
    public static string CopiedTo(string sourceTitle, string newTitle, DateOnly date) =>
        $"“{sourceTitle}” was copied to “{newTitle}”, dated {DateText.Iso(date)}. It is hidden, so nothing " +
        "changed on the site — write it, then publish when it is ready.";

    /// <summary>The same fact in the future tense, for the plan a teacher agrees to.</summary>
    public static string WouldBeCopiedTo(string sourceTitle, string newTitle, DateOnly date) =>
        $"“{sourceTitle}” would be copied to “{newTitle}”, dated {DateText.Iso(date)}.";

    /// <summary>Said in the plan, because "hidden" is the part a teacher would otherwise have to ask about.</summary>
    public const string TheCopyStartsHidden =
        "The copy starts hidden, so nothing changes on the site until you publish it.";

    // ---- What else moves ---------------------------------------------------

    /// <summary>
    /// What a plan says about the classes that would move along to make room.
    ///
    /// <para>Counted from renames AND date moves (the union, once each) — the
    /// shape Windows proposed on #163 and the mac adopted.</para>
    /// </summary>
    /// <param name="moving">How many other class pages move, counted once each.</param>
    /// <param name="renaming">How many of those are also renamed.</param>
    public static string OtherClassesWouldMove(int moving, int renaming) => renaming > 0
        ? OtherClassesWouldMoveAndLinksFollow(moving)
        : OtherClassesWouldMoveKeepingTheirNames(moving);

    /// <summary>The contract's <c>otherClassesWouldMoveAndLinksFollow</c>.</summary>
    public static string OtherClassesWouldMoveAndLinksFollow(int moving)
    {
        string verb = moving == 1 ? "class moves" : "classes move";
        return $"{moving} later {verb} a day along to make room, and the links that point at them " +
               "are rewritten to match.";
    }

    /// <summary>
    /// The contract's <c>otherClassesWouldMoveKeepingTheirNames</c>. Nothing is
    /// renamed, so nothing links anywhere new — but the dates still move.
    /// Windows' singular ("Its name does") is a platform extra; the contract
    /// pins the plural.
    /// </summary>
    public static string OtherClassesWouldMoveKeepingTheirNames(int moving)
    {
        string verb = moving == 1 ? "class moves" : "classes move";
        string theirs = moving == 1 ? "Its name does" : "Their names do";
        return $"{moving} later {verb} onto a later class day to make room. {theirs} not change.";
    }

    /// <summary>
    /// Said after a change that shuffled other classes: the undo list cannot
    /// take this back, and the backup is what can.
    ///
    /// <para>A partial undo — the new page deleted, every later class left
    /// renamed and re-dated — is worse than no undo at all, so the way back is
    /// named instead. With no path this is the contract's
    /// <c>otherClassesMoved</c>; naming the FILE is a Windows extra, because a
    /// teacher looking at a list of five is better off with the name.</para>
    /// </summary>
    public static string OtherClassesMoved(string? backupPath)
    {
        string where = string.IsNullOrEmpty(backupPath)
            ? "The copy made before any of it is in Plantoir's Backups list."
            : $"The copy made before any of it is {Path.GetFileName(backupPath)}, in Plantoir's Backups list.";
        return "Because other classes moved, “Undo that” will not take this back. " + where;
    }

    // ---- Refusals ----------------------------------------------------------

    /// <summary>
    /// A page that is not "Unit N, Day N" has no next day to become. The mac's
    /// shorter sentence since #200; Windows' used to add "— a copy can only
    /// become the next day of a unit that has numbered days".
    /// </summary>
    public static string NotANumberedClassPage(string title) =>
        $"“{title}” isn’t a numbered class page, so there is no next day for it to become.";

    /// <summary>The source page is there and cannot be read. (Not a contract key; the mac says "could not be read".)</summary>
    public static string CouldNotBeRead(string title) =>
        $"“{title}” couldn’t be read, so nothing was changed.";

    /// <summary>The timetable has run out before the copy could be given a day.</summary>
    public const string NoClassDateLeft = "There is no class date left for another class.";

    /// <summary>
    /// The copy's place is still occupied, so nothing was written over it.
    /// </summary>
    /// <remarks>
    /// Said AFTER the room has been made, so it admits to half a job: "Nothing
    /// was copied, but other classes may already have moved" (#200 C). The
    /// form with no backup can promise a copy that does not exist when the
    /// backup itself failed; the mac left it that way deliberately (#200).
    /// </remarks>
    public static string ThePlaceForTheCopyIsStillTaken(string newTitle, string? backupPath) =>
        $"“{newTitle}” is still there — the class that had to move out of the way did not, and I " +
        "will not write over a lesson. Nothing was copied, but other classes may already have moved. " +
        $"{TheCourseCopy(backupPath)} Look the section over in Plantoir.";

    /// <summary>The contract's <c>thePlaceForTheCopyIsStillTakenNamingTheBackup</c>.</summary>
    public static string ThePlaceForTheCopyIsStillTakenNamingTheBackup(string newTitle, string backupPath) =>
        ThePlaceForTheCopyIsStillTaken(newTitle, backupPath);

    /// <summary>
    /// The copy was abandoned because it could not be made certainly hidden
    /// (#200 B): the source's block has a tab used as indentation, or no
    /// column-0 place for a key. Says what the teacher is LEFT with — a hidden
    /// blank page on that day, and possibly moved classes.
    /// </summary>
    public static string TheCopyCouldNotBeMadeHidden(string sourceTitle, string newTitle, string? backupPath) =>
        $"“{sourceTitle}” was not copied — I could not be certain the copy would start hidden, and a lesson " +
        "students can already see must not turn up somewhere new where they can read it. " +
        $"A blank class page called “{newTitle}” is waiting on that day instead, and it is hidden. " +
        $"Other classes may already have moved. {TheCourseCopy(backupPath)} Look the section over in Plantoir.";

    /// <summary>The contract's <c>theCopyCouldNotBeMadeHiddenNamingTheBackup</c>.</summary>
    public static string TheCopyCouldNotBeMadeHiddenNamingTheBackup(string sourceTitle, string newTitle, string backupPath) =>
        TheCopyCouldNotBeMadeHidden(sourceTitle, newTitle, backupPath);

    private static string TheCourseCopy(string? backupPath) => string.IsNullOrEmpty(backupPath)
        ? "The copy of the course made before any of this is in Plantoir's Backups list."
        : $"The copy of the course made before any of this is {Path.GetFileName(backupPath)}, in Plantoir's Backups list.";
}

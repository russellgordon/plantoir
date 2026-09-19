namespace Plantoir.Core.Assist;

/// <summary>
/// What the assistant says about duplicating a class, and about a change that
/// moved other classes along to make room for one.
///
/// <para><b>Why these are here and not in <see cref="AssistWording"/>.</b>
/// <c>AssistWording</c> mirrors <c>contracts/assist-wording.json</c>, which is
/// GENERATED from the mac and must not gain keys from this side. The mac words
/// these sentences INLINE in <c>AssistToolRunner.duplicateClassRequested</c>
/// and <c>makeRoomForClasses</c>, so there is no contract key to mirror and no
/// way to make one from Windows. They are gathered in one named place anyway,
/// so that a mac session can quote the NAMES rather than retyping the
/// sentences, and so the reply and the plan cannot drift apart here.</para>
///
/// <para>Every sentence is as close to the mac's as the two surfaces allow.
/// Where Windows says more, it is named in the member's own remarks.</para>
/// </summary>
public static class ClassChangeWording
{
    // ---- Duplicating a class ----------------------------------------------

    /// <summary>The one line a teacher reads in the chat when a copy is made.</summary>
    public static string Duplicated(string sourceTitle, string newTitle) =>
        $"Duplicated “{sourceTitle}” as “{newTitle}”.";

    /// <summary>What the copy is, where it landed, and that nobody can see it yet.</summary>
    public static string CopiedTo(string sourceTitle, string newTitle, DateOnly date) =>
        $"“{sourceTitle}” was copied to “{newTitle}”, dated {date:yyyy-MM-dd}. It is hidden, so nothing " +
        "changed on the site — write it, then publish when it is ready.";

    /// <summary>The same fact in the future tense, for the plan a teacher agrees to.</summary>
    public static string WouldBeCopiedTo(string sourceTitle, string newTitle, DateOnly date) =>
        $"“{sourceTitle}” would be copied to “{newTitle}”, dated {date:yyyy-MM-dd}.";

    /// <summary>Said in the plan, because "hidden" is the part a teacher would otherwise have to ask about.</summary>
    public const string TheCopyStartsHidden =
        "The copy starts hidden, so nothing changes on the site until you publish it.";

    /// <summary>The summary line of the plan.</summary>
    public static string WorkedOutWhatDuplicatingWouldDo(string sourceTitle) =>
        $"Worked out what duplicating “{sourceTitle}” would do.";

    // ---- What else moves ---------------------------------------------------

    /// <summary>
    /// What a plan says about the classes that would move along to make room.
    ///
    /// <para><b>Counted from renames AND date moves, which is where this
    /// departs from the mac.</b> <c>AssistToolRunner</c> writes this line only
    /// when <c>renames.isEmpty</c> is false — and renames happen only WITHIN
    /// the unit being changed (<c>AssistWorkspace.PlanInsertClasses</c> renames
    /// nothing outside it). Duplicating the LAST day of a unit therefore
    /// renames nothing while re-dating every class of every later unit, and the
    /// mac's plan says not one word about it. A teacher who agreed to that plan
    /// agreed to something smaller than what ran.</para>
    /// </summary>
    /// <param name="moving">How many other class pages move, counted once each.</param>
    /// <param name="renaming">How many of those are also renamed.</param>
    public static string OtherClassesWouldMove(int moving, int renaming)
    {
        string verb = moving == 1 ? "class moves" : "classes move";
        if (renaming > 0)
            return $"{moving} later {verb} a day along to make room, and the links that point at them " +
                   "are rewritten to match.";

        // Nothing is renamed, so nothing links anywhere new — but the dates
        // still move, and that is the half the mac's line leaves out.
        string theirs = moving == 1 ? "Its name does" : "Their names do";
        return $"{moving} later {verb} onto a later class day to make room. {theirs} not change.";
    }

    /// <summary>
    /// Said after a change that shuffled other classes: the undo list cannot
    /// take this back, and the backup is what can.
    ///
    /// <para>A partial undo — the new page deleted, every later class left
    /// renamed and re-dated — is worse than no undo at all, so the way back is
    /// named instead. Windows names the FILE; the mac says "in Plantoir's
    /// Backups list" without it, and a teacher looking at a list of five is
    /// better off with the name.</para>
    /// </summary>
    public static string OtherClassesMoved(string? backupPath)
    {
        string where = string.IsNullOrEmpty(backupPath)
            ? "The copy made before any of it is in Plantoir's Backups list."
            : $"The copy made before any of it is {Path.GetFileName(backupPath)}, in Plantoir's Backups list.";
        return "Because other classes moved, “Undo that” will not take this back. " + where;
    }

    // ---- Refusals ----------------------------------------------------------

    /// <summary>A page that is not "Unit N, Day N" has no next day to become.</summary>
    public static string NotANumberedClassPage(string title, string unitWord) =>
        $"“{title}” isn’t a numbered class page — a copy can only become the next day of a " +
        $"{unitWord.ToLowerInvariant()} that has numbered days.";

    /// <summary>The source page is there and cannot be read.</summary>
    public static string CouldNotBeRead(string title) =>
        $"“{title}” couldn’t be read, so nothing was changed.";

    /// <summary>The timetable has run out before the copy could be given a day.</summary>
    public const string NoClassDateLeft = "There is no class date left for another class.";

    /// <summary>
    /// The copy's place is still occupied, so nothing was written over it.
    ///
    /// <para>The one case that could destroy a lesson. <c>ApplyInsertClasses</c>
    /// skips a rename whose destination already exists rather than overwriting
    /// it, which is right — but it leaves the page the copy was meant to become
    /// holding somebody's real class. Writing the copy there anyway would lose
    /// that lesson, so this refuses and points at the backup.</para>
    /// </summary>
    public static string ThePlaceForTheCopyIsStillTaken(string newTitle, string? backupPath)
    {
        string where = string.IsNullOrEmpty(backupPath)
            ? "The copy of the course made before any of this is in Plantoir's Backups list."
            : $"The copy of the course made before any of this is {Path.GetFileName(backupPath)}, " +
              "in Plantoir's Backups list.";
        return $"“{newTitle}” is still there — the class that had to move out of the way did not, and I " +
               $"will not write over a lesson. Nothing was copied. {where} Look the section over in Plantoir.";
    }
}

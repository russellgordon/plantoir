using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// The Section menu's sentences (#489, the mac's #457 batch B): the
/// assistant's functions reached from Section ▸ Publish Pages…, Hide Pages…,
/// Publish Class for a Date…, Rebuild Preview, Undo Last Change, Add Next
/// Class, Re-date Classes… and Make Room for Classes… — the same tool code,
/// called with a call built in code and never through a model
/// (<see cref="AssistSurface.Menu"/>).
/// </summary>
/// <remarks>
/// <para>What a teacher reads there is not a conversation: nobody said "undo
/// that", there is no "me" to ask again, and the way out of a change is a menu
/// item. So each sentence the tools can say in the first person, or about
/// asking, has a twin here ending <c>FromTheMenu</c>, chosen by the surface
/// (on the server, <c>AssistWorkspace.SpeaksFromTheMenu</c>). The
/// conversation's own sentences are unchanged, and so is every byte the model
/// is shown. Which sentences were twinned, and which were kept and why:
/// documentation/10-local-ai-assistant.md → "The Section menu, a third
/// client".</para>
///
/// <para>Every sentence is the contract's (<c>contracts/assist-wording.json</c>)
/// word for word; <c>ContractTests.AssistWording_MatchesContract</c> renders
/// each method with the generator's own example values. A day is written
/// "Monday, 2026-09-14" — the weekday and the ISO day, both invariant and
/// Gregorian (#144), never the machine's regional format.</para>
/// </remarks>
public static partial class AssistWording
{
    // ---- The tools' twins ---------------------------------------------------

    /// <summary>Make Room for Classes… could not finish changing one page (several: <see cref="PagesAChangeCouldNotFinishFromTheMenuNamingSeveral"/>).</summary>
    public static string PagesAChangeCouldNotFinishFromTheMenu(IReadOnlyList<string> pages) => pages.Count == 1
        ? $"“{pages[0]}” could not be finished, so look it over in Obsidian before it goes on your website."
        : PagesAChangeCouldNotFinishFromTheMenuNamingSeveral(pages);

    /// <summary>The same, for several pages: three named, then how many more.</summary>
    public static string PagesAChangeCouldNotFinishFromTheMenuNamingSeveral(IReadOnlyList<string> pages) =>
        $"{NamedFew(pages)} could not be finished, so look them over in Obsidian before they go on your website.";

    /// <summary>Undo Last Change worked.</summary>
    public static string UndidFromTheMenu(string whatHappened) =>
        $"Undone. Earlier, you {whatHappened}; that is put back now.";

    /// <summary>Undo Last Change put back some files and left the rest, edited since, alone.</summary>
    public static string UndidPartlyFromTheMenu(string whatHappened, int leftAlone)
    {
        string pages = leftAlone == 1 ? "one page was" : $"{leftAlone} pages were";
        return $"Earlier, you {whatHappened}. Everything that could be put back is put back — but {pages} left alone, because they have been edited since.";
    }

    /// <summary>Undo Last Change put nothing back: every file has been edited since.</summary>
    public static string CouldNotUndoFromTheMenu(string whatHappened, int leftAlone)
    {
        string pages = leftAlone == 1 ? "that page has" : $"those {leftAlone} pages have";
        return $"Earlier, you {whatHappened} — but nothing was undone, because {pages} been edited since. Putting the old copy back would throw away that newer work.";
    }

    /// <summary>After a partial or refused undo: the change is still the last one.</summary>
    public const string UndoIsStillAvailableFromTheMenu =
        "That change is still the last one, so Section ▸ Undo Last Change can take it back once you have dealt with the pages left alone.";

    /// <summary>
    /// Undo Last Change with nothing to undo — greyed in the menu, so this is
    /// said only when the change went away between drawing the menu and the click.
    /// </summary>
    public const string NothingToUndoFromTheMenu =
        "Nothing has been changed from the Section menu in this window yet, so there is nothing to undo. Anything older is in Plantoir's Backups list.";

    /// <summary>The section changed while its copy was being saved, so the plan no longer fits.</summary>
    public static string ChangedWhileSavingACopyFromTheMenu(string course, string section) =>
        $"Nothing was changed: {course} Section {section} changed while a copy of it was being saved, so the plan no longer fits. Choose the menu item again to see it as things are now.";

    /// <summary>One page whose settings could not be added to (several: the <c>NamingSeveral</c> twin).</summary>
    public static string PagesWhoseSettingsCannotBeAddedToFromTheMenu(IReadOnlyList<string> pages) => pages.Count == 1
        ? $"The settings at the top of “{pages[0]}” are written in a way Plantoir cannot add to, so that page stays exactly as it is. Open it in Obsidian to set it there."
        : PagesWhoseSettingsCannotBeAddedToFromTheMenuNamingSeveral(pages);

    /// <summary>Several pages whose settings could not be added to: three named, then how many more.</summary>
    public static string PagesWhoseSettingsCannotBeAddedToFromTheMenuNamingSeveral(IReadOnlyList<string> pages) =>
        $"The settings at the top of {NamedFew(pages)} are written in a way Plantoir cannot add to, so those pages stay exactly as they are. Open them in Obsidian to set them there.";

    /// <summary>A page a re-date or a make-room could not give its new date.</summary>
    public static string PageWhoseNewDateCouldNotBeSetFromTheMenu(string page) =>
        $"The new date could not be set on “{page}”: the settings at the top of it are written in a way Plantoir cannot add to. Open it in Obsidian to set the date there.";

    /// <summary>Several pages whose new dates could not be set.</summary>
    public static string PagesWhoseNewDatesCouldNotBeSetFromTheMenu(IReadOnlyList<string> pages) => pages.Count == 1
        ? PageWhoseNewDateCouldNotBeSetFromTheMenu(pages[0])
        : $"The new dates could not be set on {NamedFew(pages)}: the settings at the top of them are written in a way Plantoir cannot add to. Open them in Obsidian to set the dates there.";

    /// <summary>
    /// A page the list offered is not there any more — renamed, moved or
    /// removed in Obsidian between the list and the press. Named by the title
    /// the teacher ticked, never by the folder the call carried.
    /// </summary>
    public static string NoPageCalledFromTheMenu(string page, string course, string section) =>
        $"“{page}” is no longer in {course} Section {section} — it may have been renamed or moved since the list was shown. Choose the menu item again to see the pages as they are now.";

    /// <summary>The same, for two or more pages, already joined with "and".</summary>
    public static string NoPagesCalledFromTheMenu(string pages, string course, string section) =>
        $"{pages} are no longer in {course} Section {section} — they may have been renamed or moved since the list was shown. Choose the menu item again to see the pages as they are now.";

    /// <summary>Publish Class for a Date… on a day no class is dated.</summary>
    public static string NoClassOnFromTheMenu(DateOnly day, string course, string section) =>
        $"No class in {course} Section {section} is dated {MenuDay(day)}. Choose another day, or publish the page by its name with Section ▸ Publish Pages….";

    /// <summary>The same, in a club.</summary>
    public static string NoClassOnFromTheMenuForAMeeting(DateOnly day, string course, string section) =>
        $"No meeting in {course} Section {section} is dated {MenuDay(day)}. Choose another day, or publish the page by its name with Section ▸ Publish Pages….";

    /// <summary>Rebuild Preview while a copy of the course is being saved.</summary>
    public static string CourseIsBeingCopiedFromTheMenu(string course) =>
        $"A copy of {course} is being saved in Plantoir. Wait for that to finish, then try again.";

    /// <summary>
    /// A publish or hide that stopped part way, from the menu: the copy made
    /// just before it is the way back (one per menu change). Said in place of
    /// <see cref="RestoreSectionPutsItBack"/>, whose button only the
    /// assistant's window has.
    /// </summary>
    public const string RestoreFromBackupPutsItBack =
        "A copy of the course from just before this change is in its Backups — Course ▸ Restore from Backup… puts it back.";

    /// <summary>Make Room for Classes…'s plan, when other classes move.</summary>
    public const string MakingRoomCannotBeUndoneFromTheMenu =
        "Because other classes move, Section ▸ Undo Last Change will not take this back afterwards — the copy made just before it is in Plantoir's Backups list.";

    /// <summary>The same, in a club.</summary>
    public const string MakingRoomCannotBeUndoneFromTheMenuForAMeeting =
        "Because other meetings move, Section ▸ Undo Last Change will not take this back afterwards — the copy made just before it is in Plantoir's Backups list.";

    /// <summary>
    /// The in-app assistant's change to a section the Section menu is changing
    /// right now: refused before anything is backed up or written.
    /// </summary>
    public static string SectionIsChangingFromTheMenu(string course, string section) =>
        $"{course} Section {section} is being changed from the Section menu right now, so nothing was changed. Try again once that has finished.";

    // ---- Why the class dates are asked for first ------------------------------

    /// <summary>Why Make Room for Classes… opens the class dates first.</summary>
    public const string DatesToMakeRoom =
        "Making room for a class moves later classes onto the days this section meets, so it needs those days first.";

    /// <summary>The same, in a club.</summary>
    public const string DatesToMakeRoomForAMeeting =
        "Making room for a meeting moves later meetings onto the days this section meets, so it needs those days first.";

    // ---- The dialog's own words ----------------------------------------------
    // A dialog's title is sentence case; menu items and buttons are title case.

    public static string MenuPublishPagesTitle(string course, string section) => $"Publish pages in {course} Section {section}";
    public static string MenuHidePagesTitle(string course, string section) => $"Hide pages in {course} Section {section}";
    public static string MenuPublishClassTitle(string course, string section) => $"Publish a class in {course} Section {section}";
    public static string MenuPublishClassTitleForAMeeting(string course, string section) => $"Publish a meeting in {course} Section {section}";
    public static string MenuReDateTitle(string course, string section) => $"Re-date the classes in {course} Section {section}";
    public static string MenuReDateTitleForAMeeting(string course, string section) => $"Re-date the meetings in {course} Section {section}";
    public static string MenuMakeRoomTitle(string course, string section) => $"Make room for classes in {course} Section {section}";
    public static string MenuMakeRoomTitleForAMeeting(string course, string section) => $"Make room for meetings in {course} Section {section}";

    public const string MenuPickPagesToPublish =
        "Tick the pages to publish. The pages they link to are published with them, as far as the next class.";
    public const string MenuPickPagesToHide = "Tick the pages to hide. Pages only they link to are hidden with them.";

    public static string MenuNoHiddenPages(string course, string section) => $"Every page in {course} Section {section} is already published.";
    public static string MenuNoVisiblePages(string course, string section) => $"No page in {course} Section {section} is published.";

    public const string MenuPickClassDay = "Choose the day of the class to publish. It is published with the pages it links to.";
    public const string MenuPickClassDayForAMeeting = "Choose the day of the meeting to publish. It is published with the pages it links to.";

    public const string MenuMakeRoomAt =
        "Choose the class a new one goes in front of, and how many to make room for. That class and every later one move along to make room.";
    public const string MenuMakeRoomAtForAMeeting =
        "Choose the meeting a new one goes in front of, and how many to make room for. That meeting and every later one move along to make room.";

    public const string MenuFindAPage = "Find a page";

    public const string MenuContinueButton = "Continue";
    public const string MenuPublishButton = "Publish";
    public const string MenuHideButton = "Hide";
    public const string MenuReDateButton = "Re-date";
    public const string MenuMakeRoomButton = "Make Room";
    public const string MenuCancelButton = "Cancel";
    public const string MenuDoneButton = "OK";

    /// <summary>While the dialog waits on the change: a copy of the course comes first.</summary>
    public static string MenuSavingACopy(string course) => $"Saving a copy of {course} first…";

    public const string MenuWorking = "Working…";

    /// <summary>Titles for the answer to Rebuild Preview, Undo Last Change and Add Next Class, which ask nothing first.</summary>
    public const string MenuRebuildPreviewTitle = "Rebuild preview";
    public const string MenuUndoLastChangeTitle = "Undo last change";
    public const string MenuAddNextClassTitle = "Add next class";
    public const string MenuAddNextClassTitleForAMeeting = "Add next meeting";

    /// <summary>"Monday, 2026-09-14": the weekday and the ISO day, invariant and Gregorian (#144).</summary>
    internal static string MenuDay(DateOnly day) => DateText.Invariant(day, "dddd, " + DateText.IsoDay);
}

using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// The Section menu's voice on the server (#489, the mac's #457 batch B):
/// each sentence a menu path can meet that speaks as a conversation — "I",
/// "ask again", "Undo that" — is chosen here by <see cref="SpeaksFromTheMenu"/>.
/// The conversation's sentences, and every byte the model reads, are unchanged.
/// </summary>
public sealed partial class AssistWorkspace
{
    /// <summary>Pages whose settings could not be added to, in the voice of whoever asked.</summary>
    internal string SettingsCannotBeAddedTo(IReadOnlyList<string> pages) => SpeaksFromTheMenu
        ? AssistWording.PagesWhoseSettingsCannotBeAddedToFromTheMenu(pages)
        : AssistWording.PagesWhoseSettingsCannotBeAddedTo(pages);

    /// <summary>Pages a re-date or make-room could not give their new dates, in the voice of whoever asked.</summary>
    internal string NewDatesCouldNotBeSet(IReadOnlyList<string> pages) => SpeaksFromTheMenu
        ? AssistWording.PagesWhoseNewDatesCouldNotBeSetFromTheMenu(pages)
        : AssistWording.PagesWhoseNewDatesCouldNotBeSet(pages);

    /// <summary>Pages a make-room could not finish, in the voice of whoever asked.</summary>
    internal string ChangeCouldNotFinish(IReadOnlyList<string> pages) => SpeaksFromTheMenu
        ? AssistWording.PagesAChangeCouldNotFinishFromTheMenu(pages)
        : AssistWording.PagesAChangeCouldNotFinish(pages);

    /// <summary>
    /// Every name given matched no page. The menu sends each page by its
    /// folder AND name (<c>section1/All Classes/Unit 2, Day 5</c>), so the
    /// teacher is told the name they ticked — the part after the last slash —
    /// and the menu's sentence says the list may be out of date rather than
    /// "check the name and ask again".
    /// </summary>
    internal string NoPageNamed(string course, int section, IReadOnlyList<string> unknownNames)
    {
        string sectionText = section.ToString(System.Globalization.CultureInfo.InvariantCulture);
        if (!SpeaksFromTheMenu)
            return unknownNames.Count == 1
                ? AssistWording.NoPageCalled(course, sectionText, unknownNames[0])
                : AssistWording.NoPagesCalled(course, sectionText, AssistWording.ListingEither(unknownNames));
        var titles = unknownNames.Select(LastPartOfAName).ToList();
        return titles.Count == 1
            ? AssistWording.NoPageCalledFromTheMenu(titles[0], course, sectionText)
            : AssistWording.NoPagesCalledFromTheMenu(PublishPlan.Listing(titles), course, sectionText);
    }

    /// <summary>"section1/All Classes/Unit 2, Day 5" → "Unit 2, Day 5".</summary>
    internal static string LastPartOfAName(string name)
    {
        string forward = name.Replace('\\', '/');
        int slash = forward.LastIndexOf('/');
        return slash >= 0 ? forward[(slash + 1)..] : forward;
    }

    // ---- Where the last change was made (#489) ----------------------------

    /// <summary>
    /// The <c>_meta</c> key carrying where the change at the top of this
    /// server's undo list was made, as <c>CODE/N</c>, or JSON null when the
    /// list is empty. Sent by the Section menu's server after every call, so
    /// the window can grey Undo Last Change everywhere but the section the last
    /// menu change was made to (<c>subjectMenus</c> → <c>lastChangeIsHere</c>)
    /// without a tool of its own to ask. <see cref="UndoHistory.Entry"/>
    /// carries files, not a section, which is why the place is recorded per
    /// entry here rather than derived from paths (a shared page's flag lives
    /// in a file no section owns).
    /// </summary>
    public const string LastChangeKey = "plantoir.app/lastChange";

    /// <summary>
    /// The <c>_meta</c> key carrying how many changes this server's undo list
    /// holds after the call — so the window's trail line can say whether a menu
    /// item "carried out" a change or "changed nothing", and whether Undo Last
    /// Change "took the last change back", without parsing a sentence. Sent
    /// beside <see cref="LastChangeKey"/>, by the menu's server only.
    /// </summary>
    public const string ChangesToUndoKey = "plantoir.app/changesToUndo";

    private readonly Dictionary<UndoHistory.Entry, string> _placeOfEntry = new(ReferenceEqualityComparer.Instance);

    /// <summary>
    /// After a call: the top undo entry, if it is new, was made by this call
    /// to <paramref name="courseCode"/> Section <paramref name="section"/>.
    /// </summary>
    public void NoteWhereTheLastChangeWasMade(UndoHistory.Entry? before, string? courseCode, int? section)
    {
        if (History?.Entries is not { Count: > 0 } entries) return;
        var top = entries[^1];
        if (ReferenceEquals(top, before) || _placeOfEntry.ContainsKey(top)) return;
        if (courseCode is null || section is null) return;
        string code = courseCode;
        try { code = Course(courseCode).Code; } catch (AssistRefusal) { }
        _placeOfEntry[top] = $"{code}/{section}";
    }

    /// <summary>The top undo entry now, to compare after a call.</summary>
    public UndoHistory.Entry? TopOfTheUndoList =>
        History?.Entries is { Count: > 0 } entries ? entries[^1] : null;

    /// <summary>Where the change at the top of the undo list was made, as <c>CODE/N</c>; null when there is none.</summary>
    public string? LastChangePlace =>
        TopOfTheUndoList is { } top && _placeOfEntry.TryGetValue(top, out var place) ? place : null;
}

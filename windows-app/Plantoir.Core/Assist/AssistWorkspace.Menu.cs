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

    /// <summary>
    /// A page plan as the menu's table (#548): the Folder cell is the page's
    /// folder from the course folder, the COURSE CODE for a page at its root
    /// (the mac's <c>StartOfYearPageNaming.folder</c>), and the noun is the
    /// course's. Sent only by the menu's server — see
    /// <see cref="AssistToolAnswer.PlanTableKey"/>.
    /// </summary>
    public PlanTable Tabulate(PublishPlan plan)
    {
        var course = Course(plan.CourseCode);
        return plan.Tabulate(page => FolderOf(course, page), course.Configuration.ClassNoun);
    }

    /// <summary>"section1/All Classes/Unit 2, Day 5" → "Unit 2, Day 5".</summary>
    internal static string LastPartOfAName(string name)
    {
        string forward = name.Replace('\\', '/');
        int slash = forward.LastIndexOf('/');
        return slash >= 0 ? forward[(slash + 1)..] : forward;
    }

    // ---- What the menu's dialogs offer (#489) ------------------------------

    /// <summary>One page a teacher may tick in Publish Pages… or Hide Pages….</summary>
    /// <param name="Name">What the call sends: its place in the course, <c>section1/All Classes/Unit 2, Day 3</c>.</param>
    /// <param name="Title">What the teacher reads.</param>
    /// <param name="Folder">Its folder in the course, to tell apart two pages of one title.</param>
    public sealed record MenuPage(string Name, string Title, string Folder, bool IsClass, DateOnly? Date);

    /// <summary>
    /// The pages Publish Pages… (hidden ones) or Hide Pages… (visible ones)
    /// offers for a section: classes first, by date then title, then the rest
    /// by folder then title — never the How I Teach page. A page whose flag
    /// cannot be read is offered to Publish Pages… too: publishing it writes
    /// the flag out in full, which is how such a page is mended (the mac's
    /// <c>SectionVerbSheetModel.rows</c>). Read in-process, changing nothing.
    /// </summary>
    public IReadOnlyList<MenuPage> PagesToOffer(string courseCode, int section, bool publishing)
    {
        var course = Course(courseCode);
        int number = Section(course, section);
        var classes = new List<MenuPage>();
        var others = new List<MenuPage>();
        foreach (string page in PagePaths.MarkdownPages(course.DirectoryPath, number).Where(p => ListsAsAPage(course, p)))
        {
            string text;
            try { text = File.ReadAllText(page); } catch { continue; }
            bool visible = !PageFrontmatter.IsDraft(text, number);
            bool certain = PageFrontmatter.Visibility(text, number) != PageVisibility.CannotTell;
            bool offered = publishing ? (!visible || !certain) : visible;
            if (!offered) continue;
            var planned = Plan(course, number, page, draft: !publishing, viaLink: false);
            string name = SectionVerbs.PageName(course.DirectoryPath, page);
            int slash = name.LastIndexOf('/');
            var row = new MenuPage(name, planned.DisplayTitle ?? planned.Title, slash > 0 ? name[..slash] : "",
                                   planned.IsClassPage, planned.Date);
            (row.IsClass ? classes : others).Add(row);
        }
        var orderedClasses = classes
            .OrderBy(row => row.Date is null)
            .ThenBy(row => row.Date ?? default)
            .ThenBy(row => row.Title, StringComparer.OrdinalIgnoreCase);
        var orderedOthers = others
            .OrderBy(row => row.Folder, StringComparer.OrdinalIgnoreCase)
            .ThenBy(row => row.Title, StringComparer.OrdinalIgnoreCase);
        return orderedClasses.Concat(orderedOthers).ToList();
    }

    /// <summary>A class Make Room for Classes… can make room in front of.</summary>
    public sealed record MenuClass(string Title, int Unit, int Day);

    /// <summary>The section's class pages the course's naming can read, in unit and day order.</summary>
    public IReadOnlyList<MenuClass> ClassesToMakeRoomBefore(string courseCode, int section)
    {
        var course = Course(courseCode);
        int number = Section(course, section);
        var naming = course.Configuration.Naming;
        var found = new List<MenuClass>();
        foreach (string page in ClassPages(course, number))
        {
            string title = Path.GetFileNameWithoutExtension(page);
            if (naming.Parse(title) is { } position) found.Add(new MenuClass(title, position.Unit, position.Day));
        }
        return found.OrderBy(row => row.Unit).ThenBy(row => row.Day).ToList();
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

    /// <summary>
    /// The <c>_meta</c> key saying whether the call CHANGED anything — sent by
    /// the menu's server only, beside <see cref="LastChangeKey"/>, so the
    /// window's "ran from a menu" line says "carried out" or "changed nothing"
    /// from a fact the server knows rather than from the undo list's depth.
    /// </summary>
    /// <remarks>
    /// The depth alone was wrong twice over (2B's implementation review, M1):
    /// Make Room for Classes records NO undo entry on purpose (see
    /// <c>ApplyInsertClasses</c>), so a room really made read as "changed
    /// nothing"; and the list keeps at most twenty, so from the twenty-first
    /// change on the depth stays at twenty and every change read the same way.
    /// A call changed something when the top of the undo list is a different
    /// entry afterwards — a new one, however deep the list, or one taken back —
    /// or when a change that keeps no undo entry said it wrote something.
    /// </remarks>
    public const string ChangedKey = "plantoir.app/changed";

    private bool _changedWithNoUndoEntry;

    /// <summary>
    /// A call wrote something that leaves no NEW undo entry, so the menu's
    /// trail line ends "carried out" (or, for an undo, "took part of the last
    /// change back") rather than "changed nothing" (#489 M1; #550, the mac's
    /// #531). Five paths say so: Make Room for Classes when it wrote anything
    /// (it keeps no entry on purpose), a partial undo (its entry stays on the
    /// list), and a publish or hide — page list or whole unit — or a re-date
    /// that stopped part way after writing (the recording is abandoned).
    /// Public because <c>undo_last_change</c>, in plantoir-mcp, notes the
    /// partial undo.
    /// </summary>
    public void NoteAChangeWithNoUndoEntry() => _changedWithNoUndoEntry = true;

    /// <summary>
    /// Why a write failed, in a teacher's words: a permission said plainly,
    /// anything else as the system put it — what a publish that stopped part
    /// way has said since #165.
    /// </summary>
    internal static string ReasonItStopped(Exception error) => error is UnauthorizedAccessException
        ? "Plantoir doesn’t have permission to change one of them."
        : error.Message;

    /// <summary>
    /// A change whose FIRST write failed: nothing was changed — the mac's
    /// "Nothing was changed: {error}" (#550). In no contract on either side.
    /// </summary>
    internal static string NothingWasChanged(Exception error) => "Nothing was changed: " + ReasonItStopped(error);

    /// <summary>
    /// A publish, hide or re-date that failed while writing (#550). After a
    /// write it is noted as a change with no undo entry and the caller
    /// rethrows, so the part-way sentence is said; before any write it is
    /// refused as <see cref="NothingWasChanged"/>, since "Only part of … was
    /// changed" would be false.
    /// </summary>
    internal void StoppedWhileWriting(bool wrote, Exception error)
    {
        if (!wrote) throw new AssistRefusal(NothingWasChanged(error));
        NoteAChangeWithNoUndoEntry();
    }

    /// <summary>
    /// <c>wording.publishStoppedPartWay</c> with its way back, said by every
    /// change that stopped part way (#165, #436; the re-date since #550):
    /// the menu, which has no Restore banner, points at the course's Backups
    /// (#489); Plantoir's own window at its Restore Section button; an outside
    /// assistant at neither. The undo entry is abandoned on a throw, so the
    /// copy is what puts it back.
    /// </summary>
    public string StoppedPartWay(string what, Exception error, int section)
    {
        string said = AssistWording.PublishStoppedPartWay(what, ReasonItStopped(error));
        if (SpeaksFromTheMenu && ConversationBackupPath is not null)
            said += " " + AssistWording.RestoreFromBackupPutsItBack;
        else if (ServesTheLocalWindow && ConversationBackupPath is not null)
            said += " " + AssistWording.RestoreSectionPutsItBack(section.ToString(System.Globalization.CultureInfo.InvariantCulture));
        return said;
    }

    /// <summary>Pages named one to a line by their place in the folder, at most fifteen — <c>PlantoirTools.Listing</c>'s shape.</summary>
    internal string ListingOf(IReadOnlyList<string> paths)
    {
        const int mostListed = 15;
        var lines = new List<string>();
        foreach (string path in paths.Take(mostListed)) lines.Add("  " + Relative(path));
        if (paths.Count > mostListed) lines.Add($"  …and {paths.Count - mostListed} more.");
        return string.Join("\n", lines);
    }

    /// <summary>
    /// After a call: whether it changed anything (see <see cref="ChangedKey"/>).
    /// Reading it clears the no-undo-entry note, so the next call starts clean.
    /// </summary>
    public bool TakeWhetherTheCallChangedAnything(UndoHistory.Entry? topBefore)
    {
        bool changed = !ReferenceEquals(topBefore, TopOfTheUndoList) || _changedWithNoUndoEntry;
        _changedWithNoUndoEntry = false;
        return changed;
    }

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

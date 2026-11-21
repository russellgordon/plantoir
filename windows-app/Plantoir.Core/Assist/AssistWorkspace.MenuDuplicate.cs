using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Assist;

/// <summary>
/// Classes ▸ Add Class…, as a copy of a class (#927, the mac's #897 piece A;
/// <c>contracts/class-planning.json</c> → <c>duplicatingAsTheNextClass</c>):
/// one of THIS section's class pages, named by its FILE, becomes the
/// section's NEXT class, the page Add Next Class would make, with the
/// source's words, hidden. Nothing else is renamed, re-dated or rewritten.
/// </summary>
/// <remarks>
/// <para><b>On the menu's server only</b> (<see cref="SpeaksFromTheMenu"/>),
/// reached through <see cref="MenuDuplicateArgument"/>, an argument no
/// schema declares: <c>plantoir-mcp</c>'s filter reads it before the binder
/// would drop it, so nothing an outside assistant or the built-in model is
/// shown moves. The built-in assistant's own <c>duplicate</c> (by title,
/// after its source, moving later classes) is unchanged.</para>
///
/// <para><b>By file, never by title</b>: a title lookup answers the first
/// page in path order, and a course-level "Concepts/Unit 2, Day 3" sorts
/// before the class of that name. The source must be one of
/// <see cref="ClassPages"/>, compared by FOLDER as Windows compares folders
/// (<see cref="WorkingFolder.IsTheSame"/>: full path, case-insensitive) and by
/// file name as written. The mac resolves links in the folder too (macOS
/// lists a linked course's class folders resolved); here both sides are
/// built from the same course directory, so they are spelled alike, and the
/// page itself is never resolved, so a page that is a link is still found.</para>
///
/// <para><b>Built and read back BEFORE anything is written</b>, and written
/// with <see cref="FileMode.CreateNew"/>, so a page that appeared at that name
/// meanwhile is never written over; a write that fails part way removes the
/// file it created.</para>
///
/// <para><b>No entry on the old undo list</b> (the night-3 settled list, lane
/// B: the entries #927 describes are the in-memory list's, which the journal
/// replaces; the copy's final form is the journal step the mac's U3a defines,
/// which Windows' W7 copies). The contract's <c>expectUndoEntries</c> is held
/// against #899 in <c>NamedGapLedger</c> by case.</para>
/// </remarks>
public sealed partial class AssistWorkspace
{
    /// <summary>The argument the menu names the source by: its path inside the course folder, <c>.md</c> included.</summary>
    public const string MenuDuplicateArgument = "duplicateFileFromTheMenu";

    /// <summary>Everything both halves of the menu's copy need.</summary>
    public sealed record MenuDuplicateRequest(
        string CourseCode, int Section, string SourcePath, string SourceTitle, string SourceText, string NewTitle, DateOnly NewDate,
        string NewPath, string CopyText);

    /// <summary>
    /// The copy, worked out and checked: throws <see cref="AssistRefusal"/>
    /// in the menu's words for anything that would not be this section's
    /// class, and <see cref="CopyCannotBeHidden"/> when the copy does not read
    /// back hidden. Changes nothing.
    /// </summary>
    public MenuDuplicateRequest PlanMenuDuplicate(string courseCode, int sectionNumber, string sourcePath)
    {
        var course = Course(courseCode);
        int section = Section(course, sectionNumber);
        var noun = course.Configuration.ClassNoun;
        string sectionText = section.ToString(System.Globalization.CultureInfo.InvariantCulture);
        if (UnitWordRenamer.InterruptedRenameTarget(UnitWordRenamer.Facts(course), clearingAStaleRecord: false) is not null)
            throw new AssistRefusal(AddClassWords.UnitWordRenameUnfinished(noun));

        string wanted = Path.Combine(course.DirectoryPath, sourcePath.Replace('/', Path.DirectorySeparatorChar));
        string? source = null;
        foreach (string page in ClassPages(course, section))
            if (WorkingFolder.IsTheSame(Path.GetDirectoryName(page), Path.GetDirectoryName(wanted))
                && string.Equals(Path.GetFileName(page), Path.GetFileName(wanted), StringComparison.Ordinal))
                source = page;
        string shownName = Path.GetFileNameWithoutExtension(sourcePath.Replace('\\', '/').Split('/')[^1]);
        if (source is null)
            throw new AssistRefusal(AssistWording.NoPageCalledFromTheMenu(shownName, course.Code, sectionText));
        string sourceTitle = Path.GetFileNameWithoutExtension(source);
        string sourceText;
        try { sourceText = File.ReadAllText(source); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            throw new AssistRefusal(AssistWording.NoPageCalledFromTheMenu(sourceTitle, course.Code, sectionText));
        }

        // The next class, exactly as Add Next Class plans it. Missing dates
        // between the dialog's own check and the press get the menu's
        // sentence, not the conversation's "may I ask for your dates".
        if (TimetableMemory.Read(_folder, course.Code, section, recording: false) is not { Dates.Count: > 0 })
            throw new AssistRefusal(AddClassWords.NeedsClassDatesFirst(noun));
        var plan = PlanAddNextClass(course.Code, section);
        if (plan.Classes.Count == 0)
            throw new AssistRefusal(AssistWording.MenuTheNextPageIsAlreadyThere(plan.AlreadyThere.FirstOrDefault() ?? ""));
        var next = plan.Classes[0];
        string newPath = Path.Combine(_folder, next.RelativePath.Replace('/', Path.DirectorySeparatorChar));

        // The assistant's three steps, in its order: the title, every
        // per-section key out FIRST (the build resolves them over the plain
        // keys, so an inherited publishForSection1: true would beat the
        // publish: false below), then the date and the flag.
        bool sectionLocal = PagePaths.IsSectionLocal(course.DirectoryPath, newPath);
        string copied = PageFrontmatter.SetTitle(sourceText, next.Title);
        copied = PageFrontmatter.WithoutPerSectionKeys(copied);
        copied = PageFrontmatter.SetCreated(copied, PageFrontmatter.CreatedKeyFor(section, sectionLocal), next.Date,
            SiblingTimeAndOffset(course, section, ClassPages(course, section))).Text;
        copied = PageFrontmatter.SetDraft(copied, PageFrontmatter.PublishKeyFor(section, sectionLocal), draft: true, section).Text;
        if (PageFrontmatter.Visibility(copied, section) != PageVisibility.Hidden)
            throw new CopyCannotBeHidden(sourceTitle);

        return new MenuDuplicateRequest(course.Code, section, sourcePath, sourceTitle, sourceText, next.Title, next.Date, newPath, copied);
    }

    /// <summary>The copy could not be made certainly hidden: nothing is written, and the trail says so.</summary>
    public sealed class CopyCannotBeHidden(string sourceTitle) : Exception(AssistWording.TheCopyCouldNotBeMadeHiddenFromTheMenu(sourceTitle))
    {
        public string SourceTitle { get; } = sourceTitle;
    }

    /// <summary>The plan's card: what is copied to what, on which day, and that it starts hidden.</summary>
    public static string DescribeMenuDuplicate(MenuDuplicateRequest request) =>
        ClassChangeWording.WouldBeCopiedTo(request.SourceTitle, request.NewTitle, request.NewDate) + "\n" +
        ClassChangeWording.TheCopyStartsHidden;

    /// <summary>
    /// The trail line for a menu copy that could not be made certainly hidden,
    /// naming the menu by the title the course's menu bar gives it (Meetings
    /// in a club), noted at the plan AND at the write.
    /// </summary>
    public void NoteTheMenusCopyWasNotMade(string courseCode, int section)
    {
        var noun = NounForCourse(courseCode);
        string menu = SubjectMenuLayout.Title(SubjectMenuLayout.MenuContaining(SubjectMenuRules.Item.AddClass) ?? SubjectMenuLayout.Menu.Classes, noun);
        ActivityTrail.Note(ActivityTrail.Event.ClassCopyNotMade,
            $"did not copy a class from the {menu} menu — the copy could not be made certainly hidden, so nothing was written",
            courseCode, section);
    }

    /// <summary>
    /// The write: a copy of the course first, the plan made again and held to
    /// the one shown, then ONE new file. Returns the finished sentence.
    /// </summary>
    public string ApplyMenuDuplicate(MenuDuplicateRequest request, IProgress<string>? progress = null)
    {
        var course = Course(request.CourseCode);
        RefuseIfPlantoirIsBuilding(course);
        try { BackUpOnceForThisConversation(course, request.Section, progress); }
        catch (Exception error) when (error is not AssistRefusal)
        {
            throw new AssistRefusal($"{course.Code} couldn’t be backed up, so nothing was copied: {error.Message}");
        }

        // Held again to the plan after the copy (#351's plan/write gap).
        MenuDuplicateRequest again;
        try { again = PlanMenuDuplicate(request.CourseCode, request.Section, request.SourcePath); }
        catch (CopyCannotBeHidden) { throw; }
        catch (AssistRefusal) { again = request with { CopyText = "" }; }
        if (again != request)
            throw new AssistRefusal(AssistWording.ChangedWhileSavingACopyFromTheMenu(course.Code,
                request.Section.ToString(System.Globalization.CultureInfo.InvariantCulture)));

        Directory.CreateDirectory(Path.GetDirectoryName(request.NewPath)!);
        bool created = false;
        try
        {
            using (var stream = new FileStream(request.NewPath, FileMode.CreateNew, FileAccess.Write))
            {
                created = true;
                using var writer = new StreamWriter(stream, new System.Text.UTF8Encoding(false));
                writer.Write(request.CopyText);
            }
        }
        catch (IOException) when (!created && File.Exists(request.NewPath))
        {
            // A page appeared at that name meanwhile: never written over.
            throw new AssistRefusal(AssistWording.MenuTheNextPageIsAlreadyThere(request.NewTitle));
        }
        catch (IOException error) when (!created)
        {
            // Not there, and still not made (a path too long, a cloud-file
            // error, a drive gone): said as what it is, never "already there"
            // (lane B review, low 4; the mac matches only fileWriteFileExists).
            throw new AssistRefusal(NothingWasCreated(error));
        }
        catch (Exception error) when (created)
        {
            // This call made the file, so a half-written one goes; the copy
            // of the course saved first is the way back for anything else.
            try { File.Delete(request.NewPath); } catch { }
            throw new AssistRefusal(NothingWasCreated(error));
        }
        // Changed, with no entry on the old list (see the remarks above), so
        // the trail's "ran from a menu" line says "carried out".
        NoteAChangeWithNoUndoEntry();
        return AssistWording.DuplicatedFromTheMenu(request.SourceTitle, request.NewTitle, DateText.Iso(request.NewDate));
    }
}

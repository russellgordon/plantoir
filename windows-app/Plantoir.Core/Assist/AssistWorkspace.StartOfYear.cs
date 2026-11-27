using System.Security.Cryptography;
using System.Text;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Plantoir.Core.Undo;

namespace Plantoir.Core.Assist;

/// <summary>Where a start-of-year act was asked from, as the trail says it.</summary>
public enum StartOfYearAskedFrom
{
    TheApp,
    TheAssistant,
    AnOutsideAssistant,
}

/// <summary>A plan for one section, its words, and its code.</summary>
public sealed record StartOfYearProposal(
    string CourseCode,
    int Section,
    StartOfYearPlan Plan,
    string Text,
    string Code)
{
    /// <summary>
    /// The plan in the course's own noun — what the TEACHER reads (the app's
    /// sheet, the window's card). <see cref="Text"/> is the class form, which
    /// is what the model and plantoir-mcp's text content carry (#274).
    /// </summary>
    public string TeacherText { get; init; } = Text;
}

/// <summary>What a write did: the sentence to say, the backup, and the files written (before → after).</summary>
public sealed record StartOfYearOutcome(
    bool Changed,
    string Message,
    string? BackupPath,
    IReadOnlyDictionary<string, (string Before, string After)> Written)
{
    /// <summary>
    /// Set only when Go stopped part way (#899 W8c-2a, the mac's
    /// <c>Outcome.stoppedPartWay</c>): some pages went into draft and could
    /// not all be put back. Null for every other outcome, a stop that changed
    /// nothing included (that stays <c>writeFailed</c>). <see cref="Message"/>
    /// is still what the assistants say today.
    /// </summary>
    public StartOfYearStoppedPartWay? StoppedPartWay { get; init; }
}

/// <summary>
/// What the sheet needs to offer the restore after Go stopped part way (the
/// mac's <c>StartOfYearPreparation.StoppedPartWay</c>): the section, the
/// course, the backup Go made as Restore from Backup… lists it (made with the
/// outcome, so the offer is never shown without one), and how many files are
/// kept beside their pages. No hidden name: the sheet names none.
/// </summary>
public sealed record StartOfYearStoppedPartWay(int Section, string CourseCode, BackupItem Backup, int KeptCount);

public sealed partial class AssistWorkspace
{
    /// <summary>
    /// The section's pages as the start-of-year planner reads them: kind, the
    /// built site's own visibility reading, direct links (never to itself),
    /// and the name a teacher reads.
    /// </summary>
    public IReadOnlyList<StartOfYearPage> StartOfYearPages(Course course, int section)
    {
        var graph = LinkGraph.Build(course, section);
        var classPages = ClassPages(course, section).Select(Path.GetFullPath)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        string frontPage = Path.GetFullPath(SectionIndex.PathFor(course, section));
        string keyLinks = Path.GetFullPath(Path.Combine(course.SectionDirectory(section), KeyLinksFileName));
        var naming = course.Configuration.Naming;

        var pages = new List<StartOfYearPage>();
        var declared = course.Configuration.CurriculumFolders;
        foreach (string full in graph.Pages.Where(page => ListsAsAPage(course, page)))
        {
            string text;
            try { text = File.ReadAllText(full); } catch { continue; }
            StartOfYearKind kind =
                string.Equals(full, frontPage, StringComparison.OrdinalIgnoreCase) ? StartOfYearKind.SectionFrontPage
                : string.Equals(full, keyLinks, StringComparison.OrdinalIgnoreCase) ? StartOfYearKind.KeyLinks
                : classPages.Contains(full) ? StartOfYearKind.Class
                : LinkGraph.IsLandingPage(full) ? StartOfYearKind.FolderIndex
                : IsCurriculum(course.DirectoryPath, full, declared) ? StartOfYearKind.Curriculum
                : StartOfYearKind.Page;
            string relativeDirectory = Path.GetRelativePath(course.DirectoryPath, Path.GetDirectoryName(full)!)
                .Replace('\\', '/');
            pages.Add(new StartOfYearPage(
                Id: full,
                Name: PagePaths.DisplayTitle(full, text),
                Folder: relativeDirectory == "." ? course.Code : relativeDirectory,
                Kind: kind,
                Visible: !PageFrontmatter.IsDraft(text, section),
                LinksTo: graph.TargetsOf(full)
                    .Where(target => !string.Equals(target, full, StringComparison.OrdinalIgnoreCase))
                    .ToHashSet(StringComparer.OrdinalIgnoreCase),
                Number: kind == StartOfYearKind.Class ? naming.Parse(Path.GetFileNameWithoutExtension(full)) : null,
                Date: DateOf(course, section, full)));
        }
        return pages;
    }

    /// <summary>
    /// The plan for one section and its code. The code covers every page of
    /// the section, path and bytes, so any change to the section since the
    /// plan was shown makes it stale. Each platform has its own algorithm;
    /// only the guarantee is shared (<c>startOfYear.planCode</c>).
    /// </summary>
    public StartOfYearProposal PlanStartOfYear(string courseCode, int sectionNumber)
    {
        var course = Course(courseCode);
        int section = Section(course, sectionNumber);
        var pages = StartOfYearPages(course, section);
        var plan = StartOfYearPlan.Make(pages);
        string code = StartOfYearCode(course, section, pages);
        DateTime? scheduled = null;
        try { scheduled = TaskScheduling.NextRun(_folder, course.Code, section); } catch { }
        bool actionable = plan.First is not null && !plan.NothingToDo;
        string text = StartOfYearWording.Describe(plan, course.Code, section, DateOnly.FromDateTime(DateTime.Now),
            scheduled, actionable ? code : null);
        var noun = course.Configuration.ClassNoun;
        return new StartOfYearProposal(course.Code, section, plan, text, code)
        {
            TeacherText = noun == ClassNoun.Class ? text
                : StartOfYearWording.Describe(plan, course.Code, section, DateOnly.FromDateTime(DateTime.Now),
                    scheduled, actionable ? code : null, noun),
        };
    }

    private static string StartOfYearCode(Course course, int section, IEnumerable<StartOfYearPage> pages)
    {
        var hash = new StringBuilder($"{course.Code}\n{section}\n");
        foreach (var page in pages.OrderBy(p => p.Id, StringComparer.OrdinalIgnoreCase))
        {
            string text;
            try { text = File.ReadAllText(page.Id); } catch { text = "<unreadable>"; }
            hash.Append(page.Id.ToLowerInvariant()).Append('\n').Append(text).Append("\n\0");
        }
        byte[] digest = SHA256.HashData(Encoding.UTF8.GetBytes(hash.ToString()));
        return Convert.ToHexString(digest, 0, 4).ToLowerInvariant();
    }

    /// <summary>
    /// Put the plan into effect — the MCP write and the app's Go, the same
    /// steps. Re-plans first, and writes nothing when the code is missing or
    /// stale. Takes a FRESH backup for this act (never the once-per-conversation
    /// copy) and refuses without one. Each page in the plan gets its own key
    /// set to draft, and a stray <c>publishForSection&lt;N&gt;</c> is set too
    /// when the build would otherwise still read the page as published; the
    /// section's front page is repointed AFTER, at its newest visible class.
    /// </summary>
    public StartOfYearOutcome PrepareForStartOfYear(string courseCode, int sectionNumber, string? planCode,
                                                     StartOfYearAskedFrom from, BackupMaker? backupMaker = null)
    {
        var proposal = PlanStartOfYear(courseCode, sectionNumber);
        var course = Course(proposal.CourseCode);
        int section = proposal.Section;
        var plan = proposal.Plan;
        string where = from switch
        {
            StartOfYearAskedFrom.TheApp => "from the app",
            StartOfYearAskedFrom.TheAssistant => "from the assistant",
            _ => "from an outside assistant",
        };
        StartOfYearOutcome NotDone(string reason, string message)
        {
            ActivityTrail.Note(ActivityTrail.Event.StartOfYearNotDone,
                $"did not get ready for the start of the year {where} — nothing was changed ({reason})", course.Code, section);
            return new StartOfYearOutcome(false, message, null, new Dictionary<string, (string, string)>());
        }

        if (plan.First is null) return NotDone("noFirstClass", proposal.Text);
        if (plan.NothingToDo) return NotDone("nothingToDo", proposal.Text);
        if (string.IsNullOrWhiteSpace(planCode))
            return NotDone("missingPlanCode", AssistWording.StartOfYearNeedsItsPlan(course.Code, section.ToString()));
        if (!string.Equals(planCode.Trim(), proposal.Code, StringComparison.OrdinalIgnoreCase))
            return NotDone("changedSinceShown", AssistWording.StartOfYearPlanHasChanged(course.Code, section.ToString()));

        string backup;
        try
        {
            // The teacher's own copy from the app's Go; the assistant's goes
            // through the one door that leaves its trail line (#360).
            backup = backupMaker is not null
                ? CourseArchiver.BackUpCourse(course, Workspace.CoursesDirectory(_folder), backupMaker)
                : AssistantBackup(course, section);
        }
        catch
        {
            return NotDone("backupFailed", AssistWording.StartOfYearNeedsABackup(course.Code));
        }

        // The copy can take a while: the plan must still be the one shown,
        // and still be makeable (a first class renamed or deleted meanwhile).
        var afterCopy = PlanStartOfYear(courseCode, sectionNumber);
        if (afterCopy.Plan.First is null || afterCopy.Plan.NothingToDo
            || !string.Equals(afterCopy.Code, proposal.Code, StringComparison.OrdinalIgnoreCase))
            return NotDone("changedSinceShown", AssistWording.ChangedWhileSavingACopy(course.Code, section.ToString()));

        var written = new Dictionary<string, (string Before, string After)>(StringComparer.OrdinalIgnoreCase);
        // Pages the writer DECLINED (#421, the mac's #186): no column-0 place
        // for a new line in their settings, so they are left exactly as they
        // were and named — never counted as put into draft while students can
        // still see them, which is the damaging direction.
        var declined = new List<StartOfYearDraft>();
        using var recording = UndoHistory.Record(_undo,
            $"got {course.Code} Section {section} ready for the start of the year");
        // ONE step through the door (#899 W7b2-5; the mac's
        // StartOfYearPlanner.apply): every page put into draft together, all
        // or none, each read through the step at plan time; the front page
        // kept true by its rule after the step (recompute, sectionFrontPage),
        // never written as a file of it. A failure now changes nothing, so
        // there is nothing to put back: the act's own put-back is gone.
        // The app's Go is the sheet's (the mac's UndoStepMaker.sheet); the
        // assistant's is its conversation's.
        var step = NewUndoStep("getReadyForTheStartOfTheYear", course.Code, section,
            madeBy: from == StartOfYearAskedFrom.TheApp ? "sheet" : null);
        string index = Path.GetFullPath(SectionIndex.PathFor(course, section));
        string? frontBefore = null;
        try
        {
            foreach (var draft in plan.Drafts)
            {
                string full = draft.Page.Id;
                string before = step.ReadText(full);
                var (after, noRoom) = StartOfYearDraftEdit(course, section, full, before);
                // Half a write that still leaves the page up is no write at
                // all: nothing is saved, and the page is named.
                if (noRoom)
                {
                    declined.Add(draft);
                    continue;
                }
                if (after == before) continue;
                written[full] = (before, after);
            }
            // Into the step in the order of their places in the working
            // folder (Relative, forward slashes), as the mac's planWrites sorts
            // its paths; the sheet's lists and Undo Getting Ready keep the
            // plan's order (written).
            var places = new List<string>(written.Keys);
            places.Sort((one, other) => string.CompareOrdinal(Relative(one), Relative(other)));
            foreach (string full in places)
                step.Write(full, written[full].After);
            // The front page catches up AFTER the hides, by its rule, or it
            // keeps embedding the class just put into draft.
            step.KeepsTheFrontPageTrue(section, index);
            try { if (File.Exists(index)) frontBefore = File.ReadAllText(index); } catch { }
            MakeTheUndoStep(step);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // All or none: "Nothing was changed" unless the door left a page
            // holding its new content with its earlier content kept beside
            // it, which is said as part way, naming each kept file.
            // The door's exception alone tells the two stops apart (#899
            // W8c-2a): part way is its own outcome, every other write error
            // changed nothing.
            if (error is not UndoStepLeftPartWayException partWay)
                return NotDone("writeFailed", NothingWasChanged(error));
            string backupName = Path.GetFileName(backup);
            ActivityTrail.Note(ActivityTrail.Event.StartOfYearNotDone,
                ActivityTrail.StartOfYearStoppedPartWayLine(where, partWay.KeptOriginals.Count, backupName),
                course.Code, section);
            // The backup as Restore from Backup… lists it. Go's own backup
            // name is always one BackupItem.From reads; if it ever were not,
            // no offer is made, and the sheet's writeFailed words are said,
            // which are true (the backup holds the course as it was).
            if (BackupItem.From(backup, course.Code) is not { } backupItem)
                return new StartOfYearOutcome(false,
                    StartOfYearWording.Fill(StartOfYearWording.WriteFailed, ("backup", backupName)),
                    backup, new Dictionary<string, (string, string)>());
            return new StartOfYearOutcome(false,
                RefusalForAStepThatStopped(error, "the pages put into draft", section).Message,
                backup, new Dictionary<string, (string, string)>())
            {
                StoppedPartWay = new StartOfYearStoppedPartWay(section, course.Code, backupItem, partWay.KeptOriginals.Count),
            };
        }
        // The front page as the rule left it, for Undo Getting Ready.
        string? frontAfter = null;
        try { if (File.Exists(index)) frontAfter = File.ReadAllText(index); } catch { }
        if (frontBefore is not null && frontAfter is not null && frontAfter != frontBefore)
            written[index] = (frontBefore, frontAfter);
        recording.Done();

        // Counted from what was put into draft: a declined page is one of the
        // pages "left as they were" (the trail's one line carries it, per
        // activityTrail.mustRecord — never a second line).
        var drafted = plan.Drafts.Where(d => !declined.Contains(d)).ToList();
        int classesDrafted = drafted.Count(d => d.Reason == StartOfYearReason.LaterClass);
        int firstUsedLater = drafted.Count(d => d.Reason == StartOfYearReason.FirstUsedIn);
        int nothingSees = drafted.Count - classesDrafted - firstUsedLater;
        ActivityTrail.Note(ActivityTrail.Event.SectionMadeReadyForTheStartOfTheYear,
            $"made ready for the start of the year {where} — {StartOfYearWording.ClassesCounted(classesDrafted)} and " +
            $"{StartOfYearWording.Counted(firstUsedLater + nothingSees, "other page", "other pages")} put into draft " +
            $"({firstUsedLater} first used later, {nothingSees} that nothing students can see links to), " +
            $"{plan.Pages.Count - drafted.Count} left as they were; backup {Path.GetFileName(backup)}; preview not rebuilt",
            course.Code, section);

        string? declinedSentence = declined.Count == 0 ? null
            : AssistWording.PagesWhoseSettingsCannotBeAddedTo(declined.Select(d => d.Page.Name).ToList());
        string message = drafted.Count == 0 && declinedSentence is not null
            ? declinedSentence
            : StartOfYearWording.Fill(StartOfYearWording.Done, ("pages", StartOfYearWording.PagesCounted(drafted.Count)))
              + (declinedSentence is null ? "" : " " + declinedSentence);
        return new StartOfYearOutcome(written.Count > 0, message, backup, written);
    }

    /// <summary>
    /// The edit Go makes to one page: its own key set to draft, and a stray
    /// <c>publishForSection&lt;N&gt;</c> too when the build would otherwise
    /// still read the page as published — or NO ROOM, when the page's settings
    /// have no column-0 place for a new line (#421). One rule, asked by Go and
    /// by the sheet before Go (#619), so the sheet names exactly the pages Go
    /// will leave as they are.
    /// </summary>
    private static (string After, bool NoRoom) StartOfYearDraftEdit(Course course, int section, string full, string before)
    {
        bool sectionLocal = PagePaths.IsSectionLocal(course.DirectoryPath, full);
        var (after, edit) = PageFrontmatter.SetDraft(before, PageFrontmatter.PublishKeyFor(section, sectionLocal), true, section);
        bool noRoom = edit.NoRoomForAKey;
        // A stray per-section key beside `publish:` is read FIRST by the
        // build, so writing only `publish: false` would leave the class up.
        if (!noRoom && !PageFrontmatter.IsDraft(after, section))
        {
            (after, edit) = PageFrontmatter.SetDraft(after, PageFrontmatter.PublishKeyFor(section, false), true, section);
            noRoom = edit.NoRoomForAKey;
        }
        return (after, noRoom);
    }

    /// <summary>The pages Go would leave exactly as they are for want of room for a key, named as the write names them — for the sheet, before Go (#619).</summary>
    public IReadOnlyList<string> StartOfYearPagesWithNoRoom(string courseCode, int sectionNumber, StartOfYearPlan plan)
    {
        var course = Course(courseCode);
        int section = Section(course, sectionNumber);
        var names = new List<string>();
        foreach (var draft in plan.Drafts)
        {
            string before;
            try { before = File.ReadAllText(draft.Page.Id); } catch { continue; }
            if (StartOfYearDraftEdit(course, section, draft.Page.Id, before).NoRoom) names.Add(draft.Page.Name);
        }
        return names;
    }

    /// <summary>
    /// Writes <c>start of the year change undone</c> when an undo took back a
    /// start-of-year change — the assistant's "undo that" or an outside
    /// assistant's <c>undo_last_change</c>. Recognised by the description the
    /// write recorded; any other undo writes nothing here.
    /// </summary>
    public static void NoteIfItUndidAStartOfYear(UndoResult result, StartOfYearAskedFrom from)
    {
        var match = System.Text.RegularExpressions.Regex.Match(result.Description,
            "^got (?<course>.+) Section (?<section>[0-9]+) ready for the start of the year$");
        if (!match.Success) return;
        NoteStartOfYearUndone(match.Groups["course"].Value, int.Parse(match.Groups["section"].Value),
            from, result.Restored.Count, result.Skipped.Count);
    }

    /// <summary>The trail line for an undo of getting ready, from wherever it was undone.</summary>
    public static void NoteStartOfYearUndone(string course, int section, StartOfYearAskedFrom from, int putBack, int leftAsTheyAre)
    {
        string where = from switch
        {
            StartOfYearAskedFrom.TheApp => "from the app's undo sheet",
            StartOfYearAskedFrom.TheAssistant => "from the assistant",
            _ => "from an outside assistant's undo_last_change",
        };
        ActivityTrail.Note(ActivityTrail.Event.StartOfYearChangeUndone,
            $"undid getting ready for the start of the year {where} — {StartOfYearWording.PagesCounted(putBack)} put back, " +
            $"{leftAsTheyAre} left as they are because they had changed since", course, section);
    }

    /// <summary>
    /// What an undo of a start-of-year write WOULD do, asked before the
    /// teacher agrees: the pages it would put back and the ones it would leave
    /// because they changed since — sorted by the undo's own rule,
    /// <see cref="UndoVerdict.Of"/> (#564, the mac's <c>whatAnUndoWouldDo</c>),
    /// so the sheet cannot call a page "left alone" that the undo then treats
    /// as already back. A page already as it was is in neither list.
    /// </summary>
    public static (IReadOnlyList<string> PutBack, IReadOnlyList<string> LeftAsTheyAre) WhatAnUndoWouldDo(
        IReadOnlyDictionary<string, (string Before, string After)> written)
    {
        var putBack = new List<string>();
        var left = new List<string>();
        foreach (var (path, (before, after)) in written)
        {
            var verdict = UndoVerdict.Of(path, new UndoHistory.FileState(before, after));
            if (verdict == UndoVerdict.Kind.PutBack) putBack.Add(path);
            else if (verdict == UndoVerdict.Kind.LeftAlone) left.Add(path);
        }
        return (putBack, left);
    }

    /// <summary>
    /// Put back what a start-of-year write changed, by the same verdict: a
    /// file still holding exactly what was written goes back to what it held
    /// before; a file already back is left as it is and not counted; a file
    /// changed since — or one that could not be written — is left and named.
    /// </summary>
    public static (IReadOnlyList<string> PutBack, IReadOnlyList<string> LeftAsTheyAre) UndoStartOfYear(
        IReadOnlyDictionary<string, (string Before, string After)> written)
    {
        // Through today's undo, as the mac's StartOfYearPreparation.undo
        // records the held change on a fresh AssistChangeHistory and undoes
        // it (#899 W7b2-5): the same verdict, and no writer of its own here.
        var files = new Dictionary<string, UndoHistory.FileState>(StringComparer.OrdinalIgnoreCase);
        foreach (var (path, (before, after)) in written) files[path] = new UndoHistory.FileState(before, after);
        var history = new UndoHistory();
        history.Remember(new UndoHistory.Entry("got ready for the start of the year", DateTime.Now, files));
        UndoResult result = history.Undo();
        return (result.Restored, result.Skipped);
    }
}

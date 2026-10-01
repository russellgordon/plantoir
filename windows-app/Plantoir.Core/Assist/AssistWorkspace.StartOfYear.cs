using System.Security.Cryptography;
using System.Text;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

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
    string Code);

/// <summary>What a write did: the sentence to say, the backup, and the files written (before → after).</summary>
public sealed record StartOfYearOutcome(
    bool Changed,
    string Message,
    string? BackupPath,
    IReadOnlyDictionary<string, (string Before, string After)> Written);

public sealed partial class AssistWorkspace
{
    /// <summary>
    /// The section's pages as the start-of-year planner reads them: kind, the
    /// built site's own visibility reading, direct links (never to itself),
    /// and the name a teacher reads.
    /// </summary>
    public IReadOnlyList<StartOfYearPage> StartOfYearPages(Course course, int section)
    {
        var graph = LinkGraph.Build(course.DirectoryPath, section);
        var classPages = ClassPages(course, section).Select(Path.GetFullPath)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        string frontPage = Path.GetFullPath(SectionIndex.PathFor(course, section));
        string keyLinks = Path.GetFullPath(Path.Combine(course.SectionDirectory(section), KeyLinksFileName));
        string unitWord = course.Configuration.UnitWord;

        var pages = new List<StartOfYearPage>();
        foreach (string full in graph.Pages.Where(page => ListsAsAPage(course, page)))
        {
            string text;
            try { text = File.ReadAllText(full); } catch { continue; }
            StartOfYearKind kind =
                string.Equals(full, frontPage, StringComparison.OrdinalIgnoreCase) ? StartOfYearKind.SectionFrontPage
                : string.Equals(full, keyLinks, StringComparison.OrdinalIgnoreCase) ? StartOfYearKind.KeyLinks
                : classPages.Contains(full) ? StartOfYearKind.Class
                : LinkGraph.IsLandingPage(full) ? StartOfYearKind.FolderIndex
                : IsCurriculum(course.DirectoryPath, full) ? StartOfYearKind.Curriculum
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
                Number: kind == StartOfYearKind.Class ? UnitDay.Parse(Path.GetFileNameWithoutExtension(full), unitWord) : null,
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
        return new StartOfYearProposal(course.Code, section, plan, text, code);
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
        using var recording = UndoHistory.Record(_undo,
            $"got {course.Code} Section {section} ready for the start of the year");
        try
        {
            foreach (var draft in plan.Drafts)
            {
                string full = draft.Page.Id;
                string before = File.ReadAllText(full);
                bool sectionLocal = PagePaths.IsSectionLocal(course.DirectoryPath, full);
                var (after, _) = PageFrontmatter.SetDraft(before, PageFrontmatter.PublishKeyFor(section, sectionLocal), true, section);
                // A stray per-section key beside `publish:` is read FIRST by the
                // build, so writing only `publish: false` would leave the class up.
                if (!PageFrontmatter.IsDraft(after, section))
                    (after, _) = PageFrontmatter.SetDraft(after, PageFrontmatter.PublishKeyFor(section, false), true, section);
                if (after == before) continue;
                Save(full, after);
                written[full] = (before, after);
            }

            // The front page catches up — after the hides, or it keeps
            // embedding the class just put into draft.
            var classes = ClassPages(course, section);
            if (SectionIndex.MostRecentPublished(course, section, classes) is { } newest)
            {
                string index = SectionIndex.PathFor(course, section);
                string before = File.ReadAllText(index);
                string tail = SiblingTimeAndOffset(course, section, classes);
                if (SectionIndex.PointedAndDated(before, Path.GetFileNameWithoutExtension(newest),
                        DateOf(course, section, newest) ?? default, tail) is { } after && after != before)
                {
                    Save(index, after);
                    written[Path.GetFullPath(index)] = (before, after);
                }
            }
        }
        catch
        {
            recording.Done();
            ActivityTrail.Note(ActivityTrail.Event.StartOfYearNotDone,
                $"did not get ready for the start of the year {where} — the pages could not all be written (writeFailed); backup {Path.GetFileName(backup)}",
                course.Code, section);
            return new StartOfYearOutcome(written.Count > 0,
                StartOfYearWording.Fill(StartOfYearWording.WriteFailed, ("backup", Path.GetFileName(backup))),
                backup, written);
        }
        recording.Done();

        int classesDrafted = plan.Classes.Count();
        int firstUsedLater = plan.OtherPages.Count(d => d.Reason == StartOfYearReason.FirstUsedIn);
        int nothingSees = plan.OtherPages.Count() - firstUsedLater;
        ActivityTrail.Note(ActivityTrail.Event.SectionMadeReadyForTheStartOfTheYear,
            $"made ready for the start of the year {where} — {StartOfYearWording.ClassesCounted(classesDrafted)} and " +
            $"{StartOfYearWording.Counted(firstUsedLater + nothingSees, "other page", "other pages")} put into draft " +
            $"({firstUsedLater} first used later, {nothingSees} that nothing students can see links to), " +
            $"{plan.Pages.Count - plan.Drafts.Count} left as they were; backup {Path.GetFileName(backup)}; preview not rebuilt",
            course.Code, section);

        return new StartOfYearOutcome(true,
            StartOfYearWording.Fill(StartOfYearWording.Done, ("pages", StartOfYearWording.PagesCounted(plan.Drafts.Count))),
            backup, written);
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
    /// Put back what a start-of-year write changed: each file still holding
    /// exactly what was written goes back to what it held before; a file
    /// changed since is left as it is and named (the assistant's skip rule).
    /// </summary>
    public static (IReadOnlyList<string> PutBack, IReadOnlyList<string> LeftAsTheyAre) UndoStartOfYear(
        IReadOnlyDictionary<string, (string Before, string After)> written)
    {
        var putBack = new List<string>();
        var left = new List<string>();
        foreach (var (path, (before, after)) in written)
        {
            string now;
            try { now = File.ReadAllText(path); } catch { left.Add(path); continue; }
            if (now != after) { left.Add(path); continue; }
            File.WriteAllText(path, before);
            putBack.Add(path);
        }
        return (putBack, left);
    }
}

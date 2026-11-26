using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using Plantoir.Core.Models;
using Plantoir.Core.Undo;

namespace Plantoir.Core.Assist;

/// <summary>
/// The links checklist as the sheet holds it (#392 / #399 / #405): the rows
/// as re-read when it opened, the teacher's own ticks, and what each class
/// row's publish would bring. Every rule is <see cref="LinksChecklist"/>'s;
/// this only holds the state, so the sheet and the contract runner drive the
/// same object.
/// </summary>
public sealed class LinksChecklistSheet
{
    public required string CourseCode { get; init; }
    public required int Section { get; init; }
    public required IReadOnlyList<LinksChecklistRow> Rows { get; init; }
    public required Dictionary<string, bool> Ticks { get; init; }
    public required IReadOnlyDictionary<string, IReadOnlyList<string>> Brings { get; init; }

    /// <summary>How many PAGES each class row's publish brings, rows or not (wording.comesWith).</summary>
    public required IReadOnlyDictionary<string, int> BringsCount { get; init; }

    /// <summary>What a teacher calls each row's page, and each page a second line names.</summary>
    public required IReadOnlyDictionary<string, string> RowTitles { get; init; }
    public required Func<string, string> NameOf { get; init; }

    public HashSet<string> Going => LinksChecklist.Going(Rows, Ticks);
    public Dictionary<string, string> ComingWith => LinksChecklist.ComingWith(Rows, Ticks, Brings);
    public HashSet<string> Locked => LinksChecklist.Locked(Rows, Going, ComingWith);
    public HashSet<string> ShownTicked => LinksChecklist.ShownTicked(Going, ComingWith);

    /// <summary>The checkbox. See <see cref="LinksChecklist.Toggle"/>.</summary>
    public void Toggle(string place, bool on) => LinksChecklist.Toggle(Rows, Ticks, Brings, place, on);

    /// <summary>The button's sentence: rows SHOWN ticked, or the plain word when none is.</summary>
    public string PublishButton()
    {
        int count = ShownTicked.Count;
        return count == 0
            ? LinksChecklistWording.PublishNothingTicked
            : LinksChecklistWording.Fill(LinksChecklistWording.PublishButton,
                new Dictionary<string, string> { ["count"] = count.ToString(), ["pages"] = LinksChecklistWording.Pages(count) });
    }

    /// <summary>
    /// A row's second line. Coming with a ticked class wins (#398) and is
    /// followed by the plain linkedFrom part only; a row under another row
    /// says it goes when that page goes (#385, never "only"); otherwise its
    /// date and, when set, the hidden class it is first used in.
    /// </summary>
    public string SecondLine(LinksChecklistRow row)
    {
        string key = LinksChecklist.Key(row.Place);
        var parts = new List<string>();
        string F(string template, string? place, int count = 0) => LinksChecklistWording.Fill(template,
            new Dictionary<string, string>
            {
                ["name"] = place is null ? "" : NameOf(place),
                ["count"] = count.ToString(),
                ["pages"] = LinksChecklistWording.Pages(count),
            });

        if (row.IsClass)
        {
            parts.Add(LinksChecklistWording.ClassRow);
            if (BringsCount.TryGetValue(key, out int n) && n > 0) parts.Add(F(LinksChecklistWording.ComesWith, null, n));
            return string.Join(" · ", parts);
        }
        if (ComingWith.TryGetValue(key, out var cls))
        {
            parts.Add(F(LinksChecklistWording.ComesWithAClass, cls));
            if (row.LinkedFrom is { Count: > 0 } from)
                parts.Add(from.Count == 1 ? F(LinksChecklistWording.LinkedFrom, from[0])
                                          : F(LinksChecklistWording.LinkedFromSeveral, from[0], from.Count - 1));
            return string.Join(" · ", parts);
        }
        var parents = row.DependsOn.Where(p => RowTitles.ContainsKey(LinksChecklist.Key(p))).ToList();
        if (parents.Count > 0)
            parts.Add(parents.Count == 1 ? F(LinksChecklistWording.LinkedFromRow, parents[0])
                                         : F(LinksChecklistWording.LinkedFromSeveralRows, parents[0], parents.Count - 1));
        switch (row.Why)
        {
            case "keepsItsDate": parts.Add(LinksChecklistWording.KeepsItsDate); break;
            case "datedByTheBuild": parts.Add(LinksChecklistWording.KeepsTheDateItHas); break;
        }
        if (row.FirstUsedIn is { } first) parts.Add(F(LinksChecklistWording.FirstUsedIn, first));
        else if (parents.Count == 0 && row.LinkedFrom is { Count: > 0 } linked)
            parts.Add(linked.Count == 1 ? F(LinksChecklistWording.LinkedFrom, linked[0])
                                        : F(LinksChecklistWording.LinkedFromSeveral, linked[0], linked.Count - 1));
        return string.Join(" · ", parts);
    }
}

/// <summary>What pressing Publish did — the sheet's reply, the trail line and the answered file read it.</summary>
public sealed record LinksChecklistPublished(
    IReadOnlyList<string> Written,
    IReadOnlyList<string> RememberedUnticked,
    IReadOnlyList<string> LeftWithTheirPage,
    IReadOnlyList<string> ChangedSince,
    int CameWithAClass,
    int ClassesPublished,
    int BroughtByClasses)
{
    /// <summary>
    /// Pages Publish would have written but the writer DECLINED (#421; no
    /// column-0 place in their settings for a new line), by the name a teacher
    /// reads. Left exactly as they were, never in <see cref="Written"/> and
    /// never remembered as unticked.
    /// </summary>
    public IReadOnlyList<string> Declined { get; init; } = Array.Empty<string>();

    /// <summary>The sentence naming <see cref="Declined"/>, or null.</summary>
    public string? DeclinedSentence => Declined.Count == 0 ? null : AssistWording.PagesWhoseSettingsCannotBeAddedTo(Declined);

    /// <summary>
    /// What the teacher is told after Publish: how many pages were published
    /// (what was WRITTEN), each page changed since the sheet opened, and the
    /// pages the writer declined — named, never silently left hidden (#421).
    /// </summary>
    public string Reply(LinksChecklistSheet sheet)
    {
        var said = new List<string>
        {
            LinksChecklistWording.Fill(LinksChecklistWording.Published, new Dictionary<string, string>
            {
                ["count"] = Written.Count.ToString(),
                ["pages"] = LinksChecklistWording.Pages(Written.Count),
            }),
        };
        foreach (string changed in ChangedSince)
            said.Add(LinksChecklistWording.Fill(LinksChecklistWording.PageChangedSince,
                new Dictionary<string, string> { ["name"] = sheet.NameOf(changed) }));
        if (DeclinedSentence is { } declined) said.Add(declined);
        return string.Join(" ", said);
    }
}

public sealed partial class AssistWorkspace
{
    /// <summary>
    /// Open the sheet on an offer: re-read every row with this app's own
    /// reader, drop a page that is now visible or gone, FREE the rows under a
    /// page made visible and drop the rows under a page gone (to a fixed
    /// point); start from the offer's ticks except a place the answered file
    /// says was unticked; and work out what each class row brings with ONE
    /// call to the publish planner (#405), shared out by each class's own reach.
    /// </summary>
    public LinksChecklistSheet OpenLinksChecklist(LinksChecklistOffer offer)
    {
        var course = Course(offer.Course);
        int section = Section(course, offer.Section);
        var pages = PlaceIndex(course);

        var kept = offer.Rows.Where(r => pages.TryGetValue(LinksChecklist.Key(r.Place), out var path) && !IsVisible(path, section))
                              .ToList();
        var gone = offer.Rows.Where(r => !pages.ContainsKey(LinksChecklist.Key(r.Place))).Select(r => LinksChecklist.Key(r.Place)).ToHashSet();
        var visible = offer.Rows.Where(r => pages.TryGetValue(LinksChecklist.Key(r.Place), out var path) && IsVisible(path, section))
                                .Select(r => LinksChecklist.Key(r.Place)).ToHashSet();
        bool changed = true;
        while (changed)
        {
            changed = false;
            var next = new List<LinksChecklistRow>();
            var present = kept.Select(r => LinksChecklist.Key(r.Place)).ToHashSet();
            foreach (var row in kept)
            {
                var parents = row.DependsOn.Select(LinksChecklist.Key).ToList();
                if (parents.Count > 0 && parents.Any(visible.Contains))
                {
                    next.Add(row with { DependsOn = Array.Empty<string>() });
                    changed = true;
                    continue;
                }
                if (parents.Count > 0 && parents.All(p => gone.Contains(p) || (!present.Contains(p) && !visible.Contains(p))))
                {
                    gone.Add(LinksChecklist.Key(row.Place));
                    changed = true;
                    continue;
                }
                next.Add(row);
            }
            kept = next;
        }

        var (_, leftUnticked) = LinksChecklist.ReadAnswered(course.DirectoryPath, section);
        var ticks = kept.ToDictionary(r => LinksChecklist.Key(r.Place),
                                      r => r.Ticked && !leftUnticked.Contains(LinksChecklist.Key(r.Place)), StringComparer.Ordinal);

        var (brings, counts) = WhatEachClassBrings(course, section, kept, pages);
        var titles = TitlesInTheSection(course, section);
        return new LinksChecklistSheet
        {
            CourseCode = course.Code,
            Section = section,
            Rows = kept,
            Ticks = ticks,
            Brings = brings,
            BringsCount = counts,
            RowTitles = kept.ToDictionary(r => LinksChecklist.Key(r.Place), r => titles.RowTitle(r.Place, r.Title), StringComparer.Ordinal),
            NameOf = place => titles.Name(place),
        };
    }

    /// <summary>
    /// ONE planner call for every class row, shared out by each class's own
    /// reach (the walk from that class alone, stopping at classes). Not from
    /// firstUsedIn — 1,896 of 1,900 brought rows on the mac's payloads are
    /// reached through other pages — and not from a second walk alone, which
    /// would show a page the writer declines as coming.
    /// </summary>
    private (Dictionary<string, IReadOnlyList<string>> Brings, Dictionary<string, int> Counts) WhatEachClassBrings(
        Course course, int section, IReadOnlyList<LinksChecklistRow> rows, Dictionary<string, string> pages)
    {
        var brings = new Dictionary<string, IReadOnlyList<string>>(StringComparer.Ordinal);
        var counts = new Dictionary<string, int>(StringComparer.Ordinal);
        var classes = rows.Where(r => r.IsClass && pages.ContainsKey(LinksChecklist.Key(r.Place))).ToList();
        if (classes.Count == 0) return (brings, counts);

        var plan = PlanPublish(course.Code, section,
            classes.Select(r => Relative(Path.GetFullPath(pages[LinksChecklist.Key(r.Place)]))).ToList());
        var changing = plan.Changes.Where(c => c.BecauseLinked)
            .Select(c => Path.GetFullPath(PagePaths.ResolveInside(_folder, c.Page.RelativePath)))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        var graph = LinkGraph.Build(course, section);
        var classPaths = ClassPages(course, section).Select(Path.GetFullPath).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var placeOfPath = pages.ToDictionary(p => Path.GetFullPath(p.Value), p => p.Key, StringComparer.OrdinalIgnoreCase);

        foreach (var cls in classes)
        {
            string start = Path.GetFullPath(pages[LinksChecklist.Key(cls.Place)]);
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { start };
            var queue = new Queue<string>(new[] { start });
            var reach = new List<string>();
            while (queue.Count > 0)
                foreach (string target in graph.TargetsOf(queue.Dequeue()))
                {
                    if (!seen.Add(target) || classPaths.Contains(target)) continue;
                    reach.Add(target);
                    queue.Enqueue(target);
                }
            var brought = reach.Where(changing.Contains).ToList();
            string key = LinksChecklist.Key(cls.Place);
            counts[key] = brought.Count;
            brings[key] = brought.Where(placeOfPath.ContainsKey).Select(p => placeOfPath[p]).ToList();
        }
        return (brings, counts);
    }

    /// <summary>
    /// The sheet's Publish (#899 W7b2-8): ONE step, key
    /// <c>answerTheLinksChecklist</c>, made by the sheet (the mac's
    /// <c>LinksChecklistPublisher.publish</c>, <c>UndoStepMaker.sheet</c>):
    /// every page it publishes and dates, then the answered record, then the
    /// record of the later classes it published, planned in that order and
    /// made together, all or none. The front page is NOT repointed (ruling
    /// F1), so the step names no recompute, as the mac's names none. The
    /// answered file's leftUnticked holds only rows whose OWN tick was off.
    /// </summary>
    /// <exception cref="AssistRefusal">A deploy is under way; or the step was refused, "Nothing was changed: …", or
    /// stopped part way, the checklist's part-way sentence (<see cref="LinksChecklistWording.PagesYouTicked"/>).</exception>
    public LinksChecklistPublished PublishAndRemember(LinksChecklistSheet sheet)
    {
        var course = Course(sheet.CourseCode);
        int section = Section(course, sheet.Section);
        if (WorkLease.HeldBy(_folder, course.Code).Contains(WorkLease.Publishing))
            throw new AssistRefusal(LinksChecklistWording.Fill(LinksChecklistWording.DeployUnderWay,
                new Dictionary<string, string> { ["course"] = course.Code }));

        string backup = BackUpOnceForThisConversation(course, section);
        _ = backup;
        using var recording = UndoHistory.Record(_undo, $"published pages that links lead to in {course.Code} Section {section}");
        var step = NewUndoStep(LinksChecklist.AnsweredActionKey, course.Code, section, madeBy: "sheet");
        LinksChecklistPublished result;
        try { result = PlanThePress(sheet, step); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // A page the plan needs could not be read: nothing was written
            // (the mac's catch around planning, AssistToolRefusal.unreadablePage).
            throw RefusalForAPressThatStopped(error, sheet, planning: true);
        }
        try { MakeTheUndoStep(step); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            throw RefusalForAPressThatStopped(error, sheet, planning: false);
        }
        recording.Done();
        NotePublished(sheet, result);
        return result;
    }

    /// <summary>
    /// A press whose step failed, said as the mac's <c>publish</c> and
    /// <c>LinksChecklistPublisher.sentence(forRefused:)</c> say it (W7b2-8
    /// review 1, L1). Every refusal wrote nothing (the press is one step):
    /// a page the plan could not read, and a file the door could not read
    /// just now that really cannot be read, are the unreadable-page sentence
    /// naming the course; a section page changed since it was checked is
    /// <c>linksChecklist.wording.pageChangedSince</c>, the page named as the
    /// sheet names it; a file left holding the new content, its earlier
    /// content kept beside it, is the checklist part-way sentence naming each
    /// kept file, and nothing more (the mac's sheet points at no button
    /// after it); anything else is "Nothing was changed: …".
    /// </summary>
    internal AssistRefusal RefusalForAPressThatStopped(Exception error, LinksChecklistSheet sheet, bool planning)
    {
        var course = Course(sheet.CourseCode);
        if (planning) return new AssistRefusal(UnreadablePage(course.Code));
        if (error is UndoStepLeftPartWayException)
        {
            NoteAChangeWithNoUndoEntry();
            return new AssistRefusal(AssistWording.PublishStoppedPartWay(LinksChecklistWording.PagesYouTicked, ReasonItStopped(error)));
        }
        if (error is UndoStepRefusedException { Refusal: { Path: { } named } refusal })
        {
            string full = Path.IsPathRooted(named) ? named : UndoDoor.FullPath(_folder, named);
            if (refusal.Kind == UndoRefusalKind.ChangedSince && PageNameOnTheSheet(sheet, course, full) is { } name)
                return new AssistRefusal(LinksChecklistWording.Fill(LinksChecklistWording.PageChangedSince,
                    new Dictionary<string, string> { ["name"] = name }));
            // "Could not be read" only for a file that really cannot be read
            // now; a page that is a link, or a folder, cannot be checked and
            // so was not written, which "Nothing was changed" says.
            if (refusal.Kind == UndoRefusalKind.CannotTellNow && UndoCurrent.Read(full) is UndoCurrent.CannotReadNow)
                return new AssistRefusal(UnreadablePage(course.Code));
        }
        return new AssistRefusal(NothingWasChanged(error));
    }

    /// <summary>The page at <paramref name="fullPath"/> as the sheet names it, or null when it is not one of the course's pages (the answered record, the kept record).</summary>
    private string? PageNameOnTheSheet(LinksChecklistSheet sheet, Course course, string fullPath)
    {
        if (!fullPath.EndsWith(".md", StringComparison.OrdinalIgnoreCase)) return null;
        string place = PlaceOf(course, Relative(Path.GetFullPath(fullPath)));
        string key = LinksChecklist.Key(place);
        if (!PlaceIndex(course).ContainsKey(key)) return null;
        return sheet.RowTitles.TryGetValue(key, out string? title) ? title : sheet.NameOf(place);
    }

    /// <summary>
    /// Plans the press into <paramref name="step"/> without making it:
    /// the ticked classes through the normal class publish (they bring their
    /// pages, dated by that class, the class's own date untouched), the going
    /// page rows through the exact-pages publish with the offer's date (none
    /// for keepsItsDate, datedByTheBuild, structuralNeverDated); where a page
    /// is both, the CLASS's date wins; then the answered record and the kept
    /// record. Each page is read as the step will leave it, and each before
    /// is read here, at plan time. Nothing is freed here: what goes is worked
    /// out from the rows AS SHOWN, less pages changed since.
    /// </summary>
    internal LinksChecklistPublished PlanThePress(LinksChecklistSheet sheet, UndoActionStep step)
    {
        var course = Course(sheet.CourseCode);
        int section = Section(course, sheet.Section);
        PlanningThrough = step;
        try
        {
            var result = PlanThePages(sheet, course, section, step);
            LinksChecklist.PlanAnswered(step, course.DirectoryPath, section, sheet.Rows.Select(r => r.Place),
                                        result.RememberedUnticked, DateTime.UtcNow);
            // A class dated after the next class that the teacher published from
            // here is one they chose: kept at its date (#475), or the next Deploy
            // would offer to hide it again and the two questions would undo each
            // other (the mac's batch B implementation review, finding 2).
            KeepTheClassesItPublished(course, section, result.Written, step);
            return result;
        }
        finally { PlanningThrough = null; }
    }

    private LinksChecklistPublished PlanThePages(LinksChecklistSheet sheet, Course course, int section, UndoActionStep step)
    {
        var pages = PlaceIndex(course);
        var going = sheet.Going;
        var coming = sheet.ComingWith;
        var changedSince = new List<string>();
        bool Hidden(string key) => pages.TryGetValue(key, out var path) && !IsVisibleThrough(step, path, section);

        var rowByKey = sheet.Rows.ToDictionary(r => LinksChecklist.Key(r.Place), r => r, StringComparer.Ordinal);
        var classesGoing = sheet.Rows.Where(r => r.IsClass && going.Contains(LinksChecklist.Key(r.Place))).ToList();
        var stillHiddenClasses = new List<LinksChecklistRow>();
        foreach (var cls in classesGoing)
        {
            if (Hidden(LinksChecklist.Key(cls.Place))) { stillHiddenClasses.Add(cls); continue; }
            changedSince.Add(sheet.RowTitles[LinksChecklist.Key(cls.Place)]);
        }
        // A row shown coming with a class: named when it, or its class, changed since.
        foreach (var (row, cls) in coming)
        {
            if (going.Contains(row)) continue;
            bool classStill = stillHiddenClasses.Any(c => LinksChecklist.Key(c.Place) == LinksChecklist.Key(cls));
            if (!classStill || !Hidden(row)) changedSince.Add(sheet.RowTitles[row]);
        }

        // The classes' own plan — the same planner the assistant's publish uses.
        PublishPlan? classPlan = stillHiddenClasses.Count == 0 ? null : PlanPublish(course.Code, section,
            stillHiddenClasses.Select(r => Relative(Path.GetFullPath(pages[LinksChecklist.Key(r.Place)]))).ToList());
        var brought = classPlan?.Changing.Select(p => Path.GetFullPath(PagePaths.ResolveInside(_folder, p.RelativePath)))
                          .ToHashSet(StringComparer.OrdinalIgnoreCase) ?? new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        string tail = SiblingTimeAndOffset(course, section, ClassPages(course, section));
        var written = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        // Pages the writer DECLINED (#421, the mac's #186): named in the reply,
        // never counted as written, and never remembered as left unticked —
        // the teacher ticked them; they stay hidden for a reason of their own.
        var declined = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        void Decline(string full, string name) => declined.TryAdd(Path.GetFullPath(full), name);

        if (classPlan is not null)
        {
            foreach (var page in classPlan.CannotBeAddedTo)
                Decline(PagePaths.ResolveInside(_folder, page.RelativePath), page.DisplayTitle);
            foreach (var page in classPlan.Changing)
            {
                string full = PagePaths.ResolveInside(_folder, page.RelativePath);
                var (updated, edit) = PageFrontmatter.SetDraft(step.ReadText(full), page.FrontmatterKey, false, section);
                if (edit.NoRoomForAKey) { Decline(full, page.DisplayTitle); continue; }
                if (edit.Changed) { step.Write(full, updated); written.Add(Path.GetFullPath(full)); }
            }
            // Each page a ticked class brings takes THAT class's date (the
            // first class in the sheet's order when two bring it) — not the
            // earliest class anywhere that can reach it, which is what the
            // assistant's date rule would pick through a visible overview.
            var classPaths = ClassPages(course, section).Select(Path.GetFullPath).ToHashSet(StringComparer.OrdinalIgnoreCase);
            var graph = LinkGraph.Build(course, section);
            var dated = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var cls in stillHiddenClasses)
            {
                string start = Path.GetFullPath(pages[LinksChecklist.Key(cls.Place)]);
                if (PageFrontmatter.CreatedOn(step.ReadText(start), section, true) is not { } classDay) continue;
                var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { start };
                var queue = new Queue<string>(new[] { start });
                while (queue.Count > 0)
                    foreach (string target in graph.TargetsOf(queue.Dequeue()))
                    {
                        if (!seen.Add(target) || classPaths.Contains(target)) continue;
                        queue.Enqueue(target);
                        if (!brought.Contains(target) || !dated.Add(target)) continue;
                        string createdKey = PageFrontmatter.CreatedKeyFor(section, PagePaths.IsSectionLocal(course.DirectoryPath, target));
                        var (updated, moved) = PageFrontmatter.SetCreated(step.ReadText(target), createdKey, classDay, tail);
                        if (moved) step.Write(target, updated);
                    }
            }
            // The front page is deliberately left as it is (ruling F1): classPlan.Index is not applied.
        }

        foreach (var key in going)
        {
            if (!rowByKey.TryGetValue(key, out var row) || row.IsClass) continue;
            if (!Hidden(key)) continue;   // made visible or gone since: dropped, not written again
            string full = Path.GetFullPath(pages[key]);
            if (brought.Contains(full)) continue;   // a ticked class brings it: the CLASS's date wins
            var planned = Plan(course, section, full, draft: false, viaLink: false);
            string text = step.ReadText(full);
            var (updated, edit) = PageFrontmatter.SetDraft(text, planned.FrontmatterKey, false, section);
            // Declined: not even the date is written — a hidden page with a new date is no publish.
            if (edit.NoRoomForAKey) { Decline(full, planned.DisplayTitle); continue; }
            if (row.Date is { } iso && DateOnly.TryParse(iso, System.Globalization.CultureInfo.InvariantCulture,
                                                          System.Globalization.DateTimeStyles.None, out var day))
            {
                string createdKey = PageFrontmatter.CreatedKeyFor(section, PagePaths.IsSectionLocal(course.DirectoryPath, full));
                var (dated, moved) = PageFrontmatter.SetCreated(updated, createdKey, day, tail);
                if (moved) { updated = dated; }
            }
            if (edit.Changed || updated != text) { step.Write(full, updated); written.Add(full); }
        }

        // What the press left hidden, of both kinds — never a page a ticked
        // class WROTE, and never a page that is no longer hidden.
        var remembered = new List<string>();
        var leftWith = new List<string>();
        int cameWith = 0;
        foreach (var row in sheet.Rows.Where(r => !r.IsClass))
        {
            string key = LinksChecklist.Key(row.Place);
            bool wasWritten = pages.TryGetValue(key, out var p) && written.Contains(Path.GetFullPath(p));
            bool byAClass = pages.TryGetValue(key, out var bp) && brought.Contains(Path.GetFullPath(bp));
            if (wasWritten || byAClass)
            {
                if (!going.Contains(key)) cameWith++;
                continue;
            }
            if (!Hidden(key)) continue;
            if (pages.TryGetValue(key, out var dp) && declined.ContainsKey(Path.GetFullPath(dp))) continue;
            bool ownTick = sheet.Ticks.TryGetValue(key, out bool on) && on;
            if (ownTick) leftWith.Add(row.Place); else remembered.Add(row.Place);
        }
        foreach (var cls in sheet.Rows.Where(r => r.IsClass))
        {
            string key = LinksChecklist.Key(cls.Place);
            if (going.Contains(key) || !Hidden(key)) continue;
            remembered.Add(cls.Place);
        }

        return new LinksChecklistPublished(
            written.Select(path => placeOrTitle(path)).ToList(), remembered, leftWith,
            changedSince.Distinct().ToList(), cameWith, stillHiddenClasses.Count,
            classPlan?.Changing.Count(p => !stillHiddenClasses.Any(c => LinksChecklist.Key(c.Place) == LinksChecklist.Key(PlaceOf(course, p.RelativePath)))) ?? 0)
        {
            Declined = declined.Values.ToList(),
        };

        string placeOrTitle(string path) => PlaceOf(course, Relative(path));
    }

    /// <summary>
    /// The rollover's release of the published-pages record (#392), recorded
    /// in this workspace's undo history so "undo that" puts it back.
    /// </summary>
    public void ReleasePublishedPagesForARollover(Course course, int section)
    {
        using var recording = UndoHistory.Record(_undo, $"released section {section}'s record of published pages");
        LinksChecklist.ReleasePublishedPages(course.DirectoryPath, section, DateTime.Now, _undo);
        recording.Done();
    }

    // ---- The trail (activityTrail.mustRecord) ----------------------------

    /// <summary>Record that the sheet was shown. <paramref name="occasion"/> is in words: "after a preview", "from the menu".</summary>
    public static void NoteOffered(LinksChecklistSheet sheet, string occasion)
    {
        int Count(string group) => sheet.Rows.Count(r => r.Group == group);
        int under = LinksChecklist.ShownOrder(sheet.Rows).Count(x => x.Depth > 0);
        Plantoir.Core.Scripting.ActivityTrail.Note(Plantoir.Core.Scripting.ActivityTrail.Event.OfferedToPublishPagesThatLinksLeadTo,
            $"offered to publish pages that links lead to, {occasion}: {Count(LinksChecklist.FromAClassGroup)} used by a class, " +
            $"{Count(LinksChecklist.NotReachedGroup)} linked from other pages, {Count(LinksChecklist.ClassGroup)} classes; " +
            $"{under} listed under another page; {sheet.ShownTicked.Count} ticked",
            sheet.CourseCode, sheet.Section);
    }

    /// <summary>Record a Publish press: counts and at most ten PLACES — never anything written on a page.</summary>
    public static void NotePublished(LinksChecklistSheet sheet, LinksChecklistPublished result)
    {
        var places = result.Written.Take(10).ToList();
        string named = string.Join(", ", places) + (result.Written.Count > 10 ? $" and {result.Written.Count - 10} more" : "");
        Plantoir.Core.Scripting.ActivityTrail.Note(Plantoir.Core.Scripting.ActivityTrail.Event.PublishedPagesThatLinksLedTo,
            $"published {result.Written.Count} {(result.Written.Count == 1 ? "page" : "pages")} that links led to; " +
            $"{result.ClassesPublished} classes bringing {result.BroughtByClasses} more ({result.CameWithAClass} of them on the list); " +
            $"{result.RememberedUnticked.Count} left unticked, {result.LeftWithTheirPage.Count} left with the page they come under: {named}",
            sheet.CourseCode, sheet.Section);
        NoteLeftHidden(sheet, "Publish with some unticked", result.RememberedUnticked.Count + result.LeftWithTheirPage.Count,
                       result.LeftWithTheirPage.Count);
        NoteSettingsLeftAsTheyWere("publishing pages that links lead to", result.Declined.Count, sheet.CourseCode, sheet.Section);
    }

    private static void NoteLeftHidden(LinksChecklistSheet sheet, string how, int total, int followers)
    {
        if (total <= 0) return;
        Plantoir.Core.Scripting.ActivityTrail.Note(Plantoir.Core.Scripting.ActivityTrail.Event.LeftPagesHiddenThatLinksLeadTo,
            $"left {total} {(total == 1 ? "page" : "pages")} hidden that links lead to ({followers} with the page they come under), {how}",
            sheet.CourseCode, sheet.Section);
    }

    /// <summary>
    /// Records as kept (<see cref="LaterClassesKept"/>) any class among
    /// <paramref name="places"/> the question at Deploy would now ask about:
    /// a class published from the links checklist, or by naming its date
    /// (Publish Class for a Date…, <c>publish_class_on</c>). A class that
    /// would not be asked about — tomorrow's — leaves no record.
    /// </summary>
    internal void KeepTheClassesItPublished(Course course, int section, IEnumerable<string> places, UndoActionStep step)
    {
        var published = places.Select(ClassesDatedLater.PlaceKey).ToHashSet(StringComparer.Ordinal);
        Func<string, string> readPage = step.ReadText;
        Func<string, string?> readRecord = step.ReadTextIfAny;
        // Planned into the action's own step: written only if the pages are
        // (#899 W7a; the links checklist's press, W7b2-8), and never part of
        // today's in-memory undo, as before. A record that cannot be read or
        // planned just now costs only the record, never the publish, as
        // before and as the mac's `try?` (part three, review 1, MEDIUM 2;
        // LaterClassesKept's own sentence).
        try
        {
            var kept = ClassesDatedLater.FlaggedIn(course, section, Today(), readPage, readRecord)
                .Where(page => published.Contains(page.Place))
                .ToList();
            LaterClassesKept.PlanInto(step, course.DirectoryPath, section, kept);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
    }

    /// <summary>The classes a publish by DATE published, kept at that date (#475): the teacher named the day. Planned into <paramref name="step"/>.</summary>
    internal void KeepTheClassesPublishedByTheirDate(PublishPlan plan, UndoActionStep step)
    {
        var course = Course(plan.CourseCode);
        KeepTheClassesItPublished(course, plan.SectionNumber, plan.NamedPages.Select(page =>
            ClassesDatedLater.PlaceOf(course.DirectoryPath, PagePaths.ResolveInside(_folder, page.RelativePath))), step);
    }

    /// <summary>
    /// Publish Class for a Date whose pages needed no change (#899 W7a): a
    /// class it names that the question at Deploy would ask about is still
    /// kept at its date, on a step of its own (<c>publishClassForADate</c>),
    /// as the mac's does. A record that cannot be written costs the question
    /// once more, nothing else (<see cref="LaterClassesKept"/>).
    /// </summary>
    public void KeepTheClassesPublishedByTheirDateOnAStepOfTheirOwn(PublishPlan plan)
    {
        var step = NewUndoStep("publishClassForADate", plan.CourseCode, plan.SectionNumber);
        try
        {
            KeepTheClassesPublishedByTheirDate(plan, step);
            MakeTheUndoStep(step);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
    }

    /// <summary>
    /// Not Now: nothing written but the answer, as ONE step of that one record
    /// (#899 W7b2-8; the mac's <c>LinksChecklistAnswered.write</c> on a step of
    /// its own, key <c>answerTheLinksChecklist</c>, made by the sheet); every
    /// row left (0 followers, since the press leaves every row).
    /// </summary>
    /// <returns>False when the record could not be written: the checklist is offered again, nothing else (the mac's <c>try?</c>).</returns>
    public bool NotNow(LinksChecklistSheet sheet)
    {
        var course = Course(sheet.CourseCode);
        int section = Section(course, sheet.Section);
        var unticked = sheet.Rows.Where(r => !(sheet.Ticks.TryGetValue(LinksChecklist.Key(r.Place), out bool on) && on))
                                 .Select(r => r.Place).ToList();
        bool remembered = LinksChecklist.RecordTheAnswer(NewUndoStep(LinksChecklist.AnsweredActionKey, course.Code, section, madeBy: "sheet"),
                                                         course.DirectoryPath, section, sheet.Rows.Select(r => r.Place), unticked, DateTime.UtcNow);
        NoteLeftHidden(sheet, "Not Now", sheet.Rows.Count, 0);
        return remembered;
    }

    /// <summary>Every page of the course by its place (course-relative, no .md), in composed form.</summary>
    private Dictionary<string, string> PlaceIndex(Course course) =>
        Directory.EnumerateFiles(course.DirectoryPath, "*.md", SearchOption.AllDirectories)
            .GroupBy(path => LinksChecklist.Key(PlaceOf(course, Relative(path))), StringComparer.Ordinal)
            .ToDictionary(group => group.Key, group => group.First(), StringComparer.Ordinal);

    private string PlaceOf(Course course, string relativeToFolder)
    {
        string full = PagePaths.ResolveInside(_folder, relativeToFolder);
        string place = Path.GetRelativePath(course.DirectoryPath, full).Replace('\\', '/');
        return place.EndsWith(".md", StringComparison.OrdinalIgnoreCase) ? place[..^3] : place;
    }

    private static bool IsVisible(string path, int section)
    {
        try { return PageFrontmatter.Visibility(File.ReadAllText(path), section) == PageVisibility.Visible; }
        catch { return false; }
    }

    /// <summary><see cref="IsVisible"/>, the page read as <paramref name="step"/> will leave it.</summary>
    private static bool IsVisibleThrough(UndoActionStep step, string path, int section)
    {
        try { return PageFrontmatter.Visibility(step.ReadText(path), section) == PageVisibility.Visible; }
        catch { return false; }
    }

    /// <summary>
    /// Names as #362 names them (linksChecklist.naming): a page's title (front
    /// matter, else file name, else the folder for an untitled index.md), with
    /// its folder when ANOTHER page in the SECTION shares the title.
    /// </summary>
    private SectionTitles TitlesInTheSection(Course course, int section)
    {
        var titles = PagePaths.MarkdownPages(course.DirectoryPath, section)
            .Select(path => (Place: LinksChecklist.Key(PlaceOf(course, Relative(path))), Title: TitleOf(path)))
            .ToList();
        return new SectionTitles(course, titles);
    }

    private sealed class SectionTitles(Course course, List<(string Place, string Title)> titles)
    {
        private readonly Dictionary<string, string> _byPlace =
            titles.GroupBy(t => t.Place).ToDictionary(g => g.Key, g => g.First().Title, StringComparer.Ordinal);

        private bool Shared(string title) => titles.Count(t => t.Title == title) > 1;

        private static string FolderOf(string place) =>
            place.Contains('/') ? place[..place.LastIndexOf('/')] : "";

        private string TitleFor(string place, string? fallback)
        {
            string key = LinksChecklist.Key(place);
            if (_byPlace.TryGetValue(key, out var t)) return t;
            // A page gone since keeps the title the build read.
            return fallback ?? (place.Contains('/') ? place[(place.LastIndexOf('/') + 1)..] : place);
        }

        public string RowTitle(string place, string? fallback)
        {
            string title = TitleFor(place, fallback);
            return Shared(title)
                ? LinksChecklistWording.Fill(LinksChecklistWording.RowInFolder,
                    new Dictionary<string, string> { ["page"] = title, ["folder"] = FolderOf(LinksChecklist.Key(place)) })
                : title;
        }

        public string Name(string place)
        {
            string title = TitleFor(place, null);
            return Shared(title) ? $"“{title}” (in {FolderOf(LinksChecklist.Key(place))})" : $"“{title}”";
        }
    }
}

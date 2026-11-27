using System.Text.Json.Nodes;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Undo;

/// <summary>What recovery did with one step.</summary>
internal enum UndoRecoveryOutcome
{
    /// <summary>Every file where the work started: <c>failed</c>.</summary>
    NothingTookEffect,
    /// <summary>Every file where the work was going: <c>applied</c>, <c>undone</c> or <c>redone</c>.</summary>
    Completed,
    /// <summary>Some of each: what took effect was put back, <c>rolledBack</c>.</summary>
    RolledBack,
    /// <summary>A file in the way (or a put-back that cannot be planned): <c>interrupted</c>, the list cleared.</summary>
    Interrupted,
    /// <summary>Shadow: recorded, never repaired.</summary>
    LeftAlone,
}

/// <summary>One step recovery settled: its number, the work it ended, the outcome, and the step itself (for re-deriving after the hold).</summary>
internal sealed record UndoRecoveryResult(long Seq, UndoPhase Phase, UndoRecoveryOutcome Outcome, UndoStep Step, string Root,
                                          int FilesPutBack = 0, int FilesInTheWay = 0);

/// <summary>What one run of recovery came to: the steps it settled, and whether a test (or the harness) stopped it at a kill point.</summary>
/// <param name="Left">The steps it tried and left for later, each with why (a file in use, a page that cannot be read now):
/// the true answer an Undo or a Redo gives when such a step is the newest (W3's review, LOW 4).</param>
/// <param name="NotRun">Why recovery did not run at all (the list busy past its wait, unreadable, its folder not makeable), or null when it ran.</param>
internal sealed record UndoRecoveryRun(IReadOnlyList<UndoRecoveryResult> Settled, bool StoppedByATest,
                                       IReadOnlyDictionary<long, UndoRefusal>? Left = null, string? NotRun = null);

/// <summary>One line for the activity trail: the course and section it is about, and the words after them.</summary>
/// <param name="Kept">The hidden names of the kept files the line names (U3c's lines), for a test to match against the disk.</param>
/// <param name="NoLongerInTheList">Of those, the ones said to be kept because the list no longer holds a copy of them.</param>
internal sealed record UndoTrailLine(ActivityTrail.Event Event, string? Course, long? Section, string Words,
                                     IReadOnlyList<string>? Kept = null, IReadOnlyList<string>? NoLongerInTheList = null);

/// <summary>What became of a change the list could not record (the mac's <c>UndoUnrecordedChange</c>).</summary>
internal enum UndoUnrecordedChange { WentAhead, NothingWasChanged, StoppedPartWay, MadeButNotClosed }

/// <summary>
/// The trail lines Undo writes (<c>activityTrail.mustRecord</c>), in the
/// mac's words (<c>UndoTrail</c> in <c>UndoAppSeams.swift</c>). The door is
/// given a sink for them; the app's start-up (W4) passes
/// <see cref="ToTheActivityTrail"/>, a test passes a list.
/// </summary>
internal static class UndoTrail
{
    /// <summary>
    /// <c>the undo list could not record publishPages: the list was busy. The
    /// change went ahead (the list is not in use yet).</c> (the mac's
    /// <c>couldNotRecordLine</c>; <c>activityTrail.mustRecord</c>'s "undo could
    /// not record a step"). The course and section go in front, as every line.
    /// </summary>
    internal static string CouldNotRecordWords(string action, string why, UndoUnrecordedChange change) =>
        $"the undo list could not record {action}: {why}. " + change switch
        {
            UndoUnrecordedChange.WentAhead => "The change went ahead (the list is not in use yet).",
            UndoUnrecordedChange.NothingWasChanged => "Nothing was changed.",
            UndoUnrecordedChange.StoppedPartWay => "The change stopped part way; what a file held before is kept beside it.",
            _ => "The change was made; its record is finished at the next chance.",
        };

    /// <summary><c>the undo list put back 2 files left part way by a change that stopped</c>.</summary>
    internal static string RolledBackWords(UndoPhase phase, int files)
    {
        string what = phase switch
        {
            UndoPhase.Undoing => "an undo",
            UndoPhase.Redoing => "a redo",
            _ => "a change",
        };
        return $"the undo list put back {Files(files)} left part way by {what} that stopped";
    }

    /// <summary>
    /// <c>the undo list keeps the folder courses/ICS3U/made, set aside by a
    /// change that stopped, as courses/ICS3U/made (kept by Undo), because
    /// something else now holds courses/ICS3U/made</c>, or <c>the undo list
    /// puts the folder courses/ICS3U/made back in its place; it changed while
    /// a change that stopped had set it aside (1 file added)</c> (the mac's
    /// <c>foundAFolderSetAsideLine</c>). Written just before the rename, so it
    /// says what is being done.
    /// </summary>
    internal static string FoundAFolderSetAsideWords(string place, string? keptAs, string changes) =>
        keptAs is not null
            ? $"the undo list keeps the folder {place}, set aside by a change that stopped, as {keptAs}, because something else now holds {place}"
            : $"the undo list puts the folder {place} back in its place; it changed while a change that stopped had set it aside ({changes})";

    /// <summary><c>… , found 1 file changed by hand since, and cleared the list</c>.</summary>
    internal static string InterruptedWords(UndoPhase phase, int putBack, int inTheWay) =>
        RolledBackWords(phase, putBack) + $", found {Files(inTheWay)} changed by hand since, and cleared the list";

    private static string Files(int count) => count == 1 ? "1 file" : $"{count} files";

    /// <summary>"a change", "an undo" or "a redo": the work that stopped.</summary>
    private static string What(UndoPhase phase) => phase switch
    {
        UndoPhase.Undoing => "an undo",
        UndoPhase.Redoing => "a redo",
        _ => "a change",
    };

    /// <summary><c>“A.md”</c>: the page a kept file's hidden name stands beside.</summary>
    private static string PlaceOfKept(string kept) => "\u201c" + (UndoSwap.PlaceOfStagedName(kept) ?? kept) + "\u201d";

    private static string Quoted(string name) => "\u201c" + name + "\u201d";

    /// <summary>
    /// <c>the undo list could not put back 1 file left part way by a change
    /// that stopped, because what it needs to put it back is no longer in the
    /// list, and cleared the list. What “A.md” held before is kept beside it as
    /// the hidden file “.A.md.plantoir-undo-4-apply-orig”.</c> (the mac's
    /// <c>couldNotPutBackLine</c>): one sentence per kept original on the disk.
    /// </summary>
    internal static string CouldNotPutBackWords(UndoPhase phase, int leftPartWay, IReadOnlyList<string> keptOriginals)
    {
        var line = new System.Text.StringBuilder();
        line.Append($"the undo list could not put back {Files(leftPartWay)} left part way by {What(phase)} that stopped, ");
        line.Append($"because what it needs to put {(leftPartWay == 1 ? "it" : "them")} back is no longer in the list, and cleared the list.");
        foreach (string kept in keptOriginals)
            line.Append($" What {PlaceOfKept(kept)} held before is kept beside it as the hidden file {Quoted(kept)}.");
        return line.ToString();
    }

    /// <summary>
    /// <c>the undo list settled a change that stopped. What “A.md” held before
    /// is kept beside it as the hidden file “…”, because it differs from what
    /// the list recorded.</c>, or <c>because the list no longer holds a copy of
    /// it.</c> for one in <paramref name="noLongerInTheList"/> (the mac's
    /// <c>keptAnOriginalLine</c>).
    /// </summary>
    internal static string KeptWhatAPageHeldWords(UndoPhase phase, IReadOnlyList<string> keptOriginals, IReadOnlyList<string> noLongerInTheList)
    {
        var line = new System.Text.StringBuilder();
        line.Append($"the undo list settled {What(phase)} that stopped.");
        foreach (string kept in keptOriginals)
        {
            string because = noLongerInTheList.Contains(kept)
                ? "because the list no longer holds a copy of it"
                : "because it differs from what the list recorded";
            line.Append($" What {PlaceOfKept(kept)} held before is kept beside it as the hidden file {Quoted(kept)}, {because}.");
        }
        return line.ToString();
    }

    /// <summary>
    /// <c>Undo put back “A.md” from what was kept beside it, but the list could
    /// not keep a copy of all it needs for this change, so what it could not
    /// keep stays beside the page, and the next Undo or Redo of this change
    /// uses it. What “A.md” held a moment before is kept beside it as the
    /// hidden file “…”.</c> (the mac's <c>keptWhatItReplacedLine</c>, U4b2-4).
    /// Each kept file is given by its path in the working folder
    /// (<c>&lt;page's folder&gt;/&lt;hidden name&gt;</c>; a bare hidden name
    /// stands for a page at the top of the working folder), so two pages with
    /// one name in two folders are two pages. A page is said to come "from
    /// what was kept beside it" only when its path is in
    /// <paramref name="putBackFromAKeptOriginal"/> (null: every page named
    /// was). A named page whose file name another page of the step shares
    /// (<paramref name="pagesOfTheStep"/>, every op's path, named here or not)
    /// is named by its path inside <c>courses/&lt;course&gt;/</c>, or by its
    /// path in the working folder when it is outside that or the step has no
    /// course. The hidden file is always its bare name. Names and prefixes are
    /// compared by <see cref="SameSpelling"/>.
    /// </summary>
    internal static string KeptWhatItReplacedWords(bool isUndo, IReadOnlyList<string> keptOfWhatItHeld, IReadOnlyList<string> keptOfWhatItHoldsNow,
                                                   string? course = null, IReadOnlyList<string>? putBackFromAKeptOriginal = null,
                                                   IReadOnlyList<string>? pagesOfTheStep = null)
    {
        var pages = new List<string>();
        foreach (string kept in keptOfWhatItHeld.Concat(keptOfWhatItHoldsNow))
        {
            string page = PageOfKept(kept);
            if (!ContainsSpelling(pages, page)) pages.Add(page);
        }
        var pagesThatCouldBeMistaken = new List<string>(pages);
        foreach (string page in pagesOfTheStep ?? [])
        {
            if (!ContainsSpelling(pagesThatCouldBeMistaken, page)) pagesThatCouldBeMistaken.Add(page);
        }
        var fromTheList = new List<string>();
        var fromKept = new List<string>();
        foreach (string page in pages)
        {
            string named = NameOnTheLine(page, pagesThatCouldBeMistaken, course);
            if (putBackFromAKeptOriginal is null || ContainsSpelling(putBackFromAKeptOriginal, page)) fromKept.Add(named);
            else fromTheList.Add(named);
        }
        string which = isUndo ? "Undo" : "Redo";
        var line = new System.Text.StringBuilder();
        if (pages.Count == 0) line.Append($"{which} put back a page");
        else if (fromKept.Count == 0) line.Append($"{which} put back {string.Join(", ", fromTheList)}");
        else if (fromTheList.Count == 0) line.Append($"{which} put back {string.Join(", ", fromKept)} from what was kept beside it");
        else line.Append($"{which} put back {string.Join(", ", fromTheList)}, and put back {string.Join(", ", fromKept)} from what was kept beside it");
        line.Append(", but the list could not keep a copy of all it needs for this change, ");
        line.Append("so what it could not keep stays beside the page, and the next Undo or Redo of this change uses it.");
        foreach (string kept in keptOfWhatItHeld)
            line.Append($" What {NameOnTheLine(PageOfKept(kept), pagesThatCouldBeMistaken, course)} held a moment before is kept beside it as the hidden file {Quoted(HiddenNameOf(kept))}.");
        foreach (string kept in keptOfWhatItHoldsNow)
            line.Append($" What {NameOnTheLine(PageOfKept(kept), pagesThatCouldBeMistaken, course)} holds now is kept beside it as the hidden file {Quoted(HiddenNameOf(kept))}.");
        return line.ToString();
    }

    /// <summary>
    /// Whether two names or paths are spelled the same: in Unicode
    /// normalization form C, then ordinally (documentation 12, "What W4c and
    /// W8 owe from U4b2-6", its last bullet; the mac's <c>String ==</c>, which
    /// treats canonically equivalent forms as equal). Capitals differ:
    /// <c>Index.md</c> and <c>index.md</c> are two names. The one comparison
    /// of the kept line's names, pages and course prefix.
    /// </summary>
    internal static bool SameSpelling(string first, string second) =>
        string.Equals(first.Normalize(System.Text.NormalizationForm.FormC), second.Normalize(System.Text.NormalizationForm.FormC), StringComparison.Ordinal);

    private static bool ContainsSpelling(IEnumerable<string> list, string wanted)
    {
        foreach (string item in list)
        {
            if (SameSpelling(item, wanted)) return true;
        }
        return false;
    }

    /// <summary>The last part of a <c>/</c>-separated path: a kept file's hidden name, or a page's file name.</summary>
    private static string HiddenNameOf(string path) => path[(path.LastIndexOf('/') + 1)..];

    /// <summary>
    /// The page a kept file stands beside, by its place in the working
    /// folder: the kept file's folder plus the name between the hidden name's
    /// leading dot and its last <c>.plantoir-undo-</c>
    /// (<c>courses/ICS3U/Section 1/.index.md.plantoir-undo-4-undo-orig</c>
    /// gives <c>courses/ICS3U/Section 1/index.md</c>; a bare hidden name, the
    /// page's name alone). The mac's <c>UndoTrail.pageOfKept</c>.
    /// </summary>
    internal static string PageOfKept(string kept)
    {
        int slash = kept.LastIndexOf('/');
        string hidden = kept[(slash + 1)..];
        string pageName = UndoSwap.PlaceOfStagedName(hidden) ?? hidden;
        return slash < 0 ? pageName : kept[..(slash + 1)] + pageName;
    }

    /// <summary>
    /// A page as the kept line names it, quoted: by its file name, or, when
    /// another of <paramref name="pages"/> has the same file name, by its path
    /// with <c>courses/&lt;course&gt;/</c> taken off, or its whole path in the
    /// working folder when it is not under that or there is no course (the
    /// mac's <c>UndoTrail.nameOnTheLine</c>).
    /// </summary>
    private static string NameOnTheLine(string page, IReadOnlyList<string> pages, string? course)
    {
        string pageName = HiddenNameOf(page);
        bool sharesItsName = false;
        foreach (string other in pages)
        {
            if (!SameSpelling(other, page) && SameSpelling(HiddenNameOf(other), pageName)) sharesItsName = true;
        }
        if (!sharesItsName) return Quoted(pageName);
        // The prefix is the first two parts, each compared by SameSpelling;
        // the rest is kept as the path spells it.
        if (!string.IsNullOrEmpty(course))
        {
            int first = page.IndexOf('/');
            int second = first < 0 ? -1 : page.IndexOf('/', first + 1);
            if (second > 0 && SameSpelling(page[..first], "courses") && SameSpelling(page[(first + 1)..second], course))
                return Quoted(page[(second + 1)..]);
        }
        return Quoted(page);
    }

    /// <summary>
    /// <c>Undo was refused: a change that stopped part way could not be put
    /// back yet, because courses/ICS3U/Section 1/Classes/A.md is in use by
    /// another program. The list is kept, and the next Undo tries again.</c>
    /// (the mac's <c>leftNewestLine</c>).
    /// </summary>
    internal static string LeftNewestWords(bool isUndo, UndoRefusal refusal)
    {
        string which = isUndo ? "Undo" : "Redo";
        string path = refusal.Path ?? "a page";
        string why = refusal.Kind switch
        {
            UndoRefusalKind.FileIsInUse => $"{path} is in use by another program",
            // No path: what could not be read is the list's own content for
            // the step (the plan's UndoListUnreadableException), never a page
            // (W4c review 1, LOW 3).
            UndoRefusalKind.CannotTellNow when refusal.Path is null => "what the list holds for it could not be read just now",
            UndoRefusalKind.CannotTellNow => $"{path} could not be read just now",
            UndoRefusalKind.CouldNotWrite => $"nothing could be written beside {path} (the disk may be full)",
            UndoRefusalKind.ChangedSince => $"{path} changed while it was being put back",
            UndoRefusalKind.ContentMissing => $"what it needs for {path} is no longer in the list",
            _ => "it holds something this version cannot read",
        };
        return $"{which} was refused: a change that stopped part way could not be put back yet, because {why}. "
             + $"The list is kept, and the next {which} tries again.";
    }

    /// <summary>
    /// Writes a line to the real activity trail, <c>course/section · words</c>:
    /// the sink the app's start-up (W4) gives the door. Each event Undo
    /// writes is named here, so the trail's wiring scan sees its writer.
    /// </summary>
    internal static void ToTheActivityTrail(UndoTrailLine line)
    {
        // Each event Undo writes, named on the right of an arm so the trail's
        // wiring scan (ActivityTrailWiringTests) sees its writer: a case label
        // alone, with the event passed on as line.Event, is not seen.
        ActivityTrail.Event written = line.Event switch
        {
            ActivityTrail.Event.UndoRolledBack => ActivityTrail.Event.UndoRolledBack,
            ActivityTrail.Event.UndoCouldNotRecordAStep => ActivityTrail.Event.UndoCouldNotRecordAStep,
            ActivityTrail.Event.UndoFoundAFolderSetAside => ActivityTrail.Event.UndoFoundAFolderSetAside,
            ActivityTrail.Event.UndoCouldNotPutBack => ActivityTrail.Event.UndoCouldNotPutBack,
            ActivityTrail.Event.UndoKeptWhatAPageHeld => ActivityTrail.Event.UndoKeptWhatAPageHeld,
            ActivityTrail.Event.UndoKeptWhatItReplaced => ActivityTrail.Event.UndoKeptWhatItReplaced,
            ActivityTrail.Event.UndoRefusedForAChangeLeftPartWay => ActivityTrail.Event.UndoRefusedForAChangeLeftPartWay,
            _ => throw new ArgumentException("An event Undo does not write: " + line.Event, nameof(line)),
        };
        if (string.IsNullOrEmpty(line.Course)) ActivityTrail.Note(written, line.Words);
        else if (line.Section is { } section and >= 0 and <= int.MaxValue) ActivityTrail.Note(written, line.Words, line.Course, (int)section);
        else ActivityTrail.Note(written, line.Course + " · " + line.Words);
    }
}

/// <summary>
/// Settles steps whose work stopped part way (#899 W3; <c>undo.rule.recovery</c>,
/// the mac's <c>UndoRecovery</c>). Run inside the lock: in the door's begin
/// hold, its Undo/Redo offer hold, before EVERY prune, and by
/// <see cref="UndoDoor.Recover"/> (at every launch of the app and of
/// <c>plantoir-mcp.exe</c>, since W4: <see cref="UndoAtLaunch.Recover"/>).
///
/// <para>For each step in flight whose process is gone (or that this process
/// gave up on, <see cref="UndoProcessMemory.NoteAbandoned"/>), each file the
/// step changed is judged by its CONTENT, never a time: where the work
/// started, where it was going, or neither. All at the start: <c>failed</c>.
/// All at the end: completed. Some of each: what took effect is put back,
/// <c>rolledBack</c>, a trail line. Any file neither (changed by hand since):
/// what can be verified is put back, the step is <c>interrupted</c> naming the
/// files in the way, and the list is CLEARED (as ruling 13 clears for a
/// refused step). A put-back that cannot be planned (its content missing) is
/// closed the same way (<c>couldNotPutBack</c>). The journal never says done
/// or failed for a step that is half applied.</para>
///
/// <para>A file in use or that cannot be read now, a refused put-back swap,
/// or the list unreadable: the step is LEFT, to be tried again on a bounded
/// schedule (at once at an Undo, a Redo or an explicit recovery; otherwise
/// at the process's first lock, then one minute after a refusal, doubling,
/// at most an hour), so an ordinary action pays nothing for it in between
/// (measured on the mac before the rule: 187 to 255 ms on every action for a
/// 300-page put-back). A step pruning would close now is tried at once, so it
/// is never closed <c>unsettled</c> while one more try could settle it.</para>
///
/// <para>A step whose folder cannot be reached, or that this version cannot
/// read, is left while it is on the list (ruling 10); pruning closes it past
/// the limits. A step that keeps a file true by a rule (a <c>recompute</c>) is
/// settled only by a recovery that will re-derive it, and only once a runner
/// for its maintainer exists. In SHADOW nothing is written into a working
/// folder: a step that partly took effect is recorded interrupted and the
/// list cleared, the files left exactly as the work left them.</para>
/// </summary>
internal static class UndoRecovery
{
    /// <summary>
    /// Recovery, inside the lock. <paramref name="trySwapsNow"/>: an Undo, a
    /// Redo or an explicit recovery, where a put-back refused earlier is tried
    /// at once; false on the ordinary path. <paramref name="leavingStepsThatRederive"/>:
    /// the caller cannot re-derive after the hold (a plain write's begin), so
    /// a live step that keeps a file true is left for one that can.
    /// </summary>
    internal static UndoRecoveryRun Run(UndoJournalWriter writer, UndoJournal journal, UndoMode mode, bool trySwapsNow,
                                        bool leavingStepsThatRederive, IUndoMaintainers? maintainers,
                                        Action<UndoTrailLine>? trail, UndoSeams? seams, IUndoExternalPlaces? places = null)
    {
        writer.RecoveredThisHold = true;
        IUndoExternalPlaces theirPlaces = places ?? new UndoAppSettingsPlaces();
        var settled = new List<UndoRecoveryResult>();
        var left = new Dictionary<long, UndoRefusal>();
        DateTimeOffset now = journal.Now;
        HashSet<long>? pruningWouldClose = null;
        var inFlight = writer.Folded.Steps.Values.Where(step => step.IsInFlight).ToList();
        foreach (UndoFoldedStep record in inFlight)
        {
            if (!MaySettle(record, journal)) continue;
            if (!record.Readable) continue;
            if (RootOf(record.Step, journal) is not { } root) continue;
            bool keepsAFileTrue = KeepsAFileTrue(record.Step);
            // Never settled with its re-derivation skipped (the hard review of U2b, MEDIUM 5).
            if (keepsAFileTrue && !CanRederive(record.Step, maintainers)) continue;
            // Settled only by a recovery that will re-derive it (MEDIUM 1), and
            // never closed unsettled by this hold's pruning meanwhile: one more
            // try, by the next recovery that re-derives (an Undo, a Redo, the
            // next launch's), can settle it (W3's review, LOW 2).
            if (keepsAFileTrue && leavingStepsThatRederive && mode == UndoMode.Live)
            {
                writer.LeftForARederivingRecovery.Add(record.Seq);
                continue;
            }
            string key = KeyOf(record, journal);
            if (!trySwapsNow && !journal.Memory.RefusedSwapIsDue(key, now))
            {
                pruningWouldClose ??= ClosedByPruningNow(writer, journal);
                if (!pruningWouldClose.Contains(record.Seq)) continue;
            }
            SettleAnswer answer = Settle(record, root, writer, journal, mode, trail, seams, theirPlaces);
            if (answer.Stopped) return new UndoRecoveryRun(settled, StoppedByATest: true, left);
            if (answer.Result is { } result)
            {
                journal.Memory.ForgetTheRefusedSwap(key);
                journal.Memory.ForgetAbandoned(AbandonedKeyOf(journal, record.Seq, record.State, record.Process?.Pid ?? 0));
                settled.Add(result);
            }
            else if (answer.TryAgain)
            {
                if (answer.Why is { } why) left[record.Seq] = why;
                journal.Memory.NoteARefusedSwap(key, now);
            }
        }
        // In shadow too, since U3 (rule.recovery): a shadow step is staged
        // beside its pages like a live one, so one closed interrupted would
        // otherwise leave its dot-files in the course until the switch flips.
        // Shadow removes only the journal's own staged FILES of a step whose
        // every op changes a file in place, never a folder set aside (the
        // mac's tidyClosedSteps(onlyStepsOfFiles:)), and keeps a kept
        // original that differs from its page.
        TidyClosedSteps(writer, journal, trail, onlyStepsOfFiles: mode == UndoMode.Shadow);
        return new UndoRecoveryRun(settled, StoppedByATest: false, left);
    }

    /// <summary>
    /// The number of a step a gone process left in flight that keeps a file
    /// true by a rule, on this course (any when either has none): a write
    /// through a door that cannot re-derive is refused while one waits, so it
    /// never lands over a page the stopped work left part way (the mac's
    /// third hard review of U2b, LOW 1).
    /// </summary>
    internal static long? DeadStepThatKeepsAFileTrue(UndoJournalWriter writer, UndoJournal journal, string? course)
    {
        foreach (UndoFoldedStep record in writer.Folded.Steps.Values)
        {
            if (!record.IsInFlight || !KeepsAFileTrue(record.Step) || !MaySettle(record, journal)) continue;
            if (course is not null && record.Step.Course is { } stepCourse && !string.Equals(course, stepCourse, StringComparison.Ordinal)) continue;
            return record.Seq;
        }
        return null;
    }

    /// <summary>Whether a step holds a <c>recompute</c> op.</summary>
    internal static bool KeepsAFileTrue(UndoStep step) => step.Ops.Any(op => op.Kind == UndoOp.Recompute);

    /// <summary>
    /// Whether recovery may settle a step in flight: its process can be
    /// identified (a pid of 1 to 2^31-1: the W1 review's low on a pid of 0
    /// or less read as a known process) and is gone, or this process gave
    /// up on it. A step whose process cannot be identified is never settled
    /// (a live process of another version may still be swapping), and pruning
    /// closes it past the limits.
    /// </summary>
    internal static bool MaySettle(UndoFoldedStep record, UndoJournal journal)
    {
        if (record.Process is not { } process || process.Pid is <= 0 or > int.MaxValue) return false;
        if (journal.Memory.IsAbandoned(AbandonedKeyOf(journal, record.Seq, record.State, process.Pid))) return true;
        return !journal.IsAlive(process);
    }

    /// <summary>One step's work in one list: the list, its number, where its work stands, and when it was made (a new list in a reused folder is never confused with an old one).</summary>
    internal static string KeyOf(UndoFoldedStep record, UndoJournal journal) =>
        UndoProcessMemory.KeyOf(journal.Folder) + "#" + record.Seq + "#" + record.State + "#"
        + (record.Step.MadeAt?.ToUnixTimeMilliseconds().ToString(System.Globalization.CultureInfo.InvariantCulture) ?? "");

    /// <summary>
    /// A step this process gave up on: the list, its number, where its work
    /// stands, and the process (only a step named by this process's own id is
    /// ever settled as abandoned while it lives).
    /// </summary>
    internal static string AbandonedKeyOf(UndoJournal journal, long seq, UndoStepState working, long pid) =>
        UndoProcessMemory.KeyOf(journal.Folder) + "#" + seq + "#" + working + "#pid" + pid;

    private static bool CanRederive(UndoStep step, IUndoMaintainers? maintainers)
    {
        foreach (UndoOp op in step.Ops)
        {
            if (op.Kind == UndoOp.Recompute && (op.Maintainer is not { } maintainer || maintainers?.CanRun(maintainer) != true)) return false;
        }
        return true;
    }

    /// <summary>
    /// The folder a step's paths are under, or null when it cannot be reached.
    /// A step none of whose ops names a path (an external op alone,
    /// <c>opKinds.wholeOps</c>) needs no folder: its root is empty, which no op
    /// of it reads.
    /// </summary>
    internal static string? RootOf(UndoStep step, UndoJournal journal)
    {
        if (!step.Ops.Any(op => op.PathsNamed.Any())) return "";
        return step.WorkingFolder?.PathAtTheTime is { Length: > 0 } path && journal.CanReach(step) ? path : null;
    }

    /// <summary>The listing each tree op of a step recorded, by its folder's full path: what a folder set aside must still be for recovery to put it back as the step's.</summary>
    internal static IReadOnlyDictionary<string, string> AsideListings(UndoStep step, string root)
    {
        var listings = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (UndoOp op in step.Ops)
        {
            if (op.Kind is UndoOp.CreateTree or UndoOp.RemoveTree && op.Path is { } path && op.ListingSha is { } sha)
                listings[Path.GetFullPath(UndoDoor.FullPath(root, path))] = sha;
        }
        return listings;
    }

    /// <summary>
    /// Every tree op's folder of this step that a staged <c>-orig</c> name still
    /// holds beside it (its place could not be read, or a rename failed): a
    /// folder still aside is IN THE WAY, never settled as if it were gone (the
    /// mac's second hard review of U2b, MEDIUM 3).
    /// </summary>
    internal static HashSet<string> FoldersKeptAside(UndoStep step, string root)
    {
        var kept = new HashSet<string>(StringComparer.Ordinal);
        foreach (UndoOp op in step.Ops)
        {
            if (op.Kind is not (UndoOp.CreateTree or UndoOp.RemoveTree) || op.Path is not { } path) continue;
            string place = UndoDoor.FullPath(root, path);
            string? folder = Path.GetDirectoryName(place);
            if (folder is null || !Directory.Exists(folder)) continue;
            string prefix = "." + Path.GetFileName(place) + UndoSwap.StagedMarker + step.Seq + "-";
            IEnumerable<string> names;
            try { names = Directory.EnumerateDirectories(folder, prefix + "*").Select(Path.GetFileName).ToList()!; }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { continue; }
            foreach (string name in names)
            {
                if (string.Equals(UndoSwap.PlaceOfStagedName(name), Path.GetFileName(place), StringComparison.OrdinalIgnoreCase)
                    && UndoSwap.IsAFolderSetAside(Path.Combine(folder, name)))
                    kept.Add(path);
            }
        }
        return kept;
    }

    /// <summary>
    /// The trail line for a teacher's folder found set aside (the mac's
    /// <c>noteAnAsideFolder</c>), said before it is renamed: put back though
    /// it changed while aside (what changed, counted against the step's
    /// record when the list still holds it), or kept under a visible name
    /// because something else holds its place. A folder put back as recorded
    /// needs no line.
    /// </summary>
    internal static void NoteAnAsideFolder(UndoAsideFolder found, UndoStep step, string root, UndoJournal? journal, Action<UndoTrailLine>? trail)
    {
        if (trail is null || (found.PutBack && found.Matched)) return;
        string place = InsideTheFolder(found.Place, root);
        string? keptAs = found.KeptAs is { } kept ? InsideTheFolder(kept, root) : null;
        string changes = found.PutBack ? WhatChanged(found.FoundAt, step, place, journal) : "";
        trail(new UndoTrailLine(ActivityTrail.Event.UndoFoundAFolderSetAside, step.Course, step.Section,
                                UndoTrail.FoundAFolderSetAsideWords(place, keptAs, changes)));
    }

    /// <summary>A place's path inside the working folder, forward slashes, or its last name when it is not inside it.</summary>
    private static string InsideTheFolder(string full, string root)
    {
        string rootPath = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        string fullPath = Path.GetFullPath(full);
        return fullPath.StartsWith(rootPath, StringComparison.OrdinalIgnoreCase)
            ? fullPath[rootPath.Length..].Replace(Path.DirectorySeparatorChar, '/')
            : Path.GetFileName(fullPath);
    }

    /// <summary><c>1 file added, 2 changed</c> against the step's recorded listing, or <c>changed</c> when the list no longer holds it.</summary>
    private static string WhatChanged(string folder, UndoStep step, string place, UndoJournal? journal)
    {
        string? recordedSha = null;
        foreach (UndoOp op in step.Ops)
        {
            if (string.Equals(op.Path, place, StringComparison.Ordinal)) recordedSha = op.ListingSha;
        }
        UndoTreeListing? recorded = null;
        try
        {
            if (journal is not null && recordedSha is not null && journal.Blob(recordedSha) is { } bytes) recorded = UndoTreeListing.Parse(bytes);
        }
        catch (UndoListUnreadableException) { }
        if (recorded is null || UndoTreeReading.Read(folder) is not UndoTreeReading.Tree now) return "changed";
        var before = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach ((string path, string sha) in recorded.Files) before[path] = sha;
        int added = 0, changed = 0;
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach ((string path, string sha) in now.Listing.Files)
        {
            seen.Add(path);
            if (before.TryGetValue(path, out string? was)) { if (was != sha) changed++; }
            else added++;
        }
        int removed = before.Keys.Count(path => !seen.Contains(path));
        var parts = new List<string>();
        if (added > 0) parts.Add(added == 1 ? "1 file added" : $"{added} files added");
        if (changed > 0) parts.Add(changed == 1 ? "1 changed" : $"{changed} changed");
        if (removed > 0) parts.Add(removed == 1 ? "1 removed" : $"{removed} removed");
        return parts.Count == 0 ? "changed" : string.Join(", ", parts);
    }

    private static HashSet<long> ClosedByPruningNow(UndoJournalWriter writer, UndoJournal journal)
    {
        var seqs = new HashSet<long>();
        try
        {
            foreach (UndoPruneAction action in UndoPruning.Decide(writer.Reading(), journal.Now, journal.IsAlive))
            {
                if (action is UndoPruneAction.ClosedUnsettled closed) seqs.Add(closed.Seq);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
        return seqs;
    }

    /// <summary>
    /// Removes the staged files of every step closed <c>interrupted</c> this
    /// process has not yet tidied and whose folder it can reach (a step closed
    /// while its folder was away: <c>knownLimits.stagedFilesOfAFolderAway</c>,
    /// the director's ruling 6 on U1's third round). Once per process; one
    /// whose file could not be removed is looked for again at the next lock.
    /// </summary>
    /// <param name="onlyStepsOfFiles">Shadow's: only a step whose every op changes a file in place or moves a file or folder whole (<see cref="ChangesOnlyFilesAndMoves"/>).</param>
    internal static void TidyClosedSteps(UndoJournalWriter writer, UndoJournal journal, Action<UndoTrailLine>? trail = null,
                                         bool onlyStepsOfFiles = false)
    {
        foreach (UndoFoldedStep record in writer.Folded.Steps.Values)
        {
            if (record.State != UndoStepState.Interrupted) continue;
            if (onlyStepsOfFiles && !ChangesOnlyFilesAndMoves(record.Step)) continue;
            string key = UndoProcessMemory.KeyOf(journal.Folder) + "#" + record.Seq;
            if (journal.Memory.HasTidied(key)) continue;
            if (RootOf(record.Step, journal) is not { } root) continue;
            bool allGone;
            UndoStep closedStep = record.Step;
            try
            {
                // Nothing will put a closed step's page back: a kept original
                // that differs from its page is the only copy of what it held,
                // and stays (the mac's U3c).
                allGone = UndoSwap.TidyLeftovers(record.Seq, closedStep.PathsToTidy, root, AsideListings(closedStep, root),
                                                 found => NoteAnAsideFolder(found, closedStep, root, journal, trail), keepingOnlyCopies: true);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { allGone = false; }
            if (allGone) journal.Memory.NoteTidied(key);
        }
    }

    /// <summary>
    /// Whether a step changes only files and moves files or folders whole
    /// (U4b: Rename folder): the steps whose staged files shadow tidies. A
    /// move sets nothing aside, so all its tidy removes is the step's own
    /// staged files beside its pages, at each page's place and, for a page a
    /// move carries, at its place before the move (<see cref="UndoStep.PathsToTidy"/>);
    /// a kept original that differs from its page stays. A step that makes or
    /// takes out a folder, or stands apart, is still left to a live recovery
    /// (the mac's <c>changesOnlyFilesAndMoves</c>; #899 W8-7).
    /// </summary>
    internal static bool ChangesOnlyFilesAndMoves(UndoStep step)
    {
        foreach (UndoOp op in step.Ops)
        {
            if (op.Kind is not (UndoOp.WriteFile or UndoOp.EditLine or UndoOp.ReplaceText or UndoOp.EditJson or UndoOp.Recompute or UndoOp.Move)) return false;
        }
        return true;
    }

    // ---- Kept originals (the mac's U3c) --------------------------------------------

    /// <summary>Every kept original (<c>-orig</c>, <c>-&lt;n&gt;-orig</c>, a file) of this step's beside one place, by name order.</summary>
    internal static List<string> KeptOriginalFiles(UndoStep step, string place)
    {
        var found = new List<string>();
        string? folder = Path.GetDirectoryName(place);
        if (folder is null) return found;
        string placeName = Path.GetFileName(place);
        string prefix = "." + placeName + UndoSwap.StagedMarker + step.Seq + "-";
        List<string> names;
        try
        {
            names = new List<string>();
            foreach (string entry in Directory.EnumerateFiles(folder, "." + "*" + UndoSwap.StagedMarker + step.Seq + "-*")) names.Add(Path.GetFileName(entry));
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return found; }
        names.Sort(StringComparer.Ordinal);
        foreach (string name in names)
        {
            if (!name.StartsWith(prefix, StringComparison.Ordinal) || !name.EndsWith("-orig", StringComparison.Ordinal)) continue;
            if (UndoSwap.PlaceOfStagedName(name) != placeName) continue;
            found.Add(Path.Combine(folder, name));
        }
        return found;
    }

    /// <summary>
    /// What a step's own swap kept beside a page as its original (any of the
    /// step's labels), answered for a page's path and the sha of the whole
    /// content wanted there only when a kept original's bytes hash to exactly
    /// that (Russell's ruling of 2026-11-20, 15:20): trusted by its content
    /// alone, never its name or its times. Null when none matches. One that is
    /// there and cannot be read just now (a cloud placeholder not downloaded,
    /// a permission, another program holding it) is told to
    /// <paramref name="couldNotRead"/> when none matches: it may be the one,
    /// so the caller answers "cannot tell now", never "no match".
    /// </summary>
    internal static Func<string, string, byte[]?> KeptOriginal(UndoStep step, string root, Action<string>? couldNotRead = null) =>
        (path, sha) =>
        {
            bool unreadable = false;
            foreach (string kept in KeptOriginalFiles(step, UndoDoor.FullPath(root, path)))
            {
                UndoCurrent item = UndoCurrent.Read(kept);
                if (item is UndoCurrent.CannotReadNow) { unreadable = true; continue; }
                if (item is UndoCurrent.Bytes bytes && string.Equals(UndoCheck.Sha(bytes.Content), sha, StringComparison.Ordinal)) return bytes.Content;
            }
            if (unreadable) couldNotRead?.Invoke(path);
            return null;
        };

    /// <summary>
    /// Writes back into the list what a put-back from kept originals takes and
    /// sets aside (the first review of U3c, MEDIUM): each kept original's bytes
    /// as their blob, and what the page holds now as the other direction's blob
    /// when it hashes to the recorded other sha. Inside the lock, before the
    /// swap. A failed write is never ignored: the page's outgoing content is
    /// then kept beside it by the swap (<c>OutgoingOf</c>), and a kept
    /// original whose own bytes the list would not take is never tidied
    /// (<c>KeptOriginalsHolding</c>; the second review of U3c, MEDIUM).
    /// </summary>
    internal static UndoWhatTheListCouldNotTake StoreWhatKeptOriginalsGive(IReadOnlyList<UndoKeptOriginalUse> uses, UndoJournalWriter writer, UndoJournal journal)
    {
        var notWhole = new HashSet<string>(StringComparer.Ordinal);
        var keptNotStored = new HashSet<string>(StringComparer.Ordinal);
        foreach (UndoKeptOriginalUse use in uses)
        {
            if (!TryToStore(use.Kept, writer)) keptNotStored.Add(UndoCheck.Sha(use.Kept));
            // The other direction wants no file there: nothing to keep.
            if (use.OtherSha is not { } otherSha) continue;
            if (journal.Blob(otherSha) is not null) continue;
            bool stored = use.Outgoing is UndoCurrent.Bytes outgoing
                          && string.Equals(UndoCheck.Sha(outgoing.Content), otherSha, StringComparison.Ordinal)
                          && TryToStore(outgoing.Content, writer);
            if (!stored) notWhole.Add(use.Path);
        }
        return new UndoWhatTheListCouldNotTake(notWhole, keptNotStored);
    }

    /// <summary>
    /// An Undo or Redo never deletes an only copy (documentation 12, "The lows
    /// fixed with U4a that W4c and W7 copy", item 4; the mac's
    /// <c>UndoRecovery.storeWhatTheOtherDirectionNeeds</c>): under the lock,
    /// before the swap, each page's outgoing bytes that the step's other
    /// direction needs (a writeFile op's after for an Undo, its before for a
    /// Redo) go into the list when it lacks them. The pages whose bytes the
    /// list would not take are returned: the swap keeps those bytes beside the
    /// page (<c>OutgoingOf</c>), and the other direction is made from that kept
    /// file. Bytes a kept original of the step already holds beside the page
    /// need nothing more. (#899 W8-9: the U4b2-4 stack case rests on it.)
    /// </summary>
    internal static HashSet<string> StoreWhatTheOtherDirectionNeeds(IReadOnlyList<(string Path, byte[]? Expected, byte[]? Replacement)> inOrder,
                                                                    UndoStep step, bool backward, string root, UndoJournalWriter writer, UndoJournal journal)
    {
        var notStored = new HashSet<string>(StringComparer.Ordinal);
        foreach ((string path, byte[]? outgoing, _) in inOrder)
        {
            if (outgoing is null) continue;
            string outgoingSha = UndoCheck.Sha(outgoing);
            bool needed = false;
            foreach (UndoOp op in step.Ops)
            {
                if (op.Kind != UndoOp.WriteFile || op.Path != path) continue;
                string? otherSha = backward ? op.AfterSha : op.BeforeSha;
                if (string.Equals(otherSha, outgoingSha, StringComparison.Ordinal)) needed = true;
            }
            if (!needed || journal.Blob(outgoingSha) is not null) continue;
            bool alreadyKept = false;
            if (root.Length > 0)
            {
                foreach (string kept in KeptOriginalFiles(step, UndoDoor.FullPath(root, path)))
                {
                    if (UndoCurrent.Read(kept) is UndoCurrent.Bytes bytes && string.Equals(UndoCheck.Sha(bytes.Content), outgoingSha, StringComparison.Ordinal))
                        alreadyKept = true;
                }
            }
            if (alreadyKept) continue;
            if (!TryToStore(outgoing, writer)) notStored.Add(path);
        }
        return notStored;
    }

    private static bool TryToStore(byte[] bytes, UndoJournalWriter writer)
    {
        try { writer.WriteBlob(bytes); return true; }
        catch (Exception error) when (error is UndoJournalException or IOException or UnauthorizedAccessException) { return false; }
    }

    /// <summary>
    /// Whether a kept original's bytes are exactly what the list gives for its
    /// page, so it is not the only copy of what it holds: what the step's ops
    /// on that page come to, undone or redone, from what the page holds now (a
    /// whole file by its recorded sha, whose content the list must still hold;
    /// a line, a hunk or a member derived from the page). Never true for one
    /// that holds anything else, such as an edit that raced the swap into the
    /// original's file (the mac's <c>listHolds</c>; the third review of U3a, LOW 1).
    /// </summary>
    internal static Func<string, string, bool> ListHolds(UndoStep step, string root, UndoJournal journal) =>
        (kept, place) =>
        {
            if (UndoCurrent.Read(kept) is not UndoCurrent.Bytes keptBytes) return false;
            string wanted = Path.GetFullPath(place);
            var opsOnThePlace = new List<UndoOp>();
            Dictionary<string, UndoOp> carriers = UndoCheck.Carriers(step.Ops);
            foreach (UndoOp op in step.Ops)
            {
                if (op.Kind == UndoOp.Recompute || op.IsWhole || op.Path is not { } path) continue;
                if (string.Equals(Path.GetFullPath(UndoDoor.FullPath(root, path)), wanted, StringComparison.OrdinalIgnoreCase))
                {
                    opsOnThePlace.Add(op);
                }
                else if (carriers.TryGetValue(path, out UndoOp? carrier))
                {
                    // A carried page whose folder has moved back (U4b; W8-7):
                    // the same op, judged at its old place.
                    string oldPlace = UndoOp.PlaceBeforeTheMove(path, carrier.From!, carrier.To!);
                    if (string.Equals(Path.GetFullPath(UndoDoor.FullPath(root, oldPlace)), wanted, StringComparison.OrdinalIgnoreCase))
                        opsOnThePlace.Add(op with { Path = oldPlace });
                }
            }
            if (opsOnThePlace.Count == 0) return false;
            foreach (bool backward in new[] { true, false })
            {
                UndoCheck.PlanResult plan;
                try { plan = UndoCheck.Plan(opsOnThePlace, backward, relative => UndoCurrent.Read(UndoDoor.FullPath(root, relative)), journal.Blob); }
                catch (UndoListUnreadableException) { continue; }
                if (plan is not UndoCheck.PlanResult.Ready ready) continue;
                foreach ((string path, _, byte[]? replacement) in ready.InOrder)
                {
                    if (replacement is null) continue;
                    if (string.Equals(Path.GetFullPath(UndoDoor.FullPath(root, path)), wanted, StringComparison.OrdinalIgnoreCase)
                        && replacement.AsSpan().SequenceEqual(keptBytes.Content)) return true;
                }
            }
            return false;
        };

    /// <summary>The hidden name of every kept original of this step still beside the files it names, each once, in the order the step names them.</summary>
    internal static List<string> KeptOriginalsLeft(UndoStep step, string root)
    {
        var names = new List<string>();
        // Beside a carried page at its folder's old place too (W8-7).
        foreach (string path in step.PathsToTidy)
        {
            if (!UndoPlaces.StaysInside(root, path)) continue;
            foreach (string kept in KeptOriginalFiles(step, UndoDoor.FullPath(root, path)))
            {
                string name = Path.GetFileName(kept);
                if (names.Contains(name)) continue;
                names.Add(name);
                UndoSwap.HideAKeptFileLeft(kept);
            }
        }
        return names;
    }

    /// <summary>
    /// Of these kept originals' hidden names, those whose bytes hash to what the
    /// journal recorded for their page (a writeFile's before or after): kept
    /// because the list no longer holds that content, never because they differ
    /// from it (the first review of U3c, LOW 2).
    /// </summary>
    internal static List<string> KeptOriginalsOfWhatWasRecorded(IReadOnlyList<string> names, UndoStep step, string root)
    {
        var recorded = new List<string>();
        Dictionary<string, UndoOp> carriers = UndoCheck.Carriers(step.Ops);
        foreach (UndoOp op in step.Ops)
        {
            if (op.Kind != UndoOp.WriteFile || op.Path is not { } path) continue;
            // A carried page's kept originals at its folder's old place too (W8-7).
            var places = new List<string> { path };
            if (carriers.TryGetValue(path, out UndoOp? carrier)) places.Add(UndoOp.PlaceBeforeTheMove(path, carrier.From!, carrier.To!));
            foreach (string kept in places.Where(place => UndoPlaces.StaysInside(root, place))
                                          .SelectMany(place => KeptOriginalFiles(step, UndoDoor.FullPath(root, place))))
            {
                string name = Path.GetFileName(kept);
                if (!names.Contains(name) || recorded.Contains(name)) continue;
                if (UndoCurrent.Read(kept) is not UndoCurrent.Bytes bytes) continue;
                string sha = UndoCheck.Sha(bytes.Content);
                if (sha == op.BeforeSha || sha == op.AfterSha) recorded.Add(name);
            }
        }
        return recorded;
    }

    private sealed record SettleAnswer(UndoRecoveryResult? Result, bool TryAgain, bool Stopped, UndoRefusal? Why = null)
    {
        /// <summary>Left, to be tried again, for the reason given.</summary>
        internal static SettleAnswer AgainFor(UndoRefusal why) => new(null, true, false, why);

        internal static readonly SettleAnswer Again = new(null, true, false);
        internal static readonly SettleAnswer Nothing = new(null, false, false);
        internal static readonly SettleAnswer Halted = new(null, false, true);
    }

    /// <summary>
    /// Where each file of a step stands now, by content, in the order its ops
    /// name them. U4b (opKinds.wholeOps' order; #899 W8-7): an edit a move of
    /// the step carries is read where its folder is now (<see cref="PlaceNow"/>),
    /// and the move is judged as if the step's edits inside it were taken
    /// back, without the step's own staged and kept files inside it
    /// (<see cref="CarryingMoveState"/>), so a step killed between its move
    /// and its edits settles whole, by content (the mac's <c>fileStates</c>).
    /// </summary>
    /// <param name="blob">The list's content by sha, for taking a carried edit back; null: a carried edit is judged as it is.</param>
    internal static IReadOnlyList<(string Path, UndoOpState State)> FileStates(UndoStep step, string root, IUndoExternalPlaces? places = null,
                                                                               Func<string, byte[]?>? blob = null)
    {
        var order = new List<string>();
        var states = new Dictionary<string, UndoOpState>(StringComparer.Ordinal);
        var currents = new Dictionary<string, UndoCurrent?>(StringComparer.Ordinal);
        Dictionary<string, UndoOp> carriers = UndoCheck.Carriers(step.Ops);
        foreach (UndoOp op in step.Ops)
        {
            if (op.IsWhole)
            {
                // A move, a tree or an external op is one place of its own,
                // judged whole (a move by its pair, never by one side); a place
                // that now leads outside the folder is in the way.
                string place = op.PlaceName;
                if (!states.ContainsKey(place)) order.Add(place);
                IUndoExternalPlaces where = places ?? new UndoAppSettingsPlaces();
                states[place] = UndoPlaces.FirstPlaceLeadingOut(root, op) is not null
                    ? UndoOpState.Neither
                    : carriers.Values.Any(carrier => ReferenceEquals(carrier, op))
                        ? CarryingMoveState(op, step, carriers, root, where, blob)
                        : UndoCheck.WholeStateOf(op, root, where);
                continue;
            }
            if (op.Kind == UndoOp.Recompute || op.Path is not { } path) continue;
            if (!currents.ContainsKey(path))
            {
                // A place that now leads outside the folder (a junction since)
                // is read through nothing: it is in the way. A carried edit is
                // read where its folder is now.
                string readPath = carriers.TryGetValue(path, out UndoOp? carrier) ? PlaceNow(path, carrier, root) : path;
                currents[path] = UndoPlaces.StaysInside(root, readPath) ? UndoCurrent.Read(UndoDoor.FullPath(root, readPath)) : null;
                order.Add(path);
            }
            UndoOpState state = currents[path] is { } current ? UndoCheck.StateOf(op, current) : UndoOpState.Neither;
            if (states.TryGetValue(path, out UndoOpState earlier))
            {
                // A page another program holds with no read sharing stays IN
                // USE, so the refusal names the file in use, never cannot tell
                // (W4's review, LOW 4); otherwise one that cannot be read now
                // stays cannot tell.
                if (earlier == UndoOpState.InUse || state == UndoOpState.InUse) states[path] = UndoOpState.InUse;
                else if (earlier == UndoOpState.CannotTell || state == UndoOpState.CannotTell) states[path] = UndoOpState.CannotTell;
                else if (earlier != state) states[path] = UndoOpState.Neither;
            }
            else
            {
                states[path] = state;
            }
        }
        return order.Select(path => (path, states[path])).ToList();
    }

    /// <summary>Whether the folder (or file) a move carries edits with is at its old place now: nothing at <c>to</c> and something at <c>from</c> (the mac's <c>isAtItsOldPlace</c>). Looked at without following a link.</summary>
    internal static bool IsAtItsOldPlace(UndoOp move, string root) =>
        move.From is { } from && move.To is { } to
        && UndoLinks.Look(UndoTreeReading.Under(root, to)) == UndoLinks.What.Nothing
        && UndoLinks.Look(UndoTreeReading.Under(root, from)) != UndoLinks.What.Nothing;

    /// <summary>Where an edit named inside a move's new place is on the disk now: under the move's <c>from</c> while the folder is still (or again) there, otherwise where it is named (the mac's <c>placeNow</c>; U4b).</summary>
    internal static string PlaceNow(string path, UndoOp move, string root) =>
        IsAtItsOldPlace(move, root) ? UndoOp.PlaceBeforeTheMove(path, move.From!, move.To!) : path;

    /// <summary>
    /// A move that carries edits (U4b), judged on whichever side its folder
    /// is: each carried page as it is once the step's edits on it are taken
    /// back (last op first), and the step's own staged and kept files inside
    /// the folder left out (<see cref="UndoSwap.StepsOwnFilesInside"/>, the
    /// plan's reading since W8-3). A carried page that is neither as the step
    /// left it nor as before is left as it is, so the move is then a change
    /// since too (the mac's <c>carryingMoveState</c>; #899 W8-7).
    /// </summary>
    internal static UndoOpState CarryingMoveState(UndoOp move, UndoStep step, IReadOnlyDictionary<string, UndoOp> carriers, string root,
                                                  IUndoExternalPlaces places, Func<string, byte[]?>? blob)
    {
        if (move.From is not { } from || move.To is not { } to) return UndoOpState.Neither;
        bool atItsOldPlace = IsAtItsOldPlace(move, root);
        string side = UndoTreeReading.Under(root, atItsOldPlace ? from : to);
        Dictionary<string, UndoCurrent> overriding = UndoSwap.StepsOwnFilesInside(side, step.Seq);
        for (int index = step.Ops.Count - 1; index >= 0; index--)
        {
            UndoOp edit = step.Ops[index];
            if (edit.IsWhole || edit.Kind == UndoOp.Recompute || edit.Path is not { } path) continue;
            if (!carriers.TryGetValue(path, out UndoOp? carrier) || !ReferenceEquals(carrier, move)) continue;
            if (UndoOp.PartInside(to, path) is not { } inside) continue;
            UndoCurrent current = overriding.TryGetValue(inside, out UndoCurrent? already)
                ? already
                : UndoCurrent.Read(inside.Length == 0 ? side : UndoTreeReading.Under(side, inside));
            if (UndoCheck.StateOf(edit, current) != UndoOpState.After || blob is null) continue;
            if (TakenBack(edit, current, blob) is { } takenBack) overriding[inside] = takenBack;
        }
        // One place under two spellings: the same files either way (W8-5).
        if (move.IsCaseOnlyMove) return UndoCheck.WholeStateOf(move, root, places, overridingTo: overriding, overridingFrom: overriding);
        return atItsOldPlace
            ? UndoCheck.WholeStateOf(move, root, places, overridingFrom: overriding)
            : UndoCheck.WholeStateOf(move, root, places, overridingTo: overriding);
    }

    /// <summary>What one edit leaves its file holding once taken back from <paramref name="current"/>, by the plan's own rule (<see cref="UndoCheck.Plan"/>); null when it cannot be taken back (its content gone, a hunk not placed).</summary>
    private static UndoCurrent? TakenBack(UndoOp edit, UndoCurrent current, Func<string, byte[]?> blob)
    {
        UndoCheck.PlanResult plan;
        try { plan = UndoCheck.Plan([edit], backward: true, _ => current, blob); }
        catch (UndoListUnreadableException) { return null; }
        if (plan is not UndoCheck.PlanResult.Ready ready) return null;
        foreach (var change in ready.InOrder)
            return change.Item3 is { } replacement ? new UndoCurrent.Bytes(replacement) : new UndoCurrent.Absent();
        return current;
    }

    private static SettleAnswer Settle(UndoFoldedStep record, string root, UndoJournalWriter writer, UndoJournal journal,
                                       UndoMode mode, Action<UndoTrailLine>? trail, UndoSeams? seams, IUndoExternalPlaces places)
    {
        UndoStep step = record.Step;
        (UndoPhase phase, string work) = record.State switch
        {
            UndoStepState.Begun => (UndoPhase.Begin, "apply"),
            UndoStepState.Undoing => (UndoPhase.Undoing, "undo"),
            UndoStepState.Redoing => (UndoPhase.Redoing, "redo"),
            _ => (UndoPhase.Begin, ""),
        };
        if (work.Length == 0) return SettleAnswer.Nothing;
        string label = $"{step.Seq}-{work}";
        bool live = mode == UndoMode.Live;

        if (live)
        {
            // What the stopped work staged goes first: its new contents, and
            // the kept originals that are copies of their pages. Every kept
            // original that differs from its page stays until the plan is
            // ready, even one the list gives: another page may yet stop the
            // put-back and the list be cleared, and then it is the only copy
            // (the mac's U3c; its first review, LOW 1). A teacher's folder it
            // set aside is put back in its place, or kept under a visible name
            // beside it, never deleted (W6).
            try
            {
                UndoSwap.TidyLeftovers(step.Seq, step.PathsToTidy, root, AsideListings(step, root),
                                       found => NoteAnAsideFolder(found, step, root, journal, trail), keepingOnlyCopies: true);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
            if (seams?.Stops("afterRecoveryTidied") == true) return SettleAnswer.Halted;
        }

        bool startedFromBefore = phase is UndoPhase.Begin or UndoPhase.Redoing;
        UndoOpState startState = startedFromBefore ? UndoOpState.Before : UndoOpState.After;
        IReadOnlyList<(string Path, UndoOpState State)> files = FileStates(step, root, places, journal.Blob);
        // A teacher's folder still set aside after the tidying is IN THE WAY,
        // never settled as if it were gone; one whose place cannot be read stays
        // cannot tell, tried again.
        HashSet<string> keptAside = FoldersKeptAside(step, root);
        if (keptAside.Count > 0)
        {
            var judged = new List<(string, UndoOpState)>();
            foreach ((string path, UndoOpState state) in files)
                judged.Add(keptAside.Contains(path) && state is not (UndoOpState.CannotTell or UndoOpState.InUse) ? (path, UndoOpState.Neither) : (path, state));
            files = judged;
        }
        // An interrupted line names files inside the working folder: an
        // external op's target is no path, so it is never named there.
        var targets = new HashSet<string>(StringComparer.Ordinal);
        foreach (UndoOp op in step.Ops)
        {
            if (op.Kind == UndoOp.External && op.Target is { } target) targets.Add(target);
        }
        List<string> PathsOnly(IEnumerable<string> places) => places.Where(place => !targets.Contains(place)).ToList();
        // A file that could not be read now is never judged changed by hand:
        // tried again on the schedule, as for a file in use (ruling 4).
        foreach ((string path, UndoOpState state) in files)
        {
            if (state is UndoOpState.InUse)
                return SettleAnswer.AgainFor(new UndoRefusal(UndoRefusalKind.FileIsInUse, path));
            if (state is UndoOpState.CannotTell or UndoOpState.NotReadable)
                return SettleAnswer.AgainFor(new UndoRefusal(UndoRefusalKind.CannotTellNow, path));
        }

        int atStart = 0, atEnd = 0;
        var inTheWay = new List<string>();
        var endPaths = new List<string>();
        foreach ((string path, UndoOpState state) in files)
        {
            if (state == UndoOpState.Neither) inTheWay.Add(path);
            else if (state == startState) atStart++;
            else { atEnd++; endPaths.Add(path); }
        }

        var events = new List<JsonObject>();
        UndoRecoveryOutcome outcome;
        // Kept originals' bytes a put-back took that the list would not take
        // just now: no tidy removes a kept original holding them (U3c).
        IReadOnlySet<string>? keptNotTaken = null;
        int putBack = 0;
        UndoTrailLine? line = null;
        string? course = step.Course;
        long? section = step.Section;
        string phaseWord = phase.ToString().ToLowerInvariant();

        if (inTheWay.Count == 0 && atEnd == 0)
        {
            outcome = UndoRecoveryOutcome.NothingTookEffect;
            events.Add(new JsonObject { ["seq"] = step.Seq, ["event"] = "failed", ["phase"] = phaseWord, ["reason"] = "nothingTookEffect" });
        }
        else if (inTheWay.Count == 0 && atStart == 0)
        {
            outcome = UndoRecoveryOutcome.Completed;
            string finishing = phase switch { UndoPhase.Undoing => "undone", UndoPhase.Redoing => "redone", _ => "applied" };
            events.Add(new JsonObject { ["seq"] = step.Seq, ["event"] = finishing });
        }
        else
        {
            if (live && endPaths.Count > 0)
            {
                var opsToPutBack = step.Ops.Where(op => op.Kind != UndoOp.Recompute && endPaths.Contains(op.PlaceName)).ToList();
                UndoCheck.PlanResult plan;
                // Content the list no longer holds is taken from the step's own
                // kept original beside the page when its hash is the one
                // recorded (Russell's ruling of 2026-11-20, 15:20).
                string? keptOriginalNotRead = null;
                var uses = new List<UndoKeptOriginalUse>();
                try
                {
                    plan = UndoCheck.Plan(opsToPutBack, backward: startedFromBefore,
                                          relative => UndoCurrent.Read(UndoDoor.FullPath(root, relative)), journal.Blob,
                                          whole: new UndoWholeReads(root, places),
                                          keptOriginal: KeptOriginal(step, root, path => keptOriginalNotRead ??= path),
                                          keptOriginalUsed: uses.Add, ownSeq: step.Seq);
                }
                catch (UndoListUnreadableException)
                {
                    // Content it needs cannot be read just now: tried again.
                    return SettleAnswer.AgainFor(new UndoRefusal(UndoRefusalKind.CannotTellNow));
                }
                // A kept original that cannot be read just now may be the one:
                // cannot tell now, the step left for the next try, never closed
                // and the list never cleared (the first review of U3c, LOW 5).
                if (plan is UndoCheck.PlanResult.ContentMissing && keptOriginalNotRead is { } notRead)
                    return SettleAnswer.AgainFor(new UndoRefusal(UndoRefusalKind.CannotTellNow, notRead));
                switch (plan)
                {
                    case UndoCheck.PlanResult.FileIsInUse or UndoCheck.PlanResult.CannotTellNow or UndoCheck.PlanResult.FolderCannotBeReached:
                        return SettleAnswer.AgainFor(UndoDoor.RefusalOf(plan));
                    case UndoCheck.PlanResult.Ready ready:
                    {
                        // The plan is ready, so the list will put these pages
                        // back: only now does a kept original whose bytes the
                        // list gives go (LOW 1). Then what the kept originals
                        // give, and what the pages hold now, into the list
                        // before the swap (MEDIUM). A step that stays on the
                        // list (an undo or a redo put back to where it began)
                        // keeps beside its page what the list will not take; a
                        // change rolled back leaves the list.
                        try
                        {
                            UndoSwap.TidyLeftovers(step.Seq, step.PathsToTidy, root, AsideListings(step, root), null,
                                                   keepingOnlyCopies: true, unlessTheListHolds: ListHolds(step, root, journal));
                        }
                        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
                        UndoWhatTheListCouldNotTake notTaken = StoreWhatKeptOriginalsGive(uses, writer, journal);
                        IReadOnlySet<string>? keepingTheOriginalsOf = null;
                        if (phase != UndoPhase.Begin)
                        {
                            keepingTheOriginalsOf = notTaken.OutgoingOf;
                            keptNotTaken = notTaken.KeptOriginalsHolding;
                        }
                        List<UndoSwapTarget> putBackTargets = UndoDoor.TargetsOf(ready, root);
                        UndoSeams? recoverySeams = seams is null ? null : new UndoSeams
                        {
                            StopsHere = (point, index) => seams.Stops(point == "beforeSwap" ? "recoveryBeforeSwap" : point, index),
                        };
                        switch (UndoSwap.Swap(putBackTargets, label + "-recover", root.Length == 0 ? null : root, recoverySeams, places, keepingTheOriginalsOf))
                        {
                            case UndoSwapResult.StoppedByATest: return SettleAnswer.Halted;
                            case UndoSwapResult.Refused refused: return SettleAnswer.AgainFor(refused.Refusal);   // a file in use: tried again on the schedule
                        }
                        putBack = putBackTargets.Count;
                        break;
                    }
                    default:
                    {
                        // It can never be put back (its content missing): closed,
                        // never left in flight (the director's ruling 4).
                        var leftPartWay = endPaths.OrderBy(path => path, StringComparer.Ordinal).ToList();
                        foreach (string path in inTheWay)
                        {
                            if (!leftPartWay.Contains(path)) leftPartWay.Add(path);
                        }
                        events.Add(Interrupted(step.Seq, phaseWord, "couldNotPutBack", PathsOnly(leftPartWay)));
                        events.Add(new JsonObject { ["event"] = "cleared", ["reason"] = "interrupted" });
                        if (seams?.Stops("recoveryBeforeWriting") == true) return SettleAnswer.Halted;
                        if (!Write(events, step, writer)) return SettleAnswer.Nothing;
                        // Nothing that is an only copy is deleted: a kept original
                        // that differs from its page stays under its hidden name.
                        // Said after the tidy, so it names what is on the disk.
                        try
                        {
                            UndoSwap.TidyLeftovers(step.Seq, step.PathsToTidy, root, AsideListings(step, root), null, keepingOnlyCopies: true);
                        }
                        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
                        List<string> keptLeft = KeptOriginalsLeft(step, root);
                        trail?.Invoke(new UndoTrailLine(ActivityTrail.Event.UndoCouldNotPutBack, course, section,
                                                        UndoTrail.CouldNotPutBackWords(phase, leftPartWay.Count, keptLeft), keptLeft));
                        return new SettleAnswer(new UndoRecoveryResult(step.Seq, phase, UndoRecoveryOutcome.Interrupted, step, root, 0, leftPartWay.Count), false, false);
                    }
                }
            }
            if (inTheWay.Count == 0 && live)
            {
                outcome = UndoRecoveryOutcome.RolledBack;
                events.Add(new JsonObject { ["seq"] = step.Seq, ["event"] = "rolledBack", ["phase"] = phaseWord, ["reason"] = "partlyTookEffect" });
                line = new UndoTrailLine(ActivityTrail.Event.UndoRolledBack, course, section, UndoTrail.RolledBackWords(phase, putBack));
            }
            else if (inTheWay.Count == 0)
            {
                // Shadow: recorded, never repaired.
                outcome = UndoRecoveryOutcome.LeftAlone;
                events.Add(Interrupted(step.Seq, phaseWord, "partlyTookEffect", PathsOnly(endPaths.OrderBy(path => path, StringComparer.Ordinal))));
                events.Add(new JsonObject { ["event"] = "cleared", ["reason"] = "interrupted" });
            }
            else
            {
                outcome = UndoRecoveryOutcome.Interrupted;
                events.Add(Interrupted(step.Seq, phaseWord, "changedByHand", PathsOnly(inTheWay)));
                events.Add(new JsonObject { ["event"] = "cleared", ["reason"] = "interrupted" });
                // In shadow nothing was put back and nothing offered was
                // cleared: the journal holds the outcome, the trail does not.
                if (live)
                    line = new UndoTrailLine(ActivityTrail.Event.UndoRolledBack, course, section, UndoTrail.InterruptedWords(phase, putBack, inTheWay.Count));
            }
        }
        if (seams?.Stops("recoveryBeforeWriting") == true) return SettleAnswer.Halted;
        if (outcome == UndoRecoveryOutcome.Completed && phase == UndoPhase.Begin)
        {
            try { writer.DropTheRedoBranch(below: step.Seq); }
            catch (UndoJournalException) { return SettleAnswer.Nothing; }
        }
        if (!Write(events, step, writer)) return SettleAnswer.Nothing;
        if (line is not null) trail?.Invoke(line);
        if (live && outcome is UndoRecoveryOutcome.Completed or UndoRecoveryOutcome.NothingTookEffect or UndoRecoveryOutcome.RolledBack)
        {
            // Settled: its kept originals are needed no more, except one whose
            // bytes the list does not hold (an edit that raced the swap, or
            // content the list would not take): the only copy, kept beside its
            // page and named on the trail (the third review of U3a, LOW 1).
            try
            {
                UndoSwap.TidyLeftovers(step.Seq, step.PathsToTidy, root, AsideListings(step, root), null, keepingOnlyCopies: true,
                                       unlessTheListHolds: ListHolds(step, root, journal), keepingCopiesHolding: keptNotTaken);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
            List<string> kept = KeptOriginalsLeft(step, root);
            if (kept.Count > 0)
            {
                List<string> noLonger = KeptOriginalsOfWhatWasRecorded(kept, step, root);
                trail?.Invoke(new UndoTrailLine(ActivityTrail.Event.UndoKeptWhatAPageHeld, course, section,
                                                UndoTrail.KeptWhatAPageHeldWords(phase, kept, noLonger), kept, noLonger));
            }
        }
        if (!live && outcome == UndoRecoveryOutcome.NothingTookEffect && ChangesOnlyFilesAndMoves(step))
        {
            // Shadow, a step of files killed before its first swap: closed
            // `failed`, so the closed-step tidy (interrupted only) never meets
            // it, and its staged new content would stay beside every page
            // until the switch flips. Nothing took effect, so every staged
            // file is the journal's own; a kept original that differs from
            // its page still stays (W7a, the harness's w7-publish-kill,
            // shadow beforeSwap@0). Nothing on the trail, as shadow writes none.
            try
            {
                UndoSwap.TidyLeftovers(step.Seq, step.PathsToTidy, root, AsideListings(step, root), null, keepingOnlyCopies: true);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
        }
        return new SettleAnswer(new UndoRecoveryResult(step.Seq, phase, outcome, step, root, putBack, inTheWay.Count), false, false);
    }

    private static JsonObject Interrupted(long seq, string phase, string reason, IReadOnlyList<string> paths)
    {
        var named = new JsonArray();
        foreach (string path in paths) named.Add(path);
        return new JsonObject { ["seq"] = seq, ["event"] = "interrupted", ["phase"] = phase, ["reason"] = reason, ["paths"] = named };
    }

    /// <summary>Appends recovery's lines (a clearing's seq the highest in the journal as it is written) and makes them durable.</summary>
    private static bool Write(IEnumerable<JsonObject> events, UndoStep step, UndoJournalWriter writer)
    {
        try
        {
            foreach (JsonObject line in events)
            {
                if ((string?)line["event"] == "cleared") line["seq"] = Math.Max(writer.Folded.Highest, step.Seq);
                writer.Append(line);
            }
            writer.Sync();
            return true;
        }
        catch (UndoJournalException)
        {
            return false;
        }
    }
}

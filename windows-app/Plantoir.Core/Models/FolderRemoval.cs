using System;
using System.Collections.Generic;
using System.Linq;

namespace Plantoir.Core.Models;

/// <summary>
/// A teacher took a FOLDER out of a course: the whole gesture, in the order it
/// has to happen in.
///
/// <para><b>The order is the rule</b>, which is why this is one method in Core
/// rather than three steps in the view. The marks decision is made from what
/// the checklist OFFERS, and what it offers depends on the copy lists and on
/// <c>excluded_items</c> — so the removal has to be RECORDED before the walk
/// that decides. Windows got this wrong the other way round until 2026-09-18:
/// <c>CourseSettingsView.DropFromMarksPool</c> read a walk cached by the
/// previous form pass, taken before the exclusion was written, so the removed
/// folder was still among the choices. Leaving the order in the view meant no
/// test could pin it; moving the steps apart again would be the same bug.</para>
///
/// <para>Pinned by <c>contracts/shared-rules.json</c> -&gt;
/// <c>gradedFolders.removingAFolder</c>, six cases, run by
/// <c>GradedFolderChoicesTests.WhatARemovalDoesToTheMarksPoolMatchesTheContract</c>.
/// Settled 2026-09-09 by Russell (issue #142): Windows adopts the mac's
/// rule.</para>
/// </summary>
public static class FolderRemoval
{
    /// <summary>
    /// Take <paramref name="name"/> out of the course: off its copy list, onto
    /// <c>excluded_items</c>, and — unless one of the two exceptions applies —
    /// out of the marks pool.
    ///
    /// <para><b>Both halves of the exclusion are needed.</b> The name's ABSENCE
    /// from the copy list is the actual mechanism; <c>excluded_items</c> is
    /// what stops the next build's preflight scan rediscovering the folder on
    /// disk and putting it straight back. The build does reconcile the two, but
    /// only at the next build — a teacher reading the list before then would
    /// see a folder they had just removed.</para>
    ///
    /// <para><b>Why the pool is not simply told to drop the name.</b> The
    /// confirmation promises "Removing it will take it out of your course's
    /// marks pool", and leaving a removed folder in the pool would leave
    /// <c>graded_folders</c> naming a folder <c>excluded_items</c> tells the
    /// build to skip. But a removal is not an ANSWER to the marks question, and
    /// two exceptions exist to stop it quietly taking marks OFF the coverage
    /// map:</para>
    ///
    /// <list type="number">
    /// <item><b>A never-asked course is left unasked.</b> <c>graded_folders</c>
    /// stays ABSENT, the historical substring rule keeps running, a
    /// <c>Thinking Tasks</c> still counts, and putting the folder back restores
    /// what the course had. Freezing here is the trap the whole key exists to
    /// avoid: on the ordinary course whose only marked folder is <c>Tasks</c>,
    /// materialising the historical answer and removing the name writes
    /// <c>[]</c> — asked and answered, nothing counts for marks, permanently,
    /// from a gesture the teacher was told would do one narrow thing.</item>
    /// <item><b>A name the checklist STILL OFFERS keeps its place.</b> The pool
    /// is a list of NAMES: drop <c>Tasks</c> while <c>Portfolios/Tasks</c> is
    /// still published and you stop counting a folder nobody removed, while the
    /// checklist goes on showing a <c>Tasks</c> row for it. This is in slight
    /// tension with the confirmation's literal words — the FOLDER left the
    /// course, a folder of that name did not — and the trade was made
    /// deliberately.</item>
    /// </list>
    ///
    /// <para><b>One reason for the drop that is NOT true</b>, kept here because
    /// it was written down wrongly once and a wrong reason gets acted on
    /// (corrected 2026-09-06): a pool naming an excluded folder does not read
    /// as "asked and answered" to the build and does not suppress the
    /// <c>noGradedFolders</c> warning. <c>_has_graded_folders</c> in
    /// <c>build_site.py</c> walks the MERGED tree and answers false when no
    /// directory there matches a pooled name, so <c>site_health.py</c> raises
    /// the finding exactly as it would for an empty pool. The reason to drop
    /// the name is the promise in the dialog, which is reason enough.</para>
    ///
    /// <para><b>Nothing here can ever assign <c>null</c> to the pool</b>, and
    /// that is deliberate: <c>CourseConfiguration.GradedFolders</c>'s setter
    /// turns null into key REMOVAL, so one careless "leave it absent" written
    /// as an assignment would turn a course that HAD been asked back into a
    /// never-asked one. "Leave it absent" is expressed by returning.</para>
    /// </summary>
    /// <param name="courseDirectory">
    /// The course folder, walked afresh HERE rather than read from the view's
    /// cache. The cache is right for drawing rows — the protection rules are
    /// asked once per row of a pass and a disk walk per row would be absurd —
    /// and wrong for this one caller, which runs mid-gesture after writes it
    /// must see. Null or missing is fine: the choices are then the copy lists
    /// alone.
    /// </param>
    public static void RemoveFolderFromCourse(
        CourseConfiguration config, string? courseDirectory, string scope, string name)
    {
        ArgumentNullException.ThrowIfNull(config);
        if (string.IsNullOrEmpty(name)) return;

        bool perSection = scope == CourseConfiguration.PerSectionScope;

        // 1. Off the copy list. Idempotent: the list editor has usually done
        //    this already, and a removal driven from anywhere else has not.
        //    Matched EXACTLY, case included, the way the editor's own
        //    List.Remove and the build's preflight scan match.
        var folders = perSection ? config.PerSectionFolders : config.SharedFolders;
        if (folders.RemoveAll(folder => string.Equals(folder, name, StringComparison.Ordinal)) > 0)
        {
            if (perSection) config.PerSectionFolders = folders;
            else config.SharedFolders = folders;
        }

        // 2. Recorded, so preflight does not rediscover it.
        config.Exclude(scope, name);

        // 3. ONLY NOW is it worth asking what the checklist offers.
        if (GradedFolderChoices.For(config, courseDirectory)
                .Contains(name, StringComparer.OrdinalIgnoreCase)) return;

        // Case-INSENSITIVE, which the contract deliberately leaves unpinned and
        // which matters here. The walk returns names as they are spelled on
        // disk, so removing a top-level `Tasks` while `Portfolios/tasks`
        // survives offers `tasks`; an exact comparison would call that "not
        // offered" and drop `Tasks` from the pool, while `build_site.py`
        // lowercases both sides and goes on counting that folder. Marks would
        // come off the coverage map because of a capital letter. The drop below
        // has always been case-insensitive for the same reason, and the two
        // must agree or a name can be judged absent and removed anyway.
        // Proposed to the mac as a contract case by issue #172; the six cases
        // above cannot see the difference, which is why it is an issue.

        // The never-asked guard, written out because it is half of the rule as
        // the contract states it ("no longer offered AND the course had already
        // been asked") — but it is NOT what makes cases 1 and 2 pass today, and
        // saying otherwise would be the kind of wrong reason that gets acted
        // on. Measured 2026-09-18: replacing this line with
        // `MaterializedGradedFolders(...)` over the SAME post-exclusion walk
        // leaves all six cases green, because `InferredPool` only ever returns
        // names drawn FROM those choices, so a name no longer offered cannot be
        // in the materialised pool either. It is kept because it says the rule
        // plainly and because it does not depend on that subset property: give
        // the historical rule a default of its own and this line is the only
        // thing still standing between a legacy course and a frozen pool.
        var pool = config.GradedFolders;
        if (pool is null) return;                       // never asked: leave it that way
        if (pool.RemoveAll(folder => string.Equals(folder, name, StringComparison.OrdinalIgnoreCase)) == 0) return;
        config.GradedFolders = pool;                    // may legitimately be empty — see case 4
    }
}

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Models;

/// <summary>
/// Putting right the folder problems that CAN be put right.
///
/// <para>Only two of the six checks are repairable, and the line between them
/// is the whole design: <b>a fix must restore the FEATURE, not merely satisfy
/// the check.</b> Recreating an empty curriculum folder would silence "the
/// curriculum map could not be built" and leave the map missing, because that
/// folder only counts once it holds a page named for an expectation code. A
/// button that makes a warning go away without fixing anything is worse than no
/// button: the teacher then believes it is dealt with.</para>
///
/// <para>These two are different. An empty <c>Media</c> folder and a bare front
/// page are the correct starting state rather than a pretence — the pictures
/// are the teacher's and cannot be conjured back, and inventing content for a
/// front page would put words in their mouth.</para>
///
/// <para>Pinned by <c>contracts/shared-rules.json</c> -&gt;
/// <c>siteHealth.repair</c>.</para>
/// </summary>
public static class SiteHealthRepair
{
    // ---- What can be repaired -------------------------------------------

    /// <summary>
    /// Whether THIS app can put a finding right, as opposed to merely knowing
    /// that the toolchain called it fixable.
    ///
    /// <para>Asked of the NAME first — <see cref="SiteHealthFinding.CanBeRepaired"/>,
    /// which a contract test pins against <c>siteHealth.repair.offered.checks</c>
    /// — and of the payload's flag second. The flag arrives from outside and
    /// means "this kind of thing is repairable"; the name is what says this app
    /// has a repair for it. Requiring both is what the mac does, and it means a
    /// build that ever stopped setting the flag would stop offering a button
    /// rather than offering one that cannot work.</para>
    /// </summary>
    public static bool CanRepair(SiteHealthFinding finding) =>
        finding.CanBeRepaired && finding.Fixable;

    public static IReadOnlyList<SiteHealthFinding> Repairable(IEnumerable<SiteHealthFinding> findings) =>
        findings.Where(CanRepair).ToList();

    /// <summary>
    /// What the button says, or null when there is nothing to offer.
    ///
    /// <para>Plain, and about the teacher's course rather than about the check.
    /// A button naming the one thing it will do is worth more than a generic
    /// one, and with two problems there is no short way to name both.</para>
    /// </summary>
    public static string? ButtonTitle(IReadOnlyList<SiteHealthFinding> findings)
    {
        var repairable = Repairable(findings);
        if (repairable.Count == 0) return null;
        if (repairable.Count == 1 && repairable[0].Name == "mediaFolderMissing")
            return "Put the Media folder back";
        if (repairable.Count == 1) return "Add the missing page";
        return "Put them back";
    }

    // ---- What a repair did ----------------------------------------------

    /// <summary>How one repair went.</summary>
    ///
    /// <remarks>
    /// <see cref="AlreadyFine"/> is a THIRD answer, and leaving it out is a bug
    /// the mac shipped and corrected (row 364): both restores decline when the
    /// folder is already there, which is the documented idempotent path —
    /// pressing the button twice, or pressing it after putting the folder back
    /// in Obsidian. Folding that into "failed" tells a teacher whose course is
    /// perfectly all right to go and check whether their disk is read-only.
    /// </remarks>
    public enum Result
    {
        Restored,
        AlreadyFine,
        Failed,
    }

    /// <summary>Where the teacher met the problem.</summary>
    ///
    /// <remarks>
    /// It chooses the SENTENCE and nothing else — the preview is offered on
    /// both occasions — so do not reach for it expecting it to gate behaviour.
    /// </remarks>
    public enum Occasion
    {
        Building,
        Publishing,
    }

    /// <summary>
    /// What a repair did, ready to be shown.
    ///
    /// <para>It exists so that a repair which FAILED is reported too. Both
    /// restores can fail — a read-only volume, a permissions problem, a file
    /// sitting where the folder should be — and reporting only success made a
    /// failed repair indistinguishable from a successful one: the dialog simply
    /// closed either way. Silence on the failure path, in the feature written
    /// to end silence.</para>
    /// </summary>
    public sealed record Outcome(string Headline, string Detail, bool CanRebuild);

    // ---- The sentences ---------------------------------------------------

    public const string CouldNotExplanation =
        "You can make it yourself in Obsidian, or check that the folder holding " +
        "this course isn't locked or read-only.";

    /// <summary>
    /// Why the preview does not show the repair yet.
    ///
    /// <para>The folder is back on disk and the preview still shows how things
    /// were. Left unsaid, "Put the Media folder back" reads as though
    /// everything is fixed — the same silent gap as a warning nobody sees.</para>
    ///
    /// <para><b>"Preview", not "build" — for CLARITY, not because "build" is
    /// forbidden.</b> This app says "build" in plenty of places a teacher reads
    /// ("Click Preview to build this section's website"), and that is fine. The
    /// problem with a button labelled "Build Again" was that it never said WHAT
    /// would be built, and the thing on offer already has a name the teacher
    /// knows.</para>
    /// </summary>
    public const string NotOnTheSiteYet =
        "Your preview still shows how things were before this. " +
        "Preview it again to see the change.";

    /// <summary>
    /// The same, for a teacher whose repair followed a PUBLISH.
    ///
    /// <para><b>The preview is still offered here</b>, which is a change of mind
    /// worth recording. It was withheld on the grounds that a preview does not
    /// change what students see — true, but it conflates two things. The teacher
    /// has just put a folder back and quite reasonably wants to SEE that it
    /// worked. What a preview does NOT do is update the published site, and that
    /// is a job for the sentence rather than for removing the button.</para>
    ///
    /// <para>Careful with the tense: this is ALSO shown when a deploy FAILED,
    /// and for a section publishing for the first time nothing has ever gone
    /// out. It says what publishing WILL do, never what it did.</para>
    /// </summary>
    public const string NotPublishedYet =
        "Publishing is what puts this in front of students, so it is not on " +
        "their site until you publish again. You can preview it now to check " +
        "the change looks right.";

    /// <summary>
    /// What was put back, in words a teacher can check against their folder.
    ///
    /// <para>A repair whose outcome is invisible is a repair nobody trusts the
    /// second time — and the Media folder in particular is somewhere a teacher
    /// cannot see from this app at all, so silence after pressing the button is
    /// indistinguishable from nothing having happened.</para>
    /// </summary>
    public static string? WhatWasPutBack(IReadOnlyList<string> repairedNames)
    {
        var parts = new List<string>();
        foreach (string name in repairedNames)
        {
            if (name == "mediaFolderMissing") parts.Add("the Media folder");
            else if (name == "sectionIndexMissing") parts.Add("the front page");
        }
        if (parts.Count == 0) return null;
        if (parts.Count == 1) return $"Put {parts[0]} back.";
        return "Put " + string.Join(", ", parts.Take(parts.Count - 1)) +
               " and " + parts[^1] + " back.";
    }

    /// <summary>The same list, said the other way round — for a partial failure.</summary>
    public static string? WhatCouldNotBePutBack(IReadOnlyList<string> names)
    {
        if (WhatWasPutBack(names) is not { } described) return null;
        // "Put the front page back." -> "Could not put the front page back."
        return "Could not " + char.ToLowerInvariant(described[0]) + described[1..];
    }

    // ---- Doing it --------------------------------------------------------

    /// <summary>
    /// Repairs what can be repaired and describes the result, whatever it was.
    /// Null when there was nothing repairable to begin with — a teacher who was
    /// only told about a missing curriculum folder is never offered a button,
    /// so nothing is ever reported back to them either.
    /// </summary>
    public static Outcome? OutcomeOfRepairing(
        IReadOnlyList<SiteHealthFinding> findings, Course course,
        Occasion occasion = Occasion.Building)
    {
        var wanted = Repairable(findings);
        if (wanted.Count == 0) return null;

        var results = Repair(wanted, course);

        // Named once each, however many findings produced them: two sections
        // both missing a front page are two repairs and one sentence, and
        // "Put the front page and the front page back." is not a sentence.
        var restored = new List<string>();
        var failed = new List<string>();
        foreach (var (finding, result) in results)
        {
            if (result == Result.Restored) { if (!restored.Contains(finding.Name)) restored.Add(finding.Name); }
            else if (result == Result.Failed) { if (!failed.Contains(finding.Name)) failed.Add(finding.Name); }
        }
        restored.Sort(StringComparer.Ordinal);
        failed.Sort(StringComparer.Ordinal);

        // Nothing to do: every one of them was already there. Pressing the
        // button twice must not read as a permissions problem.
        if (restored.Count == 0 && failed.Count == 0)
            return new Outcome("That is already put right.", "Nothing needed changing.", false);

        if (restored.Count == 0)
            return new Outcome("Plantoir could not put that back.", CouldNotExplanation, false);

        string putBack = WhatWasPutBack(restored) ?? "";

        // A PARTIAL failure said nothing about the half that did not come back
        // — silence whenever anything else succeeded, in the type added so that
        // failure would not be silent.
        if (WhatCouldNotBePutBack(failed) is { } alsoFailed)
            return new Outcome(putBack, alsoFailed + " " + CouldNotExplanation, false);

        return occasion == Occasion.Publishing
            ? new Outcome(putBack, NotPublishedYet, true)
            : new Outcome(putBack, NotOnTheSiteYet, true);
    }

    /// <summary>
    /// Repairs what can be repaired, and reports what each one did.
    ///
    /// <para><b>Never overwrites.</b> Every repair checks first, so pressing the
    /// button twice — or pressing it after fixing the problem in Obsidian —
    /// changes nothing.</para>
    /// </summary>
    /// <remarks>
    /// One entry per FINDING, not per check name — which is a deliberate
    /// divergence from the mac, whose dictionary is keyed by name. Two sections
    /// each missing a front page are two findings with one name: both get
    /// repaired either way, but keyed by name only the last result is reported,
    /// so "section 1 restored, section 2 was already there" becomes "that is
    /// already put right" with no preview offered. Unreachable from the app
    /// today (a view owns one runner, and the checks announce per section), and
    /// cheaper to make impossible than to leave as a comment.
    /// </remarks>
    public static IReadOnlyList<(SiteHealthFinding Finding, Result Result)> Repair(
        IReadOnlyList<SiteHealthFinding> findings, Course course)
    {
        var results = new List<(SiteHealthFinding, Result)>();
        foreach (var finding in findings)
        {
            if (!CanRepair(finding)) continue;
            if (finding.Name == "mediaFolderMissing")
                results.Add((finding, RestoreMedia(course)));
            else if (finding.Name == "sectionIndexMissing")
                results.Add((finding, RestoreIndex(finding.Section, course)));
        }
        return results;
    }

    /// <summary>
    /// An empty <c>Media</c> folder beside the course, which is exactly what a
    /// new course gets.
    /// </summary>
    public static Result RestoreMedia(Course course)
    {
        string path = Path.Combine(course.DirectoryPath, "Media");
        try
        {
            // A FILE where the folder belongs is not "already fine": the build
            // is looking for a directory, and a file there is a problem the
            // teacher has to resolve themselves.
            if (Directory.Exists(path)) return Result.AlreadyFine;
            if (File.Exists(path)) return Result.Failed;
            Directory.CreateDirectory(path);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            return Result.Failed;
        }
        // Not the course+section overload — Media belongs to the whole course,
        // and stamping a section number into the line would name a section the
        // finding may not even be about.
        ActivityTrail.Note(ActivityTrail.Event.FolderProblemRepaired,
                           course.Code + " · put the Media folder back");
        return Result.Restored;
    }

    /// <summary>
    /// A section's front page, carrying a title and nothing else.
    ///
    /// <para>Deliberately almost empty: this is the page a teacher will write,
    /// and inventing content for it would be putting words in their mouth. What
    /// it must have is a title, or the site shows the file name. A page carrying
    /// only <c>title:</c> is VISIBLE — <c>file-formats.json</c> -&gt;
    /// <c>pageVisibility.readingCases</c> — so the bare page restores the
    /// FEATURE rather than merely satisfying the check.</para>
    /// </summary>
    public static Result RestoreIndex(int sectionNumber, Course course)
    {
        // A finding's section number is parsed from the build's output and
        // falls back to 0 when it is missing or the wrong type. Creating a
        // `section0` folder because a line was malformed would be inventing
        // structure the course does not have.
        if (!course.Configuration.SectionNumbers.Contains(sectionNumber)) return Result.Failed;

        string sectionDirectory = course.SectionDirectory(sectionNumber);
        string index = Path.Combine(sectionDirectory, "index.md");
        try
        {
            // A FOLDER named index.md is not "already fine": Quartz needs a
            // page there, and File.Exists answers false for a directory — so
            // without this the write below fails and the teacher is told to
            // check whether their disk is read-only, which is not the problem.
            // (The mac asks fileExists, which is TRUE for a directory, and
            // therefore reports this one as already put right — the worse of
            // the two answers. See MAC-HANDOFF.)
            if (Directory.Exists(index)) return Result.Failed;
            if (File.Exists(index)) return Result.AlreadyFine;
            Directory.CreateDirectory(sectionDirectory);
            // The course's own name, matching the mac character for character:
            // the same button on the two platforms must not write differently
            // titled pages into a teacher's vault.
            File.WriteAllText(index, $"---\ntitle: {course.Configuration.CourseName}\n---\n");
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            return Result.Failed;
        }
        ActivityTrail.Note(ActivityTrail.Event.FolderProblemRepaired,
                           "put the front page back", course.Code, sectionNumber);
        return Result.Restored;
    }
}

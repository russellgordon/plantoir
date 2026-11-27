using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Undo;

namespace Plantoir.Core.Models;

/// <summary>Where a folder lives, for the purposes of a rename.</summary>
public enum FolderScope
{
    /// <summary>One copy, at the course root.</summary>
    Shared,
    /// <summary>One copy per section, under each <c>section&lt;N&gt;</c>.</summary>
    PerSection,
}

/// <summary>What a rename did, or why it could not be finished.</summary>
public sealed record RenameOutcome(
    bool Succeeded,
    string Message,
    int FoldersMoved,
    int PagesRelinked,
    bool NothingWasThere);

/// <summary>
/// Renaming one of a course's folders from inside Plantoir — on disk, in every
/// section that has one, in the links that name it, and in every configuration
/// key that mentioned it.
///
/// <para><b>Why this exists at all.</b> The list editors in Course Settings
/// changed <c>course_config.json</c> and never touched disk, so Add wrote an
/// entry pointing at no folder and Remove left a folder full of the teacher's
/// work unreferenced. A rename was possible only in Obsidian, after which
/// preflight discovered the new name and APPENDED it, leaving the
/// configuration naming both. Renaming from inside Plantoir is the one moment
/// the change can be WITNESSED, which is what makes the rest of it
/// possible.</para>
///
/// <para><b>Three decisions, none obvious from the code.</b></para>
/// <list type="number">
/// <item><description><b>It commits to disk immediately, not at Save.</b>
/// Settings holds its edits in memory and reverts them on Cancel — but a
/// folder that has really moved cannot be un-moved, so a rename that waited
/// for Save would let Cancel appear to undo something it cannot. The
/// configuration is written to a FRESH read of the file, so the teacher's
/// other unsaved edits stay unsaved.</description></item>
/// <item><description><b>Nothing moves until every destination has been
/// checked.</b> A per-section rename is several moves, and one that got half
/// way through four sections would leave a course nobody could reason about.
/// This matters more on Windows than on the mac: <see cref="Directory.Move"/>
/// refuses a folder with an open handle, and both OneDrive and Obsidian hold
/// them.</description></item>
/// <item><description><b>The class folder need NOT keep the word "class" in
/// its new name.</b> A refusal to that effect shipped on the mac for a few
/// hours and was reversed the same day: it was Plantoir's vocabulary imposed
/// on a teacher's, and somebody whose units are Threads and whose classes are
/// Days calls the folder "All Days". The lookup was what was at fault, and
/// <c>class_folder</c> — which this rename MATERIALISES — is the
/// fix.</description></item>
/// </list>
///
/// <para><b>Renaming a folder is far safer than renaming a page</b>, which is
/// why this ships without an undo. Obsidian resolves <c>[[Quiz 1]]</c> by
/// searching the vault, so a bare link survives the folder moving; only
/// QUALIFIED links break, and <see cref="FolderPathRewriter"/> handles
/// those.</para>
/// </summary>
public static class SpecialFolderRenamer
{
    /// <summary>Names Plantoir keeps for itself.</summary>
    private const string MediaFolderName = "Media";

    /// <summary>
    /// Why this new name cannot be used, or null when it can.
    ///
    /// <para>Checked before anything is touched, and every sentence is the
    /// contract's — see <c>specialNames.renameFolder.problems</c>.</para>
    /// </summary>
    public static string? Problem(string? newName, string currentName, IEnumerable<string> namesInUse) =>
        Problem(newName, currentName, namesInUse, isFinishingAnInterruptedRename: false);

    /// <summary>
    /// The refusals, asked before anything on disk is touched. With
    /// <paramref name="isFinishingAnInterruptedRename"/> the one refusal that
    /// would otherwise stop a rename from being FINISHED — "this course
    /// already has a folder called that" — is waived, because the starting
    /// state of an interrupted rename holds both names by definition: the
    /// folder moved, the configuration still names the old one, and a build
    /// since has discovered the new one and appended it. That is not two
    /// folders competing for a name; it is one rename half done. The flag is
    /// true only for the exact target the record names — see
    /// <see cref="InterruptedRenameTarget"/> — so typing anything else gets
    /// the ordinary refusal back.
    /// </summary>
    public static string? Problem(string? newName, string currentName, IEnumerable<string> namesInUse,
                                  bool isFinishingAnInterruptedRename)
    {
        string wanted = (newName ?? string.Empty).Trim();
        if (wanted.Length == 0) return SpecialNames.RenameProblemEmpty;
        // Exact equality only, as on the mac: "tasks" to "Tasks" is a rename a
        // teacher may reasonably want, and the filesystem lets it through.
        if (wanted.Equals(currentName, StringComparison.Ordinal)) return SpecialNames.RenameProblemUnchanged;
        if (wanted.Contains('/') || wanted.Contains('\\') || wanted.Contains(':'))
            return SpecialNames.RenameProblemHasSeparator;
        if (wanted.StartsWith('.')) return SpecialNames.RenameProblemIsHidden;
        if (wanted.Equals(MediaFolderName, StringComparison.OrdinalIgnoreCase))
            return SpecialNames.RenameProblemIsMedia;
        if (LooksLikeASectionFolder(wanted))
            return SpecialNames.RenameProblemLooksLikeASection.Replace("{name}", wanted);
        if (WindowsWontAllow(wanted))
            return SpecialNames.RenameProblemWindowsWontAllowIt.Replace("{name}", wanted);
        foreach (string used in namesInUse)
            if (!used.Equals(currentName, StringComparison.OrdinalIgnoreCase)
                && used.Equals(wanted, StringComparison.OrdinalIgnoreCase)
                && !isFinishingAnInterruptedRename)
                return SpecialNames.RenameProblemAlreadyUsed.Replace("{name}", wanted);
        return null;
    }

    public sealed class RenameException(string message) : Exception(message);

    // ---- Where a folder by a name would be ---------------------------------

    /// <summary>Every place a folder of this name lives for this scope, whether or not it exists.</summary>
    public static IReadOnlyList<(string Path, int? Section)> FolderLocations(
        string name, FolderScope scope, string courseDirectory, IReadOnlyList<int> sectionNumbers)
    {
        if (scope == FolderScope.Shared) return new[] { (Path.Combine(courseDirectory, name), (int?)null) };
        return sectionNumbers.Select(n => (Path.Combine(courseDirectory, $"section{n}", name), (int?)n)).ToList();
    }

    // ---- The record of a rename that has started ----------------------------

    /// <summary>
    /// <c>&lt;courses&gt;/.internal/renames/&lt;CODE&gt;.json</c> — the
    /// <c>.internal</c> convention both apps share, and deliberately NOT a
    /// <c>course_config.json</c> key, because the failure being handled is
    /// that the configuration write did not happen.
    /// </summary>
    public static string RenameRecordPath(string courseDirectory)
    {
        string trimmed = courseDirectory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        string courses = Path.GetDirectoryName(trimmed) ?? trimmed;
        return Path.Combine(courses, ".internal", "renames", Path.GetFileName(trimmed) + ".json");
    }

    /// <summary>
    /// Written BEFORE anything moves. A rename interrupted between the move
    /// and the configuration write leaves folders under the new name and a
    /// configuration naming the old one; the next build discovers the moved
    /// folder and appends it, so the list holds BOTH names and retrying is
    /// refused as a clash. The disk alone cannot be the evidence — that same
    /// state is also a phantom entry whose folder was never made being renamed
    /// onto a genuine second folder, and bypassing there would hand the real
    /// folder the phantom's attributes, <c>hidden</c> among them. So the
    /// record carries the TARGET, and the clash check is relaxed only when the
    /// record and the disk agree.
    /// </summary>
    public static void RecordRenameStarting(string oldName, string newName, FolderScope scope, string courseDirectory)
    {
        try
        {
            string path = RenameRecordPath(courseDirectory);
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            var note = new JObject { ["from"] = oldName, ["to"] = newName, ["scope"] = ScopeKey(scope) };
            File.WriteAllText(path, note.ToString(Newtonsoft.Json.Formatting.Indented) + "\n");
        }
        catch (Exception) { /* best-effort: a missing record costs a refusal later, never a folder */ }
    }

    /// <summary>The configuration is written, so the rename is whole and the record can go.</summary>
    public static void ClearRenameRecord(string courseDirectory)
    {
        try { File.Delete(RenameRecordPath(courseDirectory)); } catch (Exception) { }
    }

    private static JObject? ReadRenameRecord(string courseDirectory)
    {
        try
        {
            string path = RenameRecordPath(courseDirectory);
            return File.Exists(path) ? JObject.Parse(File.ReadAllText(path)) : null;
        }
        catch (Exception) { return null; }
    }

    /// <summary>
    /// The name a rename of this folder was heading for when it stopped, or
    /// null when nothing was interrupted. Answered when the sheet opens, not
    /// per keystroke: it reads the record and asks the disk.
    /// </summary>
    public static string? InterruptedRenameTarget(
        string oldName, FolderScope scope, string courseDirectory, IReadOnlyList<int> sectionNumbers)
    {
        var note = ReadRenameRecord(courseDirectory);
        if (note?["to"]?.ToString() is not { } target) return null;
        return LooksLikeAnInterruptedRename(oldName, target, scope, courseDirectory, sectionNumbers) ? target : null;
    }

    /// <summary>
    /// True only when BOTH the record and the disk say so: the record names
    /// this exact rename, no place still holds the old folder (a mixture means
    /// something other than an interrupted rename, and the ordinary refusal
    /// must stand), and at least one place holds the new one.
    /// </summary>
    public static bool LooksLikeAnInterruptedRename(
        string oldName, string newName, FolderScope scope, string courseDirectory, IReadOnlyList<int> sectionNumbers)
    {
        var note = ReadRenameRecord(courseDirectory);
        if (note is null) return false;
        if (!string.Equals(note["from"]?.ToString(), oldName, StringComparison.OrdinalIgnoreCase)) return false;
        if (!string.Equals(note["to"]?.ToString(), newName, StringComparison.OrdinalIgnoreCase)) return false;
        if (note["scope"]?.ToString() != ScopeKey(scope)) return false;
        foreach (var (place, _) in FolderLocations(oldName, scope, courseDirectory, sectionNumbers))
            if (Directory.Exists(place) || File.Exists(place)) return false;
        foreach (var (place, _) in FolderLocations(newName, scope, courseDirectory, sectionNumbers))
            if (Directory.Exists(place)) return true;
        return false;
    }

    public static string ScopeKey(FolderScope scope) =>
        scope == FolderScope.Shared ? CourseConfiguration.SharedScope : CourseConfiguration.PerSectionScope;

    public static string ConfigurationKey(FolderScope scope) =>
        scope == FolderScope.Shared ? "shared_folders" : "per_section_folders";

    // ---- Doing it ------------------------------------------------------------

    /// <summary>
    /// Course Settings' change to <c>course_config.json</c>, planned into the
    /// rename's own step (#899 W8b-15b): the configuration this copy holds,
    /// the file, and the change made to a fresh read of it.
    /// </summary>
    public sealed record SettingsChange(CourseConfiguration Configuration, string Path, Func<JObject, JObject> Change);

    /// <summary>
    /// The settings change a rename of this folder makes (<see cref="Renaming"/>),
    /// with the curriculum folders that hold an expectation page read NOW,
    /// before the move (#345): afterwards the old name is not there to read.
    /// </summary>
    public static SettingsChange RenamingTheSettings(CourseConfiguration configuration, string configPath,
                                                     string oldName, string newName, FolderScope scope, string courseDirectory)
    {
        var sharedBefore = configuration.SharedFolders.Append(newName).ToList();
        var (pagesBefore, letterFirstBefore) = CurriculumFolderRule.FoldersWithPages(courseDirectory, sharedBefore);
        var curriculumPages = pagesBefore.Select(f => string.Equals(f, newName, StringComparison.OrdinalIgnoreCase) ? oldName : f).ToList();
        var curriculumLetterFirst = letterFirstBefore.Select(f => string.Equals(f, newName, StringComparison.OrdinalIgnoreCase) ? oldName : f).ToList();
        return new SettingsChange(configuration, configPath,
            values => Renaming(values, oldName, newName, scope, curriculumPages, curriculumLetterFirst));
    }

    /// <summary><c>undo-action-steps.json</c> → <c>renameFolder</c>'s action key.</summary>
    internal const string RenameFolderActionKey = "renameFolder";

    /// <summary>
    /// Renames the folder on disk — in every section that has one — rewrites
    /// the links that name it, and makes <paramref name="settings"/>' change,
    /// as ONE step through the door (#899 W8b-15b; the mac's U4b), made by
    /// <c>sheet</c>, held by the course: one <c>move</c> per place of the
    /// folder (<see cref="UndoActionStep.MoveFolder"/>, judged by its
    /// listing), then each relinked page named at its place after the move,
    /// then one <c>editJSON</c> per changed member of the settings. All of it
    /// or none: a step refused leaves the course exactly as it was, and is
    /// said as a <see cref="RenameException"/>. A step refused because a page
    /// or a setting changed between the plan and the make is planned again
    /// from the disk, up to three times, as the mac's sheet does.
    ///
    /// <para>Nothing is planned until every destination has been checked.
    /// <paramref name="finishing"/> is a rename found interrupted: its
    /// folders already moved, so the step is its relinked pages and its
    /// members, and no move.</para>
    /// </summary>
    public static RenameOutcome Rename(
        string oldName, string newName, FolderScope scope, string courseDirectory, IReadOnlyList<int> sectionNumbers,
        SettingsChange? settings = null, bool finishing = false)
        => Rename(oldName, newName, scope, courseDirectory, sectionNumbers, settings, finishing, null, null);

    /// <param name="undo">The list, mode and trail: this process's by default, a test's own in a test.</param>
    /// <param name="door">A test's door over <paramref name="undo"/>; the list's own by default.</param>
    internal static RenameOutcome Rename(
        string oldName, string newName, FolderScope scope, string courseDirectory, IReadOnlyList<int> sectionNumbers,
        SettingsChange? settings, bool finishing, UndoForThisProcess? undo, UndoDoor? door)
    {
        IReadOnlyList<(string From, string To, int? Section)> moves = finishing
            ? new List<(string, string, int?)>()
            : Moves(courseDirectory, oldName, newName, scope, sectionNumbers);
        // A rename that only changes capitalisation moves a folder onto
        // itself: the destination "exists" because it IS the source.
        bool onlyCapitalisation = oldName.Equals(newName, StringComparison.OrdinalIgnoreCase);
        if (!onlyCapitalisation && WhyTheMovesCannotBeMade(moves) is { } refusal)
            throw new RenameException(refusal);

        string? workingFolder = HowITeachSettingsRow.WorkingFolderOf(courseDirectory);
        string course = Path.GetFileName(Path.TrimEndingDirectorySeparator(Path.GetFullPath(courseDirectory)));
        int attempts = 0;
        while (true)
        {
            var step = new UndoActionStep(new UndoStepMaker("sheet", RenameFolderActionKey), workingFolder, course,
                                          section: null, holds: "course", undo: undo, door: door);
            int relinked;
            CourseConfiguration.PlannedRecord? plannedSettings = null;
            try
            {
                foreach (var move in moves) step.MoveFolder(move.From, move.To);
                relinked = PlanRelinkedPages(step, courseDirectory, oldName, newName, moves);
                if (settings is not null) plannedSettings = settings.Configuration.PlanRecordOnDisk(settings.Change, settings.Path, step);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or Newtonsoft.Json.JsonException)
            {
                // Only planning: nothing was written.
                throw new RenameException(error.Message);
            }

            if (moves.Count > 0) RecordRenameStarting(oldName, newName, scope, courseDirectory);
            try { step.Make(); }
            catch (UndoStepRefusedException refused) when (refused.Refusal.Kind == UndoRefusalKind.ChangedSince && attempts < 3)
            {
                attempts++;
                continue;
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                throw new RenameException(error.Message);
            }
            if (plannedSettings is not null) settings!.Configuration.FinishRecord(plannedSettings, settings.Change, settings.Path);

            if (!finishing && moves.Count == 0)
            {
                // No folder to move — but a page may still carry a qualified
                // link into the name, and the configuration changes under it,
                // so the links are rewritten regardless; and the rename DID
                // happen, so the done sentence leads and "nothing was there"
                // is the explanation after it, as on the mac.
                string done = SpecialNames.RenameDone.Replace("{old}", oldName).Replace("{new}", newName);
                return new RenameOutcome(true, done + " " + SpecialNames.RenameNothingWasThere, 0, relinked, NothingWasThere: true);
            }
            return new RenameOutcome(true, DoneMessage(oldName, newName, relinked), moves.Count, relinked, NothingWasThere: false);
        }
    }

    /// <summary>
    /// Plans every page in the course whose links name the folder, rewritten,
    /// into <paramref name="step"/>: each read now, from where the walk finds
    /// it, and named at its place AFTER the moves (inside a moved folder, at
    /// the folder's new place, which the move carries). The walk never goes
    /// through a link (<see cref="PagePaths.MarkdownPages"/> with
    /// <c>descendsIntoLinks: false</c>), so a page is relinked only at its own
    /// place inside the course. The pages are planned in the one page order
    /// (<see cref="UndoActionStep.ComparePageOrder"/>, by the place each is
    /// named at), which a step that moves no folder keeps as planned. A page
    /// that cannot be read, or is not UTF-8, is left out, as on the mac.
    /// Returns how many pages are planned.
    /// </summary>
    internal static int PlanRelinkedPages(UndoActionStep step, string courseDirectory, string oldName, string newName,
                                          IReadOnlyList<(string From, string To, int? Section)> moves)
    {
        var strict = new UTF8Encoding(false, throwOnInvalidBytes: true);
        var planned = new List<(string Place, byte[] Rewritten)>();
        foreach (string page in PagePaths.MarkdownPages(courseDirectory, descendsIntoLinks: false))
        {
            string text;
            try { text = strict.GetString(File.ReadAllBytes(page)); }
            catch (Exception) { continue; }
            if (FolderPathRewriter.Count(text, oldName) == 0) continue;
            string rewritten = FolderPathRewriter.Rewritten(text, oldName, newName);
            if (rewritten == text) continue;
            planned.Add((PlaceAfter(moves, page), strict.GetBytes(rewritten)));
        }
        planned.Sort((first, second) => UndoActionStep.ComparePageOrder(Slashed(first.Place), Slashed(second.Place)));
        foreach (var (place, rewritten) in planned) step.WriteBytes(place, rewritten);
        return planned.Count;
    }

    /// <summary>A page's place once the folders have moved: under a move's <c>To</c> when it is inside its <c>From</c>, by the one comparison (<see cref="UndoOp.PartInside"/>).</summary>
    private static string PlaceAfter(IReadOnlyList<(string From, string To, int? Section)> moves, string page)
    {
        string place = Path.GetFullPath(page);
        foreach (var move in moves)
        {
            if (UndoOp.PartInside(Slashed(Path.GetFullPath(move.From)), Slashed(place)) is not { } inside) continue;
            string to = Path.GetFullPath(move.To);
            return inside.Length == 0 ? to : Path.Combine(to, inside.Replace('/', Path.DirectorySeparatorChar));
        }
        return place;
    }

    private static string Slashed(string fullPath) => fullPath.Replace('\\', '/');

    /// <summary>What the teacher is told afterwards: what moved, and what else changed.</summary>
    public static string DoneMessage(string oldName, string newName, int relinked)
    {
        string done = SpecialNames.RenameDone.Replace("{old}", oldName).Replace("{new}", newName);
        string links = relinked switch
        {
            0 => SpecialNames.RenameRelinkedNone,
            1 => SpecialNames.RenameRelinkedOne,
            _ => SpecialNames.RenameRelinkedMany.Replace("{count}", relinked.ToString()),
        };
        return done + " " + links;
    }

    /// <summary>
    /// Adding a name to a list CREATES the folder — in every section, for a
    /// per-section one. It used to write a configuration entry pointing at
    /// nothing. Since #580 (the mac's #506) the folder is not left empty: it
    /// gets the two pages a folder made with the course gets, its
    /// <c>index.md</c> and a <c>_DUPLICATE ME.md</c> (<see cref="FolderScaffold"/>),
    /// written only into a folder this call makes, never into one already on
    /// disk. The folders and their pages are ONE step, all or none
    /// (<see cref="FolderScaffold.PlanPages"/>). <see cref="FolderScaffold.Outcome.FoldersCreated"/>
    /// is 0 when nothing was made.
    /// </summary>
    /// <param name="template">The bundled template's text (<see cref="FolderScaffold.ReadTemplate"/>); null leaves it out.</param>
    /// <param name="curriculumPageNames">
    /// Asked once the folders to make are known and before the step is planned, as
    /// the mac's <c>createFoldersOnDisk</c> reads it since U4a (#899 W8-13): the file
    /// names at the top of the course's primary curriculum folder, or null.
    /// </param>
    /// <param name="created">The <c>created</c> stamp, in the wizard's form; null is now.</param>
    public static FolderScaffold.Outcome CreateFoldersOnDisk(string name, FolderScope scope, string courseDirectory,
        IReadOnlyList<int> sectionNumbers, string? template = null, Func<IReadOnlyList<string>?>? curriculumPageNames = null,
        string? created = null)
        => CreateFoldersOnDisk(name, scope, courseDirectory, sectionNumbers, template, curriculumPageNames, created, null, null);

    /// <param name="undo">The list, mode and trail: this process's by default, a test's own in a test.</param>
    /// <param name="door">A test's door over <paramref name="undo"/>; the list's own by default.</param>
    internal static FolderScaffold.Outcome CreateFoldersOnDisk(string name, FolderScope scope, string courseDirectory,
        IReadOnlyList<int> sectionNumbers, string? template, Func<IReadOnlyList<string>?>? curriculumPageNames,
        string? created, UndoForThisProcess? undo, UndoDoor? door)
    {
        // Re-adding a name whose folder is already there is the common case
        // and is not worth a word.
        var newFolders = new List<string>();
        foreach (var (place, _) in FolderLocations(name, scope, courseDirectory, sectionNumbers))
        {
            if (Directory.Exists(place) || File.Exists(place)) continue;
            newFolders.Add(place);
        }
        if (newFolders.Count == 0) return new FolderScaffold.Outcome();
        var pages = FolderScaffold.Pages(name, scope, sectionNumbers, curriculumPageNames?.Invoke(),
            created ?? SectionAdder.Timestamp(DateTimeOffset.Now), template);
        // ONE step (#899 W8-13; the mac's U4a): each folder made whole with
        // its two pages, as one createTree, all of them or none. The folder
        // list's own change is Save's, in Save's step. A failure makes
        // nothing, and the outcome says no folder was made.
        var step = new UndoActionStep(new UndoStepMaker("sheet", AddFolderActionKey),
            HowITeachSettingsRow.WorkingFolderOf(courseDirectory),
            Path.GetFileName(Path.TrimEndingDirectorySeparator(Path.GetFullPath(courseDirectory))),
            section: null, holds: "course", undo: undo, door: door);
        var outcome = FolderScaffold.PlanPages(pages, newFolders, courseDirectory, step);
        try { step.Make(); }
        catch (Exception) { return new FolderScaffold.Outcome(); }
        return outcome;
    }

    /// <summary><c>undo-action-steps.json</c> → <c>addFolder</c>'s action key.</summary>
    internal const string AddFolderActionKey = "addFolder";

    // ---- The configuration keys a rename carries across -----------------------

    /// <summary>
    /// The configuration with every key that named the folder now naming the
    /// new one — a port of the mac's <c>renaming(_:to:scope:in:)</c>, and the
    /// one consumer of <see cref="KeysThatCarryAcross"/>. Run against a FRESH
    /// read of the file by <see cref="CourseConfiguration.RecordOnDisk"/>.
    ///
    /// <para>Materialised, not merely carried: a course made from scratch has
    /// <c>curriculum_folder: null</c> and no <c>class_folder</c>, both found
    /// by guessing at the name. Rename <c>Curriculum</c> to
    /// <c>Expectations</c> without writing the key and the guess stops
    /// finding it, the map is built from nothing, and nobody is told. The
    /// rename is the one moment Plantoir witnesses the change.</para>
    ///
    /// <para><c>hidden</c> is the dangerous one: leave it naming the old folder
    /// and a rename silently UN-HIDES it, so the next publish puts pages the
    /// teacher deliberately hid in front of students. Scoped keys are carried
    /// only by a rename in their own scope, because a shared folder and a
    /// per-section folder may legitimately share a name.</para>
    /// </summary>
    /// <param name="withPages">
    /// The shared folders that held an expectation page BEFORE the move (#345):
    /// which curriculum folders the course resolves to is decided from the
    /// disk, and after the move the old name is not there to read. Null reads
    /// the curriculum folders by name alone, as before.
    /// </param>
    /// <param name="withLetterFirstPages">Those of them holding a letter-first (<c>A1.1</c>) page; null means all of them.</param>
    public static JObject Renaming(JObject values, string oldName, string newName, FolderScope scope,
                                   IEnumerable<string>? withPages = null, IEnumerable<string>? withLetterFirstPages = null)
    {
        var updated = (JObject)values.DeepClone();
        var perSection = Strings(values["per_section_folders"]);
        var shared = Strings(values["shared_folders"]);

        // Which special folder, if either, this WAS — decided before the list
        // is rewritten, because both answers are derived from it.
        bool wasTheClassFolder = scope == FolderScope.PerSection
            && WasSurelyTheClassFolder(oldName, perSection,
                values["class_folder"]?.Type == JTokenType.String ? values["class_folder"]!.ToString() : null);
        // #345: ONE OF the curriculum folders the course resolves to — declared
        // first, then (when none holds a page) the scan's — read from the
        // pages as they were before the move.
        var declaredCurriculum = CurriculumFolderRule.Declared(values["curriculum_folders"], values["curriculum_folder"]);
        var curriculum = CurriculumFolderRule.Resolve(declaredCurriculum, shared, withPages, withLetterFirstPages);
        bool wasACurriculumFolder = scope == FolderScope.Shared
            && curriculum.Resolved.Contains(oldName, StringComparer.OrdinalIgnoreCase);

        string listKey = ConfigurationKey(scope);
        updated[listKey] = new JArray(RenamingInList(Strings(values[listKey]), oldName, newName));

        if (wasTheClassFolder) updated["class_folder"] = newName;
        if (wasACurriculumFolder)
        {
            // The declared list (or, when nothing was declared, the folders it
            // resolves to) with the old name replaced in the same place — and
            // the legacy key naming the list's FIRST (primary) folder, so an
            // older Plantoir reading only that key keeps its map.
            var list = (declaredCurriculum.Count > 0 ? declaredCurriculum : curriculum.Resolved.ToList())
                .Select(name => string.Equals(name, oldName, StringComparison.OrdinalIgnoreCase) ? newName : name)
                .ToList();
            updated["curriculum_folders"] = new JArray(list);
            updated["curriculum_folder"] = list[0];
        }

        // Three flat lists that name folders from EITHER scope.
        foreach (string key in new[] { "graded_folders", "hidden", "expandable" })
            if (values[key] is JArray names)
                updated[key] = new JArray(RenamingInList(Strings(names), oldName, newName));

        // Scoped, both of them: carried only by a rename in their own scope.
        if (!wasACurriculumFolder && scope == FolderScope.Shared && values["curriculum_folder"]?.Type == JTokenType.String
            && values["curriculum_folder"]!.ToString().Equals(oldName, StringComparison.OrdinalIgnoreCase))
            updated["curriculum_folder"] = newName;
        if (scope == FolderScope.PerSection && values["class_folder"]?.Type == JTokenType.String
            && values["class_folder"]!.ToString().Equals(oldName, StringComparison.OrdinalIgnoreCase))
            updated["class_folder"] = newName;

        // This scope's exclusions only: excluded_items is keyed by scope
        // precisely because the same bare name can exist in both.
        if (values["excluded_items"] is JObject excluded && excluded[ScopeKey(scope)] is JArray excludedNames)
        {
            var rewritten = (JObject)excluded.DeepClone();
            rewritten[ScopeKey(scope)] = new JArray(RenamingInList(Strings(excludedNames), oldName, newName));
            updated["excluded_items"] = rewritten;
        }
        return updated;
    }

    /// <summary>
    /// Whether this folder is the class folder with enough confidence to write
    /// the key. A recorded key that names a real folder is the answer. With
    /// nothing recorded the resolver GUESSES — "class" in the name, else the
    /// first folder — and freezing a first-folder guess into <c>class_folder</c>
    /// would stop a real "All Classes" added later from ever taking over, and
    /// leave the same course with different JSON on the two machines. So,
    /// unrecorded, the name must contain "class" and be what the resolver
    /// picks. The mac's <c>wasSurelyTheClassFolder</c>, found by its review
    /// 2026-09-01 and by this side's 2026-09-07.
    /// </summary>
    public static bool WasSurelyTheClassFolder(string name, IReadOnlyList<string> perSectionFolders, string? recorded)
    {
        if (recorded is { Length: > 0 }
            && perSectionFolders.Any(f => f.Equals(recorded, StringComparison.OrdinalIgnoreCase)))
            return recorded.Equals(name, StringComparison.OrdinalIgnoreCase);
        if (!name.Contains("class", StringComparison.OrdinalIgnoreCase)) return false;
        return ClassFolderRule.Name(perSectionFolders).Equals(name, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// The list with the old name replaced — and DE-DUPLICATED, because the
    /// starting state of an interrupted rename holds both names by definition,
    /// and a naive rename would leave the new one in twice.
    /// </summary>
    public static List<string> RenamingInList(IEnumerable<string> names, string oldName, string newName)
    {
        var result = new List<string>();
        foreach (string name in names)
        {
            string renamed = name.Equals(oldName, StringComparison.OrdinalIgnoreCase) ? newName : name;
            if (!result.Any(kept => kept.Equals(renamed, StringComparison.OrdinalIgnoreCase))) result.Add(renamed);
        }
        return result;
    }

    private static List<string> Strings(JToken? token)
    {
        var result = new List<string>();
        if (token is JArray array)
            foreach (var element in array)
                if (element is JValue { Type: JTokenType.String } v) result.Add((string)v!);
        return result;
    }

    /// <summary>
    /// Names Windows itself will not accept, checked BEFORE anything is
    /// touched so a teacher is told plainly rather than meeting the operating
    /// system's own error half way through a rename.
    ///
    /// <para>The trailing dot is the one worth knowing about: Windows strips
    /// it, so <c>Tasks.</c> resolves to <c>Tasks</c> and the destination check
    /// would report "there is already something called Tasks. beside it" about
    /// the very folder being renamed.</para>
    /// </summary>
    private static bool WindowsWontAllow(string name)
    {
        foreach (char invalid in Path.GetInvalidFileNameChars())
            if (name.Contains(invalid)) return true;
        if (name.EndsWith('.') || name.EndsWith(' ')) return true;

        // The device names DOS reserved, with or without an extension.
        string stem = name;
        int dot = stem.IndexOf('.');
        if (dot >= 0) stem = stem[..dot];
        foreach (string reserved in ReservedDeviceNames)
            if (stem.Equals(reserved, StringComparison.OrdinalIgnoreCase)) return true;
        return false;
    }

    private static readonly string[] ReservedDeviceNames =
    {
        "CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
    };

    /// <summary>
    /// <c>section3</c> and friends: what Plantoir calls a section's own folder,
    /// so a teacher's folder cannot be called that.
    /// </summary>
    private static bool LooksLikeASectionFolder(string name)
    {
        if (!name.StartsWith("section", StringComparison.OrdinalIgnoreCase)) return false;
        string rest = name["section".Length..];
        return rest.Length > 0 && rest.All(char.IsDigit);
    }

    /// <summary>
    /// Every folder that would move, in the order they would move.
    ///
    /// <para>A shared folder is one move at the course root; a per-section
    /// folder is one move under each section that actually has it. A section
    /// that does not have the folder is not an error — a course can have four
    /// sections and the folder in three.</para>
    /// </summary>
    public static IReadOnlyList<(string From, string To, int? Section)> Moves(
        string courseDirectory, string currentName, string newName,
        FolderScope scope, IReadOnlyList<int> sectionNumbers)
    {
        var moves = new List<(string, string, int?)>();
        // Path.Combine with a ROOTED second argument discards the first and
        // returns the root - so a new name of "C:\Windows" would move the
        // folder out of the course entirely. Problem() refuses such a name and
        // every caller is meant to ask it first, but a move list is not the
        // place to depend on that.
        if (Path.IsPathRooted(newName) || newName.Contains('/') || newName.Contains('\\'))
            return moves;

        if (scope == FolderScope.Shared)
        {
            string from = Path.Combine(courseDirectory, currentName);
            if (IsAPlaceToMove(from))
                moves.Add((from, Path.Combine(courseDirectory, newName), null));
            return moves;
        }

        foreach (int section in sectionNumbers)
        {
            string sectionDirectory = Path.Combine(courseDirectory, $"section{section}");
            string from = Path.Combine(sectionDirectory, currentName);
            if (IsAPlaceToMove(from))
                moves.Add((from, Path.Combine(sectionDirectory, newName), section));
        }
        return moves;
    }

    /// <summary>
    /// Whether a place holds something the rename moves, looked at WITHOUT
    /// following a link (<see cref="UndoLinks.Look"/>, never
    /// <c>Directory.Exists</c>, which follows one): a folder; or a link, or a
    /// place that cannot be looked at now, either of which the step refuses
    /// <c>cannotTellNow</c> with nothing changed (a linked folder is renamed
    /// as a link by W8b-21). A file at the place, or nothing, is not moved.
    /// </summary>
    private static bool IsAPlaceToMove(string place) =>
        UndoLinks.Look(place) is UndoLinks.What.Folder or UndoLinks.What.Link or UndoLinks.What.CannotLook;

    /// <summary>
    /// Why the moves cannot all be made, or null when they can.
    ///
    /// <para>Every destination checked BEFORE any of them is moved. On Windows
    /// this is not belt-and-braces: <see cref="Directory.Move"/> refuses a
    /// folder with an open handle, and a teacher's folder is very often open in
    /// Obsidian or being copied by OneDrive.</para>
    /// </summary>
    public static string? WhyTheMovesCannotBeMade(
        IReadOnlyList<(string From, string To, int? Section)> moves)
    {
        foreach (var move in moves)
        {
            if (Directory.Exists(move.To) || File.Exists(move.To))
                return SpecialNames.RenameProblemDestinationExists
                    .Replace("{name}", Path.GetFileName(move.To));
        }
        return null;
    }

    /// <summary>
    /// The sentence describing a rename that got part of the way and then
    /// stopped.
    ///
    /// <para>The SHAPE is the point: the count that moved, and the section that
    /// stopped it. A bare exception here leaves a teacher with a course renamed
    /// in two sections out of four and no idea which — and a folder half
    /// renamed is not something they can put right without being told where to
    /// look.</para>
    /// </summary>
    public static string HalfFailureMessage(int moved, int total, string name, int? section, string reason)
    {
        string where = section is int number ? $"the one in section{number}" : "the one at the top of the course";
        return $"Plantoir renamed {moved} of {total} copies of “{name}” and then could not rename {where}: {reason}";
    }

    /// <summary>
    /// The keys a rename must carry across, from the contract rather than from
    /// memory.
    ///
    /// <para><c>hidden</c> is the dangerous one: it holds the folders kept OUT
    /// of the built site, so a rename that does not carry it silently UN-HIDES
    /// the folder and the next publish puts pages the teacher deliberately hid
    /// in front of students. Missed on the mac until the real app was driven,
    /// on a course whose hidden list named its Curriculum folder.</para>
    /// </summary>
    public static IReadOnlyList<string> KeysThatCarryAcross => new[]
    {
        "shared_folders", "per_section_folders", "graded_folders", "curriculum_folder", "curriculum_folders",
        "class_folder", "hidden", "expandable", "excluded_items",
    };
}

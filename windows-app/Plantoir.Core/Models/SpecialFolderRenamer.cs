using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Newtonsoft.Json.Linq;

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
    /// Renames the folder on disk — in every section that has one — and
    /// rewrites the links that name it. The configuration is NOT touched here:
    /// the caller records the change with <see cref="Renaming"/> through
    /// <see cref="CourseConfiguration.RecordOnDisk"/>, disk first on purpose,
    /// so that a move that fails leaves the course exactly as it was.
    ///
    /// <para>Nothing moves until every destination has been checked (a
    /// per-section rename is several moves, and one that stopped half way
    /// would leave a course nobody could reason about). If a move still
    /// fails — <c>Directory.Move</c> refuses a folder with an open handle, and
    /// both OneDrive and Obsidian hold them — the moved sections stay moved
    /// and the exception names WHICH section stopped it. Rolling back was
    /// rejected: a roll-back can itself half-fail, leaving a state nobody has
    /// a sentence for, and it moves a teacher's folders a second time without
    /// being asked.</para>
    /// </summary>
    public static RenameOutcome Rename(
        string oldName, string newName, FolderScope scope, string courseDirectory, IReadOnlyList<int> sectionNumbers)
    {
        var moves = Moves(courseDirectory, oldName, newName, scope, sectionNumbers);
        // A rename that only changes capitalisation moves a folder onto
        // itself: the destination "exists" because it IS the source.
        bool onlyCapitalisation = oldName.Equals(newName, StringComparison.OrdinalIgnoreCase);
        if (!onlyCapitalisation && WhyTheMovesCannotBeMade(moves) is { } refusal)
            throw new RenameException(refusal);

        if (moves.Count == 0)
        {
            // No folder to move — but a page may still carry a qualified link
            // into the name, and the configuration is about to change under
            // it, so the links are rewritten regardless; and the rename DID
            // happen, so the done sentence leads and "nothing was there" is
            // the explanation after it, as on the mac.
            int relinkedAnyway = RelinkPages(courseDirectory, oldName, newName);
            string done = SpecialNames.RenameDone.Replace("{old}", oldName).Replace("{new}", newName);
            return new RenameOutcome(true, done + " " + SpecialNames.RenameNothingWasThere, 0, relinkedAnyway, NothingWasThere: true);
        }

        RecordRenameStarting(oldName, newName, scope, courseDirectory);

        int moved = 0;
        foreach (var move in moves)
        {
            try { Directory.Move(move.From, move.To); moved++; }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                throw new RenameException(HalfFailureMessage(moved, moves.Count, oldName, move.Section, error.Message));
            }
        }

        int relinked = RelinkPages(courseDirectory, oldName, newName);
        return new RenameOutcome(true, DoneMessage(oldName, newName, relinked), moved, relinked, NothingWasThere: false);
    }

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
    /// Every page in the course whose links name the folder is rewritten.
    /// One unwritable page must not abandon the rest: the folder has already
    /// moved, so stopping would leave MORE links broken than carrying on.
    /// </summary>
    public static int RelinkPages(string courseDirectory, string oldName, string newName)
    {
        int changed = 0;
        foreach (string page in PagePaths.MarkdownPages(courseDirectory))
        {
            string text;
            try { text = File.ReadAllText(page); } catch (Exception) { continue; }
            if (FolderPathRewriter.Count(text, oldName) == 0) continue;
            string rewritten = FolderPathRewriter.Rewritten(text, oldName, newName);
            if (rewritten == text) continue;
            try { File.WriteAllText(page, rewritten); changed++; } catch (Exception) { }
        }
        return changed;
    }

    /// <summary>
    /// Adding a name to a list CREATES the folder — in every section, for a
    /// per-section one. It used to write a configuration entry pointing at
    /// nothing. Nothing is put inside: an empty folder is the honest starting
    /// state. True when at least one folder was made.
    /// </summary>
    public static bool CreateFoldersOnDisk(string name, FolderScope scope, string courseDirectory, IReadOnlyList<int> sectionNumbers)
    {
        bool created = false;
        foreach (var (place, _) in FolderLocations(name, scope, courseDirectory, sectionNumbers))
        {
            try
            {
                if (Directory.Exists(place) || File.Exists(place)) continue;
                Directory.CreateDirectory(place);
                created = true;
            }
            catch (Exception) { }
        }
        return created;
    }

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
    public static JObject Renaming(JObject values, string oldName, string newName, FolderScope scope)
    {
        var updated = (JObject)values.DeepClone();
        var perSection = Strings(values["per_section_folders"]);
        var shared = Strings(values["shared_folders"]);

        // Which special folder, if either, this WAS — decided before the list
        // is rewritten, because both answers are derived from it.
        bool wasTheClassFolder = scope == FolderScope.PerSection
            && WasSurelyTheClassFolder(oldName, perSection,
                values["class_folder"]?.Type == JTokenType.String ? values["class_folder"]!.ToString() : null);
        bool wasTheCurriculumFolder = scope == FolderScope.Shared
            && string.Equals(
                CurriculumFolderRule.Resolve(values["curriculum_folder"]?.Type == JTokenType.String ? values["curriculum_folder"]!.ToString() : null, shared),
                oldName, StringComparison.OrdinalIgnoreCase);

        string listKey = ConfigurationKey(scope);
        updated[listKey] = new JArray(RenamingInList(Strings(values[listKey]), oldName, newName));

        if (wasTheClassFolder) updated["class_folder"] = newName;
        if (wasTheCurriculumFolder) updated["curriculum_folder"] = newName;

        // Three flat lists that name folders from EITHER scope.
        foreach (string key in new[] { "graded_folders", "hidden", "expandable" })
            if (values[key] is JArray names)
                updated[key] = new JArray(RenamingInList(Strings(names), oldName, newName));

        // Scoped, both of them: carried only by a rename in their own scope.
        if (scope == FolderScope.Shared && values["curriculum_folder"]?.Type == JTokenType.String
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
            if (Directory.Exists(from))
                moves.Add((from, Path.Combine(courseDirectory, newName), null));
            return moves;
        }

        foreach (int section in sectionNumbers)
        {
            string sectionDirectory = Path.Combine(courseDirectory, $"section{section}");
            string from = Path.Combine(sectionDirectory, currentName);
            if (Directory.Exists(from))
                moves.Add((from, Path.Combine(sectionDirectory, newName), section));
        }
        return moves;
    }

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
        "shared_folders", "per_section_folders", "graded_folders", "curriculum_folder",
        "class_folder", "hidden", "expandable", "excluded_items",
    };
}

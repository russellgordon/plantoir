using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

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
    public static string? Problem(string? newName, string currentName, IEnumerable<string> namesInUse)
    {
        string wanted = (newName ?? string.Empty).Trim();
        if (wanted.Length == 0) return SpecialNames.RenameProblemEmpty;
        if (wanted.Equals(currentName, StringComparison.OrdinalIgnoreCase)) return SpecialNames.RenameProblemUnchanged;
        if (wanted.Contains('/') || wanted.Contains('\\') || wanted.Contains(':'))
            return SpecialNames.RenameProblemHasSeparator;
        if (wanted.StartsWith('.')) return SpecialNames.RenameProblemIsHidden;
        if (wanted.Equals(MediaFolderName, StringComparison.OrdinalIgnoreCase))
            return SpecialNames.RenameProblemIsMedia;
        if (LooksLikeASectionFolder(wanted))
            return SpecialNames.RenameProblemLooksLikeASection.Replace("{name}", wanted);
        foreach (string used in namesInUse)
            if (!used.Equals(currentName, StringComparison.OrdinalIgnoreCase)
                && used.Equals(wanted, StringComparison.OrdinalIgnoreCase))
                return SpecialNames.RenameProblemAlreadyUsed.Replace("{name}", wanted);
        return null;
    }

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

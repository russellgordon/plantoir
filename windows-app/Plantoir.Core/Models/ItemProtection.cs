using System;
using System.Collections.Generic;
using System.Linq;

namespace Plantoir.Core.Models;

/// <summary>How freely a row in a list editor may be removed.</summary>
public enum ProtectionKind
{
    /// <summary>Nothing depends on it: the minus button removes it.</summary>
    Ordinary,
    /// <summary>Something depends on it: ask first, then do as asked.</summary>
    Consequential,
    /// <summary>A feature would break: the minus becomes an ⓘ that explains.</summary>
    Blocked,
}

/// <summary>
/// What happens when a teacher presses minus on one row, or unticks one box.
///
/// <para><b>Removal is NEVER silently greyed out</b>, and pressing minus never
/// auto-flips a related switch from inside a dialog. A blocked row swaps its
/// minus for an ⓘ whose flyout says in plain words what depends on the folder
/// and names the switch to turn off first; the teacher then decides. A
/// disabled button with no explanation is the version of this that gets
/// reported as "the app is broken".</para>
///
/// <para>A class rather than a Swift-style enum with payloads, which C# has
/// no equivalent of. The payload is the sentence, and there is exactly one
/// per case.</para>
/// </summary>
public sealed record ItemProtection
{
    public ProtectionKind Kind { get; private init; }

    /// <summary>The confirmation's title. Empty unless Consequential.</summary>
    public string Title { get; private init; } = "";

    /// <summary>The confirmation's body. Empty unless Consequential.</summary>
    public string Message { get; private init; } = "";

    /// <summary>What the ⓘ explains. Empty unless Blocked.</summary>
    public string Reason { get; private init; } = "";

    public static readonly ItemProtection Ordinary = new() { Kind = ProtectionKind.Ordinary };

    public static ItemProtection Consequential(string title, string message) =>
        new() { Kind = ProtectionKind.Consequential, Title = title, Message = message };

    public static ItemProtection Blocked(string reason) =>
        new() { Kind = ProtectionKind.Blocked, Reason = reason };

    public bool IsBlocked => Kind == ProtectionKind.Blocked;
    public bool AsksFirst => Kind == ProtectionKind.Consequential;
}

/// <summary>Which list a row belongs to — the rules differ per list.</summary>
public enum ItemList
{
    SharedFolders,
    SharedFiles,
    PerSectionFolders,
    PerSectionFiles,
    /// <summary>The Marks checklist, where the "row" is a tick rather than a minus.</summary>
    GradedFolders,
}

/// <summary>
/// Everything the protection rules need to know, gathered once so the rules
/// themselves stay a pure function of it.
///
/// <para><paramref name="InWizard"/> chooses between two nearly identical sets
/// of sentences. They differ only in which switch they name, because the New
/// Course wizard and Course Settings call the same setting different things —
/// and a sentence naming a switch the teacher cannot see is worse than no
/// sentence.</para>
///
/// <para><paramref name="CurriculumCoverageEnabled"/> and
/// <paramref name="CurriculumPagesEnabled"/> are EFFECTIVE values, not raw
/// switch positions. In the wizard a parent switch being off leaves its
/// children disabled but still reading true, and blocking on a disabled
/// switch is a deadlock: the teacher is told to turn off a control they
/// cannot reach.</para>
/// </summary>
public sealed record ProtectionContext(
    bool InWizard,
    bool CurriculumCoverageEnabled,
    bool CurriculumPagesEnabled,
    string Jurisdiction,
    string? ResolvedCurriculumFolder,
    IReadOnlyList<string> GradedFolders,
    IReadOnlyList<string> PerSectionFolders,
    /// <summary>
    /// The folder this course actually uses for class pages — the recorded
    /// <c>class_folder</c> where there is one, otherwise the guess. Optional
    /// so every existing caller keeps its behaviour.
    /// </summary>
    string? ResolvedClassFolder = null);

/// <summary>
/// The protection rules themselves: given a name, which list it is in, and
/// the course's state, what happens when the teacher tries to remove it.
///
/// <para>Pinned by <c>contracts/shared-rules.json</c> -> <c>specialNames</c>
/// and by <c>ItemProtectionTests</c>.</para>
/// </summary>
public static class ItemProtectionRule
{
    /// <summary>The one per-section folder that can never go.</summary>
    public const string SectionIndexFileName = "index.md";

    public static ItemProtection For(string name, ItemList list, ProtectionContext context)
    {
        if (string.IsNullOrEmpty(name)) return ItemProtection.Ordinary;

        switch (list)
        {
            case ItemList.PerSectionFiles:
                // A section with no index.md cannot be published at all. The
                // GUI half of a defect the build already knew about.
                return name.Equals(SectionIndexFileName, StringComparison.OrdinalIgnoreCase)
                    ? ItemProtection.Blocked(SpecialNames.SectionIndexFileBlocked)
                    : ItemProtection.Ordinary;

            case ItemList.PerSectionFolders:
                return PerSectionFolderProtection(name, context);

            case ItemList.SharedFolders:
                return SharedFolderProtection(name, context);

            case ItemList.GradedFolders:
                // Unticking, not removing: only the floor applies.
                return MarksFloorProtection(name, context) ?? ItemProtection.Ordinary;

            default:
                return ItemProtection.Ordinary;
        }
    }

    private static ItemProtection PerSectionFolderProtection(string name, ProtectionContext context)
    {
        // EXACTLY the folder called "All Classes", case-insensitively, and no
        // other. The next-class button and the schedule write pages into it,
        // so a confirmation would be asking the teacher to break both. Every
        // other per-section folder — including other names that mention
        // classes — stays as removable as it ever was.
        // The folder this course actually uses, and the literal "All Classes"
        // for every course that never recorded one. Blocking only the literal
        // was right until `class_folder` existed; now that a course can call
        // its class folder "All Days", blocking only "All Classes" would let a
        // teacher remove the very folder the next-class button and the
        // schedule write into.
        if (name.Equals(ClassFolderRule.FallbackName, StringComparison.OrdinalIgnoreCase)
            || (context.ResolvedClassFolder is { } used
                && name.Equals(used, StringComparison.OrdinalIgnoreCase)))
            return ItemProtection.Blocked(SpecialNames.ClassFolderBlocked);

        // Never `per_section_folders: []`: a section with no folder has
        // nowhere for its lessons to go.
        if (context.PerSectionFolders.Count <= 1)
            return ItemProtection.Blocked(SpecialNames.LastPerSectionFolderBlocked);

        return MarksFloorProtection(name, context)
               ?? GradedFolderConfirmation(name, context)
               ?? ItemProtection.Ordinary;
    }

    private static ItemProtection SharedFolderProtection(string name, ProtectionContext context)
    {
        if (IsTheCurriculumFolder(name, context))
        {
            if (context.InWizard)
            {
                if (context.CurriculumCoverageEnabled)
                    return ItemProtection.Blocked(SpecialNames.CurriculumFolderBlockedByCoverageMap);
                if (context.CurriculumPagesEnabled)
                    return ItemProtection.Blocked(
                        SpecialNames.CurriculumFolderBlockedByCurriculumPages(context.Jurisdiction));
            }
            else if (context.CurriculumCoverageEnabled)
            {
                return ItemProtection.Blocked(SpecialNames.CurriculumFolderBlockedByCoverageSetting);
            }

            // Coverage is off, so nothing breaks today — but the expectations
            // will not be there if it is turned on later, which is worth
            // saying before the folder goes.
            return ItemProtection.Consequential(
                SpecialNames.RemoveCurriculumFolderTitle(name),
                SpecialNames.RemoveCurriculumFolderMessage);
        }

        return MarksFloorProtection(name, context)
               ?? GradedFolderConfirmation(name, context)
               ?? ItemProtection.Ordinary;
    }

    /// <summary>
    /// The marks floor, or null when it does not apply. While the coverage map
    /// is on, the LAST folder counting for marks cannot go: an empty pool
    /// shows every expectation as never evaluated, which looks like a bug in
    /// the map rather than a choice the teacher made.
    /// </summary>
    private static ItemProtection? MarksFloorProtection(string name, ProtectionContext context)
    {
        if (!context.CurriculumCoverageEnabled) return null;
        if (!IsGraded(name, context)) return null;
        if (context.GradedFolders.Count > 1) return null;

        return ItemProtection.Blocked(context.InWizard
            ? SpecialNames.LastGradedFolderBlockedWizard
            : SpecialNames.LastGradedFolderBlocked);
    }

    private static ItemProtection? GradedFolderConfirmation(string name, ProtectionContext context)
    {
        if (!IsGraded(name, context)) return null;
        return ItemProtection.Consequential(
            SpecialNames.RemoveGradedFolderTitle(name),
            SpecialNames.RemoveGradedFolderMessage);
    }

    private static bool IsGraded(string name, ProtectionContext context) =>
        context.GradedFolders.Contains(name, StringComparer.OrdinalIgnoreCase);

    private static bool IsTheCurriculumFolder(string name, ProtectionContext context) =>
        context.ResolvedCurriculumFolder is { } resolved &&
        name.Equals(resolved, StringComparison.Ordinal);
}

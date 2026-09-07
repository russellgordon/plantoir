using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace Plantoir.Core.Models;

/// <summary>
/// Which folders the Marks checklist may OFFER — as opposed to
/// <see cref="GradedFolderRule"/>, which decides which folders COUNT.
///
/// <para><b>The interaction between those two is the bug this exists for.</b>
/// The rule matches a folder segment at ANY depth, and an ABSENT
/// <c>graded_folders</c> key means the teacher has never been asked, so the
/// historical substring rule still applies. A checklist offering only the
/// course's TOP-LEVEL folders therefore hands a teacher a list that is
/// narrower than what the build is already counting — and <b>the first tick
/// freezes it</b>. From that tick onwards, anything the build counted today
/// and the list omitted loses its marks without a word: every expectation
/// that folder addressed reads as never evaluated on the Curriculum Coverage
/// map, permanently, and nothing says so. A teacher who files assessed work
/// in <c>Portfolios/Tasks</c> is exactly that teacher.</para>
///
/// <para>The macOS app has walked the course folder since it added
/// <c>nestedFolderNames</c>; this is that rule, ported. It is deliberately
/// shallow and cheap rather than complete — see <see cref="MaxDepth"/>.</para>
///
/// <para>Pinned by <c>contracts/shared-rules.json</c> -&gt;
/// <c>gradedFolders.choices</c>.</para>
/// </summary>
public static class GradedFolderChoices
{
    /// <summary>
    /// How far below the course folder the walk goes. Immediate children are
    /// level 1, so levels 1 to 4 are offered and level 5 is not.
    ///
    /// <para><b>An affordability judgement, not completeness</b>, and it is
    /// honest about that: a graded folder buried five levels down is still
    /// absent from the list. Four is far more complete than the top-level
    /// lists alone — which is what the case that mattered needed — and it is
    /// what keeps this cheap on a course of a few thousand pages. The number
    /// matches the mac's exactly and must keep matching it: a different cap on
    /// one platform would mean the two apps offer different pools for the same
    /// course, and a teacher's tick would then freeze a different answer
    /// depending on which app they happened to be sitting at.</para>
    /// </summary>
    public const int MaxDepth = 4;

    /// <summary>
    /// Folders that are never offered, and are never walked INTO either.
    ///
    /// <para>Build output, Plantoir's own bookkeeping, and <c>Media</c>.
    /// <c>Media</c> is defensible either way — a teacher who grades video
    /// portfolios might want it — and it stays out because media is not
    /// assessed work in either app today, and differing here would change what
    /// the coverage map says. The two build-output names are skipped on this
    /// platform even though Windows keeps built websites outside the course
    /// folder: a folder left behind from before that move must not turn up in
    /// the list.</para>
    ///
    /// <para>Matched EXACTLY, case included, because the mac matches against a
    /// <c>Set&lt;String&gt;</c>. A teacher's own folder called <c>media</c> is
    /// therefore offered on both platforms.</para>
    /// </summary>
    public static readonly IReadOnlyList<string> SkippedFolders = new[]
    {
        ".merged_output", "merged_output", ".internal", ".obsidian",
        "node_modules", "Media", ".git",
    };

    /// <summary>
    /// Whether a name is one of a course's section folders — <c>section1</c>,
    /// <c>section2</c> and so on.
    ///
    /// <para>A section folder is not somewhere work lives: its CONTENTS are
    /// merged into the site and its own name never appears in a page's path
    /// there, so ticking it would count nothing. Its children are still
    /// walked, because a graded folder inside a section certainly does
    /// count.</para>
    /// </summary>
    public static bool IsSectionFolder(string name)
    {
        const string prefix = "section";
        if (string.IsNullOrEmpty(name) || name.Length <= prefix.Length) return false;
        if (!name.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) return false;
        for (int index = prefix.Length; index < name.Length; index++)
            if (!char.IsAsciiDigit(name[index])) return false;
        return true;
    }

    /// <summary>
    /// The folder names found inside a course, shallowest first and in name
    /// order within each folder.
    ///
    /// <para>Includes the course's own top-level folders: a folder sitting on
    /// disk that is in neither copy list will be added to <c>shared_folders</c>
    /// by the next build's preflight scan and will count for marks from then
    /// on, so offering it is right rather than premature.</para>
    ///
    /// <param name="excludedShared">
    /// <c>excluded_items.shared</c>, and <paramref name="excludedPerSection"/>
    /// is <c>excluded_items.per_section</c>. A name a teacher has REMOVED from
    /// the course is not offered back, and is not walked into. Without this the
    /// removal confirmation's own promise — "Removing it will take it out of
    /// your course's marks pool" — is broken on the very next redraw, because
    /// the folder is still on disk. Matched exactly, case included, the same
    /// way <c>CourseConfiguration.IsExcluded</c> and the build's preflight scan
    /// match. Only the two levels preflight actually discovers are filtered:
    /// the course's own children against the shared scope, and a section
    /// folder's children against the per-section scope.
    /// </param>
    /// </summary>
    public static List<string> NestedFolderNames(
        string? courseDirectory,
        IReadOnlyList<string>? excludedShared = null,
        IReadOnlyList<string>? excludedPerSection = null)
    {
        var found = new List<string>();
        if (string.IsNullOrWhiteSpace(courseDirectory)) return found;
        if (!Directory.Exists(courseDirectory)) return found;

        Walk(courseDirectory, 1, CourseConfiguration.SharedScope, found,
             excludedShared, excludedPerSection);
        return found;
    }

    /// <summary>
    /// Everything the Marks checklist offers: the course's shared folders,
    /// then its per-section folders, then what is on disk — in that order,
    /// de-duplicated by exact name.
    ///
    /// <para>The declared lists come first because they are what a teacher
    /// arranged deliberately; the walked names are the safety net underneath
    /// them.</para>
    /// </summary>
    public static List<string> For(CourseConfiguration config, IReadOnlyList<string> nestedNames)
    {
        ArgumentNullException.ThrowIfNull(config);

        var choices = new List<string>();
        foreach (string name in config.SharedFolders) Offer(choices, name);
        foreach (string name in config.PerSectionFolders) Offer(choices, name);
        foreach (string name in nestedNames ?? Array.Empty<string>()) Offer(choices, name);
        return choices;
    }

    /// <summary>The same, walking the course folder itself.</summary>
    public static List<string> For(CourseConfiguration config, string? courseDirectory)
    {
        ArgumentNullException.ThrowIfNull(config);

        return For(config, NestedFolderNames(
            courseDirectory,
            config.ExcludedItems(CourseConfiguration.SharedScope),
            config.ExcludedItems(CourseConfiguration.PerSectionScope)));
    }

    // ---- The walk --------------------------------------------------------

    private static void Offer(List<string> choices, string name)
    {
        if (string.IsNullOrEmpty(name)) return;
        if (choices.Contains(name, StringComparer.Ordinal)) return;
        choices.Add(name);
    }

    /// <param name="scopeOfChildren">
    /// Which <c>excluded_items</c> scope this directory's children are
    /// discovered into, or null where the build discovers nothing — the shared
    /// scope directly inside the course, the per-section scope directly inside
    /// a section folder, and nothing anywhere deeper.
    /// </param>
    private static void Walk(string directory, int depth, string? scopeOfChildren,
                             List<string> found,
                             IReadOnlyList<string>? excludedShared,
                             IReadOnlyList<string>? excludedPerSection)
    {
        if (depth > MaxDepth) return;

        DirectoryInfo[] children;
        try
        {
            children = new DirectoryInfo(directory).GetDirectories();
        }
        catch (IOException)
        {
            return;             // Unreadable: skip this branch rather than lose the list.
        }
        catch (UnauthorizedAccessException)
        {
            return;
        }

        // Sorted so the list a teacher reads is the same one every time, and
        // so the contract can pin an ORDER at all. Directory enumeration order
        // is the filesystem's business and is not promised by either platform.
        Array.Sort(children, (left, right) =>
            string.Compare(left.Name, right.Name, StringComparison.OrdinalIgnoreCase));

        foreach (DirectoryInfo child in children)
        {
            string name = child.Name;
            if (name.StartsWith('.')) continue;

            FileAttributes attributes;
            try
            {
                attributes = child.Attributes;
            }
            catch (IOException)
            {
                continue;
            }
            if (attributes.HasFlag(FileAttributes.Hidden)) continue;

            // A symlink or junction ONLY — never "any reparse point". With
            // OneDrive's Files On-Demand, which teachers using a synced working
            // folder have on by default, an unmaterialised folder is also a
            // reparse point, and skipping those would have put every synced
            // course straight back to the top-level-only list this class
            // exists to fix. `LinkTarget` is null for a cloud placeholder and
            // non-null for a real link, which is exactly the distinction
            // wanted. (The mac's walker does not follow symlinks either.)
            if (child.LinkTarget is not null) continue;

            if (SkippedFolders.Contains(name, StringComparer.Ordinal)) continue;

            if (scopeOfChildren is { } scope
                && Excluded(scope, name, excludedShared, excludedPerSection)) continue;

            bool isSection = IsSectionFolder(name);
            if (!isSection && !found.Contains(name, StringComparer.Ordinal)) found.Add(name);

            Walk(child.FullName, depth + 1,
                 isSection ? CourseConfiguration.PerSectionScope : null,
                 found, excludedShared, excludedPerSection);
        }
    }

    private static bool Excluded(string scope, string name,
                                 IReadOnlyList<string>? excludedShared,
                                 IReadOnlyList<string>? excludedPerSection)
    {
        var list = scope == CourseConfiguration.PerSectionScope ? excludedPerSection : excludedShared;
        return list is not null && list.Contains(name, StringComparer.Ordinal);
    }
}

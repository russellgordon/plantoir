using System;
using System.Collections.Generic;
using System.Linq;

namespace Plantoir.Core.Models;

/// <summary>
/// Which folders hold work that COUNTS FOR MARKS.
///
/// <para>An expectation is "assessed" — the ring on a cell in the Curriculum
/// Coverage map, and Ontario's requirement that every overall expectation be
/// evaluated at least once — when a page addressing it lives in one of these.
/// It used to be hardcoded: any folder whose name CONTAINED "task". A teacher
/// who called theirs "Tests", or renamed "Tasks", silently lost every assessed
/// mark on the map with nothing said.</para>
///
/// <para><b>Absent is not empty, and conflating the two breaks courses both
/// ways.</b> An ABSENT <c>graded_folders</c> key means the teacher has never
/// been asked, so the historical substring rule still applies. An EMPTY list
/// means they were asked and cleared it, which is a real answer and is
/// honoured. The exact-name rule is NARROWER than the substring one —
/// <c>support/skeletons</c> ships a family whose folder is "Thinking Tasks",
/// which the old rule counted and a pool of ["Tasks"] does not — so seeding
/// every existing course with ["Tasks"] would have quietly taken the assessed
/// marks off that course's map.</para>
///
/// <para>Pinned by <c>contracts/shared-rules.json</c> -> <c>gradedFolders</c>,
/// whose cases the macOS suite, <c>scripts/test_graded_folders.py</c> and
/// <c>GradedFolderContractTests</c> all run against their own
/// implementations.</para>
/// </summary>
public static class GradedFolderRule
{
    /// <summary>
    /// The substring a folder's name must contain for a course that has never
    /// been asked which folders count.
    /// </summary>
    public const string HistoricalSubstring = "task";

    /// <summary>
    /// Whether a page counts for marks.
    ///
    /// <param name="pooledNames">
    /// The course's <c>graded_folders</c>, or <b>null</b> when the key is
    /// absent — which is not the same as an empty list.
    /// </param>
    /// <param name="relativePath">
    /// The page's path RELATIVE to the content root. Either separator.
    /// </param>
    /// </summary>
    public static bool CountsForMarks(IReadOnlyList<string>? pooledNames, string relativePath)
    {
        if (string.IsNullOrWhiteSpace(relativePath)) return false;

        var segments = relativePath.Split(new[] { '/', '\\' }, StringSplitOptions.RemoveEmptyEntries);
        // The last segment is the FILE NAME, and a page is not assessed work
        // on account of what it is called. Folder segments only, at any depth,
        // so a teacher who files by unit inside Tasks does not lose credit.
        if (segments.Length < 2) return false;
        var folders = segments[..^1];

        if (pooledNames is null)
            return folders.Any(f => f.Contains(HistoricalSubstring, StringComparison.OrdinalIgnoreCase));

        var pool = new HashSet<string>(
            pooledNames.Where(n => !string.IsNullOrEmpty(n)),
            StringComparer.OrdinalIgnoreCase);
        return folders.Any(pool.Contains);
    }

    /// <summary>
    /// The pool a course that has never been asked is ALREADY working to,
    /// read off the folders it actually has.
    ///
    /// <para>Used to materialise a <c>null</c> pool the first time a teacher
    /// edits it, so their first tick does not silently narrow the course from
    /// the substring rule to whatever one box they touched. Mirrors the
    /// fallback branch of <c>setup_course.py:graded_folders_for</c>.</para>
    /// </summary>
    public static List<string> InferredPool(IEnumerable<string>? folderNames)
    {
        var found = new List<string>();
        foreach (string name in folderNames ?? Enumerable.Empty<string>())
        {
            if (string.IsNullOrEmpty(name)) continue;
            if (!name.Contains(HistoricalSubstring, StringComparison.OrdinalIgnoreCase)) continue;
            if (found.Contains(name, StringComparer.Ordinal)) continue;
            found.Add(name);
        }
        return found;
    }

    /// <summary>
    /// A declared pool narrowed to the folders the course actually ends up
    /// with, keeping the course's own capitalisation.
    ///
    /// <para>The wizard's half of <c>setup_course.py:graded_folders_for</c>: a
    /// name the teacher removed while setting the course up is dropped rather
    /// than written into a pool that matches nothing on disk.</para>
    /// </summary>
    public static List<string> Reconciled(IEnumerable<string>? declared, IEnumerable<string>? actualFolders)
    {
        var actual = (actualFolders ?? Enumerable.Empty<string>())
            .Where(n => !string.IsNullOrEmpty(n)).ToList();
        var byLowerName = new Dictionary<string, string>(StringComparer.Ordinal);
        // LAST wins, not first: setup_course.py builds this with a dict
        // comprehension (`{name.lower(): name for name in actual_list}`),
        // where a later key overwrites an earlier one. TryAdd would keep the
        // FIRST and disagree with the build for a course holding both
        // "Tasks" and "tasks".
        foreach (string name in actual)
            byLowerName[name.ToLowerInvariant()] = name;

        var reconciled = new List<string>();
        foreach (string name in declared ?? Enumerable.Empty<string>())
        {
            if (string.IsNullOrEmpty(name)) continue;
            string? target = actual.Contains(name, StringComparer.Ordinal)
                ? name
                : byLowerName.TryGetValue(name.ToLowerInvariant(), out var matched) ? matched : null;
            if (target is not null && !reconciled.Contains(target, StringComparer.Ordinal))
                reconciled.Add(target);
        }
        return reconciled;
    }
}

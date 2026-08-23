using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace Plantoir.Core.Models;

/// <summary>
/// Which folder holds a section's class pages, and whether a given page is one
/// of them.
///
/// <para><b>One rule, because there were four and they disagreed.</b> This app
/// tested the whole directory STRING for "class"; the mac's assistant sniffed a
/// page's immediate parent; the mac's <c>ClassPages</c> asked the course's
/// configured folder list; and <c>build_site.py</c> matched the exact strings
/// "all classes" and "classes" against every path segment INCLUDING the file
/// name. A teacher whose folder was called anything else got a different answer
/// from each — and the build's answer silently changed the Curriculum Coverage
/// map from "pages the course teaches" to "every published page", which is a
/// wrong map that reports success.</para>
///
/// <para>Pinned by <c>contracts/class-planning.json</c> → <c>classFolder</c>,
/// which the macOS suite and <c>scripts/test_class_folder.py</c> run against
/// their own implementations of the same rule. Named ...Rule rather than
/// ClassFolder because <c>AssistWorkspace</c> already has a private method by
/// that name which returns a PATH, and two things called ClassFolder that
/// return different kinds of answer is how the next bug gets written.</para>
/// </summary>
public static class ClassFolderRule
{
    /// <summary>
    /// The name used when a course has no per-section folders configured at
    /// all, so a section still has a predictable answer rather than an empty
    /// path.
    /// </summary>
    public const string FallbackName = "All Classes";

    /// <summary>
    /// The class folder's name, read from the course's own configured
    /// per-section folders rather than guessed from what is on disk.
    ///
    /// <para>Substring matching is safe HERE because the list is a short
    /// curated one the teacher chose. It is NOT safe against arbitrary paths,
    /// which is what <see cref="IsClassPage"/> is careful about.</para>
    /// </summary>
    public static string Name(IEnumerable<string>? perSectionFolders)
    {
        // A null ELEMENT is reachable: these lists come from JSON, including
        // the contract's own case data. Swift and Python coerce; unguarded
        // LINQ would throw a NullReferenceException here instead.
        var folders = (perSectionFolders ?? Enumerable.Empty<string>())
            .Where(f => !string.IsNullOrEmpty(f)).ToList();
        return folders.FirstOrDefault(f => f.Contains("class", StringComparison.OrdinalIgnoreCase))
               ?? folders.FirstOrDefault()
               ?? FallbackName;
    }

    /// <summary>
    /// WHICH FOLDERS COUNT as holding class pages — every configured
    /// per-section folder whose name mentions classes, and failing that the
    /// single name <see cref="Name"/> chose.
    ///
    /// <para>Naming and membership are the same question only when a course has
    /// ONE such folder. A course configured ["Class Resources", "All Classes"]
    /// would otherwise resolve to "Class Resources" for both, match zero pages,
    /// and drop the coverage map back to "every published page" —
    /// reintroducing the exact silent failure this rule was written to close.
    /// Writing goes to one folder; counting looks at all of them.</para>
    /// </summary>
    public static IReadOnlyList<string> Names(IEnumerable<string>? perSectionFolders)
    {
        var folders = (perSectionFolders ?? Enumerable.Empty<string>())
            .Where(f => !string.IsNullOrEmpty(f)).ToList();
        var mentioningClasses = folders
            .Where(f => f.Contains("class", StringComparison.OrdinalIgnoreCase)).ToList();
        return mentioningClasses.Count > 0
            ? mentioningClasses
            : new List<string> { Name(folders) };
    }

    /// <summary>
    /// Whether a page is one of the section's class pages, given its path
    /// RELATIVE to the content root (or the working folder). Either separator.
    ///
    /// <para>Two things this is deliberately careful about, both real bugs:</para>
    /// <list type="bullet">
    /// <item><description><b>Folder segments only, never the file name.</b>
    /// Defence in depth, NOT a bug that was observed — an earlier draft of this
    /// comment claimed the build had been counting pages such as
    /// "How This Class Works.md" by name, and that was wrong: the old rule was
    /// equality too, so it never fired. Under segment EQUALITY a file name
    /// cannot collide with a folder name, and this exclusion changes no answer
    /// today. It is kept so a future move to prefix or substring matching
    /// cannot silently start counting a page for what it is
    /// CALLED.</description></item>
    /// <item><description><b>Relative, never absolute.</b> This app tested the
    /// whole directory string, so a teacher whose working folder was
    /// <c>C:\Users\x\Classroom\</c> made every page in every course a class
    /// page. Where a teacher keeps their files is not a fact about their
    /// lessons.</description></item>
    /// </list>
    /// </summary>
    public static bool IsClassPage(string relativePath, IEnumerable<string> classFolders)
    {
        if (string.IsNullOrWhiteSpace(relativePath)) return false;

        var segments = relativePath.Split(new[] { '/', '\\' }, StringSplitOptions.RemoveEmptyEntries);
        if (segments.Length == 0) return false;

        // The last segment is the file name — already split, so no path
        // handling is needed or wanted here.
        if (segments[^1].Equals("index.md", StringComparison.OrdinalIgnoreCase))
            return false;

        var wanted = new HashSet<string>(
            (classFolders ?? Enumerable.Empty<string>()).Where(f => !string.IsNullOrEmpty(f)),
            StringComparer.OrdinalIgnoreCase);

        for (int i = 0; i < segments.Length - 1; i++)
        {
            if (wanted.Contains(segments[i])) return true;
        }
        return false;
    }
}

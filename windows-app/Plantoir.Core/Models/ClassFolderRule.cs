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
        var folders = perSectionFolders?.ToList() ?? new List<string>();
        return folders.FirstOrDefault(f => f.Contains("class", StringComparison.OrdinalIgnoreCase))
               ?? folders.FirstOrDefault()
               ?? FallbackName;
    }

    /// <summary>
    /// Whether a page is one of the section's class pages, given its path
    /// RELATIVE to the content root (or the working folder). Either separator.
    ///
    /// <para>Two things this is deliberately careful about, both real bugs:</para>
    /// <list type="bullet">
    /// <item><description><b>Folder segments only, never the file name.</b> The
    /// build's rule ran over every segment including the file name, so
    /// "How This Class Works.md" — which ships in about twenty payloads — and
    /// ADA1O's curriculum page "B3. Connections Beyond the Classroom.md"
    /// counted as lessons, inflating what the course was judged to
    /// teach.</description></item>
    /// <item><description><b>Relative, never absolute.</b> This app tested the
    /// whole directory string, so a teacher whose working folder was
    /// <c>C:\Users\x\Classroom\</c> made every page in every course a class
    /// page. Where a teacher keeps their files is not a fact about their
    /// lessons.</description></item>
    /// </list>
    /// </summary>
    public static bool IsClassPage(string relativePath, string classFolder)
    {
        if (string.IsNullOrWhiteSpace(relativePath)) return false;

        var segments = relativePath.Split(new[] { '/', '\\' }, StringSplitOptions.RemoveEmptyEntries);
        if (segments.Length == 0) return false;

        if (Path.GetFileName(segments[^1]).Equals("index.md", StringComparison.OrdinalIgnoreCase))
            return false;

        for (int i = 0; i < segments.Length - 1; i++)
        {
            if (segments[i].Equals(classFolder, StringComparison.OrdinalIgnoreCase))
                return true;
        }
        return false;
    }
}

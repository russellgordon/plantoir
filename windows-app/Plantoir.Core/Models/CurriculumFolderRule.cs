using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Newtonsoft.Json.Linq;

namespace Plantoir.Core.Models;

/// <summary>
/// Which curriculum folders a course has — for the build's coverage maps and
/// for what the app protects and names (<c>shared-rules.json</c> →
/// <c>specialNames.curriculumFoldersResolution</c>; GitHub issue #345, the
/// mac's #128). Plural since #345: a course with an Ontario and a College
/// Board folder has a map for each folder it DECLARES that holds an
/// expectation page.
/// </summary>
/// <remarks>
/// <para><b>Declared names first</b> — <c>curriculum_folders</c> in order,
/// then the legacy <c>curriculum_folder</c> — and only when none of them holds
/// a page, the ONE folder the old scan finds: alphabetically first among the
/// names mentioning "curriculum" that holds a LETTER-FIRST page (<c>A1.1</c>,
/// the only shape before #128), and only then the first holding any code. That
/// preference is the trap the mac's first draft fell into: the LCS course of
/// #90 keeps <c>1.A</c> skill pages in "College Board Curriculum", which sorts
/// first, and would have taken Ontario's map. Not additive: an archived copy
/// of a curriculum folder must not grow a map of its own.</para>
///
/// <para><b>Decided from the DISK</b>: which shared folders hold an
/// expectation page, recursively (<see cref="FoldersWithPages"/>), the same
/// thing the build reads. The wizard, which has no disk yet, counts the
/// payload's declared folder while its pages are being installed.</para>
/// </remarks>
public static class CurriculumFolderRule
{
    private const string Marker = "curriculum";

    /// <summary>What the build maps, what the apps protect and name, and the maps' titles.</summary>
    public sealed record Resolution(IReadOnlyList<string> Mapped, IReadOnlyList<string> Resolved, IReadOnlyList<string> Titles);

    /// <summary>
    /// The names a course declares, in order: <c>curriculum_folders</c>, then
    /// the legacy <c>curriculum_folder</c> when it is not already there. Null,
    /// empty, non-string and path-like entries are dropped; repeats are
    /// compared ignoring letter case.
    /// </summary>
    public static List<string> Declared(JToken? list, JToken? legacy)
    {
        var names = new List<string>();
        void Take(JToken? token)
        {
            if (token is not JValue { Type: JTokenType.String } value) return;
            string name = (string)value!;
            if (name.Length == 0 || name.Contains('/') || name.Contains('\\') || name == "." || name == "..") return;
            if (names.Contains(name, StringComparer.OrdinalIgnoreCase)) return;
            names.Add(name);
        }
        if (list is JArray array) foreach (var entry in array) Take(entry);
        Take(legacy);
        return names;
    }

    public static Resolution Resolve(
        IReadOnlyList<string> declared,
        IEnumerable<string>? sharedFolders,
        IEnumerable<string>? withPages,
        IEnumerable<string>? withLetterFirstPages = null)
    {
        var folders = (sharedFolders ?? Enumerable.Empty<string>()).Where(f => !string.IsNullOrEmpty(f)).ToList();
        var pages = (withPages ?? Enumerable.Empty<string>()).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var letterFirst = (withLetterFirstPages ?? pages).ToHashSet(StringComparer.OrdinalIgnoreCase);

        // A declared name, in the LIST's spelling, when the course has it.
        string? Have(string name) => folders.FirstOrDefault(f => string.Equals(f, name, StringComparison.OrdinalIgnoreCase));
        var declaredHere = declared.Select(Have).Where(f => f is not null).Select(f => f!)
            .Distinct(StringComparer.OrdinalIgnoreCase).ToList();

        var mapped = declaredHere.Where(pages.Contains).ToList();
        bool aDeclaredFolderHasPages = mapped.Count > 0;
        if (!aDeclaredFolderHasPages)
        {
            var named = folders.Where(f => f.Contains(Marker, StringComparison.OrdinalIgnoreCase))
                .OrderBy(f => f, StringComparer.Ordinal).ToList();
            string? scan = named.FirstOrDefault(letterFirst.Contains) ?? named.FirstOrDefault(pages.Contains);
            if (scan is not null) mapped.Add(scan);
        }

        string? byName = declaredHere.FirstOrDefault()
                         ?? folders.Where(f => f.Contains(Marker, StringComparison.OrdinalIgnoreCase))
                             .OrderBy(f => f, StringComparer.Ordinal).FirstOrDefault();
        var resolved = mapped.Count > 0
            ? mapped.ToList()
            : byName is not null ? new List<string> { byName } : new List<string>();

        string? primary = aDeclaredFolderHasPages ? declared.FirstOrDefault() : mapped.FirstOrDefault();
        return new Resolution(mapped, resolved, CurriculumRules.CoveragePageTitles(mapped, primary));
    }

    /// <summary>
    /// The single folder the old rule gives, for a caller with no disk to
    /// read: the configured name when the course has it, else the
    /// alphabetically first name mentioning the curriculum.
    /// </summary>
    public static string? Resolve(string? configuredName, IEnumerable<string>? sharedFolders) =>
        Resolve(configuredName is null ? Array.Empty<string>() : new[] { configuredName }, sharedFolders, null)
            .Resolved.FirstOrDefault();

    /// <summary>
    /// The course's SHARED folders that hold an expectation page anywhere
    /// inside them, and those holding a letter-first one (<c>A1.1</c>).
    /// </summary>
    public static (IReadOnlySet<string> WithPages, IReadOnlySet<string> WithLetterFirstPages) FoldersWithPages(
        string? courseDirectory, IEnumerable<string>? sharedFolders)
    {
        var withPages = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var letterFirst = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (string.IsNullOrEmpty(courseDirectory)) return (withPages, letterFirst);
        foreach (string folder in sharedFolders ?? Enumerable.Empty<string>())
        {
            if (string.IsNullOrEmpty(folder)) continue;
            string path = Path.Combine(courseDirectory, folder);
            if (!Directory.Exists(path)) continue;
            List<string> files;
            try { files = Directory.EnumerateFiles(path, "*.md", SearchOption.AllDirectories).ToList(); }
            catch (IOException) { continue; }
            catch (UnauthorizedAccessException) { continue; }
            foreach (string file in files)
            {
                string stem = Path.GetFileNameWithoutExtension(file);
                if (!CurriculumRules.IsExpectationCode(stem)) continue;
                withPages.Add(folder);
                if (CurriculumRules.IsLetterFirstCode(stem)) { letterFirst.Add(folder); break; }
            }
        }
        return (withPages, letterFirst);
    }

    /// <summary>The course's resolution, from its configuration and the disk.</summary>
    public static Resolution ForCourse(CourseConfiguration config, string? courseDirectory)
    {
        var (withPages, letterFirst) = FoldersWithPages(courseDirectory, config.SharedFolders);
        return Resolve(config.CurriculumFolders, config.SharedFolders, withPages, letterFirst);
    }
}

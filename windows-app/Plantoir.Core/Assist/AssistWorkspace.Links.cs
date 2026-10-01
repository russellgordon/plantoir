using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// "What does &lt;page&gt; link to?", answered from the section's own files
/// (#305 / mac #167; <c>assist-cases.json</c> → <c>linksQuestion.answering</c>).
/// </summary>
public sealed partial class AssistWorkspace
{
    /// <summary>
    /// The answer to a links question, or null when <paramref name="onlyIfFound"/>
    /// and no page is called that — then the question goes to the model.
    /// </summary>
    /// <remarks>
    /// <para>Every link on the page once, in the order the page has them, each
    /// by the name a teacher sees for the page it reaches; a page students
    /// cannot see is marked <c>linkedPageIsADraft</c>; a link that LEADS
    /// NOWHERE is shown as written and marked <c>linkedPageIsMissing</c>.</para>
    ///
    /// <para><b>Leads nowhere is decided by what is on DISK, never by an
    /// extension</b>: "Lab 1.2" is a page and "diagram.png" a picture because
    /// of the files. A target is somewhere when it is a page of this section
    /// by file name (any capitals), a FOLDER whose landing page (index.md) is
    /// in the section, or any FILE of that name in the course folder. A folder
    /// alone is not a file, so <c>[[Unit 3]]</c> naming a folder with no
    /// landing page leads nowhere. A picture or handout that exists is not a
    /// page and is not listed.</para>
    ///
    /// <para>Links inside code are examples (<see cref="MarkdownCode"/>), a
    /// table's escaped pipe is read without its backslash
    /// (<see cref="WikiLinks"/>), and a link to the page itself is not
    /// listed. Measured on the mac across 39 payloads: with code left in, 188
    /// targets read as dead; with the table backslash left on, 69 did.</para>
    /// </remarks>
    public string? LinksAnswer(string courseCode, int sectionNumber, string page, string? asTyped, bool onlyIfFound)
    {
        var course = Course(courseCode);
        int section = Section(course, sectionNumber);
        var pages = PagePaths.MarkdownPages(course.DirectoryPath, section)
            .Where(path => ListsAsAPage(course, path))
            .Select(Path.GetFullPath)
            .ToList();
        var titles = pages.ToDictionary(path => path, path => TitleOf(path), StringComparer.OrdinalIgnoreCase);

        // The page asked about: by file name, then by the name the sidebar
        // shows (a landing page by its folder's name too). "the X page" tries
        // X first and then, only when that finds nothing, the phrase as typed
        // without "the", without "page", and whole.
        var readings = new List<string> { page };
        if (asTyped is { } typed)
        {
            string t = typed.Trim();
            if (t.StartsWith("the ", StringComparison.OrdinalIgnoreCase)) readings.Add(t[4..].Trim());
            if (t.EndsWith(" page", StringComparison.OrdinalIgnoreCase)) readings.Add(t[..^5].Trim());
            readings.Add(t);
        }

        List<string> found = new();
        foreach (string reading in readings)
        {
            found = Lookup(reading, pages, titles);
            if (found.Count > 0) break;
        }

        if (found.Count == 0)
        {
            if (onlyIfFound) return null;
            return AssistWording.NoPageCalled(course.Code, section.ToString(), page);
        }
        if (found.Count > 1)
        {
            return AssistWording.MorePagesThanOneAreCalled(course.Code, section.ToString(), page) + "\n" +
                   string.Join("\n", found.Select(path => "• " + Relative(path)));
        }

        string chosen = found[0];
        string shownAsked = titles[chosen];
        string text;
        try { text = File.ReadAllText(chosen); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return AssistWording.PageCouldNotBeRead(shownAsked);
        }

        var byFileName = pages.GroupBy(path => Path.GetFileNameWithoutExtension(path), StringComparer.OrdinalIgnoreCase)
                              .ToDictionary(group => group.Key, group => group.First(), StringComparer.OrdinalIgnoreCase);
        var landingByFolder = pages.Where(path => Path.GetFileName(path).Equals("index.md", StringComparison.OrdinalIgnoreCase))
                                   .GroupBy(path => Path.GetFileName(Path.GetDirectoryName(path)) ?? "", StringComparer.OrdinalIgnoreCase)
                                   .ToDictionary(group => group.Key, group => group.First(), StringComparer.OrdinalIgnoreCase);
        var filesByName = Directory.EnumerateFiles(course.DirectoryPath, "*", SearchOption.AllDirectories)
            .GroupBy(path => Path.GetFileName(path), StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => group.First(), StringComparer.OrdinalIgnoreCase);

        var listed = new List<string>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var link in WikiLinks.PageLinks(text))
        {
            string written = link.Target.Trim();
            string name = written.Replace('\\', '/').Split('/')[^1];
            string bare = name.EndsWith(".md", StringComparison.OrdinalIgnoreCase) ? name[..^3] : name;

            string? reached = byFileName.TryGetValue(bare, out var asPage) ? asPage
                            : landingByFolder.TryGetValue(bare, out var landing) ? landing
                            : null;
            if (reached is not null)
            {
                if (string.Equals(reached, chosen, StringComparison.OrdinalIgnoreCase)) continue;   // itself
                if (!seen.Add(reached)) continue;
                bool hidden = PageFrontmatter.Visibility(SafeRead(reached), section) == PageVisibility.Hidden;
                listed.Add("• " + titles[reached] + (hidden ? " — " + AssistWording.LinkedPageIsADraft : ""));
                continue;
            }
            // A file of that name somewhere in the course: a picture or a
            // handout that exists is not a page and is not listed.
            if (filesByName.ContainsKey(name) || filesByName.ContainsKey(bare)) continue;
            if (!seen.Add("missing:" + written)) continue;
            listed.Add("• " + written + " — " + AssistWording.LinkedPageIsMissing);
        }

        return listed.Count == 0
            ? AssistWording.PageLinksToNothing(shownAsked)
            : AssistWording.PageLinksTo(shownAsked) + "\n" + string.Join("\n", listed);
    }

    private static string SafeRead(string path)
    {
        try { return File.ReadAllText(path); } catch { return ""; }
    }

    private static string TitleOf(string path) => PagePaths.DisplayTitle(path, SafeRead(path));

    private static List<string> Lookup(string reading, List<string> pages, Dictionary<string, string> titles)
    {
        string wanted = reading.Trim();
        if (wanted.EndsWith(".md", StringComparison.OrdinalIgnoreCase)) wanted = wanted[..^3];
        var byFile = pages.Where(path => Path.GetFileNameWithoutExtension(path).Equals(wanted, StringComparison.OrdinalIgnoreCase)
                                         && !Path.GetFileName(path).Equals("index.md", StringComparison.OrdinalIgnoreCase))
                          .ToList();
        if (byFile.Count > 0) return byFile;
        var byFolder = pages.Where(path => Path.GetFileName(path).Equals("index.md", StringComparison.OrdinalIgnoreCase) &&
                                           (Path.GetFileName(Path.GetDirectoryName(path)) ?? "").Equals(wanted, StringComparison.OrdinalIgnoreCase))
                            .ToList();
        if (byFolder.Count > 0) return byFolder;
        return pages.Where(path => titles[path].Equals(wanted, StringComparison.OrdinalIgnoreCase)).ToList();
    }
}

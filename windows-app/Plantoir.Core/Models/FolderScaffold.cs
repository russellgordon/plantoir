using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

namespace Plantoir.Core.Models;

/// <summary>
/// The two pages a folder added in Course Settings starts with: its
/// <c>index.md</c>, so the site's sidebar shows it, and a
/// <c>_DUPLICATE ME.md</c>, so a teacher has a page to copy (GitHub #580, the
/// mac's #506 and its <c>FolderScaffold.swift</c>).
/// </summary>
/// <remarks>
/// <para>A folder made with the course gets both from <c>setup_course.py</c>.
/// A folder added AFTERWARDS is made by the app itself — nothing runs the
/// course creator for a Settings click — and until #580 it was made empty, so
/// it never appeared in the sidebar although it was not hidden. Every text here
/// is setup's own, word for word; <c>contracts/course-management.json</c> →
/// <c>foldersAddedLater</c> carries the cases, computed with setup's own
/// functions, and both apps compare them as bytes.</para>
///
/// <para>The page to duplicate is the generic skeleton's template, whatever the
/// course was made from: all the skeleton templates are one file, and a
/// SIBLING folder's copy was rejected as the source because it may be a
/// teacher's edited page with stale dates.</para>
/// </remarks>
public static class FolderScaffold
{
    /// <summary>One page to write, by its path inside the course folder (always <c>/</c>-separated).</summary>
    public sealed record Page(string RelativePath, string Text);

    /// <summary>What a folder added later was given, for the trail.</summary>
    public sealed record Outcome(int FoldersCreated = 0, int IndexPagesWritten = 0, int TemplatesWritten = 0);

    public const string TemplateFileName = "_DUPLICATE ME.md";

    /// <summary>The template's path inside the bundled <c>support</c> folder — <c>foldersAddedLater.templateSource</c>.</summary>
    public static readonly string[] TemplatePathInSupport = { "skeletons", "general", "shared", "Concepts", TemplateFileName };

    /// <summary>setup's <c>EXAMPLE_CONTENT_CREATED_SENTINEL</c>.</summary>
    public const string CreatedSentinel = "__CREATED__";

    /// <summary>The placeholder expectation the template's "Curriculum connection" embeds.</summary>
    public const string PlaceholderExpectation = "A1.1";

    public const string CurriculumBlockStart = "%%curriculum-start%%";
    public const string CurriculumBlockEnd = "%%curriculum-end%%";

    private static readonly UTF8Encoding Utf8NoBom = new(encoderShouldEmitUTF8Identifier: false);

    // ---- The pages --------------------------------------------------------------

    /// <summary>
    /// Every page a folder added later starts with: for a shared folder its
    /// <c>index.md</c> and template; for a per-section folder the same two in
    /// each section, in section order. <paramref name="curriculumPageNames"/>
    /// are the file names at the top of the course's primary curriculum folder,
    /// or null when it has none; a null <paramref name="template"/> leaves the
    /// template out.
    /// </summary>
    public static List<Page> Pages(string name, FolderScope scope, IReadOnlyList<int> sectionNumbers,
                                   IReadOnlyList<string>? curriculumPageNames, string created, string? template)
    {
        var stems = SpecificExpectationStems(curriculumPageNames ?? Array.Empty<string>());
        var result = new List<Page>();
        if (scope == FolderScope.Shared)
        {
            result.Add(new Page(name + "/index.md", SharedIndexText(name, sectionNumbers, created)));
            if (template is not null)
                result.Add(new Page(name + "/" + TemplateFileName, TemplateText(template, sectionNumbers, stems, created)));
            return result;
        }
        foreach (int number in sectionNumbers)
        {
            string folderPath = $"section{number}/" + name;
            result.Add(new Page(folderPath + "/index.md", SectionIndexText(name, created)));
            if (template is not null)
                result.Add(new Page(folderPath + "/" + TemplateFileName, TemplateText(template, null, stems, created)));
        }
        return result;
    }

    /// <summary>A shared folder's <c>index.md</c>: setup's "Create shared structure" page.</summary>
    public static string SharedIndexText(string name, IReadOnlyList<int> sectionNumbers, string created)
    {
        var text = new StringBuilder("---\n");
        text.Append("title: ").Append(FrontmatterTitle(name)).Append('\n');
        foreach (int number in sectionNumbers)
        {
            text.Append($"createdSection{number}: {created}\n");
            text.Append($"publishForSection{number}: true\n");
        }
        text.Append("---\n");
        text.Append($"This is the **{name}** folder. Add Markdown files to this folder to build out your site. ")
            .Append("Optionally, you can remove this `index.md` file and Quartz will then show only a listing ")
            .Append("of files that exist in this folder instead.\n");
        return text.ToString();
    }

    /// <summary>
    /// A per-section folder's <c>index.md</c>: setup's per-section page. Not
    /// SectionAdder's fallback literal, which ends without a newline — the
    /// contract's bytes carry one.
    /// </summary>
    public static string SectionIndexText(string name, string created) =>
        "---\n" +
        $"title: {FrontmatterTitle(name)}\n" +
        $"created: {created}\n" +
        "publish: true\n" +
        "---\n" +
        $"This is the **{name}** folder. Add Markdown files to this folder to build out your site.\n";

    // ---- The title rule (foldersAddedLater.titleQuoting) ------------------------

    /// <summary>
    /// What follows <c>title: </c> for a folder's or file's name: the name
    /// itself, or — when written plain YAML would not read it back as the name
    /// — the name double-quoted with JSON's escapes. Measured on #506's review:
    /// plain, <c>Unit: One</c>, <c>'Tis the Season</c> and <c>&amp; Friends</c>
    /// gave index pages the build could not read. setup's
    /// <c>frontmatter_title</c> and the mac's <c>FolderScaffold.frontmatterTitle</c>
    /// are the same rule.
    /// </summary>
    public static string FrontmatterTitle(string name)
    {
        if (!TitleNeedsQuoting(name)) return name;
        var quoted = new StringBuilder("\"");
        foreach (char c in name)
        {
            switch (c)
            {
                case '"': quoted.Append("\\\""); break;
                case '\\': quoted.Append("\\\\"); break;
                case '\n': quoted.Append("\\n"); break;
                case '\r': quoted.Append("\\r"); break;
                case '\t': quoted.Append("\\t"); break;
                case '\b': quoted.Append("\\b"); break;
                case '\f': quoted.Append("\\f"); break;
                default:
                    // Only C0 is escaped, as JSON (and the mac) do: DEL is
                    // written raw — a known limit the contract's note records.
                    if (c < 0x20) quoted.Append("\\u").Append(((int)c).ToString("x4"));
                    else quoted.Append(c);
                    break;
            }
        }
        quoted.Append('"');
        return quoted.ToString();
    }

    /// <summary>
    /// setup's <c>title_needs_quoting</c>: empty; a first character that is
    /// neither an ASCII letter nor beyond ASCII; a last that is a space, a tab
    /// or a colon; <c>: </c>, <c> #</c> or a control character (DEL included)
    /// anywhere; or one of YAML 1.1's plain words for true, false and null.
    /// Generous on purpose — a quoted title is still the same title.
    /// </summary>
    public static bool TitleNeedsQuoting(string name)
    {
        if (name.Length == 0) return true;
        char first = name[0];
        bool firstIsAsciiLetter = first is >= 'A' and <= 'Z' or >= 'a' and <= 'z';
        if (!firstIsAsciiLetter && first <= 127) return true;
        char last = name[^1];
        if (last is ' ' or '\t' or ':') return true;
        char previous = '\0';
        foreach (char c in name)
        {
            if (c < 0x20 || c == 0x7F) return true;
            if (previous == ':' && c == ' ') return true;
            if (previous == ' ' && c == '#') return true;
            previous = c;
        }
        return PlainNonTextWords.Contains(name.ToLowerInvariant());
    }

    private static readonly HashSet<string> PlainNonTextWords =
        new(StringComparer.Ordinal) { "true", "false", "yes", "no", "on", "off", "y", "n", "null", "~" };

    // ---- The template -----------------------------------------------------------

    /// <summary>
    /// The template as read from disk, with CRLF turned into LF. A Windows
    /// checkout with <c>core.autocrlf=true</c> — the bundle copies
    /// the whole <c>support</c> folder from it — has the file as CRLF, while the contract's
    /// bytes and every page the mac writes are LF.
    /// </summary>
    public static string TemplateFrom(string text) => text.Replace("\r\n", "\n");

    /// <summary>The template at <paramref name="path"/>, LF, or null when it cannot be read.</summary>
    public static string? ReadTemplate(string? path)
    {
        if (string.IsNullOrEmpty(path)) return null;
        try { return TemplateFrom(File.ReadAllText(path)); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException) { return null; }
    }

    /// <summary>
    /// The template as setup would pour it, in setup's order
    /// (<c>install_file</c>): the date filled in; the embed retargeted at the
    /// first specific expectation when the course has some but no A1.1; the
    /// curriculum markers taken out (and what is between them, when the course
    /// has no expectation); and — in a SHARED folder — the created/publish keys
    /// split per section, held back in every one.
    /// </summary>
    public static string TemplateText(string template, IReadOnlyList<int>? sharedBy,
                                      IReadOnlyList<string> curriculumStems, string created)
    {
        string text = template.Replace(CreatedSentinel, created);
        bool keepsTheConnection = curriculumStems.Count > 0;
        if (keepsTheConnection && !Contains(curriculumStems, PlaceholderExpectation))
            text = text.Replace("[[" + PlaceholderExpectation + "]]", "[[" + curriculumStems[0] + "]]");
        text = RemovingCurriculumMarkers(text, keepsTheConnection);
        if (sharedBy is not null) text = SplittingKeysPerSection(text, sharedBy);
        return text;
    }

    private static bool Contains(IReadOnlyList<string> list, string value)
    {
        foreach (string item in list) if (string.Equals(item, value, StringComparison.Ordinal)) return true;
        return false;
    }

    /// <summary>
    /// The specific expectations among a curriculum folder's file names, in
    /// the order setup reads them: by FULL file name, ordinal, as Python's
    /// <c>sorted(glob("*.md"))</c> does — so <c>B1.10</c> comes before
    /// <c>B1.2</c> — and only the letter-first <c>A1.1</c> shape.
    /// </summary>
    public static List<string> SpecificExpectationStems(IEnumerable<string> fileNames)
    {
        var markdown = new List<string>();
        foreach (string fileName in fileNames)
            if (fileName.EndsWith(".md", StringComparison.Ordinal)) markdown.Add(fileName);
        markdown.Sort(StringComparer.Ordinal);
        var stems = new List<string>();
        foreach (string fileName in markdown)
        {
            string stem = fileName[..^3];
            if (IsSpecificExpectationStem(stem)) stems.Add(stem);
        }
        return stems;
    }

    /// <summary>
    /// <c>^[A-Z][0-9]+\.[0-9]+$</c>, ASCII only — written out rather than as a
    /// .NET regex, whose <c>\d</c> takes every Unicode digit and whose <c>$</c>
    /// matches before a trailing newline.
    /// </summary>
    public static bool IsSpecificExpectationStem(string stem)
    {
        int dot = stem.IndexOf('.');
        if (dot < 0 || stem.IndexOf('.', dot + 1) >= 0) return false;
        if (dot < 2 || stem[0] is < 'A' or > 'Z') return false;
        return AllAsciiDigits(stem, 1, dot) && AllAsciiDigits(stem, dot + 1, stem.Length);
    }

    private static bool AllAsciiDigits(string text, int start, int end)
    {
        if (end <= start) return false;
        for (int i = start; i < end; i++) if (text[i] is < '0' or > '9') return false;
        return true;
    }

    /// <summary>setup's <c>strip_curriculum_blocks</c>: the marker lines always go, and what is between them unless kept.</summary>
    public static string RemovingCurriculumMarkers(string text, bool keepingContent)
    {
        var kept = new List<string>();
        bool inside = false;
        foreach (string line in text.Split('\n'))
        {
            string trimmed = line.Trim();
            if (trimmed == CurriculumBlockStart) { inside = true; continue; }
            if (trimmed == CurriculumBlockEnd) { inside = false; continue; }
            if (inside && !keepingContent) continue;
            kept.Add(line);
        }
        return string.Join("\n", kept);
    }

    /// <summary>
    /// setup's <c>per_section_frontmatter</c> over the template's frontmatter:
    /// the <c>created:</c> and <c>publish:</c> lines are replaced, where the
    /// first of them stood, by one <c>createdSectionN</c> /
    /// <c>publishForSectionN</c> pair per section, values copied as written.
    /// </summary>
    public static string SplittingKeysPerSection(string text, IReadOnlyList<int> sectionNumbers)
    {
        if (sectionNumbers.Count == 0 || !text.StartsWith("---\n", StringComparison.Ordinal)) return text;
        string afterOpening = text[4..];
        int closing = afterOpening.IndexOf("\n---", StringComparison.Ordinal);
        if (closing < 0) return text;
        string head = afterOpening[..closing];
        string rest = afterOpening[closing..];
        string? created = null, publish = null;
        foreach (string line in head.Split('\n'))
        {
            if (line.StartsWith("created:", StringComparison.Ordinal)) created = line["created:".Length..].Trim(' ', '\t');
            else if (line.StartsWith("publish:", StringComparison.Ordinal)) publish = line["publish:".Length..].Trim(' ', '\t');
        }
        if (created is null && publish is null) return text;
        var block = new List<string>();
        foreach (int number in sectionNumbers)
        {
            if (created is not null) block.Add($"createdSection{number}: {created}");
            if (publish is not null) block.Add($"publishForSection{number}: {publish}");
        }
        var lines = new List<string>();
        bool placed = false;
        foreach (string line in head.Split('\n'))
        {
            if (line.StartsWith("created:", StringComparison.Ordinal) || line.StartsWith("publish:", StringComparison.Ordinal))
            {
                if (!placed) { lines.AddRange(block); placed = true; }
                continue;
            }
            lines.Add(line);
        }
        return "---\n" + string.Join("\n", lines) + rest;
    }

    // ---- Planning them as one step ----------------------------------------------

    /// <summary>
    /// Plans every new folder, with its pages, into <paramref name="step"/> as
    /// ONE <c>createTree</c> per tree (#899 W8-13; the mac's
    /// <c>FolderScaffold.planPages</c>, U4a): each tree made at the highest
    /// folder of the new one's path that is not there yet, holding the folders
    /// below it down to the new one and the new one's pages. Pages go only
    /// into the folders in <paramref name="newFolders"/>, the ones this click
    /// makes; the step makes them all or none. UTF-8 without a byte-order
    /// mark, LF, as the mac writes.
    /// </summary>
    internal static Outcome PlanPages(IReadOnlyList<Page> pages, IReadOnlyList<string> newFolders, string courseDirectory,
                                      Plantoir.Core.Undo.UndoActionStep step)
    {
        string course = Path.GetFullPath(courseDirectory);
        var treeOrder = new List<string>();
        var treeFolders = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        var treeFiles = new Dictionary<string, Dictionary<string, byte[]>>(StringComparer.OrdinalIgnoreCase);
        var placeOfNewFolder = new Dictionary<string, (string Root, string Inside)>(StringComparer.OrdinalIgnoreCase);
        foreach (string folder in newFolders)
        {
            string folderPath = RelativeInside(course, folder);
            // The tree's root: the first folder of the path, walking down from
            // the course, that is not there yet.
            string[] parts = folderPath.Split('/');
            string root = parts[0];
            for (int count = 1; count <= parts.Length; count++)
            {
                root = string.Join("/", parts, 0, count);
                if (!Directory.Exists(FullPathOf(course, root))) break;
            }
            if (!treeFolders.ContainsKey(root))
            {
                treeOrder.Add(root);
                treeFolders[root] = new List<string>();
                treeFiles[root] = new Dictionary<string, byte[]>(StringComparer.Ordinal);
            }
            string inside = Plantoir.Core.Undo.UndoOp.PartInside(root, folderPath) ?? "";
            if (inside != "")
            {
                string walked = "";
                foreach (string part in inside.Split('/'))
                {
                    walked = walked == "" ? part : walked + "/" + part;
                    if (!treeFolders[root].Contains(walked)) treeFolders[root].Add(walked);
                }
            }
            placeOfNewFolder[folderPath] = (root, inside);
        }
        int indexPages = 0, templates = 0;
        foreach (var page in pages)
        {
            int slash = page.RelativePath.LastIndexOf('/');
            string pageFolder = slash < 0 ? "" : page.RelativePath[..slash];
            string name = page.RelativePath[(slash + 1)..];
            if (!placeOfNewFolder.TryGetValue(pageFolder, out var place)) continue;
            string pathInTree = place.Inside == "" ? name : place.Inside + "/" + name;
            treeFiles[place.Root][pathInTree] = Utf8NoBom.GetBytes(page.Text);
            if (string.Equals(name, TemplateFileName, StringComparison.Ordinal)) templates++;
            else indexPages++;
        }
        foreach (string root in treeOrder)
            step.MakeTree(FullPathOf(course, root), treeFolders[root], treeFiles[root]);
        return new Outcome(newFolders.Count, indexPages, templates);
    }

    /// <summary>A folder's path inside the course, <c>/</c>-separated, spelled as given.</summary>
    private static string RelativeInside(string courseDirectory, string folder) =>
        Path.GetRelativePath(courseDirectory, Path.GetFullPath(folder)).Replace('\\', '/');

    private static string FullPathOf(string courseDirectory, string relative) =>
        Path.Combine(courseDirectory, relative.Replace('/', Path.DirectorySeparatorChar));

    /// <summary>
    /// The file names at the top of the course's PRIMARY curriculum folder, the
    /// first one <see cref="CurriculumFolderRule"/> resolves (#345, the mac's
    /// #128 and its <c>curriculumPageNames(for:)</c>), or null when it has none
    /// or it is not on disk.
    /// </summary>
    public static List<string>? CurriculumPageNames(CourseConfiguration configuration, string courseDirectory) =>
        TopLevelFileNames(courseDirectory, CurriculumFolderRule.ForCourse(configuration, courseDirectory).Resolved.FirstOrDefault());

    /// <summary>
    /// The file names at the top of <paramref name="folderName"/> inside the
    /// course, or null when there is no such folder (or none was given).
    /// </summary>
    public static List<string>? TopLevelFileNames(string courseDirectory, string? folderName)
    {
        if (string.IsNullOrEmpty(folderName)) return null;
        string folder = Path.Combine(courseDirectory, folderName);
        try
        {
            if (!Directory.Exists(folder)) return null;
            var names = new List<string>();
            foreach (string entry in Directory.EnumerateFileSystemEntries(folder))
                names.Add(Path.GetFileName(entry));
            return names;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { return null; }
    }

    // ---- The trail --------------------------------------------------------------

    /// <summary>
    /// The trail's "folder created" line: which folder, which list, and — since
    /// #580 — the pages Plantoir put inside it, so "where did this page come
    /// from?" has an answer. Only what was actually written is named. The
    /// mac's <c>CourseSettingsView.folderCreatedTrailLine</c>, word for word.
    /// </summary>
    public static string FolderCreatedTrailLine(string name, string courseCode, FolderScope scope, Outcome outcome)
    {
        string line = $"created the folder {name} in {courseCode} ({SpecialFolderRenamer.ConfigurationKey(scope)})";
        if (outcome.IndexPagesWritten > 0 && outcome.TemplatesWritten > 0) line += ", with its index page and a page to duplicate";
        else if (outcome.IndexPagesWritten > 0) line += ", with its index page";
        else if (outcome.TemplatesWritten > 0) line += ", with a page to duplicate";
        return line;
    }
}

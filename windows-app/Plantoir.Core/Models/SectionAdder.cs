using System.Globalization;

namespace Plantoir.Core.Models;

/// <summary>
/// Scaffolds a brand-new section for an existing course, imitating a sibling
/// section where one exists so a page the siblings keep unpublished starts
/// unpublished here too.
/// </summary>
public static class SectionAdder
{
    /// <summary>Teacher-eyes-only pages: created unpublished, never in the site.</summary>
    public static readonly IReadOnlySet<string> UnpublishedFileNames =
        new HashSet<string> { "Private Notes.md", "Scratch Page.md" };

    public sealed class SectionAddException(string message) : Exception(message);

    public static void AddSection(int number, Course course)
    {
        var config = course.Configuration;
        if (config.SectionNumbers.Contains(number))
            throw new SectionAddException($"Section {number} of {course.Code} already exists.");
        string sectionDir = course.SectionDirectory(number);
        if (Directory.Exists(sectionDir))
            throw new SectionAddException(
                $"A folder for section {number} of {course.Code} is already on disk. Move it aside first — it may hold work you want to keep.");

        string created = Timestamp(DateTimeOffset.Now);
        Directory.CreateDirectory(sectionDir);

        string? siblingDir = LowestExistingSiblingSectionDirectory(course);
        if (siblingDir != null)
        {
            ReplicateSiblingSection(siblingDir, sectionDir, course, number, created);
        }

        string indexFile = Path.Combine(sectionDir, "index.md");
        if (!File.Exists(indexFile))
        {
            string indexFrontmatter = ScaffoldFrontmatter(
                SiblingFile("index.md", course),
                newTitle: SectionTitle(course, number),
                fallbackTitle: null, fallbackIsDraft: false, created: created);
            File.WriteAllText(indexFile, $"---\n{indexFrontmatter}\n---");
        }

        foreach (string folder in config.PerSectionFolders)
        {
            string folderPath = Path.Combine(sectionDir, folder);
            Directory.CreateDirectory(folderPath);
            string folderIndex = Path.Combine(folderPath, "index.md");
            if (!File.Exists(folderIndex))
            {
                string fm = ScaffoldFrontmatter(
                    SiblingFile(folder + "/index.md", course),
                    newTitle: null, fallbackTitle: folder, fallbackIsDraft: false, created: created);
                File.WriteAllText(folderIndex,
                    $"---\n{fm}\n---\nThis is the **{folder}** folder. Add Markdown files to this folder to build out your site.");
            }
        }

        foreach (string fileName in config.PerSectionFiles)
        {
            string filePath = Path.Combine(sectionDir, fileName);
            if (!File.Exists(filePath))
            {
                bool isUnpublished = UnpublishedFileNames.Contains(fileName);
                string fm = ScaffoldFrontmatter(
                    SiblingFile(fileName, course),
                    newTitle: null,
                    fallbackTitle: fileName.Replace(".md", ""),
                    fallbackIsDraft: isUnpublished,
                    created: created);
                string note = isUnpublished
                    ? $"This is the per-section file **{fileName}**. It is marked `publish: false`, so it stays out of the built site — a private place for your own notes."
                    : $"This is the per-section file **{fileName}**.";
                File.WriteAllText(filePath, $"---\n{fm}\n---\n{note}");
            }
        }

        ExtendCourseLevelPages(course, number, created);

        // Only after the folder is safely written does the config learn about
        // it — a mid-way failure never leaves settings pointing at nothing.
        var numbers = config.SectionNumbers;
        numbers.Add(number);
        numbers.Sort();
        config.SetSectionNumbers(numbers);
        config.Write(course.ConfigFilePath);
    }

    internal static string? LowestExistingSiblingSectionDirectory(Course course)
    {
        foreach (int n in course.Configuration.SectionNumbers.OrderBy(n => n))
        {
            string candidate = course.SectionDirectory(n);
            if (Directory.Exists(candidate)) return candidate;
        }
        return null;
    }

    private static void ReplicateSiblingSection(string siblingDir, string destinationDir, Course course, int sectionNumber, string created)
    {
        foreach (string dirPath in Directory.GetDirectories(siblingDir, "*", SearchOption.AllDirectories))
        {
            string relative = Path.GetRelativePath(siblingDir, dirPath);
            Directory.CreateDirectory(Path.Combine(destinationDir, relative));
        }

        foreach (string filePath in Directory.GetFiles(siblingDir, "*", SearchOption.AllDirectories))
        {
            string relative = Path.GetRelativePath(siblingDir, filePath);
            string targetPath = Path.Combine(destinationDir, relative);
            string? dir = Path.GetDirectoryName(targetPath);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);

            if (Path.GetExtension(filePath).Equals(".md", StringComparison.OrdinalIgnoreCase))
            {
                ReplicateMarkdownFile(filePath, targetPath, relative, course, sectionNumber, created);
            }
            else
            {
                File.Copy(filePath, targetPath, overwrite: true);
            }
        }
    }

    private static void ReplicateMarkdownFile(string sourcePath, string destinationPath, string relativePath, Course course, int sectionNumber, string created)
    {
        string text;
        try { text = File.ReadAllText(sourcePath); }
        catch
        {
            File.Copy(sourcePath, destinationPath, overwrite: true);
            return;
        }

        var lines = FrontmatterLines(sourcePath);
        if (lines == null)
        {
            File.WriteAllText(destinationPath, text);
            return;
        }

        string normalizedRelative = relativePath.Replace('\\', '/');
        bool isRootIndex = normalizedRelative == "index.md";
        bool isTopLevelPerSectionFile = course.Configuration.PerSectionFiles.Contains(normalizedRelative);

        var newLines = new List<string>();
        foreach (string line in lines)
        {
            if (isRootIndex && line.StartsWith("title:", StringComparison.Ordinal))
            {
                string newTitle = SectionTitle(course, sectionNumber);
                newLines.Add("title: " + newTitle);
            }
            else if ((isRootIndex || isTopLevelPerSectionFile) && line.StartsWith("created:", StringComparison.Ordinal))
            {
                newLines.Add("created: " + created);
            }
            else
            {
                newLines.Add(line);
            }
        }

        int prefixToDrop = ("---\n" + string.Join("\n", lines)).Length;
        string textNormalized = text.Replace("\r\n", "\n");
        string restOfText = textNormalized[prefixToDrop..];
        string rewritten = "---\n" + string.Join("\n", newLines) + restOfText;
        File.WriteAllText(destinationPath, rewritten);
    }

    internal static void ExtendCourseLevelPages(Course course, int sectionNumber, string created)
    {
        var sectionFolderNames = new HashSet<string>(course.Configuration.SectionNumbers.Select(n => $"section{n}"));
        if (!Directory.Exists(course.DirectoryPath)) return;

        foreach (string file in Directory.GetFiles(course.DirectoryPath, "*.md", SearchOption.AllDirectories))
        {
            string relative = Path.GetRelativePath(course.DirectoryPath, file);
            string firstSegment = relative.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)[0];
            if (sectionFolderNames.Contains(firstSegment))
                continue;

            ExtendFrontmatter(file, sectionNumber, created);
        }
    }

    private static void ExtendFrontmatter(string filePath, int sectionNumber, string created)
    {
        string text;
        try { text = File.ReadAllText(filePath); }
        catch { return; }

        var lines = FrontmatterLines(filePath);
        if (lines == null || AlreadyHasKeys(sectionNumber, lines)) return;

        int? lowestSection = null;
        foreach (string line in lines)
        {
            int? num = PerSectionKeyNumber(line);
            if (num.HasValue)
            {
                if (!lowestSection.HasValue || num.Value < lowestSection.Value)
                    lowestSection = num.Value;
            }
        }
        if (!lowestSection.HasValue) return;

        var addition = new List<string> { $"createdSection{sectionNumber}: {created}" };
        string? publish = PublishValue(lowestSection.Value, lines);
        if (publish != null)
            addition.Add($"publishForSection{sectionNumber}: {publish}");

        int lastKeyIndex = -1;
        for (int i = 0; i < lines.Count; i++)
        {
            if (PerSectionKeyNumber(lines[i]) != null)
                lastKeyIndex = i;
        }

        var updated = new List<string>();
        for (int i = 0; i < lines.Count; i++)
        {
            updated.Add(lines[i]);
            if (i == lastKeyIndex)
                updated.AddRange(addition);
        }

        string textNormalized = text.Replace("\r\n", "\n");
        int prefixToDrop = ("---\n" + string.Join("\n", lines)).Length;
        string body = textNormalized[prefixToDrop..];
        string rewritten = "---\n" + string.Join("\n", updated) + body;
        File.WriteAllText(filePath, rewritten);
    }

    private static bool AlreadyHasKeys(int sectionNumber, List<string> lines)
    {
        string[] prefixes = [$"createdSection{sectionNumber}:", $"publishForSection{sectionNumber}:", $"draftSection{sectionNumber}:"];
        return lines.Any(l => prefixes.Any(p => l.StartsWith(p, StringComparison.Ordinal)));
    }

    private static string? PublishValue(int sectionNumber, List<string> lines)
    {
        string pubPrefix = $"publishForSection{sectionNumber}:";
        foreach (string line in lines)
        {
            if (line.StartsWith(pubPrefix, StringComparison.Ordinal))
                return line[pubPrefix.Length..].Trim();
        }
        string draftPrefix = $"draftSection{sectionNumber}:";
        foreach (string line in lines)
        {
            if (line.StartsWith(draftPrefix, StringComparison.Ordinal))
            {
                string val = line[draftPrefix.Length..].Trim().ToLowerInvariant();
                return val == "true" ? "false" : "true";
            }
        }
        return null;
    }

    private static int? PerSectionKeyNumber(string line)
    {
        string[] prefixes = ["createdSection", "publishForSection", "draftSection"];
        foreach (string prefix in prefixes)
        {
            if (line.StartsWith(prefix, StringComparison.Ordinal))
            {
                string rest = line[prefix.Length..];
                int colon = rest.IndexOf(':');
                if (colon > 0 && int.TryParse(rest[..colon], out int num))
                    return num;
            }
        }
        return null;
    }

    /// <summary>The first existing copy among ascending section numbers — deterministic.</summary>
    internal static string? SiblingFile(string relativePath, Course course)
    {
        foreach (int n in course.Configuration.SectionNumbers.OrderBy(n => n))
        {
            string candidate = Path.Combine(course.SectionDirectory(n),
                relativePath.Replace('/', Path.DirectorySeparatorChar));
            if (File.Exists(candidate)) return candidate;
        }
        return null;
    }

    /// <summary>
    /// Lines between an opening "---" (which must be line 1, exactly) and the
    /// closing "---". No closing marker → null.
    /// </summary>
    internal static List<string>? FrontmatterLines(string path)
    {
        string text;
        try { text = File.ReadAllText(path); } catch { return null; }
        var lines = text.Split('\n');
        if (lines.Length == 0 || lines[0].TrimEnd('\r') != "---") return null;
        var collected = new List<string>();
        for (int i = 1; i < lines.Length; i++)
        {
            if (lines[i].TrimEnd('\r') == "---") return collected;
            collected.Add(lines[i].TrimEnd('\r'));
        }
        return null;
    }

    /// <summary>
    /// A sibling's frontmatter carried over whole, with only the created date
    /// freshened and (for index.md) the title replaced.
    /// </summary>
    internal static string ScaffoldFrontmatter(string? siblingPath, string? newTitle,
                                               string? fallbackTitle, bool fallbackIsDraft, string created)
    {
        var siblingLines = siblingPath is null ? null : FrontmatterLines(siblingPath);
        if (siblingLines is not null)
        {
            var rewritten = siblingLines.Select(line =>
            {
                if (line.StartsWith("created:", StringComparison.Ordinal)) return "created: " + created;
                if (line.StartsWith("title:", StringComparison.Ordinal) && newTitle is not null) return "title: " + newTitle;
                return line;
            });
            return string.Join("\n", rewritten);
        }
        // The publish key, not the legacy draft one, and note the polarity is
        // INVERTED: a teacher-eyes-only page is `publish: false`. Missing this
        // would have quietly born every new section in the old schema — the
        // same gap that setup_course.py had, in the other creation path.
        //
        // Only the fallback writes this. When there is a sibling section its
        // frontmatter is copied verbatim, which is what a course still using
        // `draft:` wants: the new section matches its siblings rather than
        // becoming the one page in the course with a different vocabulary.
        string title = newTitle ?? fallbackTitle ?? "";
        return $"title: {title}\ncreated: {created}\npublish: {(fallbackIsDraft ? "false" : "true")}";
    }

    /// <summary>
    /// Prefer the sibling's own title with its trailing "Section N" renumbered
    /// (preserving the teacher's wording); otherwise the wizard's form. The
    /// grade prefix is LITERAL — the switch alone decides.
    /// </summary>
    public static string SectionTitle(Course course, int sectionNumber)
    {
        string? sibling = SiblingFile("index.md", course);
        if (sibling is not null && FrontmatterLines(sibling) is { } lines)
        {
            foreach (string line in lines)
            {
                if (!line.StartsWith("title:", StringComparison.Ordinal)) continue;
                string value = line["title:".Length..].Trim();
                var match = System.Text.RegularExpressions.Regex.Match(value, @"Section \d+$");
                if (match.Success)
                    return value[..match.Index] + "Section " + sectionNumber;
                break;
            }
        }
        string gradeLabel = GradeLabel(course.Code);
        bool showsGrade = course.Configuration.ShowsGradeInTitle(sectionNumber);
        string prefix = showsGrade && gradeLabel.Length > 0 ? gradeLabel + " " : "";
        return $"{prefix}{course.Configuration.CourseName}, Section {sectionNumber}";
    }

    /// <summary>Grade label derived from course code (e.g. "ICS3U" -> "Grade 11", "MCMPR11" -> "Grade 11").</summary>
    public static string GradeLabel(string courseCode)
    {
        string trimmed = courseCode.Trim();
        if (string.IsNullOrEmpty(trimmed)) return "";

        // 1. Check for trailing 2-digit grade numbers common in BC (e.g. MCMPR11, MFMP-10, MMA--09)
        if (trimmed.EndsWith("09", StringComparison.OrdinalIgnoreCase) || trimmed.EndsWith("-09", StringComparison.OrdinalIgnoreCase))
            return "Grade 9";
        if (trimmed.EndsWith("10", StringComparison.OrdinalIgnoreCase) || trimmed.EndsWith("-10", StringComparison.OrdinalIgnoreCase))
            return "Grade 10";
        if (trimmed.EndsWith("11", StringComparison.OrdinalIgnoreCase) || trimmed.EndsWith("-11", StringComparison.OrdinalIgnoreCase))
            return "Grade 11";
        if (trimmed.EndsWith("12", StringComparison.OrdinalIgnoreCase) || trimmed.EndsWith("-12", StringComparison.OrdinalIgnoreCase))
            return "Grade 12";

        // 2. Check for Ontario course codes (4th character is digit 1–4)
        if (trimmed.Length >= 4)
        {
            char c = trimmed[3];
            if (char.IsDigit(c))
            {
                return c switch
                {
                    '1' => "Grade 9",
                    '2' => "Grade 10",
                    '3' => "Grade 11",
                    '4' => "Grade 12",
                    _ => "Grade ?",
                };
            }
        }

        return "";
    }

    /// <summary>Wizard-style created stamp: 2026-08-10T14:30:00.000-0400 (offset without colon).</summary>
    public static string Timestamp(DateTimeOffset date)
    {
        string body = date.ToString("yyyy-MM-dd'T'HH:mm:ss.'000'", CultureInfo.InvariantCulture);
        string offset = date.ToString("zzz", CultureInfo.InvariantCulture).Replace(":", "");
        return body + offset;
    }

    /// <summary>The smallest positive number not already in use.</summary>
    public static int SuggestedNumber(IReadOnlyCollection<int> existing)
    {
        int candidate = 1;
        while (existing.Contains(candidate)) candidate++;
        return candidate;
    }

    /// <summary>Live validation for the Add Section sheet. Empty entry → no warning yet.</summary>
    public static string? EntryProblem(string entry, IReadOnlyCollection<int> existing, string courseCode)
    {
        string trimmed = entry.Trim();
        if (trimmed.Length == 0) return null;
        if (!int.TryParse(trimmed, out int number) || number < 1)
            return $"“{trimmed}” isn’t a section number — sections are 1 or higher.";
        if (existing.Contains(number))
            return $"Section {number} of {courseCode} already exists.";
        return null;
    }

    public static bool EntryIsAddable(string entry, IReadOnlyCollection<int> existing) =>
        int.TryParse(entry.Trim(), out int number) && number >= 1 && !existing.Contains(number);
}

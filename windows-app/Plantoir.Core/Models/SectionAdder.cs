using System.Globalization;
using Plantoir.Core.Scripting;

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

        var (givenKeys, heldBack) = ExtendCourseLevelPagesCounting(course, number, created);

        // Only after the folder is safely written does the config learn about
        // it — a mid-way failure never leaves settings pointing at nothing.
        var numbers = config.SectionNumbers;
        numbers.Add(number);
        numbers.Sort();
        config.SetSectionNumbers(numbers);
        config.Write(course.ConfigFilePath);

        // Rule 5: this writes into pages the teacher never opened, so the
        // trail says it happened and how many - never which (#282, mac #175).
        ActivityTrail.Note(ActivityTrail.Event.SectionAdded,
            TrailLine(number, givenKeys, heldBack), course.Code, number);
    }

    /// <summary>The trail's line for a section added, word for word the mac's <c>SectionAdder.trailLine</c>.</summary>
    internal static string TrailLine(int sectionNumber, int pagesGivenKeys, int pagesKeptHiddenUnreadable = 0)
    {
        string pages = pagesGivenKeys == 1 ? "1 page" : $"{pagesGivenKeys} pages";
        string line = $"added section {sectionNumber}; {pages} shared by every section "
            + "given a date and a published-or-hidden setting for it";
        if (pagesKeptHiddenUnreadable > 0)
        {
            string unread = pagesKeptHiddenUnreadable == 1 ? "1 of them was" : $"{pagesKeptHiddenUnreadable} of them were";
            line += $"; {unread} kept hidden because its setting for the other sections could not be read";
        }
        return line;
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

        string normalizedRelative = relativePath.Replace('\\', '/');
        bool isRootIndex = normalizedRelative == "index.md";
        bool isTopLevelPerSectionFile = course.Configuration.PerSectionFiles.Contains(normalizedRelative);
        string? newTitle = isRootIndex ? SectionTitle(course, sectionNumber) : null;
        string? newCreated = isRootIndex || isTopLevelPerSectionFile ? created : null;

        File.WriteAllText(destinationPath, ReplaceTitleAndCreated(text, newTitle, newCreated));
    }

    /// <summary>
    /// The page with its top-level <c>title:</c> and <c>created:</c> replaced,
    /// each taking its old value's continuation lines with it and keeping its
    /// own line ending (#284, the mac's #199). The block is found the way the
    /// build finds it; a page without one is returned unchanged.
    /// </summary>
    /// <remarks>
    /// Walked from the BOTTOM of the block, so removing one key's continuation
    /// lines never shifts a key still to come. Until #282/#284 this rebuilt
    /// <c>"---\n" + block</c> and cut the old text by a character count, which
    /// assumed exactly <c>---</c> on line 0 and LF — and replaced the key's
    /// line alone, so a title below its key was read by the site joined to
    /// the new one.
    /// </remarks>
    internal static string ReplaceTitleAndCreated(string text, string? newTitle, string? newCreated)
    {
        if (newTitle is null && newCreated is null) return text;
        if (PageVisibilityReader.FenceIndices(text) is not { } fences) return text;

        var lines = new List<string>(text.Split('\n'));
        int close = fences.Close;
        for (int index = close - 1; index > fences.Open; index--)
        {
            string bare = PageVisibilityReader.TrimCarriageReturn(lines[index]);
            if (bare.StartsWith(' ') || bare.StartsWith('\t')) continue;
            if (newTitle is not null && PageVisibilityReader.ValuePart("title", bare) is not null)
                close -= PageFrontmatter.ReplaceKeyLine(lines, index, "title", "title: " + newTitle, close);
            else if (newCreated is not null && PageVisibilityReader.ValuePart("created", bare) is not null)
                close -= PageFrontmatter.ReplaceKeyLine(lines, index, "created", "created: " + newCreated, close);
        }
        return string.Join("\n", lines);
    }

    internal static void ExtendCourseLevelPages(Course course, int sectionNumber, string created) =>
        ExtendCourseLevelPagesCounting(course, sectionNumber, created);

    /// <summary>
    /// Give every course-level page with per-section keys a pair for the new
    /// section, and say how many were given keys and how many of those were
    /// held back because the setting they copy could not be read — the two
    /// numbers the trail's <c>section added</c> line carries.
    /// </summary>
    internal static (int GivenKeys, int HeldBack) ExtendCourseLevelPagesCounting(Course course, int sectionNumber, string created)
    {
        var sectionFolderNames = new HashSet<string>(course.Configuration.SectionNumbers.Select(n => $"section{n}"));
        if (!Directory.Exists(course.DirectoryPath)) return (0, 0);

        int given = 0, heldBack = 0;
        foreach (string file in Directory.GetFiles(course.DirectoryPath, "*.md", SearchOption.AllDirectories))
        {
            string relative = Path.GetRelativePath(course.DirectoryPath, file);
            string firstSegment = relative.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)[0];
            if (sectionFolderNames.Contains(firstSegment))
                continue;

            string text;
            try { text = File.ReadAllText(file); }
            catch { continue; }
            var (rewritten, outcome) = ExtendFrontmatter(text, sectionNumber, created);
            if (outcome == PageOutcome.Untouched) continue;
            try { File.WriteAllText(file, rewritten); }
            catch { continue; }
            given++;
            if (outcome == PageOutcome.GivenKeysAndKeptHiddenBecauseUnreadable) heldBack++;
        }
        return (given, heldBack);
    }

    /// <summary>What adding a section did to one course-level page.</summary>
    internal enum PageOutcome { Untouched, GivenKeys, GivenKeysAndKeptHiddenBecauseUnreadable }

    /// <summary>
    /// The page with a <c>createdSection&lt;N&gt;</c> and a
    /// <c>publishForSection&lt;N&gt;</c> for the new section, copied from the
    /// LOWEST existing section — pinned by
    /// <c>course-management.json → sectionNumbers.addingKeysToAPage</c>,
    /// compared as bytes.
    /// </summary>
    /// <remarks>
    /// <para>The block is found with the shared finder (#282, the mac's #175):
    /// three dashes or more, blank lines before, spaces after. The old strict
    /// finder SKIPPED a <c>----</c> fence, a blank line before the fence and a
    /// trailing space — and a page with no key for a section is SHOWN in it,
    /// so a page hidden in section 1 was published in the new section,
    /// silently.</para>
    /// <para>Spliced by LINE INDEX, never by rebuilding <c>"---\n" + block</c>
    /// and cutting by a character count: measured on the mac, that left a
    /// stray character on the new date (<c>…-0400e</c>) for the three
    /// non-<c>---</c> shapes, and here it rewrote a CRLF page as LF. The pair
    /// goes after the last per-section key's WHOLE value (its continuation
    /// lines, #181), each new line taking the ending of the line it follows.</para>
    /// </remarks>
    internal static (string Text, PageOutcome Outcome) ExtendFrontmatter(string text, int sectionNumber, string created)
    {
        if (PageVisibilityReader.FenceIndices(text) is not { } fences) return (text, PageOutcome.Untouched);
        var allLines = new List<string>(text.Split('\n'));
        var lines = allLines.Skip(fences.Open + 1).Take(fences.Close - fences.Open - 1)
            .Select(PageVisibilityReader.TrimCarriageReturn).ToList();
        if (AlreadyHasKeys(sectionNumber, lines)) return (text, PageOutcome.Untouched);

        var numbered = lines.Select((line, index) => (Index: index, Number: PerSectionKeyNumber(line)))
            .Where(entry => entry.Number is not null).ToList();
        if (numbered.Count == 0) return (text, PageOutcome.Untouched);
        int lowestSection = numbered.Min(entry => entry.Number!.Value);

        var addition = new List<string> { $"createdSection{sectionNumber}: {created}" };
        var (publish, couldBeRead) = PublishReading(lowestSection, lines);
        if (publish != null)
        {
            // An empty value is a null, and `key:` is how YAML spells one.
            addition.Add(publish.Length == 0
                ? $"publishForSection{sectionNumber}:"
                : $"publishForSection{sectionNumber}: {publish}");
        }

        int lastKeyPosition = fences.Open + 1 + numbered[^1].Index;
        string lineEnding = allLines[lastKeyPosition].EndsWith('\r') ? "\r" : "";
        string lastKey = lines[numbered[^1].Index];
        lastKey = lastKey[..lastKey.IndexOf(':')];
        bool wasEmpty = PageVisibilityReader.ValuePart(lastKey, lines[numbered[^1].Index]) is { } value
            && PageVisibilityReader.TrimYamlSpaces(value).Length == 0;
        int valueLines = PageFrontmatter.ContinuationLineCount(allLines, lastKeyPosition, fences.Close, wasEmpty);
        allLines.InsertRange(lastKeyPosition + 1 + valueLines, addition.Select(line => line + lineEnding));

        return (string.Join("\n", allLines),
            couldBeRead ? PageOutcome.GivenKeys : PageOutcome.GivenKeysAndKeptHiddenBecauseUnreadable);
    }

    private static bool AlreadyHasKeys(int sectionNumber, List<string> lines)
    {
        string[] prefixes = [$"createdSection{sectionNumber}:", $"publishForSection{sectionNumber}:", $"draftSection{sectionNumber}:"];
        return lines.Any(l => prefixes.Any(p => l.StartsWith(p, StringComparison.Ordinal)));
    }

    /// <inheritdoc cref="PublishReading"/>
    internal static string? PublishValue(int sectionNumber, List<string> lines) =>
        PublishReading(sectionNumber, lines).Value;

    /// <summary>
    /// The value a new section's <c>publishForSection&lt;N&gt;</c> should carry,
    /// taken from the section this page already has — or null when the page
    /// carries neither spelling.
    /// </summary>
    /// <remarks>
    /// <para>The per-section value is copied VERBATIM. Whatever the build makes
    /// of `publishForSection1: oN` it makes of `publishForSection2: oN`, so no
    /// reader standing between the two can invert it by misreading it. The one
    /// value that cannot be copied is one that runs onto the NEXT line — a
    /// block scalar, or a key with the value indented beneath it — because the
    /// copy would be a key with nothing after it. Those are written as held
    /// back.</para>
    ///
    /// <para>The continuation test comes BEFORE the empty one, deliberately: a
    /// `publishForSection1:` whose value sits indented below it LOOKS empty,
    /// and copying that emptiness would publish a page the build holds back.
    /// Both references — the mac's <c>SectionAdder.publishValue</c> and
    /// <c>setup_course.per_section_frontmatter</c> — write `false` for it.</para>
    ///
    /// <para><c>draftSection&lt;N&gt;</c> is the older spelling with the
    /// OPPOSITE polarity, so it is read and inverted — carrying it across
    /// unchanged would publish a page the teacher had held back. Until
    /// 2026-09-19 this compared the value with the literal "true", which
    /// quietly PUBLISHED a `draftSection1: yes` or `draftSection1: On` page
    /// into the new section while the build went on hiding the original. A
    /// draft value this app cannot read is written as held back: a page wrongly
    /// held back is one a teacher notices and fixes; a page wrongly published
    /// is one nobody notices at all.</para>
    /// </remarks>
    internal static (string? Value, bool CouldBeRead) PublishReading(int sectionNumber, List<string> lines)
    {
        // The reader's own matcher and the reader's own LAST-wins rule, so the
        // value carried across is the value the build reads. A prefix test
        // missed `"publishForSection1": false` entirely, and stopping at the
        // first of two copies carried the one PyYAML throws away.
        if (PageVisibilityReader.LastTopLevelEntry($"publishForSection{sectionNumber}", lines) is { } entry)
        {
            bool continues = entry.NextLine is { } below
                && (below.StartsWith(' ') || below.StartsWith('\t'));
            if (continues) return ("false", false);

            string value = PageVisibilityReader.TrimYamlSpaces(entry.Value);
            if (value.Length == 0)
            {
                // A key with nothing after it is a NULL, which PUBLISHES the
                // page. Copying the emptiness keeps the new section saying what
                // the old one says; writing "false" would hide it.
                return ("", true);
            }
            if (!PageVisibilityReader.IsCompleteOnItsOwnLine(entry.Value)) return ("false", false);
            return (value, true);
        }

        if (PageVisibilityReader.LastTopLevelEntry($"draftSection{sectionNumber}", lines) is { } legacy)
        {
            // No `continues` check of its own on this branch, because the
            // READER now has one: a value with an indented line below it is
            // `cannot tell` whatever is on the key's line, so it lands "false"
            // — held back — which is what `setup_course.per_section_frontmatter`
            // writes for the same input.
            //
            // **This differs from the mac, and the difference is new.** Until
            // the reader was corrected (2026-09-19, issue #176) this branch
            // matched the SWIFT, which still consults the line below only when
            // the key's line is EMPTY: the mac carries `draftSection1: false`
            // with an indented line under it across as PUBLISHED, and this
            // carries it as held back. Measured what the SITE does with the
            // source page — python-frontmatter 1.3.0 / PyYAML 6.0.3, then
            // `build_site._as_bool`:
            //
            //     draftSection1: false / "  x"   'false x'  -> PUBLISHED
            //     draftSection1: no    / "  x"   'no x'     -> PUBLISHED
            //     draftSection1: true  / "  x"   'true x'   -> PUBLISHED
            //     draftSection1: yes   / "  x"   'yes x'    -> PUBLISHED
            //     draftSection1:       / "  true"  True     -> HIDDEN
            //
            // Neither app reproduces that: both err HELD BACK, the mac in two
            // of those rows and this in four. Uniformly held back is the
            // documented preference here — a page wrongly held back is one a
            // teacher notices and fixes — and it is the Python's answer too.
            // The mac's own #176 fix closes it, since its `publishValue` asks
            // the same reader.
            var scalar = PageVisibilityReader.ReadScalar(legacy.Value, legacy.NextLine);
            var answer = PageVisibilityReader.DraftFamilyAnswer(scalar);
            return answer switch
            {
                PageVisibility.Visible => ("true", true),
                PageVisibility.Hidden => ("false", true),
                _ => ("false", false),   // cannot tell: held back, and counted
            };
        }
        return (null, true);
    }

    internal static int? PerSectionKeyNumber(string line)
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
        // The build's own boundary (#282): three dashes or more, blank lines
        // before, spaces after - the same finder every writer uses.
        if (PageVisibilityReader.FenceIndices(text) is not { } fences) return null;
        return text.Split('\n').Skip(fences.Open + 1).Take(fences.Close - fences.Open - 1)
            .Select(PageVisibilityReader.TrimCarriageReturn).ToList();
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
            // Through the shared ReplaceKeyLine (#284), bottom up, so a title
            // or date below its key goes with it rather than joining the new one.
            string replaced = ReplaceTitleAndCreated("---\n" + string.Join("\n", siblingLines) + "\n---", newTitle, created);
            return replaced[4..^4];
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

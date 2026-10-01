using System.Text;
using System.Text.RegularExpressions;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Models;

/// <summary>
/// Copy a Page from This Course… (#247, mac #207;
/// <c>contracts/shared-rules.json → copyingAPageBetweenCourses</c>): one page
/// out of one course and into another, with the pictures and files it shows
/// and — on a checklist — the pages it links to.
///
/// <para><b>The two promises.</b> A copy ALWAYS arrives hidden from students
/// in every section of the destination (<see cref="CopyPageFrontmatter"/>),
/// and nothing already in the destination is changed, renamed or written over.
/// Anything the page names that is not carried is LISTED.</para>
///
/// <para><b>Never overwritten, and on NTFS that is this class's job, not the
/// file system's.</b> Every write is <see cref="FileMode.CreateNew"/>, never a
/// <c>File.Exists</c> check (a check has a window); an
/// <see cref="IOException"/> with HResult 0x80070050 (ERROR_FILE_EXISTS) is the
/// ordinary "already here" skip. CreateNew refuses a name differing only by
/// CASE — but MEASURED on NTFS (bundle-6 plan §0), it does NOT refuse one
/// differing only by how an accent is SPELLED (NFC against NFD): NTFS makes a
/// second file. So the name index — NFC-composed, then upper-cased, ordinal,
/// <c>.md</c> dropped — is the ONLY guard against an accent twin here, where on
/// the mac <c>O_EXCL</c> refuses it too. It is updated after EACH successful
/// write (bundle-6 ruling 5), so two twins arriving in one run cannot both be
/// written.</para>
///
/// <para><b>Names are written as the SOURCE spelled them.</b> .NET's listing
/// and <see cref="Path.Combine(string, string)"/> leave an NFD name exactly as
/// stored (measured), so a name is normalised only to COMPARE.</para>
/// </summary>
public static class CoursePageCopy
{
    /// <summary>The one folder this feature may create: Plantoir looks after it.</summary>
    public const string MediaFolder = "Media";

    /// <summary>Generated folders, never indexed (<c>neverOverwritten.theBuiltWebsiteIsNotIndexed</c>).</summary>
    public static readonly IReadOnlyList<string> NotIndexed =
        new[] { ".merged_output", "node_modules", ".git", ".quartz-cache", ".cache", ".obsidian" };

    /// <summary>How the rename search ends: a numbered name up to this, then the page is not copied.</summary>
    public const int MostNumberedNames = 50;

    private const int ErrorFileExists = unchecked((int)0x80070050);
    private const int ErrorAlreadyExists = unchecked((int)0x800700B7);

    /// <summary>A name as it is COMPARED: NFC, then upper-cased, ordinal.</summary>
    public static string Fold(string name) => name.Normalize(NormalizationForm.FormC).ToUpperInvariant();

    /// <summary>A page's name as it is compared: the file name without <c>.md</c>, folded.</summary>
    public static string PageKey(string fileName) =>
        Fold(fileName.EndsWith(".md", StringComparison.OrdinalIgnoreCase) ? fileName[..^3] : fileName);

    // ---- What is offered ---------------------------------------------------

    /// <summary>
    /// The pages that may be copied: directly inside a TOP-LEVEL shared folder
    /// of the source, never a folder's <c>index.md</c>, never deeper. Relative
    /// paths with forward slashes, sorted.
    /// </summary>
    public static List<string> Offered(Course source) =>
        FoldersOnDisk(source)
            .SelectMany(folder => SafeFiles(Path.Combine(source.DirectoryPath, folder), "*.md")
                .Where(file => !Path.GetFileName(file).Equals("index.md", StringComparison.OrdinalIgnoreCase))
                .Select(file => folder + "/" + Path.GetFileName(file)))
            .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
            .ToList();

    /// <summary>The destination's shared folders that are listed AND on disk — the only places a page may land.</summary>
    public static List<string> FoldersOffered(Course destination) => FoldersOnDisk(destination);

    private static List<string> FoldersOnDisk(Course course) =>
        course.Configuration.SharedFolders
            .Where(folder => folder.Length > 0 && !folder.Contains('/') && !folder.Contains('\\')
                             && Directory.Exists(Path.Combine(course.DirectoryPath, folder)))
            .ToList();

    /// <summary>The destinations a source can be copied into: courses being taught, never a reference course, never itself.</summary>
    public static List<Course> Destinations(Course source, IEnumerable<Course> courses) =>
        courses.Where(course => !ReferenceCourse.IsKeptForReference(course)
                                && !string.Equals(course.DirectoryPath, source.DirectoryPath, StringComparison.OrdinalIgnoreCase))
            .ToList();

    // ---- The plan --------------------------------------------------------------

    /// <param name="Page">The source page, relative, forward slashes ("Concepts/Recursion.md").</param>
    /// <param name="IntoFolder">The destination shared folder the chosen page lands in.</param>
    /// <param name="Unticked">Linked pages the teacher unticked, by name; required pages ignore it.</param>
    public sealed record Request(Course Source, Course Destination, string Page, string IntoFolder,
                                 bool AlsoCopiesLinkedPages, IReadOnlySet<string>? Unticked = null);

    public enum MediaKind { Created, Reused, Renamed }

    /// <summary>One picture or file the copied pages show.</summary>
    /// <param name="SourcePath">The file in the source's Media, as listed.</param>
    /// <param name="NameAsWritten">The name the page's text uses, which a rename rewrites.</param>
    /// <param name="DestinationName">The name it has in the destination's Media.</param>
    public sealed record PlannedMedia(string SourcePath, string NameAsWritten, string DestinationName, MediaKind Kind, long Bytes)
    {
        public string SourceName => Path.GetFileName(SourcePath);
    }

    /// <summary>One page that will be copied.</summary>
    public sealed record PlannedPage(string Name, string SourcePath, string DestinationRelative, bool IsChosen, bool Required,
                                     IReadOnlyList<PlannedMedia> Media);

    /// <summary>A page or file not copied, and the contract key (result tense) that says why.</summary>
    public sealed record Skip(string Name, string Reason);

    public sealed record Plan(
        IReadOnlyList<PlannedPage> Pages,
        IReadOnlyList<PlannedMedia> Media,
        IReadOnlyList<Skip> Skipped,
        IReadOnlyList<string> LinksLeadingNowhere,
        IReadOnlyList<string> LinkedPageRows)
    {
        public IEnumerable<PlannedMedia> Brought => Media.Where(m => m.Kind != MediaKind.Reused);
        public long BytesBrought => Brought.Sum(m => m.Bytes);
        public IReadOnlyDictionary<string, string> Renamed =>
            Media.Where(m => m.Kind == MediaKind.Renamed).ToDictionary(m => m.SourceName, m => m.DestinationName);
    }

    /// <summary>The future-tense twin of each skip reason, for the checklist (<c>hidden.readBackAndDelete.theChecklistIsInTheFUTURE</c>).</summary>
    public static string FutureOf(string reason) => reason switch
    {
        "aPageOfThatNameIsAlreadyHere" => "willBeLeftAsItIs",
        "aClassPageWasLeftAlone" => "aClassPageWillBeLeftAlone",
        "anIndexPageIsNotCopied" => "anIndexPageWillNotBeCopied",
        "aPageAtTheCourseRootIsNotCopied" => "aPageAtTheCourseRootWillNotBeCopied",
        "aPageInsideOneSectionsFolderIsNotCopied" => "aPageInsideOneSectionsFolderWillNotBeCopied",
        _ => reason,
    };

    private enum PageKind { Copyable, Class, Index, Root, Section }

    /// <summary>
    /// What a copy WOULD do, reading both courses and writing nothing. A
    /// linked page is followed when the teacher asked for linked pages and has
    /// not unticked it; a page shown INSIDE a copied page always comes, and is
    /// required while that page comes. A class page stops the walk.
    /// </summary>
    public static Plan MakePlan(Request request)
    {
        var source = request.Source;
        var destination = request.Destination;
        var unticked = request.Unticked ?? new HashSet<string>();
        var destinationPages = PageIndex(destination.DirectoryPath);
        var sourcePages = PageIndexWithPaths(source.DirectoryPath);
        var sourceMedia = MediaIn(source.DirectoryPath);
        var destinationMedia = MediaIn(destination.DirectoryPath).ToDictionary(file => Fold(Path.GetFileName(file)), file => file);
        var foldersOffered = FoldersOffered(destination);
        var classFolders = ClassFolderRule.Names(source.Configuration.ClassFolder, source.Configuration.PerSectionFolders);

        var pages = new List<PlannedPage>();
        var media = new List<PlannedMedia>();
        var skipped = new List<Skip>();
        var nowhere = new List<string>();
        var rows = new List<string>();
        var visited = new HashSet<string>(StringComparer.Ordinal);
        var queue = new Queue<(string Relative, bool IsChosen, bool Required)>();
        queue.Enqueue((request.Page, true, true));
        visited.Add(PageKey(Path.GetFileName(request.Page)));

        while (queue.Count > 0)
        {
            var (relative, isChosen, required) = queue.Dequeue();
            string fileName = relative.Split('/')[^1];
            string name = fileName.EndsWith(".md", StringComparison.OrdinalIgnoreCase) ? fileName[..^3] : fileName;
            if (destinationPages.Contains(PageKey(fileName)))
            {
                skipped.Add(new Skip(name, "aPageOfThatNameIsAlreadyHere"));
                if (isChosen) break;
                continue;
            }
            string sourcePath = Path.Combine(source.DirectoryPath, relative.Replace('/', Path.DirectorySeparatorChar));
            string text;
            try { text = File.ReadAllText(sourcePath); }
            catch
            {
                skipped.Add(new Skip(name, "thePageCouldNotBeRead"));
                if (isChosen) break;
                continue;
            }

            // The pictures and files it shows, settled now.
            var shown = new List<PlannedMedia>();
            bool namesRanOut = false;
            foreach (var reference in References(text).Where(r => r.IsFile))
            {
                var found = FindInSource(reference.Name, sourceMedia);
                if (found is null) { AddOnce(nowhere, reference.Written); continue; }
                if (found.Value.ByFoldingSpaces) AddOnce(nowhere, reference.Written);
                var already = media.Concat(shown).FirstOrDefault(m => string.Equals(m.SourcePath, found.Value.Path, StringComparison.OrdinalIgnoreCase));
                if (already is not null)
                {
                    if (!shown.Contains(already)) shown.Add(already with { NameAsWritten = reference.Name });
                    continue;
                }
                var planned = Settle(found.Value.Path, reference.Name, source.Code, destinationMedia, media.Concat(shown));
                if (planned is null) { namesRanOut = true; break; }
                shown.Add(planned);
            }
            if (namesRanOut)
            {
                skipped.Add(new Skip(name, "thePicturesCouldNotBePointedAtTheirNewNames"));
                if (isChosen) break;
                continue;
            }

            string topFolder = relative.Contains('/') ? relative.Split('/')[0] : "";
            string landsIn = isChosen
                ? request.IntoFolder
                : foldersOffered.FirstOrDefault(f => f.Equals(topFolder, StringComparison.OrdinalIgnoreCase)) ?? request.IntoFolder;
            pages.Add(new PlannedPage(name, sourcePath, landsIn + "/" + fileName, isChosen, required, shown));
            foreach (var m in shown.Where(m => !media.Any(x => string.Equals(x.SourcePath, m.SourcePath, StringComparison.OrdinalIgnoreCase))))
                media.Add(m);

            // The pages it links to.
            foreach (var reference in References(text).Where(r => !r.IsFile))
            {
                string key = PageKey(reference.Name);
                if (key == PageKey(fileName)) continue;                         // a page naming itself
                if (destinationPages.Contains(key)) continue;                  // the link works already
                if (!sourcePages.TryGetValue(key, out string? linked))
                {
                    AddOnce(nowhere, reference.Written);
                    continue;
                }
                string linkedName = linked.Split('/')[^1][..^3];
                var kind = Classify(linked, classFolders);
                if (kind != PageKind.Copyable)
                {
                    if (!skipped.Any(s => PageKey(s.Name) == key)) skipped.Add(new Skip(linkedName, ReasonFor(kind)));
                    continue;
                }
                if (!reference.IsEmbed && !rows.Contains(linkedName)) rows.Add(linkedName);
                bool follow = reference.IsEmbed
                              || (request.AlsoCopiesLinkedPages && !unticked.Contains(linkedName));
                if (!follow)
                {
                    if (!visited.Contains(key)) AddOnce(nowhere, reference.Written);
                    continue;
                }
                if (visited.Add(key)) queue.Enqueue((linked, false, reference.IsEmbed));
            }
        }

        // A page that did not come along takes nothing with it.
        var used = pages.SelectMany(p => p.Media).Select(m => m.SourcePath).ToHashSet(StringComparer.OrdinalIgnoreCase);
        media.RemoveAll(m => !used.Contains(m.SourcePath));
        return new Plan(pages, media, skipped, nowhere, rows);
    }

    private static void AddOnce(List<string> list, string item)
    {
        if (!list.Contains(item)) list.Add(item);
    }

    private static string ReasonFor(PageKind kind) => kind switch
    {
        PageKind.Class => "aClassPageWasLeftAlone",
        PageKind.Index => "anIndexPageIsNotCopied",
        PageKind.Root => "aPageAtTheCourseRootIsNotCopied",
        PageKind.Section => "aPageInsideOneSectionsFolderIsNotCopied",
        _ => "",
    };

    private static PageKind Classify(string relative, IReadOnlyList<string> classFolders)
    {
        var segments = relative.Split('/');
        if (segments[^1].Equals("index.md", StringComparison.OrdinalIgnoreCase)) return PageKind.Index;
        if (segments.Length == 1) return PageKind.Root;
        if (Regex.IsMatch(segments[0], @"^section[0-9]+$", RegexOptions.IgnoreCase))
            return ClassFolderRule.IsClassPage(string.Join("/", segments.Skip(1)), classFolders) ? PageKind.Class : PageKind.Section;
        return PageKind.Copyable;
    }

    /// <summary>
    /// Where one picture lands: under its own name when the destination has
    /// none of that name; REUSED when it has one with the same bytes; under
    /// "&lt;name&gt; (from &lt;source folder&gt;)&lt;ext&gt;" — then numbered — when the
    /// name holds something different. Null when the bounded search finds no
    /// free name, which means the PAGE is not copied: written with the
    /// original name it would show the teacher their own different picture.
    /// </summary>
    private static PlannedMedia? Settle(string sourcePath, string nameAsWritten, string sourceFolder,
        IReadOnlyDictionary<string, string> destinationMedia, IEnumerable<PlannedMedia> alreadyPlanned)
    {
        string sourceName = Path.GetFileName(sourcePath);
        long bytes = new FileInfo(sourcePath).Length;
        var planned = alreadyPlanned.Select(m => Fold(m.DestinationName)).ToHashSet(StringComparer.Ordinal);
        // Only the DESTINATION is consulted here. Two incoming pictures that
        // are accent twins of each other both plan "created"; the write-time
        // index, updated after each write, is what stops the second (ruling 5).
        if (!destinationMedia.TryGetValue(Fold(sourceName), out string? existing))
            return new PlannedMedia(sourcePath, nameAsWritten, sourceName, MediaKind.Created, bytes);
        if (SameBytes(sourcePath, existing))
            return new PlannedMedia(sourcePath, nameAsWritten, Path.GetFileName(existing), MediaKind.Reused, bytes);

        string stem = Path.GetFileNameWithoutExtension(sourceName), extension = Path.GetExtension(sourceName);
        foreach (string candidate in Enumerable.Range(1, MostNumberedNames)
                     .Select(n => n == 1 ? $"{stem} (from {sourceFolder}){extension}" : $"{stem} (from {sourceFolder}) {n}{extension}"))
        {
            if (planned.Contains(Fold(candidate))) continue;
            if (!destinationMedia.TryGetValue(Fold(candidate), out string? taken))
                return new PlannedMedia(sourcePath, nameAsWritten, candidate, MediaKind.Renamed, bytes);
            if (SameBytes(sourcePath, taken))
                return new PlannedMedia(sourcePath, nameAsWritten, Path.GetFileName(taken), MediaKind.Reused, bytes);
        }
        return null;
    }

    /// <summary>Same size, then the same bytes, read in chunks: a real picture can be hundreds of megabytes.</summary>
    public static bool SameBytes(string a, string b)
    {
        try
        {
            if (new FileInfo(a).Length != new FileInfo(b).Length) return false;
            using var first = new FileStream(a, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            using var second = new FileStream(b, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            var left = new byte[1 << 16];
            var right = new byte[1 << 16];
            while (true)
            {
                int read = first.ReadAtLeast(left, left.Length, throwOnEndOfStream: false);
                int other = second.ReadAtLeast(right, right.Length, throwOnEndOfStream: false);
                if (read != other || !left.AsSpan(0, read).SequenceEqual(right.AsSpan(0, other))) return false;
                if (read == 0) return true;
            }
        }
        catch { return false; }
    }

    // ---- Reading what a page names ------------------------------------------

    /// <summary>One thing a page names: a page or a file, as written and as a bare name.</summary>
    public sealed record Reference(string Written, string Name, bool IsEmbed, bool IsFile);

    private static readonly Regex HtmlAttribute = new(@"\b(?:src|href)\s*=\s*(?:""(?<v>[^""]*)""|'(?<v>[^']*)')",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    /// <summary>
    /// Every page and file the page names OUTSIDE code and <c>%%</c> comments
    /// (<c>readingALink</c>): wikilinks and embeds (an escaped table pipe ends
    /// the name), Markdown destinations — angle-bracketed ones too — and HTML
    /// <c>src</c>/<c>href</c>. A name with an extension other than <c>.md</c>
    /// is a FILE; a link with a scheme names nothing here.
    /// </summary>
    public static List<Reference> References(string text)
    {
        var found = new List<Reference>();
        foreach (var link in WikiLinks.Parse(text))
        {
            string bare = link.Target.Replace('\\', '/').Split('/')[^1].Trim();
            found.Add(new Reference(link.Target, bare, link.IsEmbed, IsFileName(bare)));
        }
        var ranges = MarkdownCode.NotALinkRanges(text);
        var destinations = MarkdownCode.MatchesOutside(FolderPathRewriter.AngleLink, text, ranges)
            .Select(m => (m.Index, Value: m.Groups[2].Value, Embed: m.Index > 0 && IsEmbedBefore(text, m.Index)))
            .Concat(MarkdownCode.MatchesOutside(FolderPathRewriter.MarkdownLink, text, ranges)
                .Select(m => (m.Index, Value: m.Groups[2].Value, Embed: IsEmbedBefore(text, m.Index))))
            .Concat(MarkdownCode.MatchesOutside(HtmlAttribute, text, ranges)
                .Select(m => (m.Index, Value: m.Groups["v"].Value, Embed: true)))
            .OrderBy(d => d.Index);
        foreach (var (_, value, embed) in destinations)
        {
            string destination = value.Trim();
            if (destination.Length == 0 || destination.StartsWith('#') || destination.StartsWith("//", StringComparison.Ordinal)) continue;
            if (FolderPathRewriter.Scheme.IsMatch(destination)) continue;
            int cut = destination.IndexOfAny(new[] { '#', '?' });
            if (cut >= 0) destination = destination[..cut];
            string decoded;
            try { decoded = Uri.UnescapeDataString(destination); } catch { decoded = destination; }
            string bare = decoded.Replace('\\', '/').Split('/')[^1].Trim();
            if (bare.Length == 0) continue;
            found.Add(new Reference(decoded, bare, embed, IsFileName(bare)));
        }
        return found;
    }

    /// <summary>Whether the <c>](</c> at <paramref name="index"/> closes an image <c>![…]</c>.</summary>
    private static bool IsEmbedBefore(string text, int index)
    {
        int open = text.LastIndexOf('[', Math.Max(0, index));
        return open > 0 && text[open - 1] == '!';
    }

    private static readonly HashSet<string> FileExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp", ".avif", ".bmp", ".ico", ".tif", ".tiff", ".heic",
        ".pdf", ".mp4", ".mov", ".webm", ".m4v", ".mp3", ".m4a", ".wav", ".ogg",
        ".zip", ".doc", ".docx", ".ppt", ".pptx", ".xls", ".xlsx", ".csv", ".txt", ".py", ".java", ".swift", ".json", ".html",
    };

    /// <summary>
    /// A FILE rather than a page: an extension from a fixed list, because a
    /// curriculum page is genuinely called <c>E2.6</c> and its ".6" is not one.
    /// </summary>
    private static bool IsFileName(string name)
    {
        string extension = Path.GetExtension(name);
        return extension.Length > 1 && !extension.Equals(".md", StringComparison.OrdinalIgnoreCase) && FileExtensions.Contains(extension);
    }

    /// <summary>The three spaces a typed link carries as an ordinary one: no-break, narrow no-break, figure.</summary>
    private static string FoldSpaces(string name) =>
        name.Replace((char)0x00A0, ' ').Replace((char)0x202F, ' ').Replace((char)0x2007, ' ');

    /// <summary>The file in the source's Media a name points at: exactly, by its folded spelling, then by folding invisible spaces.</summary>
    private static (string Path, bool ByFoldingSpaces)? FindInSource(string name, IReadOnlyList<string> sourceMedia)
    {
        string exact = sourceMedia.FirstOrDefault(file => Path.GetFileName(file) == name) ?? "";
        if (exact.Length > 0) return (exact, false);
        string folded = sourceMedia.FirstOrDefault(file => Fold(Path.GetFileName(file)) == Fold(name)) ?? "";
        if (folded.Length > 0) return (folded, false);
        string spaced = sourceMedia.FirstOrDefault(file => Fold(FoldSpaces(Path.GetFileName(file))) == Fold(FoldSpaces(name))) ?? "";
        return spaced.Length > 0 ? (spaced, true) : null;
    }

    // ---- The indexes --------------------------------------------------------------

    /// <summary>Every page name ANYWHERE in a course, folded — what "a page of that name is already here" asks.</summary>
    public static HashSet<string> PageIndex(string courseDirectory) =>
        Walk(courseDirectory).Where(path => path.EndsWith(".md", StringComparison.OrdinalIgnoreCase))
            .Select(path => PageKey(Path.GetFileName(path))).ToHashSet(StringComparer.Ordinal);

    private static Dictionary<string, string> PageIndexWithPaths(string courseDirectory)
    {
        var index = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (string path in Walk(courseDirectory).Where(p => p.EndsWith(".md", StringComparison.OrdinalIgnoreCase))
                     .OrderBy(p => p.Count(c => c == Path.DirectorySeparatorChar)).ThenBy(p => p, StringComparer.OrdinalIgnoreCase))
        {
            string key = PageKey(Path.GetFileName(path));
            if (!index.ContainsKey(key))
                index[key] = Path.GetRelativePath(courseDirectory, path).Replace(Path.DirectorySeparatorChar, '/');
        }
        return index;
    }

    private static List<string> MediaIn(string courseDirectory) =>
        SafeFiles(Path.Combine(courseDirectory, MediaFolder), "*").ToList();

    private static IEnumerable<string> SafeFiles(string folder, string pattern)
    {
        try { return Directory.EnumerateFiles(folder, pattern, ReferenceLock.Unfiltered).ToList(); }
        catch { return Array.Empty<string>(); }
    }

    private static IEnumerable<string> Walk(string root)
    {
        var pending = new Stack<string>();
        pending.Push(root);
        while (pending.Count > 0)
        {
            string folder = pending.Pop();
            List<FileSystemInfo> entries;
            try { entries = new DirectoryInfo(folder).EnumerateFileSystemInfos("*", ReferenceLock.Unfiltered).ToList(); }
            catch { continue; }
            foreach (var entry in entries)
            {
                if (entry.Attributes.HasFlag(FileAttributes.ReparsePoint)) continue;
                if (entry is DirectoryInfo)
                {
                    if (!NotIndexed.Contains(entry.Name, StringComparer.OrdinalIgnoreCase)) pending.Push(entry.FullName);
                }
                else yield return entry.FullName;
            }
        }
    }

    // ---- The copy ------------------------------------------------------------------

    /// <summary>What a copy did.</summary>
    public sealed class Outcome
    {
        public List<string> PagesCreated { get; } = new();
        public List<Skip> Skipped { get; } = new();
        public List<string> MediaCreated { get; } = new();
        public List<string> MediaReused { get; } = new();
        public Dictionary<string, string> MediaRenamed { get; } = new();
        public List<string> MediaLeftAlone { get; } = new();
        public List<string> LinksLeadingNowhere { get; } = new();
        /// <summary>Copies that could not be shown hidden AND could not be removed — must not be deployed.</summary>
        public List<string> MustBeRemoved { get; } = new();
        /// <summary>Pages whose source had settings the build could not read, given a block of their own.</summary>
        public int CopiedHiddenBecauseUnreadable { get; set; }
        /// <summary>Set when nothing was written because the act was refused (a contract wording key).</summary>
        public string? Refusal { get; set; }
        public string? BackupName { get; set; }
    }

    /// <summary>
    /// One Copy a Page window's session: the backup is taken ONCE, before its
    /// first write (<c>theBackup.oncePerSheetNotOncePerPress</c>) — five
    /// presses of "Copy another" are not five backups of a growing course.
    /// </summary>
    public sealed class Session
    {
        private readonly Func<Course, string> _backUp;
        public Session(Func<Course, string> backUp) => _backUp = backUp;
        public string? BackupName { get; private set; }
        public int BackupsTaken { get; private set; }

        /// <summary>The backup's file name, taking it if this session has not; throws when it could not be saved.</summary>
        public string BackUpOnce(Course destination)
        {
            if (BackupName is null)
            {
                BackupName = Path.GetFileName(_backUp(destination));
                BackupsTaken++;
            }
            return BackupName;
        }
    }

    /// <summary>
    /// Writes the plan: the destination's settings re-read for its sections,
    /// the backup once per session, the pictures, then each page — composed
    /// hidden, guarded, created exclusively, the index updated, read back, and
    /// DELETED (the delete checked) if it is not certainly hidden. Writes ONE
    /// trail line at the end in every outcome but a refusal.
    /// </summary>
    /// <param name="isDeploying">Asked immediately before the first write; a deploy of the destination refuses.</param>
    public static Outcome Copy(Plan plan, Request request, Session session, Func<bool>? isDeploying = null)
    {
        var outcome = new Outcome();
        var destination = request.Destination;
        if (isDeploying?.Invoke() == true)
        {
            outcome.Refusal = "thatCourseIsDeployingRightNow";
            return outcome;
        }
        try { outcome.BackupName = session.BackUpOnce(destination); }
        catch
        {
            outcome.Refusal = "theCopyOfTheCourseCouldNotBeSaved";
            return outcome;
        }

        // Re-read immediately before composing: a section added in another
        // window since the plan would otherwise get nothing said about it.
        IReadOnlyList<int> sections;
        try { sections = CourseConfiguration.Load(destination.ConfigFilePath).SectionNumbers; }
        catch { sections = destination.SectionNumbers; }

        outcome.Skipped.AddRange(plan.Skipped);
        outcome.LinksLeadingNowhere.AddRange(plan.LinksLeadingNowhere);
        var pageIndex = PageIndex(destination.DirectoryPath);
        string mediaFolder = Path.Combine(destination.DirectoryPath, MediaFolder);
        var mediaIndex = SafeFiles(mediaFolder, "*").Select(f => Fold(Path.GetFileName(f))).ToHashSet(StringComparer.Ordinal);
        var failedMedia = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var file in plan.Media)
        {
            if (file.Kind == MediaKind.Reused) { outcome.MediaReused.Add(file.DestinationName); continue; }
            string target = Path.Combine(mediaFolder, file.DestinationName);
            if (mediaIndex.Contains(Fold(file.DestinationName)))
            {
                // A twin spelled another way, or one that appeared since the
                // plan: never a second file, never an overwrite.
                outcome.MediaLeftAlone.Add(file.DestinationName);
                outcome.Skipped.Add(new Skip(file.DestinationName, "aPictureCouldNotBeCopied"));
                failedMedia.Add(file.SourcePath);
                continue;
            }
            try
            {
                Directory.CreateDirectory(mediaFolder);
                CreateExclusively(file.SourcePath, target);
                ReferenceLock.Clear(target);
                mediaIndex.Add(Fold(file.DestinationName));                       // after EACH write (ruling 5)
                if (file.Kind == MediaKind.Renamed) outcome.MediaRenamed[file.SourceName] = file.DestinationName;
                outcome.MediaCreated.Add(file.DestinationName);
            }
            catch (IOException e) when (e.HResult is ErrorFileExists or ErrorAlreadyExists)
            {
                outcome.MediaLeftAlone.Add(file.DestinationName);
                outcome.Skipped.Add(new Skip(file.DestinationName, "aPictureCouldNotBeCopied"));
                failedMedia.Add(file.SourcePath);
            }
            catch
            {
                outcome.Skipped.Add(new Skip(file.DestinationName, "aPictureCouldNotBeCopied"));
                failedMedia.Add(file.SourcePath);
            }
        }

        foreach (var page in plan.Pages)
        {
            string fileName = page.DestinationRelative.Split('/')[^1];
            string target = Path.Combine(destination.DirectoryPath, page.DestinationRelative.Replace('/', Path.DirectorySeparatorChar));
            if (pageIndex.Contains(PageKey(fileName)))
            {
                outcome.Skipped.Add(new Skip(page.Name, "aPageOfThatNameIsAlreadyHere"));
                continue;
            }
            string source;
            try { source = File.ReadAllText(page.SourcePath); }
            catch { outcome.Skipped.Add(new Skip(page.Name, "thePageCouldNotBeRead")); continue; }

            var renamed = page.Media.Where(m => !string.Equals(m.NameAsWritten, m.DestinationName, StringComparison.Ordinal)
                                                && m.Kind != MediaKind.Created)
                .GroupBy(m => m.NameAsWritten).ToDictionary(g => g.Key, g => g.First().DestinationName);
            string rewritten = PointedAt(source, renamed);
            if (References(rewritten).Any(r => r.IsFile && renamed.ContainsKey(r.Name) && !renamed.ContainsValue(r.Name)))
            {
                outcome.Skipped.Add(new Skip(page.Name, "thePicturesCouldNotBePointedAtTheirNewNames"));
                continue;
            }
            bool unreadableBlock = PageVisibilityReader.FenceIndices(rewritten) is null && PageVisibilityReader.OpensAFence(rewritten);
            string? composed = CopyPageFrontmatter.Compose(rewritten, sections);
            if (composed is null)
            {
                outcome.Skipped.Add(new Skip(page.Name, "theCopyCouldNotBeMadeHidden"));
                continue;
            }
            if (!CopyPageFrontmatter.IsCertainlyHidden(composed, sections))
            {
                outcome.Skipped.Add(new Skip(page.Name,
                    CopyPageFrontmatter.BuilderAgrees(composed) ? "theCopyCouldNotBeMadeHidden" : "thePageIsWrittenInAWayPlantoirCannotBeSureOf"));
                continue;
            }
            BeforeWritingAPage?.Invoke(target);
            try
            {
                using (var stream = new FileStream(target, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                using (var writer = new StreamWriter(stream, new UTF8Encoding(false)))
                    writer.Write(composed);
            }
            catch (IOException e) when (e.HResult is ErrorFileExists or ErrorAlreadyExists)
            {
                // Appeared between the plan and the write: the ordinary skip, in the index's words.
                outcome.Skipped.Add(new Skip(page.Name, "aPageOfThatNameIsAlreadyHere"));
                continue;
            }
            catch
            {
                outcome.Skipped.Add(new Skip(page.Name, "thePageCouldNotBeWritten"));
                continue;
            }
            pageIndex.Add(PageKey(fileName));                                    // after EACH write (ruling 5)

            // Cleared BEFORE the read-back: a locked file could not be deleted,
            // and deleting it is what the guard has to be able to do.
            ReferenceLock.Clear(target);
            string back;
            try { back = File.ReadAllText(target); } catch { back = ""; }
            if (!CopyPageFrontmatter.IsCertainlyHidden(back, sections))
            {
                try { File.Delete(target); } catch { }
                if (File.Exists(target))
                {
                    outcome.MustBeRemoved.Add(target);
                    outcome.Skipped.Add(new Skip(page.Name, "theCopyIsStillThereAndMustBeRemoved"));
                }
                else outcome.Skipped.Add(new Skip(page.Name, "theCopyCouldNotBeMadeHidden"));
                continue;
            }
            if (unreadableBlock) outcome.CopiedHiddenBecauseUnreadable++;
            outcome.PagesCreated.Add(page.DestinationRelative);
        }

        ActivityTrail.Note(ActivityTrail.Event.PagesCopiedFromAnotherCourse, TrailLine(request, outcome));
        return outcome;
    }

    /// <summary>A test's racing creator: called with a page's path after every check and before its write.</summary>
    internal static Action<string>? BeforeWritingAPage { get; set; }

    /// <summary>Copies a file to a name that must not exist yet, by stream: no attribute and no access entry travels.</summary>
    private static void CreateExclusively(string from, string to)
    {
        using var input = new FileStream(from, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        using var output = new FileStream(to, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        input.CopyTo(output, 1 << 20);
    }

    /// <summary>
    /// The page with every reference to a renamed file pointed at its new name:
    /// a wikilink's name, an angle-bracketed destination written PLAIN, a
    /// Markdown or HTML destination with its spaces escaped as written.
    /// </summary>
    public static string PointedAt(string text, IReadOnlyDictionary<string, string> renamed)
    {
        if (renamed.Count == 0) return text;
        string Replace(string written, bool escapeSpaces)
        {
            string decoded;
            try { decoded = Uri.UnescapeDataString(written); } catch { decoded = written; }
            int slash = Math.Max(decoded.LastIndexOf('/'), decoded.LastIndexOf('\\'));
            string bare = decoded[(slash + 1)..];
            if (!renamed.TryGetValue(bare, out string? to)) return written;
            string head = written[..Math.Max(0, Math.Max(written.LastIndexOf('/'), written.LastIndexOf('\\')) + 1)];
            return head + (escapeSpaces ? to.Replace(" ", "%20") : to);
        }
        var ranges = MarkdownCode.NotALinkRanges(text);
        var edits = new List<(int Start, int Length, string Text)>();
        foreach (Match m in MarkdownCode.MatchesOutside(WikiLinks.TargetPattern, text, ranges))
        {
            string updated = Replace(m.Groups[2].Value, escapeSpaces: false);
            if (updated != m.Groups[2].Value) edits.Add((m.Groups[2].Index, m.Groups[2].Length, updated));
        }
        foreach (Match m in MarkdownCode.MatchesOutside(FolderPathRewriter.AngleLink, text, ranges))
        {
            string updated = Replace(m.Groups[2].Value, escapeSpaces: false);
            if (updated != m.Groups[2].Value) edits.Add((m.Groups[2].Index, m.Groups[2].Length, updated));
        }
        foreach (Match m in MarkdownCode.MatchesOutside(FolderPathRewriter.MarkdownLink, text, ranges))
        {
            string updated = Replace(m.Groups[2].Value, escapeSpaces: true);
            if (updated != m.Groups[2].Value) edits.Add((m.Groups[2].Index, m.Groups[2].Length, updated));
        }
        foreach (Match m in MarkdownCode.MatchesOutside(HtmlAttribute, text, ranges))
        {
            string updated = Replace(m.Groups["v"].Value, escapeSpaces: true);
            if (updated != m.Groups["v"].Value) edits.Add((m.Groups["v"].Index, m.Groups["v"].Length, updated));
        }
        var builder = new StringBuilder(text);
        foreach (var (start, length, replacement) in edits.OrderByDescending(e => e.Start))
            builder.Remove(start, length).Insert(start, replacement);
        return builder.ToString();
    }

    /// <summary>
    /// The trail line: from-folder, to course and folder, the counts, the
    /// backup's name — never a page's title or a picture's name.
    /// </summary>
    public static string TrailLine(Request request, Outcome outcome)
    {
        int pagesLeft = outcome.Skipped.Count(s => s.Reason != "aPictureCouldNotBeCopied");
        string line = $"copied from {request.Source.Code} into {ReferenceCourse.ShownCode(request.Destination)} " +
                      $"({request.Destination.Code}), {request.IntoFolder}: {outcome.PagesCreated.Count} pages created, " +
                      $"{pagesLeft} left alone; pictures and files: {outcome.MediaCreated.Count - outcome.MediaRenamed.Count} created, " +
                      $"{outcome.MediaReused.Count} reused, {outcome.MediaRenamed.Count} under a new name, " +
                      $"{outcome.MediaLeftAlone.Count} left alone; backup {outcome.BackupName}";
        if (outcome.CopiedHiddenBecauseUnreadable > 0)
            line += $"; {outcome.CopiedHiddenBecauseUnreadable} copied hidden because their settings could not be read";
        if (outcome.MustBeRemoved.Count > 0)
            line += $"; {outcome.MustBeRemoved.Count} could not be removed and must not be deployed";
        return line;
    }
}

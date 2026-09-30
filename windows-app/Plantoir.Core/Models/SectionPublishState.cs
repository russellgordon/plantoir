using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace Plantoir.Core.Models;

/// <summary>
/// The " — Edited" title-bar marker: whether any page a section uses, or
/// shares with other sections, has changed since that section last
/// published. Ported from mac's <c>SectionPublishState.swift</c> — see
/// documentation/05-build-pipeline.md, "The ' — Edited' marker", and
/// <c>contracts/app-rules.json</c> → <c>publishedFreshness</c>, which is the
/// authoritative case list both platforms run.
///
/// Nothing here reads file CONTENTS — only each file's size and modification
/// date, which is what makes it cheap enough to run whenever a window comes
/// to the front. That is also its one accepted false negative: a file
/// restored from a backup that preserves modification dates and whose size
/// happens to match reads as unchanged. Publishing is never blocked by the
/// marker, so a teacher who suspects it can simply publish.
/// </summary>
public static class SectionPublishState
{
    /// <summary>The stamp written at <c>.publish_state/section&lt;N&gt;.json</c>.</summary>
    public sealed class Stamp
    {
        [JsonPropertyName("fingerprint")]
        public string Fingerprint { get; set; } = "";

        [JsonPropertyName("publishedAt")]
        public DateTime PublishedAt { get; set; }

        [JsonPropertyName("destinations")]
        public List<string> Destinations { get; set; } = new();

        /// <summary>
        /// The rule the fingerprint was taken under (#358 / mac #330;
        /// <c>publishedFreshness.fingerprintRules.stampField</c>). Absent
        /// means rule 1: every stamp written before rule 2 existed.
        /// </summary>
        [JsonPropertyName("fingerprintRule")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public int? FingerprintRule { get; set; }
    }

    // ---- Fingerprint rules (#358 / mac #330) ---------------------------
    //
    // app-rules.json -> publishedFreshness.fingerprintRules. Rule 1 is every
    // counted file; rule 2 is rule 1 less the teacher's How I Teach page at a
    // reserved place (the top of the course, or the top of section<N>/),
    // which the build keeps off the site - so editing it must not mark a
    // section "— Edited". VERSIONED rather than changed in place, because the
    // fingerprint is a wire format three implementations hold byte for byte:
    // the stamp names its rule, and a reader computes under THAT rule. This
    // app, the scheduled wrapper (section_fingerprint.py --rule 2) and the
    // stamp move to rule 2 together; any one alone is a false "— Edited".

    /// <summary>The rule every new fingerprint is recorded under.</summary>
    public const int CurrentRule = 2;

    /// <summary>What a stamp without <c>fingerprintRule</c> means.</summary>
    public const int RuleWhenAbsent = 1;

    public static readonly IReadOnlyCollection<int> KnownRules = new[] { 1, 2 };

    /// <summary>
    /// <c>shared-rules.json → howITeachPage.matching</c>: the whole file name,
    /// after Unicode NFC, with ONLY A-Z folded — the same fold as
    /// <c>scripts/how_i_teach.py</c>, so the two cannot disagree about a name
    /// (a dotted capital I is a look-alike and counts).
    /// </summary>
    public static bool IsTheHowITeachPage(string fileName) =>
        string.Equals(AsciiFolded(fileName.Normalize(NormalizationForm.FormC)), "how i teach.md", StringComparison.Ordinal);

    private static string AsciiFolded(string name) =>
        new string(name.Select(c => c is >= 'A' and <= 'Z' ? (char)(c + 32) : c).ToArray());

    /// <summary>The top of the course, or the top of a <c>section&lt;N&gt;</c> folder (ASCII digits).</summary>
    public static bool IsReservedHowITeachPlace(string relativePath)
    {
        var parts = relativePath.Replace('\\', '/').Split('/');
        if (parts.Length == 1) return IsTheHowITeachPage(parts[0]);
        if (parts.Length != 2) return false;
        string folder = parts[0];
        string digits = folder.StartsWith("section", StringComparison.Ordinal) ? folder["section".Length..] : "";
        bool isASection = digits.Length > 0 && digits.All(c => c is >= '0' and <= '9');
        return isASection && IsTheHowITeachPage(parts[1]);
    }

    private static readonly HashSet<string> IgnoredFileNames = new(StringComparer.Ordinal)
    {
        ".DS_Store",
        "Thumbs.db",
        "course_config.backup.json",
    };

    private static readonly HashSet<string> IgnoredFolderNames = new(StringComparer.Ordinal)
    {
        "merged_output",
        "node_modules",
    };

    private static readonly Regex SectionFolderPattern = new(@"^section\d+$", RegexOptions.Compiled);

    /// <summary>True only for "section" + all-digits — "section3", not "sections" or "section3b".</summary>
    public static bool IsSectionFolderName(string name) => SectionFolderPattern.IsMatch(name);

    public static string StampPath(string courseDirectory, int sectionNumber) =>
        Path.Combine(courseDirectory, ".publish_state", $"section{sectionNumber}.json");

    // ---- What counts -------------------------------------------------

    /// <summary>
    /// Whether a REGULAR FILE at this course-relative path (forward-slash
    /// separated) is a genuine input to the section's built site.
    /// </summary>
    public static bool CountsTowardFingerprint(string relativePath, int sectionNumber, int rule = RuleWhenAbsent)
    {
        if (rule >= 2 && IsReservedHowITeachPlace(relativePath)) return false;
        var parts = relativePath.Split('/');
        if (parts.Any(part => part.StartsWith('.'))) return false;
        string fileName = parts[^1];
        if (IgnoredFileNames.Contains(fileName)) return false;
        if (fileName.EndsWith(".tmp", StringComparison.Ordinal)) return false;
        if (parts.Any(part => IgnoredFolderNames.Contains(part))) return false;
        string firstSegment = parts[0];
        if (IsSectionFolderName(firstSegment) &&
            !string.Equals(firstSegment, "section" + sectionNumber, StringComparison.Ordinal))
            return false;
        return true;
    }

    /// <summary>
    /// Whether a FOLDER at this course-relative path is worth descending
    /// into at all — the same rules minus the filename-specific ones.
    /// </summary>
    public static bool FolderCountsTowardFingerprint(string relativePath, int sectionNumber)
    {
        var parts = relativePath.Split('/');
        if (parts.Any(part => part.StartsWith('.'))) return false;
        if (parts.Any(part => IgnoredFolderNames.Contains(part))) return false;
        string firstSegment = parts[0];
        if (IsSectionFolderName(firstSegment) &&
            !string.Equals(firstSegment, "section" + sectionNumber, StringComparison.Ordinal))
            return false;
        return true;
    }

    // ---- Self-publishing exclusion ------------------------------------

    /// <summary>
    /// Course-relative subpaths to exclude from the fingerprint because the
    /// course publishes "to a folder on this computer" INSIDE its own course
    /// folder — see <c>publishedFreshness.selfPublishing</c>. Only local-
    /// folder destinations can ever resolve inside the course directory.
    /// </summary>
    public static List<string> SelfPublishingSubpaths(
        string courseDirectory, IEnumerable<CourseConfiguration.DeployDestination> destinations)
    {
        var result = new List<string>();
        string courseRoot = NormalizedFullPath(courseDirectory);
        foreach (var destination in destinations)
        {
            if (string.IsNullOrWhiteSpace(destination.Path)) continue;
            string destinationFull = NormalizedFullPath(destination.Path);
            if (!destinationFull.StartsWith(courseRoot + "/", StringComparison.OrdinalIgnoreCase) &&
                !string.Equals(destinationFull, courseRoot, StringComparison.OrdinalIgnoreCase))
                continue;
            string relative = destinationFull.Length <= courseRoot.Length
                ? ""
                : destinationFull[(courseRoot.Length + 1)..];
            if (relative.Length > 0) result.Add(relative);
        }
        return result;
    }

    private static string NormalizedFullPath(string path) =>
        Path.GetFullPath(Environment.ExpandEnvironmentVariables(path)).Replace('\\', '/').TrimEnd('/');

    /// <summary>
    /// Case-INSENSITIVE on purpose: NTFS is case-insensitive but case-
    /// preserving, so a destination path typed with different casing than
    /// the folder's actual on-disk name (<c>...\Site</c> against a folder
    /// physically named <c>site</c>) must still match, or a self-publishing
    /// course would permanently read as "— Edited". <see cref="Fingerprint"/>'s
    /// relative paths come from the enumerator's on-disk casing;
    /// <see cref="SelfPublishingSubpaths"/>'s come from the teacher's
    /// configured (typed) path — the two are not guaranteed to agree.
    /// </summary>
    public static bool IsExcluded(string relativePath, IReadOnlyList<string> excluded)
    {
        foreach (string candidate in excluded)
        {
            if (candidate.Length == 0) continue;
            if (string.Equals(relativePath, candidate, StringComparison.OrdinalIgnoreCase) ||
                relativePath.StartsWith(candidate + "/", StringComparison.OrdinalIgnoreCase))
                return true;
        }
        return false;
    }

    // ---- Fingerprint ----------------------------------------------------

    /// <summary>
    /// The section's fingerprint: everything on disk under
    /// <paramref name="courseDirectory"/> that is a genuine input to this
    /// section's site, as sorted lines of <c>path|size|modifiedMicroseconds</c>,
    /// SHA-256 hex. A wire format, not an implementation detail — must
    /// match the mac's algorithm byte for byte, including ordinal (not
    /// culture-aware) sorting.
    /// </summary>
    public static string Fingerprint(
        string courseDirectory, int sectionNumber, IReadOnlyList<string>? excludingRelativePaths = null,
        int rule = CurrentRule)
    {
        var excluded = excludingRelativePaths ?? Array.Empty<string>();
        var lines = new List<string>();
        Walk(courseDirectory, courseDirectory, sectionNumber, excluded, lines, hopsRemaining: 1, rule);
        lines.Sort(StringComparer.Ordinal);
        string joined = string.Join("\n", lines);
        byte[] hash = SHA256.HashData(Encoding.UTF8.GetBytes(joined));
        return Convert.ToHexStringLower(hash);
    }

    private static void Walk(
        string courseDirectory, string directory, int sectionNumber,
        IReadOnlyList<string> excluded, List<string> lines, int hopsRemaining, int rule)
    {
        IEnumerable<string> entries;
        try { entries = Directory.EnumerateFileSystemEntries(directory); }
        catch { return; }

        foreach (string entryPath in entries)
        {
            string name = Path.GetFileName(entryPath);
            if (name.StartsWith('.')) continue; // hidden entries are skipped wholesale

            string relative = RelativePath(courseDirectory, entryPath);
            if (IsExcluded(relative, excluded)) continue;

            bool isSymlink = IsSymlink(entryPath);

            if (isSymlink)
            {
                if (hopsRemaining <= 0) continue; // one hop only
                AppendSymlink(courseDirectory, entryPath, relative, sectionNumber, excluded, lines, rule);
                continue;
            }

            if (Directory.Exists(entryPath))
            {
                if (!FolderCountsTowardFingerprint(relative, sectionNumber)) continue;
                Walk(courseDirectory, entryPath, sectionNumber, excluded, lines, hopsRemaining, rule);
            }
            else if (File.Exists(entryPath))
            {
                if (!CountsTowardFingerprint(relative, sectionNumber, rule)) continue;
                AppendFileLine(lines, relative, entryPath);
            }
        }
    }

    /// <summary>
    /// Resolves a symlink by hand, ONE hop: a link to a file contributes its
    /// target's size/date under the LINK's own path; a link to a folder is
    /// walked (with no further link-following); a broken link contributes
    /// where it points, so repointing or removing it is visible.
    /// </summary>
    private static void AppendSymlink(
        string courseDirectory, string linkPath, string linkRelative, int sectionNumber,
        IReadOnlyList<string> excluded, List<string> lines, int rule)
    {
        string? target = null;
        try { target = File.ResolveLinkTarget(linkPath, returnFinalTarget: true)?.FullName; }
        catch { /* broken link — target below stays null */ }

        if (target is null || (!File.Exists(target) && !Directory.Exists(target)))
        {
            string destination = "";
            try { destination = new FileInfo(linkPath).LinkTarget ?? ""; } catch { /* best effort */ }
            lines.Add($"{linkRelative}|link|{destination}");
            return;
        }

        if (File.Exists(target))
        {
            if (!CountsTowardFingerprint(linkRelative, sectionNumber, rule)) return;
            AppendFileLine(lines, linkRelative, target);
            return;
        }

        // A link to a folder: walk it under the LINK's own path prefix, not
        // following any further symlink inside (hopsRemaining: 0).
        WalkUnderPrefix(target, target, linkRelative, sectionNumber, excluded, lines, rule);
    }

    private static void WalkUnderPrefix(
        string physicalRoot, string directory, string relativePrefix, int sectionNumber,
        IReadOnlyList<string> excluded, List<string> lines, int rule)
    {
        IEnumerable<string> entries;
        try { entries = Directory.EnumerateFileSystemEntries(directory); }
        catch { return; }

        foreach (string entryPath in entries)
        {
            string name = Path.GetFileName(entryPath);
            if (name.StartsWith('.')) continue;

            string innerRelative = RelativePath(physicalRoot, entryPath);
            string relative = relativePrefix + "/" + innerRelative;
            if (IsExcluded(relative, excluded)) continue;

            if (IsSymlink(entryPath)) continue; // one hop total — do not follow a link inside a linked folder

            if (Directory.Exists(entryPath))
            {
                if (!FolderCountsTowardFingerprint(relative, sectionNumber)) continue;
                WalkUnderPrefix(physicalRoot, entryPath, relativePrefix, sectionNumber, excluded, lines, rule);
            }
            else if (File.Exists(entryPath))
            {
                if (!CountsTowardFingerprint(relative, sectionNumber, rule)) continue;
                AppendFileLine(lines, relative, entryPath);
            }
        }
    }

    private static void AppendFileLine(List<string> lines, string relativePath, string physicalPath)
    {
        var info = new FileInfo(physicalPath);
        long size = info.Length;
        // Truncated microseconds since epoch, matching the mac's
        // `modified * 1_000_000` cast to Int. DateTime ticks are 100ns
        // units, so dividing by 10 (floor) is the same truncation.
        long unixEpochTicks = DateTime.UnixEpoch.Ticks;
        long microseconds = (info.LastWriteTimeUtc.Ticks - unixEpochTicks) / 10;
        lines.Add($"{relativePath}|{size}|{microseconds}");
    }

    /// <summary>
    /// Whether the entry at this path is itself a reparse point (symlink or
    /// junction). `.NET`'s directory enumeration neither follows a symlink
    /// nor reports it as a regular file, so this has to be checked by hand —
    /// same trap as `FileManager` on the mac, see "Symlinks" in
    /// documentation/05-build-pipeline.md.
    /// </summary>
    private static bool IsSymlink(string path)
    {
        try { return File.GetAttributes(path).HasFlag(FileAttributes.ReparsePoint); }
        catch { return false; }
    }

    private static string RelativePath(string root, string fullPath) =>
        Path.GetRelativePath(root, fullPath).Replace('\\', '/');

    // ---- Stamp read/write -------------------------------------------------

    private static readonly JsonSerializerOptions WriteOptions = new()
    {
        WriteIndented = true,
    };

    public static Stamp? ReadStamp(string courseDirectory, int sectionNumber)
    {
        string path = StampPath(courseDirectory, sectionNumber);
        try
        {
            string json = File.ReadAllText(path);
            return JsonSerializer.Deserialize<Stamp>(json);
        }
        catch { return null; } // missing or unreadable == never published, never "edited"
    }

    /// <summary>
    /// Writes the stamp atomically (temp file + move). Returns false, and
    /// never throws, on failure — a write that fails must not crash a
    /// publish that otherwise succeeded; the window simply keeps saying
    /// " — Edited" and that failure is logged to the activity trail instead.
    /// </summary>
    public static bool RecordPublish(
        string courseDirectory, int sectionNumber, string fingerprint,
        IReadOnlyList<string> destinations, DateTime? at = null, int rule = CurrentRule)
    {
        try
        {
            string dir = Path.Combine(courseDirectory, ".publish_state");
            Directory.CreateDirectory(dir);
            var stamp = new Stamp
            {
                Fingerprint = fingerprint,
                PublishedAt = (at ?? DateTime.UtcNow),
                Destinations = destinations.ToList(),
                FingerprintRule = rule,
            };
            string json = JsonSerializer.Serialize(stamp, WriteOptions);
            string finalPath = StampPath(courseDirectory, sectionNumber);
            string tempPath = finalPath + ".tmp";
            File.WriteAllText(tempPath, json);
            File.Move(tempPath, finalPath, overwrite: true);
            return true;
        }
        catch { return false; }
    }

    /// <summary>
    /// A section with no readable stamp has never published (or predates
    /// this feature) and is never shown as edited — a marker that is on for
    /// every new course from the moment it is created is one teachers learn
    /// to ignore.
    /// </summary>
    public static bool HasUnpublishedEdits(
        string courseDirectory, int sectionNumber, IReadOnlyList<string>? excludingRelativePaths = null)
    {
        var stamp = ReadStamp(courseDirectory, sectionNumber);
        if (stamp is null) return false;
        // Computed under the rule the STAMP names (absent = 1); a rule this
        // copy does not know counts as edited — nothing that cannot be read
        // may claim a section is up to date.
        int rule = stamp.FingerprintRule ?? RuleWhenAbsent;
        if (!KnownRules.Contains(rule)) return true;
        string current = Fingerprint(courseDirectory, sectionNumber, excludingRelativePaths, rule);
        return !string.Equals(stamp.Fingerprint, current, StringComparison.Ordinal);
    }

    /// <summary>The window's title-bar text only — never a sentence naming the section.</summary>
    public static string WindowTitle(string @base, bool hasUnpublishedEdits) =>
        hasUnpublishedEdits ? @base + " — Edited" : @base;
}

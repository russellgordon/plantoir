using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;

namespace Plantoir.Core.Models;

/// <summary>
/// The teacher's "How I Teach" page (#340, mac #209): one per course,
/// <c>How I Teach.md</c> at the top of the course folder, saying how the
/// course is taught. Read and written by an outside assistant through
/// <c>plantoir-mcp</c>; NEVER on the website — and that is kept by the BUILD
/// (shared Python, <c>scripts/how_i_teach.py</c>) by the page's LOCATION,
/// not by <c>publish: false</c>, because a later <c>publishForSection&lt;N&gt;:
/// true</c> beats it. The rule, with what was rejected, is
/// <c>contracts/shared-rules.json</c> → <c>howITeachPage</c>.
/// </summary>
/// <remarks>
/// A port of the mac's <c>HowITeachPage.swift</c>, deliberately close to it:
/// the read, the plan and the write on both platforms must agree about the
/// same bytes (<c>planAndWriteAgree</c>, <c>emptyPageIsNotWritten</c>).
/// </remarks>
public static class HowITeachPage
{
    public const string FileName = "How I Teach.md";
    public const string Title = "How I Teach";

    /// <summary><c>howITeachPage.tools.mostCharacters</c>.</summary>
    public const int MostCharacters = 8000;

    /// <summary>What a new page opens with. Not the guarantee — the location is.</summary>
    public const string NewPageSettings = "---\npublish: false\n---\n";

    private static readonly UTF8Encoding StrictUtf8 = new(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true);

    /// <summary>
    /// NFC, then ONLY A–Z folded to a–z (<c>howITeachPage.matching</c>).
    /// Not <c>ToLowerInvariant</c>: that folds the Kelvin sign and friends,
    /// and the contract pins look-alikes as NOT the page.
    /// </summary>
    public static string Folded(string name)
    {
        var builder = new StringBuilder();
        foreach (char c in name.Normalize(NormalizationForm.FormC))
            builder.Append(c is >= 'A' and <= 'Z' ? (char)(c + 32) : c);
        return builder.ToString();
    }

    /// <summary>Whether one file NAME is the page. Nothing is trimmed.</summary>
    public static bool IsTheName(string name) => Folded(name) == Folded(FileName);

    /// <summary>Whether a title a caller used means the page — any capitals, with or without .md.</summary>
    public static bool IsItsTitle(string title)
    {
        string wanted = Folded(title.Trim());
        return wanted == Folded(Title) || wanted == Folded(FileName);
    }

    /// <summary><c>section</c> followed by one or more ASCII digits.</summary>
    public static bool IsASectionFolderName(string name) =>
        name.StartsWith("section", StringComparison.Ordinal) && name.Length > 7 &&
        name[7..].All(c => c is >= '0' and <= '9');

    /// <summary>
    /// Whether a path relative to the COURSE folder is one of the two places
    /// the build keeps off the site: the top of the course, or the top of a
    /// <c>section&lt;N&gt;/</c> folder.
    /// </summary>
    public static bool IsAtAReservedPlace(string relativePath)
    {
        var parts = relativePath.Replace('\\', '/').Split('/');
        return parts.Length switch
        {
            1 => IsTheName(parts[0]),
            2 => IsASectionFolderName(parts[0]) && IsTheName(parts[1]),
            _ => false,
        };
    }

    /// <summary>Whether a full path inside a course is the page at a reserved place.</summary>
    public static bool IsTheHowITeachPage(string fullPath, string courseDirectory) =>
        IsAtAReservedPlace(Path.GetRelativePath(courseDirectory, fullPath));

    /// <summary>
    /// The course's page, found by LISTING the course folder, so the teacher's
    /// own spelling ("how i teach.md") is what is read and replaced. Null when
    /// there is none; the first in ordinal name order when several exist.
    /// </summary>
    public static string? ExistingPath(string courseDirectory)
    {
        try
        {
            return Directory.EnumerateFiles(courseDirectory)
                .Where(path => IsTheName(Path.GetFileName(path)))
                .OrderBy(path => Path.GetFileName(path), StringComparer.Ordinal)
                .FirstOrDefault();
        }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
    }

    /// <summary>
    /// A page's bytes as text, KEEPING a leading byte-order mark as U+FEFF —
    /// <c>File.ReadAllText</c> drops it, and a replaced page's settings must
    /// be kept byte for byte. Null when the bytes are not UTF-8.
    /// </summary>
    public static string? TextOf(byte[] bytes)
    {
        try { return StrictUtf8.GetString(bytes); }
        catch (DecoderFallbackException) { return null; }
    }

    /// <summary>First eight lowercase hex digits of the SHA-256 of the bytes on disk, BOM included.</summary>
    public static string MarkOf(byte[] bytes) =>
        Convert.ToHexString(SHA256.HashData(bytes))[..8].ToLowerInvariant();

    /// <summary>The page has WORDS after its settings block (<c>emptyPageIsNotWritten</c>).</summary>
    public static bool HasWords(string text) => Body(text).TrimStart('﻿').Trim().Length > 0;

    /// <summary>Written: has words, or cannot be read as text (never taken to be empty).</summary>
    public static bool IsWritten(string path)
    {
        byte[] bytes;
        try { bytes = File.ReadAllBytes(path); }
        catch { return true; }
        return TextOf(bytes) is not { } text || HasWords(text);
    }

    /// <summary>The course's page when it has been written, else null — what list_courses asks.</summary>
    public static string? WrittenPath(string courseDirectory) =>
        ExistingPath(courseDirectory) is { } path && IsWritten(path) ? path : null;

    public static int WordCount(string text) =>
        Body(text).Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)
                  .Count(piece => piece.Trim('﻿').Length > 0);

    public static string Body(string text) =>
        SettingsBlock(text) is { } block ? text[block.Length..] : text;

    /// <summary>
    /// A leading BOM, an opening <c>---</c> line, and everything through the
    /// next <c>---</c> line and its ending — or null when there is none, or
    /// it never closes. LF or CRLF.
    /// </summary>
    public static string? SettingsBlock(string text)
    {
        var lines = LinesKeepingTheirEndings(text);
        if (lines.Count == 0) return null;
        string first = lines[0];
        string mark = "";
        if (first.StartsWith('﻿')) { mark = "﻿"; first = first[1..]; }
        if (!IsAFence(first)) return null;
        var block = new StringBuilder(mark + first);
        for (int i = 1; i < lines.Count; i++)
        {
            block.Append(lines[i]);
            if (IsAFence(lines[i])) return block.ToString();
        }
        return null;
    }

    /// <summary>Whether text to be SAVED opens with a fence, after a BOM and blank lines.</summary>
    public static bool OpensWithAFence(string text)
    {
        string remaining = text.TrimStart('﻿');
        foreach (string line in LinesKeepingTheirEndings(remaining))
        {
            if (line.Trim().Length == 0) continue;
            return IsAFence(line);
        }
        return false;
    }

    public static string Trimmed(string text) => text.Trim();

    /// <summary><c>howITeachPage.tools.newPageBytes</c>.</summary>
    public static string NewPageText(string text) => NewPageSettings + "\n" + Trimmed(text) + "\n";

    /// <summary>The existing settings block kept byte for byte; only the body replaced.</summary>
    public static string ReplacedPageText(string existing, string text)
    {
        if (SettingsBlock(existing) is not { } block) return Trimmed(text) + "\n";
        string lineEnd = block.EndsWith("\r\n", StringComparison.Ordinal) ? "\r\n" : "\n";
        string kept = block.EndsWith('\n') ? block : block + lineEnd;
        return kept + lineEnd + Trimmed(text) + lineEnd;
    }

    public static string TrailLineForARead(int? words, bool cutShort, bool empty = false)
    {
        if (empty) return "an outside assistant found an empty How I Teach page";
        if (words is not { } count) return "an outside assistant found no How I Teach page yet";
        return $"an outside assistant read the How I Teach page ({Counted(count)}" +
               (cutShort ? ", more than one answer carries" : "") + ")";
    }

    public static string TrailLineForAWrite(int? wordsBefore, int wordsAfter, string? backupName)
    {
        string line = wordsBefore is { } before
            ? $"an outside assistant replaced the How I Teach page ({before} → {Counted(wordsAfter)})"
            : $"an outside assistant wrote a new How I Teach page ({Counted(wordsAfter)})";
        return line + (backupName is not null
            ? $", after backing up the course as {backupName}"
            : ", with no backup, because one could not be made");
    }

    private static string Counted(int words) => words == 1 ? "1 word" : $"{words} words";

    private static bool IsAFence(string line) => line.TrimEnd('\n', '\r', ' ', '\t') == "---";

    private static List<string> LinesKeepingTheirEndings(string text)
    {
        var lines = new List<string>();
        int start = 0;
        for (int i = 0; i < text.Length; i++)
        {
            if (text[i] != '\n') continue;
            lines.Add(text[start..(i + 1)]);
            start = i + 1;
        }
        if (start < text.Length) lines.Add(text[start..]);
        return lines;
    }
}

/// <summary>
/// A How I Teach page the build kept off the website although the course's
/// settings had LISTED it (<c>howITeachPage.keptOffMarker</c>). Read like
/// <see cref="PagesDatedByTheBuild"/>, from the same two readers.
/// </summary>
public sealed record HowITeachKeptOffReport(string Course, int Section, IReadOnlyList<string> Pages)
{
    public const string Marker = "PLANTOIR_KEPT_OFF:";

    /// <summary><c>howITeachPage.keptOffTrailLine</c>, worded as the mac words it.</summary>
    public string TrailSentence =>
        $"the build kept {Pages.Count} {(Pages.Count == 1 ? "page" : "pages")} named How I Teach off the website " +
        $"that the course's settings had listed for it: {string.Join(", ", Pages)}";

    public static bool IsMarkerLine(string line) => line.Contains(Marker, StringComparison.Ordinal);

    public static HowITeachKeptOffReport? Parse(string? line)
    {
        if (string.IsNullOrWhiteSpace(line)) return null;
        int at = line.IndexOf(Marker, StringComparison.Ordinal);
        if (at < 0) return null;
        try
        {
            if (System.Text.Json.Nodes.JsonNode.Parse(line[(at + Marker.Length)..].Trim())
                is not System.Text.Json.Nodes.JsonObject obj) return null;
            string course = obj["course"]?.GetValue<string>() ?? "";
            int section = obj["section"]?.GetValue<int>() ?? 0;
            var pages = (obj["pages"] as System.Text.Json.Nodes.JsonArray)?
                .Select(page => page?.GetValue<string>() ?? "")
                .Where(page => page.Length > 0).ToList() ?? new List<string>();
            if (course.Length == 0 || section <= 0 || pages.Count == 0) return null;
            return new HowITeachKeptOffReport(course, section, pages);
        }
        catch (Exception error) when (error is System.Text.Json.JsonException or InvalidOperationException or FormatException)
        {
            return null;
        }
    }

    public static IReadOnlyList<HowITeachKeptOffReport> ReportsIn(IEnumerable<string> lines) =>
        lines.Select(Parse).Where(report => report is not null).Select(report => report!).ToList();
}

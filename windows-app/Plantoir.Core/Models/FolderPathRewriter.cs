using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;

namespace Plantoir.Core.Models;

/// <summary>
/// Pointing every link that names a FOLDER at that folder's new name.
///
/// <para><b>Most links need nothing done to them, and that is the important
/// fact.</b> Obsidian resolves <c>[[Quiz 1]]</c> by searching the vault, so
/// moving the folder it lives in leaves the link working. Renaming a folder is
/// therefore a far smaller risk than renaming a page, and is why this could be
/// built without an undo: only QUALIFIED links break, and those are what this
/// handles.</para>
///
/// <para><b>What is handled</b> — <c>[[Tasks/Quiz 1]]</c> and
/// <c>![[Tasks/diagram.png]]</c>; a full vault path such as
/// <c>[[ICS3U/section1/Tasks/Quiz 1]]</c>, so ANY segment is matched and not
/// only the first; <c>[[Tasks/Quiz 1#Marking|the quiz]]</c>, whose alias and
/// heading are the teacher's own words and are never touched; and Markdown
/// style, <c>[the quiz](Tasks/Quiz%201.md)</c>, with or without percent-encoded
/// spaces and with a leading <c>./</c>.</para>
///
/// <para><b>What is NOT handled, on purpose.</b> A segment is replaced only
/// when it matches the WHOLE folder name: a folder called <c>Tasks</c> does not
/// rewrite <c>Extra Tasks/</c>, and a page whose own name is <c>Tasks.md</c> is
/// left alone, because the match stops before the last <c>/</c> and a file name
/// is never a candidate. A rewriter that matched substrings would rename
/// folders the teacher never touched.</para>
///
/// <para><b>Links that point outside the course are refused explicitly</b>, and
/// NOT because "nothing in them is a segment of this course's tree" — that
/// reasoning is exactly wrong. <c>https://example.com/Tasks/handout.pdf</c> has
/// <c>Tasks</c> sitting in it as an ordinary segment, and the walk below is
/// blind to what a path MEANS, so without the refusal a rename would repoint
/// that link at a page on somebody else's website. Found by adversarial review
/// on the mac, 2026-09-01, and inherited here as a rule rather than as
/// code.</para>
/// </summary>
public static class FolderPathRewriter
{
    /// <summary>
    /// An optional <c>!</c>, the opening brackets, then the target — which runs
    /// up to the first <c>]</c>, <c>|</c> or <c>#</c>, so an alias, a heading
    /// and a block reference stay where they are.
    /// </summary>
    private static readonly Regex WikiLink =
        new(@"(!?\[\[)([^\]|#]+)", RegexOptions.Compiled);

    /// <summary>
    /// A Markdown link or embed's target: everything between <c>](</c> and the
    /// closing bracket. Titles (<c>](path "title")</c>) are left in place
    /// because the path is taken only up to the first space.
    /// </summary>
    private static readonly Regex MarkdownLink =
        new(@"(\]\()([^)\s]+)", RegexOptions.Compiled);

    /// <summary>A URL scheme: http:, https:, mailto:, obsidian: and friends.</summary>
    private static readonly Regex Scheme =
        new(@"^[A-Za-z][A-Za-z0-9+.\-]*:", RegexOptions.Compiled);

    /// <summary>
    /// Every link in <paramref name="text"/> that names <paramref name="oldName"/>
    /// as a folder, pointed at <paramref name="newName"/>.
    /// </summary>
    public static string Rewritten(string text, string oldName, string newName)
    {
        if (string.IsNullOrEmpty(text)) return text;
        if (string.IsNullOrWhiteSpace(oldName) || string.IsNullOrWhiteSpace(newName)) return text;
        if (oldName.Equals(newName, StringComparison.Ordinal)) return text;

        string once = WikiLink.Replace(text, match => Replaced(match, oldName, newName));
        return MarkdownLink.Replace(once, match => Replaced(match, oldName, newName));
    }

    /// <summary>
    /// How many links point INTO this folder by name — what the "and N pages
    /// had links pointing into it" sentence counts. Only qualified links count;
    /// a bare <c>[[Quiz 1]]</c> does not point into anything.
    /// </summary>
    public static int Count(string text, string folderName)
    {
        if (string.IsNullOrEmpty(text) || string.IsNullOrWhiteSpace(folderName)) return 0;
        int found = 0;
        foreach (Regex pattern in new[] { WikiLink, MarkdownLink })
            foreach (Match match in pattern.Matches(text))
                if (NamesTheFolder(match.Groups[2].Value, folderName))
                    found++;
        return found;
    }

    private static string Replaced(Match match, string oldName, string newName)
    {
        string opening = match.Groups[1].Value;
        string target = match.Groups[2].Value;
        return opening + RewrittenTarget(target, oldName, newName);
    }

    /// <summary>
    /// One link target, with any SEGMENT naming the folder replaced.
    ///
    /// <para>The last segment is the page's own file name and is never a
    /// candidate, so a page called <c>Tasks.md</c> survives a rename of the
    /// folder <c>Tasks</c>.</para>
    /// </summary>
    private static string RewrittenTarget(string target, string oldName, string newName)
    {
        if (PointsOutsideTheCourse(target)) return target;

        var segments = new List<string>(target.Split('/'));
        if (segments.Count < 2) return target;   // nothing but a file name

        bool changed = false;
        for (int i = 0; i < segments.Count - 1; i++)
        {
            if (!SegmentIs(segments[i], oldName)) continue;
            // Keep the spelling style the link already used: a percent-encoded
            // segment stays encoded, so a link Obsidian wrote in Markdown style
            // is still a link Obsidian can follow.
            segments[i] = WasEncoded(segments[i]) ? Uri.EscapeDataString(newName) : newName;
            changed = true;
        }
        return changed ? string.Join("/", segments) : target;
    }

    private static bool NamesTheFolder(string target, string folderName)
    {
        if (PointsOutsideTheCourse(target)) return false;
        var segments = target.Split('/');
        for (int i = 0; i < segments.Length - 1; i++)
            if (SegmentIs(segments[i], folderName)) return true;
        return false;
    }

    /// <summary>
    /// Whether this path segment IS the folder — the whole segment, never a
    /// part of it, compared with percent-encoding undone and case ignored.
    /// </summary>
    private static bool SegmentIs(string segment, string folderName)
    {
        if (segment.Length == 0) return false;
        if (segment == "." || segment == "..") return false;
        return Decoded(segment).Equals(folderName, StringComparison.OrdinalIgnoreCase);
    }

    private static bool WasEncoded(string segment) => !Decoded(segment).Equals(segment, StringComparison.Ordinal);

    private static string Decoded(string segment)
    {
        if (!segment.Contains('%')) return segment;
        try { return Uri.UnescapeDataString(segment); }
        catch (UriFormatException) { return segment; }
    }

    /// <summary>
    /// A target this rename has no business touching: anything with a URL
    /// scheme, and anything absolute.
    ///
    /// <para>A relative path with a leading <c>./</c> is NOT outside the course
    /// and is still rewritten.</para>
    /// </summary>
    private static bool PointsOutsideTheCourse(string target)
    {
        if (target.Length == 0) return true;
        if (target.StartsWith("/", StringComparison.Ordinal)) return true;
        if (target.StartsWith(@"\", StringComparison.Ordinal)) return true;
        // A Windows drive letter reads as a one-character scheme, so it is
        // already caught below — but say so explicitly rather than relying on
        // that coincidence.
        if (target.Length >= 2 && char.IsLetter(target[0]) && target[1] == ':') return true;
        return Scheme.IsMatch(target);
    }
}

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
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
    /// The characters that go into a link AS THEY STAND when escaping runs.
    /// Everything else is percent-encoded as UTF-8.
    ///
    /// <para><b>This set was measured against the built site, not reasoned
    /// about, and <c>Uri.EscapeDataString</c> is the wrong tool for it.</b>
    /// Quartz resolves an internal link with JavaScript's <c>decodeURI</c>
    /// (<c>quartz/util/path.ts</c>, <c>transformInternalLink</c>), and
    /// <c>decodeURI</c> deliberately leaves the reserved set
    /// <c>; / ? : @ &amp; = + $ , #</c> STILL ENCODED — that is what
    /// distinguishes it from <c>decodeURIComponent</c>. <c>sluggify</c>, in the
    /// same file, then maps <c>&amp;</c> to <c>-and-</c> and <c>%</c> to
    /// <c>-percent</c> when it builds the address. So a folder called
    /// "Tasks &amp; Quizzes" written as <c>Tasks%20%26%20Quizzes</c> decodes to
    /// <c>Tasks %26 Quizzes</c> and slugs to <c>Tasks--percent26-Quizzes</c>,
    /// while the real folder slugs to <c>Tasks--and--Quizzes</c>: a 404 for
    /// students, and invisible to the teacher, because Obsidian decodes
    /// <c>%26</c> perfectly well. <c>Uri.EscapeDataString</c> keeps only
    /// <c>A-Za-z0-9-._~</c>, so it produces exactly that — and over-encodes
    /// <c>,</c> the same way, which is the one that will actually happen here:
    /// "Unit 1, Day 2" is this project's own naming pattern.</para>
    ///
    /// <para>The set is what JavaScript's <c>encodeURI</c> leaves alone, minus
    /// three — <c>(</c> and <c>)</c> close a destination, <c>#</c> starts a
    /// heading — and minus <c>/</c> and <c>:</c>, which the rename sheet
    /// refuses anyway. <c>?</c> IS in it: <c>sluggify</c> STRIPS a question
    /// mark from the real folder's name, so "Why Not?" slugs to
    /// <c>Why-Not</c>, an unescaped <c>Why%20Not?</c> slugs to the same and
    /// resolves, and the escaped <c>Why%20Not%3F</c> slugs to
    /// <c>Why-Not-percent3F</c> and 404s. A folder name may not contain a
    /// question mark on Windows, but this is a pure string transform and the
    /// rule is shared.</para>
    ///
    /// <para><b>Nothing is encoded unless escaping RUNS</b> — see
    /// <see cref="WouldBreakAMarkdownTarget"/>, or a segment that arrived
    /// percent-encoded. "Café" goes into a link as "Café"; "Café Notes" goes in
    /// as <c>Caf%C3%A9%20Notes</c>. Both resolve, and reading this set as
    /// "always encode everything else" is the way the two apps would write
    /// different text for the same rename.</para>
    ///
    /// <para>Written down once, in
    /// <c>contracts/shared-rules.json</c> →
    /// <c>specialNames.renameFolder.linkRewriting.escapingSet.leaveUnescaped</c>,
    /// and pinned character-for-character against this constant by
    /// <c>FolderPathRewriterTests</c>. Change it there, not here.</para>
    /// </summary>
    internal const string CharactersThatSurviveQuartzUndecoded =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789;,@&=+$-_.!~*'?";

    /// <summary>
    /// Every link in <paramref name="text"/> that names <paramref name="oldName"/>
    /// as a folder, pointed at <paramref name="newName"/>.
    /// </summary>
    public static string Rewritten(string text, string oldName, string newName)
    {
        if (string.IsNullOrEmpty(text)) return text;
        if (string.IsNullOrWhiteSpace(oldName) || string.IsNullOrWhiteSpace(newName)) return text;
        if (oldName.Equals(newName, StringComparison.Ordinal)) return text;

        string once = WikiLink.Replace(text, match => Replaced(match, oldName, newName, markdown: false));
        return MarkdownLink.Replace(once, match => Replaced(match, oldName, newName, markdown: true));
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

    private static string Replaced(Match match, string oldName, string newName, bool markdown)
    {
        string opening = match.Groups[1].Value;
        string target = match.Groups[2].Value;
        return opening + RewrittenTarget(target, oldName, newName, markdown);
    }

    /// <summary>
    /// One link target, with any SEGMENT naming the folder replaced.
    ///
    /// <para>The last segment is the page's own file name and is never a
    /// candidate, so a page called <c>Tasks.md</c> survives a rename of the
    /// folder <c>Tasks</c>.</para>
    /// </summary>
    private static string RewrittenTarget(string target, string oldName, string newName, bool markdown)
    {
        if (PointsOutsideTheCourse(target)) return target;

        var segments = new List<string>(target.Split('/'));
        if (segments.Count < 2) return target;   // nothing but a file name

        bool changed = false;
        for (int i = 0; i < segments.Count - 1; i++)
        {
            if (!SegmentIs(segments[i], oldName)) continue;
            segments[i] = Spelled(newName, wasEncoded: WasEncoded(segments[i]), markdown: markdown);
            changed = true;
        }
        return changed ? string.Join("/", segments) : target;
    }

    /// <summary>
    /// How the new name is spelled inside this particular link.
    ///
    /// <para>Keeping the style the link already used is the obvious rule and is
    /// WRONG for Markdown links on its own. A Markdown destination ends at the
    /// first space — the pattern above is literally <c>[^)\s]+</c> — so
    /// renaming <c>Tasks</c> to <c>All Tasks</c> turned
    /// <c>[q](Tasks/Quiz%201.md)</c> into <c>[q](All Tasks/Quiz%201.md)</c>,
    /// which neither Obsidian nor Quartz can follow. The rename would have
    /// broken every Markdown-style link into the folder, in a teacher's own
    /// pages, silently. Found by adversarial review 2026-09-06 and reproduced
    /// before being fixed; the mac had the identical rule and the identical
    /// defect, and took this fix unchanged.</para>
    ///
    /// <para>So: in a Markdown link, encode when the NEW name needs it,
    /// whatever the old one looked like. In a wikilink, keep the old style —
    /// <c>[[All Tasks/Quiz 1]]</c> is exactly how Obsidian writes a wikilink
    /// with a space in it, and escaping there would be the mirror-image
    /// mistake.</para>
    ///
    /// <para><b>Both branches encode the same way, and that is not an
    /// accident.</b> The second one — a segment that ARRIVED percent-encoded
    /// goes back percent-encoded, so a link a teacher already had keeps the
    /// shape it had — is the older of the two rules and was kept rather than
    /// replaced. It used <c>Uri.EscapeDataString</c> too, which is why fixing
    /// only the first line would have left a name mis-spelled whenever the old
    /// segment happened to arrive encoded. The contract has a case for each
    /// branch.</para>
    /// </summary>
    private static string Spelled(string newName, bool wasEncoded, bool markdown)
    {
        if (markdown && WouldBreakAMarkdownTarget(newName)) return PercentEncoded(newName);
        return wasEncoded ? PercentEncoded(newName) : newName;
    }

    /// <summary>
    /// The name percent-encoded so that Quartz gets the folder's REAL name back
    /// out of it. See <see cref="CharactersThatSurviveQuartzUndecoded"/> for why
    /// the allowed set is neither <c>Uri.EscapeDataString</c>'s nor the whole
    /// reserved set — both were tried on the mac and both are wrong here.
    ///
    /// <para>The walk is over UTF-8 BYTES rather than characters, deliberately.
    /// A character loop would have to encode each <c>char</c> on its own, which
    /// splits a surrogate pair and produces two invalid sequences for one
    /// letter. Every byte at or above <c>0x80</c> is outside the allowed set by
    /// construction — the set is all ASCII — so testing the byte is exact.</para>
    ///
    /// <para>Upper-case hex, matching what the contract's cases expect and what
    /// the mac's <c>addingPercentEncoding</c> writes.</para>
    /// </summary>
    private static string PercentEncoded(string name)
    {
        var built = new StringBuilder(name.Length);
        foreach (byte value in Encoding.UTF8.GetBytes(name))
        {
            char character = (char)value;
            if (value < 0x80 && CharactersThatSurviveQuartzUndecoded.IndexOf(character) >= 0)
                built.Append(character);
            else
                built.Append('%').Append(value.ToString("X2", CultureInfo.InvariantCulture));
        }
        return built.ToString();
    }

    /// <summary>
    /// Whether this name, dropped into a Markdown link destination unescaped,
    /// would end the destination early or misparse it.
    ///
    /// <para>Whitespace and round brackets, and nothing else. <b>A lone
    /// <c>%</c> was on this list for an afternoon and was taken back off</b>,
    /// so do not put it back. The argument for it was that Quartz resolves an
    /// internal link with JavaScript's <c>decodeURI</c> and
    /// <c>decodeURI("10%/Quiz.md")</c> throws — true of <c>decodeURI</c> on its
    /// own, and irrelevant here, because Quartz never sees a bare <c>%</c>: the
    /// Markdown parser normalises it to <c>%25</c> on the way to HTML long
    /// before the link transformer runs. Measured in the running image
    /// 2026-09-06, <c>[b](Top10%/Quiz.md)</c> arrives as
    /// <c>Top10%25/Quiz.md</c>. A <c>%</c> is still ENCODED whenever escaping
    /// runs for another reason, which is what stops "Top 100%" becoming the
    /// half-escaped <c>Top%20100%</c>.</para>
    /// </summary>
    private static bool WouldBreakAMarkdownTarget(string name)
    {
        foreach (char character in name)
            if (char.IsWhiteSpace(character) || character == '(' || character == ')') return true;
        return false;
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

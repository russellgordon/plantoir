using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace Plantoir.Core.Assist;

/// <summary>
/// "What does Unit 2, Day 3 link to?" — the ninth parsed family, answered in
/// CODE (#305 / mac #167; <c>assist-cases.json</c> → <c>linksQuestion</c>).
/// </summary>
/// <param name="Page">The title to look up, sliced from what the teacher TYPED with one pair of quotes taken off.</param>
/// <param name="AsTyped">For "the X page": the whole phrase, tried only when <paramref name="Page"/> finds nothing.</param>
/// <param name="OnlyIfAPageIsCalled">"the quiz", "The Water Cycle": answered in code only when the section has a page called that; otherwise the model.</param>
/// <param name="OtherCourse">The sentence named ANOTHER course: refused in code, nothing read.</param>
public sealed record LinksQuestionMatch(string? Page, string? AsTyped = null, bool OnlyIfAPageIsCalled = false,
                                        string? OtherCourse = null);

public sealed partial record AssistCardCommand
{
    /// <summary>
    /// Read a links question against the window it was typed in.
    /// </summary>
    /// <remarks>
    /// <para><b>Why in code.</b> Measured 2026-09-25 on the mac, both tiers,
    /// the app's own flags/body/prompt: "What does Unit 2, Day 3 link to?"
    /// reached <c>read_page</c> 0 times in 84 on BOTH assistants, and on the
    /// smaller one "Which pages does Unit 2, Day 3 link to?" became a
    /// <c>publish_pages</c> plan 31 times in 84 — a write, for a read-only
    /// question. A sentence in <c>read_page</c>'s description was REJECTED: it
    /// moves the tool surface both apps were measured against.</para>
    ///
    /// <para><b>A place</b> may stand before "link to" or after it, at most
    /// once, and is read only when it is THIS window's; another course is
    /// refused (a card binds the window's course unconditionally, so answering
    /// would read this course's page and call it the other's); another section
    /// goes to the model. "in &lt;word&gt;" with no section is a course only
    /// when it is this window's or a code that EXISTS in the shipped course
    /// lists — <paramref name="isACourseCode"/> — so "in Lab01" is part of a
    /// page's name. With no window, any place falls through.</para>
    /// </remarks>
    /// <returns>Null when the sentence is not this family, or must go to the model.</returns>
    public static LinksQuestionMatch? LinksQuestion(string message, string? windowCourse = null, int? windowSection = null,
                                                    Func<string, bool>? isACourseCode = null)
    {
        string s = Tidied(message);
        if (s.Length == 0) return null;

        string? x = null, after = null;
        foreach (var frame in LinkFrames)
        {
            var m = frame.Match(s);
            if (!m.Success) continue;
            x = m.Groups["x"].Value;
            after = m.Groups["after"].Success ? m.Groups["after"].Value : "";
            break;
        }
        if (x is null) return null;

        // After "link to": nothing, or " in <place>". Anything else — ", and
        // publish them", "and are they live" — is a second request.
        Place? placeAfter = null;
        if (after!.Length > 0)
        {
            var inPlace = Regex.Match(after, @"^\s+in\s+(?<p>.+)$", RegexOptions.IgnoreCase);
            if (!inPlace.Success) return null;
            placeAfter = PlaceOf(inPlace.Groups["p"].Value, windowCourse, windowSection, isACourseCode);
            if (placeAfter.Kind == PlaceKind.NotAPlace) return null;
        }

        x = x.Trim();
        // A title slot that is itself a place is not a page: "What links are
        // in SPH3U?", "What does this section link to?".
        var whole = PlaceOf(x, windowCourse, windowSection, isACourseCode);
        if (whole.Kind != PlaceKind.NotAPlace)
            return whole.Kind == PlaceKind.OtherCourse && placeAfter is null ? new LinksQuestionMatch(null, OtherCourse: whole.Course) : null;

        // A place at the end of the title: the LAST " in ", and only when what
        // follows it is a place — "Day 3 in Unit 2" is a page's name.
        Place? placeBefore = null;
        int at = x.LastIndexOf(" in ", StringComparison.OrdinalIgnoreCase);
        if (at > 0)
        {
            var candidate = PlaceOf(x[(at + 4)..], windowCourse, windowSection, isACourseCode);
            if (candidate.Kind != PlaceKind.NotAPlace)
            {
                placeBefore = candidate;
                x = x[..at].Trim();
            }
        }
        if (placeBefore is not null && placeAfter is not null) return null;   // at most once
        var place = placeBefore ?? placeAfter;
        if (place is not null)
        {
            if (windowCourse is null || windowSection is null) return null;
            if (place.Kind == PlaceKind.OtherCourse) return new LinksQuestionMatch(null, OtherCourse: place.Course);
            if (place.Kind == PlaceKind.OtherSection) return null;
        }

        string title = WithoutOnePairOfQuotes(x).Trim();
        if (title.Length == 0) return null;
        string lower = title.ToLowerInvariant();
        if (NotATitle.Contains(lower) || NotATitleOpenings.Any(opening => lower.StartsWith(opening, StringComparison.Ordinal)))
            return null;
        // "... and publish them": a second request riding on the first.
        if (Regex.IsMatch(lower, @"\band (?:publish|unpublish|hide|deploy|show|list|tell|check|are|is)\b")) return null;
        // The title is itself another course's code: "What does SPH3U link to?".
        if (isACourseCode is not null && !lower.Contains(' ') && isACourseCode(title.ToUpperInvariant()) &&
            !string.Equals(title, windowCourse, StringComparison.OrdinalIgnoreCase))
            return new LinksQuestionMatch(null, OtherCourse: title);

        var thePage = Regex.Match(title, @"^the\s+(?<inner>.+)\s+page$", RegexOptions.IgnoreCase);
        if (thePage.Success) return new LinksQuestionMatch(thePage.Groups["inner"].Value.Trim(), AsTyped: title);
        if (lower.StartsWith("the ", StringComparison.Ordinal))
            return new LinksQuestionMatch(title, OnlyIfAPageIsCalled: true);
        return new LinksQuestionMatch(title);
    }

    /// <summary>
    /// Whether this card is the links family. The window's agent answers that
    /// family through <see cref="LinksQuestion"/> only, and skips this card.
    /// </summary>
    public bool IsALinksQuestion =>
        ToolName == "read_page" && Arguments.TryGetValue("answer", out var answer) && answer == "links";

    /// <summary>The family as a card: <c>read_page</c> with <c>answer: "links"</c>, an argument in no schema the model is shown.</summary>
    private static AssistCardCommand? LinksCard(string message)
    {
        if (LinksQuestion(message) is not { Page: { } page } found) return null;
        var arguments = new Dictionary<string, string> { ["page"] = page, ["answer"] = "links" };
        if (found.AsTyped is { } typed) arguments["asTyped"] = typed;
        if (found.OnlyIfAPageIsCalled) arguments["onlyIfFound"] = "yes";
        return new AssistCardCommand("read_page", arguments);
    }

    private static readonly Regex[] LinkFrames =
    {
        new(@"^(?:what|which pages|what pages|where) does (?<x>.+?) link to(?<after>.*)$", RegexOptions.IgnoreCase),
        new(@"^(?:what|where) does (?<x>.+?) point to(?<after>.*)$", RegexOptions.IgnoreCase),
        new(@"^what links are (?:on|in) (?<x>.+)$", RegexOptions.IgnoreCase),
        new(@"^(?:show me the links|list the links) (?:on|in|from) (?<x>.+)$", RegexOptions.IgnoreCase),
    };

    private static readonly HashSet<string> NotATitle = new(StringComparer.Ordinal)
    {
        "it", "that", "this", "today", "tomorrow", "my course", "this course", "this section",
    };

    private static readonly string[] NotATitleOpenings =
    {
        "today", "tomorrow", "my ", "the next ", "this ", "that ", "the page ",
    };

    /// <summary>A question mark, a full stop and a 'please' taken off either end.</summary>
    private static string Tidied(string message)
    {
        string s = message.Trim();
        for (int pass = 0; pass < 2; pass++)
        {
            s = s.TrimEnd('?', '.', '!', ' ');
            s = Regex.Replace(s, @"^please,?\s+", "", RegexOptions.IgnoreCase);
            s = Regex.Replace(s, @",?\s+please$", "", RegexOptions.IgnoreCase);
        }
        return s.Trim();
    }

    private static string WithoutOnePairOfQuotes(string title)
    {
        title = title.Trim();
        if (title.Length >= 2 &&
            ((title[0] == '"' && title[^1] == '"') || (title[0] == '“' && title[^1] == '”') ||
             (title[0] == '\'' && title[^1] == '\'')))
            return title[1..^1];
        return title;
    }

    private enum PlaceKind { NotAPlace, ThisWindow, OtherSection, OtherCourse }

    private sealed record Place(PlaceKind Kind, string? Course = null);

    private static Place PlaceOf(string text, string? windowCourse, int? windowSection, Func<string, bool>? isACourseCode)
    {
        string p = text.Trim();
        if (p.Equals("this section", StringComparison.OrdinalIgnoreCase)) return new(PlaceKind.ThisWindow);

        var section = Regex.Match(p, @"^section (?<n>\d+)$", RegexOptions.IgnoreCase);
        if (section.Success) return SectionOf(int.Parse(section.Groups["n"].Value), windowSection);

        var withCourse = Regex.Match(p, @"^(?:section (?<n>\d+) of (?<c>\S+)|(?<c>\S+) section (?<n>\d+))$",
                                     RegexOptions.IgnoreCase);
        if (withCourse.Success)
        {
            string course = withCourse.Groups["c"].Value;
            if (!string.Equals(course, windowCourse, StringComparison.OrdinalIgnoreCase))
                return new(PlaceKind.OtherCourse, course);
            return SectionOf(int.Parse(withCourse.Groups["n"].Value), windowSection);
        }

        if (!p.Contains(' '))
        {
            if (windowCourse is not null && p.Equals(windowCourse, StringComparison.OrdinalIgnoreCase))
                return new(PlaceKind.ThisWindow);
            if (isACourseCode is not null && isACourseCode(p.ToUpperInvariant())) return new(PlaceKind.OtherCourse, p);
        }
        return new(PlaceKind.NotAPlace);
    }

    private static Place SectionOf(int number, int? windowSection) =>
        windowSection == number ? new(PlaceKind.ThisWindow) : new(PlaceKind.OtherSection);
}

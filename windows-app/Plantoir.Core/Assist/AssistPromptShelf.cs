using System;
using System.Collections.Generic;
using System.Linq;

namespace Plantoir.Core.Assist;

/// <summary>
/// The shelf of things a teacher can ask for in the local AI assistant window:
/// what it offers, and that its open/shut state is remembered.
///
/// Grouped the way a teacher thinks about them, not the way the tools are
/// organised.
/// </summary>
public static class AssistPromptShelf
{
    public const string OpenGroupsKey = "AssistPromptShelfOpenGroups";

    public const string HeaderText =
        "Here are some things you can ask me for. Tap one to put it in the box, change it to suit, then press Return.";

    public static readonly IReadOnlyList<(string Title, IReadOnlyList<string> Phrasings)> Groups =
    [
        ("Making pages visible",
        [
            "Publish Unit 2, Day 3",
            "Publish tomorrow's class",
            "Publish Monday's class",
            "Publish Unit 5",
        ]),
        ("Taking it back",
        [
            "Unpublish Unit 2, Day 3",
            "Unpublish Unit 4",
            "Undo that",
        ]),
        ("Checking",
        [
            "What would students see in this section right now?",
            "Preview",
        ]),
        ("Planning classes",
        [
            "Add the next class page",
            "Start a new unit for the next class",
            "Add five more days to Unit 4",
            "Duplicate Unit 3, Day 2 as my next class",
            "When are my next classes?",
            "I have a revised list of class dates",
            "Re-date my classes",
        ]),
        ("Putting the site online",
        [
            "Deploy now",
            "Deploy at 6:30 AM",
            "Cancel scheduled deploy",
        ]),
    ];

    public static HashSet<string> ParseOpenGroups(string? raw)
    {
        var titles = new HashSet<string>(StringComparer.Ordinal);
        if (string.IsNullOrWhiteSpace(raw)) return titles;

        foreach (string piece in raw.Split('|', StringSplitOptions.RemoveEmptyEntries))
        {
            string trimmed = piece.Trim();
            if (trimmed.Length > 0) titles.Add(trimmed);
        }
        return titles;
    }

    public static string SerializeOpenGroups(IEnumerable<string> openTitles)
    {
        return string.Join("|", openTitles.Where(t => !string.IsNullOrWhiteSpace(t)).Distinct());
    }
}

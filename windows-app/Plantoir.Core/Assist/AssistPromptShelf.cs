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

    /// <summary>
    /// The shelf for ONE course (#274, mac <c>AssistPromptShelfView.groups(naming:noun:)</c>).
    /// An ordinary course gets <see cref="Groups"/> unchanged. A numbered
    /// course — a club's "Week 3" — gets its own list in its own noun: no
    /// unit cards (each would be refused there) and no "Publish Week 2" /
    /// "Unpublish Week 2", because publishing one page by its title goes to
    /// the model and no routing measurement has been made in a club. Every
    /// card on it but "Cancel scheduled deploy" is matched in code.
    /// </summary>
    public static IReadOnlyList<(string Title, IReadOnlyList<string> Phrasings)> GroupsFor(
        Plantoir.Core.Models.ClassPageNaming naming, Plantoir.Core.Models.ClassNoun noun)
    {
        if (!naming.IsNumbered) return Groups;
        string one = noun == Plantoir.Core.Models.ClassNoun.Meeting ? "meeting" : "class";
        string many = noun == Plantoir.Core.Models.ClassNoun.Meeting ? "meetings" : "classes";
        return
        [
            ("Making pages visible", [$"Publish tomorrow's {one}", $"Publish Monday's {one}"]),
            ("Taking it back", ["Undo that"]),
            ("Checking", ["What would students see in this section right now?", "Preview"]),
            ($"Planning {many}",
            [
                $"Add the next {one} page",
                $"Duplicate {naming.Title(1, 2)} as my next {one}",
                $"Make room for one {one} at {naming.Title(1, 3)}",
                $"When are my next {many}?",
                $"I have a revised list of {one} dates",
                $"Re-date my {many}",
            ]),
            ("Putting the site online", ["Deploy now", "Deploy at 6:30 AM", "Cancel scheduled deploy"]),
        ];
    }

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

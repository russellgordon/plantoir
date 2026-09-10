using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text.Json.Nodes;

namespace Plantoir.Core.Assist;

public sealed record AssistCardCommand(string ToolName, IReadOnlyDictionary<string, string> Arguments)
{
    private static readonly char[] TrimChars = new[] { ' ', '\t', '\r', '\n', '.', '!' };

    private static readonly Dictionary<string, (string Tool, Dictionary<string, string> Args)> FixedShapes =
        new(StringComparer.OrdinalIgnoreCase)
        {
            ["what would students see in this section right now?"] = ("check_section", new()),
            ["what do students see right now?"] = ("check_section", new()),
            ["preview"] = ("rebuild_preview", new()),
            ["rebuild the preview"] = ("rebuild_preview", new()),
            ["undo that"] = ("undo_last_change", new()),
            ["deploy now"] = ("deploy_section", new()),
            ["deploy this section now"] = ("deploy_section", new()),
            ["deploy"] = ("deploy_section", new()),
            ["publish tomorrow's class"] = ("publish_class_on", new() { ["when"] = "tomorrow" }),
            ["publish monday's class"] = ("publish_class_on", new() { ["when"] = "monday" }),
            ["publish tuesday's class"] = ("publish_class_on", new() { ["when"] = "tuesday" }),
            ["publish wednesday's class"] = ("publish_class_on", new() { ["when"] = "wednesday" }),
            ["publish thursday's class"] = ("publish_class_on", new() { ["when"] = "thursday" }),
            ["publish friday's class"] = ("publish_class_on", new() { ["when"] = "friday" }),
            ["publish saturday's class"] = ("publish_class_on", new() { ["when"] = "saturday" }),
            ["publish sunday's class"] = ("publish_class_on", new() { ["when"] = "sunday" }),
            ["what pages are in this section?"] = ("list_pages", new()),
            ["add the next class page"] = ("add_next_class", new()),
            ["start a new unit for the next class"] = ("add_next_class", new() { ["unit"] = "next" }),
            ["start a new unit"] = ("add_next_class", new() { ["unit"] = "next" }),
            ["when are my next classes?"] = ("read_remembered_timetable", new()),
            ["when are my next classes"] = ("read_remembered_timetable", new()),
            ["when is my next class?"] = ("read_remembered_timetable", new()),
            ["when is my next class"] = ("read_remembered_timetable", new()),
            ["when do i teach next?"] = ("read_remembered_timetable", new()),
            ["when do i teach next"] = ("read_remembered_timetable", new()),
            ["what dates am i teaching?"] = ("read_remembered_timetable", new()),
            ["what dates am i teaching"] = ("read_remembered_timetable", new()),
            ["show me the rest of the dates"] = ("read_remembered_timetable", new() { ["scope"] = "all" }),
            ["show me all the dates"] = ("read_remembered_timetable", new() { ["scope"] = "all" }),
            ["i have a revised list of class dates"] = ("read_remembered_timetable", new() { ["revise"] = "yes" }),
            ["i have a new list of class dates"] = ("read_remembered_timetable", new() { ["revise"] = "yes" }),
            ["change my class dates"] = ("read_remembered_timetable", new() { ["revise"] = "yes" }),
            ["re-date my classes"] = ("re_date_classes", new()),
            ["redate my classes"] = ("re_date_classes", new()),
            ["re-date this section"] = ("re_date_classes", new()),
            // A ROLLOVER, and only a rollover, carries `rollover`. The three
            // phrasings above it are ordinary re-dating — a snow day, a
            // timetable that shifted — and asking THOSE about websites would
            // let a teacher answer "a new website" mid-semester and abandon
            // the address their students are reading right now.
            ["roll this section over to a new year"] = ("re_date_classes", new() { ["rollover"] = "yes" }),

            // The two answers to the website question, as whole sentences
            // rather than "a new website" — which is an exact match a teacher
            // could type meaning something else entirely. Each also works as a
            // FIRST thing to say, for a teacher who already knows which they
            // want, because re-dating a section already on its dates changes
            // nothing. Named from AssistWording rather than typed here: the
            // assistant's own reply offers these back word for word, and a
            // phrasing a teacher is TOLD to say must be one the matcher takes.
            [AssistWording.RolloverSayToStartANewWebsite] =
                ("re_date_classes", new() { ["rollover"] = "yes", ["website"] = "new" }),
            [AssistWording.RolloverSayToKeepTheSameWebsite] =
                ("re_date_classes", new() { ["rollover"] = "yes", ["website"] = "same" }),
        };

    private static readonly Dictionary<string, int> SpelledNumbers = new(StringComparer.OrdinalIgnoreCase)
    {
        ["one"] = 1, ["two"] = 2, ["three"] = 3, ["four"] = 4, ["five"] = 5, ["six"] = 6,
        ["seven"] = 7, ["eight"] = 8, ["nine"] = 9, ["ten"] = 10, ["eleven"] = 11, ["twelve"] = 12,
    };

    public static AssistCardCommand? Matching(string message)
    {
        string tidied = message.Trim(TrimChars).ToLowerInvariant();
        if (string.IsNullOrEmpty(tidied)) return null;

        if (FixedShapes.TryGetValue(tidied, out var found))
        {
            return new AssistCardCommand(found.Tool, found.Args);
        }

        if (WholeUnit(tidied) is { } unit) return unit;
        if (MoreDays(tidied) is { } more) return more;
        return DuplicateClass(tidied, message);
    }

    private static AssistCardCommand? WholeUnit(string tidied)
    {
        var prefixes = new[] { ("unpublish unit ", "unpublish_pages"), ("publish unit ", "publish_pages") };
        foreach (var (prefix, tool) in prefixes)
        {
            if (tidied.StartsWith(prefix, StringComparison.Ordinal))
            {
                string rest = tidied[prefix.Length..].Trim();
                if (!string.IsNullOrEmpty(rest) && !rest.Contains(',') && int.TryParse(rest, out _))
                {
                    return new AssistCardCommand(tool, new Dictionary<string, string>
                    {
                        ["pages"] = $"Unit {rest}",
                    });
                }
            }
        }
        return null;
    }

    private static AssistCardCommand? MoreDays(string tidied)
    {
        string[] words = tidied.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        // add <count> more days to unit <number> -> 7 words
        if (words.Length != 7) return null;
        if (words[0] != "add" || words[2] != "more" || words[3] != "days" || words[4] != "to" || words[5] != "unit")
            return null;

        int howMany = 0;
        if (SpelledNumbers.TryGetValue(words[1], out int spelled))
        {
            howMany = spelled;
        }
        else if (int.TryParse(words[1], out int parsed))
        {
            howMany = parsed;
        }

        if (howMany <= 0 || !int.TryParse(words[6], out int unit)) return null;

        return new AssistCardCommand("add_next_class", new Dictionary<string, string>
        {
            ["unit"] = unit.ToString(),
            ["days"] = howMany.ToString(),
        });
    }

    private static AssistCardCommand? DuplicateClass(string tidied, string original)
    {
        const string opening = "duplicate ";
        if (!tidied.StartsWith(opening, StringComparison.Ordinal)) return null;

        string typed = original.Trim(TrimChars);
        string body = tidied[opening.Length..];
        string[] endings = { " as my next class", " as the next class", " as my next lesson" };

        foreach (string ending in endings)
        {
            if (body.EndsWith(ending, StringComparison.Ordinal))
            {
                int start = opening.Length;
                int end = typed.Length - ending.Length;
                if (start >= end) return null;

                string title = typed[start..end].Trim();
                if (string.IsNullOrEmpty(title)) return null;

                return new AssistCardCommand("add_next_class", new Dictionary<string, string>
                {
                    ["duplicate"] = title,
                });
            }
        }
        return null;
    }

    /// <summary>
    /// The two tools that publish ONE day's class, whose card argument is a
    /// relative day and whose parameter is an absolute date.
    /// </summary>
    private static readonly HashSet<string> PublishesADaysClass = new(StringComparer.OrdinalIgnoreCase)
    {
        "publish_class_on",
        "plan_publish_class_on",
    };

    /// <summary>
    /// The card as the JSON this app really sends, with <c>when</c> turned
    /// into the <c>date</c> the tool takes.
    /// </summary>
    /// <remarks>
    /// <para><b>Why the rename happens here.</b> The eight fixed phrasings
    /// ("publish tomorrow's class", and the seven weekdays) set <c>when</c>,
    /// which is the mac's shape and is pinned by
    /// <c>contracts/assist-cases.json</c> -&gt; <c>cardPhrasings</c>, so the
    /// card cannot simply be changed to say <c>date</c>. On the mac the card
    /// and the runner share a process and the runner reads either name; here
    /// the call crosses <c>plantoir-mcp</c> over JSON-RPC, and the SDK's
    /// binder drops a key the method does not declare - and then refuses for
    /// the required <c>date</c> it never got. That is issue #116: the
    /// commonest request in the product, and one of the prompt shelf's
    /// suggested prompts, answered with "That tool couldn't be run".
    /// So this method - the one place the card becomes the wire - is where
    /// the two names meet, and where they are reconciled.</para>
    ///
    /// <para><b>Why the day is settled HERE rather than in the tool.</b>
    /// <c>AssistAgent.RunCommand</c> synthesises ONE arguments object and
    /// reuses it: first for the plan twin, then, if the teacher presses Go,
    /// for the act itself. Settling "tomorrow" at the moment the phrasing is
    /// matched means the plan a teacher read and the class that gets published
    /// are the same day even when the two are minutes apart across midnight.
    /// Resolving inside the tool instead would let the second call land on a
    /// different day than the first proposed - rare, silent, and exactly the
    /// kind of wrong day nobody would think to look for. The tool understands
    /// these words as well, for MCP callers that have no card
    /// (<c>PlantoirTools.PlanForDay</c>); it is the same shared reader either
    /// way, so there is one answer to what "monday" means.</para>
    ///
    /// <para>No card sets both <c>when</c> and <c>date</c>, and none should:
    /// the two would race on the order the dictionary happens to yield them.
    /// The fixed shapes are written out one by one a few hundred lines above,
    /// which is where that stays true.</para>
    ///
    /// <para>A word that cannot be read is passed through as the <c>date</c>
    /// unchanged, so the tool answers with its own sentence about the date
    /// rather than the binder throwing about a parameter a teacher has never
    /// heard of. No card can reach that branch - all eight words resolve - and
    /// it is a guard rather than a behaviour.</para>
    /// </remarks>
    /// <param name="today">
    /// The day to count from, for tests. Left null, it is the real today, read
    /// at the moment the phrasing is matched.
    /// </param>
    public JsonObject ToJsonObject(string course, int section, DateOnly? today = null)
    {
        var obj = new JsonObject
        {
            ["course"] = course,
            ["section"] = section,
        };
        if (ToolName == "publish_pages" || ToolName == "unpublish_pages" ||
            ToolName == "plan_publish_pages" || ToolName == "plan_unpublish_pages")
        {
            obj["includeLinked"] = false;
        }
        foreach (var (k, v) in Arguments)
        {
            if (k == "when" && PublishesADaysClass.Contains(ToolName))
            {
                var day = SectionScheduleSource.ReadRelativeDay(
                    v, today ?? DateOnly.FromDateTime(DateTime.Now));
                // InvariantCulture, because a machine set to a non-Gregorian
                // default calendar renders "yyyy" in ITS year - 2569 for Thai
                // Buddhist - and the tool would then look for a class on a day
                // no course has.
                obj["date"] = day is { } read
                    ? read.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)
                    : v;
            }
            else if (k == "pages")
            {
                obj[k] = new JsonArray(JsonValue.Create(v));
            }
            else if (k == "includeLinked" && bool.TryParse(v, out bool b))
            {
                obj[k] = b;
            }
            else
            {
                obj[k] = v;
            }
        }
        return obj;
    }
}

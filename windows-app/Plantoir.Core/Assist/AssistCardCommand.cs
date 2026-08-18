using System;
using System.Collections.Generic;
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
            ["roll this section over to a new year"] = ("re_date_classes", new()),
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

    public JsonObject ToJsonObject(string course, int section)
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
            if (k == "pages")
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

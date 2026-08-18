using System.Globalization;
using System.Text.RegularExpressions;

namespace Plantoir.Core.Assist;

public enum ColumnOrdering
{
    DayThenMonth,
    MonthThenDay
}

public static class ColumnOrderingExtensions
{
    public static string Note(this ColumnOrdering ordering) =>
        ordering switch
        {
            ColumnOrdering.DayThenMonth => "day first",
            ColumnOrdering.MonthThenDay => "month first",
            _ => ""
        };
}

public abstract record ScheduleOutcome
{
    public sealed record Dates(ScheduleReading Reading) : ScheduleOutcome;
    public sealed record Question(OrderingQuestion OrderingQuestion) : ScheduleOutcome;
}

public sealed record ScheduleReading(
    IReadOnlyList<DateOnly> Dates,
    string SuggestedSource,
    ColumnOrdering? ChosenOrdering = null)
{
    public IReadOnlyList<string> DatesText => Dates.Select(d => d.ToString("yyyy-MM-dd")).ToList();
}

public sealed class OrderingQuestion
{
    public required string Written { get; init; }
    public required string DayFirstSpoken { get; init; }
    public required string MonthFirstSpoken { get; init; }
    public required string DayFirstShort { get; init; }
    public required string MonthFirstShort { get; init; }
    public required IReadOnlyList<string> Column { get; init; }
    public required string Place { get; init; }
    public required string SuggestedSource { get; init; }

    public string Prompt =>
        $"These dates can be read two ways, and nothing in {Place} settles which. Is “{Written}” {DayFirstSpoken}, or {MonthFirstSpoken}?";

    public ScheduleReading Answer(ColumnOrdering ordering)
    {
        var outcome = SectionScheduleSource.Read(Column, Place, SuggestedSource, ordering);
        if (outcome is ScheduleOutcome.Dates datesOutcome)
        {
            return new ScheduleReading(
                datesOutcome.Reading.Dates,
                $"{SuggestedSource}, {ordering.Note()}",
                ordering);
        }
        throw new AssistRefusal($"Nothing could be read from {Place}.");
    }
}

public static class SectionScheduleSource
{
    private static readonly string[] SingleDateFormats = new[]
    {
        "yyyy-MM-dd",
        "yyyy/MM/dd",
        "yyyy.MM.dd",
        "MMM d, yyyy",
        "MMM d yyyy",
        "MMMM d, yyyy",
        "MMMM d yyyy",
        "d MMM yyyy",
        "d MMMM yyyy",
        "d MMM. yyyy",
        "d MMMM, yyyy",
        "MMM-d-yyyy",
        "d-MMM-yyyy",
        "MMM. d, yyyy",
        "MMM. d yyyy",
        "d Sept. yyyy",
        "d Sept yyyy"
    };

    public static DateOnly? ReadRelativeDay(string input, DateOnly today)
    {
        string trimmed = input.Trim().ToLowerInvariant();
        if (trimmed == "today") return today;
        if (trimmed == "tomorrow") return today.AddDays(1);
        if (trimmed == "yesterday") return today.AddDays(-1);

        if (DateOnly.TryParseExact(input.Trim(), "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var directDate))
            return directDate;

        return null;
    }

    public static ScheduleOutcome ReadTypedText(string text, ColumnOrdering? ordering = null)
    {
        var lines = text.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None);
        return Read(lines, "what you pasted", "pasted by hand", ordering);
    }

    public static ScheduleOutcome Read(
        IReadOnlyList<string> column,
        string place,
        string suggestedSource,
        ColumnOrdering? answered = null)
    {
        var values = column
            .Select(line => line.Trim())
            .Where(line => !string.IsNullOrEmpty(line))
            .ToList();

        if (values.Count == 0)
            throw new AssistRefusal($"There are no dates in {place}, so there is nothing to remember.");

        var entries = values.Select(EntryFrom).ToList();

        // Forgive unreadable first line if it's a header and there are subsequent lines
        if (entries[0] is ParsedEntry.Unreadable && entries.Count > 1)
        {
            entries.RemoveAt(0);
        }

        var offenders = new List<string>();
        string? dayFirstProof = null;
        string? monthFirstProof = null;
        string? undecided = null;

        foreach (var entry in entries)
        {
            switch (entry)
            {
                case ParsedEntry.Day:
                    continue;
                case ParsedEntry.Unreadable un:
                    offenders.Add($"“{un.Written}”");
                    break;
                case ParsedEntry.NumbersInEitherOrder num:
                    if (num.First > 12 && num.Second > 12)
                    {
                        offenders.Add($"“{num.Written}”");
                        continue;
                    }
                    if (num.First > 12)
                    {
                        dayFirstProof ??= num.Written;
                        continue;
                    }
                    if (num.Second > 12)
                    {
                        monthFirstProof ??= num.Written;
                        continue;
                    }
                    if (num.First != num.Second)
                    {
                        undecided ??= num.Written;
                    }
                    break;
            }
        }

        if (offenders.Count > 0)
        {
            string subject = offenders.Count == 1 ? "isn’t a date" : "aren’t dates";
            throw new AssistRefusal(
                $"{string.Join(", ", offenders)} {subject} Plantoir can read, so nothing was taken from {place}. " +
                "A half-read timetable would date the wrong classes, so the whole list is refused — fix those and try again. Dates written 2026-09-08 always work.");
        }

        if (dayFirstProof != null && monthFirstProof != null)
        {
            throw new AssistRefusal(
                $"{place} is written both ways round: “{dayFirstProof}” can only be day/month/year, and “{monthFirstProof}” can only be month/day/year. " +
                "Nothing was read, because either reading would be wrong for half the column. Write them all the same way, or as 2026-09-08.");
        }

        ColumnOrdering ordering = ColumnOrdering.DayThenMonth;
        if (monthFirstProof != null)
        {
            ordering = ColumnOrdering.MonthThenDay;
        }
        else if (dayFirstProof == null)
        {
            if (answered.HasValue)
            {
                ordering = answered.Value;
            }
            else if (undecided != null)
            {
                return new ScheduleOutcome.Question(BuildQuestion(undecided, column, place, suggestedSource));
            }
        }

        var dates = new List<DateOnly>();
        foreach (var entry in entries)
        {
            switch (entry)
            {
                case ParsedEntry.Day d:
                    if (!dates.Contains(d.Value)) dates.Add(d.Value);
                    break;
                case ParsedEntry.NumbersInEitherOrder num:
                    int month = ordering == ColumnOrdering.MonthThenDay ? num.First : num.Second;
                    int dayOfMonth = ordering == ColumnOrdering.MonthThenDay ? num.Second : num.First;
                    try
                    {
                        var d = new DateOnly(num.Year, month, dayOfMonth);
                        if (!dates.Contains(d)) dates.Add(d);
                    }
                    catch
                    {
                        offenders.Add($"“{num.Written}”");
                    }
                    break;
            }
        }

        if (offenders.Count > 0)
        {
            string subject = offenders.Count == 1 ? "isn’t a date" : "aren’t dates";
            throw new AssistRefusal(
                $"{string.Join(", ", offenders)} {subject} Plantoir can read, so nothing was taken from {place}.");
        }

        if (dates.Count == 0)
            throw new AssistRefusal($"There are no dates in {place}, so there is nothing to remember.");

        dates.Sort();
        return new ScheduleOutcome.Dates(new ScheduleReading(dates, suggestedSource, answered));
    }

    private static OrderingQuestion BuildQuestion(string written, IReadOnlyList<string> column, string place, string suggestedSource)
    {
        var numbers = ExtractNumbers(written);
        int first = numbers[0];
        int second = numbers[1];

        return new OrderingQuestion
        {
            Written = written,
            DayFirstSpoken = SpokenDate(first, second),
            MonthFirstSpoken = SpokenDate(second, first),
            DayFirstShort = ShortDate(first, second),
            MonthFirstShort = ShortDate(second, first),
            Column = column,
            Place = place,
            SuggestedSource = suggestedSource
        };
    }

    private static string SpokenDate(int day, int month)
    {
        string monthName = CultureInfo.InvariantCulture.DateTimeFormat.GetMonthName(Math.Clamp(month, 1, 12));
        string daySuffix = day switch
        {
            1 or 21 or 31 => "st",
            2 or 22 => "nd",
            3 or 23 => "rd",
            _ => "th"
        };
        return $"the {day}{daySuffix} of {monthName}";
    }

    private static string ShortDate(int day, int month)
    {
        string monthName = CultureInfo.InvariantCulture.DateTimeFormat.GetMonthName(Math.Clamp(month, 1, 12));
        return $"{day} {monthName}";
    }

    private static List<int> ExtractNumbers(string text)
    {
        var matches = Regex.Matches(text, @"\d+");
        return matches.Select(m => int.Parse(m.Value)).ToList();
    }

    private abstract record ParsedEntry
    {
        public sealed record Day(DateOnly Value) : ParsedEntry;
        public sealed record NumbersInEitherOrder(int First, int Second, int Year, string Written) : ParsedEntry;
        public sealed record Unreadable(string Written) : ParsedEntry;
    }

    private static ParsedEntry EntryFrom(string written)
    {
        string trimmed = written.Trim();
        if (string.IsNullOrEmpty(trimmed))
            return new ParsedEntry.Unreadable(written);

        // Try standard single date formats
        string normalized = trimmed.Replace("Sept.", "Sep").Replace("Sept", "Sep");
        foreach (var format in SingleDateFormats)
        {
            if (DateTime.TryParseExact(normalized, format, CultureInfo.InvariantCulture, DateTimeStyles.None, out var dt))
                return new ParsedEntry.Day(DateOnly.FromDateTime(dt));
            if (DateTime.TryParseExact(trimmed, format, CultureInfo.InvariantCulture, DateTimeStyles.None, out dt))
                return new ParsedEntry.Day(DateOnly.FromDateTime(dt));
        }

        // Try slash/dash/dot separated numbers
        var parts = trimmed.Split(new[] { '/', '-', '.' }, StringSplitOptions.None);
        if (parts.Length == 3 &&
            int.TryParse(parts[0], out int p1) &&
            int.TryParse(parts[1], out int p2) &&
            int.TryParse(parts[2], out int p3))
        {
            // Year at front (YYYY-MM-DD or YYYY/MM/DD)
            if (p1 >= 1000)
            {
                try
                {
                    var d = new DateOnly(p1, p2, p3);
                    return new ParsedEntry.Day(d);
                }
                catch
                {
                    return new ParsedEntry.Unreadable(written);
                }
            }

            // Year at back (DD/MM/YYYY or MM/DD/YYYY)
            int year = p3 < 100 ? (p3 >= 50 ? 1900 + p3 : 2000 + p3) : p3;
            return new ParsedEntry.NumbersInEitherOrder(p1, p2, year, trimmed);
        }

        return new ParsedEntry.Unreadable(written);
    }

    public static Uri CsvUrlForGoogleSheetLink(string link)
    {
        string trimmed = link.Trim();
        string marker = "/spreadsheets/d/";
        int markerIndex = trimmed.IndexOf(marker, StringComparison.Ordinal);
        if (markerIndex < 0)
        {
            throw new AssistRefusal(
                $"“{trimmed}” is not a Google Sheet link. Open the sheet in your browser and copy the address from the address bar — it looks like https://docs.google.com/spreadsheets/d/…/edit.");
        }

        string afterMarker = trimmed[(markerIndex + marker.Length)..];
        string identifier = "";
        foreach (char c in afterMarker)
        {
            if (c is '/' or '?' or '#') break;
            identifier += c;
        }

        if (identifier == "e")
        {
            throw new AssistRefusal(
                "That is a “published to the web” link, which Plantoir cannot read a column from. Open the sheet itself and copy the address from the address bar instead — it looks like https://docs.google.com/spreadsheets/d/…/edit.");
        }

        if (string.IsNullOrEmpty(identifier) || !Regex.IsMatch(identifier, @"^[a-zA-Z0-9_-]+$"))
        {
            throw new AssistRefusal(
                $"“{trimmed}” is not a Google Sheet link. Open the sheet in your browser and copy the address from the address bar — it looks like https://docs.google.com/spreadsheets/d/…/edit.");
        }

        string address = $"https://docs.google.com/spreadsheets/d/{identifier}/export?format=csv";
        string? tab = TabIdentifier(trimmed);
        if (!string.IsNullOrEmpty(tab))
        {
            address += $"&gid={tab}";
        }

        return new Uri(address);
    }

    public static string? TabIdentifier(string link)
    {
        var match = Regex.Match(link, @"[?#&]gid=(\d+)");
        if (match.Success)
        {
            return match.Groups[1].Value;
        }
        return null;
    }

    /// <summary>
    /// A .csv or .ics file, read by what it is rather than by asking.
    /// </summary>
    public static ScheduleOutcome ReadFromFile(string filePath, ColumnOrdering? ordering = null)
    {
        string name = Path.GetFileName(filePath);
        string ext = Path.GetExtension(filePath).ToLowerInvariant();
        if (ext != ".csv" && ext != ".ics" && ext != ".txt")
        {
            throw new AssistRefusal($"“{name}” isn’t a file Plantoir can read a timetable from. A comma-separated file (.csv) or an iCalendar export (.ics) from your calendar app always works.");
        }

        string text;
        try
        {
            text = File.ReadAllText(filePath);
        }
        catch (Exception ex)
        {
            throw new AssistRefusal($"Could not read {name}: {ex.Message}");
        }

        if (ext == ".ics" || text.Contains("BEGIN:VCALENDAR", StringComparison.OrdinalIgnoreCase))
        {
            var column = ColumnFromCalendarExport(text, name);
            return Read(column, name, name, ordering);
        }
        else
        {
            var lines = text.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None);
            var column = lines.Select(FirstFieldInCSVRow).ToList();
            return Read(column, name, name, ordering);
        }
    }

    /// <summary>
    /// A calendar export: every DTSTART, and nothing else in the file.
    /// </summary>
    public static List<string> ColumnFromCalendarExport(string text, string place)
    {
        var result = new List<string>();
        foreach (var line in Unfolded(text))
        {
            string upper = line.ToUpperInvariant();
            if (!upper.StartsWith("DTSTART")) continue;
            int colon = line.IndexOf(':');
            if (colon < 0) continue;
            string val = line[(colon + 1)..].Trim();
            result.Add(CalendarDayText(val));
        }
        if (result.Count == 0)
        {
            throw new AssistRefusal($"No start dates were found in {place}.");
        }
        return result;
    }

    /// <summary>
    /// 20260908T090000Z and 20260908 both begin with the day.
    /// </summary>
    public static string CalendarDayText(string value)
    {
        if (value.Length < 8) return value;
        for (int i = 0; i < 8; i++)
        {
            if (!char.IsAsciiDigit(value[i])) return value;
        }
        string year = value.Substring(0, 4);
        string month = value.Substring(4, 2);
        string day = value.Substring(6, 2);
        return $"{year}-{month}-{day}";
    }

    /// <summary>
    /// A calendar file wraps long lines, continuing them with a leading space or tab.
    /// </summary>
    public static List<string> Unfolded(string text)
    {
        var result = new List<string>();
        var rawLines = text.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None);
        foreach (var raw in rawLines)
        {
            string line = raw.Replace("\r", "");
            if (line.StartsWith(' ') || line.StartsWith('\t'))
            {
                if (result.Count == 0) continue;
                string continuation = line[1..];
                result[^1] += continuation;
                continue;
            }
            if (line.Length > 0)
                result.Add(line);
        }
        return result;
    }

    /// <summary>
    /// The first field on a comma-separated row that has anything in it.
    /// </summary>
    public static string FirstFieldInCSVRow(string row)
    {
        if (string.IsNullOrWhiteSpace(row)) return "";
        var parts = row.Split(',');
        foreach (var part in parts)
        {
            string trimmed = part.Trim().Trim('"', '\'');
            if (!string.IsNullOrEmpty(trimmed)) return trimmed;
        }
        return "";
    }
}

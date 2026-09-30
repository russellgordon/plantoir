using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// A school's timetable sheet, read into dated class meetings.
///
/// Every school writes these differently, so nothing about one school's sheet
/// is assumed. What IS assumed is the shape the format implies: a header row
/// naming each class location, and underneath it a column of dates — optionally
/// paired with a second column carrying the meeting number, or a label for a
/// day nobody teaches on.
///
/// Three things are worked out from the sheet rather than hard-coded:
///
/// * **Which row is the header**, found by looking for a row whose cells sit
///   directly above dates. That works whether the labels are "A"…"H",
///   "Block F", "Period 1" or "1A", because it never looks at the labels.
/// * **What the dates look like.** "Oct-13", "13-Oct", "2026-10-13",
///   "10/13/2026", "13/10/2026" and "October 13, 2026" all read. The format is
///   chosen for the COLUMN as a whole, not per cell.
/// * **Whether there is a meeting-number column at all.** With one, its
///   numbers and labels are used. Without, every dated row is a meeting and
///   they are numbered in order.
/// </summary>
public sealed class Timetable
{
    public required string Block { get; init; }
    public required IReadOnlyList<Meeting> Meetings { get; init; }
    public required IReadOnlyList<NonTeachingDay> NonTeachingDays { get; init; }

    /// <summary>The labels the sheet offers, for when the one asked for isn't there.</summary>
    public required IReadOnlyList<string> AvailableBlocks { get; init; }

    /// <summary>How the dates in this sheet were read, so a mis-read is visible.</summary>
    public required string DateFormat { get; init; }

    /// <summary>
    /// The academic year that a date with no year belongs to, worked out from
    /// today. A school year is named for the calendar year it starts in, and
    /// starts in the late summer — so in August 2026 the year is 2026/2027,
    /// and in March 2027 it is still 2026/2027.
    /// </summary>
    public static int AcademicYearStarting(DateOnly today) =>
        today.Month >= 8 ? today.Year : today.Year - 1;

    // ---- Date styles -----------------------------------------------------

    /// <summary>
    /// One way a school might write a date. Tried against a whole column at a
    /// time: a style only wins if EVERY date in the column reads under it,
    /// which is what stops "05/06" being guessed at cell by cell.
    /// </summary>
    private sealed record Style(string Name, string[] Formats, bool HasYear);

    private static readonly Style[] Styles =
    {
        new("year-month-day", new[] { "yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd" }, true),
        new("month name and day", new[] { "MMM-d", "MMM d", "MMMM d", "MMMM-d", "MMM.d", "MMM. d" }, false),
        new("day and month name", new[] { "d-MMM", "d MMM", "d MMMM", "d-MMMM" }, false),
        new("month name, day, year",
            new[] { "MMM d, yyyy", "MMMM d, yyyy", "MMM d yyyy", "MMMM d yyyy", "MMM-d-yyyy" }, true),
        new("day, month name, year", new[] { "d MMM yyyy", "d-MMM-yyyy", "d MMMM yyyy" }, true),
        new("month/day/year", new[] { "M/d/yyyy", "M/d/yy", "M-d-yyyy", "M-d-yy" }, true),
        new("day/month/year", new[] { "d/M/yyyy", "d/M/yy", "d-M-yyyy", "d-M-yy" }, true),
        new("month/day", new[] { "M/d", "M-d" }, false),
        new("day/month", new[] { "d/M", "d-M" }, false),
    };

    private static bool TryOne(Style style, string text, out DateTime value) =>
        DateTime.TryParseExact(text.Trim(), style.Formats, CultureInfo.InvariantCulture,
            DateTimeStyles.None, out value);

    /// <summary>True when a cell could be a date under any style at all.</summary>
    internal static bool LooksLikeDate(string text)
    {
        string value = text.Trim();
        if (value.Length is 0 or > 30) return false;
        foreach (var style in Styles)
            if (TryOne(style, value, out _)) return true;
        return false;
    }

    /// <summary>
    /// Read a whole column of dates under one consistent style.
    ///
    /// Styles are scored rather than guessed: every value must read, and among
    /// the styles that manage it the one implying the FEWEST year rollovers
    /// wins. A school year crosses at most one new year, so an interpretation
    /// that needs three is the wrong interpretation.
    /// </summary>
    private static bool TryReadColumn(IReadOnlyList<string> raw, int startYear,
                                      out List<DateOnly> dates, out string styleName)
    {
        dates = new List<DateOnly>();
        styleName = "";
        if (raw.Count == 0) return false;

        List<DateOnly>? best = null;
        int fewestRollovers = int.MaxValue;

        foreach (var style in Styles)
        {
            var parsed = new List<DateOnly>(raw.Count);
            int year = startYear, previousMonth = 0, rollovers = 0;
            bool ok = true;

            foreach (string cell in raw)
            {
                if (!TryOne(style, cell, out DateTime value)) { ok = false; break; }
                if (style.HasYear)
                {
                    parsed.Add(DateOnly.FromDateTime(value));
                    continue;
                }
                // No year in the text: carry one, rolling it forward the
                // moment the month goes backwards.
                if (previousMonth != 0 && value.Month < previousMonth) { year++; rollovers++; }
                previousMonth = value.Month;
                try { parsed.Add(new DateOnly(year, value.Month, value.Day)); }
                catch { ok = false; break; }
            }

            if (!ok || parsed.Count != raw.Count) continue;
            if (rollovers < fewestRollovers)
            {
                fewestRollovers = rollovers;
                best = parsed;
                styleName = style.Name;
            }
        }

        if (best is null) return false;
        dates = best;
        return true;
    }

    // ---- Reading the sheet ------------------------------------------------

    /// <summary>
    /// Labels compared without the words schools decorate them with, so "F",
    /// "Block F", "block f" and "F Block" are the same location.
    /// </summary>
    internal static string Normalize(string label)
    {
        string value = Regex.Replace(label.Trim().ToUpperInvariant(),
            @"\b(BLOCK|PERIOD|SECTION|CLASS|DAY)\b", " ");
        return Regex.Replace(value, @"[^A-Z0-9]", "");
    }

    public static Timetable Parse(string csv, string block, int startYear)
    {
        var rows = ReadCsv(csv);

        // The header is the row with the most cells sitting directly above a
        // date. Nothing is assumed about what the labels look like, so this
        // works for "A", "Block F", "Period 3" or "Green" alike.
        //
        // Two rules keep it honest. A row containing a date in a column it
        // would otherwise score cannot be the header — otherwise the LAST row
        // of dates would look like a header for the rows beneath it. And ties
        // go to the later row, because a sheet's title and instructions sit
        // above the header, never below it.
        int headerAt = -1, headerScore = 0;
        for (int i = 0; i < rows.Count; i++)
        {
            int score = 0;
            for (int c = 0; c < rows[i].Count; c++)
            {
                string label = rows[i][c].Trim();
                if (label.Length == 0 || LooksLikeDate(label)) continue;
                for (int r = i + 1; r < Math.Min(i + 4, rows.Count); r++)
                    if (c < rows[r].Count && LooksLikeDate(rows[r][c])) { score++; break; }
            }
            if (score >= headerScore && score > 0) { headerScore = score; headerAt = i; }
        }
        if (headerAt < 0)
            throw new AssistRefusal(
                "That sheet doesn’t look like a timetable — no row of labels with dates underneath was found.");

        var header = rows[headerAt];
        var available = new List<string>();
        int column = -1;
        for (int i = 0; i < header.Count; i++)
        {
            string label = header[i].Trim();
            if (label.Length == 0) continue;
            bool hasDates = false;
            for (int r = headerAt + 1; r < Math.Min(headerAt + 4, rows.Count); r++)
                if (i < rows[r].Count && LooksLikeDate(rows[r][i])) { hasDates = true; break; }
            if (!hasDates) continue;

            available.Add(label);
            if (Normalize(label) == Normalize(block)) column = i;
        }

        if (column < 0)
            throw new AssistRefusal(
                $"That timetable has no “{block.Trim()}”. It has " + string.Join(", ", available) + ".");

        // Collect the block's rows: a date, and whatever sits beside it.
        var raw = new List<(string When, string Marker)>();
        for (int i = headerAt + 1; i < rows.Count; i++)
        {
            var row = rows[i];
            if (column >= row.Count) continue;
            string when = row[column].Trim();
            if (!LooksLikeDate(when)) continue;
            string marker = column + 1 < row.Count ? row[column + 1].Trim() : "";
            raw.Add((when, marker));
        }
        if (raw.Count == 0)
            throw new AssistRefusal($"“{block.Trim()}” has no dates under it in that sheet.");

        if (!TryReadColumn(raw.Select(r => r.When).ToList(), startYear, out var dates, out string styleName))
            throw new AssistRefusal(
                $"The dates under “{block.Trim()}” aren’t all written the same way, so they can’t be read " +
                $"reliably. The first is “{raw[0].When}”.");

        // A numbers column is optional. Without one, every dated row is a
        // meeting and they are numbered in the order they appear.
        bool numbered = raw.Any(r => int.TryParse(r.Marker, NumberStyles.None,
            CultureInfo.InvariantCulture, out _));

        var meetings = new List<Meeting>();
        var nonTeaching = new List<NonTeachingDay>();
        for (int i = 0; i < raw.Count; i++)
        {
            string marker = raw[i].Marker;
            if (!numbered)
            {
                meetings.Add(new Meeting(meetings.Count + 1, dates[i]));
                continue;
            }
            if (int.TryParse(marker, NumberStyles.None, CultureInfo.InvariantCulture, out int number))
                meetings.Add(new Meeting(number, dates[i]));
            else if (marker.Length > 0)
                nonTeaching.Add(new NonTeachingDay(dates[i], marker));
        }

        if (meetings.Count == 0)
            throw new AssistRefusal($"“{block.Trim()}” has no class meetings in that sheet — only days off.");

        return new Timetable
        {
            Block = header[column].Trim(),
            Meetings = meetings,
            NonTeachingDays = nonTeaching,
            AvailableBlocks = available,
            DateFormat = styleName,
        };
    }

    /// <summary>
    /// Construct a timetable directly from a list of dates (e.g. from TimetableMemory).
    /// </summary>
    public static Timetable FromDates(IReadOnlyList<DateOnly> dates, string source = "")
    {
        var meetings = dates.Select((d, i) => new Meeting(i + 1, d)).ToList();
        return new Timetable
        {
            Block = string.IsNullOrWhiteSpace(source) ? "Class Dates" : source,
            Meetings = meetings,
            NonTeachingDays = Array.Empty<NonTeachingDay>(),
            AvailableBlocks = Array.Empty<string>(),
            DateFormat = "yyyy-MM-dd",
        };
    }

    /// <summary>
    /// An even spread of <paramref name="count"/> classes across the
    /// meetings — the STARTING POINT, not the answer.
    ///
    /// Which lesson belongs on which day is a judgement about content: a
    /// double period, a lesson that must follow an investigation, a class that
    /// would be left holding nothing but a warm-up if it were split. The tool
    /// cannot see any of that, so it offers a sensible spread and expects to
    /// be overruled by whoever can read the agendas.
    /// </summary>
    public List<Meeting> EvenSpread(int count)
    {
        if (count <= 0) return new List<Meeting>();
        if (count >= Meetings.Count) return Meetings.Take(count).ToList();

        var chosen = new List<Meeting>(count);
        for (int i = 0; i < count; i++)
        {
            // Anchors the first class on the first meeting and the last on the
            // last, so a re-dated course spans the year it was given.
            int index = count == 1 ? 0 : (int)Math.Round(i * (Meetings.Count - 1.0) / (count - 1));
            chosen.Add(Meetings[index]);
        }
        return chosen;
    }

    /// <summary>
    /// The same block, from a given first day of class onwards.
    ///
    /// A block runs the whole year, but a section of a course does not span
    /// semesters — so a course starting in February uses the back half of it
    /// and nothing before. Meeting numbers are left as the sheet has them, so
    /// a teacher reading the timetable and a plan referring to "meeting 31"
    /// are talking about the same day.
    /// </summary>
    public Timetable From(DateOnly firstDay)
    {
        var kept = Meetings.Where(m => m.Date >= firstDay).ToList();
        if (kept.Count == 0)
            throw new AssistRefusal(
                $"Block {Block} has no class meetings on or after {DateText.Iso(firstDay)}. " +
                $"It runs {DateText.Iso(Meetings[0].Date)} to {DateText.Iso(Meetings[^1].Date)}.");

        return new Timetable
        {
            Block = Block,
            Meetings = kept,
            NonTeachingDays = NonTeachingDays.Where(d => d.Date >= firstDay).ToList(),
            AvailableBlocks = AvailableBlocks,
            DateFormat = DateFormat,
        };
    }

    public Meeting? ByNumber(int number) =>
        Meetings.FirstOrDefault(m => m.Number == number) is { Number: > 0 } found ? found : null;

    /// <summary>A minimal CSV reader: quoted fields, embedded commas and newlines.</summary>
    internal static List<List<string>> ReadCsv(string text)
    {
        var rows = new List<List<string>>();
        var row = new List<string>();
        var field = new StringBuilder();
        bool quoted = false;

        for (int i = 0; i < text.Length; i++)
        {
            char c = text[i];
            if (quoted)
            {
                if (c == '"')
                {
                    if (i + 1 < text.Length && text[i + 1] == '"') { field.Append('"'); i++; }
                    else quoted = false;
                }
                else field.Append(c);
                continue;
            }
            switch (c)
            {
                case '"': quoted = true; break;
                case ',': row.Add(field.ToString()); field.Clear(); break;
                case '\r': break;
                case '\n':
                    row.Add(field.ToString()); field.Clear();
                    rows.Add(row); row = new List<string>();
                    break;
                default: field.Append(c); break;
            }
        }
        row.Add(field.ToString());
        if (row.Count > 1 || row[0].Length > 0) rows.Add(row);
        return rows;
    }
}

/// <summary>One numbered class meeting on a date.</summary>
public readonly record struct Meeting(int Number, DateOnly Date);

/// <summary>A day the timetable names but no unit content belongs on.</summary>
public readonly record struct NonTeachingDay(DateOnly Date, string Label);

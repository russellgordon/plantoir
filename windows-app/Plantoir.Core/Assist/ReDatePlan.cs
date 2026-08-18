using System;
using System.Collections.Generic;
using System.Linq;

namespace Plantoir.Core.Assist;

/// <summary>
/// Moving a section's classes onto a real timetable, worked out before
/// anything is written.
///
/// Plain sentences, no arrows, no markdown. Matches macOS SectionReDatePlan.
/// </summary>
public sealed class ReDatePlan
{
    public required string CourseCode { get; init; }
    public required int SectionNumber { get; init; }
    public required string Block { get; init; }
    public required IReadOnlyList<PlannedDate> Dates { get; init; }

    /// <summary>
    /// Concepts, exercises and the rest, carried along by the same amount as
    /// the lesson that anchors them.
    /// </summary>
    public required IReadOnlyList<PlannedDate> Materials { get; init; }

    /// <summary>
    /// Year-round reference pages moved to the first day of class: everything
    /// Key Links points at, and every curriculum page.
    /// </summary>
    public IReadOnlyList<PlannedDate> Reference { get; init; } = Array.Empty<PlannedDate>();

    public int CurriculumCount { get; init; }

    /// <summary>Date problems this change would leave behind, in plain words.</summary>
    public required IReadOnlyList<string> Problems { get; init; }

    /// <summary>Days the timetable names that no unit content belongs on.</summary>
    public required IReadOnlyList<NonTeachingDay> NonTeachingDays { get; init; }

    /// <summary>Every date this section meets, not only the ones this plan uses.</summary>
    public IReadOnlyList<DateOnly> AllMeetings { get; init; } = Array.Empty<DateOnly>();

    /// <summary>Meetings the spread did not use.</summary>
    public required int UnusedMeetings { get; init; }

    /// <summary>Classes with no day of their own, all sitting on the last one.</summary>
    public int Overflowing { get; init; }

    public IReadOnlyList<ReDateMove> Moves { get; init; } = Array.Empty<ReDateMove>();
    public DateOnly FirstDay { get; init; }
    public DateOnly LastDay { get; init; }
    public int ClassCount { get; init; }
    public int SpareDates { get; init; }

    public IEnumerable<PlannedDate> Changing =>
        Dates.Concat(Materials).Concat(Reference).Where(d => d.WillChange);

    public bool ChangesNothing => Moves.Count > 0 ? Moves.Count == 0 : !Changing.Any();

    public string Describe(int mostListed = 15)
    {
        var lines = new List<string>();
        lines.Add($"{CourseCode} Section {SectionNumber}: re-dating onto the class dates on file.");
        lines.Add("");

        if (ChangesNothing)
        {
            lines.Add("Every page is already on the day it should be.");
            return string.Join("\n", lines);
        }

        int count = ClassCount > 0 ? ClassCount : Dates.Count;
        var first = FirstDay != default ? FirstDay : (Dates.Count > 0 ? Dates[0].New : default);
        var last = LastDay != default ? LastDay : (Dates.Count > 0 ? Dates[^1].New : default);

        lines.Add($"{count} {(count == 1 ? "class runs" : "classes run")} from " +
                  $"{first:yyyy-MM-dd} ({first.DayOfWeek}) to " +
                  $"{last:yyyy-MM-dd} ({last.DayOfWeek}).");

        int spare = SpareDates > 0 ? SpareDates : UnusedMeetings;
        if (spare > 0)
        {
            lines.Add($"{spare} recorded {(spare == 1 ? "date is" : "dates are")} " +
                      "left over at the end.");
        }

        if (Overflowing > 0)
        {
            lines.Add($"{Overflowing} {(Overflowing == 1 ? "class has" : "classes have")} no day " +
                      $"of {(Overflowing == 1 ? "its" : "their")} own this year, so " +
                      $"{(Overflowing == 1 ? "it goes" : "they all go")} on " +
                      $"{last:yyyy-MM-dd} with the last one. Move or delete " +
                      $"{(Overflowing == 1 ? "it" : "them")} when you have decided what to do.");
        }
        lines.Add("");

        var moves = Moves.Count > 0
            ? Moves
            : Dates.Concat(Materials).Concat(Reference).Where(d => d.WillChange).Select(d =>
                new ReDateMove(d.Title, d.RelativePath, d.Current, d.New, ReDateReason.AClass)).ToList();

        string word = moves.Count == 1 ? "page" : "pages";
        lines.Add($"{moves.Count} {word} would move:");
        int listed = 0;
        foreach (var move in moves)
        {
            if (listed == mostListed)
            {
                lines.Add($"…and {moves.Count - listed} more.");
                break;
            }
            switch (move.Reason)
            {
                case ReDateReason.AClass:
                    lines.Add($"“{move.Title}” moves to {move.To:yyyy-MM-dd}.");
                    break;
                case ReDateReason.BroughtBy:
                    lines.Add($"“{move.Title}” moves to {move.To:yyyy-MM-dd}, with “{move.ClassTitle}”.");
                    break;
                case ReDateReason.YearRound:
                    lines.Add($"“{move.Title}” moves to {move.To:yyyy-MM-dd}, the first day of class, " +
                              "because Key Links points at it.");
                    break;
            }
            listed++;
        }

        lines.Add("");
        lines.Add("Curriculum pages are left alone — Plantoir dates those itself every time it " +
                  "builds the site.");
        return string.Join("\n", lines);
    }
}

public enum ReDateReason
{
    AClass,
    BroughtBy,
    YearRound
}

public sealed record ReDateMove(
    string Title,
    string RelativePath,
    DateOnly? From,
    DateOnly To,
    ReDateReason Reason,
    string? ClassTitle = null,
    bool Unpublishes = false);

/// <summary>One class page and the day it would move to.</summary>
public sealed record PlannedDate(
    string Title,
    string RelativePath,
    string FrontmatterKey,
    DateOnly? Current,
    DateOnly New,
    int MeetingNumber,
    bool Unpublishes = false)
{
    public bool WillChange => Current != New || Unpublishes;

    private string Meeting => MeetingNumber > 0 ? $", meeting {MeetingNumber}" : "";

    public string Describe() =>
        WillChange
            ? $"{Title}  {Show(Current)} → {New:yyyy-MM-dd} ({New:ddd}){Meeting}"
            : $"{Title}  {New:yyyy-MM-dd} ({New:ddd}){Meeting} — unchanged";

    private static string Show(DateOnly? value) => value is { } date ? date.ToString("yyyy-MM-dd") : "no date";
}

using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// Making room in a course that is already built out.
///
/// A teacher discovers in November that Unit 2 needs another day on a task.
/// Doing that by hand means renaming every class after it, re-dating every one
/// of them onto the days the class actually meets, and finding every link that
/// pointed at a page whose name just changed — across a course that might hold
/// two hundred pages. That is the tedium this exists to remove.
///
/// It is also the most dangerous thing the assistant can do, because it
/// renames pages a teacher's links point at. So the plan names the renames,
/// counts the links, and says how the dates move, before anything happens.
/// </summary>
public sealed class InsertPlan
{
    public required string CourseCode { get; init; }
    public required int SectionNumber { get; init; }
    public required int Unit { get; init; }
    public required int AtDay { get; init; }

    /// <summary>The course's naming — required, so no plan can fall back to "Unit … Day …" (#268).</summary>
    public required ClassPageNaming Naming { get; init; }

    /// <summary>Where the room is made, named the way the COURSE names a page (<c>insertion.positionInSentences</c>).</summary>
    public string PositionTitle => Naming.Title(Unit, AtDay);

    /// <summary>The blank classes that would be made room for.</summary>
    public required IReadOnlyList<NewClass> Added { get; init; }

    /// <summary>Pages that would be renamed, in the order they must happen.</summary>
    public required IReadOnlyList<Rename> Renames { get; init; }

    /// <summary>Every class whose date would move, new name where it has one.</summary>
    public required IReadOnlyList<DateMove> Moves { get; init; }

    /// <summary>Links that would be rewritten to follow a renamed page.</summary>
    public required int LinksToRewrite { get; init; }

    public required IReadOnlyList<string> Problems { get; init; }

    public bool ChangesNothing => Added.Count == 0 && Renames.Count == 0 && Moves.Count == 0;

    /// <summary>The plan in the class form — what the MODEL reads, in every course.</summary>
    public string Describe() => Describe(ClassNoun.Class);

    /// <summary>The plan in a course's own noun: the meeting form is the TEACHER's card only (#274).</summary>
    public string Describe(ClassNoun noun)
    {
        var lines = new List<string>();

        if (ChangesNothing)
        {
            lines.Add($"Nothing would change in {CourseCode} Section {SectionNumber}.");
            foreach (string problem in Problems) lines.Add("• " + problem);
            return string.Join("\n", lines);
        }

        string section = SectionNumber.ToString();
        lines.Add(noun == ClassNoun.Meeting
            ? AssistWording.WouldMakeRoomForAMeeting(Added.Count, PositionTitle, CourseCode, section)
            : AssistWording.WouldMakeRoom(Added.Count, PositionTitle, CourseCode, section));
        lines.Add("");

        lines.Add($"New, and unpublished until you write {(Added.Count == 1 ? "it" : "them")}:");
        foreach (var added in Added)
            lines.Add($"  {added.Title}  ({DateText.Iso(added.Date)} {added.Date.DayOfWeek})");

        if (Renames.Count > 0)
        {
            lines.Add("");
            lines.Add($"Renamed — {Renames.Count} page{(Renames.Count == 1 ? "" : "s")}:");
            foreach (var rename in Renames.Take(MostShown))
                lines.Add($"  {rename.From} → {rename.To}");
            if (Renames.Count > MostShown)
                lines.Add($"  …and {Renames.Count - MostShown} more.");

            // The number that matters most, and the one a teacher cannot check
            // for themselves without opening every page in the course.
            lines.Add("");
            lines.Add(LinksToRewrite == 0
                ? "No links point at any of those names, so nothing else needs changing."
                : $"{LinksToRewrite} link{(LinksToRewrite == 1 ? "" : "s")} " +
                  $"point{(LinksToRewrite == 1 ? "s" : "")} at those names and would be updated to match.");
        }

        if (Moves.Count > 0)
        {
            lines.Add("");
            lines.Add(noun == ClassNoun.Meeting
                ? AssistWording.MovedToLaterDaysForAMeeting(Moves.Count)
                : AssistWording.MovedToLaterDays(Moves.Count));
            foreach (var move in Moves.Take(MostShown))
            {
                string fromText = move.From.HasValue ? DateText.Iso(move.From.Value) : "no date";
                lines.Add($"  {move.Title}  {fromText} → {DateText.Iso(move.To)}");
            }
            if (Moves.Count > MostShown)
                lines.Add($"  …and {Moves.Count - MostShown} more.");
        }

        foreach (string problem in Problems) lines.Add("• " + problem);
        return string.Join("\n", lines);
    }

    private const int MostShown = 10;
}

/// <summary>A page that changes name, and the file it becomes.</summary>
public sealed record Rename(string From, string To, string FromPath, string ToPath);

/// <summary>A class that keeps its name but moves to a different day.</summary>
public sealed record DateMove(string Title, string RelativePath, DateOnly? From, DateOnly To);

namespace Plantoir.Core.Assist;

/// <summary>
/// Duplicating a lesson as the next class: everything both halves of the
/// request need, worked out once.
///
/// <para>"Duplicate Unit 3, Day 2 as my next class" does NOT put a copy after
/// the last class of the course. It makes the SOURCE'S own next day — Unit 3,
/// Day 3 — and everything from there on shuffles along, which is why this
/// carries an <see cref="InsertPlan"/> rather than a date and a title. Making
/// room is <see cref="AssistWorkspace.PlanInsertClasses"/>'s job and is not
/// reimplemented here: it renames the later days of the unit highest-day
/// first, re-dates every class after the insertion point onto days the section
/// actually meets, and counts the links that would be rewritten.</para>
/// </summary>
public sealed class DuplicateClassPlan
{
    public required string CourseCode { get; init; }
    public required int SectionNumber { get; init; }

    /// <summary>The page being copied, as a teacher would name it.</summary>
    public required string SourceTitle { get; init; }

    /// <summary>What that page holds now. Read at plan time, written at apply time.</summary>
    public required string SourceText { get; init; }

    /// <summary>What the copy becomes — the source's next day in its own unit.</summary>
    public required string NewTitle { get; init; }

    /// <summary>The first day this section meets that the copy can have.</summary>
    public required DateOnly NewDate { get; init; }

    /// <summary>How room is made for it, and what else moves as a result.</summary>
    public required InsertPlan Insertion { get; init; }

    /// <summary>
    /// How many OTHER class pages move, counted once each.
    ///
    /// <para>A renamed page is usually re-dated as well, so the two lists
    /// overlap; a later unit's pages are re-dated and never renamed. Counting
    /// the union is what makes the sentence a teacher reads true in both
    /// shapes.</para>
    /// </summary>
    public int OtherClassesMoving =>
        Insertion.Renames.Select(r => r.To)
            .Concat(Insertion.Moves.Select(m => m.Title))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Count();

    /// <summary>
    /// Whether anything but the copy itself changes.
    ///
    /// <para>This is what decides whether the change goes on the undo list at
    /// all, and it is deliberately STRICTER than the mac's
    /// <c>!request.plan.renames.isEmpty</c>. Renames happen only within the
    /// unit being changed, so duplicating the LAST day of a unit renames
    /// nothing while re-dating every class of every later unit — where the mac
    /// then offers an undo that takes back the new page and leaves the rest of
    /// the year moved.</para>
    /// </summary>
    public bool MovesOtherClasses => Insertion.Renames.Count > 0 || Insertion.Moves.Count > 0;

    /// <summary>The card a teacher agrees to before anything is written.</summary>
    public string Describe()
    {
        var lines = new List<string>
        {
            ClassChangeWording.WouldBeCopiedTo(SourceTitle, NewTitle, NewDate),
            ClassChangeWording.TheCopyStartsHidden,
        };

        if (MovesOtherClasses)
        {
            lines.Add("");
            lines.Add(ClassChangeWording.OtherClassesWouldMove(OtherClassesMoving, Insertion.Renames.Count));
        }

        return string.Join("\n", lines);
    }
}

using System;
using System.Text;

namespace Plantoir.Core.Scripting;

/// <summary>
/// What a section's stop sweep reclaimed, and how it reaches the trail.
///
/// Lives in Core rather than beside <c>PreviewStopper</c> in the app for one
/// reason: the app project cannot be referenced by Plantoir.Tests, and a
/// count that is parsed out of another program's output is exactly the kind
/// of thing that must be tested rather than eyeballed. The mac keeps its
/// equivalent (<c>PreviewStopper.countReclaimed</c>) under test too.
/// </summary>
public static class ReclaimedProcesses
{
    /// <summary>
    /// How many processes the launcher said it ended, or null when it said
    /// nothing of the kind.
    ///
    /// PARSED rather than counted, because the counting happens where the
    /// rule runs — see contracts/shared-rules.json → stopPreview. The
    /// launcher's own sentence ("Stopped 3 process(es).") is the only report
    /// of it that crosses back, and both platforms read that line the same
    /// way: find "Stopped ", take the digits that follow, stop at the first
    /// thing that is not one.
    /// </summary>
    public static int? Count(string printed)
    {
        if (string.IsNullOrEmpty(printed)) return null;
        foreach (string line in printed.Split('\n'))
        {
            int at = line.IndexOf("Stopped ", StringComparison.Ordinal);
            if (at < 0) continue;
            int index = at + "Stopped ".Length;
            var digits = new StringBuilder();
            while (index < line.Length && char.IsDigit(line[index]))
            {
                digits.Append(line[index]);
                index++;
            }
            if (digits.Length > 0 && int.TryParse(digits.ToString(), out int value))
                return value;
        }
        return null;
    }

    /// <summary>
    /// The sentence a teacher would recognise for a given count — "reclaimed
    /// 3 leftover website-builder processes", never the launcher's own
    /// "Stopped 3 process(es)", and never a function name.
    /// </summary>
    public static string Wording(int count) => count == 1
        ? "reclaimed 1 leftover website-builder process"
        : $"reclaimed {count} leftover website-builder processes";

    /// <summary>
    /// Puts the count on the trail.
    ///
    /// Nothing is recorded when the launcher said nothing countable: it
    /// declines to run at all without the bundled website builder, and a line
    /// claiming zero would be indistinguishable from a sweep that ran and
    /// found nothing. Those are different facts and the trail must not blur
    /// them — telling them apart is the whole reason this event exists. A
    /// teacher reporting a publish that stopped halfway is choosing between
    /// "there was nothing left to stop" and "a build was still going and was
    /// ended", and nothing else on the trail separates the two.
    /// </summary>
    public static void Note(string printed, string courseCode, int sectionNumber)
    {
        if (Count(printed) is not int reclaimed) return;
        ActivityTrail.Note(ActivityTrail.Event.SectionProcessesReclaimed,
                           Wording(reclaimed), courseCode, sectionNumber);
    }
}

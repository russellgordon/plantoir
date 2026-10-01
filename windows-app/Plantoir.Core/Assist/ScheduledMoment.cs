using System;
using System.Globalization;

namespace Plantoir.Core.Assist;

/// <summary>
/// Settle a time of day — <c>"06:30"</c>, <c>"tomorrow 06:30"</c> — into the
/// whole moment it means, <c>"yyyy-MM-dd HH:mm"</c>, against ONE clock, once,
/// where the call is made (#193).
/// </summary>
/// <remarks>
/// <para><b>Why the settling is not optional.</b> <c>ScheduledDeploy.ReadTheMoment</c>'s
/// lenient step reads a bare <c>"06:30"</c> as TODAY at 06:30 — usually a
/// moment already past — and says nothing. The mac's runner refuses a bare
/// time loudly. A matcher without this step would therefore be a SILENT
/// wrong day here; that is why both are one piece.</para>
///
/// <para><b>The rule:</b> a bare time is the next such time, forwards,
/// counting today while it is still to come — the rule a bare weekday already
/// gets. The same minute counts as gone. An explicit "today" or "tomorrow"
/// is obeyed, even into the past (the existing "already passed" refusal then
/// says so). A whole moment is handed straight back — the settler is
/// IDEMPOTENT, which is what lets the card, the trail line and the act each
/// read the same settled call. Anything else is not settled (null), so the
/// tool meets it with its own refusal. <c>deployAtATime.resolving</c> is the
/// specification.</para>
///
/// <para><b>Daylight saving, which .NET does not do for you.</b> On the
/// morning the clocks go forward a wall time like 02:30 does not exist;
/// <c>TimeZoneInfo.ConvertTimeToUtc</c> THROWS on it. Foundation moves it
/// FORWARD, so the mac settles 02:30 onto 03:30 and the card names it; this
/// does the same, minute by minute to the first wall time that exists. On the
/// night the clocks go back, a repeated wall time is taken as its EARLIER
/// instant, as <c>Calendar</c> picks. Whatever the zone does, the settled text
/// must read back through <c>ScheduledDeploy.ReadTheMoment</c> — the card and
/// the trail line both depend on it, and a test asserts it.</para>
/// </remarks>
public static class ScheduledMoment
{
    public const string WrittenForm = "yyyy-MM-dd HH:mm";

    /// <param name="when">What the card or the model wrote.</param>
    /// <param name="today">This app's one day.</param>
    /// <param name="now">This app's one wall clock, in <paramref name="zone"/>.</param>
    /// <returns>The whole moment, or null when there is nothing this settles.</returns>
    public static string? Settle(string when, DateOnly today, DateTime now, TimeZoneInfo zone)
    {
        string text = when.Trim().ToLowerInvariant();
        string dayWord = "";
        string[] words = text.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (words.Length == 2)
        {
            dayWord = words[0];
            text = words[1];
        }
        else if (words.Length != 1) return null;

        if (!TimeOnly.TryParseExact(text, "HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out var time) ||
            text.Length != 5)
            return null;

        switch (dayWord)
        {
            case "":
                var todayAt = ExistingWallTime(today.ToDateTime(time), zone);
                return Written(Instant(todayAt, zone) > Instant(now, zone)
                    ? todayAt
                    : ExistingWallTime(today.AddDays(1).ToDateTime(time), zone));
            case "today":
                return Written(ExistingWallTime(today.ToDateTime(time), zone));
            case "tomorrow":
                return Written(ExistingWallTime(today.AddDays(1).ToDateTime(time), zone));
            default:
                return null;
        }
    }

    /// <summary>Settle against the machine's own clock and zone.</summary>
    public static string? Settle(string when, DateOnly today, DateTime now) =>
        Settle(when, today, now, TimeZoneInfo.Local);

    private static string Written(DateTime wall) =>
        wall.ToString(WrittenForm, CultureInfo.InvariantCulture);

    /// <summary>
    /// A wall time that does not exist, moved FORWARD by the gap the clocks
    /// jumped — 02:30 onto 03:30 when they go from 02:00 to 03:00 — which is
    /// what Foundation's <c>Calendar</c> does on the mac. (Moving to the first
    /// minute that exists would give 03:00, a different moment from the
    /// mac's for the same sentence; the first draft here did exactly that.)
    /// </summary>
    internal static DateTime ExistingWallTime(DateTime wall, TimeZoneInfo zone)
    {
        var unspecified = DateTime.SpecifyKind(wall, DateTimeKind.Unspecified);
        if (!zone.IsInvalidTime(unspecified)) return unspecified;
        var gap = zone.GetUtcOffset(unspecified.AddHours(6)) - zone.GetUtcOffset(unspecified.AddHours(-6));
        var moved = unspecified + (gap > TimeSpan.Zero ? gap : TimeSpan.FromHours(1));
        // A zone with a gap wider than the window above is not one that
        // exists, but a wall time that still does not exist is not handed on.
        for (int minutes = 0; minutes < 24 * 60 && zone.IsInvalidTime(moved); minutes++) moved = moved.AddMinutes(1);
        return moved;
    }

    /// <summary>The instant a wall time names — the EARLIER one when the clocks went back.</summary>
    private static DateTime Instant(DateTime wall, TimeZoneInfo zone)
    {
        var unspecified = DateTime.SpecifyKind(ExistingWallTime(wall, zone), DateTimeKind.Unspecified);
        if (zone.IsAmbiguousTime(unspecified))
        {
            var offsets = zone.GetAmbiguousTimeOffsets(unspecified);
            var largest = offsets[0] > offsets[1] ? offsets[0] : offsets[1];
            return DateTime.SpecifyKind(unspecified - largest, DateTimeKind.Utc);
        }
        return TimeZoneInfo.ConvertTimeToUtc(unspecified, zone);
    }
}

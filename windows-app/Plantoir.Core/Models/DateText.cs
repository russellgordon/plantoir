using System.Globalization;

namespace Plantoir.Core.Models;

/// <summary>
/// The one place a date becomes text that Plantoir will read back, sort, or
/// hand to something outside the teacher's language — and the one place such
/// text becomes a date again.
///
/// <para><b>Why a helper, and not <c>ToString("yyyy-MM-dd")</c> where it is
/// needed.</b> A custom format string renders the YEAR in the current
/// culture's default calendar. The <c>-</c> is a literal and is safe; the
/// <c>yyyy</c> is not. On a machine whose regional format is Thai the default
/// calendar is Buddhist, and <c>new DateTime(2026, 9, 9).ToString("yyyy-MM-dd")</c>
/// is <c>2569-09-09</c> — measured on Windows 11 (GitHub #144). Before this
/// helper existed, 66 sites in this app formatted a date that way and none
/// passed a culture. The dangerous ones WROTE: the remembered timetable, a
/// page's <c>created:</c>, a transcript's file name. The reader on the other
/// end was invariant (<see cref="CultureInfo.InvariantCulture"/> reads
/// <c>2569</c> as the Gregorian year 2569), so a remembered class landed 543
/// years out and nothing reported a fault. A display sentence with the same
/// fault is wrong once; a written file is wrong until somebody notices.</para>
///
/// <para><b>The mac is immune by construction</b>: its <c>CalendarDay.text</c>
/// is three integers through <c>String(format:)</c>, no calendar and no locale.
/// This helper is how the C# reaches the same place with one call, so that
/// the next site added is one call rather than one more chance to forget.
/// A test walks the product sources and fails on any site that renders a year
/// without going through here (<c>DateTextTests</c>), which is what keeps this
/// fixed rather than fixed once.</para>
///
/// <para><b>What is deliberately NOT routed through here.</b>
/// <c>TaskScheduling</c> formats a date for <c>schtasks.exe</c> and parses
/// its output; both are in the machine's own culture because that program
/// accepts nothing else. <c>BackupItem</c> and <c>ArchivedItem</c> show a
/// month by name to the teacher and say <c>CurrentCulture</c> out loud. A
/// sentence that names a weekday and a month with no year is left cultural
/// too: it is read by a person, in their language, and carries nothing a
/// calendar can shift.</para>
///
/// <para><b>Reading is half of it.</b> An invariant write read back with a
/// bare <c>DateTime.TryParse</c> is WORSE than the old state: under th-TH
/// <c>2026-09-20</c> parses as the year 1483, because the reader takes the
/// digits as a Buddhist year. Every string this class writes is read with
/// <see cref="TryReadDay"/> or with <see cref="CultureInfo.InvariantCulture"/>
/// passed explicitly, and a writer changed here must have its reader checked
/// in the same change.</para>
/// </summary>
public static class DateText
{
    /// <summary>The ISO day, <c>yyyy-MM-dd</c>, in the Gregorian calendar.</summary>
    public const string IsoDay = "yyyy-MM-dd";

    /// <summary>The trail's and transcripts' moment, <c>yyyy-MM-dd HH:mm:ss</c>.</summary>
    public const string StampFormat = "yyyy-MM-dd HH:mm:ss";

    /// <summary>A day as <c>2026-09-09</c>, whatever the machine's regional format.</summary>
    public static string Iso(DateOnly day) => day.ToString(IsoDay, CultureInfo.InvariantCulture);


    /// <summary>
    /// A moment as <c>2026-09-09 14:15:30</c>, for the trail and the run
    /// transcripts. The <c>:</c> in a custom format is the culture's TIME
    /// SEPARATOR, not a literal, so a bare <c>HH:mm:ss</c> renders
    /// <c>14.15.30</c> on a Finnish or Danish machine — the same class of
    /// fault as the year, one column over.
    /// </summary>
    public static string Stamp(DateTime moment) => moment.ToString(StampFormat, CultureInfo.InvariantCulture);

    /// <summary>
    /// A moment in a custom <paramref name="format"/>, Gregorian. For the few
    /// shapes that are not the ISO day or the stamp — a file-name stamp with
    /// underscores, a report name with "at" — so that a format string never
    /// again appears in product code without its culture.
    /// </summary>
    public static string Invariant(DateTime moment, string format) =>
        moment.ToString(format, CultureInfo.InvariantCulture);

    /// <inheritdoc cref="Invariant(DateTime, string)"/>
    public static string Invariant(DateOnly day, string format) =>
        day.ToString(format, CultureInfo.InvariantCulture);

    /// <summary>
    /// Reads a day written as <c>yyyy-MM-dd</c> — by this app, or by a teacher
    /// answering a tool that asked for that shape — and nothing else.
    /// Invariant, so the digits are a Gregorian year on every machine, and
    /// EXACT, because a lenient invariant parse takes <c>09/08/2026</c> as
    /// September the 8th, which a teacher in Canada or Britain did not mean:
    /// a date in any other shape is refused, and the refusal already says
    /// which shape to use.
    /// </summary>
    public static bool TryReadDay(string? text, out DateOnly day)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            day = default;
            return false;
        }
        return DateOnly.TryParseExact(text.Trim(), IsoDay, CultureInfo.InvariantCulture, DateTimeStyles.None, out day);
    }
}

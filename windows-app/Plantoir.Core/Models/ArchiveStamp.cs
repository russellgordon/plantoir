namespace Plantoir.Core.Models;

/// <summary>
/// Whether the moment written into an archive or a backup's name —
/// <c>ICS3U_2026-08-09_141530.zip</c> — is one Plantoir could have stamped.
///
/// <para><b>Why this exists at all, when this app has always written the
/// stamp correctly.</b> Both ends here are pinned to
/// <see cref="System.Globalization.CultureInfo.InvariantCulture"/>
/// (<see cref="CourseArchiver.TimestampedName"/>,
/// <see cref="ArchivedItem.From"/>, <see cref="BackupItem.From"/>), so no
/// Windows machine has ever written a name in its own calendar. The mac
/// did, until 2026-09-10: a <c>DateFormatter</c> with a format and no locale
/// renders <c>yyyy</c> in whatever calendar the Mac is set to, so the same
/// instant was written <c>2569-08-09_141530</c> on a Buddhist Mac,
/// <c>0008-08-09_141530</c> on a Japanese one, <c>1448-02-26_141530</c> on
/// an Islamic one and <c>2018-12-03_141530</c> on an Ethiopic one. Those
/// zips are on teachers' disks, and a working folder moves between
/// machines.</para>
///
/// <para><b>What that costs HERE is a deleted backup.</b> Invariant parsing
/// reads <c>2569-08-09_141530</c> perfectly well as the year 2569, so a zip
/// carried in from a pre-fix Thai Mac sorts as the NEWEST thing in the
/// folder, takes one of the five places
/// <see cref="CourseArchiver.MostBackupsKept"/> keeps, and pushes a real
/// backup off the disk with nothing reported. A stamp that cannot be true is
/// therefore not allowed to decide anything destructive — see
/// <see cref="CourseArchiver.PruneBackups"/>, which skips such a backup
/// instead of counting it. It stays LISTED, so the teacher can still restore
/// it or delete it themselves; only the one thing about it that is known to
/// be wrong — its date — stops being believed.</para>
///
/// <para>The counterpart on the mac is <c>ArchiveStamp.swift</c>, and the
/// bounds below are its bounds. They are contract data there
/// (<c>contracts/course-management.json</c> → <c>zipNames</c> →
/// <c>couldHaveBeenStamped</c>) on the branch that has not merged yet; when
/// it does, this file's two constants get pinned against it and the cases
/// run from the JSON — issue #161, part 2.</para>
/// </summary>
public static class ArchiveStamp
{
    /// <summary>
    /// The earliest moment a Plantoir archive or backup can name.
    ///
    /// <para>Not a round number, and not a guess: the archive feature was
    /// written on 2026-08-09, so no zip of this kind can be older than that.
    /// It is dated a comfortable year and a half BEFORE that day so no real
    /// name is ever refused — a machine whose clock is a few months out still
    /// writes a name this accepts — and it still clears the nearest wrong
    /// reading, Ethiopic <c>2018-12-03</c>, by six years. Any floor between
    /// the two works; one in the middle is wrong in neither direction.</para>
    ///
    /// <para><see cref="DateTimeKind.Unspecified"/> deliberately: stamps come
    /// back out of a file name through <c>TryParseExact</c> as wall time with
    /// no zone, and this is compared against them.</para>
    /// </summary>
    public static readonly DateTime EarliestPossible =
        new DateTime(2025, 1, 1, 0, 0, 0, DateTimeKind.Unspecified);

    /// <summary>
    /// How far ahead of now a stamp may be and still be believed.
    ///
    /// <para>Two days, not one. The stamp says what the clock on the wall
    /// said, on both ends, so a zip written this morning in Kiritimati
    /// (UTC+14) and read the same morning on Baker Island (UTC−12) is 26
    /// hours ahead of this PC's idea of now — absurd as travel, ordinary as a
    /// folder in OneDrive. Two days also covers a daylight-saving step.
    /// The extra day costs nothing: no wrong reading of any calendar lands
    /// within a year of the ceiling.</para>
    /// </summary>
    public static readonly TimeSpan FutureAllowance = TimeSpan.FromDays(2);

    /// <summary>
    /// Whether <paramref name="moment"/> is one Plantoir could have stamped:
    /// at or after <see cref="EarliestPossible"/>, and no more than
    /// <see cref="FutureAllowance"/> past now. BOTH bounds are inclusive.
    ///
    /// <para>Local wall time throughout — never <c>UtcNow</c>. A parsed stamp
    /// carries no zone and means what the clock said where it was written, so
    /// comparing it against a UTC now would refuse real names for up to half a
    /// day at either end of the world.</para>
    /// </summary>
    /// <param name="now">
    /// The clock to measure the ceiling against. Passed only by tests, which
    /// need an answer that does not change between one line and the next;
    /// nothing in the app passes it.
    /// </param>
    public static bool CouldHaveBeenStamped(DateTime moment, DateTime? now = null)
    {
        DateTime asOf = now ?? DateTime.Now;
        return moment >= EarliestPossible && moment <= asOf + FutureAllowance;
    }
}

using System.Globalization;

namespace Plantoir.Core.Undo;

/// <summary>
/// The journal's one spelling of a moment (<c>undoJournal.eventKeys.at</c>):
/// UTC, ISO 8601, to the second, <c>2026-11-13T21:04:05Z</c>; a reader also
/// accepts fractions of a second (#899, W1).
///
/// <para>Invariant culture always. Read as the Mac's <c>UndoMoment.date</c>
/// reads (an ISO 8601 internet date-time): a trailing <c>Z</c>, or an offset
/// such as <c>+00:00</c> or <c>-05:00</c>, which is turned into UTC; fractions
/// of a second with either (the W1 review's second round: Windows made such a
/// step unreadable where the Mac reads it). A local time with neither is not
/// a moment: reading it as UTC would move a step's time by hours. A moment
/// that does not parse is treated as absent by the caller (an <c>at</c> is
/// optional on read), never guessed at. Writers still write only the
/// <c>Z</c> spelling.</para>
/// </summary>
internal static class UndoMoment
{
    private static readonly string[] Formats =
    [
        "yyyy-MM-dd'T'HH:mm:ss'Z'",
        "yyyy-MM-dd'T'HH:mm:ss.FFFFFFF'Z'",
        "yyyy-MM-dd'T'HH:mm:sszzz",
        "yyyy-MM-dd'T'HH:mm:ss.FFFFFFFzzz",
    ];

    /// <summary>The moment, or null when the text is not the journal's spelling of one.</summary>
    internal static DateTimeOffset? Parse(string? text)
    {
        if (string.IsNullOrEmpty(text)) return null;
        return DateTimeOffset.TryParseExact(text, Formats, CultureInfo.InvariantCulture,
            DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out DateTimeOffset moment)
            ? moment
            : null;
    }

    /// <summary>The spelling a writer uses: whole seconds, UTC.</summary>
    internal static string Format(DateTimeOffset moment) =>
        moment.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture);
}

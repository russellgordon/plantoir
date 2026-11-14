using System.Globalization;

namespace Plantoir.Core.Undo;

/// <summary>
/// The journal's one spelling of a moment (<c>undoJournal.eventKeys.at</c>):
/// UTC, ISO 8601, to the second, <c>2026-11-13T21:04:05Z</c>; a reader also
/// accepts fractions of a second (#899, W1).
///
/// <para>Invariant culture always, and a trailing <c>Z</c> required: a moment
/// with an offset, or a local time, is not one this format writes, and reading
/// it as UTC would move a step's time by hours. A moment that does not parse
/// is treated as absent by the caller (an <c>at</c> is optional on read), never
/// guessed at.</para>
/// </summary>
internal static class UndoMoment
{
    private static readonly string[] Formats =
    [
        "yyyy-MM-dd'T'HH:mm:ss'Z'",
        "yyyy-MM-dd'T'HH:mm:ss.FFFFFFF'Z'",
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

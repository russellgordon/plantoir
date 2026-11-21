using System.Globalization;
using System.Text;
using System.Text.Json;

namespace Plantoir.Core.Undo;

/// <summary>
/// Any JSON value, as <c>editJSON</c> and <c>external</c> record it (#899 W6;
/// the mac's <c>UndoJSON</c>, <c>undoJournal.opKinds.editJSON</c>).
///
/// <para>Compared as the contract says (<see cref="Same"/>): <c>true</c> and
/// <c>false</c> never equal a number, numbers by value (1 and 1.0 are one
/// number, held as a double as the mac holds them), strings code point for
/// code point (never Unicode equivalence), objects by their members in any
/// order, arrays in order. Rejected: <c>JsonNode.DeepEquals</c> (the PC plan's
/// first idea), whose number comparison is exact on the decimal text and so
/// would read <c>2^53 + 1</c> differently from the mac, which reads it through a
/// double; the contract instead makes any whole number of 2^53 or more
/// "cannot tell" (<see cref="IsExact"/>), on both platforms.</para>
/// </summary>
internal abstract class UndoJson
{
    private UndoJson() { }

    internal sealed class Null : UndoJson
    {
        internal static readonly Null Value = new();
    }

    internal sealed class Bool(bool value) : UndoJson
    {
        internal bool Value { get; } = value;
    }

    internal sealed class Number(double value, bool measured = true) : UndoJson
    {
        internal double Value { get; } = value;

        /// <summary>
        /// False for a number a file spells in a way this app is not measured
        /// to read as the mac reads it (<see cref="ReadAsTheMacReads"/>): the
        /// file holding it is "cannot tell" (<see cref="HoldsOnlyMeasuredNumbers"/>).
        /// </summary>
        internal bool Measured { get; } = measured;
    }

    internal sealed class Text(string value) : UndoJson
    {
        internal string Value { get; } = value;
    }

    internal sealed class List(IReadOnlyList<UndoJson> items) : UndoJson
    {
        internal IReadOnlyList<UndoJson> Items { get; } = items;
    }

    internal sealed class Members(IReadOnlyDictionary<string, UndoJson> members) : UndoJson
    {
        internal IReadOnlyDictionary<string, UndoJson> Items { get; } = members;
    }

    /// <summary>The largest whole number a double holds exactly, plus one: 2^53.</summary>
    internal const double TwoToThe53 = 9_007_199_254_740_992d;

    /// <summary>Whether two values are one JSON value; two absent values (null) are the same, an absent one and JSON's null are not.</summary>
    internal static bool Same(UndoJson? first, UndoJson? second)
    {
        if (first is null || second is null) return first is null && second is null;
        switch (first)
        {
            case Null:
                return second is Null;
            case Bool flag:
                return second is Bool other && other.Value == flag.Value;
            case Number number:
                return second is Number otherNumber && otherNumber.Value == number.Value;
            case Text text:
                return second is Text otherText && string.Equals(text.Value, otherText.Value, StringComparison.Ordinal);
            case List list:
            {
                if (second is not List otherList || otherList.Items.Count != list.Items.Count) return false;
                for (int index = 0; index < list.Items.Count; index++)
                {
                    if (!Same(list.Items[index], otherList.Items[index])) return false;
                }
                return true;
            }
            case Members members:
            {
                if (second is not Members otherMembers || otherMembers.Items.Count != members.Items.Count) return false;
                foreach (KeyValuePair<string, UndoJson> member in members.Items)
                {
                    if (!otherMembers.Items.TryGetValue(member.Key, out UndoJson? match) || !Same(member.Value, match)) return false;
                }
                return true;
            }
            default:
                return false;
        }
    }

    /// <summary>
    /// A JSON element as a value, or null when it holds a number no double can
    /// hold (one beyond the double's range). A key written twice in an object
    /// keeps its LAST value, as Foundation's reader does on the mac; the byte
    /// mover refuses a key written twice on the path it walks. With
    /// <paramref name="asTheMacReadsAFile"/>, each number is the double the
    /// mac's reader takes from its spelling (<see cref="ReadAsTheMacReads"/>):
    /// a file's bytes are read that way, a journal's record is not.
    /// </summary>
    internal static UndoJson? From(JsonElement element, bool asTheMacReadsAFile = false)
    {
        switch (element.ValueKind)
        {
            case JsonValueKind.Null:
                return Null.Value;
            case JsonValueKind.True:
                return new Bool(true);
            case JsonValueKind.False:
                return new Bool(false);
            case JsonValueKind.Number:
            {
                // A number beyond a double's range is an infinity here, whichever reader gives it.
                if (!element.TryGetDouble(out double number)
                    && !double.TryParse(element.GetRawText(), NumberStyles.Float, CultureInfo.InvariantCulture, out number)) return null;
                if (double.IsNaN(number)) return null;
                if (!asTheMacReadsAFile) return double.IsInfinity(number) ? null : new Number(number);
                string spelling = element.GetRawText();
                if (!SpellingIsMeasured(spelling)) return new Number(double.IsInfinity(number) ? 0 : number, measured: false);
                // Measured (2026-11-20): the mac reads a number beyond a double's
                // range as minus infinity when it is negative (-1e400, -1.8e308,
                // -0.5e309) and cannot read the file when it is positive (1e400).
                if (double.IsPositiveInfinity(number)) return null;
                if (double.IsNegativeInfinity(number)) return new Number(double.NegativeInfinity);
                return new Number(ReadAsTheMacReads(spelling, number));
            }
            case JsonValueKind.String:
                return new Text(element.GetString()!);
            case JsonValueKind.Array:
            {
                var items = new List<UndoJson>();
                foreach (JsonElement item in element.EnumerateArray())
                {
                    if (From(item, asTheMacReadsAFile) is not { } value) return null;
                    items.Add(value);
                }
                return new List(items);
            }
            case JsonValueKind.Object:
            {
                var members = new Dictionary<string, UndoJson>(StringComparer.Ordinal);
                foreach (JsonProperty property in element.EnumerateObject())
                {
                    if (From(property.Value, asTheMacReadsAFile) is not { } value) return null;
                    members[property.Name] = value;
                }
                return new Members(members);
            }
            default:
                return null;
        }
    }

    /// <summary>
    /// Whether every number in the value is one a double holds exactly as
    /// written: no whole number of 2^53 or more (the mac's
    /// <c>UndoJSONBytes.isExact</c>; 2^53 + 1 reads as 2^53, so such a number
    /// can never be compared or written exactly).
    /// </summary>
    internal bool IsExact
    {
        get
        {
            switch (this)
            {
                case Number number:
                    return !(Math.Round(number.Value) == number.Value && Math.Abs(number.Value) >= TwoToThe53);
                case List list:
                    foreach (UndoJson item in list.Items)
                    {
                        if (!item.IsExact) return false;
                    }
                    return true;
                case Members members:
                    foreach (UndoJson item in members.Items.Values)
                    {
                        if (!item.IsExact) return false;
                    }
                    return true;
                default:
                    return true;
            }
        }
    }

    /// <summary>
    /// Whether this value is one this app is MEASURED to read, compare and
    /// spell exactly as the mac does (#899 W6 review 2): every key printable
    /// ASCII (<see cref="IsMeasuredKey"/>), no text starting with a byte-order
    /// mark, and every number read as measured. Anything else is refused
    /// before a byte is written ("cannot tell" when judged, never written),
    /// because the mac's Foundation does something this app has not been
    /// measured to copy: it sorts keys beyond ASCII by Unicode collation (an
    /// emoji first, <c>é</c> between <c>E</c> and <c>f</c>, a full-width
    /// <c>Ａ</c> beside <c>A</c>), takes keys that are canonically equivalent
    /// for one (<c>é</c> as one character and as <c>e</c> with a combining
    /// accent; the Kelvin sign and <c>K</c>), and reads text without a
    /// byte-order mark at its start (<c>undo.editJSONCases</c>,
    /// <c>undo.checkCases</c>, held here by name in <c>NamedGapLedger</c>).
    /// </summary>
    internal bool IsMeasured
    {
        get
        {
            switch (this)
            {
                case Number number:
                    return number.Measured;
                case Text words:
                    return !words.Value.StartsWith('\uFEFF');
                case List list:
                    foreach (UndoJson item in list.Items)
                    {
                        if (!item.IsMeasured) return false;
                    }
                    return true;
                case Members members:
                    foreach (KeyValuePair<string, UndoJson> member in members.Items)
                    {
                        if (!IsMeasuredKey(member.Key) || !member.Value.IsMeasured) return false;
                    }
                    return true;
                default:
                    return true;
            }
        }
    }

    /// <summary>
    /// Whether every number anywhere in a file's value was read as measured
    /// (<see cref="SpellingIsMeasured"/>). A file holding one that is not is
    /// "cannot tell" as a whole: the mac cannot read some such files at all
    /// (a number with 168 digits after the point), so even a member beside it
    /// is never judged or moved here.
    /// </summary>
    internal bool HoldsOnlyMeasuredNumbers
    {
        get
        {
            switch (this)
            {
                case Number number:
                    return number.Measured;
                case List list:
                    foreach (UndoJson item in list.Items)
                    {
                        if (!item.HoldsOnlyMeasuredNumbers) return false;
                    }
                    return true;
                case Members members:
                    foreach (UndoJson item in members.Items.Values)
                    {
                        if (!item.HoldsOnlyMeasuredNumbers) return false;
                    }
                    return true;
                default:
                    return true;
            }
        }
    }

    /// <summary>
    /// A key made only of printable ASCII (U+0020 to U+007E), the only keys
    /// whose order (<see cref="UndoMacKeyOrder"/>) and equality this app is
    /// measured to share with the mac. A tab, an accent, a full-width letter,
    /// an emoji or a byte-order mark makes a key one it is not.
    /// </summary>
    internal static bool IsMeasuredKey(string key)
    {
        foreach (char character in key)
        {
            if (character < 0x20 || character > 0x7E) return false;
        }
        return true;
    }

    /// <summary>
    /// The value spelled compactly, byte for byte as the mac's
    /// <c>JSONSerialization</c> writes it (<c>.sortedKeys</c>,
    /// <c>.withoutEscapingSlashes</c>): keys in the mac's order
    /// (<see cref="UndoMacKeyOrder"/>), slashes as they are, nothing escaped
    /// but what JSON requires (a quote, a backslash, a control character), a
    /// whole number without a decimal part, any other number as C's
    /// <c>%.17g</c> spells it (<see cref="SpellNumber"/>). Only the NEW value
    /// of a member is ever spelled by the app (<c>undo.editJSONCases</c>, whose
    /// key-order and number rows were taken from the mac's own code on
    /// 2026-11-20). Null for a value that is not exact (<see cref="IsExact"/>):
    /// never written approximately; and null for a value this app is not
    /// measured to spell as the mac does (<see cref="IsMeasured"/>: a key
    /// beyond printable ASCII, text starting with a byte-order mark), unless
    /// <paramref name="onlyAsTheMacIsMeasuredToWrite"/> is false, which only
    /// the app's own settings file asks for (a file the mac never writes, so
    /// its key order is this app's own; <c>external</c>).
    /// </summary>
    internal string? Spelled(bool onlyAsTheMacIsMeasuredToWrite = true)
    {
        if (!IsExact) return null;
        if (onlyAsTheMacIsMeasuredToWrite && !IsMeasured) return null;
        var text = new StringBuilder();
        Spell(this, text);
        return text.ToString();
    }

    private static void Spell(UndoJson value, StringBuilder text)
    {
        switch (value)
        {
            case Null:
                text.Append("null");
                return;
            case Bool flag:
                text.Append(flag.Value ? "true" : "false");
                return;
            case Number number:
                text.Append(SpellNumber(number.Value));
                return;
            case Text words:
                SpellString(words.Value, text);
                return;
            case List list:
            {
                text.Append('[');
                for (int index = 0; index < list.Items.Count; index++)
                {
                    if (index > 0) text.Append(',');
                    Spell(list.Items[index], text);
                }
                text.Append(']');
                return;
            }
            case Members members:
            {
                var names = new List<string>(members.Items.Keys);
                names.Sort(UndoMacKeyOrder.Instance);
                text.Append('{');
                bool first = true;
                foreach (string name in names)
                {
                    if (!first) text.Append(',');
                    first = false;
                    SpellString(name, text);
                    text.Append(':');
                    Spell(members.Items[name], text);
                }
                text.Append('}');
                return;
            }
        }
    }

    /// <summary>
    /// A number as the mac writes it. A whole number (which <see cref="IsExact"/>
    /// keeps below 2^53) is its digits, negative zero 0 (the mac hands such a
    /// number over as an integer). Any other is a double written as C's
    /// <c>%.17g</c>: 17 significant digits correctly rounded, trailing zeros
    /// dropped, fixed notation for an exponent from -4 to 16 and otherwise
    /// <c>d.ddde-XX</c> with at least two exponent digits (measured: 0.1 is
    /// <c>0.10000000000000001</c>, 1e-07 is <c>9.9999999999999995e-08</c>).
    /// Rejected: .NET's shortest round trip (<c>"R"</c>), which wrote
    /// <c>0.1</c> and <c>1E-07</c> where the mac writes the bytes above.
    /// </summary>
    internal static string SpellNumber(double value)
    {
        if (Math.Round(value) == value) return ((long)value).ToString(CultureInfo.InvariantCulture);
        // "E16" is the value correctly rounded to 17 significant digits: d.dddddddddddddddde+XXX.
        string scientific = Math.Abs(value).ToString("E16", CultureInfo.InvariantCulture);
        int marker = scientific.IndexOf('E');
        string digits = scientific[..marker].Replace(".", "", StringComparison.Ordinal).TrimEnd('0');
        if (digits.Length == 0) digits = "0";
        int exponent = int.Parse(scientific[(marker + 1)..], NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture);
        var spelled = new StringBuilder();
        if (value < 0) spelled.Append('-');
        if (exponent >= -4 && exponent < 17)
        {
            if (exponent < 0)
            {
                spelled.Append("0.").Append('0', -exponent - 1).Append(digits);
            }
            else if (digits.Length <= exponent + 1)
            {
                spelled.Append(digits).Append('0', exponent + 1 - digits.Length);
            }
            else
            {
                spelled.Append(digits, 0, exponent + 1).Append('.').Append(digits, exponent + 1, digits.Length - exponent - 1);
            }
            return spelled.ToString();
        }
        spelled.Append(digits[0]);
        if (digits.Length > 1) spelled.Append('.').Append(digits, 1, digits.Length - 1);
        spelled.Append('e').Append(exponent < 0 ? '-' : '+');
        spelled.Append(Math.Abs(exponent).ToString("00", CultureInfo.InvariantCulture));
        return spelled.ToString();
    }

    /// <summary>
    /// Whether a file's spelling of a number is one this app is measured to
    /// read as the mac reads it (2026-11-20, on macOS 26.7.3, through the mac's
    /// reader): at most 17 digits with an exponent, at most 38 without, digits
    /// counted from the first one that is not a leading zero of the integer
    /// part (so <c>0.00012339999999999999e0</c> has 20). Beyond that the mac
    /// reads a decimal number this app does not copy: with an exponent and
    /// more than 17 digits, <c>1.2345678901234567890123e-5</c> is
    /// <c>1.2345678901234573e-05</c> there, not the nearest double; with more
    /// than 38, its reads disagree, and with 120 or more digits after the point
    /// (or an exponent far from zero) it cannot read the file at all. A
    /// spelling that is not measured makes the file "cannot tell"
    /// (<see cref="HoldsOnlyMeasuredNumbers"/>, <c>undo.checkCases</c>).
    /// </summary>
    internal static bool SpellingIsMeasured(string spelling)
    {
        string unsigned = spelling.StartsWith('-') ? spelling[1..] : spelling;
        int marker = unsigned.IndexOfAny(['e', 'E']);
        string mantissa = marker >= 0 ? unsigned[..marker] : unsigned;
        int point = mantissa.IndexOf('.');
        string whole = (point >= 0 ? mantissa[..point] : mantissa).TrimStart('0');
        int fractionDigits = point >= 0 ? mantissa.Length - point - 1 : 0;
        int digits = whole.Length + fractionDigits;
        return marker >= 0 ? digits <= 17 : digits <= 38;
    }

    /// <summary>
    /// The double the mac's reader (Foundation's <c>JSONSerialization</c>)
    /// takes from a number as a file spells it, so a file's member is judged,
    /// and a moved member read back, as the mac judges it; only for a spelling
    /// <see cref="SpellingIsMeasured"/> passes. Measured on macOS 26.7.3
    /// (2026-11-20, through the mac's reader): a spelling in fixed notation
    /// with a decimal point and more than 17 digits once the integer part's
    /// leading zeros are dropped (<c>0.012345678901234567</c>, not
    /// <c>0.12345678901234567</c>) becomes an <c>NSDecimalNumber</c>, whose
    /// double is its digits as a whole number (trailing zeros dropped), summed
    /// in 16-bit pieces as doubles, then divided by ten once per decimal place
    /// (every one of 30,000 such spellings of 18 to 38 digits agreed, bit for
    /// bit or, for a long spelling of zero, as the same number); every other
    /// measured spelling is the nearest double (4,244 in fixed notation; 4,000
    /// with an exponent and at most 17 digits, exponents -330 to 310). So
    /// 0.00012339999999999999, the spelling of 0.0001234, reads as
    /// 0.00012340000000000002 there, and a member set to 0.0001234 is refused
    /// on both platforms (<c>undo.editJSONCases</c>).
    /// </summary>
    internal static double ReadAsTheMacReads(string spelling, double nearest)
    {
        if (spelling.Contains('e', StringComparison.OrdinalIgnoreCase) || !spelling.Contains('.', StringComparison.Ordinal)) return nearest;
        bool negative = spelling.StartsWith('-');
        string unsigned = negative ? spelling[1..] : spelling;
        int point = unsigned.IndexOf('.');
        string whole = unsigned[..point].TrimStart('0');
        string fraction = unsigned[(point + 1)..];
        if (whole.Length + fraction.Length <= 17) return nearest;
        System.Numerics.BigInteger mantissa = System.Numerics.BigInteger.Parse(whole + fraction, CultureInfo.InvariantCulture);
        int exponent = -fraction.Length;
        while (!mantissa.IsZero && mantissa % 10 == 0)
        {
            mantissa /= 10;
            exponent++;
        }
        var pieces = new List<int>();
        while (!mantissa.IsZero)
        {
            pieces.Add((int)(mantissa & 0xFFFF));
            mantissa >>= 16;
        }
        double read = 0;
        for (int index = pieces.Count - 1; index >= 0; index--) read = read * 65536 + pieces[index];
        for (int step = 0; step < -exponent; step++) read /= 10;
        for (int step = 0; step < exponent; step++) read *= 10;
        return negative ? -read : read;
    }

    /// <summary>A string as JSON: a quote, a backslash and a control character escaped, nothing else.</summary>
    internal static void SpellString(string value, StringBuilder text)
    {
        text.Append('"');
        foreach (char character in value)
        {
            switch (character)
            {
                case '"': text.Append("\\\""); break;
                case '\\': text.Append("\\\\"); break;
                case '\n': text.Append("\\n"); break;
                case '\r': text.Append("\\r"); break;
                case '\t': text.Append("\\t"); break;
                case '\b': text.Append("\\b"); break;
                case '\f': text.Append("\\f"); break;
                default:
                    if (character < 0x20) text.Append("\\u").Append(((int)character).ToString("x4", CultureInfo.InvariantCulture));
                    else text.Append(character);
                    break;
            }
        }
        text.Append('"');
    }
}

/// <summary>
/// The order the mac's <c>JSONSerialization</c> writes an object's keys in
/// with <c>.sortedKeys</c>, which is not ordinal: measured on macOS 26.7.3
/// (2026-11-20, through the mac's own spelling code, 6,000 random sets of
/// printable ASCII keys, every one in this order). A key is read as pieces: a
/// run of digits, or one character. Pieces are compared first by kind and
/// value: punctuation (in <see cref="Punctuation"/>'s order, a space first),
/// then a run of digits (by its number, so 9 before 10), then a letter
/// (ignoring case); a key that runs out first comes first. Keys equal so far
/// are then told apart at the first piece that differs: a lowercase letter
/// before its capital, a run with fewer zeros in front before one with more
/// (so <c>1A</c>, <c>01a</c>; <c>ab</c>, <c>aB</c>, <c>Ab</c>). Rejected:
/// ordinal order, which wrote <c>"10","9","B","a"</c> where the mac writes
/// <c>"9","10","a","B"</c>. A key holding anything beyond printable ASCII
/// is never written to a file the mac also reads: the mac sorts such keys by
/// Unicode collation, which this table does not copy (#899 W6 review 2), so
/// <see cref="UndoJson.Spelled"/> refuses them (<see cref="UndoJson.IsMeasuredKey"/>);
/// they are placed here after every letter by their code only for the app's
/// own settings file.
/// </summary>
internal sealed class UndoMacKeyOrder : IComparer<string>
{
    internal static readonly UndoMacKeyOrder Instance = new();

    private const string Punctuation = " _-,;:!?.'\"()[]{}@*/\\&#%`^+<=>|~$";

    private readonly record struct Piece(int Kind, string Primary, int Tie);

    private static List<Piece> PiecesOf(string key)
    {
        var pieces = new List<Piece>();
        int index = 0;
        while (index < key.Length)
        {
            char character = key[index];
            if (character is >= '0' and <= '9')
            {
                int end = index;
                while (end < key.Length && key[end] is >= '0' and <= '9') end++;
                string run = key[index..end];
                string withoutZeros = run.TrimStart('0');
                // Same length first, then the digits: the run's number, however long.
                pieces.Add(new Piece(1, withoutZeros.Length.ToString("D10", CultureInfo.InvariantCulture) + withoutZeros, run.Length - withoutZeros.Length));
                index = end;
                continue;
            }
            int punctuation = Punctuation.IndexOf(character);
            if (punctuation >= 0)
                pieces.Add(new Piece(0, punctuation.ToString("D2", CultureInfo.InvariantCulture), 0));
            else if (character is >= 'a' and <= 'z')
                pieces.Add(new Piece(2, character.ToString(), 0));
            else if (character is >= 'A' and <= 'Z')
                pieces.Add(new Piece(2, char.ToLowerInvariant(character).ToString(), 1));
            else
                pieces.Add(new Piece(3, ((int)character).ToString("D6", CultureInfo.InvariantCulture), 0));
            index++;
        }
        return pieces;
    }

    public int Compare(string? first, string? second)
    {
        if (first is null || second is null) return first is null ? (second is null ? 0 : -1) : 1;
        List<Piece> firstPieces = PiecesOf(first);
        List<Piece> secondPieces = PiecesOf(second);
        int shared = Math.Min(firstPieces.Count, secondPieces.Count);
        for (int index = 0; index < shared; index++)
        {
            Piece one = firstPieces[index];
            Piece other = secondPieces[index];
            if (one.Kind != other.Kind) return one.Kind.CompareTo(other.Kind);
            int byValue = string.CompareOrdinal(one.Primary, other.Primary);
            if (byValue != 0) return byValue;
        }
        if (firstPieces.Count != secondPieces.Count) return firstPieces.Count.CompareTo(secondPieces.Count);
        for (int index = 0; index < shared; index++)
        {
            if (firstPieces[index].Tie != secondPieces[index].Tie) return firstPieces[index].Tie.CompareTo(secondPieces[index].Tie);
        }
        return string.CompareOrdinal(first, second);
    }
}

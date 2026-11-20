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

    internal sealed class Number(double value) : UndoJson
    {
        internal double Value { get; } = value;
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
    /// mover refuses a key written twice on the path it walks.
    /// </summary>
    internal static UndoJson? From(JsonElement element)
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
                if (!element.TryGetDouble(out double number) || double.IsInfinity(number) || double.IsNaN(number)) return null;
                return new Number(number);
            case JsonValueKind.String:
                return new Text(element.GetString()!);
            case JsonValueKind.Array:
            {
                var items = new List<UndoJson>();
                foreach (JsonElement item in element.EnumerateArray())
                {
                    if (From(item) is not { } value) return null;
                    items.Add(value);
                }
                return new List(items);
            }
            case JsonValueKind.Object:
            {
                var members = new Dictionary<string, UndoJson>(StringComparer.Ordinal);
                foreach (JsonProperty property in element.EnumerateObject())
                {
                    if (From(property.Value) is not { } value) return null;
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
    /// The value spelled compactly: keys sorted (ordinally), slashes as they
    /// are, nothing escaped but what JSON requires (a quote, a backslash, a
    /// control character), a whole number without a decimal part, any other
    /// number in its shortest spelling that reads back as the same double.
    /// Only the NEW value of a member is ever spelled by the app
    /// (<c>undo.editJSONCases</c>). Null for a value that is not exact
    /// (<see cref="IsExact"/>): never written approximately.
    /// </summary>
    internal string? Spelled()
    {
        if (!IsExact) return null;
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
                if (Math.Round(number.Value) == number.Value)
                    text.Append(((long)number.Value).ToString(CultureInfo.InvariantCulture));
                else
                    text.Append(number.Value.ToString("R", CultureInfo.InvariantCulture));
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
                names.Sort(StringComparer.Ordinal);
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

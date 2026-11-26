using System.Text.Json;
using System.Text.RegularExpressions;

namespace Plantoir.Core.Undo;

/// <summary>
/// <c>shared-rules.json</c> → <c>undo.wording</c>, read from the copy of the
/// contract built into this assembly, never retyped (#899 W7b2-11; the W7b1
/// review 2, LOW 4). Read once, the first time a sentence is asked for.
/// </summary>
internal static class UndoContractWording
{
    // ---- Stored properties -------------------------------------------------------

    /// <summary>The name the contract is built in under (<c>Plantoir.Core.csproj</c>).</summary>
    private const string ResourceName = "shared-rules.json";

    private static readonly Lazy<IReadOnlyDictionary<string, string>> Wording = new(ReadTheWording);

    // ---- Functions -------------------------------------------------------------------

    /// <summary>The contract's sentence under <paramref name="key"/>, as it is written there.</summary>
    internal static string Of(string key) => Wording.Value[key];

    /// <summary>
    /// The contract's sentence under <paramref name="key"/> with each
    /// <c>{name}</c> in it filled from <paramref name="filling"/>, in one pass,
    /// so a value that itself holds a <c>{name}</c> is never filled again.
    /// </summary>
    internal static string Filled(string key, IReadOnlyDictionary<string, string> filling) =>
        Regex.Replace(Of(key), @"\{([A-Za-z]+)\}", match =>
            filling.TryGetValue(match.Groups[1].Value, out string? value) ? value : match.Value);

    private static IReadOnlyDictionary<string, string> ReadTheWording()
    {
        using Stream stream = typeof(UndoContractWording).Assembly.GetManifestResourceStream(ResourceName)
            ?? throw new InvalidOperationException("The contract shared-rules.json is not built into Plantoir.Core.");
        using JsonDocument rules = JsonDocument.Parse(stream);
        var sentences = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (JsonProperty sentence in rules.RootElement.GetProperty("undo").GetProperty("wording").EnumerateObject())
        {
            if (sentence.Value.ValueKind == JsonValueKind.String) sentences[sentence.Name] = sentence.Value.GetString()!;
        }
        return sentences;
    }
}

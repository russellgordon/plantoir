namespace Plantoir.Core.Catalogs;

/// <summary>The 12 preset header emojis — mirrors PRESET_HEADER_EMOJIS in setup_course.py.</summary>
public static class EmojiCatalog
{
    public static readonly IReadOnlyList<string> Presets = new[]
    {
        "📚", "🎓", "🏫", "✏️", "📝", "📐",
        "📊", "🧪", "🔬", "🔭", "🧬", "🖥️",
    };
}

/// <summary>Font pairings and code fonts — mirrors FONT_PAIRINGS / CODE_FONTS in setup_course.py.</summary>
public static class FontCatalog
{
    public sealed record Pairing(string Header, string Body);

    public static readonly IReadOnlyList<Pairing> Pairings = new[]
    {
        new Pairing("Playfair Display", "Source Sans 3"),
        new Pairing("Source Serif 4", "Inter"),
        new Pairing("Montserrat", "Lora"),
        new Pairing("Raleway", "Roboto"),
        new Pairing("Poppins", "Merriweather"),
        new Pairing("Archivo", "Noto Sans"),
        new Pairing("Helvetica, Arial", "Helvetica, Arial"),
    };

    public static readonly IReadOnlyList<string> CodeFonts = new[]
    {
        "JetBrains Mono", "Fira Code", "IBM Plex Mono",
        "Source Code Pro", "Inconsolata", "Ubuntu Mono",
    };

    /// <summary>
    /// The pairing's label. The system choice is STORED as "Helvetica, Arial"
    /// and stays so, but has never shown Helvetica: the build writes it as the
    /// system stack, so it is Segoe UI here and San Francisco on a Mac (#629,
    /// windows #648; documentation/06-quartz-customizations.md → C2-31).
    /// </summary>
    public static string PairingLabel(string header, string body) =>
        header == "Helvetica, Arial" && body == "Helvetica, Arial"
            ? "System fonts (each device's own)"
            : $"{header}  —  {body}";

    /// <summary>Bundled TTF base names: the family name with spaces removed.</summary>
    public static readonly IReadOnlyList<string> BundledFontFiles = new[]
    {
        "Archivo", "FiraCode", "IBMPlexMono", "Inconsolata", "Inter", "JetBrainsMono",
        "Lora", "Merriweather", "Montserrat", "NotoSans", "PlayfairDisplay", "Poppins",
        "Raleway", "Roboto", "SourceCodePro", "SourceSans3", "SourceSerif4", "UbuntuMono",
    };

    /// <summary>Family display name → bundled file base name (strip spaces).</summary>
    public static string FileBaseName(string familyName) => familyName.Replace(" ", "");
}

/// <summary>The 27 Quartz locales in wizard order (nb-NO deliberately first).</summary>
public static class LocaleCatalog
{
    public static readonly IReadOnlyList<string> Codes = new[]
    {
        "nb-NO", "ar-SA", "ca-ES", "cs-CZ", "de-DE", "en-GB", "en-US", "es-ES", "fa-IR", "fi-FI",
        "fr-FR", "hu-HU", "it-IT", "ja-JP", "ko-KR", "lt-LT", "nl-NL", "pl-PL", "pt-BR", "ro-RO",
        "ru-RU", "th-TH", "tr-TR", "uk-UA", "vi-VN", "zh-CN", "zh-TW",
    };

    private static readonly IReadOnlyDictionary<string, string> Labels = new Dictionary<string, string>
    {
        ["nb-NO"] = "Norwegian Bokmål (Norway)",
        ["ar-SA"] = "Arabic (Saudi Arabia)",
        ["ca-ES"] = "Catalan (Spain)",
        ["cs-CZ"] = "Czech (Czechia)",
        ["de-DE"] = "German (Germany)",
        ["en-GB"] = "English (United Kingdom)",
        ["en-US"] = "English (United States)",
        ["es-ES"] = "Spanish (Spain)",
        ["fa-IR"] = "Persian (Iran)",
        ["fi-FI"] = "Finnish (Finland)",
        ["fr-FR"] = "French (France)",
        ["hu-HU"] = "Hungarian (Hungary)",
        ["it-IT"] = "Italian (Italy)",
        ["ja-JP"] = "Japanese (Japan)",
        ["ko-KR"] = "Korean (South Korea)",
        ["lt-LT"] = "Lithuanian (Lithuania)",
        ["nl-NL"] = "Dutch (Netherlands)",
        ["pl-PL"] = "Polish (Poland)",
        ["pt-BR"] = "Portuguese (Brazil)",
        ["ro-RO"] = "Romanian (Romania)",
        ["ru-RU"] = "Russian (Russia)",
        ["th-TH"] = "Thai (Thailand)",
        ["tr-TR"] = "Turkish (Türkiye)",
        ["uk-UA"] = "Ukrainian (Ukraine)",
        ["vi-VN"] = "Vietnamese (Vietnam)",
        ["zh-CN"] = "Chinese, Simplified (China)",
        ["zh-TW"] = "Chinese, Traditional (Taiwan)",
    };

    public static string DisplayName(string code) =>
        Labels.TryGetValue(code, out string? label) ? $"{code} — {label}" : code;
}

using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// Course Settings (#387, mac #364 #373 #374 #376 #369): what enables Save,
/// the held-back sentence, the settings wording and the label-word scan —
/// <c>shared-rules.json</c> → <c>savingSettings.whatEnablesSave</c>,
/// <c>courseSettingsWording</c>, <c>userFacingLabelWords</c>, deserialised.
/// </summary>
/// <remarks>
/// A change is made through the SAME Core setter the dialog's control calls
/// (<c>CourseSettingsView.BuildSectionBlock</c>); that every control calls
/// <c>MarkChanged</c> at all is the part no model test can see, and is what
/// <c>CourseSettingsSaveUiTests</c> (opt-in, unproven while the desktop was
/// locked) drives through the real window.
/// </remarks>
public sealed class CourseSettingsSaveTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("save-enables").FullName;
    private string Existing => Directory.CreateDirectory(Path.Combine(_folder, "existing")).FullName;
    private string Missing => Path.Combine(_folder, "missing-folder");
    private string AnotherMissing => Path.Combine(_folder, "another-missing-folder");

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private static JsonNode WhatEnablesSave =>
        ContractLoader.LoadJson("shared-rules.json")["savingSettings"]!["whatEnablesSave"]!;

    private string Placeholders(string json) => json
        .Replace("{missingFolder}", Missing.Replace("\\", "\\\\"))
        .Replace("{anotherMissingFolder}", AnotherMissing.Replace("\\", "\\\\"))
        .Replace("{existingFolder}", Existing.Replace("\\", "\\\\"));

    /// <summary>baseShape with `set` applied and `remove` removed, read back as a fresh window reads the file.</summary>
    private CourseConfiguration Opened(JsonNode c)
    {
        var shape = JObject.Parse(WhatEnablesSave["baseShape"]!.ToJsonString());
        var set = JObject.Parse(Placeholders(c["set"]?.ToJsonString() ?? "{}"));
        foreach (var property in set.Properties()) shape[property.Name] = property.Value;
        foreach (var key in c["remove"]?.AsArray() ?? new JsonArray()) shape.Remove(key!.ToString());
        string path = Path.Combine(_folder, "course_config.json");
        File.WriteAllText(path, shape.ToString(Newtonsoft.Json.Formatting.Indented), new UTF8Encoding(false));
        return CourseConfiguration.Load(path);
    }

    /// <summary>One change, through the setter the dialog's control calls.</summary>
    private void Make(CourseConfiguration config, JsonNode change)
    {
        if (change["setting"] is { } setting)
        {
            string value = Placeholders(change["value"]?.ToString() ?? "");
            switch (setting.ToString())
            {
                case "deployTarget": config.DeployTarget = value; break;
                case "deployFolderPath": config.DeployFolderPath = value; break;
                case "addAdditionalDestination":
                    config.AdditionalDeployTargets = config.AdditionalDeployTargets
                        .Append(new CourseConfiguration.AdditionalDeployTarget(change["type"]!.ToString(),
                                                                                Placeholders(change["path"]!.ToString())))
                        .ToList();
                    break;
                default: throw new InvalidOperationException("an unknown setting: " + setting);
            }
            return;
        }
        int section = change["section"]!.GetValue<int>();
        var v = change["value"]!;
        switch (change["key"]!.ToString())
        {
            case "emojis.sections.section<N>": config.SetEmoji(section, v.ToString()); break;
            case "color_schemes.section<N>": config.SetColourSchemeId(section, v.ToString()); break;
            case "fonts.sections.section<N>":
                config.SetFont(section, new FontChoice(v["header"]!.ToString(), v["body"]!.ToString(), v["code"]!.ToString()));
                break;
            case "show_section_marker.sections.section<N>": config.SetShowsSectionMarker(section, v.GetValue<bool>()); break;
            case "show_grade_in_title.sections.section<N>": config.SetShowsGradeInTitle(section, v.GetValue<bool>()); break;
            case "custom_domains.sections.section<N>":
                config.SetCustomDomain(section, change["destinationType"]!.ToString(), v.ToString());
                break;
            default: throw new InvalidOperationException("a per-section key this runner does not know: " + change["key"]);
        }
    }

    [Fact]
    public void AFreshlyOpenedCourseIsClean()
    {
        var cases = WhatEnablesSave["freshOpenCases"]!.AsArray();
        Assert.Equal(8, cases.Count);
        foreach (var c in cases)
        {
            var state = SettingsSaveState.Decide(Opened(c!), "");
            Assert.False(state.SaveEnabled, $"{c!["name"]}: Save enabled on a fresh open");
            Assert.False(state.RevertEnabled, $"{c["name"]}: Revert enabled on a fresh open");
        }
    }

    [Fact]
    public void EveryPerSectionChangeEnablesSaveAndWritesOnlyItsOwnKey()
    {
        var cases = WhatEnablesSave["perSectionEditCases"]!.AsArray();
        Assert.Equal(7, cases.Count);
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            var config = Opened(c);
            Make(config, c["change"]!);
            var state = SettingsSaveState.Decide(config, "");
            Assert.True(state.SaveEnabled && state.RevertEnabled, $"{name}: Save/Revert not enabled");

            config.Write(Path.Combine(_folder, "course_config.json"));
            var written = JObject.Parse(File.ReadAllText(Path.Combine(_folder, "course_config.json")));
            foreach (var expect in c["written"]!.AsArray().Concat(c["unchanged"]!.AsArray()))
            {
                JToken? at = written;
                foreach (var step in expect!["path"]!.AsArray()) at = at?[step!.ToString()];
                Assert.True(at is not null && JToken.DeepEquals(at, JToken.Parse(expect["value"]!.ToJsonString())),
                    $"{name}: {string.Join(".", expect["path"]!.AsArray())} is {at?.ToString(Newtonsoft.Json.Formatting.None) ?? "absent"}, expected {expect["value"]!.ToJsonString()}");
            }
        }
    }

    [Fact]
    public void ADestinationProblemHoldsSaveBackOnlyWhenTheEditMovesWhereTheCoursePublishes()
    {
        var cases = WhatEnablesSave["heldBackCases"]!.AsArray();
        Assert.Equal(7, cases.Count);
        var wording = ContractLoader.LoadJson("shared-rules.json")["courseSettingsWording"]!;
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            var config = Opened(c);
            foreach (var change in c["changes"]!.AsArray()) Make(config, change!);
            var state = SettingsSaveState.Decide(config, c["cloudflareAccountIDOnThisMac"]?.ToString() ?? "");
            var expect = c["expect"]!;
            Assert.True(expect["saveEnabled"]!.GetValue<bool>() == state.SaveEnabled, $"{name}: saveEnabled");
            Assert.True(expect["revertEnabled"]!.GetValue<bool>() == state.RevertEnabled, $"{name}: revertEnabled");
            Assert.True(expect["heldBack"]!.GetValue<bool>() == state.HeldBack, $"{name}: heldBack");
            if (!state.HeldBack) continue;
            Assert.Equal(expect["check"]!.ToString(), state.Check);
            Assert.Equal(expect["reason"]!.ToString(), state.Reason);
            Assert.Equal(wording["saveHeldBack"]!.ToString().Replace("{reason}", expect["reason"]!.ToString()), state.Sentence);
        }
    }

    [Fact]
    public void TheSettingsWordsAreTheContracts()
    {
        var wording = ContractLoader.LoadJson("shared-rules.json")["courseSettingsWording"]!;
        Assert.Equal(wording["localeLabel"]!.ToString(), CourseSettingsWording.LocaleLabel);
        Assert.Equal(wording["localeCaption"]!.ToString(), CourseSettingsWording.LocaleCaption);
        Assert.Equal(wording["colourSchemeNoneChosen"]!.ToString(), CourseSettingsWording.ColourSchemeNoneChosen);
        Assert.Equal(wording["saveHeldBack"]!.ToString(), SettingsSaveState.SaveHeldBackTemplate);
    }

    /// <summary>
    /// <c>userFacingLabelWords</c> over this app's views: every string literal
    /// in <c>Plantoir/Views</c> and <c>Plantoir/*.cs</c> (comments skipped, an
    /// interpolation's code skipped) and every label attribute in the XAML —
    /// whole word, case-insensitive. The one exception is the contract's own:
    /// the About window's credit to Quartz, by name.
    /// </summary>
    [Fact]
    public void NoLabelNamesTheMachinery()
    {
        var rule = ContractLoader.LoadJson("shared-rules.json")["userFacingLabelWords"]!;
        var forbidden = rule["forbidden"]!.AsArray().Select(w => Regex.Escape(w!.ToString()));
        var word = new Regex(@"\b(" + string.Join("|", forbidden) + @")\b", RegexOptions.IgnoreCase);
        string app = Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir");
        var hits = new List<string>();

        foreach (string file in Directory.GetFiles(Path.Combine(app, "Views"), "*.cs").Concat(Directory.GetFiles(app, "*.cs")))
        {
            string[] lines = File.ReadAllLines(file);
            foreach (var (line, literal) in StringLiterals(File.ReadAllText(file)))
            {
                if (!word.IsMatch(literal)) continue;
                if (IsNotALabel(literal, lines[Math.Min(line, lines.Length) - 1])) continue;
                if (Path.GetFileName(file) == "AboutDialog.cs" && literal == "Quartz") continue;   // the credit (exceptions[0])
                hits.Add($"{Path.GetFileName(file)}:{line}: {literal}");
            }
        }
        foreach (string file in Directory.GetFiles(Path.Combine(app, "Views"), "*.xaml").Concat(Directory.GetFiles(app, "*.xaml")))
        {
            string text = Regex.Replace(File.ReadAllText(file), "<!--.*?-->", "", RegexOptions.Singleline);
            foreach (Match m in Regex.Matches(text, "(?:Content|Text|Header|Title|PlaceholderText|ToolTip)=\"([^\"]*)\""))
                if (word.IsMatch(m.Groups[1].Value)) hits.Add($"{Path.GetFileName(file)}: {m.Value}");
        }
        Assert.True(hits.Count == 0, "labels name the machinery (CLAUDE.md rule 1):\n" + string.Join("\n", hits));
    }

    /// <summary>
    /// A literal no teacher reads: a file name, path or address, or text this
    /// app MATCHES in a launcher's output rather than shows. The mac's scope is
    /// "a literal passed straight to a call that puts words on screen"; this
    /// scan reads every literal and sets these aside instead, which errs on the
    /// side of finding more.
    /// </summary>
    private static bool IsNotALabel(string literal, string line) =>
        // A path or an address has no spaces; "Language / region (…)" does, and is a label.
        (!literal.Contains(' ') && (literal.Contains('/') || literal.Contains('\\')))
        || Regex.IsMatch(literal, @"^[\w.-]+\.(json|md|ps1|py|exe|dll)$", RegexOptions.IgnoreCase)
        || Regex.IsMatch(line, @"\.(Contains|StartsWith|EndsWith|IndexOf)\(");

    /// <summary>The string literals of a C# file, comments skipped and interpolation holes removed.</summary>
    private static IEnumerable<(int Line, string Literal)> StringLiterals(string source)
    {
        int i = 0, line = 1;
        while (i < source.Length)
        {
            char ch = source[i];
            if (ch == '\n') { line++; i++; continue; }
            if (ch == '/' && i + 1 < source.Length && source[i + 1] == '/') { while (i < source.Length && source[i] != '\n') i++; continue; }
            if (ch == '/' && i + 1 < source.Length && source[i + 1] == '*')
            {
                int end = source.IndexOf("*/", i + 2, StringComparison.Ordinal);
                end = end < 0 ? source.Length : end + 2;
                line += source[i..end].Count(c => c == '\n');
                i = end; continue;
            }
            if (ch == '\'') { i += source[i + 1] == '\\' ? 4 : 3; continue; }   // a char literal
            if (ch == '"' || ((ch == '$' || ch == '@') && i + 1 < source.Length && (source[i + 1] == '"' || source[i + 1] is '$' or '@')))
            {
                int start = i;
                bool verbatim = false, interpolated = false;
                while (source[i] is '$' or '@') { verbatim |= source[i] == '@'; interpolated |= source[i] == '$'; i++; }
                if (source[i] != '"') { i++; continue; }
                if (source.AsSpan(i).StartsWith("\"\"\""))
                {
                    int end = source.IndexOf("\"\"\"", i + 3, StringComparison.Ordinal);
                    end = end < 0 ? source.Length : end + 3;
                    string body = source[(i + 3)..Math.Max(i + 3, end - 3)];
                    yield return (line, interpolated ? Regex.Replace(body, @"\{[^{}]*\}", "") : body);
                    line += source[start..end].Count(c => c == '\n');
                    i = end; continue;
                }
                i++;
                var literal = new StringBuilder();
                while (i < source.Length)
                {
                    if (!verbatim && source[i] == '\\') { literal.Append(source, i, Math.Min(2, source.Length - i)); i += 2; continue; }
                    if (source[i] == '"')
                    {
                        if (verbatim && i + 1 < source.Length && source[i + 1] == '"') { literal.Append('"'); i += 2; continue; }
                        i++; break;
                    }
                    if (source[i] == '\n') line++;
                    literal.Append(source[i]); i++;
                }
                string text = literal.ToString();
                yield return (line, interpolated ? Regex.Replace(text, @"\{[^{}]*\}", "") : text);
                continue;
            }
            i++;
        }
    }
}

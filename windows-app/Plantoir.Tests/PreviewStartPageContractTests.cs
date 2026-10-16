using System.Text.Json.Nodes;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// #514 (the mac's #504): Preview at Last Viewed, played from
/// <c>shared-rules.json → previewStartPage</c> — the setting, the words, the
/// one title function, what an address leaves remembered, what the asking
/// comes to, and the full decision — through the same functions the press
/// calls. Nothing here is retyped from the contract except the counts.
/// </summary>
public class PreviewStartPageContractTests
{
    private static JsonNode Block => ContractLoader.LoadJson("shared-rules.json")["previewStartPage"]!;

    private static PreviewStartPage.Setting SettingOf(string name) => name switch
    {
        "frontPage" => PreviewStartPage.Setting.FrontPage,
        "lastViewed" => PreviewStartPage.Setting.LastViewed,
        _ => throw new InvalidOperationException($"the contract names a setting this app does not know: {name}"),
    };

    private static string KeyOf(PreviewStartPage.Title title) => title switch
    {
        PreviewStartPage.Title.Preview => "preview",
        PreviewStartPage.Title.PreviewAtLastViewed => "previewAtLastViewed",
        _ => "stopPreview",
    };

    private static PreviewStartPage.Answer? AnswerOf(string? name) => name switch
    {
        null => null,
        "answered" => PreviewStartPage.Answer.Answered,
        "gone" => PreviewStartPage.Answer.Gone,
        "didNotAnswer" => PreviewStartPage.Answer.DidNotAnswer,
        _ => throw new InvalidOperationException($"the contract names an answer this app does not know: {name}"),
    };

    [Fact]
    public void TheNumbersAreTheContracts()
    {
        Assert.Equal(Block["attempts"]!.GetValue<int>(), PreviewStartPage.Attempts);
        Assert.Equal(Block["secondsPerAttempt"]!.GetValue<int>(), PreviewStartPage.SecondsPerAttempt);
        Assert.Equal(Block["goneStatuses"]!.AsArray().Select(s => s!.GetValue<int>()), PreviewStartPage.GoneStatuses);
        Assert.Equal(5, Block["setting"]!["cases"]!.AsArray().Count);
        Assert.Equal(6, Block["titles"]!["cases"]!.AsArray().Count);
        Assert.Equal(12, Block["remembering"]!["cases"]!.AsArray().Count);
        Assert.Equal(7, Block["answers"]!["cases"]!.AsArray().Count);
        Assert.Equal(10, Block["cases"]!.AsArray().Count);
        Assert.Equal(2, Block["settingChangedTrail"]!.AsArray().Count);
    }

    [Fact]
    public void EverySettingCaseReadsAsTheContractSays()
    {
        var setting = Block["setting"]!;
        Assert.Equal(new[] { "frontPage", "lastViewed" }, setting["values"]!.AsArray().Select(v => v!.ToString()));
        Assert.Equal(setting["default"]!.ToString(), new AppSettings().PreviewOpensAt);
        foreach (var value in setting["values"]!.AsArray())
            Assert.Equal(value!.ToString(), PreviewStartPage.Stored(SettingOf(value.ToString())));
        foreach (var c in setting["cases"]!.AsArray())
        {
            string? stored = c!["stored"]?.ToString();
            Assert.True(SettingOf(c["reads"]!.ToString()) == PreviewStartPage.Read(stored), $"stored {stored ?? "null"}");
        }
    }

    [Fact]
    public void TheWordsAreTheContracts()
    {
        var wording = Block["wording"]!.AsObject();
        var here = new Dictionary<string, string>
        {
            ["preview"] = PreviewStartPage.Preview,
            ["previewAtLastViewed"] = PreviewStartPage.PreviewAtLastViewed,
            ["stopPreview"] = PreviewStartPage.StopPreview,
            ["paneTitle"] = PreviewStartPage.PaneTitle,
            ["settingLabel"] = PreviewStartPage.SettingLabel,
            ["frontPageChoice"] = PreviewStartPage.FrontPageChoice,
            ["lastViewedChoice"] = PreviewStartPage.LastViewedChoice,
            ["optionNote"] = PreviewStartPage.OptionNote,
        };
        Assert.Equal(wording.Select(p => p.Key).OrderBy(k => k), here.Keys.OrderBy(k => k));
        foreach (var (key, words) in here) Assert.True(wording[key]!.ToString() == words, $"wording.{key}");

        // Windows' own sentence under the choices, and only Windows': the
        // mac's says Option and that the MENU item changes its name.
        var windows = Block["windowsWording"]!;
        Assert.Equal(new[] { "windows" }, windows["appliesOn"]!.AsArray().Select(p => p!.ToString()));
        Assert.Equal(windows["altNote"]!.ToString(), PreviewStartPage.AltNote);
        Assert.DoesNotContain("Option", PreviewStartPage.AltNote);
    }

    [Fact]
    public void TheMacsOptionSentenceIsNeverShownHere()
    {
        // Kept so the key set is the contract's; its second half is untrue
        // of a WinUI menu, so the app's own source never reaches for it.
        string app = Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir");
        var offenders = Directory.EnumerateFiles(app, "*.*", SearchOption.AllDirectories)
            .Where(f => f.EndsWith(".cs", StringComparison.Ordinal) || f.EndsWith(".xaml", StringComparison.Ordinal))
            .Where(f => !f.Contains(Path.DirectorySeparatorChar + "obj" + Path.DirectorySeparatorChar)
                     && !f.Contains(Path.DirectorySeparatorChar + "bin" + Path.DirectorySeparatorChar))
            .Where(f => File.ReadAllText(f).Contains("PreviewStartPage.OptionNote", StringComparison.Ordinal))
            .ToList();
        Assert.Empty(offenders);
    }

    [Fact]
    public void EveryTitleCaseRunsThroughTheOneFunction()
    {
        foreach (var c in Block["titles"]!["cases"]!.AsArray())
        {
            var title = PreviewStartPage.TitleFor(SettingOf(c!["setting"]!.ToString()),
                                                  c["modifierHeld"]!.GetValue<bool>(),
                                                  c["previewIsRunning"]!.GetValue<bool>());
            Assert.True(c["title"]!.ToString() == KeyOf(title), c.ToJsonString());
            Assert.Equal(Block["wording"]![KeyOf(title)]!.ToString(), PreviewStartPage.Words(title));
        }
    }

    [Fact]
    public void TheTitleAndThePressAgree()
    {
        // What the button says is what the press does: XOR, four ways.
        foreach (var setting in new[] { PreviewStartPage.Setting.FrontPage, PreviewStartPage.Setting.LastViewed })
            foreach (bool held in new[] { false, true })
            {
                bool atLastViewed = PreviewStartPage.OpensAtLastViewed(setting, held);
                var title = PreviewStartPage.TitleFor(setting, held, previewIsRunning: false);
                Assert.Equal(atLastViewed, title == PreviewStartPage.Title.PreviewAtLastViewed);
            }
    }

    [Fact]
    public void OnlyAltWithoutCtrlIsTheModifier()
    {
        Assert.True(PreviewStartPage.ModifierHeld(altDown: true, ctrlDown: false));
        Assert.False(PreviewStartPage.ModifierHeld(altDown: true, ctrlDown: true));   // AltGr
        Assert.False(PreviewStartPage.ModifierHeld(altDown: false, ctrlDown: true));
        Assert.False(PreviewStartPage.ModifierHeld(altDown: false, ctrlDown: false));
    }

    [Fact]
    public void EveryRememberingCaseLeavesWhatTheContractSays()
    {
        foreach (var c in Block["remembering"]!["cases"]!.AsArray())
        {
            string name = c!["name"]!.ToString();
            string? page = c["page"]?.ToString();
            var root = new Uri(c["previewRoot"]!.ToString());
            string? expected = c["remember"]?.ToString();
            string? got = PreviewStartPage.Remember(page, root, c["appLoadUnderWay"]!.GetValue<bool>());
            Assert.True(expected == got, $"{name}: expected {expected ?? "null"}, got {got ?? "null"}");
        }
    }

    [Fact]
    public void EveryAnswerCaseEndsAsTheContractSays()
    {
        foreach (var c in Block["answers"]!["cases"]!.AsArray())
        {
            var statuses = c!["statuses"]!.AsArray().Select(s => s is null ? (int?)null : s.GetValue<int>()).ToList();
            var expected = AnswerOf(c["answer"]!.ToString());
            Assert.True(expected == PreviewStartPage.AfterTries(statuses), $"after tries {c.ToJsonString()}");

            // The asking itself, scripted: no more asks than the statuses
            // given, a one-second pause between them, never after the last.
            int asked = 0;
            var pauses = new List<TimeSpan>();
            var answer = PreviewStartPage.AskAsync(
                _ => Task.FromResult(statuses[asked++]),
                (pause, _) => { pauses.Add(pause); return Task.CompletedTask; },
                CancellationToken.None).GetAwaiter().GetResult();
            Assert.True(expected == answer, $"asked {c.ToJsonString()}");
            Assert.Equal(statuses.Count, asked);
            Assert.Equal(asked - 1, pauses.Count);
            Assert.All(pauses, pause => Assert.Equal(TimeSpan.FromSeconds(1), pause));
        }
    }

    [Fact]
    public void EveryDecisionCaseOpensAndSaysWhatTheContractSays()
    {
        foreach (var c in Block["cases"]!.AsArray())
        {
            string name = c!["name"]!.ToString();
            var setting = SettingOf(c["setting"]!.ToString());
            bool held = c["modifierHeld"]!.GetValue<bool>();
            string? remembered = c["remembered"]?.ToString();
            var answer = AnswerOf(c["answer"]?.ToString());
            bool justChanged = c["frontPageWasJustChanged"]!.GetValue<bool>();

            var (opens, trail) = PreviewStartPage.DecideForCase(setting, held, remembered, answer, justChanged);
            string expectedOpens = c["opens"]!.ToString();
            Assert.True(expectedOpens == (opens == PreviewStartPage.Opens.RememberedPage ? "rememberedPage" : "frontPage"), $"{name}: opens");
            Assert.True(c["trail"]?.ToString() == trail, $"{name}: trail {trail ?? "null"}");

            // A case that needed no asking is one the press would not ask about.
            string? asks = PreviewStartPage.PathToAsk(PreviewStartPage.OpensAtLastViewed(setting, held), justChanged, remembered);
            if (answer is null) Assert.True(asks is null, $"{name}: the press would have asked about {asks}");
            else Assert.True(asks == remembered, $"{name}: the press would not have asked");
        }
    }

    [Fact]
    public void EverySettingChangedLineIsTheContracts()
    {
        foreach (var c in Block["settingChangedTrail"]!.AsArray())
            Assert.Equal(c!["trail"]!.ToString(), PreviewStartPage.SettingChangedTrail(SettingOf(c["choice"]!.ToString())));
    }
}

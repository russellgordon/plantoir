using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// <c>contracts/app-rules.json</c> → <c>outsideAgents.fixWith</c> (#736, the
/// mac's #717 part two): both case lists run here as the mac runs them, and
/// every word and bound <see cref="FixWithAssistant"/> retypes pinned key by
/// key. The mac's twin is <c>FixWithAssistantTests.swift</c>.
/// </summary>
public class FixWithAssistantContractTests
{
    private static JsonNode FixWith() => ContractLoader.LoadJson("app-rules.json")["outsideAgents"]!["fixWith"]!;

    private static SectionProblemRow Row(string kind, string page, string prompt, string id = "") => new()
    {
        Id = id.Length > 0 ? id : kind + "|" + page + "|" + prompt.GetHashCode(),
        Kind = kind, Page = page, Prompt = prompt,
    };

    public static IEnumerable<object[]> ButtonCaseNames() =>
        FixWith()["buttonCases"]!.AsArray().Select(c => new object[] { c!["name"]!.ToString() });

    public static IEnumerable<object[]> GreetingCaseNames() =>
        FixWith()["greetingCases"]!.AsArray().Select(c => new object[] { c!["name"]!.ToString() });

    /// <summary><c>buttonCases</c>: which buttons show, whether they can be pressed, and what a press hands over.</summary>
    [Theory]
    [MemberData(nameof(ButtonCaseNames))]
    public void ButtonCases(string name)
    {
        var testCase = FixWith()["buttonCases"]!.AsArray().Single(c => c!["name"]!.ToString() == name)!;
        var rows = testCase["rows"]!.AsArray().Select((r, i) => (
            Row: Row("figuresCouldNotBeDrawn", "Unit 1/Graphs", "p", id: "row" + i),
            Ticked: r!["ticked"]!.GetValue<bool>(),
            State: r["state"]!.ToString())).ToList();
        var handover = FixWithAssistant.HandoverOf(rows.Select(r => r.Row),
            id => rows.Single(r => r.Row.Id == id).Ticked,
            row => rows.Single(r => r.Row.Id == row.Id).State == "fixedInTheSource"
                ? SectionProblemsRules.RowState.FixedInTheSource : SectionProblemsRules.RowState.Current);
        var buttons = FixWithAssistant.Buttons(testCase["claudeInstalled"]!.GetValue<bool>(),
            testCase["codexInstalled"]!.GetValue<bool>(), testCase["keptForReference"]!.GetValue<bool>(), handover);
        var expect = testCase["expect"]!;
        Assert.Equal(expect["claudeShown"]!.GetValue<bool>(), buttons.ClaudeShown);
        Assert.Equal(expect["codexShown"]!.GetValue<bool>(), buttons.CodexShown);
        Assert.Equal(expect["enabled"]!.GetValue<bool>(), buttons.Enabled);
        Assert.Equal(expect["handedOver"]!.GetValue<int>(), handover.Rows.Count);
        Assert.Equal(expect["unticked"]!.GetValue<int>(), handover.Unticked);
        Assert.Equal(expect["fixedInTheSource"]!.GetValue<int>(), handover.FixedInTheSource);
    }

    /// <summary><c>greetingCases</c>: the whole message exactly, or its bounds; never a semicolon, a newline or ". (".</summary>
    [Theory]
    [MemberData(nameof(GreetingCaseNames))]
    public void GreetingCases(string name)
    {
        var testCase = FixWith()["greetingCases"]!.AsArray().Single(c => c!["name"]!.ToString() == name)!;
        var greeting = FixWithAssistant.GreetingFor(RowsOf(testCase), testCase["course"]!.ToString(),
            testCase["courseName"]!.ToString(), testCase["section"]!.GetValue<int>(), testCase["occasion"]!.ToString());
        var expect = testCase["expect"];
        if (expect is null) { Assert.Null(greeting); return; }
        Assert.NotNull(greeting);
        Assert.Equal(expect["rowsNamed"]!.GetValue<int>(), greeting!.RowsNamed);
        Assert.Equal(expect["rowsNotNamed"]!.GetValue<int>(), greeting.RowsNotNamed);
        if (expect["text"] is { } text) Assert.Equal(text.ToString(), greeting.Text);
        if (expect["atMostCharacters"] is { } most) Assert.True(FixWithAssistant.Characters(greeting.Text) <= most.GetValue<int>());
        if (expect["textHas"] is { } has) Assert.Contains(has.ToString(), greeting.Text);
        AssertOneCleanLine(greeting.Text);
    }

    internal static IReadOnlyList<SectionProblemRow> RowsOf(JsonNode testCase)
    {
        if (testCase["manyRows"] is { } many)
        {
            int count = many["count"]!.GetValue<int>(), characters = many["promptCharacters"]!.GetValue<int>();
            return Enumerable.Range(1, count).Select(n =>
            {
                string prompt = many["prompt"]!.ToString().Replace("{n}", n.ToString());
                return Row(many["kind"]!.ToString(), many["page"]!.ToString().Replace("{n}", n.ToString()),
                           prompt.PadRight(characters, 'x'), id: "row" + n);
            }).ToList();
        }
        return testCase["rows"]!.AsArray().Select((r, i) =>
            Row(r!["kind"]!.ToString(), r["page"]!.ToString(), r["prompt"]!.ToString(), id: "row" + i)).ToList();
    }

    private static void AssertOneCleanLine(string text)
    {
        Assert.DoesNotContain(";", text);
        Assert.DoesNotContain("\n", text);
        Assert.DoesNotContain("\r", text);
        Assert.DoesNotContain(". (", text);
        Assert.DoesNotContain("\"", text);
    }

    /// <summary>Every word, bound and list this app retypes is the contract's, key by key.</summary>
    [Fact]
    public void PiecesAndBoundsAreTheContracts()
    {
        var fixWith = FixWith();
        var buttons = fixWith["buttons"]!.AsArray();
        Assert.Equal(new[] { "claude", "codex" }, buttons.Select(b => b!["key"]!.ToString()));
        Assert.Equal(FixWithAssistant.ClaudeButtonTitle, buttons[0]!["title"]!.ToString());
        Assert.Equal(FixWithAssistant.CodexButtonTitle, buttons[1]!["title"]!.ToString());
        Assert.Equal(fixWith["notEnabledHelp"]!.ToString(), FixWithAssistant.NotEnabledHelp);

        var pieces = fixWith["fixGreeting"]!.AsObject().ToDictionary(p => p.Key, p => p.Value!.ToString());
        var ours = new Dictionary<string, string>
        {
            ["openingOne"] = FixWithAssistant.OpeningOne,
            ["openingSeveral"] = FixWithAssistant.OpeningSeveral,
            ["rowWithAPage"] = FixWithAssistant.RowWithAPage,
            ["rowWithoutAPage"] = FixWithAssistant.RowWithoutAPage,
            ["sharedPage"] = FixWithAssistant.SharedPage,
            ["rowSeparator"] = FixWithAssistant.RowSeparator,
            ["more"] = FixWithAssistant.More,
            ["afterTheRows"] = FixWithAssistant.AfterTheRows,
            ["planFirst"] = FixWithAssistant.PlanFirst,
            ["closingPreview"] = FixWithAssistant.ClosingPreview,
            ["closingDeploy"] = FixWithAssistant.ClosingDeploy,
            ["closingBoth"] = FixWithAssistant.ClosingBoth,
        };
        Assert.Equal(pieces.OrderBy(p => p.Key), ours.OrderBy(p => p.Key));
        foreach (var piece in pieces.Values) Assert.DoesNotContain(";", piece);

        Assert.Equal(fixWith["mostRowsInThePrompt"]!.GetValue<int>(), FixWithAssistant.MostRowsInThePrompt);
        Assert.Equal(fixWith["greetingMaxCharacters"]!.GetValue<int>(), FixWithAssistant.GreetingMaxCharacters);
        Assert.Equal(fixWith["pagePlaceMaxCharacters"]!.GetValue<int>(), FixWithAssistant.PagePlaceMaxCharacters);
        Assert.Equal(fixWith["courseNameMaxCharacters"]!.GetValue<int>(), FixWithAssistant.CourseNameMaxCharacters);
        Assert.Equal(fixWith["otherwiseSkill"]!.ToString(), FixWithAssistant.OtherwiseSkill);
        Assert.Equal(fixWith["skillForKind"]!.AsObject().ToDictionary(p => p.Key, p => p.Value!.ToString()).OrderBy(p => p.Key),
                     FixWithAssistant.SkillForKind.OrderBy(p => p.Key));
        Assert.Equal(fixWith["deployOnlyKinds"]!.AsArray().Select(k => k!.ToString()).Order(), FixWithAssistant.DeployOnlyKinds.Order());
        Assert.Equal(fixWith["replaceInTheMessage"]!.AsArray().Select(p => (p![0]!.ToString(), p[1]!.ToString())),
                     FixWithAssistant.ReplaceInTheMessage);
        foreach (var (from, to) in FixWithAssistant.ReplaceInTheMessage) Assert.Equal(from.Length, to.Length);

        // What a door that did not open says: one Core place for both callers.
        var agents = ContractLoader.LoadJson("app-rules.json")["outsideAgents"]!["agents"]!.AsArray();
        var claude = agents.Single(a => a!["key"]!.ToString() == "claude")!;
        var codex = agents.Single(a => a!["key"]!.ToString() == "codex")!;
        Assert.Equal(claude["didNotOpenTitle"]!.ToString(), OutsideDoorWording.ClaudeDidNotOpenTitle);
        Assert.Equal(codex["didNotOpenTitle"]!.ToString(), OutsideDoorWording.CodexDidNotOpenTitle);
        Assert.Equal(claude["couldNotStart"]!.ToString().Replace("{course}", "ICS3U"), OutsideDoorWording.ClaudeCouldNotStart("ICS3U"));
        Assert.Equal(codex["couldNotStart"]!.ToString().Replace("{course}", "ICS3U"), OutsideDoorWording.CodexCouldNotStart("ICS3U"));

        // The How I Teach sentence inside the message is the door's own.
        Assert.Equal(ContractLoader.LoadJson("app-rules.json")["outsideAgents"]!["greetingHowITeachSentence"]!.ToString(),
                     ClaudeCodeLauncher.HowITeachSentence);
    }

    /// <summary>Every skill named is one the app writes into the working folder, and every key is a problem's kind.</summary>
    [Fact]
    public void EverySkillIsCarried()
    {
        string skills = Path.Combine(ContractLoader.RepositoryRoot, "support", "agent_guidance", "skills");
        foreach (string skill in FixWithAssistant.SkillForKind.Values.Append(FixWithAssistant.OtherwiseSkill).Distinct())
            Assert.True(Directory.Exists(Path.Combine(skills, skill)), $"{skill} is not a skill the app carries");
        var kinds = ContractLoader.LoadJson("shared-rules.json")["sectionProblems"]!["kinds"]!.AsArray()
            .Select(k => k!["kind"]!.ToString()).ToHashSet();
        foreach (string kind in FixWithAssistant.SkillForKind.Keys.Concat(FixWithAssistant.DeployOnlyKinds))
            Assert.Contains(kind, kinds);
    }

    /// <summary>
    /// Whatever the rows, the course and the pages bring — a semicolon, a
    /// double quote, a line break in a name, a 7,000-character name — the
    /// message is one line, bounded, with no semicolon and no ". (".
    /// </summary>
    [Fact]
    public void NoSemicolonNewlineOrStopParen()
    {
        var rows = Enumerable.Range(1, 12).Select(n => Row("printPdfNotFound", $"Unit {n}/A; \"B\" 100% & {{section}}",
            $"“Unit {n}”; it says \"x\".", id: "r" + n)).ToList();
        var greeting = FixWithAssistant.GreetingFor(rows, "MPM2D", new string('n', 7000) + ";\"", 1, "preview")!;
        AssertOneCleanLine(greeting.Text);
        Assert.True(FixWithAssistant.Characters(greeting.Text) <= FixWithAssistant.GreetingMaxCharacters);
        Assert.Contains("{section}", greeting.Text);
        Assert.Contains("100%", greeting.Text);
        Assert.Equal(12, greeting.RowsNamed + greeting.RowsNotNamed);
    }

    /// <summary>Characters are counted as the mac counts them: an emoji is one, not two.</summary>
    [Fact]
    public void BoundsCountCharactersNotUtf16Units()
    {
        string page = string.Concat(Enumerable.Repeat("🎓", 400));
        string file = FixWithAssistant.FileOf(page, "MPM2D");
        string place = file["courses/MPM2D/".Length..^".md".Length];
        Assert.Equal(FixWithAssistant.PagePlaceMaxCharacters, FixWithAssistant.Characters(place));
        Assert.EndsWith("…", place);
        string name = string.Concat(Enumerable.Repeat("é🎓", 60));
        var greeting = FixWithAssistant.GreetingFor(new[] { Row("printPdfNotFound", "", "p") }, "MPM2D", name, 1, "preview")!;
        string named = greeting.Text[(greeting.Text.IndexOf('(') + 1)..greeting.Text.IndexOf(')')];
        Assert.Equal(FixWithAssistant.CourseNameMaxCharacters, FixWithAssistant.Characters(named));
    }

    /// <summary>When the door's own UTF-16 bound bites first, rows go from the END, said with "more".</summary>
    [Fact]
    public void TheCommandLineBoundDropsRowsFromTheEnd()
    {
        var rows = Enumerable.Range(1, 10).Select(n => Row("printPdfNotFound", $"Unit {n}", new string('p', 300), id: "r" + n)).ToList();
        var whole = FixWithAssistant.GreetingFor(rows, "MPM2D", "", 1, "preview")!;
        Assert.Equal(10, whole.RowsNamed);
        var cut = FixWithAssistant.GreetingFor(rows, "MPM2D", "", 1, "preview", fits: text => text.Length <= 2000)!;
        Assert.True(cut.Text.Length <= 2000);
        Assert.Equal(10, cut.RowsNamed + cut.RowsNotNamed);
        Assert.True(cut.RowsNamed < 10);
        Assert.Contains($" · and {cut.RowsNotNamed} more on the Problems tab. ", cut.Text);
        Assert.Contains("1) ", cut.Text);
        Assert.DoesNotContain($"{cut.RowsNamed + 1}) ", cut.Text);
        // The first is always named.
        var one = FixWithAssistant.GreetingFor(rows, "MPM2D", "", 1, "preview", fits: _ => false)!;
        Assert.Equal(1, one.RowsNamed);
    }

    /// <summary>A real record's rowState leaves out a row another section's later build shows fixed in the source.</summary>
    [Fact]
    public void RealRowStateLeavesARowOut()
    {
        var broken = Row("figuresCouldNotBeDrawn", "Unit 1/Graphs", "p", id: "a");
        var other = Row("quizzesNotReady", "section1/Class 4", "q", id: "b");
        var here = new SectionProblemsRecord
        {
            Course = "MPM2D", Section = 1, BuildId = "1", BuiltAt = DateTimeOffset.Parse("2026-11-01T10:00:00Z"),
            Rows = new[] { broken, other }, PagesShown = new[] { "Unit 1/Graphs", "section1/Class 4" }, SiteSaidComplete = true,
        };
        var later = new SectionProblemsRecord
        {
            Course = "MPM2D", Section = 2, BuildId = "2", BuiltAt = DateTimeOffset.Parse("2026-11-02T10:00:00Z"),
            Rows = Array.Empty<SectionProblemRow>(), PagesShown = new[] { "Unit 1/Graphs" }, SiteSaidComplete = true,
        };
        var handover = FixWithAssistant.HandoverOf(here, new[] { later }, _ => true);
        Assert.Equal(new[] { "b" }, handover.Rows.Select(r => r.Id));
        Assert.Equal(1, handover.FixedInTheSource);
        Assert.Equal(0, handover.Unticked);
    }

    /// <summary>
    /// The trail's line is the contract's <c>line</c> with "problem(s)" said as
    /// the mac says it, and carries counts and kinds only: no page and no
    /// row's words, which are the teacher's own.
    /// </summary>
    [Fact]
    public void TheTrailLineIsTheContractsAndCarriesNoPage()
    {
        var entry = ContractLoader.LoadJson("shared-rules.json")["activityTrail"]!["mustRecord"]!.AsArray()
            .Single(e => e!["event"]!.ToString() == "asked an assistant to fix problems")!;
        Assert.Equal("asked an assistant to fix problems", ActivityTrail.KeyFor(ActivityTrail.Event.AskedAnAssistantToFixProblems));
        string line = entry["line"]!.ToString();
        Assert.StartsWith("{course}/{section} · ", line);

        var rows = new[]
        {
            Row("figuresCouldNotBeDrawn", "Unit 1/Secret Page", "“Unit 1/Secret Page”, diagram 1: words", id: "a"),
            Row("figuresCouldNotBeDrawn", "Unit 2/Other", "o", id: "b"),
            Row("printPdfNotFound", "", "handout", id: "c"),
        };
        var handover = new FixWithAssistant.Handover(rows, Unticked: 2, FixedInTheSource: 1);
        var greeting = new FixWithAssistant.Greeting("x", RowsNamed: 3, RowsNotNamed: 0);
        string ours = FixWithAssistant.TrailLine(FixWithAssistant.Assistant.Codex, handover, greeting);
        string expected = line["{course}/{section} · ".Length..]
            .Replace("{assistant}", "Codex").Replace("{count} problem(s)", "3 problems")
            .Replace("{kinds}", "figuresCouldNotBeDrawn, printPdfNotFound").Replace("{named}", "3")
            .Replace("{unticked}", "2").Replace("{fixed}", "1");
        Assert.Equal(expected, ours);
        Assert.DoesNotContain("Secret", ours);
        Assert.DoesNotContain("handout", ours);
        Assert.Contains("fix 1 problem (", FixWithAssistant.TrailLine(FixWithAssistant.Assistant.Claude,
            new FixWithAssistant.Handover(new[] { rows[2] }, 0, 0), greeting));
    }

    /// <summary>Rule 1: the message a teacher may read in the terminal names no machinery.</summary>
    [Fact]
    public void TheMessageNamesNoMachinery()
    {
        foreach (var testCase in FixWith()["greetingCases"]!.AsArray())
        {
            var greeting = FixWithAssistant.GreetingFor(RowsOf(testCase!), testCase["course"]!.ToString(),
                testCase["courseName"]!.ToString(), testCase["section"]!.GetValue<int>(), testCase["occasion"]!.ToString());
            if (greeting is null) continue;
            foreach (string word in new[] { "toolchain", "script", "Docker", "container", "token", "model" })
                Assert.DoesNotContain(word, greeting.Text, StringComparison.OrdinalIgnoreCase);
        }
    }
}

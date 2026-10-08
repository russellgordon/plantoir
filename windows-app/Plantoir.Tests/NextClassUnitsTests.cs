using System.ComponentModel;
using System.Reflection;
using System.Text.Json.Nodes;
using ModelContextProtocol.Protocol;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Plantoir.Mcp;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// A new unit, a unit or day other than the next one, and several pages —
/// asked of an add_next_class that carries only a course and a section
/// (#440). Answered in code where the sentence is a fixed frame; stopped and
/// pointed (settler S3) where the model answered it with the plain call. The
/// twin of the mac's <c>NextClassUnitsTests.swift</c>.
/// </summary>
/// <remarks>
/// <para><b>Why this file exists.</b> Measured on the mac 2026-10-07 (M4 Pro,
/// b10435): ten such sentences reached add_next_class 50 of 50 with only a
/// course and a section, each adding ONE page in the current unit and
/// reporting success. And this app's router, shown <c>unit</c> and
/// <c>days</c> until #440, sent unit "next" on 50 of 50 plain "add the next
/// class" calls (v1.4.3 bundle A, UHD 620).</para>
///
/// <para>Every row is read from <c>contracts/assist-cases.json</c> →
/// <c>nextClassUnits</c>, so the mac reads the same sentences. Nothing typed
/// here could disagree with it, apart from the course fixtures the pointer
/// is run against.</para>
/// </remarks>
[Collection(SharedActivityState.Name)]
public sealed class NextClassUnitsTests : IDisposable
{
    private readonly List<string> _folders = new();
    private readonly string _trail = Path.Combine(Path.GetTempPath(), "plantoir-next-class-" + Guid.NewGuid().ToString("N") + ".txt");

    public NextClassUnitsTests() => ActivityTrail.SetCustomLogPathForTesting(_trail);

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { File.Delete(_trail); } catch { }
        foreach (var folder in _folders)
            try { Directory.Delete(folder, recursive: true); } catch { }
    }

    // ---- The frames, row by row -----------------------------------------

    /// <summary>Every accepted row is answered in code with the arguments it names.</summary>
    [Fact]
    public void EveryAcceptedRowIsAnsweredInCode()
    {
        var rows = Rows("accepted");
        Assert.True(rows.Count >= 10, "accepted rows have gone missing");
        var wrong = new List<string>();
        foreach (var row in rows)
        {
            string input = row["input"]!.ToString();
            Assert.NotNull(row["why"]);
            var command = AssistCardCommand.Matching(input);
            if (command is null)
            {
                wrong.Add($"\"{input}\" is in the contract as answered in code and matches nothing");
                continue;
            }
            var expected = row["expectArguments"]!.AsObject().ToDictionary(pair => pair.Key, pair => pair.Value!.ToString());
            if (command.ToolName != row["expectTool"]!.ToString() ||
                !expected.OrderBy(p => p.Key).SequenceEqual(command.Arguments.OrderBy(p => p.Key)))
                wrong.Add($"\"{input}\": {command.ToolName} {string.Join(",", command.Arguments.Select(p => p.Key + "=" + p.Value))}");
        }
        Assert.True(wrong.Count == 0, string.Join("\n", wrong));
    }

    /// <summary>Every not-this row falls through to the model.</summary>
    [Fact]
    public void EveryNotThisRowFallsThroughToTheModel()
    {
        var rows = Rows("notThis");
        Assert.True(rows.Count >= 10, "notThis rows have gone missing");
        var caught = rows.Select(row => row["input"]!.ToString())
                         .Where(input => AssistCardCommand.Matching(input) is not null)
                         .ToList();
        Assert.True(caught.Count == 0, "These matched a card: " + string.Join(" | ", caught));
    }

    // ---- Settler S3, row by row -------------------------------------------

    /// <summary>
    /// Every pointed row reaches the model (no card matches, so the routing
    /// measurement can never quietly score a card) and is pointed for the
    /// reason the row names.
    /// </summary>
    [Fact]
    public void EveryPointedRowReachesTheModelAndIsPointed()
    {
        var rows = Rows("pointed");
        Assert.True(rows.Count >= 15, "pointed rows have gone missing");
        var kindsSeen = new HashSet<string>();
        var wrong = new List<string>();
        foreach (var row in rows)
        {
            string input = row["input"]!.ToString();
            Assert.NotNull(row["why"]);
            Assert.True(row["reachesModel"]!.GetValue<bool>(), input);
            var given = row["given"]!.AsObject();
            if (AssistCardCommand.Matching(input, NumberedWord(given)) is not null)
                wrong.Add($"\"{input}\" is marked as reaching the model and matches a card");
            string expected = row["kind"]!.ToString();
            kindsSeen.Add(expected);
            var kind = AssistNextClassUnits.KindOf(input, ReadingFrom(given));
            string got = kind is { } k ? AssistNextClassUnits.Letter(k) : "none";
            if (got != expected) wrong.Add($"\"{input}\": expected {expected}, got {got}");
        }
        Assert.True(wrong.Count == 0, string.Join("\n", wrong));
        Assert.Equal(new[] { "a", "b", "c" }, kindsSeen.OrderBy(k => k));
    }

    /// <summary>
    /// Every runs row is left alone by S3 — the deterministic sweep of ruling
    /// 5: every add_next_class sentence on record that reaches the model is
    /// here, and none is stopped. <c>reachesModel</c> is pinned both ways.
    /// </summary>
    [Fact]
    public void EveryRunsRowRuns()
    {
        var rows = Rows("runs");
        Assert.True(rows.Count >= 15, "runs rows have gone missing");
        int controls = 0;
        var wrong = new List<string>();
        foreach (var row in rows)
        {
            string input = row["input"]!.ToString();
            Assert.NotNull(row["why"]);
            var given = row["given"]!.AsObject();
            bool reachesModel = row["reachesModel"]!.GetValue<bool>();
            bool card = AssistCardCommand.Matching(input, NumberedWord(given)) is not null;
            if (card == reachesModel) wrong.Add($"\"{input}\": reachesModel says {reachesModel}, a card {(card ? "matched" : "did not")}");
            if (AssistNextClassUnits.KindOf(input, ReadingFrom(given)) is { } kind)
                wrong.Add($"\"{input}\" is a runs row and S3 stops it ({AssistNextClassUnits.Letter(kind)})");
            if (row["measuredAsControl"]?.GetValue<bool>() == true)
            {
                Assert.True(reachesModel, $"{input}: a measured control must reach the model");
                controls++;
            }
        }
        Assert.True(wrong.Count == 0, string.Join("\n", wrong));
        Assert.True(controls >= 5);
    }

    /// <summary>
    /// The rows that reach the model are not caught by the agent's OTHER
    /// layers either — Windows answers some sentences in the agent before the
    /// matcher (the preview-asked-plainly reading, and the agent's own
    /// interceptions), which the mac's test cannot see. A model is scripted to
    /// answer each one with a plain add_next_class; the sentence must reach it.
    /// </summary>
    [Fact]
    public async Task EveryRowThatReachesTheModelReachesItThroughTheAgent()
    {
        var reaching = Rows("pointed").Concat(Rows("runs"))
            .Where(row => row["reachesModel"]!.GetValue<bool>())
            .Select(row => row["input"]!.ToString())
            .ToList();
        var missed = new List<string>();
        foreach (string input in reaching)
        {
            var model = new WindowBindingContractTests.ScriptedModel();
            model.Then(AddNextClassReply("""{"course":"ICS3U","section":1}"""), "tool_calls");
            var agent = new AssistAgent(model, new WindowBindingContractTests.RecordingTools(), LocalSchemas(), "ICS3U", 1)
            {
                ConfirmationMode = () => false,
            };
            await agent.Say(input, CancellationToken.None);
            if (model.Asked.Count != 1) missed.Add(input);
        }
        Assert.True(missed.Count == 0, "Answered before the model: " + string.Join(" | ", missed));
    }

    /// <summary>Nothing at all without a reading: no dates, no S3 (ruling 7).</summary>
    [Fact]
    public void WithoutAReadingNothingIsStopped()
    {
        Assert.Null(AssistNextClassUnits.KindOf("Start a new unit for the next class", null));
        Assert.Null(AssistNextClassUnits.KindOf("Add the next two classes", null));
    }

    /// <summary>
    /// The two places a literal C# port would differ from Swift (stack-2 plan
    /// review, L1): a unit number past 32 bits is still a number, and a
    /// decomposed accent is one non-letter, never "e" then a separator.
    /// </summary>
    [Fact]
    public void ThePortReadsNumbersAndAccentsAsSwiftDoes()
    {
        var reading = new AssistNextClassReading("Unit", false, ClassNoun.Class, 2, 6);
        Assert.Equal(AssistNextClassUnits.Kind.AnotherUnitOrDay,
                     AssistNextClassUnits.KindOf("Add the next class to Unit 3000000000", reading));
        Assert.Equal(new[] { "add", "the", "next", "caf", "class" },
                     AssistNextClassUnits.Words("Add the next café class"));
        Assert.Equal(new[] { "tomorrow's", "class" }, AssistNextClassUnits.Words("Tomorrow’s class"));
    }

    // ---- Hiding the two arguments (#440 item 1) --------------------------

    /// <summary>
    /// The REAL served add_next_class and plan_add_next_class, narrowed for
    /// the local model, show only what the contract's local schema shows —
    /// course and section — while the server keeps declaring unit, days and
    /// duplicate for the cards (stack-2 plan review, L4: the pin that catches
    /// a future server argument leaking to the router).
    /// </summary>
    [Fact]
    public void TheLocalModelSeesOnlyCourseAndSection()
    {
        var served = new JsonArray();
        foreach (var method in typeof(PlantoirTools).GetMethods(BindingFlags.Public | BindingFlags.Instance))
        {
            var attribute = method.GetCustomAttribute<ModelContextProtocol.Server.McpServerToolAttribute>();
            if (attribute?.Name is not ("add_next_class" or "plan_add_next_class")) continue;
            var properties = new JsonObject();
            var required = new JsonArray();
            foreach (var parameter in method.GetParameters())
            {
                if (parameter.GetCustomAttribute<DescriptionAttribute>() is null) continue;
                properties[parameter.Name!] = new JsonObject { ["type"] = parameter.ParameterType == typeof(int) ? "integer" : "string" };
                if (!parameter.HasDefaultValue) required.Add(parameter.Name);
            }
            Assert.True(properties.ContainsKey("unit") && properties.ContainsKey("days") && properties.ContainsKey("duplicate"),
                        $"{attribute.Name} no longer declares unit, days and duplicate: the cards need them declared");
            served.Add(new JsonObject
            {
                ["type"] = "function",
                ["function"] = new JsonObject
                {
                    ["name"] = attribute.Name,
                    ["description"] = "TEACHERS SAY: \"add the next class\".",
                    ["parameters"] = new JsonObject { ["type"] = "object", ["properties"] = properties, ["required"] = required },
                },
            });
        }
        Assert.Equal(2, served.Count);

        var narrowed = AssistAgent.NarrowToLocal(served, "ICS3U");
        var contract = LocalSchemas().Single(tool => tool!["function"]!["name"]!.ToString() == "add_next_class")!;
        var expected = contract["function"]!["parameters"]!["properties"]!.AsObject().Select(p => p.Key).OrderBy(k => k).ToList();
        var local = narrowed.Single(tool => tool!["function"]!["name"]!.ToString() == "add_next_class")!;
        Assert.Equal(expected, local["function"]!["parameters"]!["properties"]!.AsObject().Select(p => p.Key).OrderBy(k => k));
        Assert.Equal(new[] { "course", "section" }, expected);

        // plan_add_next_class is not a local tool at all; were it ever made
        // one, its card-only entries keep unit and days hidden there too.
        Assert.DoesNotContain(narrowed, tool => tool!["function"]!["name"]!.ToString() == "plan_add_next_class");
        foreach (string argument in new[] { "unit", "days", "duplicate" })
            Assert.Contains("plan_add_next_class." + argument, AssistAgent.CardOnlyArguments);
    }

    // ---- The pointer (ruling 1) -------------------------------------------

    /// <summary>
    /// The generated wording is this app's own output, and every sentence each
    /// pointer quotes, typed back in that kind of course, is a card that does
    /// what it says there — a Unit course, a Module course and a numbered one.
    /// The days sentence adds to the LATEST unit and "Start a new unit" opens
    /// the one after it, never a unit further on (mac review N-impl F4).
    /// </summary>
    [Fact]
    public void EveryQuotedSentenceIsACardThatWorksInThatCourse()
    {
        var rows = Rows("pointerSentences");
        Assert.Equal(3, rows.Count);
        var wording = ContractLoader.LoadJson("assist-wording.json")["wording"]!;
        foreach (var row in rows)
        {
            string key = row["wording"]!.ToString();
            var given = row["given"]!.AsObject();
            var reading = ReadingFrom(given)!;
            string sentence = AssistNextClassUnits.Pointer(reading);
            Assert.Equal(wording[key]!.ToString(), sentence);
            var quoted = QuotedSentences(sentence);
            Assert.NotEmpty(quoted);
            foreach (string typedBack in quoted)
            {
                var card = AssistCardCommand.Matching(typedBack, NumberedWord(given));
                Assert.True(card is not null, $"{key} tells the teacher to say “{typedBack}”, and that is not answered in code");
                Assert.Equal("add_next_class", card!.ToolName);
                Assert.Null(AssistNextClassUnits.KindOf(typedBack, null));
                AssertTheCardAddsAPage(card, typedBack, reading);
            }
        }
    }

    // ---- The agent ----------------------------------------------------------

    /// <summary>
    /// The model answers "Add the next two classes" with a plain
    /// add_next_class: nothing added, no card, the turn wound back, the
    /// pointer said, and the trail's line written in place of the chose-a-tool
    /// line. Through the REAL server's plan_add_next_class, so the reading
    /// travels the way it does in the window.
    /// </summary>
    [Fact]
    public async Task APointedSentenceAddsNothingAndLeavesALine()
    {
        string folder = UnitCourse(withDates: true);
        var tools = new AssistScenarioTests.RealTools(new AssistWorkspace(folder, new FakeLauncher()));
        var model = new WindowBindingContractTests.ScriptedModel();
        model.Then(AddNextClassReply("""{"course":"ICS3U","section":1}"""), "tool_calls");
        model.Then(new JsonObject { ["role"] = "assistant", ["content"] = "Hello." }, "stop");
        var agent = new AssistAgent(model, tools, LocalSchemas(), "ICS3U", 1) { ConfirmationMode = () => true };
        var pagesBefore = ClassPages(folder);

        var lines = await agent.Say("Add the next two classes", CancellationToken.None);

        Assert.Single(model.Asked);
        Assert.False(agent.IsAwaitingApproval, "a plan card went up for a sentence S3 stops");
        Assert.DoesNotContain(lines, line => line.NeedsApproval);
        Assert.Equal(AssistWording.NextClassNeedsItsOwnPhrasing(ClassNoun.Class, 1), lines.Last().Text);
        Assert.Equal(pagesBefore, ClassPages(folder));
        string trail = File.ReadAllText(_trail);
        Assert.Contains(AssistAgent.NextClassPointedLine(AssistNextClassUnits.Kind.Several), trail);
        Assert.DoesNotContain("the assistant chose add next class", trail);

        // Wound back: the next turn's request does not carry the stopped one.
        await agent.Say("Hello", CancellationToken.None);
        Assert.DoesNotContain("Add the next two classes", model.Asked[1].ToJsonString());
    }

    /// <summary>The runner's reading: null without dates, the plain next page with them, null for a course that is gone.</summary>
    [Fact]
    public void TheRunnersReading()
    {
        string folder = UnitCourse(withDates: false);
        var workspace = new AssistWorkspace(folder, new FakeLauncher());
        Assert.Null(workspace.NextClassReading("ICS3U", 1));
        RememberDates(folder);
        var reading = workspace.NextClassReading("ICS3U", 1);
        Assert.NotNull(reading);
        Assert.Equal(1, reading!.PlainNextUnit);
        Assert.Equal(2, reading.PlainNextDay);
        Assert.False(reading.IsNumbered);
        Assert.Equal("Unit", reading.UnitWord);
        Assert.Null(workspace.NextClassReading("SPH3U", 1));

        // And it travels: the plain plan carries it in _meta, a card's plan
        // (unit "next") and a refusal carry none.
        var served = new PlantoirTools(workspace);
        var plain = AssistToolAnswer.FromResult("", served.PlanAddNextClass("ICS3U", 1).Meta);
        Assert.Equal(reading, plain.NextClass);
        Assert.Null(AssistToolAnswer.FromResult("", served.PlanAddNextClass("ICS3U", 1, unit: "next").Meta).NextClass);
        Assert.Null(AssistToolAnswer.FromResult("", served.PlanAddNextClass("SPH3U", 1).Meta).NextClass);
    }

    // ---- Helpers ------------------------------------------------------------

    /// <summary>Runs the card on a fixture course of the reading's kind and checks a page was added — never refused.</summary>
    private void AssertTheCardAddsAPage(AssistCardCommand card, string typedBack, AssistNextClassReading reading)
    {
        string folder = reading.IsNumbered
            ? NumberedCourse(reading.UnitWord)
            : UnitCourse(withDates: true, unitWord: reading.UnitWord, latestUnit: reading.PlainNextUnit);
        var tools = new PlantoirTools(new AssistWorkspace(folder, new FakeLauncher()));
        var before = ClassPages(folder);
        card.Arguments.TryGetValue("unit", out string? unit);
        card.Arguments.TryGetValue("days", out string? days);
        var result = tools.AddNextClass("ICS3U", 1, unit ?? "", days is null ? 0 : int.Parse(days));
        var after = ClassPages(folder);
        Assert.True(after.Count > before.Count, $"“{typedBack}” added nothing in this course: {Text(result)}");
        if (reading.IsNumbered) return;
        int expectedUnit = days is null ? reading.PlainNextUnit + 1 : reading.PlainNextUnit;
        foreach (string name in after.Except(before))
        {
            var numbers = AssistNextClassUnits.Words(name).Where(w => w.All(char.IsAsciiDigit)).Select(int.Parse).ToList();
            Assert.True(numbers.FirstOrDefault() == expectedUnit, $"“{typedBack}” made {name}");
        }
    }

    private static string Text(CallToolResult result) =>
        string.Join("\n", result.Content.OfType<TextContentBlock>().Select(block => block.Text));

    /// <summary>A working folder with ICS3U Section 1: "Unit word" pages up to the latest unit, Day 1.</summary>
    private string UnitCourse(bool withDates, string unitWord = "Unit", int latestUnit = 1)
    {
        string folder = Directory.CreateTempSubdirectory("next-class-units").FullName;
        _folders.Add(folder);
        File.WriteAllText(Path.Combine(folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(folder, "deploy.ps1"), "# marker");
        string course = Path.Combine(folder, "courses", "ICS3U");
        string classes = Path.Combine(course, "section1", "All Classes");
        Directory.CreateDirectory(classes);
        File.WriteAllText(Path.Combine(course, "course_config.json"), $$"""
            {
              "course_code": "ICS3U",
              "course_name": "Introduction to Computer Science",
              "section_numbers": [1],
              "num_sections": 1,
              "per_section_folders": ["All Classes"],
              "per_section_files": [],
              "unit_word": "{{unitWord}}"
            }
            """);
        string title = $"{unitWord} {latestUnit}, Day 1";
        File.WriteAllText(Path.Combine(classes, title + ".md"),
                          ClassPlanningContractTests.PageText(title, "2026-09-08"));
        if (withDates) RememberDates(folder);
        return folder;
    }

    /// <summary>A numbered course (#274) whose page word is <paramref name="word"/>, with dates.</summary>
    private string NumberedCourse(string word)
    {
        string folder = Directory.CreateTempSubdirectory("next-class-units").FullName;
        _folders.Add(folder);
        var classes = new JsonArray(new JsonObject { ["title"] = $"{word} 1", ["date"] = "2026-09-08" });
        ClassPlanningContractTests.ScratchCourse(folder, new ClassPageNaming(word, ClassPageScheme.Numbered), classes, Dates);
        return folder;
    }

    private static readonly IReadOnlyList<DateOnly> Dates = new[]
    {
        new DateOnly(2026, 9, 8), new DateOnly(2026, 9, 10), new DateOnly(2026, 9, 14),
        new DateOnly(2026, 9, 16), new DateOnly(2026, 9, 21), new DateOnly(2026, 9, 23),
        new DateOnly(2026, 9, 28), new DateOnly(2026, 9, 30),
    };

    private static void RememberDates(string folder) =>
        TimetableMemory.Write(folder, "ICS3U", 1, Dates.ToList(), "typed in by hand", new DateOnly(2026, 9, 1));

    private static List<string> ClassPages(string folder) =>
        Directory.EnumerateFiles(Path.Combine(folder, "courses", "ICS3U", "section1", "All Classes"), "*.md")
                 .Select(Path.GetFileName).Select(name => name!).OrderBy(name => name, StringComparer.Ordinal).ToList();

    /// <summary>The text between each pair of curly quotes.</summary>
    private static List<string> QuotedSentences(string sentence)
    {
        var found = new List<string>();
        int at = 0;
        while ((at = sentence.IndexOf('“', at)) >= 0)
        {
            int end = sentence.IndexOf('”', at + 1);
            if (end < 0) break;
            found.Add(sentence[(at + 1)..end]);
            at = end + 1;
        }
        return found;
    }

    /// <summary>The reading a row's <c>given</c> describes; null when <c>plainNext</c> is null.</summary>
    private static AssistNextClassReading? ReadingFrom(JsonObject given)
    {
        if (given["plainNext"]?.ToString() is not { } plainNext) return null;
        var numbers = AssistNextClassUnits.Words(plainNext).Where(w => w.All(char.IsAsciiDigit)).Select(int.Parse).ToList();
        Assert.NotEmpty(numbers);
        return new AssistNextClassReading(
            given["unitWord"]!.ToString(),
            given["isNumbered"]!.GetValue<bool>(),
            ClassPageSchemes.NounReading(given["noun"]?.ToString()),
            numbers[0],
            numbers.Count > 1 ? numbers[1] : 0);
    }

    private static string? NumberedWord(JsonObject given) =>
        given["isNumbered"]?.GetValue<bool>() == true ? given["unitWord"]!.ToString() : null;

    private static JsonObject AddNextClassReply(string arguments) => new()
    {
        ["role"] = "assistant",
        ["content"] = "",
        ["tool_calls"] = new JsonArray(new JsonObject
        {
            ["id"] = "call-1",
            ["type"] = "function",
            ["function"] = new JsonObject { ["name"] = "add_next_class", ["arguments"] = arguments },
        }),
    };

    private static JsonArray LocalSchemas() =>
        ContractLoader.LoadJson("assist-cases.json")["toolSchemas"]!["local"]!.DeepClone().AsArray();

    private static List<JsonObject> Rows(string key)
    {
        var family = ContractLoader.LoadJson("assist-cases.json")["nextClassUnits"]!;
        Assert.NotNull(family["note"]);
        return family[key]!.AsArray().Select(row => row!.AsObject()).ToList();
    }
}

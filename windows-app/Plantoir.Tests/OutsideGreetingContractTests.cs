using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// What an outside assistant is told when a Revise door opens
/// (<c>app-rules.json</c> → <c>outsideAgents</c>): the handouts sentence on
/// every door (#895, the mac's #859), the courses kept for reference (#856,
/// on Windows #880's first item), and <c>greetingMustSay</c> read here (#791's
/// Windows half). Every case is walked from the JSON and every sentence named
/// by key; nothing here retypes one. Each door is taken from the contract's
/// <c>agents</c> less those held by name, and a door key this file does not
/// map THROWS, so a third door (#884) inherits these cases by name.
/// </summary>
public sealed class OutsideGreetingContractTests : IDisposable
{
    private const string Server = @"C:\Program Files\Plantoir\plantoir-mcp.exe";
    private const string Config = @"C:\Users\teacher\AppData\Local\Plantoir\assist\mcp-ICS3U.json";
    private const string Folder = @"C:\Users\teacher\Teaching";

    private readonly string _root = Path.Combine(Path.GetTempPath(), "plantoir-outside-greeting-" + Guid.NewGuid().ToString("N"));

    public OutsideGreetingContractTests() => Directory.CreateDirectory(_root);

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private static JsonNode OutsideAgents() => ContractLoader.LoadJson("app-rules.json")["outsideAgents"]!;

    private delegate OutsideDoor.Session Preparer(string code, string name, UnitPlans.Reading? plans,
                                                  string? openingMessage, IReadOnlyList<string>? referenceCourses);

    /// <summary>Every door this app has, by the contract's key; an unknown key throws.</summary>
    private static IReadOnlyList<(string Key, Preparer Prepare, string TrailLine)> Doors()
    {
        var agents = OutsideAgents()["agents"]!.AsArray();
        var held = NamedGapLedger.OutsideDoorsHeld(agents.Select(a => a!["key"]!.ToString()));
        var doors = new List<(string, Preparer, string)>();
        foreach (var agent in agents)
        {
            string key = agent!["key"]!.ToString();
            if (held.Contains(key)) continue;
            Preparer prepare = key switch
            {
                "claude" => (code, name, plans, message, references) =>
                    ClaudeCodeLauncher.Prepare(Config, code, name, plans, message, program: null, referenceCourses: references),
                "codex" => (code, name, plans, message, references) =>
                    CodexLauncher.Prepare(Server, Folder, code, name, plans, message, program: null, referenceCourses: references),
                _ => throw new InvalidOperationException($"a door this file does not map: {key}"),
            };
            doors.Add((key, prepare, agent["trailLine"]!.ToString()));
        }
        Assert.NotEmpty(doors);
        return doors;
    }

    private static IReadOnlyList<string> Strings(JsonNode? array) =>
        array!.AsArray().Select(x => x!.ToString()).ToList();

    // ---- greetingHandoutsCases (#895) ------------------------------------------

    /// <summary>
    /// Each <c>greetingHandoutsCases</c> case through every door's
    /// <c>Prepare</c>: the last argument is <c>text</c> exactly, the same on
    /// every door (<c>greetingIsTheSameForEveryAgent</c>), with no double
    /// quote, and the trail line is the door's own, unchanged by the sentence.
    /// </summary>
    [Fact]
    public void TheHandoutsCasesAreTheGreetingOfEveryDoor()
    {
        Assert.True(OutsideAgents()["greetingIsTheSameForEveryAgent"]!.GetValue<bool>());
        var cases = OutsideAgents()["greetingHandoutsCases"]!["cases"]!.AsArray();
        Assert.True(cases.Count >= 3);
        foreach (var testCase in cases)
        {
            string code = testCase!["course"]!.ToString(), name = testCase["courseName"]!.ToString();
            var plans = testCase["unitPlans"] is null ? null : new UnitPlans.Reading(Array.Empty<UnitPlans.Plan>(), 0);
            Assert.True(plans is null || testCase["unitPlans"]!.AsArray().Count == 0, "a case with plans needs a reading made for it");
            foreach (var (key, prepare, trailLine) in Doors())
            {
                var session = prepare(code, name, plans, null, Strings(testCase["referenceCourses"]));
                Assert.True(testCase["text"]!.ToString() == session.Arguments[^1], $"{key}, {testCase["name"]}: {session.Arguments[^1]}");
                Assert.DoesNotContain("\"", session.Arguments[^1]);
                string trail = trailLine.Replace("{course}", code) + (plans is null ? "" : UnitPlans.TrailClause(plans));
                Assert.Equal(trail, session.TrailText);
            }
        }
    }

    // ---- greetingReferenceCourses (#856) -------------------------------------

    [Fact]
    public void TheReferenceSentenceIsTheContracts()
    {
        var block = OutsideAgents()["greetingReferenceCourses"]!;
        Assert.Equal(block["sentence"]!.ToString(), ReferenceCoursesToMention.SentenceTemplate);
        Assert.Equal(block["separator"]!.ToString(), ReferenceCoursesToMention.Separator);
    }

    /// <summary>
    /// <c>greetingReferenceCourses.cases</c> through every door: no list is
    /// the greeting with none, byte for byte; a list is that greeting, one
    /// space and <c>expectSentence</c>, and nothing else.
    /// </summary>
    [Fact]
    public void TheReferenceCasesAreTheGreetingOfEveryDoor()
    {
        var cases = OutsideAgents()["greetingReferenceCourses"]!["cases"]!.AsArray();
        Assert.True(cases.Count >= 4);
        foreach (var testCase in cases)
        {
            string code = testCase!["course"]!.ToString(), name = testCase["courseName"]!.ToString();
            string? sentence = testCase["expectSentence"]?.ToString();
            foreach (var (key, prepare, trailLine) in Doors())
            {
                string without = prepare(code, name, null, null, null).Arguments[^1];
                var session = prepare(code, name, null, null, Strings(testCase["referenceCourses"]));
                string expected = sentence is null ? without : without + " " + sentence;
                Assert.True(expected == session.Arguments[^1], $"{key}, {testCase["name"]}: {session.Arguments[^1]}");
                Assert.Equal(trailLine.Replace("{course}", code), session.TrailText);
            }
        }
    }

    /// <summary>
    /// An opening message (Fix with…, Plan a Unit…) replaces the greeting, so
    /// the reference sentence never rides along, on any door.
    /// </summary>
    [Fact]
    public void AnOpeningMessageCarriesNoReferenceSentence()
    {
        const string message = "I'm a teacher working on ICS3U in Plantoir. Fix this.";
        foreach (var (key, prepare, _) in Doors())
            Assert.True(message == prepare("ICS3U", "Grade 11", null, message, new[] { "ICS3U-2025 (2025–26)" }).Arguments[^1], key);
    }

    internal static Course CourseOf(JsonNode node, string root)
    {
        var values = new JObject
        {
            ["course_code"] = node["courseCode"]!.ToString(),
            ["kept_for_reference"] = node["keptForReference"]!.GetValue<bool>(),
        };
        if (node["referenceSchoolYear"] is { } year) values["reference_school_year"] = year.GetValue<int>();
        string folder = node["folder"]!.ToString();
        return new Course(folder, Path.Combine(root, "courses", folder), CourseConfiguration.FromDictionary(values));
    }

    /// <summary><c>greetingReferenceCourses.listCases</c>: the list, exactly and in order, from the course and its shelf.</summary>
    [Fact]
    public void TheReferenceListIsMadeAsTheContractSays()
    {
        var cases = OutsideAgents()["greetingReferenceCourses"]!["listCases"]!.AsArray();
        Assert.True(cases.Count >= 10);
        foreach (var testCase in cases)
        {
            var today = DateOnly.ParseExact(testCase!["today"]!.ToString(), "yyyy-MM-dd", CultureInfo.InvariantCulture);
            var course = CourseOf(testCase["course"]!, _root);
            var shelf = testCase["shelf"]!.AsArray().Select(s => CourseOf(s!, _root)).ToList();
            var listed = ReferenceCoursesToMention.For(course, shelf, today);
            Assert.True(Strings(testCase["expect"]).SequenceEqual(listed),
                        $"{testCase["name"]}: {string.Join(" | ", listed)}");
        }
    }

    /// <summary>
    /// The same cases read from DISK through <see cref="ReferenceCoursesToMention.ReadFor"/>,
    /// which each door's <c>Open</c> calls at the click: the course and its
    /// shelf written as <c>course_config.json</c> files.
    /// </summary>
    [Fact]
    public void TheReferenceListIsReadFromTheFolder()
    {
        var cases = OutsideAgents()["greetingReferenceCourses"]!["listCases"]!.AsArray();
        int index = 0;
        foreach (var testCase in cases)
        {
            string workspace = Path.Combine(_root, "w" + index++);
            foreach (var node in new[] { testCase!["course"]! }.Concat(testCase["shelf"]!.AsArray().Select(s => s!)))
            {
                var course = CourseOf(node, workspace);
                Directory.CreateDirectory(course.DirectoryPath);
                var values = new JObject
                {
                    ["course_name"] = "A course", ["sections"] = 1,
                    ["course_code"] = node["courseCode"]!.ToString(),
                    ["kept_for_reference"] = node["keptForReference"]!.GetValue<bool>(),
                };
                if (node["referenceSchoolYear"] is { } year) values["reference_school_year"] = year.GetValue<int>();
                File.WriteAllText(course.ConfigFilePath, values.ToString(), new UTF8Encoding(false));
            }
            var today = DateOnly.ParseExact(testCase["today"]!.ToString(), "yyyy-MM-dd", CultureInfo.InvariantCulture);
            var listed = ReferenceCoursesToMention.ReadFor(workspace, testCase["course"]!["folder"]!.ToString(), today);
            Assert.True(Strings(testCase["expect"]).SequenceEqual(listed), $"{testCase["name"]}: {string.Join(" | ", listed)}");
        }
    }

    /// <summary>A folder that cannot be read drops the sentence and never throws: the door still opens.</summary>
    [Fact]
    public void AFolderThatCannotBeReadNamesNone()
    {
        var today = new DateOnly(2026, 9, 20);
        Assert.Empty(ReferenceCoursesToMention.ReadFor(Path.Combine(_root, "not there"), "ICS3U", today));
        Assert.Empty(ReferenceCoursesToMention.ReadFor("\0 not a path", "ICS3U", today));
    }

    // ---- greetingMustSay, by key and where (#791, #946) -------------------------

    /// <summary>The three variants <c>greetingMustSayHow</c> names.</summary>
    private static readonly (string Name, string Code, string CourseName, string[] References, bool UnitPlansTold)[] Variants =
    {
        ("a name that differs from the code", "MUSTSAY_A", "Grade 11 Computer Science", Array.Empty<string>(), false),
        ("a reference course and no unit plan yet", "MUSTSAY_B", "Grade 11 Computer Science", new[] { "MUSTSAY_B-2025 (2025–26)" }, true),
        ("a name that is the code", "MUSTSAY_C", "MUSTSAY_C", Array.Empty<string>(), false),
    };

    /// <summary>
    /// Each <c>greetingMustSay</c> entry's <c>key</c> and <c>where</c>, checked
    /// as <c>greetingMustSayHow</c> defines each <c>where</c>, over the greeting
    /// each Windows door really passes (its <c>Prepare</c>'s last argument), in
    /// the three variants it names (#946 item 3, the mac's
    /// <c>testEveryDoorsGreetingSaysWhatTheContractSays</c>). A <c>where</c>
    /// this test does not know FAILS. A door the contract lists and Windows
    /// does not have yet (GitHub Copilot) is held open by name in
    /// <see cref="NamedGapLedger"/> until #884, so <see cref="Doors"/> leaves
    /// it out rather than this test failing on the count. The handouts
    /// sentence's "on every door" is checked on Fix with… and Plan a Unit…
    /// too.
    /// </summary>
    [Fact]
    public void EveryDoorsGreetingSaysWhatTheContractSaysWhereItSays()
    {
        var outside = OutsideAgents();
        var entries = outside["greetingMustSay"]!.AsArray();
        Assert.True(entries.Count >= 8, entries.Count.ToString(CultureInfo.InvariantCulture));
        string withName = outside["greetingOpening"]!["withName"]!.ToString();
        string withoutName = outside["greetingOpening"]!["withoutName"]!.ToString();
        string planFirst = outside["greetingPlanFirstSentence"]!.ToString();
        string handouts = outside["greetingHandoutsSentence"]!.ToString();
        string noUnitPlanYet = outside["greetingUnitPlans"]!["none"]!.ToString();
        string referencesTemplate = outside["greetingReferenceCourses"]!["sentence"]!.ToString();
        string referencesSeparator = outside["greetingReferenceCourses"]!["separator"]!.ToString();
        string referencesFirstWords = referencesTemplate.Split("{course}")[0];
        Assert.NotEqual("", referencesFirstWords);

        var doors = Doors();
        int checkedGreetings = 0;
        foreach (var (door, prepare, _) in doors)
        {
            foreach (var variant in Variants)
            {
                string label = door + ", " + variant.Name;
                var plans = variant.UnitPlansTold ? new UnitPlans.Reading(Array.Empty<UnitPlans.Plan>(), 0) : null;
                string greeting = prepare(variant.Code, variant.CourseName, plans, null, variant.References).Arguments[^1];
                checkedGreetings++;
                foreach (var entry in entries)
                {
                    string key = entry!["key"]!.ToString();
                    string where = entry["where"]!.ToString();
                    Assert.True(outside[key] is not null, $"{label}: greetingMustSay names {key}, which the contract does not carry");
                    switch (where)
                    {
                        case "first":
                            string expected = variant.CourseName.Length > 0 && variant.CourseName != variant.Code
                                ? withName.Replace("{courseName}", variant.CourseName)
                                : withoutName;
                            expected = expected.Replace("{course}", variant.Code);
                            Assert.True(greeting.StartsWith(expected + " ", StringComparison.Ordinal), $"{label}: {key}\n{greeting}");
                            break;
                        case "contains":
                            Assert.True(greeting.Contains(outside[key]!.ToString(), StringComparison.Ordinal), $"{label}: {key}\n{greeting}");
                            break;
                        case "afterPlanFirst":
                            Assert.True(greeting.Contains(planFirst + " " + outside[key]!.ToString(), StringComparison.Ordinal), $"{label}: {key}\n{greeting}");
                            break;
                        case "whenReferenceCourses":
                            if (variant.References.Length == 0)
                            {
                                Assert.False(greeting.Contains(referencesFirstWords, StringComparison.Ordinal), $"{label}: {key}\n{greeting}");
                            }
                            else
                            {
                                string sentence = referencesTemplate.Replace("{course}", variant.Code)
                                    .Replace("{courses}", string.Join(referencesSeparator, variant.References));
                                Assert.True(greeting.Contains(sentence, StringComparison.Ordinal), $"{label}: {key}\n{greeting}");
                            }
                            break;
                        case "last":
                            if (variant.UnitPlansTold)
                            {
                                Assert.True(greeting.EndsWith(" " + noUnitPlanYet, StringComparison.Ordinal), $"{label}: {key}\n{greeting}");
                            }
                            else
                            {
                                Assert.False(greeting.Contains(noUnitPlanYet, StringComparison.Ordinal), $"{label}: {key}\n{greeting}");
                                Assert.True(greeting.EndsWith(handouts, StringComparison.Ordinal), $"{label}: {key}\n{greeting}");
                            }
                            break;
                        default:
                            Assert.Fail($"{label}: greetingMustSay has a 'where' this suite does not know: {where}");
                            break;
                    }
                }
            }
        }
        Assert.Equal(doors.Count * Variants.Length, checkedGreetings);
        foreach (string message in FixMessages().Concat(PlanAUnitMessages()))
            Assert.True(message.Contains(handouts, StringComparison.Ordinal), $"no handouts sentence in: {message}");
    }

    // ---- What no greeting may say (#791's ruling, #946) ------------------------

    /// <summary>
    /// Russell's ruling on #791 (2026-11-13, restated from #750): no greeting
    /// mentions marking, class results or report-card comments. The words'
    /// permanent home is <c>app-rules.json</c> → <c>outsideAgents.greetingMustNotSay</c>:
    /// case-insensitive regular expressions, proved first on the contract's
    /// own <c>mustMatch</c> (each caught by some expression) and
    /// <c>mustNotMatch</c> (caught by none), the mac's
    /// <c>testTheGreetingsForbiddenExpressionsCatchTheirCases</c>; then matched
    /// over every message the doors compose. It moved here from
    /// <c>printablePages.agentGuidance.held.words</c> (#946), which
    /// <c>held.whenTheyReturn</c> deletes while the ruling stays.
    /// </summary>
    [Fact]
    public void NoGreetingSaysWhatTheContractForbids()
    {
        var mustNotSay = OutsideAgents()["greetingMustNotSay"]!;
        var expressions = Strings(mustNotSay["expressions"]).Select(p => new Regex(p, RegexOptions.IgnoreCase)).ToList();
        Assert.NotEmpty(expressions);

        string? Says(string text)
        {
            foreach (var expression in expressions)
                if (expression.Match(text) is { Success: true } match) return match.Value;
            return null;
        }

        var mustMatch = Strings(mustNotSay["mustMatch"]);
        var mustNotMatch = Strings(mustNotSay["mustNotMatch"]);
        Assert.NotEmpty(mustMatch);
        Assert.NotEmpty(mustNotMatch);
        foreach (string sentence in mustMatch) Assert.True(Says(sentence) is not null, $"not caught: {sentence}");
        foreach (string sentence in mustNotMatch) Assert.True(Says(sentence) is null, $"caught: '{Says(sentence)}' in {sentence}");

        var every = ReviseGreetings().Concat(VariantGreetings()).Concat(FixMessages()).Concat(PlanAUnitMessages()).Concat(UnitPlanGreetings()).ToList();
        Assert.True(every.Count >= 3 + 4 + 9 + 6 + 18, every.Count.ToString(CultureInfo.InvariantCulture));
        foreach (string text in every)
            Assert.True(Says(text) is null, $"'{Says(text)}' in: {text}");
    }

    private static IReadOnlyList<string> VariantGreetings()
    {
        var greetings = new List<string>();
        foreach (var (_, prepare, _) in Doors())
            foreach (var variant in Variants)
                greetings.Add(prepare(variant.Code, variant.CourseName,
                    variant.UnitPlansTold ? new UnitPlans.Reading(Array.Empty<UnitPlans.Plan>(), 0) : null,
                    null, variant.References).Arguments[^1]);
        return greetings;
    }

    // ---- The messages the cases build -----------------------------------------

    private static IReadOnlyList<string> ReviseGreetings()
    {
        var greetings = new List<string>();
        foreach (var testCase in OutsideAgents()["greetingHandoutsCases"]!["cases"]!.AsArray())
        {
            var plans = testCase!["unitPlans"] is null ? null : new UnitPlans.Reading(Array.Empty<UnitPlans.Plan>(), 0);
            foreach (var (_, prepare, _) in Doors())
                greetings.Add(prepare(testCase["course"]!.ToString(), testCase["courseName"]!.ToString(), plans, null,
                                      Strings(testCase["referenceCourses"])).Arguments[^1]);
        }
        foreach (var testCase in OutsideAgents()["greetingReferenceCourses"]!["cases"]!.AsArray())
            foreach (var (_, prepare, _) in Doors())
                greetings.Add(prepare(testCase!["course"]!.ToString(), testCase["courseName"]!.ToString(), null, null,
                                      Strings(testCase["referenceCourses"])).Arguments[^1]);
        return greetings;
    }

    private static IReadOnlyList<string> FixMessages()
    {
        var messages = new List<string>();
        foreach (var testCase in OutsideAgents()["fixWith"]!["greetingCases"]!.AsArray())
        {
            if (testCase!["expect"] is null) continue;
            var greeting = FixWithAssistant.GreetingFor(FixWithAssistantContractTests.RowsOf(testCase), testCase["course"]!.ToString(),
                testCase["courseName"]!.ToString(), testCase["section"]!.GetValue<int>(), testCase["occasion"]!.ToString());
            messages.Add(greeting!.Text);
        }
        // Every case with rows (one of the ten has none, and no message).
        Assert.True(messages.Count >= 9, messages.Count.ToString(CultureInfo.InvariantCulture));
        return messages;
    }

    private static IReadOnlyList<string> PlanAUnitMessages() =>
        OutsideAgents()["planAUnit"]!["messageCases"]!.AsArray()
            .Select(c => PlanAUnit.OpeningMessage(c!["course"]!.ToString(), c["courseName"]!.ToString())).ToList();

    /// <summary>The 18 <c>greetingUnitPlansCases</c> greetings, each made from its own disk as <c>UnitPlansGreetingTests</c> makes them.</summary>
    private IReadOnlyList<string> UnitPlanGreetings()
    {
        var greetings = new List<string>();
        int index = 0;
        foreach (var testCase in OutsideAgents()["greetingUnitPlansCases"]!["cases"]!.AsArray())
        {
            string code = testCase!["course"]!.ToString();
            string course = Path.Combine(_root, "u" + index++, code);
            Directory.CreateDirectory(course);
            if (testCase["planningFolder"]!.GetValue<bool>())
            {
                string planning = UnitPlans.PlanningFolder(course);
                Directory.CreateDirectory(planning);
                foreach (var plan in testCase["plans"]!.AsArray())
                {
                    string unit = Path.Combine(planning, plan!["folder"]!.ToString());
                    Directory.CreateDirectory(unit);
                    File.WriteAllText(Path.Combine(unit, UnitPlans.PlanFileName), plan["file"]!.ToString(), new UTF8Encoding(false));
                }
            }
            var today = DateOnly.ParseExact(testCase["today"]!.ToString(), "yyyy-MM-dd", CultureInfo.InvariantCulture);
            var reading = UnitPlans.ToMention(course, testCase["referenceCourse"]!.GetValue<bool>(), today);
            foreach (var (_, prepare, _) in Doors())
                greetings.Add(prepare(code, code, reading, null, null).Arguments[^1]);
        }
        return greetings;
    }
}

/// <summary>
/// Each door's REAL <c>Open</c> reads the courses kept for reference from the
/// working folder at the click (#856 on Windows; the mac passes its sidebar's
/// list instead): a stub <c>claude.exe</c> and a stub npm-shaped
/// <c>codex.cmd</c> first on PATH write the argv they were given, and the
/// greeting each door handed over is the contract's
/// <c>greetingHandoutsCases</c> case with a course kept for reference. A
/// Fix with… message is handed over as it is, with no reference sentence.
/// </summary>
/// <remarks>
/// The stub writes its file AFTER <c>Open</c> returns (a .NET Framework
/// console exe takes 1.1–1.5 s, and <c>Open</c> watches 400 ms), so every read
/// POLLS for the file, up to 15 s, and one door is opened, read and its file
/// deleted before the next. Serialized with the trail's other writers: it
/// owns PATH, an environment variable and the trail's path while it runs.
/// </remarks>
[Collection(SharedActivityState.Name)]
public sealed class OutsideGreetingOpenTests : IDisposable
{
    private readonly string _scratch = Directory.CreateTempSubdirectory("plantoir-greeting-open").FullName;
    private readonly string _stubs, _output, _trail, _folder;
    private readonly string? _oldPath, _oldOutput, _oldTrail;

    public OutsideGreetingOpenTests()
    {
        _stubs = Directory.CreateDirectory(Path.Combine(_scratch, "stubs")).FullName;
        _folder = Directory.CreateDirectory(Path.Combine(_scratch, "Teaching")).FullName;
        _output = Path.Combine(_scratch, "argv.txt");
        _trail = Path.Combine(_scratch, "activity.txt");
        File.Copy(StubProgramCollection.ProbeExe, Path.Combine(_stubs, "claude.exe"));
        File.Copy(StubProgramCollection.ProbeExe, Path.Combine(_stubs, "node.exe"));
        File.WriteAllText(Path.Combine(_stubs, "cli.js"), "");
        File.WriteAllText(Path.Combine(_stubs, "codex.cmd"), "@\"%~dp0node.exe\" \"%~dp0cli.js\" %*\r\n@exit\r\n");
        _oldPath = Environment.GetEnvironmentVariable("PATH");
        _oldOutput = Environment.GetEnvironmentVariable(StubProgramCollection.OutputVariable);
        _oldTrail = Plantoir.Core.Scripting.ActivityTrail.CurrentLogPath;
        Environment.SetEnvironmentVariable("PATH", _stubs + Path.PathSeparator + _oldPath);
        Environment.SetEnvironmentVariable(StubProgramCollection.OutputVariable, _output);
        Plantoir.Core.Scripting.ActivityTrail.SetCustomLogPathForTesting(_trail);
    }

    public void Dispose()
    {
        Environment.SetEnvironmentVariable("PATH", _oldPath);
        Environment.SetEnvironmentVariable(StubProgramCollection.OutputVariable, _oldOutput);
        Plantoir.Core.Scripting.ActivityTrail.SetCustomLogPathForTesting(_oldTrail);
        try { Directory.Delete(_scratch, recursive: true); } catch { }
    }

    private void WriteCourse(string folder, string code, bool kept, int? year)
    {
        string directory = Directory.CreateDirectory(Path.Combine(_folder, "courses", folder)).FullName;
        var values = new JObject { ["course_name"] = "A course", ["course_code"] = code, ["sections"] = 1, ["kept_for_reference"] = kept };
        if (year is int y) values["reference_school_year"] = y;
        File.WriteAllText(Path.Combine(directory, "course_config.json"), values.ToString(), new UTF8Encoding(false));
    }

    /// <summary>The last argument the stub was given, polled for up to 15 s; the file is deleted after.</summary>
    private string LastArgumentWritten()
    {
        var waited = System.Diagnostics.Stopwatch.StartNew();
        string[]? lines = null;
        while (waited.Elapsed < TimeSpan.FromSeconds(15))
        {
            try
            {
                if (File.Exists(_output))
                {
                    lines = File.ReadAllLines(_output).Where(l => l.Length > 0).ToArray();
                    if (lines.Length > 1) break;
                }
            }
            catch (IOException) { }
            Thread.Sleep(100);
        }
        Assert.True(lines is { Length: > 1 }, $"the door wrote nothing in {waited.Elapsed.TotalSeconds:F1} s");
        File.Delete(_output);
        return Encoding.UTF8.GetString(Convert.FromBase64String(lines![^1]));
    }

    [Fact]
    public void OpenReadsTheShelfAtTheClick()
    {
        var withOne = ContractLoader.LoadJson("app-rules.json")["outsideAgents"]!["greetingHandoutsCases"]!["cases"]!.AsArray()
            .Single(c => c!["unitPlans"] is null && c["referenceCourses"]!.AsArray().Count == 1)!;
        string code = withOne["course"]!.ToString(), name = withOne["courseName"]!.ToString();
        string entry = withOne["referenceCourses"]![0]!.ToString();
        var today = new DateOnly(2026, 9, 20);
        // The shelf that makes that one entry: the folder before " (", filed under 2025.
        string folder = entry[..entry.IndexOf(" (", StringComparison.Ordinal)];
        Assert.Equal(entry, $"{folder} ({SchoolYear.Label(2025)})");
        WriteCourse(code, code, kept: false, year: null);
        WriteCourse(folder, code, kept: true, year: 2025);
        WriteCourse("MCV4U-2025", "MCV4U", kept: true, year: 2025);

        Assert.True(ClaudeCodeLauncher.Open(_folder, code, name, today: today), "Claude's door did not open");
        Assert.Equal(withOne["text"]!.ToString(), LastArgumentWritten());

        Assert.True(CodexLauncher.Open(_folder, code, name, today: today), "Codex's door did not open");
        Assert.Equal(withOne["text"]!.ToString(), LastArgumentWritten());

        // Fix with…'s message replaces the greeting: no reference sentence.
        const string message = "I'm a teacher working on ICS3U in Plantoir. Fix this.";
        Assert.True(ClaudeCodeLauncher.Open(_folder, code, name, message, today: today), "Claude's door did not open with a message");
        Assert.Equal(message, LastArgumentWritten());

        string trail = File.ReadAllText(_trail);
        foreach (var agent in ContractLoader.LoadJson("app-rules.json")["outsideAgents"]!["agents"]!.AsArray()
                     .Where(a => a!["key"]!.ToString() is "claude" or "codex"))
            Assert.Contains(agent!["trailLine"]!.ToString().Replace("{course}", code), trail);
    }
}
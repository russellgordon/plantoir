using System.Text.Json.Nodes;
using ModelContextProtocol;
using ModelContextProtocol.Protocol;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Plantoir.Mcp;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// <c>shared-rules.json</c> → <c>assistantReadsSettingsAtTheCall</c> (#344 /
/// mac #322): every assistant tool call, on either surface, reads the course
/// list and each <c>course_config.json</c> at the moment of the call. The
/// harness opens the assistant FIRST and only then changes the files on disk.
/// </summary>
/// <remarks>
/// Windows has no long-lived copy on the server side —
/// <c>AssistWorkspace.Courses()</c> rediscovers on every lookup, and must stay
/// uncached — so the case most at risk was the WINDOW's approval card, which
/// read the window's own snapshot. It now reads through
/// <see cref="DeployCommand.EveryDestinationByTypeAtTheCall"/>.
/// </remarks>
[Collection(SharedActivityState.Name)]
public class AssistantReadsSettingsAtTheCallTests : IDisposable
{
    private readonly string _root = Directory.CreateTempSubdirectory("plantoir-at-the-call").FullName;
    private readonly string _folder;
    private readonly string _savedFolder;
    private readonly FakeScheduler _scheduler;

    private static readonly HashSet<string> ExpectKeys = new(StringComparer.Ordinal)
    {
        "outcome", "destination", "refusal", "destinationNamed", "cardNames", "cardDoesNotName",
        "schedulable", "deployedTo", "found", "lists",
    };

    public AssistantReadsSettingsAtTheCallTests()
    {
        _folder = Path.Combine(_root, "work");
        _savedFolder = Path.Combine(_root, "site");
        Directory.CreateDirectory(_folder);
        Directory.CreateDirectory(_savedFolder);
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        _scheduler = new FakeScheduler(Path.Combine(_root, "scheduled"));
    }

    public void Dispose()
    {
        _scheduler.Dispose();
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    public static IEnumerable<object[]> Cases() =>
        ContractLoader.LoadJson("shared-rules.json")!["assistantReadsSettingsAtTheCall"]!["cases"]!.AsArray()
            .Select(c => new object[] { c!["name"]!.ToString() });

    [Theory]
    [MemberData(nameof(Cases))]
    public async Task Case_MatchesContract(string name)
    {
        var c = ContractLoader.LoadJson("shared-rules.json")!["assistantReadsSettingsAtTheCall"]!["cases"]!
            .AsArray().First(x => x!["name"]!.ToString() == name)!;
        var expect = c["expect"]!.AsObject();
        var unknown = expect.Select(pair => pair.Key).Where(key => !ExpectKeys.Contains(key)).ToList();
        Assert.True(unknown.Count == 0, $"Unknown expect keys (a misspelt one would pass vacuously): {string.Join(", ", unknown)}");

        // Opened: the assistant is started on what is on disk NOW.
        var opened = c["opened"]!;
        WriteCourse("ICS3U", new[] { 1 }, opened["target"]?.ToString(), "");
        if (opened["hasDeployedBefore"]?.GetValue<bool>() == true)
            MarkDeployed("ICS3U", ".netlify_sites");
        var launcher = new FakeLauncher();
        var tools = new PlantoirTools(new AssistWorkspace(_folder, launcher));
        var openedConfiguration = Workspace.DiscoverCourses(_folder).Single().Configuration;
        var agent = new AssistAgent(new ScriptModel(), new CannedTools(), new JsonArray(), "ICS3U", 1)
        {
            DestinationProvider = () =>
                DeployCommand.EveryDestinationByTypeAtTheCall(_folder, "ICS3U", openedConfiguration),
        };

        // Then saved, as Course Settings in another window would.
        if (c["thenSaved"] is JsonObject saved)
        {
            int[] sections = saved["sections"] is JsonArray list
                ? list.Select(n => n!.GetValue<int>()).ToArray()
                : new[] { 1 };
            string? target = saved["target"]?.ToString() ?? opened["target"]?.ToString();
            WriteCourse("ICS3U", sections, target, target == "local_folder" ? _savedFolder : "");
        }
        if (c["thenCreated"] is JsonObject created)
            WriteCourse(created["code"]!.ToString(), new[] { 1 }, null, "");

        var call = c["call"]!;
        var arguments = call["arguments"]!.AsObject();
        string tool = call["tool"]!.ToString();
        int checkedSomething = 0;

        string Text(CallToolResult result) => result.Summary() + "\n" + result.Detail();

        switch (tool)
        {
            case "schedule_deploy" when expect.ContainsKey("cardNames") || expect.ContainsKey("cardDoesNotName"):
            {
                var lines = agent.AskFirst("deploy at 6:30", "schedule_deploy", (JsonObject)arguments.DeepClone());
                string card = lines[0].Text;
                if (expect["cardNames"] is { } names) { Assert.Contains(names.ToString(), card); checkedSomething++; }
                if (expect["cardDoesNotName"] is { } not) { Assert.DoesNotContain(not.ToString(), card); checkedSomething++; }
                break;
            }
            case "schedule_deploy":
            {
                string said = Text(tools.ScheduleDeploy("ICS3U", 1, arguments["when"]!.ToString()));
                if (expect["outcome"]?.ToString() == "scheduled")
                {
                    Assert.StartsWith("Scheduled:", said);
                    checkedSomething++;
                    if (expect["destination"] is { } where)
                    {
                        string described = DeployCommand.DestinationDescription(
                            new CourseConfiguration.DeployDestination("local_folder", _savedFolder));
                        Assert.Equal("{savedFolder}", where.ToString());
                        Assert.Contains(described, said);
                        checkedSomething++;
                    }
                }
                else if (expect["outcome"]?.ToString() == "refused")
                {
                    string rendered = ContractLoader.LoadJson("shared-rules.json")!
                        ["scheduledDeployRefusals"]!["wording"]![expect["refusal"]!.ToString()]!.ToString()
                        .Replace("{course}", "ICS3U").Replace("{section}", "1")
                        .Replace("{destination}", expect["destinationNamed"]!.ToString());
                    Assert.Equal("Nothing was scheduled. " + rendered, tools.ScheduleDeploy("ICS3U", 1, arguments["when"]!.ToString()).Summary());
                    checkedSomething++;
                }
                break;
            }
            case "plan_scheduled_deploy":
            {
                var result = tools.PlanScheduledDeploy("ICS3U", 1, arguments["when"]!.ToString());
                bool isPlan = result.Meta?[AssistToolAnswer.IsPlanKey]?.GetValue<bool>() == true;
                string said = Text(result);
                bool schedulable = isPlan && !said.Contains("can't be scheduled", StringComparison.OrdinalIgnoreCase) &&
                                   !said.Contains("has never been deployed", StringComparison.Ordinal);
                Assert.Equal(expect["schedulable"]!.GetValue<bool>(), schedulable);
                checkedSomething++;
                break;
            }
            case "deploy_section":
            {
                await tools.DeploySection("ICS3U", 1, new Progress<ProgressNotificationValue>(_ => { }), default);
                var deploys = launcher.Runs.Where(run => run.Launcher == "deploy").ToList();
                var types = deploys.Select(run => run.Arguments.Contains("--to-folder") ? "local_folder" : "netlify").ToList();
                Assert.Equal(expect["deployedTo"]!.AsArray().Select(t => t!.ToString()), types);
                checkedSomething++;
                break;
            }
            case "check_section":
            {
                string said = tools.CheckSection("ICS3U", arguments["section"]!.GetValue<int>());
                if (expect["found"]?.GetValue<bool>() == true) { Assert.Contains("ICS3U Section 2", said); checkedSomething++; }
                break;
            }
            case "list_courses":
            {
                string said = tools.ListCourses();
                foreach (var code in expect["lists"]!.AsArray()) { Assert.Contains(code!.ToString(), said); checkedSomething++; }
                break;
            }
            default:
                Assert.Fail("No runner for " + tool);
                break;
        }

        Assert.True(checkedSomething > 0, $"“{name}” checked nothing.");
    }

    // ---- The fixture ------------------------------------------------------

    private void WriteCourse(string code, int[] sections, string? target, string folderPath)
    {
        string directory = Path.Combine(_folder, "courses", code);
        Directory.CreateDirectory(directory);
        string targetLine = target is null ? "" : $"\"deploy_target\": \"{target}\",";
        File.WriteAllText(Path.Combine(directory, "course_config.json"),
            $$"""
            {
              "course_code": "{{code}}",
              "course_name": "A course",
              {{targetLine}}
              "deploy_folder_path": "{{folderPath.Replace("\\", "\\\\")}}",
              "num_sections": {{sections.Length}},
              "per_section_folders": ["All Classes"],
              "per_section_files": [],
              "section_numbers": [{{string.Join(", ", sections)}}]
            }
            """);
        foreach (int section in sections)
        {
            string page = Path.Combine(directory, $"section{section}", "All Classes", "Unit 1, Day 1.md");
            Directory.CreateDirectory(Path.GetDirectoryName(page)!);
            if (!File.Exists(page))
                File.WriteAllText(page, "---\npublish: true\ncreated: 2026-09-08T07:00:00.000-0400\n---\nBody.\n");
        }
    }

    private void MarkDeployed(string code, string markerFolder)
    {
        string directory = Path.Combine(_folder, "courses", code, markerFolder);
        Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory, "section1.json"), "{}");
    }
}

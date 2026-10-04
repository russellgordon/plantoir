using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;
using ModelContextProtocol;
using Plantoir.Core.Assist;
using Plantoir.Core.Scripting;
using Plantoir.Mcp;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #436 (mac #433): an OUTSIDE assistant is held back only while a site of the
/// course is being BUILT. Runs <c>shared-rules.json → workLeases.declining.
/// outsideChanges.cases</c> case for case (the mac's counterpart is
/// <c>OutsideAssistantWhilePreviewingTests</c>), through the server's door
/// (<see cref="OutsideChangeGate"/>, as Program.cs's filter asks it) and then
/// the real <see cref="PlantoirTools"/> — never retyped here.
/// </summary>
[Collection(SharedActivityState.Name)]
public class OutsideAssistantWhilePreviewingTests : IDisposable
{
    private const string Course = "ICS3U";
    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-outside").FullName;
    private readonly string _trail = Path.Combine(Path.GetTempPath(), "plantoir-outside-" + Guid.NewGuid().ToString("N") + ".txt");
    private readonly FakeLauncher _launcher = new();
    private Process? _other;

    public OutsideAssistantWhilePreviewingTests()
    {
        ActivityTrail.SetCustomLogPathForTesting(_trail);
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        string course = CourseDir;
        Directory.CreateDirectory(course);
        File.WriteAllText(Path.Combine(course, "course_config.json"), """
            { "course_code": "ICS3U", "course_name": "A course", "deploy_target": "netlify",
              "num_sections": 1, "per_section_folders": ["All Classes"], "per_section_files": [],
              "section_numbers": [1] }
            """);
        // Deployed before, so a deploy asks no question of its own.
        Directory.CreateDirectory(Path.Combine(course, ".netlify_sites"));
        File.WriteAllText(Path.Combine(course, ".netlify_sites", "section1.json"), """{"name": "ics3u-s1"}""");
        Directory.CreateDirectory(Path.GetDirectoryName(PagePath)!);
        File.WriteAllText(PagePath, "---\npublish: false\ncreated: 2026-09-08T07:00:00.000-0400\n---\nBody.\n");
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { _other?.Kill(entireProcessTree: true); } catch { }
        _other?.Dispose();
        try { Directory.Delete(_folder, recursive: true); } catch { }
        try { File.Delete(_trail); } catch { }
        GC.SuppressFinalize(this);
    }

    private string CourseDir => Path.Combine(_folder, "courses", Course);
    private string PagePath => Path.Combine(CourseDir, "section1", "All Classes", "Unit 1, Day 1.md");

    private static JsonObject Rules => ContractLoader.LoadJson("shared-rules.json")["workLeases"]!["declining"]!["outsideChanges"]!.AsObject();

    private static readonly Lazy<JsonObject> Wording = new(() =>
        ContractLoader.LoadJson("assist-wording.json")["wording"]!.AsObject());

    public static IEnumerable<object[]> Cases() =>
        Rules["cases"]!.AsArray().Select(c => new object[] { c!["name"]!.ToString(), c.ToJsonString() });

    [Fact]
    public void TheContractStillHasItsTenCases() => Assert.True(Rules["cases"]!.AsArray().Count >= 10);

    [Theory]
    [MemberData(nameof(Cases))]
    public async Task EachCaseIsTheContracts(string name, string json)
    {
        var c = JsonNode.Parse(json)!.AsObject();
        var expect = c["expect"]!.AsObject();
        foreach (var kind in c["others"]!.AsArray()) OtherProgramHolds(kind!.ToString());

        var workspace = new AssistWorkspace(_folder, _launcher);   // an outside assistant: no PLANTOIR_LOCAL_WINDOW
        var tools = new PlantoirTools(workspace);
        var progress = new Progress<ProgressNotificationValue>(_ => { });
        var before = Snapshot();

        string said = c["asked"]!.ToString() switch
        {
            // The DETAIL: what an MCP client (the outside assistant) is sent.
            // The one-line summary is the in-app window's.
            "change" => OutsideChangeGate.Refusal("publish_pages", Arguments(), workspace)
                        ?? (await tools.PublishPages(Course, 1, progress, default, new[] { "Unit 1, Day 1" })).Detail(),
            "rebuild" => OutsideChangeGate.Refusal("rebuild_preview", Arguments(), workspace)
                         ?? await tools.RebuildPreview(Course, 1, progress, default),
            "deploy" => OutsideChangeGate.Refusal("deploy_section", Arguments(), workspace)
                        ?? await tools.DeploySection(Course, 1, progress, default),
            var other => throw new InvalidOperationException($"{name}: a case asking for {other}"),
        };

        bool written = File.ReadAllText(PagePath).Contains("publish: true", StringComparison.Ordinal);
        bool deployed = _launcher.Runs.Any(run => run.Launcher == "deploy");
        bool built = !deployed && _launcher.Runs.Any(run => run.Launcher == "preview" && run.Arguments.Contains("--build-only"));
        Assert.True(expect["written"]!.GetValue<bool>() == written, $"{name}: written was {written}. It said: {said}");
        Assert.True(expect["built"]!.GetValue<bool>() == built, $"{name}: built was {built}. It said: {said}");
        Assert.True(expect["deployed"]!.GetValue<bool>() == deployed, $"{name}: deployed was {deployed}. It said: {said}");
        if (expect["said"] is JsonValue key)
            Assert.True(said.EndsWith(Sentence(key.ToString()), StringComparison.Ordinal),
                $"{name}: the answer does not end with {key}: {said}");
        if (!written && !expect["written"]!.GetValue<bool>() && c["asked"]!.ToString() == "change")
            Assert.Equal(before, Snapshot());   // byte for byte, nothing written

        string trail = File.Exists(_trail) ? File.ReadAllText(_trail) : "";
        // The trail's sentences (its event names are not written into the file).
        if (expect["said"]?.ToString() is "courseIsBeingBuilt")
            Assert.Matches("held back|declined", trail);
        if (expect["said"]?.ToString() is "changesAreSavedPreviewShowsTheOldPages" or "deployClosedAnOpenPreview")
            Assert.Contains($"a preview of {Course} was open in Plantoir", trail);
        else
            Assert.DoesNotContain($"a preview of {Course} was open in Plantoir", trail);
    }

    /// <summary>
    /// The trap #433 names: a preview still BUILDING holds build beside
    /// preview, and build must win whatever order the leases were read in.
    /// </summary>
    [Fact]
    public void ABuildWinsWhateverOrderTheLeasesAreReadIn()
    {
        Assert.Equal(WorkLease.OutsideMeeting.ABuild, WorkLease.OutsideMeets(new[] { "preview", "build" }));
        Assert.Equal(WorkLease.OutsideMeeting.ABuild, WorkLease.OutsideMeets(new[] { "build", "preview" }));
        Assert.Equal(WorkLease.OutsideMeeting.ABuild, WorkLease.OutsideMeets(new[] { "publish", "preview" }));
        Assert.Equal(WorkLease.OutsideMeeting.AServedPreview, WorkLease.OutsideMeets(new[] { "preview", "assist" }));
        Assert.Equal(WorkLease.OutsideMeeting.Nothing, WorkLease.OutsideMeets(new[] { "assist", "import" }));
    }

    /// <summary>
    /// The writing tools the door holds back are every non-read-only tool but
    /// the contract's six — so a NEW write tool is held back by default.
    /// </summary>
    [Fact]
    public void EveryWritingToolButTheContractsSixIsHeldBack()
    {
        string rule = Rules["rule"]!.ToString();
        foreach (string exempt in OutsideChangeGate.NotAChange) Assert.Contains(exempt, rule);
        var gated = OutsideChangeGate.Gated();
        Assert.Contains("publish_pages", gated);
        Assert.Contains("unpublish_pages", gated);
        Assert.Contains("undo_last_change", gated);
        Assert.Contains("add_next_class", gated);
        Assert.DoesNotContain("plan_publish_pages", gated);
        Assert.DoesNotContain("list_pages", gated);
        foreach (string exempt in OutsideChangeGate.NotAChange) Assert.DoesNotContain(exempt, gated);
    }

    /// <summary>
    /// Plantoir's OWN window keeps #289's rule (director's ruling, as the mac's
    /// in-app assistant keeps #156's): the door lets it through, its rebuild
    /// is declined by a preview, and the note after a write says busy.
    /// </summary>
    [Fact]
    public async Task TheInAppWindowKeepsTheOldRule()
    {
        OtherProgramHolds("preview");
        var workspace = new AssistWorkspace(_folder, _launcher) { ServesTheLocalWindow = true };
        var tools = new PlantoirTools(workspace);
        var progress = new Progress<ProgressNotificationValue>(_ => { });

        Assert.Null(OutsideChangeGate.Refusal("publish_pages", Arguments(), workspace));
        Assert.Equal(AssistWording.CourseIsBusy(Course), await tools.RebuildPreview(Course, 1, progress, default));
        OtherProgramHolds("build");
        Assert.Null(OutsideChangeGate.Refusal("unpublish_pages", Arguments(), workspace));
        Assert.Empty(_launcher.Runs);
    }

    // ---- The world ---------------------------------------------------------

    private static Dictionary<string, JsonElement> Arguments() => new()
    {
        ["course"] = JsonSerializer.SerializeToElement(Course),
        ["section"] = JsonSerializer.SerializeToElement(1),
    };

    private static string Sentence(string key) =>
        Wording.Value[key]!.ToString().Replace("{course}", Course).Replace("{section}", "1");

    /// <summary>A lease of this kind, held by a real, live other process.</summary>
    private void OtherProgramHolds(string kind)
    {
        _other ??= Process.Start(new ProcessStartInfo("cmd.exe", "/c pause")
        {
            CreateNoWindow = true, UseShellExecute = false, RedirectStandardInput = true,
        })!;
        string directory = Path.Combine(_folder, "courses", ".internal", "activity");
        Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory, $"{Course}.{kind}.{_other.Id}.lease"),
            $"{_other.Id}\n{_other.ProcessName}\n2026-08-13T00:00:00Z\n");
    }

    private Dictionary<string, string> Snapshot() =>
        Directory.EnumerateFiles(CourseDir, "*", SearchOption.AllDirectories)
            .ToDictionary(path => path, File.ReadAllText);
}

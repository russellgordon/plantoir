using System.Text.Json.Nodes;
using Plantoir.Core;
using Plantoir.Core.Assist;
using Plantoir.Core.Catalogs;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

public class ContractTests
{
    [Fact]
    public void AssistWording_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("assist-wording.json");
        var wording = doc["wording"]!.AsObject();

        Assert.Equal(wording["deployApproval"]!.ToString(), AssistWording.DeployApproval);
        Assert.Equal(wording["deployQuestion"]!.ToString(), AssistWording.DeployQuestion);
        Assert.Equal(wording["planQuestion"]!.ToString(), AssistWording.PlanQuestion);
        Assert.Equal(wording["deployAccepted"]!.ToString(), AssistWording.DeployAccepted);
        Assert.Equal(wording["planAccepted"]!.ToString(), AssistWording.PlanAccepted);
        Assert.Equal(wording["cancelled"]!.ToString(), AssistWording.Cancelled);
        Assert.Equal(wording["deployWasCancelled"]!.ToString(), AssistWording.DeployWasCancelled);
        Assert.Equal(wording["planWasCancelled"]!.ToString(), AssistWording.PlanWasCancelled);

        Assert.Equal(wording["deployed"]!.ToString(), AssistWording.Deployed("{course}", "{section}"));
        Assert.Equal(wording["couldNotBuildBeforeDeploying"]!.ToString(), AssistWording.CouldNotBuildBeforeDeploying("{course}", "{section}"));
        Assert.Equal(wording["deployDidNotFinish"]!.ToString(), AssistWording.DeployDidNotFinish("{course}", "{section}"));
        Assert.Equal(wording["sectionIsBusy"]!.ToString(), AssistWording.SectionIsBusy("{course}", "{section}"));
        Assert.Equal(wording["courseIsBusy"]!.ToString(), AssistWording.CourseIsBusy("{course}"));

        Assert.Equal(wording["previewIsRebuilding"]!.ToString(), AssistWording.PreviewIsRebuilding("{course}", "{section}"));
        Assert.Equal(wording["builtWithNoWindowOpen"]!.ToString(), AssistWording.BuiltWithNoWindowOpen("{course}", "{section}"));
        Assert.Equal(wording["rebuiltForACallerWithNoWindow"]!.ToString(), AssistWording.RebuiltForACallerWithNoWindow("{course}", "{section}"));
        Assert.Equal(wording["previewDidNotBuild"]!.ToString(), AssistWording.PreviewDidNotBuild("{course}", "{section}"));

        Assert.Equal(wording["undid"]!.ToString(), AssistWording.Undid("{change}"));
        Assert.Equal(wording["undidPartly"]!.ToString(), AssistWording.UndidPartly("{change}", 2));
        Assert.Equal(wording["couldNotUndo"]!.ToString(), AssistWording.CouldNotUndo("{change}", 2));

        Assert.Equal(wording["undoIsStillAvailable"]!.ToString(), AssistWording.UndoIsStillAvailable);
        Assert.Equal(wording["nothingToUndo"]!.ToString(), AssistWording.NothingToUndo);
        Assert.Equal(wording["aCreatedPageCanBeTakenBack"]!.ToString(), AssistWording.ACreatedPageCanBeTakenBack);
        Assert.Equal(wording["undoDoesNotReachTheLiveSite"]!.ToString(), AssistWording.UndoDoesNotReachTheLiveSite);
        Assert.Equal(wording["whereTheOutputIs"]!.ToString(), AssistWording.WhereTheOutputIs);
        Assert.Equal(wording["nothingToDo"]!.ToString(), AssistWording.NothingToDo);
    }

    [Fact]
    public void FileFormats_PageVisibilityReadingCases()
    {
        var doc = ContractLoader.LoadJson("file-formats.json");
        var cases = doc["pageVisibility"]!["readingCases"]!.AsArray();

        foreach (var c in cases)
        {
            string pageText = c!["page"]!.ToString();
            bool expectedVisible = c["expectVisible"]!.GetValue<bool>();
            int section = c["section"]?.GetValue<int>() ?? 1;

            string fullFrontmatter = $"---\n{pageText}\n---\n# Content";

            bool actualVisible = !PageFrontmatter.IsDraft(fullFrontmatter, section);

            Assert.True(actualVisible == expectedVisible,
                $"Case '{pageText}' (section {section}) expected visible={expectedVisible} but got {actualVisible}");
        }
    }

    [Fact]
    public void CourseManagement_GradeLabels_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("course-management.json");
        var cases = doc["gradeLabels"]!["cases"]!.AsArray();

        foreach (var c in cases)
        {
            if (c is null) continue;
            string code = c["code"]!.ToString();
            string expectedLabel = c["expect"]!.ToString();
            string actual = SectionAdder.GradeLabel(code);
            Assert.Equal(expectedLabel, actual);
        }
    }

    [Fact]
    public void CourseManagement_CourseCode_Normalized_And_Problems_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("course-management.json");
        var normalizedCases = doc["courseCode"]!["normalized"]!.AsArray();

        foreach (var c in normalizedCases)
        {
            string typed = c!["typed"]!.ToString();
            string expected = c["expect"]!.ToString();
            Assert.Equal(expected, CourseCodeValidator.Normalize(typed));
        }

        var problemCases = doc["courseCode"]!["problems"]!.AsArray();
        foreach (var c in problemCases)
        {
            string typed = c!["typed"]!.ToString();
            var existing = c["existing"]!.AsArray().Select(e => e!.ToString()).ToList();
            string? currentCode = c["currentCode"]?.ToString();
            string? expectProblem = c["expectProblem"]?.ToString();
            string? expectShort = c["expectShort"]?.ToString();

            var (problem, shortProblem) = CourseCodeValidator.Validate(typed, existing, currentCode);
            Assert.Equal(expectProblem, problem);
            Assert.Equal(expectShort, shortProblem);
        }
    }

    [Fact]
    public void CourseManagement_DefaultCourseName_MatchesContract()
    {
        string supportFile = ContractLoader.GetSupportPath("ontario_secondary_courses.json");
        var catalog = CourseNameCatalog.Load(supportFile);

        var doc = ContractLoader.LoadJson("course-management.json");
        var cases = doc["defaultCourseName"]!["cases"]!.AsArray();

        foreach (var c in cases)
        {
            string code = c!["code"]!.ToString();
            string? expect = c["expect"]?.ToString();
            string? actual = catalog.DefaultName(code);
            Assert.Equal(expect, actual);
        }
    }

    [Fact]
    public void SharedRules_ActivityTrailEvents_Exist()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var events = doc["activityTrail"]!["mustRecord"]!.AsArray();

        var contractKeys = events.Select(e => e!["event"]!.ToString()).ToHashSet();

        var codeKeys = Enum.GetValues<ActivityTrail.Event>()
            .Select(ActivityTrail.KeyFor)
            .ToHashSet();

        Assert.Equal(contractKeys, codeKeys);
    }

    [Fact]
    public void AppRules_PreviewPorts_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("app-rules.json");
        var previewPorts = doc["previewPorts"]!;
        int wsOffset = previewPorts["websocketOffset"]!.GetValue<int>();
        Assert.Equal(1000, wsOffset);
    }

    [Fact]
    public void SharedRules_WorkingFolderPathBar_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var bar = doc["workingFolderPathBar"]!;
        var actions = bar["actions"]!.AsArray();

        var revealAction = actions.FirstOrDefault(a => a?["action"]?.ToString() == "reveal");
        Assert.NotNull(revealAction);
        Assert.Equal("Show in File Explorer", revealAction["windowsLabel"]?.ToString());

        var openAction = actions.FirstOrDefault(a => a?["action"]?.ToString() == "open");
        Assert.NotNull(openAction);
        Assert.Equal("Open Folder", openAction["windowsLabel"]?.ToString());

        // Ancestor paths on Windows
        string path = @"C:\Users\teacher\Desktop\Courses";
        var crumbs = FolderCrumb.AncestorPaths(path);
        var expected = new[]
        {
            @"C:\",
            @"C:\Users",
            @"C:\Users\teacher",
            @"C:\Users\teacher\Desktop",
            @"C:\Users\teacher\Desktop\Courses",
        };
        Assert.Equal(expected, crumbs);
    }

    [Fact]
    public void AppRules_CredentialPrompts_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("app-rules.json");
        var cases = doc["credentialPrompts"]!["cases"]!.AsArray();

        foreach (var c in cases)
        {
            if (c is null) continue;
            string prompt = c["prompt"]!.ToString();
            string expectRequest = c["expectRequest"]!.ToString();

            var match = CredentialRequests.MatchPrompt(prompt);
            string actualName = match?.Name ?? "";
            Assert.Equal(expectRequest, actualName);
        }
    }

    [Fact]
    public void AppRules_CredentialRequests_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("app-rules.json");
        var requests = doc["credentialRequests"]!["requests"]!.AsArray();

        var codeRequests = new Dictionary<string, CredentialRequest>
        {
            ["netlifyToken"] = CredentialRequests.NetlifyToken,
            ["cloudflareToken"] = CredentialRequests.CloudflareToken,
            ["cloudflareAccountID"] = CredentialRequests.CloudflareAccountID,
            ["cloudflareAccountIDHelp"] = CredentialRequests.CloudflareAccountIDHelp,
            ["teacherSurname"] = CredentialRequests.TeacherSurname,
            ["siteName"] = CredentialRequests.SiteName,
            ["siteNameConflict"] = CredentialRequests.SiteNameConflict,
        };

        foreach (var req in requests)
        {
            if (req is null) continue;
            string name = req["name"]!.ToString();
            Assert.True(codeRequests.TryGetValue(name, out var codeReq), $"Missing request definition for {name}");

            Assert.Equal(req["title"]!.ToString(), codeReq!.Title);
            Assert.Equal(req["fieldLabel"]!.ToString(), codeReq.FieldLabel);
            Assert.Equal(req["isSecret"]!.GetValue<bool>(), codeReq.IsSecret);
            Assert.Equal(req["linkAddress"]!.ToString(), codeReq.LinkAddress);
            Assert.Equal(req["linkTitle"]!.ToString(), codeReq.LinkTitle);

            var expectSteps = req["steps"]!.AsArray().Select(s => s!.ToString()).ToList();
            Assert.Equal(expectSteps, codeReq.Steps);
        }
    }

    [Fact]
    public void SharedRules_CurriculumRules_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var rules = doc["curriculumRules"]!;

        // expectationWording
        var wordingCases = rules["expectationWording"]!["cases"]!.AsArray();
        foreach (var c in wordingCases)
        {
            if (c is null) continue;
            string body = c["body"]!.ToString();
            string expect = c["expect"]!.ToString();
            string actual = CurriculumRules.ExpectationWording(body);
            Assert.Equal(expect, actual);
        }

        // isCurriculumPage
        var pageCases = rules["isCurriculumPage"]!["cases"]!.AsArray();
        foreach (var c in pageCases)
        {
            if (c is null) continue;
            string path = c["path"]!.ToString();
            bool expect = c["expect"]!.GetValue<bool>();
            bool actual = CurriculumRules.IsCurriculumPage(path);
            Assert.Equal(expect, actual);
        }

        // isExpectationCode
        var codeCases = rules["isExpectationCode"]!["cases"]!.AsArray();
        foreach (var c in codeCases)
        {
            if (c is null) continue;
            string code = c["code"]!.ToString();
            bool expect = c["expect"]!.GetValue<bool>();
            bool actual = CurriculumRules.IsExpectationCode(code);
            Assert.Equal(expect, actual);
        }
    }

    [Fact]
    public void SharedRules_AssistantModelChoice_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var modelChoice = doc["assistantModelChoice"]!;

        Assert.Equal("automatic", modelChoice["defaultChoice"]!.ToString());

        var choices = modelChoice["choices"]!.AsArray();
        var choiceKeys = choices.Select(c => c!["key"]!.ToString()).ToList();
        Assert.Equal(new[] { "automatic", "smaller", "larger" }, choiceKeys);

        foreach (var c in choices)
        {
            string key = c!["key"]!.ToString();
            string expectLabel = c["label"]!.ToString();
            Assert.Equal(expectLabel, AssistModelChoice.Label(key));
        }

        // Automatic choice resolves at point of use based on budget
        var budget8Gb = new AssistHardwareBudget(8L * 1024 * 1024 * 1024);
        var budget16Gb = new AssistHardwareBudget(16L * 1024 * 1024 * 1024);

        Assert.Equal(AssistModelTier.Small, AssistModelChoice.Resolved(AssistModelChoice.Automatic, budget8Gb));
        Assert.Equal(AssistModelTier.Large, AssistModelChoice.Resolved(AssistModelChoice.Automatic, budget16Gb));

        // Automatic never produces a caution
        Assert.Null(AssistModelChoice.Caution(AssistModelChoice.Automatic, budget8Gb));
        Assert.Null(AssistModelChoice.Caution(AssistModelChoice.Automatic, budget16Gb));

        // Hand-picked larger choice on 8 GB machine produces caution naming memory numbers
        string? caution = AssistModelChoice.Caution(AssistModelChoice.Larger, budget8Gb);
        Assert.NotNull(caution);
        Assert.Contains("8 GB", caution);
        Assert.Contains(AssistModelTier.Large.DisplayName(), caution);
        Assert.Contains(AssistModelTier.Large.MemoryDescription(), caution);
    }

    [Fact]
    public void SharedRules_AssistantModelChoice_NamesNoModel()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var jargonList = doc["assistantModelChoice"]!["namesNoModel"]!["jargon"]!
            .AsArray()
            .Select(j => j!.ToString().ToLowerInvariant())
            .ToList();

        var budget = new AssistHardwareBudget(8L * 1024 * 1024 * 1024);

        var allStrings = new List<string>
        {
            AssistModelTier.Small.DisplayName(),
            AssistModelTier.Large.DisplayName(),
            AssistModelTier.Small.ChoiceLabel(),
            AssistModelTier.Large.ChoiceLabel(),
            AssistModelTier.Small.SizeGuidance(),
            AssistModelTier.Large.SizeGuidance(),
            AssistModelChoice.Label(AssistModelChoice.Automatic),
            AssistModelChoice.Detail(AssistModelChoice.Automatic, budget),
            AssistModelChoice.Detail(AssistModelChoice.Smaller, budget),
            AssistModelChoice.Detail(AssistModelChoice.Larger, budget),
            AssistModelChoice.Caution(AssistModelChoice.Larger, budget) ?? "",
        };

        foreach (string text in allStrings)
        {
            string lower = text.ToLowerInvariant();
            foreach (string jargon in jargonList)
            {
                Assert.False(
                    lower.Contains(jargon),
                    $"User-facing string '{text}' contains forbidden model jargon '{jargon}'");
            }
        }
    }

    [Fact]
    public void AssistCases_Tools_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("assist-cases.json");
        var tools = doc["tools"]!.AsObject();

        var localTools = tools["local"]!.AsArray().Select(t => t!.ToString()).ToHashSet(StringComparer.OrdinalIgnoreCase);
        Assert.Equal(localTools, AssistAgent.ForTheLocalModel);

        var needsApproval = tools["needsApproval"]!.AsArray().Select(t => t!.ToString()).ToHashSet(StringComparer.OrdinalIgnoreCase);
        Assert.Equal(needsApproval, AssistAgent.DeploysToStudents);

        var mcpOnly = tools["mcpOnly"]!.AsArray().Select(t => t!.ToString()).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var expectedMcpOnly = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "list_curriculum_expectations",
            "plan_curriculum_mentions",
            "add_curriculum_mentions",
        };
        Assert.Equal(expectedMcpOnly, mcpOnly);
    }

    /// <summary>
    /// Every write the LOCAL MODEL can reach and that has a plan_ twin must
    /// be in <see cref="AssistAgent.PlanTwins"/>, or the confirmation setting
    /// silently does nothing for it — a teacher who asked to be shown what
    /// would happen is shown nothing, and only for some requests.
    ///
    /// Deliberately scoped to the local surface. The contract lists twins for
    /// writes the local model is never offered (re_date_classes), and gating
    /// one of those here would hold a write behind a proposal this loop never
    /// asks for.
    /// </summary>
    [Fact]
    public void PlanTwins_CoverEveryLocalWriteThatHasOne()
    {
        var tools = ContractLoader.LoadJson("assist-cases.json")!["tools"]!.AsObject();
        var local = tools["local"]!.AsArray().Select(t => t!.ToString()).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var twins = tools["planTwins"]!.AsObject();

        foreach (var (write, twin) in twins)
        {
            if (!local.Contains(write)) continue;

            // Deploying waits on its own button whatever the setting says, so
            // its twin is never the thing a teacher is shown.
            if (AssistAgent.NeedsApproval(write)) continue;

            Assert.True(AssistAgent.PlanTwins.ContainsKey(write),
                $"{write} is a local write with a plan twin, but the confirmation gate does not know it");
            Assert.Equal(twin!.ToString(), AssistAgent.PlanTwins[write]);
        }

        // And nothing is gated behind a twin that is not in the contract.
        foreach (var (write, twin) in AssistAgent.PlanTwins)
            Assert.Equal(twin, twins[write]!.ToString());
    }

    [Fact]
    public void AssistantConfirmation_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var conf = doc["assistantConfirmation"]!.AsObject();

        bool defaultsToOn = conf["defaultsToOn"]!.GetValue<bool>();
        Assert.True(defaultsToOn);

        int plansBeforeMention = conf["mentionedAfter"]!["plansAccepted"]!.GetValue<int>();
        Assert.Equal(15, plansBeforeMention);

        // NeedsApproval only applies to DeploysToStudents (deploy_section, schedule_deploy)
        Assert.True(AssistAgent.NeedsApproval("deploy_section"));
        Assert.True(AssistAgent.NeedsApproval("schedule_deploy"));
        Assert.False(AssistAgent.NeedsApproval("publish_pages"));
        Assert.False(AssistAgent.NeedsApproval("list_pages"));
        Assert.False(AssistAgent.NeedsApproval("cancel_scheduled_deploy"));
    }

    private sealed class ScriptedModel : IChatModel
    {
        public Task<JsonObject?> Ask(JsonArray messages, JsonArray tools, CancellationToken cancellation) =>
            Task.FromResult<JsonObject?>(null);
    }

    private sealed class DummyTools : IToolServer
    {
        public Task<AssistToolAnswer> CallTool(string name, JsonObject arguments, Action<string>? progress = null, CancellationToken cancellation = default) =>
            Task.FromResult(AssistToolAnswer.Same("OK"));
    }
}




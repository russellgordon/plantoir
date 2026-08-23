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
    public void CourseManagement_ClubDetection_MatchesContract()
    {
        string onFile = ContractLoader.GetSupportPath("ontario_secondary_courses.json");
        string bcFile = ContractLoader.GetSupportPath("british_columbia_secondary_courses.json");
        var catalog = CourseNameCatalog.Load(onFile, bcFile);

        var doc = ContractLoader.LoadJson("course-management.json");
        var cases = doc["courseCode"]!["clubDetection"]!["cases"]!.AsArray();

        foreach (var c in cases)
        {
            string code = c!["code"]!.ToString();
            bool expectClub = c["expectClub"]!.GetValue<bool>();
            Assert.Equal(expectClub, ClubCodeRule.IsClub(code, catalog));
        }
    }

    [Fact]
    public void CourseManagement_DefaultCourseName_MatchesContract()
    {
        string onFile = ContractLoader.GetSupportPath("ontario_secondary_courses.json");
        string bcFile = ContractLoader.GetSupportPath("british_columbia_secondary_courses.json");
        var catalog = CourseNameCatalog.Load(onFile, bcFile);

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
    public void CourseManagement_SectionNumbers_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("course-management.json");
        var sectionNumbers = doc["sectionNumbers"]!.AsObject();

        // suggested
        var suggested = sectionNumbers["suggested"]!.AsArray();
        foreach (var s in suggested)
        {
            var existing = s!["existing"]!.AsArray().Select(x => x!.GetValue<int>()).ToList();
            int expect = s["expect"]!.GetValue<int>();
            Assert.Equal(expect, SectionAdder.SuggestedNumber(existing));
        }

        // addable
        var addable = sectionNumbers["addable"]!.AsArray();
        foreach (var a in addable)
        {
            string entry = a!["entry"]!.ToString();
            var existing = a["existing"]!.AsArray().Select(x => x!.GetValue<int>()).ToList();
            bool expect = a["expect"]!.GetValue<bool>();
            Assert.Equal(expect, SectionAdder.EntryIsAddable(entry, existing));
        }

        // entryProblems
        var entryProblems = sectionNumbers["entryProblems"]!.AsArray();
        foreach (var ep in entryProblems)
        {
            string entry = ep!["entry"]!.ToString();
            var existing = ep["existing"]!.AsArray().Select(x => x!.GetValue<int>()).ToList();
            string? expect = ep["expectProblem"]?.ToString();
            Assert.Equal(expect, SectionAdder.EntryProblem(entry, existing, "ICS3U"));
        }
    }

    [Fact]
    public void CourseManagement_ZipNames_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("course-management.json");
        var zipNames = doc["zipNames"]!.AsObject();
        string courseCode = zipNames["courseCode"]!.ToString();
        var cases = zipNames["cases"]!.AsArray();

        foreach (var c in cases)
        {
            string kind = c!["kind"]!.ToString();
            string name = c["name"]!.ToString();
            string filePath = $@"C:\folder\_backups\{courseCode}\{name}";

            var backup = BackupItem.From(filePath, courseCode);
            var archive = ArchivedItem.From(filePath, courseCode);

            switch (kind)
            {
                case "backup":
                    Assert.NotNull(backup);
                    Assert.Null(archive);
                    string expectedMaker = c["maker"]?.ToString() ?? "teacher";
                    if (expectedMaker == "teacher")
                    {
                        Assert.IsType<BackupMaker.Teacher>(backup!.Maker);
                    }
                    else if (expectedMaker == "assistant")
                    {
                        Assert.IsType<BackupMaker.Assistant>(backup!.Maker);
                        int expectedSection = c["section"]!.GetValue<int>();
                        Assert.Equal(expectedSection, ((BackupMaker.Assistant)backup.Maker).SectionNumber);
                    }
                    break;
                case "archive":
                    Assert.NotNull(archive);
                    Assert.Null(backup);
                    if (c["section"] is JsonNode secNode)
                    {
                        Assert.Equal(secNode.GetValue<int>(), archive!.SectionNumber);
                    }
                    else
                    {
                        Assert.Null(archive!.SectionNumber);
                    }
                    break;
                case "neither":
                    Assert.Null(backup);
                    Assert.Null(archive);
                    break;
            }
        }
    }

    [Fact]
    public void SharedRules_FollowingLinks_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var following = doc["followingLinks"]!.AsObject();

        Assert.True(following["publishing"]!["takesLinkedPages"]!.GetValue<bool>());
        Assert.True(following["publishing"]!["transitive"]!.GetValue<bool>());
        Assert.True(following["publishing"]!["disclosedInThePlan"]!.GetValue<bool>());

        Assert.True(following["unpublishing"]!["takesALinkedPageOnlyWhenNothingElseNeedsIt"]!.GetValue<bool>());
        Assert.True(following["unpublishing"]!["aReferrerCountsOnlyWhenVisible"]!.GetValue<bool>());

        var exclusions = following["neverTakenDownByFollowingLinks"]!.AsArray();
        Assert.Equal(3, exclusions.Count);
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

    [Fact]
    public void AppRules_DeployArguments_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("app-rules.json");
        var cases = doc["deployArguments"]!["cases"]!.AsArray();

        foreach (var c in cases)
        {
            if (c is null) continue;
            string name = c["name"]!.ToString();
            string course = c["course"]!.ToString();
            int section = c["section"]!.GetValue<int>();
            string cloudflareAccountID = c["cloudflareAccountID"]?.ToString() ?? "";
            var configJson = c["configuration"]!.ToJsonString();
            var config = CourseConfiguration.FromBytes(System.Text.Encoding.UTF8.GetBytes(configJson));

            var actual = DeployCommand.Arguments(course, section, config, cloudflareAccountID);
            var expected = c["expectArguments"]!.AsArray().Select(x => x!.ToString()).ToList();

            Assert.Equal(expected, actual);
        }
    }

    [Fact]
    public void AppRules_ConfigurationRules_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("app-rules.json");
        var rules = doc["configurationRules"]!.AsObject();

        foreach (var c in rules["cloudflareAccountID"]!.AsArray())
        {
            if (c is null) continue;
            string input = c["input"]!.ToString();
            string? expect = c["expectProblem"]?.ToString();
            Assert.Equal(expect, CourseConfiguration.CloudflareAccountProblem(input));
        }

        foreach (var c in rules["customDomain"]!.AsArray())
        {
            if (c is null) continue;
            string input = c["input"]!.ToString();
            string expect = c["expectNormalized"]!.ToString();
            Assert.Equal(expect, CourseConfiguration.NormalizedCustomDomain(input));
        }

        string tempDir = Directory.CreateTempSubdirectory("contract-deployfolder").FullName;
        try
        {
            string realFile = Path.Combine(tempDir, "not-a-folder.txt");
            File.WriteAllText(realFile, "x");
            string missing = Path.Combine(tempDir, "nope");

            foreach (var c in rules["deployFolder"]!.AsArray())
            {
                if (c is null) continue;
                string input = c["input"]!.ToString()
                    .Replace("@MISSING@", missing)
                    .Replace("@FILE@", realFile)
                    .Replace("@FOLDER@", tempDir);
                string? expect = c["expectProblem"]?.ToString();
                Assert.Equal(expect, CourseConfiguration.DeployFolderProblem(input));
            }
        }
        finally
        {
            try { Directory.Delete(tempDir, recursive: true); } catch { }
        }
    }

    [Fact]
    public void AppRules_FailureExplanations_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("app-rules.json");
        var cases = doc["failureExplanations"]!["cases"]!.AsArray();

        foreach (var c in cases)
        {
            if (c is null) continue;
            string output = c["output"]!.ToString();
            string? expect = c["expect"]?.ToString();
            string? actual = FailureExplainer.Explanation(output);
            Assert.Equal(expect, actual);
        }
    }

    [Fact]
    public void AppRules_LauncherFlags_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("app-rules.json");
        var section = doc["launcherFlags"]!.AsObject();

        string repoRoot = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", ".."));
        string previewScript = File.ReadAllText(Path.Combine(repoRoot, "preview.ps1"));
        string setupScript = File.ReadAllText(Path.Combine(repoRoot, "setup.ps1"));
        string deployScript = File.ReadAllText(Path.Combine(repoRoot, "deploy.ps1"));

        var previewFlags = section["preview"]!.AsArray().Select(x => x!["flag"]!.ToString().Split(' ')[0]).ToList();
        foreach (var flag in previewFlags)
        {
            Assert.Contains(flag, previewScript, StringComparison.OrdinalIgnoreCase);
        }

        var setupFlags = section["setup"]!.AsArray().Select(x => x!["flag"]!.ToString().Split(' ')[0]).ToList();
        foreach (var flag in setupFlags)
        {
            Assert.Contains(flag, setupScript, StringComparison.OrdinalIgnoreCase);
        }

        var deployFlags = new[] { "--target", "--account", "--to-folder" };
        foreach (var flag in deployFlags)
        {
            Assert.Contains(flag, deployScript, StringComparison.OrdinalIgnoreCase);
        }
    }

    [Fact]
    public void SharedRules_PageNaming_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var cases = doc["pageNaming"]!["cases"]!.AsArray();

        foreach (var c in cases)
        {
            if (c is null) continue;
            string file = c["file"]!.ToString();
            string? frontmatterTitle = c["frontmatterTitle"]?.ToString();
            string expected = c["shown"]!.ToString();

            string pageText = frontmatterTitle is not null
                ? $"---\ntitle: {frontmatterTitle}\n---\nBody"
                : "Body without frontmatter";

            string actual = PagePaths.DisplayTitle(file, pageText);
            Assert.Equal(expected, actual);
        }
    }

    [Fact]
    public void SharedRules_SidebarFilter_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var section = doc["sidebarFilter"]!.AsObject();

        var coursesData = section["courses"]!.AsArray();
        var courses = coursesData.Select(cd =>
        {
            string code = cd!["code"]!.ToString();
            string name = cd["name"]!.ToString();
            var config = CourseConfiguration.FromBytes(System.Text.Encoding.UTF8.GetBytes($$"""{"course_code": "{{code}}", "course_name": "{{name}}", "section_numbers": [1]}"""));
            return new Course(code, Path.Combine("C:\\test\\courses", code), config);
        }).ToList();

        var cases = section["cases"]!.AsArray();
        foreach (var c in cases)
        {
            if (c is null) continue;
            string filter = c["filter"]!.ToString();
            var expect = c["expect"]!.AsArray().Select(x => x!.ToString()).ToList();

            var matches = Workspace.Filter(courses, filter).Select(x => x.Code).ToList();
            Assert.Equal(expect, matches);
        }
    }

    [Fact]
    public void SharedRules_TranscriptStripping_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var cases = doc["transcriptStripping"]!["cases"]!.AsArray();

        foreach (var c in cases)
        {
            if (c is null) continue;
            string input = c["input"]!.ToString();
            string expect = c["expect"]!.ToString();

            string actual = TranscriptBuilder.StripControlSequences(input);
            Assert.Equal(expect, actual);
        }
    }

    [Fact]
    public void SharedRules_ScheduledDeployRefusals_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var cases = doc["scheduledDeployRefusals"]!["cases"]!.AsArray();

        var now = new DateTime(2026, 8, 18, 12, 0, 0);

        foreach (var c in cases)
        {
            if (c is null) continue;
            string name = c["name"]!.ToString();
            string? expectRefusal = c["expectRefusal"]?.ToString();
            var given = c["given"]!.AsObject();

            bool isPast = given["whenIsInThePast"]?.GetValue<bool>() ?? false;
            DateTime when = isPast ? now.AddHours(-1) : now.AddHours(2);

            string target = given["target"]?.ToString() ?? "netlify";
            string folderPath = given["folderProblem"]?.GetValue<bool>() == true ? "" : "C:\\Sites\\valid";
            string cloudflareAccountID = given["cloudflareAccountID"]?.ToString() ?? "0123456789abcdef0123456789abcdef";
            bool hasDeployed = given["hasDeployedBefore"]?.GetValue<bool>() ?? true;

            // An ADDITIONAL destination — present only on the cases entry
            // 305 added. additionalTargetHasDeployedBefore defaults to true
            // so the "never deployed" case fires only when a scenario asks
            // for it explicitly.
            string? additionalTarget = given["additionalTarget"]?.ToString();
            string additionalFolderPath = given["additionalFolderProblem"]?.GetValue<bool>() == true ? "" : "C:\\Sites\\additional";
            bool additionalHasDeployed = given["additionalTargetHasDeployedBefore"]?.GetValue<bool>() ?? true;

            string tempDir = Directory.CreateTempSubdirectory("contract-sched-deploy").FullName;
            try
            {
                string additionalTargetsJson = additionalTarget is null
                    ? "[]"
                    : $$"""[{"type": "{{additionalTarget}}", "path": "{{additionalFolderPath.Replace("\\", "\\\\")}}"}]""";
                var config = CourseConfiguration.FromBytes(System.Text.Encoding.UTF8.GetBytes($$"""
                {
                    "course_code": "ICS3U",
                    "course_name": "Computer Science",
                    "section_numbers": [1],
                    "deploy_target": "{{target}}",
                    "deploy_folder_path": "{{folderPath.Replace("\\", "\\\\")}}",
                    "additional_deploy_targets": {{additionalTargetsJson}}
                }
                """));
                var course = new Course("ICS3U", tempDir, config);

                if (hasDeployed)
                {
                    if (target == "cloudflare_pages")
                    {
                        Directory.CreateDirectory(Path.Combine(tempDir, ".cloudflare_sites"));
                        File.WriteAllText(Path.Combine(tempDir, ".cloudflare_sites", "section1.json"), "{}");
                    }
                    else if (target == "netlify" || target == "local_folder")
                    {
                        Directory.CreateDirectory(Path.Combine(tempDir, ".netlify_sites"));
                        File.WriteAllText(Path.Combine(tempDir, ".netlify_sites", "section1.json"), "{}");
                    }
                }
                if (additionalTarget is not null && additionalHasDeployed)
                {
                    string folderName = additionalTarget == "cloudflare_pages" ? ".cloudflare_sites" : ".netlify_sites";
                    Directory.CreateDirectory(Path.Combine(tempDir, folderName));
                    File.WriteAllText(Path.Combine(tempDir, folderName, "section1.json"), "{}");
                }

                string? problem = ScheduledDeploy.Problem(course, 1, when, now, cloudflareAccountID);

                if (expectRefusal is null)
                {
                    Assert.Null(problem);
                }
                else
                {
                    Assert.NotNull(problem);
                    switch (expectRefusal)
                    {
                        case "hasAlreadyPassed":
                            Assert.Contains("has already passed", problem);
                            break;
                        case "deployFolderNeedsAttention":
                            Assert.Contains("needs attention first", problem);
                            break;
                        case "cloudflareAccountMissing":
                            Assert.Contains("Cloudflare Pages, which needs your Account ID", problem);
                            break;
                        case "neverDeployed":
                            Assert.Contains("has never been deployed", problem);
                            break;
                        case "additionalDeployFolderNeedsAttention":
                            Assert.Contains("also deploys to a folder", problem);
                            Assert.Contains("needs attention first", problem);
                            break;
                        case "additionalCloudflareAccountMissing":
                            Assert.Contains("also deploys to Cloudflare Pages, which needs your Account ID", problem);
                            break;
                        case "additionalDestinationNeverDeployed":
                            Assert.Contains("has never been deployed to", problem);
                            break;
                        default:
                            Assert.Fail($"Unknown refusal case: {expectRefusal}");
                            break;
                    }
                }
            }
            finally
            {
                try { Directory.Delete(tempDir, recursive: true); } catch { }
            }
        }
    }

    [Fact]
    public void FileFormats_CourseConfigKeys_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("file-formats.json");
        var keys = doc["courseConfigKeys"]!["keys"]!.AsArray().Select(k => k!["key"]!.ToString()).ToList();

        string repoRoot = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", ".."));
        string source = File.ReadAllText(Path.Combine(repoRoot, "windows-app", "Plantoir.Core", "Models", "CourseConfiguration.cs"));

        foreach (string key in keys)
        {
            Assert.Contains($"\"{key}\"", source);
        }
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




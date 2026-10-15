using System.Diagnostics;
using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// What a publish set for later does at its moment (bundle 3): the lateness
/// window (#239), the wait for the course (#289), whether the task still
/// stands, and the settings read at the run (#347) — against the contract's
/// case lists where it has them, and through <see cref="ScheduledRun.Execute"/>
/// with a stand-in scheduler, clock and wrapper runner where it does not.
/// </summary>
[Collection(SharedActivityState.Name)]
public class ScheduledRunTests : IDisposable
{
    private readonly string _root = Directory.CreateTempSubdirectory("plantoir-run").FullName;
    private readonly FakeScheduler _scheduler;
    private readonly string _trail;

    public ScheduledRunTests()
    {
        _scheduler = new FakeScheduler(_root);
        _trail = Path.Combine(_root, "activity.txt");
        ActivityTrail.SetCustomLogPathForTesting(_trail);
        ToolchainReadiness.Reset();   // the run's refresh (#477) goes through the process-wide registry
    }

    public void Dispose()
    {
        ToolchainReadiness.Reset();
        _scheduler.Dispose();
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private static JsonNode Cancellation => ContractLoader.LoadJson("shared-rules.json")["scheduledDeployCancellation"]!;

    private static bool AppliesHere(JsonNode c) =>
        c["appliesOn"] is not JsonArray platforms || platforms.Any(p => p!.ToString() == "windows");

    // ---- howLateIsTooLate.cases (#239) --------------------------------------

    [Fact]
    public void EveryLatenessCaseIsDecidedAsTheContractSays()
    {
        var cases = Cancellation["howLateIsTooLate"]!["cases"]!.AsArray();
        Assert.Equal(10, cases.Count);
        foreach (var c in cases)
        {
            TimeSpan? lateBy = c!["momentIsUnknown"]?.GetValue<bool>() == true
                ? null
                : TimeSpan.FromSeconds(c["lateBySeconds"]!.GetValue<long>());
            bool runs = !ScheduledRun.IsTooLate(lateBy, c["chosenDays"]!.GetValue<int>());
            Assert.True(runs == c["expectRuns"]!.GetValue<bool>(), $"\"{c["name"]}\": runs={runs}");
        }
    }

    [Fact]
    public void EveryStoredWindowMeansWhatTheContractSays()
    {
        var setting = Cancellation["theSetting"]!;
        Assert.Equal("scheduled_deploy_may_run_late_days", setting["key"]!.ToString());
        Assert.Equal(setting["default"]!.GetValue<int>(), CourseConfiguration.DefaultMayRunLateDays);
        foreach (var c in setting["storedValueCases"]!.AsArray())
        {
            string stored = c!["stored"] is null ? "" : $"\"scheduled_deploy_may_run_late_days\": {c["stored"]},";
            var config = CourseConfiguration.FromBytes(System.Text.Encoding.UTF8.GetBytes(
                $$"""{ {{stored}} "course_code": "ICS3U" }"""));
            Assert.Equal(c["means"]!.GetValue<int>(), config.ScheduledDeployMayRunLateDays);
        }
    }

    [Fact]
    public void TheWindowSurvivesASaveOnWindows()
    {
        // Preserved on write even though this app offers no control for it:
        // losing it would silently reset a choice a teacher made on a Mac.
        string path = Path.Combine(_root, "course_config.json");
        File.WriteAllText(path, """{ "course_code": "ICS3U", "scheduled_deploy_may_run_late_days": 14 }""");
        var config = CourseConfiguration.FromBytes(File.ReadAllBytes(path));
        config.FooterHtml = "changed";
        config.Write(path);
        Assert.Contains("\"scheduled_deploy_may_run_late_days\": 14", File.ReadAllText(path));
    }

    // ---- theDestination.cases (#347) -----------------------------------------

    [Fact]
    public void EveryDestinationCaseIsDecidedAsTheContractSays()
    {
        var cases = Cancellation["theDestination"]!["cases"]!.AsArray();
        int ran = 0;
        foreach (var c in cases.Where(c => AppliesHere(c!)))
        {
            ran++;
            var now = c!["now"]!.AsObject();
            string dir = Directory.CreateTempSubdirectory("run-destination").FullName;
            try
            {
                string folder = Path.Combine(dir, "published site");
                Directory.CreateDirectory(folder);
                Course? course = now["unreadable"]?.GetValue<bool>() == true ? null : CourseFor(now, dir, folder);
                var promised = (c["scheduledTo"] as JsonArray)?.Select(p => p!.ToString().Replace("{folder}", folder)).ToList()
                               ?? new List<string>();
                string account = now["cloudflareAccountID"]?.ToString() ?? "";

                var decision = ScheduledRun.Decide(course, 1, account, promised);
                var expect = c["expect"]!;

                if (expect["deploysTo"] is JsonArray types)
                {
                    Assert.True(decision.DeploysTo is not null, $"\"{c["name"]}\" stood down: {decision.Refusal?.Key}");
                    Assert.Equal(types.Select(t => t!.ToString()), decision.DeploysTo!.Select(d => d.Type));
                }
                else
                {
                    Assert.True(decision.DeploysTo is null, $"\"{c["name"]}\" went ahead");
                    Assert.Equal(expect["refusal"]!.ToString(), decision.Refusal!.Key);
                    if (expect["destinationNamed"] is { } named)
                        Assert.Equal(named.ToString(), decision.Refusal.Destination);
                    Assert.Contains(decision.Reason, ScheduledPublishOutcome.Sentence("ICS3U", 1,
                        new ScheduledPublishOutcome.Result(ScheduledPublishOutcome.Kind.CouldNotRunAsSetNow,
                            decision.Reason, DateTime.Now, "ICS3U", 1)));
                }
                Assert.True(expect["notesTheChange"]!.GetValue<bool>() == decision.NotesTheChange,
                    $"\"{c["name"]}\": notesTheChange={decision.NotesTheChange}");
            }
            finally { try { Directory.Delete(dir, true); } catch { } }
        }
        Assert.Equal(11, ran);
    }

    [Fact]
    public void EveryReasonClauseIsTheContractsOwn()
    {
        var clauses = Cancellation["theDestination"]!["reasonClauses"]!.AsObject();
        foreach (var (key, value) in clauses.Where(pair => pair.Key != "note"))
            Assert.Equal(value!.ToString().Replace("{destination}", "Netlify"),
                ScheduledRun.ReasonClause(new ScheduledDeploy.Refusal(key, "Netlify")));
        var wording = Cancellation["theDestination"]!["wording"]!;
        Assert.Equal(wording["settingsCouldNotBeRead"]!.ToString(), ScheduledRun.SettingsCouldNotBeRead);
        Assert.Equal(wording["wrapperCouldNotBeWritten"]!.ToString(), ScheduledRun.WrapperCouldNotBeWritten);
    }

    /// <summary>A course built from a case's <c>now</c>, the way the refusals runner builds one.</summary>
    private static Course CourseFor(JsonObject now, string dir, string folder)
    {
        string target = now["target"]?.ToString() ?? "netlify";
        string folderPath = now["folderProblem"]?.GetValue<bool>() == true ? "" : folder;
        string? additional = now["additionalTarget"]?.ToString();
        string additionalPath = now["additionalFolderProblem"]?.GetValue<bool>() == true ? "" : folder;
        bool kept = now["keptForReference"]?.GetValue<bool>() == true;
        var config = new JsonObject
        {
            ["course_code"] = "ICS3U",
            ["section_numbers"] = new JsonArray(1),
            ["deploy_target"] = target,
            ["deploy_folder_path"] = folderPath,
            ["additional_deploy_targets"] = additional is null
                ? new JsonArray()
                : new JsonArray(new JsonObject { ["type"] = additional, ["path"] = additionalPath }),
        };
        if (kept) config["kept_for_reference"] = true;
        var course = new Course("ICS3U", dir, CourseConfiguration.FromBytes(System.Text.Encoding.UTF8.GetBytes(config.ToJsonString())));

        void Mark(string type)
        {
            string marker = type == "cloudflare_pages" ? ".cloudflare_sites" : ".netlify_sites";
            Directory.CreateDirectory(Path.Combine(dir, marker));
            File.WriteAllText(Path.Combine(dir, marker, "section1.json"), "{}");
        }
        if (now["hasDeployedBefore"]?.GetValue<bool>() ?? true) Mark(target);
        if (additional is not null && (now["additionalTargetHasDeployedBefore"]?.GetValue<bool>() ?? true)) Mark(additional);
        if (now["folderGone"]?.GetValue<bool>() == true) Directory.Delete(folder, true);
        return course;
    }

    // ---- savingSettings.scheduledDeploys (#347) ------------------------------

    [Fact]
    public void EverySaveCaseSaysWhatTheContractSays()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var cases = doc["savingSettings"]!["scheduledDeploys"]!["cases"]!.AsArray();
        var names = doc["specialNames"]!;
        string goes = names["settingsSaveScheduledDeployGoesWhereTheCourseDeploysNow"]!["message"]!.ToString();
        string cannot = names["settingsSaveScheduledDeployCannotGoAheadAsSetNow"]!["message"]!.ToString();
        var moment = new DateTime(2026, 10, 1, 6, 30, 0);
        Assert.Equal(5, cases.Count);

        foreach (var c in cases)
        {
            string dir = Directory.CreateTempSubdirectory("save-case").FullName;
            try
            {
                var beforeGiven = c!["before"]!.AsObject();
                var savedGiven = c["saved"]!.AsObject();
                string site = Path.Combine(dir, "site");
                Directory.CreateDirectory(site);
                var before = new List<CourseConfiguration.DeployDestination>
                    { new(beforeGiven["target"]!.ToString(), beforeGiven["target"]!.ToString() == "local_folder" ? site : "") };
                var saved = new JsonObject
                {
                    ["course_code"] = "ICS3U",
                    ["section_numbers"] = new JsonArray(1),
                    ["deploy_target"] = savedGiven["target"]!.ToString(),
                    ["deploy_folder_path"] = savedGiven["target"]!.ToString() == "local_folder" ? site : "",
                };
                var course = new Course("ICS3U", dir, CourseConfiguration.FromBytes(System.Text.Encoding.UTF8.GetBytes(saved.ToJsonString())));
                if (beforeGiven["hasDeployedBefore"]?.GetValue<bool>() == true)
                {
                    string marker = beforeGiven["target"]!.ToString() == "cloudflare_pages" ? ".cloudflare_sites" : ".netlify_sites";
                    Directory.CreateDirectory(Path.Combine(dir, marker));
                    File.WriteAllText(Path.Combine(dir, marker, "section1.json"), "{}");
                }
                var scheduled = (c["scheduled"] as JsonArray)?.Select(s => (s!.GetValue<int>(), moment)).ToList()
                                ?? new List<(int, DateTime)>();   // scheduledElsewhere: another folder's alarm, never here

                var said = ScheduledRun.WhatASaveSays(scheduled, course, before, savedGiven["cloudflareAccountID"]?.ToString() ?? "");

                var expect = c["expect"]!.AsArray().Select(e => e!.ToString()).ToList();
                Assert.True(expect.Count == said.Count, $"\"{c["name"]}\": said {said.Count}");
                foreach (var (kind, sentence) in expect.Zip(said))
                {
                    string template = kind == "goesWhereTheCourseDeploysNow" ? goes : cannot;
                    string opening = template.Split('{')[0];
                    Assert.StartsWith(opening.Replace("{section}", "1"), sentence.Replace("Section 1", "Section {section}"));
                }
            }
            finally { try { Directory.Delete(dir, true); } catch { } }
        }
    }

    [Fact]
    public void TheSaveSentencesAreTheContractsOwn()
    {
        var names = ContractLoader.LoadJson("shared-rules.json")["specialNames"]!;
        var moment = new DateTime(2026, 10, 1, 6, 30, 0);
        string when = $"{moment:dddd d MMMM, h:mm tt}";
        string dir = Directory.CreateTempSubdirectory("save-words").FullName;
        try
        {
            string site = Path.Combine(dir, "site");
            Directory.CreateDirectory(site);
            var toFolder = new Course("ICS3U", dir, CourseConfiguration.FromBytes(System.Text.Encoding.UTF8.GetBytes(
                new JsonObject { ["deploy_target"] = "local_folder", ["deploy_folder_path"] = site }.ToJsonString())));
            var goes = ScheduledRun.WhatASaveSays([(1, moment)], toFolder, [new("netlify", "")], "");
            Assert.Equal(names["settingsSaveScheduledDeployGoesWhereTheCourseDeploysNow"]!["message"]!.ToString()
                             .Replace("{section}", "1").Replace("{moment}", when).Replace("{destinations}", site),
                         Assert.Single(goes));

            var toCloudflare = new Course("ICS3U", dir, CourseConfiguration.FromBytes(System.Text.Encoding.UTF8.GetBytes(
                new JsonObject { ["deploy_target"] = "cloudflare_pages" }.ToJsonString())));
            var cannot = ScheduledRun.WhatASaveSays([(1, moment)], toCloudflare, [new("netlify", "")], "");
            Assert.Equal(names["settingsSaveScheduledDeployCannotGoAheadAsSetNow"]!["message"]!.ToString()
                             .Replace("{section}", "1").Replace("{moment}", when)
                             .Replace("{reason}", ScheduledRun.ReasonClause(new ScheduledDeploy.Refusal("cloudflareAccountMissing"))),
                         Assert.Single(cannot));
        }
        finally { try { Directory.Delete(dir, true); } catch { } }
    }

    // ---- The run itself ---------------------------------------------------------

    private string Folder(string name = "work", string target = "netlify")
    {
        string folder = FakeScheduler.WorkingFolderWith(_root, name, "ICS3U",
            $$"""{ "course_code": "ICS3U", "section_numbers": [1], "deploy_target": "{{target}}" }""");
        Directory.CreateDirectory(Path.Combine(folder, "courses", "ICS3U", ".netlify_sites"));
        File.WriteAllText(Path.Combine(folder, "courses", "ICS3U", ".netlify_sites", "section1.json"), "{}");
        return folder;
    }

    private sealed class Clock
    {
        public DateTimeOffset Now = new(2026, 10, 1, 6, 30, 0, TimeSpan.FromHours(-4));
    }

    /// <summary>
    /// Half six on the 1st in THIS computer's time zone. The run reads the
    /// classes on <c>world.Now().LocalDateTime</c>'s day, so a clock pinned
    /// at −04:00 was the 2nd on a machine at UTC+14 (and the 30th at UTC−12),
    /// and the #475 tests below would flag a different class there (2C's
    /// implementation review, L-4).
    /// </summary>
    private static Clock HalfSixOnTheFirstHere()
    {
        var local = new DateTime(2026, 10, 1, 6, 30, 0, DateTimeKind.Unspecified);
        return new Clock { Now = new DateTimeOffset(local, TimeZoneInfo.Local.GetUtcOffset(local)) };
    }

    private ScheduledRun.World World(Clock clock, List<string> ran) => new()
    {
        Now = () => clock.Now,
        Sleep = span => clock.Now += span,
        CloudflareAccountID = () => "",
        RunWrapper = script => { ran.Add(script); return 0; },
        OutcomeDirectory = Path.Combine(_root, "outcomes"),
    };

    // ---- #475: classes dated after the next class, on a scheduled deploy ------

    /// <summary>
    /// A section whose class on the 5th is published while the next class is
    /// the 2nd (the run's day is the 1st): flagged, and nobody to ask.
    /// </summary>
    private string FolderWithAClassPublishedEarly()
    {
        string folder = FakeScheduler.WorkingFolderWith(_root, "early", "ICS3U",
            """{ "course_code": "ICS3U", "section_numbers": [1], "deploy_target": "netlify", "per_section_folders": ["All Classes"] }""");
        string course = Path.Combine(folder, "courses", "ICS3U");
        Directory.CreateDirectory(Path.Combine(course, ".netlify_sites"));
        File.WriteAllText(Path.Combine(course, ".netlify_sites", "section1.json"), "{}");
        string classes = Path.Combine(course, "section1", "All Classes");
        Directory.CreateDirectory(classes);
        File.WriteAllText(Path.Combine(classes, "Unit 1, Day 1.md"), "---\npublish: true\ncreated: 2026-10-01T07:00:00.000-0400\n---\n");
        File.WriteAllText(Path.Combine(classes, "Unit 1, Day 2.md"), "---\npublish: true\ncreated: 2026-10-02T07:00:00.000-0400\n---\n");
        File.WriteAllText(Path.Combine(classes, "Unit 1, Day 3.md"), "---\npublish: true\ncreated: 2026-10-05T07:00:00.000-0400\n---\n");
        return folder;
    }

    [Fact]
    public void AScheduledDeployThatWentOut_RecordsTheClassesDatedLater()
    {
        string folder = FolderWithAClassPublishedEarly();
        var clock = HalfSixOnTheFirstHere();
        string name = _scheduler.AddNew(folder, "ICS3U", 1, clock.Now, "Netlify");
        var world = new ScheduledRun.World
        {
            Now = () => clock.Now,
            Sleep = span => clock.Now += span,
            CloudflareAccountID = () => "",
            OutcomeDirectory = Path.Combine(_root, "outcomes"),
            // What the real wrapper does when the deploy got through.
            RunWrapper = _ =>
            {
                ScheduledPublishOutcome.Record(Path.Combine(_root, "outcomes"), "ICS3U", 1,
                    ScheduledPublishOutcome.Kind.Succeeded, "Netlify", folder);
                return 0;
            },
        };

        Assert.Equal(ScheduledRun.Ending.Deployed, ScheduledRun.Execute(TaskScheduling.JobPath(name), world));

        Assert.Contains("ICS3U/1 · deployed with classes dated after the next class: section1/All Classes/Unit 1, Day 3",
                        File.ReadAllText(_trail));
    }

    /// <summary>
    /// The wrapper exits 0 whether or not the deploy got through, so the exit
    /// code means nothing: a run that left no success record, or one from an
    /// earlier night, writes no line (the mac's fixes review, A).
    /// </summary>
    [Theory]
    [InlineData("did not finish")]
    [InlineData("an earlier night's success")]
    public void AScheduledDeployThatDidNotGoOut_RecordsNoClasses(string how)
    {
        string folder = FolderWithAClassPublishedEarly();
        var clock = HalfSixOnTheFirstHere();
        string name = _scheduler.AddNew(folder, "ICS3U", 1, clock.Now, "Netlify");
        string outcomes = Path.Combine(_root, "outcomes");
        if (how == "an earlier night's success")
        {
            ScheduledPublishOutcome.Record(outcomes, "ICS3U", 1, ScheduledPublishOutcome.Kind.Succeeded, "Netlify", folder);
            foreach (string record in Directory.GetFiles(outcomes))
                File.SetLastWriteTime(record, DateTime.Now.AddDays(-1));
        }
        var world = new ScheduledRun.World
        {
            Now = () => clock.Now,
            Sleep = span => clock.Now += span,
            CloudflareAccountID = () => "",
            OutcomeDirectory = Path.Combine(_root, "outcomes"),
            RunWrapper = _ =>
            {
                if (how == "did not finish")
                    ScheduledPublishOutcome.Record(outcomes, "ICS3U", 1, ScheduledPublishOutcome.Kind.DidNotFinish, "Netlify", folder);
                return 0;
            },
        };

        Assert.Equal(ScheduledRun.Ending.Deployed, ScheduledRun.Execute(TaskScheduling.JobPath(name), world));

        string trail = File.Exists(_trail) ? File.ReadAllText(_trail) : "";
        Assert.DoesNotContain("deployed with classes dated after the next class", trail);
    }

    [Fact]
    public void AJobTooLateStandsDownDeploysNothingAndClearsItsTask()
    {
        string folder = Folder();
        var clock = new Clock();
        string name = _scheduler.AddNew(folder, "ICS3U", 1, clock.Now.AddDays(-8), "Netlify");
        var ran = new List<string>();

        var ending = ScheduledRun.Execute(TaskScheduling.JobPath(name), World(clock, ran));

        Assert.Equal(ScheduledRun.Ending.StoodDown, ending);
        Assert.Empty(ran);
        Assert.DoesNotContain(name, _scheduler.Tasks.Keys);
        var record = ScheduledPublishOutcome.ReadFrom(Path.Combine(_root, "outcomes"), "ICS3U", 1, folder);
        Assert.Equal(ScheduledPublishOutcome.Kind.TooLateToRun, record!.Outcome);
    }

    [Fact]
    public void AnOrdinaryRunWritesTheWrapperUnderItsOwnNameHoldingBothLeases()
    {
        string folder = Folder();
        var clock = new Clock();
        string name = _scheduler.AddNew(folder, "ICS3U", 1, clock.Now, "Netlify");
        var leasesDuringTheRun = new List<string>();
        var world = new ScheduledRun.World
        {
            Now = () => clock.Now,
            Sleep = span => clock.Now += span,
            CloudflareAccountID = () => "",
            OutcomeDirectory = Path.Combine(_root, "outcomes"),
            RunWrapper = script =>
            {
                leasesDuringTheRun.AddRange(Directory.GetFiles(
                    Path.Combine(folder, "courses", ".internal", "activity"), $"*.{Environment.ProcessId}.lease")
                    .Select(Path.GetFileName)!);
                Assert.Equal(TaskScheduling.WrapperScriptPath(name), script);
                return 0;
            },
        };

        Assert.Equal(ScheduledRun.Ending.Deployed, ScheduledRun.Execute(TaskScheduling.JobPath(name), world));

        Assert.Contains($"ICS3U.build.{Environment.ProcessId}.lease", leasesDuringTheRun);
        Assert.Contains($"ICS3U.publish.{Environment.ProcessId}.lease", leasesDuringTheRun);
        Assert.Empty(Directory.GetFiles(Path.Combine(folder, "courses", ".internal", "activity"), "*.lease"));
        Assert.DoesNotContain(name, _scheduler.Tasks.Keys);   // one-shot: cleared after it ran
    }

    [Fact]
    public void AnotherProgramsBuildIsWaitedForAndATenMinuteWaitStandsDown()
    {
        string folder = Folder();
        var clock = new Clock();
        string name = _scheduler.AddNew(folder, "ICS3U", 1, clock.Now, "Netlify");
        var ran = new List<string>();
        using var other = StartALongRunningChild();
        try
        {
            WriteLease(folder, "build", other);
            var ending = ScheduledRun.Execute(TaskScheduling.JobPath(name), World(clock, ran));

            Assert.Equal(ScheduledRun.Ending.StoodDown, ending);
            Assert.Empty(ran);
            Assert.True(clock.Now - new Clock().Now >= ScheduledRun.LongestWait, "it did not wait the whole ten minutes");
            var record = ScheduledPublishOutcome.ReadFrom(Path.Combine(_root, "outcomes"), "ICS3U", 1, folder);
            Assert.Equal(ScheduledPublishOutcome.Kind.CourseWasBusy, record!.Outcome);
            Assert.Contains("waited 600 s for another program's build of the course", File.ReadAllText(_trail));
            Assert.Contains("and stood down", File.ReadAllText(_trail));
            Assert.Empty(Directory.GetFiles(Path.Combine(folder, "courses", ".internal", "activity"),
                $"*.{Environment.ProcessId}.lease"));   // its own leases went before it stood down
        }
        finally { try { other.Kill(true); } catch { } }
    }

    [Fact]
    public void AnotherProgramsPreviewIsNotWaitedFor()
    {
        string folder = Folder();
        var clock = new Clock();
        string name = _scheduler.AddNew(folder, "ICS3U", 1, clock.Now, "Netlify");
        var ran = new List<string>();
        using var other = StartALongRunningChild();
        try
        {
            WriteLease(folder, "preview", other);
            Assert.Equal(ScheduledRun.Ending.Deployed, ScheduledRun.Execute(TaskScheduling.JobPath(name), World(clock, ran)));
            Assert.Single(ran);
            Assert.Equal(new Clock().Now, clock.Now);   // not a single look again
        }
        finally { try { other.Kill(true); } catch { } }
    }

    [Fact]
    public void ADeploySetAgainWhileTheRunWorksIsNotClearedByIt()
    {
        // One task per section per folder: setting the section again while a
        // long deploy runs replaces the task under the SAME name. The run
        // clearing "its" task by name afterwards would delete the new one.
        string folder = Folder();
        var clock = new Clock();
        string name = _scheduler.AddNew(folder, "ICS3U", 1, clock.Now, "Netlify");
        var world = new ScheduledRun.World
        {
            Now = () => clock.Now, Sleep = _ => { }, CloudflareAccountID = () => "",
            OutcomeDirectory = Path.Combine(_root, "outcomes"),
            RunWrapper = _ =>
            {
                _scheduler.AddNew(folder, "ICS3U", 1, clock.Now.AddDays(1), "Netlify");   // set again, same name
                return 0;
            },
        };

        Assert.Equal(ScheduledRun.Ending.Deployed, ScheduledRun.Execute(TaskScheduling.JobPath(name), world));
        Assert.Contains(name, _scheduler.Tasks.Keys);
        Assert.Empty(_scheduler.Deleted);
    }

    // ---- #470: a start queued behind the run still working --------------------

    /// <summary>
    /// The first run sets the section again while it works, for a moment five
    /// minutes on (token 2); under <c>Queue</c> Task Scheduler starts the second
    /// instance when the first ends — here forty minutes after its moment — with
    /// the task's NEWEST definition (measured, #470). The first run leaves the
    /// new task alone; the queued one passes the lateness window, finds no
    /// leases, still stands, deploys and clears the task.
    /// </summary>
    [Fact]
    public void AQueuedRunStartedAfterTheFirstFinishedStillDeploys()
    {
        string folder = Folder();
        var first = DateTime.Now.AddMinutes(1);
        var second = first.AddMinutes(5);
        Assert.Null(TaskScheduling.Schedule(folder, "ICS3U", 1, first, [new("netlify", "")]));
        string name = TaskScheduling.NameFor("ICS3U", 1, folder);
        string jobPath = TaskScheduling.JobPath(name);
        string token1 = ScheduledRun.ReadJob(jobPath)!.Token;
        var clock = new Clock { Now = new DateTimeOffset(first) };
        var ran = new List<string>();
        var world = new ScheduledRun.World
        {
            Now = () => clock.Now, Sleep = span => clock.Now += span, CloudflareAccountID = () => "",
            OutcomeDirectory = Path.Combine(_root, "outcomes"),
            RunWrapper = script =>
            {
                ran.Add(script);
                if (ran.Count == 1)
                    Assert.Null(TaskScheduling.Schedule(folder, "ICS3U", 1, second, [new("netlify", "")]));
                return 0;
            },
        };

        Assert.Equal(ScheduledRun.Ending.Deployed, ScheduledRun.Execute(jobPath, world, taskToken: token1));
        Assert.Contains(name, _scheduler.Tasks.Keys);   // the first run left the deploy just set
        string token2 = ScheduledRun.ReadJob(jobPath)!.Token;
        Assert.NotEqual(token1, token2);
        Assert.Empty(Directory.GetFiles(Path.Combine(folder, "courses", ".internal", "activity"), "*.lease"));

        clock.Now = new DateTimeOffset(second).AddMinutes(40);   // the queued start, after the first ended
        Assert.Equal(ScheduledRun.Ending.Deployed, ScheduledRun.Execute(jobPath, world, taskToken: token2));
        Assert.Equal(2, ran.Count);
        Assert.DoesNotContain(name, _scheduler.Tasks.Keys);   // one-shot: cleared after it ran
        Assert.Null(ScheduledPublishOutcome.ReadFrom(Path.Combine(_root, "outcomes"), "ICS3U", 1, folder));
    }

    /// <summary>
    /// A queued start that comes later than the course's window allows (the
    /// first run worked for days, or the computer slept) stands down as too
    /// late, in the run's own words — the lateness check, not the queue, decides.
    /// </summary>
    [Fact]
    public void AQueuedRunStartedLaterThanTheCoursesWindowStandsDownTooLate()
    {
        string folder = Folder();
        var second = DateTime.Now.AddMinutes(5);
        Assert.Null(TaskScheduling.Schedule(folder, "ICS3U", 1, second, [new("netlify", "")]));
        string name = TaskScheduling.NameFor("ICS3U", 1, folder);
        string jobPath = TaskScheduling.JobPath(name);
        var clock = new Clock { Now = new DateTimeOffset(second).AddDays(CourseConfiguration.DefaultMayRunLateDays + 1) };
        var ran = new List<string>();

        Assert.Equal(ScheduledRun.Ending.StoodDown,
            ScheduledRun.Execute(jobPath, World(clock, ran), taskToken: ScheduledRun.ReadJob(jobPath)!.Token));
        Assert.Empty(ran);
        Assert.DoesNotContain(name, _scheduler.Tasks.Keys);
        var record = ScheduledPublishOutcome.ReadFrom(Path.Combine(_root, "outcomes"), "ICS3U", 1, folder);
        Assert.Equal(ScheduledPublishOutcome.Kind.TooLateToRun, record!.Outcome);
    }

    [Fact]
    public void ARunWhoseTaskWasCancelledMeanwhileDeploysNothing()
    {
        string folder = Folder();
        var clock = new Clock();
        string name = _scheduler.AddNew(folder, "ICS3U", 1, clock.Now, "Netlify");
        _scheduler.Tasks.Remove(name);   // cancelled from Task Scheduler itself
        var ran = new List<string>();

        Assert.Equal(ScheduledRun.Ending.NoLongerStands, ScheduledRun.Execute(TaskScheduling.JobPath(name), World(clock, ran)));
        Assert.Empty(ran);
        Assert.Null(ScheduledPublishOutcome.ReadFrom(Path.Combine(_root, "outcomes"), "ICS3U", 1, folder));
    }

    [Fact]
    public void ADestinationChangedAfterSchedulingIsWhereItGoesAndTheTrailSaysSo()
    {
        string site = Path.Combine(_root, "the site");
        Directory.CreateDirectory(site);
        string folder = FakeScheduler.WorkingFolderWith(_root, "moved", "ICS3U",
            $$"""{ "course_code": "ICS3U", "section_numbers": [1], "deploy_target": "local_folder", "deploy_folder_path": "{{site.Replace("\\", "\\\\")}}" }""");
        var clock = new Clock();
        string name = _scheduler.AddNew(folder, "ICS3U", 1, clock.Now, "Netlify");
        string? written = null;
        var world = new ScheduledRun.World
        {
            Now = () => clock.Now, Sleep = _ => { }, CloudflareAccountID = () => "",
            OutcomeDirectory = Path.Combine(_root, "outcomes"),
            RunWrapper = script => { written = File.ReadAllText(script); return 0; },
        };

        Assert.Equal(ScheduledRun.Ending.Deployed, ScheduledRun.Execute(TaskScheduling.JobPath(name), world));
        Assert.Contains("'local_folder'", written);
        Assert.DoesNotContain("'netlify'", written);
        Assert.Contains("was set to deploy to Netlify", File.ReadAllText(_trail));
    }

    [Fact]
    public void ADestinationNeverDeployedToStandsDownWithTheReason()
    {
        string folder = FakeScheduler.WorkingFolderWith(_root, "cf", "ICS3U",
            """{ "course_code": "ICS3U", "section_numbers": [1], "deploy_target": "cloudflare_pages" }""");
        var clock = new Clock();
        string name = _scheduler.AddNew(folder, "ICS3U", 1, clock.Now, "Netlify");
        var ran = new List<string>();
        var world = World(clock, ran);
        world = new ScheduledRun.World
        {
            Now = world.Now, Sleep = world.Sleep, RunWrapper = world.RunWrapper, OutcomeDirectory = world.OutcomeDirectory,
            CloudflareAccountID = () => "0123456789abcdef0123456789abcdef",
        };

        Assert.Equal(ScheduledRun.Ending.StoodDown, ScheduledRun.Execute(TaskScheduling.JobPath(name), world));
        Assert.Empty(ran);
        var record = ScheduledPublishOutcome.ReadFrom(Path.Combine(_root, "outcomes"), "ICS3U", 1, folder);
        Assert.Equal(ScheduledPublishOutcome.Kind.CouldNotRunAsSetNow, record!.Outcome);
        Assert.Contains("never been deployed to Cloudflare Pages", record.Destination);
        Assert.DoesNotContain(name, _scheduler.Tasks.Keys);
    }

    [Fact]
    public void TheCourseIsFoundByItsListedNameNeverByAskingTheVolume()
    {
        // #239's fifth trap: asking whether courses\CHESS-CLUB exists answers
        // yes for Chess-Club. Names are listed and compared; only one match counts.
        string folder = Path.Combine(_root, "clubs");
        Directory.CreateDirectory(Path.Combine(folder, "courses", "Chess-Club"));
        Directory.CreateDirectory(Path.Combine(folder, "courses", "ChessClub"));
        File.WriteAllText(Path.Combine(folder, "courses", "Chess-Club", "course_config.json"), "{}");
        File.WriteAllText(Path.Combine(folder, "courses", "ChessClub", "course_config.json"), "{}");

        Assert.Equal(Path.Combine(folder, "courses", "Chess-Club"),
                     ScheduledRun.ReadCourse(folder, "CHESS-CLUB")!.DirectoryPath);   // one match ignoring case
        Assert.Null(ScheduledRun.ReadCourse(folder, "CHESS CLUB"));                   // one hyphen away: none
    }

    // ---- #477: a copy of the folder's tools, and the run's own refresh --------

    private string Activity(string folder) => Path.Combine(folder, "courses", ".internal", "activity");

    private string TrailLineContaining(string text) =>
        File.ReadAllLines(_trail).Single(line => line.Contains(text));

    [Fact]
    public void ALiveCopyOfTheFolderIsWaitedForAndTheRunGoesAheadAfter()
    {
        string folder = Folder();
        var clock = new Clock();
        string name = _scheduler.AddNew(folder, "ICS3U", 1, clock.Now, "Netlify");
        var ran = new List<string>();
        int looks = 0;
        var world = World(clock, ran);
        world = new ScheduledRun.World
        {
            Now = world.Now, Sleep = world.Sleep, CloudflareAccountID = world.CloudflareAccountID,
            RunWrapper = world.RunWrapper, OutcomeDirectory = world.OutcomeDirectory,
            CopyingTheFolder = _ => ++looks <= 3 ? 4242 : null,
        };

        Assert.Equal(ScheduledRun.Ending.Deployed, ScheduledRun.Execute(TaskScheduling.JobPath(name), world));

        Assert.Single(ran);
        Assert.Equal(new Clock().Now.AddSeconds(45), clock.Now);
        string line = TrailLineContaining("waited 45 s");
        Assert.Contains("ICS3U/1", line);
        Assert.Contains("waited 45 s for Plantoir to finish getting the working folder ready (process 4242), and went ahead", line);
    }

    [Fact]
    public void ACopyStillRunningAfterTenMinutesStandsDownWithoutBlamingTheCourse()
    {
        string folder = Folder();
        var clock = new Clock();
        string name = _scheduler.AddNew(folder, "ICS3U", 1, clock.Now, "Netlify");
        var ran = new List<string>();
        var world = World(clock, ran);
        world = new ScheduledRun.World
        {
            Now = world.Now, Sleep = world.Sleep, CloudflareAccountID = world.CloudflareAccountID,
            RunWrapper = world.RunWrapper, OutcomeDirectory = world.OutcomeDirectory,
            CopyingTheFolder = _ => 4242,
        };

        Assert.Equal(ScheduledRun.Ending.StoodDown, ScheduledRun.Execute(TaskScheduling.JobPath(name), world));

        Assert.Empty(ran);
        Assert.True(clock.Now - new Clock().Now >= ScheduledRun.LongestWait, "it did not wait the whole ten minutes");
        var record = ScheduledPublishOutcome.ReadFrom(Path.Combine(_root, "outcomes"), "ICS3U", 1, folder)!;
        Assert.Equal(ScheduledPublishOutcome.Kind.CouldNotRunAsSetNow, record.Outcome);   // never CourseWasBusy
        Assert.Equal(ScheduledRun.WrapperCouldNotBeWritten, record.Destination);
        Assert.Contains("waited 600 s for Plantoir to finish getting the working folder ready (process 4242), and stood down",
                        File.ReadAllText(_trail));
        Assert.Empty(Directory.Exists(Activity(folder)) ? Directory.GetFiles(Activity(folder), "*.lease") : []);
        Assert.DoesNotContain(name, _scheduler.Tasks.Keys);
    }

    [Fact]
    public void ARealMarkerIsWhatTheRunWaitsFor()
    {
        string folder = Folder();
        var clock = new Clock();
        string name = _scheduler.AddNew(folder, "ICS3U", 1, clock.Now, "Netlify");
        var ran = new List<string>();
        using var other = Process.Start(new ProcessStartInfo("cmd.exe", "/c ping -n 60 127.0.0.1 >nul")
                                        { CreateNoWindow = true, UseShellExecute = false })!;
        try
        {
            Directory.CreateDirectory(Activity(folder));
            File.WriteAllText(ToolchainReadiness.MarkerPath(folder, other.Id),
                              $"{other.Id}\n{other.ProcessName}\n{DateTime.UtcNow:O}\n");
            int sleeps = 0;
            var world = new ScheduledRun.World
            {
                Now = () => clock.Now, CloudflareAccountID = () => "", OutcomeDirectory = Path.Combine(_root, "outcomes"),
                RunWrapper = script => { ran.Add(script); return 0; },
                Sleep = span =>
                {
                    clock.Now += span;
                    if (++sleeps == 2) { other.Kill(); other.WaitForExit(); }   // the copy finishes
                },
            };

            Assert.Equal(ScheduledRun.Ending.Deployed, ScheduledRun.Execute(TaskScheduling.JobPath(name), world));
            Assert.Single(ran);
            Assert.Contains($"waited 30 s for Plantoir to finish getting the working folder ready (process {other.Id}), and went ahead",
                            File.ReadAllText(_trail));
        }
        finally { try { other.Kill(); } catch { } }
    }

    /// <summary>A recipe beside "the program": the files the run must copy before it builds.</summary>
    private string Bundle(string scriptText = "NEW fingerprint")
    {
        string bundle = Path.Combine(_root, "bundle");
        Directory.CreateDirectory(Path.Combine(bundle, "scripts"));
        File.WriteAllText(Path.Combine(bundle, "Dockerfile"), "FROM new");
        File.WriteAllText(Path.Combine(bundle, "scripts", "section_fingerprint.py"), scriptText);
        File.WriteAllText(Path.Combine(bundle, "deploy.ps1"), "# new deploy");
        File.WriteAllText(Path.Combine(bundle, "preview.ps1"), "# new preview");
        return bundle;
    }

    private ScheduledRun.World WithBundle(ScheduledRun.World world, string? bundle) => new()
    {
        Now = world.Now, Sleep = world.Sleep, CloudflareAccountID = world.CloudflareAccountID,
        RunWrapper = world.RunWrapper, OutcomeDirectory = world.OutcomeDirectory,
        BundledToolchainRoot = bundle, CopyingTheFolder = _ => null,
    };

    [Fact]
    public void TheRunBringsTheFoldersToolsUpToDateBeforeItWritesTheWrapper()
    {
        string folder = Folder();
        string old = Path.Combine(folder, ".toolchain", "scripts", "section_fingerprint.py");
        Directory.CreateDirectory(Path.GetDirectoryName(old)!);
        File.WriteAllText(old, "OLD fingerprint");
        var clock = new Clock();
        string name = _scheduler.AddNew(folder, "ICS3U", 1, clock.Now, "Netlify");
        var seen = new List<string>();
        var world = WithBundle(new ScheduledRun.World
        {
            Now = () => clock.Now, Sleep = span => clock.Now += span, CloudflareAccountID = () => "",
            OutcomeDirectory = Path.Combine(_root, "outcomes"),
            RunWrapper = script =>
            {
                seen.Add(File.ReadAllText(old));
                seen.Add(File.ReadAllText(Path.Combine(folder, "deploy.ps1")));
                seen.Add(File.ReadAllText(Path.Combine(folder, "preview.ps1")));
                // Both leases were held across the copy, and still are.
                Assert.Equal(2, Directory.GetFiles(Activity(folder), $"*.{Environment.ProcessId}.lease").Length);
                return 0;
            },
        }, Bundle());

        Assert.Equal(ScheduledRun.Ending.Deployed, ScheduledRun.Execute(TaskScheduling.JobPath(name), world));

        Assert.Equal(new[] { "NEW fingerprint", "# new deploy", "# new preview" }, seen);
        string line = TrailLineContaining("got the working folder ready for a scheduled deploy");
        Assert.Contains("ICS3U/1", line);
        Assert.Empty(Directory.GetFiles(Activity(folder), ToolchainReadiness.MarkerPrefix + "*"));   // its marker went too
        Assert.DoesNotContain(name, _scheduler.Tasks.Keys);
    }

    [Fact]
    public void AFailedRefreshStandsDownAndBuildsNothing()
    {
        string folder = Folder();
        var clock = new Clock();
        string name = _scheduler.AddNew(folder, "ICS3U", 1, clock.Now, "Netlify");
        var ran = new List<string>();
        ToolchainReadiness.Copier = (_, _) => new ToolchainMirror.CopyResult(0, 1, @".toolchain\scripts\x.py", "Access is denied.");

        Assert.Equal(ScheduledRun.Ending.StoodDown,
            ScheduledRun.Execute(TaskScheduling.JobPath(name), WithBundle(World(clock, ran), Bundle())));

        Assert.Empty(ran);
        var record = ScheduledPublishOutcome.ReadFrom(Path.Combine(_root, "outcomes"), "ICS3U", 1, folder)!;
        Assert.Equal(ScheduledPublishOutcome.Kind.CouldNotRunAsSetNow, record.Outcome);
        Assert.Equal(ScheduledRun.WrapperCouldNotBeWritten, record.Destination);
        string line = TrailLineContaining("could not finish getting the working folder ready for a scheduled deploy");
        Assert.Contains("ICS3U/1", line);
        Assert.Contains("; the scheduled deploy stood down", line);
        Assert.Empty(Directory.GetFiles(Activity(folder), "*.lease"));
        Assert.DoesNotContain(name, _scheduler.Tasks.Keys);
    }

    [Fact]
    public void ACopyThatStartsJustBeforeTheRefreshIsWaitedForUntilTheRunsTenMinutes()
    {
        // Step 2 found no copy (the seam), but a window opened on the folder
        // in the moment between: the run's own copy writes its marker, finds
        // the earlier live one, and waits its turn — on the run's clock.
        string folder = Folder();
        var clock = new Clock();
        string name = _scheduler.AddNew(folder, "ICS3U", 1, clock.Now, "Netlify");
        var ran = new List<string>();
        using var other = Process.Start(new ProcessStartInfo("cmd.exe", "/c ping -n 60 127.0.0.1 >nul")
                                        { CreateNoWindow = true, UseShellExecute = false })!;
        try
        {
            Directory.CreateDirectory(Activity(folder));
            File.WriteAllText(ToolchainReadiness.MarkerPath(folder, other.Id),
                              $"{other.Id}\n{other.ProcessName}\n{DateTime.UtcNow.AddMinutes(-1):O}\n");
            var copied = 0;
            ToolchainReadiness.Copier = (_, _) => { copied++; return new ToolchainMirror.CopyResult(1, 0); };

            Assert.Equal(ScheduledRun.Ending.StoodDown,
                ScheduledRun.Execute(TaskScheduling.JobPath(name), WithBundle(World(clock, ran), Bundle())));

            Assert.Equal(0, copied);
            Assert.Empty(ran);
            Assert.True(clock.Now - new Clock().Now >= ScheduledRun.LongestWait);
            var record = ScheduledPublishOutcome.ReadFrom(Path.Combine(_root, "outcomes"), "ICS3U", 1, folder)!;
            Assert.Equal(ScheduledPublishOutcome.Kind.CouldNotRunAsSetNow, record.Outcome);
            Assert.Contains($"for Plantoir to finish getting the working folder ready (process {other.Id}), and stood down",
                            File.ReadAllText(_trail));
            Assert.False(File.Exists(ToolchainReadiness.MarkerPath(folder, Environment.ProcessId)));
            Assert.Empty(Directory.GetFiles(Activity(folder), "*.lease"));
        }
        finally { try { other.Kill(); } catch { } }
    }

    [Fact]
    public void NoBundleBesideTheProgramRemovesNothing()
    {
        string folder = Folder();
        string kept = Path.Combine(folder, ".toolchain", "scripts", "build_site.py");
        Directory.CreateDirectory(Path.GetDirectoryName(kept)!);
        File.WriteAllText(kept, "the folder's own");
        string empty = Path.Combine(_root, "no-recipe");
        Directory.CreateDirectory(empty);
        var clock = new Clock();
        string name = _scheduler.AddNew(folder, "ICS3U", 1, clock.Now, "Netlify");
        var ran = new List<string>();

        Assert.Equal(ScheduledRun.Ending.Deployed,
            ScheduledRun.Execute(TaskScheduling.JobPath(name), WithBundle(World(clock, ran), empty)));

        Assert.Single(ran);
        Assert.Equal("the folder's own", File.ReadAllText(kept));
        Assert.Equal("# stub", File.ReadAllText(Path.Combine(folder, "deploy.ps1")));
    }

    [Fact]
    public void ATaskCancelledWhileTheToolsWereCopiedDeploysNothing()
    {
        string folder = Folder();
        var clock = new Clock();
        string name = _scheduler.AddNew(folder, "ICS3U", 1, clock.Now, "Netlify");
        var ran = new List<string>();
        ToolchainReadiness.Copier = (_, _) => { _scheduler.Tasks.Remove(name); return new ToolchainMirror.CopyResult(3, 0); };

        Assert.Equal(ScheduledRun.Ending.NoLongerStands,
            ScheduledRun.Execute(TaskScheduling.JobPath(name), WithBundle(World(clock, ran), Bundle())));

        Assert.Empty(ran);
        Assert.Empty(Directory.GetFiles(Activity(folder), "*.lease"));
        Assert.Null(ScheduledPublishOutcome.ReadFrom(Path.Combine(_root, "outcomes"), "ICS3U", 1, folder));
    }

    private static Process StartALongRunningChild() =>
        Process.Start(new ProcessStartInfo("cmd.exe", "/c pause")
        { CreateNoWindow = true, UseShellExecute = false, RedirectStandardInput = true })!;

    private static void WriteLease(string folder, string kind, Process owner)
    {
        string activity = Path.Combine(folder, "courses", ".internal", "activity");
        Directory.CreateDirectory(activity);
        File.WriteAllText(Path.Combine(activity, $"ICS3U.{kind}.{owner.Id}.lease"),
            $"{owner.Id}\n{owner.ProcessName}\n2026-10-01T10:29:00.0000000Z\n");
    }
}

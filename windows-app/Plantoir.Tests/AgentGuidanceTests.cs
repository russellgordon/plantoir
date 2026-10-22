using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// The guidance for assistants (#496; the mac's #454, its
/// <c>PrintablePagesTests</c> guidance half, names kept): the managed section
/// in AGENTS.md and CLAUDE.md, the skills, Add and Not Now, the failure line
/// and notice, and that a failure never holds the folder back. Cases from
/// <c>shared-rules.json</c> → <c>printablePages.agentGuidance</c>. In the
/// shared collection because it drives <see cref="ToolchainReadiness"/>'s
/// process-wide state.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class AgentGuidanceTests : IDisposable
{
    private readonly string _folder = Path.Combine(Path.GetTempPath(), "plantoir-guidance-" + Guid.NewGuid().ToString("N")[..8]);

    public AgentGuidanceTests()
    {
        Directory.CreateDirectory(_folder);
        ToolchainReadiness.Reset();
        AgentGuidanceDeclined.FilePathForTests = Path.Combine(_folder + "-state", "agent-guidance-declined.json");
    }

    public void Dispose()
    {
        ToolchainReadiness.Reset();
        AgentGuidanceDeclined.FilePathForTests = null;
        foreach (string dir in new[] { _folder, _folder + "-state" })
        {
            try
            {
                if (!Directory.Exists(dir)) continue;
                foreach (var file in Directory.EnumerateFiles(dir, "*", SearchOption.AllDirectories))
                    File.SetAttributes(file, FileAttributes.Normal);
                Directory.Delete(dir, recursive: true);
            }
            catch { }
        }
    }

    private static string GuidanceSource => Path.Combine(ContractLoader.RepositoryRoot, "support", "agent_guidance");

    private static JsonNode Contract => ContractLoader.LoadJson("shared-rules.json")["printablePages"]!["agentGuidance"]!;

    private static string Filled(string text) =>
        text.Replace("{start}", AgentGuidance.SectionStart).Replace("{end}", AgentGuidance.SectionEnd);

    private AgentGuidance.Outcome Pass() =>
        AgentGuidance.Write(GuidanceSource, _folder, AgentGuidanceDeclined.SignatureFor, AgentGuidanceDeclined.Forget);

    [Fact]
    public void EveryRootFileCaseHoldsAsTheContractSays()
    {
        Assert.Equal(Contract["sectionStart"]!.ToString(), AgentGuidance.SectionStart);
        Assert.Equal(Contract["sectionEnd"]!.ToString(), AgentGuidance.SectionEnd);
        Assert.Equal(Contract["rootFiles"]!.AsArray().Select(f => f!.ToString()), AgentGuidance.RootFiles);
        Assert.Equal(Contract["folders"]!.AsArray().Select(f => f!.ToString()), AgentGuidance.SkillHomes.Select(h => h + "/skills"));
        var cases = Contract["rootFileCases"]!["cases"]!.AsArray();
        Assert.True(cases.Count >= 10, "the contract lost root-file cases");
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            string? existing = c["existing"] is { } e ? Filled(e.ToString()) : null;
            string? declined = c["declined"]?.ToString() switch
            {
                "thisSection" => AgentGuidance.Signature("NEW"),
                "earlierSection" => AgentGuidance.Signature("EARLIER"),
                _ => null,
            };
            var action = AgentGuidance.Action(existing, "NEW", declined);
            string expected = Filled(c["result"]!.ToString());
            string expect = c["expect"]!.ToString();
            switch (expect)
            {
                case "write":
                    Assert.True(action.Kind == AgentGuidance.RootFileKind.Write && action.Text == expected, name);
                    break;
                case "replace":
                    Assert.True(action.Kind == AgentGuidance.RootFileKind.Replace && action.Text == expected, name);
                    break;
                case "unchanged":
                    Assert.True(action.Kind == AgentGuidance.RootFileKind.Unchanged && existing == expected, name);
                    break;
                case "leave":
                    Assert.True(action.Kind == AgentGuidance.RootFileKind.Leave && existing == expected, name);
                    break;
                case "ask":
                    Assert.True(action.Kind == AgentGuidance.RootFileKind.Ask, name);
                    Assert.True(AgentGuidance.Appended(existing ?? "", "NEW") == expected, name);
                    break;
                default:
                    Assert.Fail($"{name}: an expectation this test does not know");
                    break;
            }
            // Whatever a pass (or an Add) leaves, the next pass leaves alone.
            if (expect != "leave")
                Assert.True(AgentGuidance.Action(expected, "NEW", null).Kind == AgentGuidance.RootFileKind.Unchanged,
                    $"{name}: a second pass must change nothing");
        }
    }

    [Fact]
    public void ASectionWhoseOnlyDifferenceIsItsLineEndingsIsUnchanged()
    {
        // A teacher's editor saving the file CRLF must not have the section
        // rewritten at every launch (plan review M7).
        string crlf = ("My notes.\n\n" + AgentGuidance.Block("NEW") + "\n").Replace("\n", "\r\n");
        Assert.Equal(AgentGuidance.RootFileKind.Unchanged, AgentGuidance.Action(crlf, "NEW", null).Kind);
        Assert.Equal(AgentGuidance.RootFileKind.Replace, AgentGuidance.Action(crlf, "NEWER", null).Kind);
    }

    [Fact]
    public void AddReadsTheFileAgainAndRefusesOneItCannotRead()
    {
        var cases = Contract["addCases"]!["cases"]!.AsArray();
        Assert.Equal(3, cases.Count);
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            string file = Path.Combine(_folder, name.Replace(' ', '-') + ".md");
            byte[]? before = null;
            switch (c["file"]!.ToString())
            {
                case "readable":
                    File.WriteAllText(file, c["existing"]!.ToString(), new UTF8Encoding(false));
                    break;
                case "unreadable":
                    // Saved in another encoding: these bytes are not UTF-8.
                    before = [0x4D, 0x79, 0x20, 0xE9, 0xE8, 0x0A, 0xFF, 0xFE];
                    File.WriteAllBytes(file, before);
                    break;
            }
            string? failed = AgentGuidance.AppendAfterYes(new AgentGuidance.PendingAppend("CLAUDE.md", file, "NEW"));
            if (c["expect"]!.ToString() == "refused")
            {
                Assert.NotNull(failed);
                Assert.Equal(before, File.ReadAllBytes(file));
            }
            else
            {
                Assert.Null(failed);
                Assert.Equal(Filled(c["result"]!.ToString()), File.ReadAllText(file));
            }
        }
    }

    [Fact]
    public void TheFailureLineIsTheContractsAndTheNoticeHasNoPath()
    {
        var events = ContractLoader.LoadJson("shared-rules.json")["activityTrail"]!["mustRecord"]!.AsArray();
        string example = events.First(e => e!["event"]!.ToString() == "guidance for assistants could not be written")!["line"]!.ToString();
        var outcome = new AgentGuidance.Outcome();
        outcome.Note(".agents/skills/plantoir-printing", "You don’t have permission to save the file.");
        Assert.Equal(example, AgentGuidance.CouldNotWriteLine(outcome.Failures));
        Assert.Equal(
            "Plantoir could not put its guidance for assistants into this folder (You don’t have permission to save the file). Everything else works as usual.",
            AgentGuidanceWording.CouldNotWrite(outcome.FirstReason!));

        // Windows: .NET's own message names the path; the notice must not.
        var denied = new UnauthorizedAccessException(@"Access to the path 'C:\Users\teacher\Plantoir\CLAUDE.md' is denied.");
        Assert.Equal(unchecked((int)0x80070005), denied.HResult);
        string reason = AgentGuidance.SystemReason(denied);
        Assert.DoesNotContain(@":\", reason);
        Assert.DoesNotContain("teacher", reason);
        Assert.NotEqual(AgentGuidance.CouldNotBeWritten, reason);   // the system's own sentence ("Access is denied.")

        // A FACILITY_WIN32 IOException: the system's sentence for its code.
        var exists = new IOException(@"Cannot create 'C:\x\.claude' because a file with that name already exists.", unchecked((int)0x800700B7));
        Assert.DoesNotContain(@":\", AgentGuidance.SystemReason(exists));
        Assert.NotEqual(AgentGuidance.CouldNotBeWritten, AgentGuidance.SystemReason(exists));

        // Not FACILITY_WIN32 (COR_E_IO): Win32Exception would say "Unknown error (0x1620)".
        var generic = new IOException(@"Something about 'C:\x'.");
        Assert.Equal(unchecked((int)0x80131620), generic.HResult);
        Assert.Equal(AgentGuidance.CouldNotBeWritten, AgentGuidance.SystemReason(generic));
    }

    [Fact]
    public void TheAskWordsAreTheContractsAndNameNoMachinery()
    {
        var words = Contract["words"]!;
        var pairs = new (string Key, string Said)[]
        {
            ("askTitle", AgentGuidanceWording.AskTitle("{file}")),
            ("askFound", AgentGuidanceWording.AskFound("{file}")),
            ("askWhat", AgentGuidanceWording.AskWhat),
            ("askYoursStays", AgentGuidanceWording.AskYoursStays),
            ("showWhatIsAdded", AgentGuidanceWording.ShowWhatIsAdded),
            ("add", AgentGuidanceWording.Add),
            ("notNow", AgentGuidanceWording.NotNow),
            ("couldNotWrite", AgentGuidanceWording.CouldNotWrite("{reason}")),
            ("dismiss", AgentGuidanceWording.Dismiss),
        };
        var forbidden = ContractLoader.LoadJson("shared-rules.json")["userFacingLabelWords"]!["forbidden"]!.AsArray()
            .Select(w => Regex.Escape(w!.ToString()));
        var machinery = new Regex(@"\b(" + string.Join("|", forbidden) + @")\b", RegexOptions.IgnoreCase);
        foreach (var (key, said) in pairs)
        {
            Assert.Equal(words[key]!.ToString(), said);
            Assert.False(machinery.IsMatch(said), $"{key} names the machinery: {said}");
        }
    }

    [Fact]
    public void AFreshFolderGetsTheSkillsAndBothFilesHoldingOnlyTheSection()
    {
        var outcome = Pass();
        Assert.Empty(outcome.Failures);
        Assert.Empty(outcome.Pending);
        foreach (string home in AgentGuidance.SkillHomes)
        {
            string skill = File.ReadAllText(Path.Combine(_folder, home, "skills", "plantoir-printing", "SKILL.md"));
            Assert.Contains("name: plantoir-printing", skill);
            Assert.Contains("printable: true", skill);
        }
        foreach (string name in AgentGuidance.RootFiles)
        {
            string text = File.ReadAllText(Path.Combine(_folder, name));
            Assert.StartsWith(AgentGuidance.SectionStart, text);
            Assert.Contains("plantoir-printing", text);
            Assert.EndsWith(AgentGuidance.SectionEnd + "\n", text);
        }
        // Atomic writes leave nothing behind.
        Assert.Empty(Directory.GetFiles(_folder, "*.tmp"));
        Assert.Equal(0, Pass().Changed);
    }

    [Fact]
    public void TheGraphsSkillIsWrittenAndBothRootFilesNameIt()
    {
        string skillName = ContractLoader.LoadJson("shared-rules.json")["figureFences"]!["agentGuidance"]!["skill"]!.ToString();
        Assert.Empty(Pass().Failures);
        foreach (string home in AgentGuidance.SkillHomes)
        {
            string skill = File.ReadAllText(Path.Combine(_folder, home, "skills", skillName, "SKILL.md"));
            Assert.Contains("name: " + skillName, skill);
            Assert.Contains("```functionplot", skill);
            Assert.Contains("% alt:", skill);
        }
        foreach (string name in AgentGuidance.RootFiles)
            Assert.Contains(skillName, File.ReadAllText(Path.Combine(_folder, name)));
    }

    /// <summary>
    /// #571 (the mac's <c>PrintablePagesTests.testTheQuizzesSkillIsWrittenAndBothRootFilesNameIt</c>):
    /// the self-check quizzes skill (#563) lands in both homes, holds the
    /// callout, points at the graphs and runnable-code skills rather than
    /// repeating them, and both root files name it. The probes are the
    /// skill's own Markdown, not app wording.
    /// </summary>
    [Fact]
    public void TheQuizzesSkillIsWrittenAndBothRootFilesNameIt()
    {
        string skillName = ContractLoader.LoadJson("shared-rules.json")["quizCallouts"]!["agentGuidance"]!["skill"]!.ToString();
        Assert.Empty(Pass().Failures);
        foreach (string home in AgentGuidance.SkillHomes)
        {
            string skill = File.ReadAllText(Path.Combine(_folder, home, "skills", skillName, "SKILL.md"));
            Assert.Contains("name: " + skillName, skill);
            Assert.Contains("> [!quiz]", skill);
            Assert.Contains("plantoir-math-graphs", skill);
            Assert.Contains("plantoir-runnable-code", skill);
        }
        foreach (string name in AgentGuidance.RootFiles)
            Assert.Contains(skillName, File.ReadAllText(Path.Combine(_folder, name)));
    }

    /// <summary>
    /// #600 (the mac's <c>PrintablePagesTests.testThePageAuthoringSkillIsWrittenAndBothRootFilesRouteToItFirst</c>,
    /// #596): the page-authoring skill travels the same way, names every
    /// feature skill it routes to in backticks — each written beside it — and
    /// both root files name it in their FIRST bullet, so an assistant asked for
    /// any page reads it before writing anything.
    /// </summary>
    [Fact]
    public void ThePageAuthoringSkillIsWrittenAndBothRootFilesRouteToItFirst()
    {
        var guidance = Contract["pageAuthoringSkill"]!;
        string skillName = guidance["skill"]!.ToString();
        var routesTo = guidance["routesTo"]!.AsArray().Select(name => name!.ToString()).ToList();
        Assert.Equal(4, routesTo.Count);
        Assert.Empty(Pass().Failures);
        foreach (string home in AgentGuidance.SkillHomes)
        {
            string skills = Path.Combine(_folder, home, "skills");
            string skill = File.ReadAllText(Path.Combine(skills, skillName, "SKILL.md"));
            Assert.Contains("name: " + skillName, skill);
            foreach (string routed in routesTo)
            {
                Assert.True(skill.Contains($"`{routed}`"), $"{home}: the skill must route to {routed}");
                Assert.True(File.Exists(Path.Combine(skills, routed, "SKILL.md")), $"{home}: {routed} must be written beside it");
            }
            Assert.Contains("```mermaid", skill);
            Assert.Contains("> [!", skill);
            Assert.Contains("Success criteria", skill);
            Assert.Contains("My Progress", skill);
            Assert.Contains("publish: false", skill);
            Assert.Contains("Media", skill);
        }
        foreach (string name in AgentGuidance.RootFiles)
        {
            string text = File.ReadAllText(Path.Combine(_folder, name));
            string? firstBullet = text.Split("\n- ").Skip(1).FirstOrDefault();
            Assert.True(firstBullet is not null, $"{name} must have a bullet");
            Assert.True(firstBullet!.Contains(skillName), $"{name} must name the {skillName} skill first");
        }
    }

    [Fact]
    public void ATeachersOwnFileIsAskedAboutNotWrittenAndTheirSkillsAreLeftAlone()
    {
        string own = "# My own notes for Claude\n\nAlways use British spelling.\n";
        File.WriteAllText(Path.Combine(_folder, "CLAUDE.md"), own);
        string sibling = Path.Combine(_folder, ".claude", "skills", "my-own-skill", "SKILL.md");
        Directory.CreateDirectory(Path.GetDirectoryName(sibling)!);
        File.WriteAllText(sibling, "mine\n");
        string settings = Path.Combine(_folder, ".claude", "settings.local.json");
        File.WriteAllText(settings, "{}\n");

        var outcome = Pass();
        var pending = Assert.Single(outcome.Pending);
        Assert.Equal("CLAUDE.md", pending.FileName);
        Assert.Equal(own, File.ReadAllText(Path.Combine(_folder, "CLAUDE.md")));
        Assert.Equal("mine\n", File.ReadAllText(sibling));
        Assert.Equal("{}\n", File.ReadAllText(settings));
        Assert.True(File.Exists(Path.Combine(_folder, ".claude", "skills", "plantoir-printing", "SKILL.md")),
            "the skills are written whatever the answer");

        Assert.Null(AgentGuidance.AppendAfterYes(pending));
        Assert.StartsWith(own + "\n" + AgentGuidance.SectionStart, File.ReadAllText(Path.Combine(_folder, "CLAUDE.md")));
        Assert.Empty(Pass().Pending);
    }

    [Fact]
    public void NotNowIsRememberedUntilTheWordsChangeOrTheFileGoes()
    {
        string path = Path.Combine(_folder, "CLAUDE.md");
        var pending = new AgentGuidance.PendingAppend("CLAUDE.md", path, "NEW");
        AgentGuidanceDeclined.Remember(pending);
        // Paths compare as NTFS does.
        string? stored = AgentGuidanceDeclined.SignatureFor(path.ToUpperInvariant());
        Assert.Equal(AgentGuidance.RootFileKind.Leave, AgentGuidance.Action("Mine.\n", "NEW", stored).Kind);
        Assert.Equal(AgentGuidance.RootFileKind.Ask, AgentGuidance.Action("Mine.\n", "NEWER", stored).Kind);

        // The file goes: the pass forgets the answer, and writes it fresh.
        Assert.False(File.Exists(path));
        Pass();
        Assert.Null(AgentGuidanceDeclined.SignatureFor(path));
    }

    [Fact]
    public void TheAnswerIsRecordedEitherWayAndNotNowIsKept()
    {
        string trail = Path.Combine(_folder + "-state", "activity.txt");
        Directory.CreateDirectory(Path.GetDirectoryName(trail)!);
        ActivityTrail.SetCustomLogPathForTesting(trail);
        try
        {
            File.WriteAllText(Path.Combine(_folder, "AGENTS.md"), "Mine.\n");
            var pending = new AgentGuidance.PendingAppend("AGENTS.md", Path.Combine(_folder, "AGENTS.md"), "NEW");
            ToolchainReadiness.Answer(_folder, pending, add: false);
            Assert.Equal("Mine.\n", File.ReadAllText(pending.FilePath));
            Assert.Equal(AgentGuidance.Signature("NEW"), AgentGuidanceDeclined.SignatureFor(pending.FilePath));
            ToolchainReadiness.Answer(_folder, pending, add: true);
            Assert.Contains(AgentGuidance.SectionStart, File.ReadAllText(pending.FilePath));
            Assert.Null(AgentGuidanceDeclined.SignatureFor(pending.FilePath));
            string lines = File.ReadAllText(trail);
            Assert.Contains(AgentGuidance.AskedLine("AGENTS.md", added: false), lines);
            Assert.Contains(AgentGuidance.AskedLine("AGENTS.md", added: true), lines);
        }
        finally { ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath); }
    }

    [Fact]
    public void AGuidanceFailureNeverHoldsTheFolderBack()
    {
        File.WriteAllText(Path.Combine(_folder, ".claude"), "not a folder");
        var outcome = Pass();
        Assert.NotEmpty(outcome.Failures);
        Assert.StartsWith(".claude/skills/", outcome.Failures[0]);
        Assert.DoesNotContain(@":\", outcome.FirstReason);

        // Through the real hook: the copy succeeds, the guidance pass fails.
        string work = Path.Combine(_folder, "work");
        Directory.CreateDirectory(Path.Combine(work, "courses"));
        File.WriteAllText(Path.Combine(work, Workspace.MarkerLauncher), "# stub");
        File.WriteAllText(Path.Combine(work, ".claude"), "not a folder");
        ToolchainReadiness.Copier = (folder, _) =>
        {
            Directory.CreateDirectory(Path.Combine(folder, ".toolchain"));
            File.WriteAllText(Path.Combine(folder, ".toolchain", ToolchainMirror.RecipeRootFiles[0]), "x");
            return new ToolchainMirror.CopyResult(1, 0);
        };
        string bundled = Path.Combine(_folder, "bundled");
        CopyDirectory(GuidanceSource, Path.Combine(bundled, "support", "agent_guidance"));
        ToolchainReadiness.Ensure(work, bundled).Wait(TimeSpan.FromSeconds(30));
        Assert.True(SpinWait.SpinUntil(() => ToolchainReadiness.GuidanceNoticeFor(work) is not null, TimeSpan.FromSeconds(30)));
        Assert.Equal(ToolchainReadiness.State.Ready, ToolchainReadiness.StateOf(work));
        Assert.Null(ToolchainReadiness.Refusal(work));
        Assert.StartsWith("Plantoir could not put its guidance for assistants into this folder (", ToolchainReadiness.GuidanceNoticeFor(work));
        Assert.DoesNotContain(@":\", ToolchainReadiness.GuidanceNoticeFor(work));
        ToolchainReadiness.DismissGuidanceNotice(work);
        Assert.Null(ToolchainReadiness.GuidanceNoticeFor(work));
    }

    [Fact]
    public void ABundledBodyWithCrlfIsFingerprintedAsTheLfOne()
    {
        string lf = "## Plantoir\n\nLine one.\nLine two.\n";
        string path = Path.Combine(_folder, "crlf-body.md");
        File.WriteAllText(path, lf.Replace("\n", "\r\n"), new System.Text.UTF8Encoding(false));
        string read = AgentGuidance.ReadBundledBody(path);
        Assert.DoesNotContain("\r", read);
        Assert.Equal(AgentGuidance.Signature(lf), AgentGuidance.Signature(read));
    }

    [Fact]
    public void APassThatSucceedsAfterOneThatFailedClearsTheNotice()
    {
        var failed = new AgentGuidance.Outcome();
        failed.Note("AGENTS.md", "it is read-only");
        ToolchainReadiness.ApplyGuidance(_folder, failed);
        Assert.NotNull(ToolchainReadiness.GuidanceNoticeFor(_folder));
        ToolchainReadiness.ApplyGuidance(_folder, new AgentGuidance.Outcome());
        Assert.Null(ToolchainReadiness.GuidanceNoticeFor(_folder));
    }

    [Fact]
    public void AFilesQuestionIsTakenByOneWindowAndPutBackWhenNotAnswered()
    {
        var outcome = new AgentGuidance.Outcome();
        outcome.Pending.Add(new AgentGuidance.PendingAppend("AGENTS.md", Path.Combine(_folder, "AGENTS.md"), "NEW"));
        outcome.Pending.Add(new AgentGuidance.PendingAppend("CLAUDE.md", Path.Combine(_folder, "CLAUDE.md"), "NEW"));
        ToolchainReadiness.ApplyGuidance(_folder, outcome);
        ToolchainReadiness.ApplyGuidance(_folder, outcome);   // a second pass does not ask twice
        var first = ToolchainReadiness.TakeNextPending(_folder);
        Assert.Equal("AGENTS.md", first?.FileName);
        ToolchainReadiness.PutBack(_folder, first!);
        Assert.Equal("AGENTS.md", ToolchainReadiness.TakeNextPending(_folder)?.FileName);
        Assert.Equal("CLAUDE.md", ToolchainReadiness.TakeNextPending(_folder)?.FileName);
        Assert.Null(ToolchainReadiness.TakeNextPending(_folder));
    }

    [Fact]
    public void TheToolchainCopyDoesNotWriteTheGuidance()
    {
        string mirror = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir.Core", "Models", "ToolchainMirror.cs"));
        Assert.DoesNotContain("AgentGuidance.Write(", mirror);
        // And the pass is not chained to the copy's own task, which windows await.
        string readiness = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir.Core", "Models", "ToolchainReadiness.cs"));
        Assert.DoesNotContain("ContinueWith", readiness);
    }

    private static void CopyDirectory(string from, string to)
    {
        foreach (string file in Directory.GetFiles(from, "*", SearchOption.AllDirectories))
        {
            string target = Path.Combine(to, Path.GetRelativePath(from, file));
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            File.Copy(file, target, overwrite: true);
        }
    }
}

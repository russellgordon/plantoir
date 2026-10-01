using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// <c>shared-rules.json</c> → <c>startOfYear</c> and <c>sectionCheck</c>
/// (GitHub issues #355 and #389, the mac's #96 and #362): each case laid out on
/// disk as <c>howToRunACase</c> says, planned and written through the same
/// <see cref="AssistWorkspace"/> calls the MCP pair makes, passing the plan's
/// code, then read back by the built site's reading.
/// </summary>
[Collection(SharedActivityState.Name)]
public class StartOfYearTests : IDisposable
{
    private const string Code = "TEST";
    private readonly string _folder = Path.Combine(Path.GetTempPath(), "plantoir-tests", "soy-" + Guid.NewGuid().ToString("N"));

    public StartOfYearTests() => Directory.CreateDirectory(_folder);

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private static JsonNode StartOfYearRule => ContractLoader.LoadJson("shared-rules.json")["startOfYear"]!;
    private static List<string> Strings(JsonNode? node) => node is null ? new() : node.AsArray().Select(n => n!.ToString()).ToList();

    /// <summary>
    /// Cases that need clubs (a course's `naming`), which this app does not
    /// have yet: #274 owns them, and the case runs the day it lands. Declared
    /// here by WHAT they need rather than by name, so a new club case is
    /// skipped for the same reason and a non-club case never is.
    /// </summary>
    private static bool NeedsClubs(JsonNode c) => c["naming"] is not null;

    // ---- Laying a case out -------------------------------------------------

    private string CourseDir => Path.Combine(_folder, "courses", Code);

    private Dictionary<string, string> LayOut(JsonNode c)
    {
        if (Directory.Exists(_folder)) Directory.Delete(_folder, recursive: true);
        Directory.CreateDirectory(CourseDir);
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        File.WriteAllText(Path.Combine(CourseDir, "course_config.json"),
            "{\"course_code\":\"TEST\",\"course_name\":\"Test\",\"num_sections\":1,\"section_numbers\":[1]," +
            "\"shared_folders\":[\"Concepts\"],\"per_section_folders\":[\"All Classes\"],\"per_section_files\":[\"Key Links.md\"]}");

        var paths = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var page in c["pages"]!.AsArray())
        {
            string title = page!["title"]!.ToString();
            string kind = page["kind"]!.ToString();
            bool visible = page["visible"]?.GetValue<bool>() ?? true;
            string relative = kind switch
            {
                "class" => Path.Combine("section1", "All Classes", title + ".md"),
                "keyLinks" => Path.Combine("section1", "Key Links.md"),
                "folderIndex" => Path.Combine(title, "index.md"),
                "curriculum" => Path.Combine("Curriculum", title + ".md"),
                "sectionFrontPage" => Path.Combine("section1", "index.md"),
                _ => Path.Combine(page["folder"]?.ToString() ?? "Concepts", title + ".md"),
            };
            string full = Path.Combine(CourseDir, relative);
            Directory.CreateDirectory(Path.GetDirectoryName(full)!);
            bool sectionLocal = relative.StartsWith("section1", StringComparison.Ordinal);

            var header = new List<string> { "---" };
            if (page["shownAs"] is JsonNode shownAs) header.Add($"title: {shownAs}");
            if (page["undated"]?.GetValue<bool>() != true)
            {
                string date = page["date"]?.ToString() ?? "2026-09-08";
                header.Add($"{(sectionLocal ? "created" : "createdForSection1")}: {date}T07:00:00.000-0400");
            }
            header.Add(sectionLocal ? $"publish: {(visible ? "true" : "false")}" : $"publishForSection1: {(visible ? "true" : "false")}");
            if (page["strayPublishForSection"]?.GetValue<bool>() == true) header.Add("publishForSection1: true");
            header.Add("---");
            var body = Strings(page["links"]).Select(link => $"See [[{link}]].").ToList();
            // The front page's class embed sits under its Most Recent Class
            // heading, as every section front page the app makes has it.
            if (page["embeds"] is JsonArray embeds && embeds.Count > 0) body.Add(SectionIndex.Heading);
            body.AddRange(Strings(page["embeds"]).Select(embed => $"![[{embed}]]"));
            File.WriteAllText(full, string.Join("\n", header) + "\n" + string.Join("\n\n", body) + "\n");
            paths[title] = full;
        }
        return paths;
    }

    private AssistWorkspace Workspace() => new(_folder, new FakeLauncher(), undo: new UndoHistory());

    private static string? PlanCodeIn(string planText)
    {
        var line = planText.Split('\n').FirstOrDefault(l => l.StartsWith("Plan code: ", StringComparison.Ordinal));
        return line?["Plan code: ".Length..].Trim();
    }

    // ---- The cases --------------------------------------------------------

    [Fact]
    public void EveryCaseIsPlannedAndWrittenAsTheContractSays()
    {
        var cases = StartOfYearRule["cases"]!.AsArray();
        Assert.True(cases.Count >= 15, $"startOfYear lost cases: {cases.Count} (15 when this was written)");

        var failures = new List<string>();
        int ran = 0;
        foreach (var c in cases)
        {
            if (NeedsClubs(c!)) continue;
            ran++;
            failures.AddRange(Run(c!));
        }
        Assert.True(ran >= 14, $"only {ran} startOfYear cases ran");
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }

    private List<string> Run(JsonNode c)
    {
        string name = c["name"]!.ToString();
        var problems = new List<string>();
        var paths = LayOut(c);
        var before = paths.ToDictionary(p => p.Key, p => File.ReadAllText(p.Value));
        var workspace = Workspace();

        var proposal = workspace.PlanStartOfYear(Code, 1);
        string? code = PlanCodeIn(proposal.Text);

        foreach (string warning in Strings(c["expectWarnings"]))
        {
            // The constant part of each warning's sentence.
            string marker = warning switch
            {
                "alreadyTaught" => "Dated before today, and going into draft",
                "scheduledDeploy" => "set to deploy on its own",
                _ => "is in draft itself",
            };
            Assert.Contains(marker, StartOfYearWording.ByKey[warning]);
            if (!proposal.Text.Contains(marker, StringComparison.Ordinal))
                problems.Add($"{name}: the plan carries no {warning} warning");
        }
        if (c["expectIntroContains"] is JsonNode intro && !proposal.Text.Contains(intro.ToString(), StringComparison.Ordinal))
            problems.Add($"{name}: the intro does not contain “{intro}”");
        foreach (var expected in c["expectPlanNames"]?.AsArray() ?? new JsonArray())
        {
            string page = expected!["page"]!.ToString();
            string named = expected["folder"] is JsonNode folder
                ? StartOfYearWording.PageNameInFolder(page, folder.ToString())
                : StartOfYearWording.PageName(page);
            if (!proposal.Text.Split('\n').Any(line => line.StartsWith("• " + named + " — ", StringComparison.Ordinal)))
                problems.Add($"{name}: the plan has no line naming {named}");
        }
        if (proposal.Text.Contains(".md", StringComparison.Ordinal) || proposal.Text.Contains("courses/", StringComparison.Ordinal))
            problems.Add($"{name}: the plan names a file rather than a page");

        var outcome = workspace.PrepareForStartOfYear(Code, 1, code, StartOfYearAskedFrom.AnOutsideAssistant);
        var expectDraft = Strings(c["expectDraft"]);
        if (expectDraft.Count > 0 && !outcome.Changed)
            problems.Add($"{name}: nothing was written: {outcome.Message}");

        foreach (string title in expectDraft)
        {
            string text = File.ReadAllText(paths[title]);
            if (!PageFrontmatter.IsDraft(text, 1)) problems.Add($"{name}: “{title}” is not hidden for section 1");
            if (Body(text) != Body(before[title])) problems.Add($"{name}: “{title}”'s body changed");
        }
        foreach (string title in Strings(c["expectUntouched"]))
            if (File.ReadAllText(paths[title]) != before[title]) problems.Add($"{name}: “{title}” was changed");
        // Everything not named is not touched either, front page aside.
        foreach (var (title, path) in paths)
        {
            if (expectDraft.Contains(title) || title.StartsWith("Section ", StringComparison.Ordinal)) continue;
            if (File.ReadAllText(path) != before[title] && !Strings(c["expectUntouched"]).Contains(title))
                problems.Add($"{name}: “{title}”, not in the plan, was changed");
        }

        if (c["expectFrontPageEmbeds"] is JsonNode embeds)
        {
            string front = File.ReadAllText(Path.Combine(CourseDir, "section1", "index.md"));
            if (!front.Contains($"![[{embeds}]]", StringComparison.Ordinal))
                problems.Add($"{name}: the front page does not embed “{embeds}”: {front}");
        }

        if (c["runTwice"]?.GetValue<bool>() == true)
        {
            var again = workspace.PlanStartOfYear(Code, 1);
            var snapshot = paths.ToDictionary(p => p.Key, p => File.ReadAllText(p.Value));
            var second = workspace.PrepareForStartOfYear(Code, 1, PlanCodeIn(again.Text), StartOfYearAskedFrom.AnOutsideAssistant);
            string nothing = StartOfYearWording.Fill(StartOfYearWording.NothingToDoTemplate, ("nouns", "classes"),
                ("first", again.Plan.First?.Name ?? ""));
            if (second.Changed || second.Message != nothing) problems.Add($"{name}: the second run said “{second.Message}”");
            if (paths.Any(p => File.ReadAllText(p.Value) != snapshot[p.Key])) problems.Add($"{name}: the second run wrote");
        }
        return problems;
    }

    private static string Body(string text)
    {
        int end = text.IndexOf("\n---\n", 3, StringComparison.Ordinal);
        return end < 0 ? text : text[(end + 5)..];
    }

    // ---- The guarantee and the refusals ----------------------------------

    [Fact]
    public void AWriteWithNoCodeOrAStaleCodeWritesNothing()
    {
        var c = StartOfYearRule["cases"]!.AsArray().First(x => x!["name"]!.ToString() == "the plain year")!;
        var paths = LayOut(c);
        var before = paths.ToDictionary(p => p.Key, p => File.ReadAllText(p.Value));
        var workspace = Workspace();

        var none = workspace.PrepareForStartOfYear(Code, 1, "", StartOfYearAskedFrom.AnOutsideAssistant);
        Assert.False(none.Changed);
        Assert.Equal(AssistWording.StartOfYearNeedsItsPlan(Code, "1"), none.Message);

        string code = PlanCodeIn(workspace.PlanStartOfYear(Code, 1).Text)!;
        File.AppendAllText(paths["Watt"], "\nA teacher's edit.\n");
        before["Watt"] = File.ReadAllText(paths["Watt"]);
        var stale = workspace.PrepareForStartOfYear(Code, 1, code, StartOfYearAskedFrom.AnOutsideAssistant);
        Assert.False(stale.Changed);
        Assert.Equal(AssistWording.StartOfYearPlanHasChanged(Code, "1"), stale.Message);
        Assert.All(paths, p => Assert.Equal(before[p.Key], File.ReadAllText(p.Value)));
    }

    /// <summary>The plan code sits on a line of its own in the fixed shape (planCode.line).</summary>
    [Fact]
    public void ThePlanCodeIsOnALineOfItsOwn()
    {
        Assert.Equal("Plan code: {code}", StartOfYearRule["planCode"]!["line"]!.ToString());
        var c = StartOfYearRule["cases"]!.AsArray().First(x => x!["name"]!.ToString() == "the plain year")!;
        LayOut(c);
        string text = Workspace().PlanStartOfYear(Code, 1).Text;
        Assert.Matches("(?m)^Plan code: [0-9a-f]{8}$", text);
    }

    [Fact]
    public void EverySentenceIsTheContracts()
    {
        var wording = StartOfYearRule["wording"]!.AsObject();
        Assert.Equal(wording.Select(p => p.Key).OrderBy(k => k), StartOfYearWording.ByKey.Keys.OrderBy(k => k));
        foreach (var (key, value) in wording)
            Assert.True(StartOfYearWording.ByKey[key] == value!.ToString(), $"startOfYear.wording.{key} differs");
    }

    /// <summary>An undo puts back what the write wrote and leaves a file changed since, and says so on the trail.</summary>
    [Fact]
    public void UndoPutsBackWhatWasWrittenAndLeavesWhatChangedSince()
    {
        var c = StartOfYearRule["cases"]!.AsArray().First(x => x!["name"]!.ToString() == "the plain year")!;
        var paths = LayOut(c);
        var before = paths.ToDictionary(p => p.Key, p => File.ReadAllText(p.Value));
        var workspace = Workspace();
        var outcome = workspace.PrepareForStartOfYear(Code, 1, PlanCodeIn(workspace.PlanStartOfYear(Code, 1).Text),
            StartOfYearAskedFrom.TheApp, new BackupMaker.Teacher());
        Assert.True(outcome.Changed);
        File.AppendAllText(paths["Joule"], "\nchanged since\n");

        var (putBack, left) = AssistWorkspace.UndoStartOfYear(outcome.Written);
        Assert.Contains(paths["Joule"], left);
        Assert.Equal(before["Watt"], File.ReadAllText(paths["Watt"]));
        Assert.Equal(before["Unit 1, Day 2"], File.ReadAllText(paths["Unit 1, Day 2"]));
        Assert.True(putBack.Count >= 2);
    }

    /// <summary>A scheduled deploy since the act ends the app's undo (startOfYear.undo.app).</summary>
    [Fact]
    public void AScheduledDeployEndsTheAppsUndo()
    {
        var acted = new DateTime(2026, 9, 1, 15, 0, 0);
        var entry = new StartOfYearSessionUndo.Entry(new Dictionary<string, (string, string)>(), "b.zip", "code",
            acted, ScheduledAtTheTime: acted.AddHours(15));
        var moment = acted.AddHours(15);
        Assert.False(StartOfYearSessionUndo.EndedByAScheduledDeploy(entry, acted.AddHours(1), null, scheduledNow: moment));
        Assert.True(StartOfYearSessionUndo.EndedByAScheduledDeploy(entry, acted.AddHours(16), null, scheduledNow: moment));
        var unscheduled = entry with { ScheduledAtTheTime = null };
        Assert.False(StartOfYearSessionUndo.EndedByAScheduledDeploy(unscheduled, acted.AddDays(2), acted.AddHours(-1), null));
        Assert.True(StartOfYearSessionUndo.EndedByAScheduledDeploy(unscheduled, acted.AddDays(2), acted.AddHours(3), null));
    }

    /// <summary>Ruling 2: a scheduled deploy the teacher CANCELLED ends nothing when its moment passes.</summary>
    [Fact]
    public void ACancelledScheduledDeployDoesNotEndTheAppsUndo()
    {
        var acted = new DateTime(2026, 9, 1, 15, 0, 0);
        var entry = new StartOfYearSessionUndo.Entry(new Dictionary<string, (string, string)>(), "b.zip", "code",
            acted, ScheduledAtTheTime: acted.AddHours(15));
        Assert.False(StartOfYearSessionUndo.EndedByAScheduledDeploy(entry, acted.AddHours(16), lastScheduledRun: null, scheduledNow: null));
    }

    // ---- check_section's groups -------------------------------------------

    [Fact]
    public void EverySectionCheckCaseFindsTheContractsGroups()
    {
        var cases = ContractLoader.LoadJson("shared-rules.json")["sectionCheck"]!["cases"]!.AsArray();
        Assert.True(cases.Count >= 7, $"sectionCheck lost cases: {cases.Count} (7 when this was written)");

        var failures = new List<string>();
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            LayOut(c);
            var workspace = Workspace();
            var course = workspace.Course(Code);
            var pages = workspace.StartOfYearPages(course, 1);
            string NameOf(string id) => pages.First(p => string.Equals(p.Id, id, StringComparison.OrdinalIgnoreCase)).Name;

            var missed = SectionCheck.LinkedButMissed(pages).Select(p => p.Name).OrderBy(n => n).ToList();
            var (graph, isHidden) = workspace.Inspect(course, 1);
            var classPages = workspace.ClassPages(course, 1).Select(Path.GetFullPath).ToHashSet(StringComparer.OrdinalIgnoreCase);
            var nowhere = graph.Unreferenced(classPages: classPages).Where(p => !isHidden(p)).Select(NameOf).OrderBy(n => n).ToList();
            var dangling = graph.DanglingLinks(isHidden).Select(l => $"{NameOf(l.From)} → {NameOf(l.To)}").OrderBy(n => n).ToList();

            var expectMissed = Strings(c["expectLinkedButMissed"]).OrderBy(n => n).ToList();
            var expectNowhere = Strings(c["expectLinkedFromNowhere"]).OrderBy(n => n).ToList();
            var expectDangling = c["expectLinksIntoHidden"]!.AsArray()
                .Select(pair => $"{pair![0]} → {pair[1]}").OrderBy(n => n).ToList();
            if (!missed.SequenceEqual(expectMissed)) failures.Add($"{name}: linkedButMissed [{string.Join(", ", missed)}]");
            if (!nowhere.SequenceEqual(expectNowhere)) failures.Add($"{name}: linkedFromNowhere [{string.Join(", ", nowhere)}]");
            if (!dangling.SequenceEqual(expectDangling)) failures.Add($"{name}: linksIntoHiddenPages [{string.Join(", ", dangling)}]");
            if (missed.Intersect(nowhere).Any()) failures.Add($"{name}: a page is in two groups");
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }
}

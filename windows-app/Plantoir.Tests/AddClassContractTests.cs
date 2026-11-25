using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using static Plantoir.Core.Models.SubjectMenuRules;

namespace Plantoir.Tests;

/// <summary>
/// Classes ▸ Add Class… (#927, the mac's #897 piece A), from the contract:
/// <c>shared-rules.json</c> → <c>subjectMenus.addClassSheet</c> (the ways,
/// why each is greyed, which line each is drawn with, the lines under them)
/// and <c>class-planning.json</c> → <c>duplicatingAsTheNextClass</c> (the
/// menu's copy, run through the menu's server). The mac runs the same cases in
/// <c>DuplicateAsNextClassTests</c>.
/// </summary>
public sealed class AddClassContractTests
{
    private static JsonNode Sheet => SubjectMenusContractTests.Rule["addClassSheet"]!;

    private static string Camel(string name) => char.ToLowerInvariant(name[0]) + name[1..];

    private static AddClassFacts FactsOf(JsonNode? facts)
    {
        var defaults = Sheet["factDefaults"]!.AsObject();
        bool Read(string key) => facts?[key]?.GetValue<bool>() ?? defaults[key]!.GetValue<bool>();
        return new AddClassFacts
        {
            ClassPagesAreNumbered = Read("classPagesAreNumbered"),
            UnitWordRenameUnfinished = Read("unitWordRenameUnfinished"),
            HasAClassPage = Read("hasAClassPage"),
        };
    }

    /// <summary>The facts, ways, reasons, labels and lines are the contract's names, both ways.</summary>
    [Fact]
    public void TheNamesAreTheContracts()
    {
        Assert.Equal(Sheet["ways"]!.AsArray().Select(w => w!["way"]!.ToString()),
                     Enum.GetValues<AddClassWay>().Select(w => Camel(w.ToString())));
        Assert.Equal(Sheet["factKeys"]!.AsObject().Select(p => p.Key).OrderBy(k => k),
                     typeof(AddClassFacts).GetProperties().Select(p => Camel(p.Name)).OrderBy(k => k));
        Assert.Equal(Sheet["greyedBecause"]!.AsObject().Select(p => p.Key).OrderBy(k => k),
                     Enum.GetValues<AddClassGreyedBecause>().Select(r => Camel(r.ToString())).OrderBy(k => k));
        Assert.Equal(Sheet["labels"]!.AsObject().Select(p => p.Key).OrderBy(k => k),
                     Enum.GetValues<AddClassLabel>().Select(r => Camel(r.ToString())).OrderBy(k => k));
        Assert.Equal(Sheet["reasonLines"]!.AsObject().Select(p => p.Key).OrderBy(k => k),
                     Enum.GetValues<AddClassReasonLine>().Select(r => Camel(r.ToString())).OrderBy(k => k));
    }

    /// <summary>
    /// Every case: the ways offered, why each other way is greyed, the line
    /// each way is drawn with, and the lines under the ways, in order. MUST
    /// FAIL with the copy's two reasons swapped (case 7), the rename line
    /// naming both ways whatever it holds back (cases 6 and 7), or a club's
    /// new-unit line in the course's word (case 3).
    /// </summary>
    [Fact]
    public void EveryCaseIsDecidedAsTheContractSays()
    {
        var cases = Sheet["cases"]!.AsArray();
        Assert.Equal(8, cases.Count);
        foreach (var c in cases)
        {
            string why = c!["why"]!.ToString();
            var facts = FactsOf(c["facts"]);
            Assert.True(c["ways"]!.AsArray().Select(w => w!.ToString()).SequenceEqual(AddClassWays(facts).Select(w => Camel(w.ToString()))), why);
            var greyed = c["greyed"]!.AsObject().ToDictionary(p => p.Key, p => p.Value!.ToString());
            foreach (var way in Enum.GetValues<AddClassWay>())
            {
                string name = Camel(way.ToString());
                string? expected = greyed.TryGetValue(name, out var reason) ? reason : null;
                Assert.True(expected == (WhyGreyed(way, facts) is { } here ? Camel(here.ToString()) : null), $"{why} ({name} greyed)");
                Assert.True(c["labels"]![name]!.ToString() == Camel(Label(way, facts).ToString()), $"{why} ({name} label)");
            }
            Assert.True(c["reasonLines"]!.AsArray().Select(l => l!.ToString()).SequenceEqual(ReasonLines(facts).Select(l => Camel(l.ToString()))), $"{why} (lines)");
        }
    }

    /// <summary>
    /// Each label and each reason line, drawn with an ordinary course's noun
    /// and word, is the sentence the contract names for it (<c>labels</c>,
    /// <c>reasonLines</c>, <c>greyedBecause</c> → <c>wording.…</c>), and a
    /// club's its <c>ForAMeeting</c> twin where the contract has one. MUST
    /// FAIL with a label mapped to the wrong sentence.
    /// </summary>
    [Fact]
    public void EachLineIsTheSentenceTheContractNames()
    {
        var wording = ContractLoader.LoadJson("assist-wording.json")["wording"]!.AsObject();
        string Said(string reference) => wording[reference["wording.".Length..]]!.ToString();
        string? SaidForAMeeting(string reference) => wording[reference["wording.".Length..] + "ForAMeeting"]?.ToString();
        foreach (var (key, reference) in Sheet["labels"]!.AsObject())
        {
            var label = Enum.GetValues<AddClassLabel>().Single(l => Camel(l.ToString()) == key);
            Assert.Equal(Said(reference!.ToString()), AddClassWords.Label(label, ClassNoun.Class, "unit"));
            if (SaidForAMeeting(reference.ToString()) is { } club)
                Assert.Equal(club, AddClassWords.Label(label, ClassNoun.Meeting, "unit"));
        }
        foreach (var (key, reference) in Sheet["reasonLines"]!.AsObject())
        {
            var line = Enum.GetValues<AddClassReasonLine>().Single(l => Camel(l.ToString()) == key);
            Assert.Equal(Said(reference!.ToString()), AddClassWords.Reason(line, ClassNoun.Class, "unit"));
            if (SaidForAMeeting(reference.ToString()) is { } club)
                Assert.Equal(club, AddClassWords.Reason(line, ClassNoun.Meeting, "unit"));
        }
        // The course's word fills {unit}, lower-cased unless written in capitals.
        Assert.Equal(wording["menuAddClassInANewUnitInAModuleCourse"]!.ToString(),
                     AddClassWords.Label(AddClassLabel.InANewUnitInTheCoursesWord, ClassNoun.Class,
                         SectionVerbs.UnitWordInASentence(new ClassPageNaming("Module", ClassPageScheme.UnitDay))));
        Assert.Equal("PBL", SectionVerbs.UnitWordInASentence(new ClassPageNaming("PBL", ClassPageScheme.UnitDay)));
        Assert.Equal("unit", SectionVerbs.UnitWordInASentence(new ClassPageNaming("Week", ClassPageScheme.Numbered)));
    }

    // ---- The menu's copy, through the menu's server ----------------------------

    private static AssistWorkspace MenuCourse(string folder, JsonNode c)
    {
        var naming = ClassPlanningContractTests.NamingOf(c, "word");
        var timetable = c["timetable"]!.AsArray().Select(d => DateOnly.Parse(d!.ToString())).ToList();
        ClassPlanningContractTests.ScratchCourse(folder, naming, c["existingClasses"]!.AsArray(), timetable);
        string courseDir = Path.Combine(folder, "courses", "ICS3U");
        foreach (var other in c["otherPages"]?.AsArray() ?? new JsonArray())
        {
            string path = Path.Combine(courseDir, other!["path"]!.ToString().Replace('/', Path.DirectorySeparatorChar));
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, $"---\ntitle: {Path.GetFileNameWithoutExtension(path)}\npublish: true\n---\n\n{other["words"]}\n");
        }
        if (c["sourceExtraLines"] is JsonArray extra)
        {
            string source = Path.Combine(courseDir, c["source"]!.ToString().Replace('/', Path.DirectorySeparatorChar));
            string text = File.ReadAllText(source);
            File.WriteAllText(source, text.Replace("publish: true\n", "publish: true\n" + string.Join("\n", extra.Select(l => l!.ToString())) + "\n"));
        }
        return new AssistWorkspace(folder, new FakeLauncher(), undo: new UndoHistory()) { Surface = AssistSurface.Menu };
    }

    private static List<string> Files(string folder) =>
        Directory.GetFiles(Path.Combine(folder, "courses", "ICS3U"), "*.md", SearchOption.AllDirectories)
            .Select(f => f + "\n" + File.ReadAllText(f)).OrderBy(f => f).ToList();

    /// <summary>
    /// <c>duplicatingAsTheNextClass.cases</c>, every one, through the menu's
    /// server (the plan, then the write): the copy's title, date, words and
    /// visibility, that nothing else on disk moved, and a refusal before
    /// anything is written. <c>expectUndoEntries</c> is held by case
    /// (<see cref="NamedGapLedger.MenuCopyUndoEntries"/>): a held case must
    /// still record no entry. MUST FAIL with the copy planned by the
    /// assistant's duplicate (after its source) or a course-level page taken
    /// for the source.
    /// </summary>
    [Fact]
    public void TheMenusCopyIsTheContracts()
    {
        var cases = ContractLoader.LoadJson("class-planning.json")["duplicatingAsTheNextClass"]!["cases"]!.AsArray();
        Assert.Equal(6, cases.Count);
        NamedGapLedger.StillNamed(NamedGapLedger.MenuCopyUndoEntries, cases.Select(c => c!["name"]!.ToString()));
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            string folder = Directory.CreateTempSubdirectory("contract-menu-copy").FullName;
            try
            {
                var workspace = MenuCourse(folder, c);
                var tools = new Plantoir.Mcp.PlantoirTools(workspace);
                string source = c["source"]!.ToString();
                var before = Files(folder);
                var planned = tools.DuplicateAsTheNextClassFromTheMenu("ICS3U", 1, source, planning: true);
                Assert.True(before.SequenceEqual(Files(folder)), $"{name}: the plan wrote something");

                if (c["expectRefused"] is { } refused)
                {
                    Assert.Equal(AssistWording.NoPageCalledFromTheMenu(Path.GetFileNameWithoutExtension(source), "ICS3U", "1"), planned.Summary());
                    Assert.EndsWith(refused.ToString(), "wording.noPageCalledFromTheMenu");
                    var written = tools.DuplicateAsTheNextClassFromTheMenu("ICS3U", 1, source, planning: false);
                    Assert.Equal(planned.Summary(), written.Summary());
                    Assert.True(before.SequenceEqual(Files(folder)), $"{name}: a refusal wrote something");
                    Assert.Equal(c["expectUndoEntries"]!.GetValue<int>(), workspace.History!.Entries.Count);
                    continue;
                }

                string newTitle = c["expectNewTitle"]!.ToString();
                var date = DateOnly.Parse(c["expectDate"]!.ToString());
                string copyOf = c["expectCopyOf"]!.ToString();
                Assert.True(planned.Meta?[AssistToolAnswer.IsPlanKey]?.GetValue<bool>() == true, $"{name}: no plan ({planned.Summary()})");
                Assert.Contains(ClassChangeWording.WouldBeCopiedTo(copyOf, newTitle, date), planned.Summary());

                var made = tools.DuplicateAsTheNextClassFromTheMenu("ICS3U", 1, source, planning: false);
                Assert.Equal(AssistWording.DuplicatedFromTheMenu(copyOf, newTitle, DateText.Iso(date)), made.Summary());
                string copyPath = Path.Combine(folder, "courses", "ICS3U", "section1", "All Classes", newTitle + ".md");
                string copy = File.ReadAllText(copyPath);
                Assert.Contains($"title: {newTitle}", copy);
                Assert.Contains($"created: {DateText.Iso(date)}", copy);
                // ScratchCourse writes each class's title as its body: the source's words came with it.
                Assert.Contains($"\n{copyOf}\n", copy);
                if (c["expectNotCopied"] is { } notCopied) Assert.DoesNotContain(notCopied.ToString(), copy);
                if (c["expectHidden"]?.GetValue<bool>() == true)
                    Assert.Equal(PageVisibility.Hidden, PageFrontmatter.Visibility(copy, 1));
                // The one created file is the whole change.
                var after = Files(folder);
                Assert.True(before.SequenceEqual(after.Where(f => !f.StartsWith(copyPath + "\n"))), $"{name}: something else moved");
                Assert.Equal(before.Count + 1, after.Count);

                int expectedEntries = c["expectUndoEntries"]!.GetValue<int>();
                if (NamedGapLedger.Holding(NamedGapLedger.MenuCopyUndoEntries, name) is not null)
                    Assert.True(workspace.History!.Entries.Count == 0, $"{name} is held as recording no undo entry, and recorded one: delete the entry");
                else
                    Assert.Equal(expectedEntries, workspace.History!.Entries.Count);
            }
            finally { try { Directory.Delete(folder, recursive: true); } catch { } }
        }
    }

    /// <summary>
    /// A page that appears where the copy would go after the plan was shown is
    /// never written over: the plan is made again after the copy of the course
    /// and held to the one shown (#351's plan/write gap), and the page is
    /// left as it is. MUST FAIL with the second plan removed (the write would
    /// then be refused with menuTheNextPageIsAlreadyThere, not this).
    /// </summary>
    [Fact]
    public void APageThatAppearedSinceThePlanIsNeverWrittenOver()
    {
        string folder = Directory.CreateTempSubdirectory("contract-menu-copy-there").FullName;
        try
        {
            var c = JsonNode.Parse("""{"existingClasses":[{"title":"Unit 1, Day 1","date":"2026-09-08"}],"timetable":["2026-09-08","2026-09-10"],"source":"section1/All Classes/Unit 1, Day 1.md"}""")!;
            var workspace = MenuCourse(folder, c);
            var request = workspace.PlanMenuDuplicate("ICS3U", 1, "section1/All Classes/Unit 1, Day 1.md");
            File.WriteAllText(request.NewPath, "a lesson written meanwhile");
            var refusal = Assert.Throws<AssistRefusal>(() => workspace.ApplyMenuDuplicate(request));
            Assert.Equal(AssistWording.ChangedWhileSavingACopyFromTheMenu("ICS3U", "1"), refusal.Message);
            Assert.Equal("a lesson written meanwhile", File.ReadAllText(request.NewPath));
        }
        finally { try { Directory.Delete(folder, recursive: true); } catch { } }
    }

    /// <summary>
    /// An unfinished unit-word rename refuses a copy and a new unit on the
    /// menu, and LEAVES a stale record where it is (<c>clearingAStaleRecord:
    /// false</c>); the window's "Start a new unit" is unchanged. MUST FAIL with
    /// the rename's check made clearing.
    /// </summary>
    [Fact]
    public void ARenameStoppedPartWayHoldsBackANewUnitAndACopy_AndAStaleRecordIsLeftAlone()
    {
        string folder = Directory.CreateTempSubdirectory("contract-menu-copy-rename").FullName;
        try
        {
            var c = JsonNode.Parse("""{"existingClasses":[{"title":"Unit 1, Day 1","date":"2026-09-08"},{"title":"Module 2, Day 1","date":"2026-09-10"}],"timetable":["2026-09-08","2026-09-10","2026-09-12"],"source":"section1/All Classes/Unit 1, Day 1.md"}""")!;
            var workspace = MenuCourse(folder, c);
            string courseDir = Path.Combine(folder, "courses", "ICS3U");
            UnitWordRenamer.RecordRenameStarting("Unit", "Module", courseDir);
            var tools = new Plantoir.Mcp.PlantoirTools(workspace);
            Assert.Equal(AssistWording.MenuUnitWordRenameUnfinished,
                         tools.DuplicateAsTheNextClassFromTheMenu("ICS3U", 1, "section1/All Classes/Unit 1, Day 1.md", planning: true).Summary());
            Assert.Equal(AssistWording.MenuUnitWordRenameUnfinished, tools.AddNextClass("ICS3U", 1, unit: "next").Summary());
            var course = Workspace.DiscoverCourses(folder).Single();
            Assert.True(SectionVerbs.AddClassFacts(course, 1).UnitWordRenameUnfinished);

            // A stale record (nothing named the new way) greys nothing and is LEFT.
            File.Delete(Path.Combine(courseDir, "section1", "All Classes", "Module 2, Day 1.md"));
            Assert.False(SectionVerbs.AddClassFacts(course, 1).UnitWordRenameUnfinished);
            Assert.True(File.Exists(UnitWordRenamer.RenameMarkerPath(courseDir)), "the dialog's check cleared a stale record");
        }
        finally { try { Directory.Delete(folder, recursive: true); } catch { } }
    }

    /// <summary>
    /// The copy is reached only on the menu's server: an outside client that
    /// sends the argument is answered exactly as if it had not (null here, so
    /// the tool runs as before). MUST FAIL with the surface check removed.
    /// </summary>
    [Fact]
    public void OnlyTheMenusServerReadsTheArgument()
    {
        string folder = Directory.CreateTempSubdirectory("contract-menu-copy-outside").FullName;
        try
        {
            var c = JsonNode.Parse("""{"existingClasses":[{"title":"Unit 1, Day 1","date":"2026-09-08"}],"timetable":["2026-09-08","2026-09-10"],"source":"x"}""")!;
            MenuCourse(folder, c);
            var outside = new Plantoir.Mcp.PlantoirTools(new AssistWorkspace(folder, new FakeLauncher()));
            var arguments = new Dictionary<string, JsonElement>
            {
                ["course"] = JsonSerializer.SerializeToElement("ICS3U"),
                ["section"] = JsonSerializer.SerializeToElement(1),
                [AssistWorkspace.MenuDuplicateArgument] = JsonSerializer.SerializeToElement("section1/All Classes/Unit 1, Day 1.md"),
            };
            Assert.Null(outside.FromTheMenuIfACopy("add_next_class", arguments));
            var menu = new Plantoir.Mcp.PlantoirTools(new AssistWorkspace(folder, new FakeLauncher()) { Surface = AssistSurface.Menu });
            Assert.NotNull(menu.FromTheMenuIfACopy("plan_add_next_class", arguments));
            Assert.Null(menu.FromTheMenuIfACopy("publish_pages", arguments));
        }
        finally { try { Directory.Delete(folder, recursive: true); } catch { } }
    }
}

using System.Reflection;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// <c>contracts/shared-rules.json</c> → <c>sectionProblems</c> (#734, the mac's
/// #717): the three case lists run here as the mac runs them, and every list
/// and word this app retypes pinned key by key. The mac's twin is
/// <c>SectionProblemsTests.swift</c>. <c>rowCases</c> are the shared Python's
/// and run through <c>PythonToolchainTests</c>.
/// </summary>
public class SectionProblemsContractTests
{
    private static JsonNode Section() => ContractLoader.LoadJson("shared-rules.json")["sectionProblems"]!;

    private static SectionProblemsRecord Made(string builtAt, IReadOnlyList<SectionProblemRow> rows,
        IReadOnlyList<string>? pagesShown = null, bool siteSaidComplete = true, int section = 1,
        IReadOnlyList<string>? newIds = null, IReadOnlyList<string>? goneIds = null, string alertKey = "B") => new()
    {
        Course = "MPM2D", Section = section, BuildId = "B",
        BuiltAt = DateTimeOffset.Parse(builtAt, System.Globalization.CultureInfo.InvariantCulture),
        Rows = rows, PagesShown = pagesShown ?? Array.Empty<string>(), SiteSaidComplete = siteSaidComplete,
        NewIds = newIds ?? Array.Empty<string>(), GoneIds = goneIds ?? Array.Empty<string>(), AlertKey = alertKey,
    };

    public static IEnumerable<object[]> RowStateCaseNames() =>
        ContractLoader.LoadJson("shared-rules.json")["sectionProblems"]!["rowState"]!["cases"]!.AsArray()
            .Select(c => new object[] { c!["name"]!.ToString() });

    /// <summary>
    /// <c>rowState.cases</c>: a row is "fixed in the source" only when another
    /// section's LATER build shows the page with no problem of that kind on
    /// it — never for a link, a reason about the machine, a page that section
    /// does not show, an older build, or a site-said kind before that
    /// section's site has said.
    /// </summary>
    [Theory]
    [MemberData(nameof(RowStateCaseNames))]
    public void RowStateCases(string name)
    {
        var testCase = Section()["rowState"]!["cases"]!.AsArray().Single(c => c!["name"]!.ToString() == name)!;
        var row = new SectionProblemRow
        {
            Id = "here", Kind = testCase["kind"]!.ToString(), Page = testCase["page"]!.ToString(),
            Reason = testCase["reason"]?.ToString() ?? "",
        };
        var here = Made(testCase["builtAt"]!.ToString(), new[] { row });
        var others = testCase["others"]!.AsArray().Select(other => Made(
            other!["builtAt"]!.ToString(),
            (other["rows"]?.AsArray() ?? new JsonArray()).Select(r => new SectionProblemRow
                { Id = "there", Kind = r!["kind"]!.ToString(), Page = r["page"]!.ToString() }).ToList(),
            pagesShown: other["pagesShown"]!.AsArray().Select(p => p!.ToString()).ToList(),
            siteSaidComplete: other["siteSaidComplete"]?.GetValue<bool>() ?? false,
            section: 2)).ToList();
        Assert.Equal(testCase["expect"]!.ToString(), SectionProblemsRules.ContractName(SectionProblemsRules.State(row, here, others)));
    }

    [Fact]
    public void ThereAreTwelveRowStateCasesAtLeast() =>
        Assert.True(Section()["rowState"]!["cases"]!.AsArray().Count >= 12);

    /// <summary><c>sectionMarker.cases</c>: the warning stays while the section's OWN record has a row, fixed in the source or not.</summary>
    [Fact]
    public void SectionMarkerCases()
    {
        foreach (var testCase in Section()["sectionMarker"]!["cases"]!.AsArray())
        {
            SectionProblemsRecord? made = null;
            if (testCase!["rows"] is JsonArray states)
                made = Made("2026-11-01T09:00:00Z", states.Select((_, index) => new SectionProblemRow
                    { Id = $"row{index}", Kind = "figuresCouldNotBeDrawn", Page = "Unit 1/Graphs" }).ToList());
            Assert.True(SectionProblemsRules.HasMarker(made) == testCase["expect"]!.GetValue<bool>(), testCase["name"]!.ToString());
        }
    }

    /// <summary>
    /// <c>alert.cases</c>, through the answers FILE: "answered" is read back
    /// from disk, as a relaunch (or a second marker of the same build) reads it.
    /// </summary>
    [Fact]
    public void AlertCases()
    {
        string workingFolder = Path.Combine(Path.GetTempPath(), "plantoir-alert-cases-" + Guid.NewGuid().ToString("N")[..8]);
        Directory.CreateDirectory(workingFolder);
        try
        {
            foreach (var testCase in Section()["alert"]!["cases"]!.AsArray())
            {
                string name = testCase!["name"]!.ToString();
                int newCount = testCase["new"]!.GetValue<int>(), goneCount = testCase["gone"]!.GetValue<int>();
                var made = Made("2026-11-01T09:00:00Z", Array.Empty<SectionProblemRow>(),
                    newIds: Enumerable.Range(0, newCount).Select(i => $"figuresCouldNotBeDrawn|p|tikz|k{i}").ToList(),
                    goneIds: Enumerable.Range(0, goneCount).Select(i => $"quizzesNotReady|p|{i}").ToList(),
                    alertKey: "key-" + name);
                IReadOnlySet<string> answered = new HashSet<string>();
                if (testCase["answered"]?.GetValue<bool>() == true)
                {
                    var kept = ProblemsAcknowledgements.Read(workingFolder);
                    kept.RememberAnswered(made.AlertKey, "MPM2D", 1);
                    kept.Write(workingFolder);
                    answered = ProblemsAcknowledgements.Read(workingFolder).Answered("mpm2d", 1);
                }
                Assert.True(SectionProblemsRules.AlertIsDue(made, answered) == testCase["expect"]!.GetValue<bool>(), name);
            }
        }
        finally { try { File.Delete(ProblemsAcknowledgements.PathFor(workingFolder)); Directory.Delete(workingFolder, true); } catch { } }
    }

    /// <summary>The lists retyped in <see cref="SectionProblemsRules"/> and the record's constants are the contract's.</summary>
    [Fact]
    public void TheRulesAreTheContracts()
    {
        var problems = Section();
        var rule = problems["rowState"]!;
        Assert.Equal(rule["clearsAcrossSections"]!.AsArray().Select(k => k!.ToString()).ToHashSet(),
                     SectionProblemsRules.ClearsAcrossSections.ToHashSet());
        var machine = rule["notAboutThePage"]!.AsObject();
        Assert.Equal(machine.Select(p => p.Key).ToHashSet(), SectionProblemsRules.NotAboutThePage.Keys.ToHashSet());
        foreach (var (kind, reasons) in machine)
            Assert.Equal(reasons!.AsArray().Select(r => r!.ToString()).ToHashSet(), SectionProblemsRules.NotAboutThePage[kind].ToHashSet());
        var kinds = problems["kinds"]!.AsArray();
        Assert.Equal(kinds.Where(k => k!["from"]!.ToString() == "site").Select(k => k!["kind"]!.ToString()).ToHashSet(),
                     SectionProblemsRules.SaidByTheSite.ToHashSet());
        Assert.Equal(problems["marker"]!["prefix"]!.ToString(), SectionProblemsMarker.Prefix);
        Assert.Equal(problems["alert"]!["acknowledgedKept"]!.GetValue<int>(), ProblemsAcknowledgements.Kept);
        Assert.Equal(problems["file"]!["name"]!.ToString(), SectionProblemsRecord.FileName);
        Assert.Equal(problems["file"]!["version"]!.GetValue<int>(), SectionProblemsRecord.Version);
    }

    /// <summary>Each kind's label and scope, key by key, and no more.</summary>
    [Fact]
    public void KindsAndScopesAreTheContracts()
    {
        var kinds = Section()["kinds"]!.AsArray();
        Assert.Equal(16, kinds.Count);
        Assert.Equal(kinds.ToDictionary(k => k!["kind"]!.ToString(), k => k!["label"]!.ToString()),
                     SectionProblemsWording.KindLabels.ToDictionary(p => p.Key, p => p.Value));
        Assert.Equal(kinds.ToDictionary(k => k!["kind"]!.ToString(), k => k!["scope"]!.ToString()),
                     SectionProblemsWording.KindScopes.ToDictionary(p => p.Key, p => p.Value));
    }

    /// <summary>Every word, key by key, one constant each, its name the key with a capital — and no more.</summary>
    [Fact]
    public void WordsAreTheContracts()
    {
        var words = Section()["words"]!.AsObject();
        var members = typeof(SectionProblemsWording).GetFields(BindingFlags.Public | BindingFlags.Static)
            .Where(f => f.IsLiteral && f.FieldType == typeof(string))
            .ToDictionary(f => f.Name, f => (string)f.GetValue(null)!);
        Assert.Equal(19, words.Count);
        foreach (var (key, value) in words)
        {
            string name = char.ToUpperInvariant(key[0]) + key[1..];
            Assert.True(members.ContainsKey(name), $"sectionProblems.words.{key} has no constant here.");
            Assert.Equal(value!.ToString(), members[name]);
        }
        Assert.Equal(words.Count, members.Count);
    }

    /// <summary>The fillers say the contract's words with their values in, in one pass.</summary>
    [Fact]
    public void TheFillersSayTheContractsWords()
    {
        var words = Section()["words"]!;
        Assert.Equal(words["alertTitleOne"]!.ToString().Replace("{course}", "MPM2D").Replace("{section}", "1"),
                     SectionProblemsWording.AlertTitle(1, "MPM2D", 1));
        Assert.Equal(words["alertTitleSeveral"]!.ToString().Replace("{count}", "3").Replace("{course}", "MPM2D").Replace("{section}", "2"),
                     SectionProblemsWording.AlertTitle(3, "MPM2D", 2));
        // One pass: a brace inside a VALUE is never read as a placeholder.
        Assert.Equal(words["intro"]!.ToString().Replace("{section}", "4").Replace("{course}", "A{section}B"),
                     SectionProblemsWording.IntroFor("A{section}B", 4));
        var one = new SectionProblemRow { Id = "x", Kind = "mediaFolderMissing", Sentence = "The Media folder is missing." };
        Assert.Equal(new[] { "The Media folder is missing.", SectionProblemsWording.AlertMessage, SectionProblemsWording.AlertAlsoGoneOne },
                     SectionProblemsWording.AlertParagraphs(new[] { one }, 1));
        Assert.Equal(new[] { SectionProblemsWording.AlertMessage, words["alertAlsoGoneSeveral"]!.ToString().Replace("{count}", "2") },
                     SectionProblemsWording.AlertParagraphs(new[] { one, one }, 2));
    }

    /// <summary>
    /// The order a teacher sees (today's class, the alert, the checklist) and
    /// the bound that keeps the checklist from waiting for ever on an alert
    /// that is due but not up here (#734 review, finding 1).
    /// </summary>
    [Theory]
    [InlineData(false, false, false, 0, false)]   // nothing in front: shown
    [InlineData(true, false, false, 0, true)]     // the alert (or a repair's outcome) on screen here
    [InlineData(true, false, true, 600, true)]    // ... however long the teacher reads it
    [InlineData(false, true, false, 0, true)]     // today's-class question first
    [InlineData(false, false, true, 0, true)]     // the alert is due: it comes first
    [InlineData(false, false, true, 9, true)]
    [InlineData(false, false, true, 10, false)]   // due but never up here: not for ever
    [InlineData(false, false, true, 3600, false)]
    public void TheChecklistFollowsTheAlert_ButNeverWaitsForEver(bool dialogUp, bool todaysClassUp, bool alertDue, int seconds, bool waits) =>
        Assert.Equal(waits, SectionProblemsRules.TheChecklistWaits(dialogUp, todaysClassUp, alertDue, TimeSpan.FromSeconds(seconds)));

    /// <summary>
    /// The contract says the checklist FOLLOWS the alert; the rule's order is
    /// that sentence, not a choice of this app's.
    /// </summary>
    [Fact]
    public void TheContractPutsTheChecklistAfterTheAlert() =>
        Assert.Contains("The links checklist (#379) follows it.", Section()["alert"]!["rule"]!.ToString());

    /// <summary>
    /// The app's read stands in a launcher's way as little as Windows allows
    /// (#734 review, finding 2). MEASURED on this PC: os.replace (and .NET's
    /// overwriting move) is refused while ANY handle has the file open, delete
    /// sharing or not — so sharing cannot fix it, and the shared Python
    /// retries a refused replace instead (<c>section_problems._write</c>,
    /// <c>test_a_record_a_reader_holds_open_is_replaced_once_the_reader_lets_go</c>).
    /// What the app owes, pinned here: its open shares DELETE, so an archive
    /// or a discarded build can remove the section's folder under a read; and
    /// a read has let go of the file by the time it returns.
    /// </summary>
    [Fact]
    public void TheAppsReadSharesDeleteAndLetsGoBeforeItReturns()
    {
        string folder = Path.Combine(Path.GetTempPath(), "plantoir-record-share-" + Guid.NewGuid().ToString("N")[..8]);
        Directory.CreateDirectory(folder);
        try
        {
            string path = Path.Combine(folder, SectionProblemsRecord.FileName);
            File.WriteAllText(path, RecordJson);
            using (SectionProblemsRecord.OpenShared(path))
                File.Delete(path);   // refused with read-only sharing
            File.WriteAllText(path, RecordJson);
            Assert.NotNull(SectionProblemsRecord.Read(path));
            string script = Path.Combine(folder, "replace.py");
            File.WriteAllText(script, "import os, sys\nopen(sys.argv[1] + '.py', 'w').write('{}')\nos.replace(sys.argv[1] + '.py', sys.argv[1])\n");
            var python = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("python", $"\"{script}\" \"{path}\"")
                { UseShellExecute = false, RedirectStandardError = true, CreateNoWindow = true })!;
            string error = python.StandardError.ReadToEnd();
            python.WaitForExit(30000);
            Assert.True(python.ExitCode == 0, "os.replace was refused after the app's read returned: " + error);
            Assert.Equal("{}", File.ReadAllText(path));
        }
        finally { try { Directory.Delete(folder, true); } catch { } }
    }

    /// <summary>Rule 1: nothing the tab, the marker or the alert says names the machinery.</summary>
    [Fact]
    public void NoWordNamesTheMachinery()
    {
        var texts = Section()["words"]!.AsObject().Select(p => p.Value!.ToString())
            .Concat(SectionProblemsWording.KindLabels.Values);
        foreach (string text in texts)
            foreach (string word in new[] { "script", "Docker", "container", "toolchain", "Python", "JSON", "marker", "record", "launcher" })
                Assert.False(text.Contains(word, StringComparison.OrdinalIgnoreCase), $"{word} in: {text}");
    }

    /// <summary>The trail's line names kinds once each, in the order met, and never a page.</summary>
    [Fact]
    public void TheTrailLineNamesKindsOnceAndNeverAPage()
    {
        var read = SectionProblemsRecord.Parse(RecordJson)!;
        string line = SectionProblemsRules.TrailLine(read);
        Assert.Equal("the preview found 1 new and 1 fewer problems (new: figuresCouldNotBeDrawn; gone: quizzesNotReady)", line);
        Assert.DoesNotContain("Unit 1", line);
        Assert.Equal("figuresCouldNotBeDrawn, quizzesNotReady",
                     SectionProblemsRules.KindsNamed(new[] { "figuresCouldNotBeDrawn|a", "quizzesNotReady|b|#2", "figuresCouldNotBeDrawn|c" }));
        Assert.Equal("none", SectionProblemsRules.KindsNamed(Array.Empty<string>()));
        Assert.Equal("answered the alert about new problems: Not Now", SectionProblemsRules.AnswerLine(SectionProblemsRules.AnsweredNotNow));
        // The contract's line template, with its {course}/{section} · front
        // that ActivityTrail.Note writes on every line here.
        string template = ContractLoader.LoadJson("shared-rules.json")["activityTrail"]!["mustRecord"]!.AsArray()
            .Single(e => e!["event"]!.ToString() == ActivityTrail.KeyFor(ActivityTrail.Event.ProblemsChanged))!["line"]!.ToString();
        Assert.StartsWith("{course}/{section} · the {occasion} found {new} new and {gone} fewer problems (new: {kinds}; gone: {kinds})", template);
    }

    /// <summary>The marker the contract's example prints, read from its prefix onward — glued behind half a line too — and kept out of the console.</summary>
    [Fact]
    public void TheMarkerIsReadFromItsPrefixOnward()
    {
        string example = Section()["marker"]!["examples"]!.AsArray()[0]!.ToString();
        var read = SectionProblemsMarker.Parse("Building…" + example);
        Assert.NotNull(read);
        Assert.Equal(("MPM2D", 1, 3, 1, 0), (read!.Course, read.Section, read.Rows, read.New, read.Gone));
        Assert.Equal("20261101T130000Z-1a2b3c4d", read.AlertKey);
        Assert.True(TranscriptBuilder.IsMachineLine(example), "the marker is kept out of the console");
        var dispatched = BuildMachineLines.Record(example);
        Assert.True(dispatched.WasMachineLine);
        Assert.Equal(read, dispatched.Problems);
        Assert.Null(SectionProblemsMarker.Parse("PLANTOIR_PROBLEMS: {not json"));
        Assert.Null(SectionProblemsMarker.Parse("PLANTOIR_PROBLEMS: {\"course\": \"X\"}"));
    }

    /// <summary>A record in the shape <c>scripts/section_problems.py</c> writes is read whole; another version, or nonsense, is no record.</summary>
    [Fact]
    public void TheRecordIsReadAsTheBuildWritesIt()
    {
        var read = SectionProblemsRecord.Parse(RecordJson)!;
        Assert.Equal(("MPM2D", 1, "preview", 2), (read.Course, read.Section, read.Occasion, read.Rows.Count));
        Assert.Equal("figuresCouldNotBeDrawn", read.Rows[0].Kind);
        Assert.Equal("Unit 1/Graphs", read.Rows[0].Page);
        Assert.Equal("deploy", read.Rows[1].From);
        Assert.True(read.Rows[1].Carried);
        Assert.NotNull(read.Rows[0].FirstSeen);
        Assert.Equal(new[] { "figuresCouldNotBeDrawn|Unit 1/Graphs|tikz|k1" }, read.NewIds);
        Assert.Equal("B2", read.AlertKey);
        Assert.Equal(SectionProblemsWording.WholeSection, SectionProblemsWording.PageColumn(read.Rows[1]));
        Assert.Equal(SectionProblemsWording.WholeCourse, SectionProblemsWording.PageColumn(new SectionProblemRow { Id = "mediaFolderMissing", Kind = "mediaFolderMissing" }));
        Assert.Null(SectionProblemsRecord.Parse(RecordJson.Replace("\"version\": 1", "\"version\": 2")));
        Assert.Null(SectionProblemsRecord.Parse("{not"));
        Assert.Null(SectionProblemsRecord.Parse(""));
        Assert.Equal("quizzesNotReady", SectionProblemsRecord.KindOfId("quizzesNotReady|Unit 1/Quiz|#2"));
        Assert.Equal("mediaFolderMissing", SectionProblemsRecord.KindOfId("mediaFolderMissing"));
    }

    /// <summary>
    /// The page and course names a teacher can type are shown as written: a
    /// cmd metacharacter, a quote or a newline in a page's place reaches the
    /// table's columns unchanged (review change 8; handing such text to a
    /// terminal is #736's).
    /// </summary>
    [Fact]
    public void AnAwkwardPageNameIsShownAsWritten()
    {
        string awkward = "Unit 1/50% & more | <yes> ^ \"quoted\"; x\ny";
        var row = new SectionProblemRow { Id = "pageSettingsUnreadable|" + awkward, Kind = "pageSettingsUnreadable", Page = awkward, Item = "“" + awkward + "”" };
        Assert.Equal(awkward, SectionProblemsWording.PageColumn(row));
        Assert.Equal("“" + awkward + "”", SectionProblemsWording.ProblemColumn(row, SectionProblemsRules.RowState.Current));
        Assert.Contains("50% & more Section 1", SectionProblemsWording.IntroFor("50% & more", 1));
    }

    internal const string RecordJson = """
    {"version": 1, "course": "MPM2D", "section": 1, "buildId": "B2", "builtAt": "2026-11-01T13:00:00Z",
     "occasion": "preview", "pagesShown": ["Unit 1/Graphs"], "before": ["quizzesNotReady|Unit 1/Quiz|"],
     "siteSaidComplete": true, "alertKey": "B2",
     "changed": {"new": ["figuresCouldNotBeDrawn|Unit 1/Graphs|tikz|k1"], "gone": ["quizzesNotReady|Unit 1/Quiz|"]},
     "rows": [
      {"id": "figuresCouldNotBeDrawn|Unit 1/Graphs|tikz|k1", "kind": "figuresCouldNotBeDrawn", "page": "Unit 1/Graphs",
       "reason": "undefinedCommand", "item": "“Unit 1/Graphs”, diagram 2, line 14: \\foo isn't a command LaTeX knows here",
       "sentence": "A diagram or graph on “Unit 1/Graphs” in MPM2D Section 1 could not be drawn.", "detail": "d",
       "fixable": false, "prompt": "p", "from": "build", "firstSeen": "2026-11-01T13:00:00Z", "lastSeen": "2026-11-01T13:00:00Z"},
      {"id": "filesTooLargeForCloudflare|Media/talk.mp4", "kind": "filesTooLargeForCloudflare", "page": "",
       "reason": "", "item": "Media/talk.mp4 (40.0 MB)", "sentence": "s", "detail": "d", "fixable": false, "prompt": "p",
       "from": "deploy", "carried": true, "firstSeen": "2026-10-30T08:00:00Z", "lastSeen": "2026-10-30T08:00:00Z"}
     ]}
    """;
}

using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json.Nodes;
using ModelContextProtocol.Protocol;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Plantoir.Mcp;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The How I Teach page from the outside door (#340, mac #209), against
/// <c>contracts/shared-rules.json</c> → <c>howITeachPage</c> — the cases are
/// DESERIALISED, never retyped. The mac's counterpart is <c>HowITeachTests</c>.
/// </summary>
[Collection(SharedActivityState.Name)]
public class HowITeachTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-howiteach").FullName;
    private readonly string _trail = Path.Combine(Path.GetTempPath(), "plantoir-tests",
        "howiteach-" + Guid.NewGuid().ToString("N") + ".txt");
    private readonly UndoHistory _undo = new();
    private static readonly JsonObject Rule = (JsonObject)ContractLoader.LoadJson("shared-rules.json")["howITeachPage"]!;
    private static readonly JsonObject Wording = (JsonObject)ContractLoader.LoadJson("assist-wording.json")["wording"]!;

    public HowITeachTests()
    {
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        string course = CourseDirectory;
        Directory.CreateDirectory(Path.Combine(course, "section1", "All Classes"));
        File.WriteAllText(Path.Combine(course, "course_config.json"),
            """
            { "course_code": "ICS3U", "course_name": "Computer Science", "deploy_target": "netlify",
              "num_sections": 1, "per_section_folders": ["All Classes"], "section_numbers": [1] }
            """);
        File.WriteAllText(Path.Combine(course, "section1", "All Classes", "Unit 1, Day 1.md"), "---\npublish: false\n---\nHi\n");
        Directory.CreateDirectory(Path.GetDirectoryName(_trail)!);
        ActivityTrail.SetCustomLogPathForTesting(_trail);
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { Directory.Delete(_folder, recursive: true); } catch { }
        try { File.Delete(_trail); } catch { }
        GC.SuppressFinalize(this);
    }

    private string CourseDirectory => Path.Combine(_folder, "courses", "ICS3U");
    private string PagePath => Path.Combine(CourseDirectory, HowITeachPage.FileName);
    private AssistWorkspace Open() => new(_folder, new FakeLauncher(), undo: _undo);
    private string Trail => File.Exists(_trail) ? File.ReadAllText(_trail) : "";

    // ---- The name ---------------------------------------------------------

    [Fact]
    public void EveryNameCaseIsReservedAndListedAsTheContractSays()
    {
        foreach (var c in Rule["nameCases"]!.AsArray())
        {
            string path = c!["path"]!.ToString();
            Assert.True(c["reserved"]!.GetValue<bool>() == HowITeachPage.IsAtAReservedPlace(path), $"reserved: {path}");

            string full = Path.Combine(CourseDirectory, path.Replace('/', Path.DirectorySeparatorChar));
            Directory.CreateDirectory(Path.GetDirectoryName(full)!);
            File.WriteAllText(full, "Mine.\n");
            bool listed = Open().Pages(Open().Course("ICS3U"), 1)
                .Any(p => string.Equals(p, Path.GetRelativePath(_folder, full).Replace('\\', '/'), StringComparison.Ordinal));
            File.Delete(full);
            Assert.True(c["listedAsAPage"]!.GetValue<bool>() == listed, $"listedAsAPage: {path}");
        }
    }

    [Fact]
    public void TheMarkIsHashedFromTheBytesOnDiskByteOrderMarkIncluded()
    {
        foreach (var c in Rule["tools"]!["markCases"]!.AsArray())
        {
            byte[] bytes = Encoding.UTF8.GetBytes(c!["text"]!.ToString());
            if (c["startsWithAByteOrderMark"]?.GetValue<bool>() == true)
                bytes = new byte[] { 0xEF, 0xBB, 0xBF }.Concat(bytes).ToArray();
            Assert.Equal(c["mark"]!.ToString(), HowITeachPage.MarkOf(bytes));
        }
    }

    // ---- Writing ----------------------------------------------------------

    [Fact]
    public void ANewPageIsWrittenAsTheContractsBytes()
    {
        Open().WriteHowITeach("ICS3U", "  I teach by asking first.  ", "");
        string expected = Rule["tools"]!["newPageBytes"]!.ToString()
            .Replace("\\n", "\n").Replace("<text>", "I teach by asking first.");
        Assert.Equal(expected, File.ReadAllText(PagePath));
    }

    [Fact]
    public void EveryEmptyPageCaseIsFilledWithoutAMarkAndAWrittenOneIsRefused()
    {
        var empty = (JsonObject)Rule["emptyPageIsNotWritten"]!;
        string words = empty["writeText"]!.ToString();
        foreach (var c in empty["cases"]!.AsArray())
        {
            File.WriteAllText(PagePath, c!["text"]!.ToString(), new UTF8Encoding(false));
            if (c["written"]!.GetValue<bool>())
            {
                var refusal = Assert.Throws<AssistRefusal>(() => Open().WriteHowITeach("ICS3U", words, ""));
                Assert.Equal(AssistWording.HowITeachAlreadyWritten("ICS3U"), refusal.Message);
            }
            else
            {
                Assert.Contains("would save a new How I Teach page", Open().PlanWriteHowITeach("ICS3U", words, ""));
                Open().WriteHowITeach("ICS3U", words, "");
                Assert.Equal(c["afterWrite"]!.ToString(),
                             HowITeachPage.TextOf(File.ReadAllBytes(PagePath)));
            }
            File.Delete(PagePath);
        }
    }

    [Theory]
    [InlineData("---\r\ntitle: Mine\r\npublish: false\r\n---\r\nOld words here.\r\n", true,
                "---\r\ntitle: Mine\r\npublish: false\r\n---\r\n\r\nNew.\r\n")]
    [InlineData("---\ntitle: Mine\n---\nOld words.\n", false, "---\ntitle: Mine\n---\n\nNew.\n")]
    [InlineData("---\nnever closed\nOld words.\n", false, "New.\n")]
    public void AReplacedPageKeepsItsSettingsByteForByte(string existing, bool byteOrderMark, string expected)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(existing);
        if (byteOrderMark) bytes = new byte[] { 0xEF, 0xBB, 0xBF }.Concat(bytes).ToArray();
        File.WriteAllBytes(PagePath, bytes);
        string mark = HowITeachPage.MarkOf(bytes);

        Assert.Contains($"replacing: “{mark}”", Open().PlanWriteHowITeach("ICS3U", "New.", ""));
        Open().WriteHowITeach("ICS3U", "New.", mark.ToUpperInvariant());

        byte[] after = File.ReadAllBytes(PagePath);
        byte[] want = Encoding.UTF8.GetBytes(expected);
        if (byteOrderMark) want = new byte[] { 0xEF, 0xBB, 0xBF }.Concat(want).ToArray();
        Assert.Equal(want, after);
    }

    [Fact]
    public void ThePlanAndTheWriteRefuseTheSameThings()
    {
        File.WriteAllText(PagePath, "My own words.\n");
        foreach (var (text, replacing, said) in new[]
                 {
                     ("   ", "", AssistWording.HowITeachNeedsWords),
                     (new string('a', HowITeachPage.MostCharacters + 1), "", AssistWording.HowITeachTooLong),
                     ("﻿\n\n---\npublish: true\n---\nHi", "", AssistWording.HowITeachCarriesNoSettings),
                     ("New.", "deadbeef", AssistWording.HowITeachChangedSincePlanned("ICS3U")),
                 })
        {
            Assert.Equal(said, Assert.Throws<AssistRefusal>(() => Open().PlanWriteHowITeach("ICS3U", text, replacing)).Message);
            Assert.Equal(said, Assert.Throws<AssistRefusal>(() => Open().WriteHowITeach("ICS3U", text, replacing)).Message);
        }
        Assert.Equal("My own words.\n", File.ReadAllText(PagePath));
    }

    [Fact]
    public void TheTeachersOwnSpellingIsWhatIsReplaced()
    {
        string own = Path.Combine(CourseDirectory, "how i teach.md");
        File.WriteAllText(own, "Mine.\n");
        Open().WriteHowITeach("ICS3U", "New.", HowITeachPage.MarkOf(File.ReadAllBytes(own)));
        Assert.Equal(new[] { "how i teach.md" },
            Directory.GetFiles(CourseDirectory, "*.md").Select(Path.GetFileName).ToArray());
        Assert.Equal("New.\n", File.ReadAllText(own));
    }

    [Fact]
    public void OneUndoEntryTakesTheWriteBackAndTheTrailCarriesNoWords()
    {
        var workspace = Open();
        workspace.WriteHowITeach("ICS3U", "Secret pedagogy words.", "");
        Assert.Single(_undo.Entries);
        Assert.Equal("wrote a new How I Teach page", _undo.Entries[0].Description);
        Assert.True(_undo.Undo().Succeeded);
        Assert.False(File.Exists(PagePath));

        Assert.Contains("an outside assistant wrote a new How I Teach page (3 words), after backing up the course as", Trail);
        Assert.DoesNotContain("Secret", Trail);
    }

    // ---- Reading ----------------------------------------------------------

    [Fact]
    public void ReadingAnswersEachShapeAndRecordsCountsNotWords()
    {
        var workspace = Open();
        Assert.Equal(AssistWording.HowITeachMissing("ICS3U") + "\n\n" + AssistWording.HowITeachDraftingBrief,
                     workspace.ReadHowITeach("ICS3U"));
        File.WriteAllText(PagePath, HowITeachPage.NewPageSettings);
        Assert.StartsWith(AssistWording.HowITeachEmpty("ICS3U"), workspace.ReadHowITeach("ICS3U"));
        File.WriteAllText(PagePath, "---\npublish: false\n---\nPrivate classroom words.\n");
        Assert.Equal(AssistWording.HowITeachRead("ICS3U", "Private classroom words."), workspace.ReadHowITeach("ICS3U"));
        File.WriteAllText(PagePath, new string('w', HowITeachPage.MostCharacters + 10));
        Assert.Contains(AssistWording.HowITeachCutShort("ICS3U", "courses/ICS3U/How I Teach.md"), workspace.ReadHowITeach("ICS3U"));

        string trail = Trail;
        Assert.Contains("an outside assistant found no How I Teach page yet", trail);
        Assert.Contains("an outside assistant found an empty How I Teach page", trail);
        Assert.Contains("an outside assistant read the How I Teach page (3 words)", trail);
        Assert.Contains("more than one answer carries", trail);
        Assert.DoesNotContain("Private", trail);
    }

    // ---- Never published, never listed -----------------------------------

    [Fact]
    public void AskedToPublishItByNameTheAnswerIsThatItIsNeverPublished()
    {
        File.WriteAllText(PagePath, "Mine.\n");
        var workspace = Open();
        var plan = workspace.PlanPublish("ICS3U", 1, new[] { "how i teach" }, draft: false);
        Assert.Contains(AssistWording.HowITeachIsNeverPublished("ICS3U"), plan.Problems);
        Assert.Empty(plan.UnknownNames);
        Assert.Equal(AssistWording.HowITeachIsNeverPublished("ICS3U"),
            Assert.Throws<AssistRefusal>(() => workspace.Page(workspace.Course("ICS3U"), 1, "How I Teach")).Message);
    }

    [Fact]
    public void ListCoursesCarriesTheLineToAnOutsideDoorOnly()
    {
        string outside = new PlantoirTools(Open()).ListCourses();
        Assert.Contains(AssistWording.HowITeachListedAsNotWritten, outside);
        File.WriteAllText(PagePath, "Words.\n");
        Assert.Contains(AssistWording.HowITeachListedAsWritten, new PlantoirTools(Open()).ListCourses());

        var window = new AssistWorkspace(_folder, new FakeLauncher()) { ServesTheLocalWindow = true };
        Assert.DoesNotContain("How I Teach", new PlantoirTools(window).ListCourses());
    }

    [Fact]
    public void ThePlanIsMarkedAsAPlanAndARefusalIsNot()
    {
        var tools = new PlantoirTools(Open());
        Assert.True(new AssistToolAnswerProbe(tools.PlanWriteHowITeach("ICS3U", "Words.")).IsPlan);
        Assert.False(new AssistToolAnswerProbe(tools.PlanWriteHowITeach("ICS3U", "")).IsPlan);
    }

    private sealed record AssistToolAnswerProbe(CallToolResult Result)
    {
        public bool IsPlan => Result.Meta?[AssistToolAnswer.IsPlanKey]?.GetValue<bool>() == true;
    }

    // ---- The build's marker ----------------------------------------------

    [Fact]
    public void TheKeptOffMarkerIsReadAndKeptOutOfTheConsole()
    {
        string line = Rule["keptOffMarker"]!["examples"]![0]!.ToString();
        var report = HowITeachKeptOffReport.Parse("progress… " + line);
        Assert.NotNull(report);
        Assert.Equal("the build kept 1 page named How I Teach off the website that the course's settings had listed for it: How I Teach",
                     report!.TrailSentence);
        Assert.Equal(Rule["keptOffMarker"]!["prefix"]!.ToString(), HowITeachKeptOffReport.Marker);

        var transcript = new TranscriptBuilder();
        transcript.Append("Building\n" + line + "\nDone\n");
        Assert.DoesNotContain("PLANTOIR_KEPT_OFF", transcript.DisplayText);
    }

    // ---- Words ------------------------------------------------------------

    [Fact]
    public void TheSentencesWithValuesAreTheContractsOwn()
    {
        void Same(string key, string here) => Assert.Equal(Wording[key]!.ToString(), here);
        Same("howITeachAlreadyWritten", AssistWording.HowITeachAlreadyWritten("{course}"));
        Same("howITeachBriefing", AssistWording.HowITeachBriefing("{course}"));
        Same("howITeachChangedSincePlanned", AssistWording.HowITeachChangedSincePlanned("{course}"));
        Same("howITeachCutShort", AssistWording.HowITeachCutShort("{course}", "{path}"));
        Same("howITeachEmpty", AssistWording.HowITeachEmpty("{course}"));
        Same("howITeachIsNeverPublished", AssistWording.HowITeachIsNeverPublished("{course}"));
        Same("howITeachMissing", AssistWording.HowITeachMissing("{course}"));
        Same("howITeachPlanCreates", AssistWording.HowITeachPlanCreates("{course}", "{path}"));
        Same("howITeachPlanReplaces", AssistWording.HowITeachPlanReplaces("{course}", "{path}", "{words}", "{changed}", "{mark}"));
        Same("howITeachRead", AssistWording.HowITeachRead("{course}", "{text}"));
        Same("howITeachSaved", AssistWording.HowITeachSaved("{course}"));
    }

    [Fact]
    public void TheClaudeDoorAsksForThePageVerbatimAfterListingTheSections()
    {
        string sentence = ContractLoader.LoadJson("app-rules.json")["outsideAgents"]!["greetingHowITeachSentence"]!.ToString();
        string greeting = ClaudeCodeLauncher.Greeting("ICS3U", "Computer Science");
        Assert.Contains(sentence, greeting);
        Assert.True(greeting.IndexOf("Start by listing its sections", StringComparison.Ordinal) <
                    greeting.IndexOf(sentence, StringComparison.Ordinal));
    }
}

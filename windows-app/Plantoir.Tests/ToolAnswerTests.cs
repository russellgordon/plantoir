using System.Text.Json;
using ModelContextProtocol;
using ModelContextProtocol.Protocol;
using Plantoir.Core.Assist;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// What a TEACHER reads when a tool finishes, as against what the model is
/// handed.
///
/// These exist because the two used to be one string, and the consequence was
/// not subtle: "read Unit 2, Day 3" put a lesson's entire Markdown into the
/// chat window, "what pages are in this section" put sixty file paths there,
/// and a plan ended with a sentence addressed to the model. macOS has always
/// kept the two apart — <c>AssistToolOutcome</c> — and its replies are short
/// for that one reason. Each case below pins a teacher's line against the
/// wording the mac uses for the same request.
/// </summary>
public class ToolAnswerTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-answers").FullName;
    private readonly FakeLauncher _launcher = new();

    public ToolAnswerTests()
    {
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");

        string directory = Path.Combine(_folder, "courses", "ICS3U");
        Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory, "course_config.json"),
            """
            {
              "course_code": "ICS3U",
              "course_name": "Introduction to Computer Science",
              "deploy_target": "netlify",
              "num_sections": 1,
              "per_section_folders": ["All Classes"],
              "per_section_files": ["Key Links.md"],
              "section_numbers": [1]
            }
            """);
        string sites = Path.Combine(directory, ".netlify_sites");
        Directory.CreateDirectory(sites);
        File.WriteAllText(Path.Combine(sites, "section1.json"), """{"name": "ics3u-s1-2026-gordon"}""");

        Class("Unit 1, Day 1", "2026-09-08");
        Class("Unit 1, Day 2", "2026-09-10");
        Class("Unit 1, Day 3", "2026-09-14");
    }

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
        GC.SuppressFinalize(this);
    }

    private void Class(string title, string date)
    {
        string full = Path.Combine(_folder, "courses", "ICS3U", "section1", "All Classes", title + ".md");
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        File.WriteAllText(full,
            $"---\ndraft: true\ncreated: {date}T07:00:00.000-0400\n---\nBody of {title}.\n");
    }

    private Plantoir.Mcp.PlantoirTools Tools() => new(new AssistWorkspace(_folder, _launcher));

    // ---- The channel itself ----------------------------------------------

    /// <summary>
    /// The load-bearing assumption, checked rather than believed: the summary
    /// leaves the server under <c>_meta</c>, at the exact key
    /// <c>McpClient</c> reaches for. Everything else here is wording; if this
    /// breaks, every teacher-facing line silently reverts to the model's.
    /// </summary>
    [Fact]
    public void TheTeachersLineTravelsInMetaWhereTheAppLooksForIt()
    {
        var answer = Tools().ReadPage("ICS3U", 1, "Unit 1, Day 2");
        string wire = JsonSerializer.Serialize(answer, McpJsonUtilities.DefaultOptions);

        using var parsed = JsonDocument.Parse(wire);
        Assert.True(parsed.RootElement.TryGetProperty("_meta", out var meta),
            "the result must carry _meta, or the app reads the model's half");
        Assert.Equal("Read “Unit 1, Day 2”.",
            meta.GetProperty(AssistToolAnswer.TeacherSummaryKey).GetString());
    }

    /// <summary>
    /// Claude Code reads the TEXT and is meant to be untouched by any of
    /// this. The detail is the whole page, exactly as it was before the split
    /// existed.
    /// </summary>
    [Fact]
    public void TheModelStillGetsTheWholeAnswer()
    {
        Assert.Contains("Body of Unit 1, Day 2.", Tools().ReadPage("ICS3U", 1, "Unit 1, Day 2").Detail());
    }

    /// <summary>
    /// A tool that says the same thing to both sends no <c>_meta</c> — and
    /// the absence is what the client reads as "show what you were given".
    /// Every refusal is of this shape: the reason IS the answer.
    /// </summary>
    [Fact]
    public void AToolThatSaysOneThingToBothSendsNoSummary()
    {
        var workspace = new AssistWorkspace(_folder, _launcher, undo: new UndoHistory());
        var answer = new Plantoir.Mcp.PlantoirTools(workspace).UndoLastChange();

        Assert.Null(answer.Meta);
        Assert.Equal(answer.Detail(), answer.Summary());
    }

    // ---- Looking around ---------------------------------------------------

    [Fact]
    public void ReadingAPageTellsTheTeacherItsName_NotItsContents()
    {
        var answer = Tools().ReadPage("ICS3U", 1, "Unit 1, Day 2");
        Assert.Equal("Read “Unit 1, Day 2”.", answer.Summary());
        Assert.DoesNotContain("Body of", answer.Summary());
    }

    [Fact]
    public void ListingPagesTellsTheTeacherHowMany_NotWhichFiles()
    {
        var answer = Tools().ListPages("ICS3U", 1, matching: "Unit 1");
        Assert.Equal("Found 3 pages in ICS3U Section 1.", answer.Summary());
        // The paths are the model's half, so it can pick the one meant.
        Assert.Contains("Unit 1, Day 2", answer.Detail());
    }

    [Fact]
    public void OnePageIsCountedInTheSingular()
    {
        Assert.Equal("Found 1 page in ICS3U Section 1.",
            Tools().ListPages("ICS3U", 1, matching: "Day 3").Summary());
    }

    [Fact]
    public void NothingMatchingIsOneLine_WithTheReasonForTheModel()
    {
        var answer = Tools().ListPages("ICS3U", 1, matching: "Unit 9");
        Assert.Equal("Nothing matched in ICS3U Section 1.", answer.Summary());
        Assert.Contains("Unit 9", answer.Detail());
    }

    // ---- Writing ----------------------------------------------------------

    [Fact]
    public async Task PublishingTellsTheTeacherACount_NotEveryPageAndThePreview()
    {
        var answer = await Tools().PublishPages("ICS3U", 1, includeLinked: false,
            progress: new Progress<ProgressNotificationValue>(), cancellation: default,
            pages: new[] { "Unit 1, Day 2" });

        Assert.Equal("Published 1 page.", answer.Summary());
        Assert.DoesNotContain("preview", answer.Summary(), StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task UnpublishingSaysSoInItsOwnVerb()
    {
        var tools = Tools();
        await tools.PublishPages("ICS3U", 1, includeLinked: false,
            progress: new Progress<ProgressNotificationValue>(), cancellation: default,
            pages: new[] { "Unit 1, Day 1", "Unit 1, Day 2" });

        var answer = await tools.UnpublishPages("ICS3U", 1, includeLinked: false,
            progress: new Progress<ProgressNotificationValue>(), cancellation: default,
            pages: new[] { "Unit 1, Day 1", "Unit 1, Day 2" });

        Assert.Equal("Unpublished 2 pages.", answer.Summary());
    }

    /// <summary>
    /// Four words, when four words are the whole answer. A teacher who asks
    /// to publish a class that is already published does not want a plan with
    /// a heading, a count, and a note that nothing was changed because
    /// nothing needed to be.
    /// </summary>
    [Fact]
    public async Task PublishingWhatIsAlreadyPublishedGetsFourWords()
    {
        var tools = Tools();
        await tools.PublishPages("ICS3U", 1, includeLinked: false,
            progress: new Progress<ProgressNotificationValue>(), cancellation: default,
            pages: new[] { "Unit 1, Day 2" });

        var again = await tools.PublishPages("ICS3U", 1, includeLinked: false,
            progress: new Progress<ProgressNotificationValue>(), cancellation: default,
            pages: new[] { "Unit 1, Day 2" });

        Assert.Equal("It's already been published.", again.Summary());
        Assert.Equal("It's already been published.", again.Detail());
    }

    [Fact]
    public void APlanNeverAsksTheTeacherToShowItToTheTeacher()
    {
        var answer = Tools().PlanPublishPages("ICS3U", 1, includeLinked: false,
                                              pages: new[] { "Unit 1, Day 2" });

        Assert.DoesNotContain("Show this to the teacher", answer.Summary());
        // The instruction is still there for a caller with no Go and Cancel
        // of its own, which means Claude Code.
        Assert.Contains("Show this to the teacher", answer.Detail());
    }

    // ---- Taking it back ---------------------------------------------------

    /// <summary>
    /// The undo sentences are the contract's, word for word — see
    /// contracts/assist-wording.json. They used to be written here instead,
    /// which is how "Undid publishing “X” — put 3 files back." came to be
    /// said on Windows where the mac says something else entirely.
    /// </summary>
    [Fact]
    public async Task UndoingSpeaksTheContractsWords()
    {
        var workspace = new AssistWorkspace(_folder, _launcher, undo: new UndoHistory());
        var tools = new Plantoir.Mcp.PlantoirTools(workspace);

        await tools.PublishPages("ICS3U", 1, includeLinked: false,
            progress: new Progress<ProgressNotificationValue>(), cancellation: default,
            pages: new[] { "Unit 1, Day 2" });

        string said = tools.UndoLastChange().Summary();
        Assert.StartsWith("Earlier, you published “Unit 1, Day 2”", said);
        Assert.Contains("Then you asked me to undo that, and I have done so.", said);
    }

    [Fact]
    public void WithNothingToUndoTheAnswerIsTheContractsSentence()
    {
        var workspace = new AssistWorkspace(_folder, _launcher, undo: new UndoHistory());
        Assert.Equal(AssistWording.NothingToUndo,
            new Plantoir.Mcp.PlantoirTools(workspace).UndoLastChange().Summary());
    }

    // ---- Nothing in front of a teacher names a tool ------------------------

    [Fact]
    public void WhatThisConversationChangedNeverNamesATool()
    {
        Assert.DoesNotContain("undo_last_change", Tools().ListRecentChanges());
    }
}

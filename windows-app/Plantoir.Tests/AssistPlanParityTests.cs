using System;
using System.IO;
using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Mcp;
using Xunit;

namespace Plantoir.Tests;

public sealed class AssistPlanParityTests : IDisposable
{
    private readonly string _folder;

    public AssistPlanParityTests()
    {
        _folder = Path.Combine(Path.GetTempPath(), "plantoir-parity-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_folder);
    }

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private void Page(string course, string relative, bool draftSection1 = false, string body = "")
    {
        string full = Path.Combine(_folder, "courses", course, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        string header = $"---\ntitle: {Path.GetFileNameWithoutExtension(relative)}\ncreated: 2026-09-08T07:00:00.000-0400\npublishForSection1: {!draftSection1}\n---\n";
        File.WriteAllText(full, header + body);
    }

    private void DatedClass(string course, string title, string date, bool draft = false, string body = "")
    {
        string full = Path.Combine(_folder, "courses", course, "section1", "All Classes", title + ".md");
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        string header = $"---\ntitle: {title}\ncreated: {date}T07:00:00.000-0400\ndraft: {draft.ToString().ToLowerInvariant()}\n---\n";
        File.WriteAllText(full, header + body);
    }

    private AssistWorkspace Open()
    {
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        string courseDir = Path.Combine(_folder, "courses", "ICD2O");
        Directory.CreateDirectory(courseDir);
        File.WriteAllText(Path.Combine(courseDir, "course_config.json"),
            "{\"course_code\":\"ICD2O\",\"course_name\":\"Digital Technology\",\"num_sections\":1,\"section_numbers\":[1],\"per_section_folders\":[\"All Classes\"],\"per_section_files\":[]}");
        return new AssistWorkspace(_folder, new FakeLauncher());
    }



    [Fact]
    public void UnpublishPlanMatchesMacOSOutputByteForByte()
    {
        // Setup ICD2O Section 1 matching user's exact case:
        // Unit 1, Day 15 (visible) links to Tech Headlines (visible)
        // Unit 4, Day 20 (visible) links to Tech Headlines (visible)
        DatedClass("ICD2O", "Unit 1, Day 15", "2026-10-15", draft: false, body: "See [[Tech Headlines]]");
        DatedClass("ICD2O", "Unit 4, Day 20", "2027-01-15", draft: false, body: "See [[Tech Headlines]]");
        Page("ICD2O", "Concepts/Tech Headlines.md", draftSection1: false);

        var workspace = Open();
        var plan = workspace.PlanPublish("ICD2O", 1, new[] { "Unit 4, Day 20" }, includeLinked: true, draft: true);

        string expected =
            "ICD2O Section 1: unpublishing.\n\n" +
            "1 page would change:\n" +
            "“Unit 4, Day 20” will become hidden.\n\n" +
            "1 linked page stays visible:\n" +
            "“Tech Headlines” stays visible, because “Unit 1, Day 15” still links to it.";

        Assert.Equal(expected, plan.Describe());
    }

    [Fact]
    public void UnpublishPlanWhenLinkedPageIsExclusiveTakesItDown()
    {
        DatedClass("ICD2O", "Unit 4, Day 20", "2027-01-15", draft: false, body: "See [[Exclusive Material]]");
        Page("ICD2O", "Concepts/Exclusive Material.md", draftSection1: false);

        var workspace = Open();
        var plan = workspace.PlanPublish("ICD2O", 1, new[] { "Unit 4, Day 20" }, includeLinked: true, draft: true);

        string expected =
            "ICD2O Section 1: unpublishing.\n\n" +
            "2 pages would change:\n" +
            "“Unit 4, Day 20” will become hidden.\n" +
            "“Exclusive Material” will become hidden.";

        Assert.Equal(expected, plan.Describe());
    }

    [Fact]
    public void PublishPlanShowsDateMovesAndTransitionsCleanly()
    {
        DatedClass("ICD2O", "Unit 4, Day 20", "2027-01-15", draft: true, body: "See [[Tech Headlines]]");
        Page("ICD2O", "Concepts/Tech Headlines.md", draftSection1: true);

        var workspace = Open();
        var plan = workspace.PlanPublish("ICD2O", 1, new[] { "Unit 4, Day 20" }, includeLinked: true, draft: false);

        string expected =
            "ICD2O Section 1: publishing.\n\n" +
            "2 pages would change:\n" +
            "“Unit 4, Day 20” will become visible.\n" +
            "“Tech Headlines” will become visible, with the same date as “Unit 4, Day 20”.";

        Assert.Equal(expected, plan.Describe());
    }

    [Fact]
    public void NothingToDoSentenceReturnsCleanPlainSentence()
    {
        DatedClass("ICD2O", "Unit 4, Day 20", "2027-01-15", draft: true);
        var workspace = Open();

        var unpublishPlan = workspace.PlanPublish("ICD2O", 1, new[] { "Unit 4, Day 20" }, includeLinked: true, draft: true);
        Assert.Equal("It's already hidden.", unpublishPlan.NothingToDoSentence);

        DatedClass("ICD2O", "Unit 1, Day 1", "2026-09-08", draft: false);
        var publishPlan = workspace.PlanPublish("ICD2O", 1, new[] { "Unit 1, Day 1" }, includeLinked: true, draft: false);
        Assert.Equal("It's already been published.", publishPlan.NothingToDoSentence);
    }
}

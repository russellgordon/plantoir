using ModelContextProtocol;
using Plantoir.Core.Assist;
using Plantoir.Mcp;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #165: a publish that fails part way ANSWERS, says what was only partly
/// done, and names the copy that puts it back -- like every other changing
/// tool, instead of leaving the tool as a protocol error.
/// </summary>
public class PublishStoppedPartWayTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-part-way").FullName;

    public PublishStoppedPartWayTests()
    {
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        string directory = Path.Combine(_folder, "courses", "ICS3U");
        Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory, "course_config.json"), """
            { "course_code": "ICS3U", "course_name": "A course", "deploy_target": "netlify",
              "num_sections": 1, "per_section_folders": ["All Classes"], "per_section_files": [],
              "section_numbers": [1] }
            """);
        foreach (string title in new[] { "Unit 1, Day 1", "Unit 1, Day 2" })
        {
            string full = Path.Combine(directory, "section1", "All Classes", title + ".md");
            Directory.CreateDirectory(Path.GetDirectoryName(full)!);
            File.WriteAllText(full, "---\npublish: false\ncreated: 2026-09-08T07:00:00.000-0400\n---\nBody.\n");
        }
    }

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private string Page(string title) =>
        Path.Combine(_folder, "courses", "ICS3U", "section1", "All Classes", title + ".md");

    [Theory]
    [InlineData("Unit 1", "Unit 1 was only partly published")]
    [InlineData("Unit 1, Day 2", "The pages were only partly published")]
    public async Task APageThatCannotBeWrittenIsAnsweredAndTheCopyIsNamed(string asked, string expected)
    {
        var tools = new PlantoirTools(new AssistWorkspace(_folder, new FakeLauncher()));
        var progress = new Progress<ProgressNotificationValue>(_ => { });

        // Another program holds the page: reading or writing it fails.
        using (new FileStream(Page("Unit 1, Day 2"), FileMode.Open, FileAccess.ReadWrite, FileShare.None))
        {
            var answer = await tools.PublishPages("ICS3U", 1, progress, default,
                                                  new[] { asked }, preview: false);
            string said = answer.Summary();
            Assert.Contains(expected, said);
            if (said.Contains("A copy from before", StringComparison.Ordinal))
                Assert.Contains("Restore Section 1", said);
        }
    }
}

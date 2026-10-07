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

    /// <summary>
    /// The contract's sentence (#436, mac #412: <c>wording.publishStoppedPartWay</c>),
    /// "{what}" being the unit asked for or "the pages you named". The pointer
    /// to Restore Section (<c>wording.restoreSectionPutsItBack</c>) is said
    /// ONLY in Plantoir's own window, which has that button — never to an
    /// outside assistant (director's ruling, as on the mac).
    /// </summary>
    [Theory]
    [InlineData("Unit 1", "Unit 1", false)]
    [InlineData("Unit 1, Day 2", "the pages you named", false)]
    [InlineData("Unit 1", "Unit 1", true)]
    [InlineData("Unit 1, Day 2", "the pages you named", true)]
    public async Task APageThatCannotBeWrittenIsAnsweredAndTheCopyIsNamedOnlyInTheWindow(
        string asked, string what, bool inTheWindow)
    {
        var workspace = new AssistWorkspace(_folder, new FakeLauncher()) { ServesTheLocalWindow = inTheWindow };
        var tools = new PlantoirTools(workspace);
        var progress = new Progress<ProgressNotificationValue>(_ => { });

        // The page can be read and planned, and not written: the failure comes
        // AFTER the copy is taken, which is when the pointer has a copy to name.
        File.SetAttributes(Page("Unit 1, Day 2"), FileAttributes.ReadOnly);
        try
        {
            var answer = await tools.PublishPages("ICS3U", 1, progress, default,
                                                  new[] { asked }, preview: false);
            string said = answer.Summary();
            Assert.StartsWith(AssistWording.PublishStoppedPartWay(what, ""), said);
            Assert.NotNull(workspace.ConversationBackupPath);
            if (inTheWindow)
                Assert.EndsWith(AssistWording.RestoreSectionPutsItBack("1"), said);
            else
                Assert.DoesNotContain("Restore Section", said);
        }
        finally { File.SetAttributes(Page("Unit 1, Day 2"), FileAttributes.Normal); }
    }
}

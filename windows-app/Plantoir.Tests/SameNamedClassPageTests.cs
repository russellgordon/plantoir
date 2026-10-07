using ModelContextProtocol;
using Plantoir.Core.Assist;
using Plantoir.Mcp;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #436 item 5 (mac #425's stack review, the mac's <c>SameNamedClassPageTests</c>):
/// a class page is found by its FILE. On the mac a class whose file name a
/// course-level page shared was dropped from the plan in silence ("Unit 4 was
/// unpublished", the class still visible). Every Windows caller that holds a
/// class's path — a whole unit, publish_class_on, the links checklist — passes
/// the PATH to PlanPublish, never the title; these pin the two a teacher meets most.
/// </summary>
public class SameNamedClassPageTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-same-named").FullName;

    public SameNamedClassPageTests()
    {
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        Directory.CreateDirectory(CourseDir);
        File.WriteAllText(Path.Combine(CourseDir, "course_config.json"), """
            { "course_code": "ICS3U", "course_name": "A course", "deploy_target": "netlify",
              "num_sections": 1, "per_section_folders": ["All Classes"], "per_section_files": [],
              "section_numbers": [1] }
            """);
        Write(ClassPath, "---\npublish: false\ncreated: 2026-09-08T07:00:00.000-0400\n---\nThe class.\n");
        // A course-level page whose FILE NAME is the class's.
        Write(SharedPath, "---\npublishForSection1: false\n---\nSomething else entirely.\n");
    }

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
        GC.SuppressFinalize(this);
    }

    private string CourseDir => Path.Combine(_folder, "courses", "ICS3U");
    private string ClassPath => Path.Combine(CourseDir, "section1", "All Classes", "Unit 1, Day 1.md");
    private string SharedPath => Path.Combine(CourseDir, "Concepts", "Unit 1, Day 1.md");

    private static void Write(string path, string text)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, text);
    }

    [Fact]
    public async Task PublishingTheClassOnItsDayPublishesTheClassAndNotItsNamesake()
    {
        var tools = new PlantoirTools(new AssistWorkspace(_folder, new FakeLauncher()));
        await tools.PublishClassOn("ICS3U", 1, "2026-09-08", new Progress<ProgressNotificationValue>(_ => { }),
                                   default, preview: false);
        Assert.Contains("publish: true", File.ReadAllText(ClassPath));
        Assert.Contains("publishForSection1: false", File.ReadAllText(SharedPath));
    }

    [Fact]
    public async Task PublishingTheWholeUnitPublishesTheClassAndNotItsNamesake()
    {
        var tools = new PlantoirTools(new AssistWorkspace(_folder, new FakeLauncher()));
        await tools.PublishPages("ICS3U", 1, new Progress<ProgressNotificationValue>(_ => { }), default,
                                 new[] { "Unit 1" }, preview: false);
        Assert.Contains("publish: true", File.ReadAllText(ClassPath));
        Assert.Contains("publishForSection1: false", File.ReadAllText(SharedPath));
    }
}

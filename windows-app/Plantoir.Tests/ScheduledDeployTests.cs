using Plantoir.Core.Assist;

namespace Plantoir.Tests;

/// <summary>
/// "Deploy tomorrow's class at 6:30 AM" — and the warnings that go with it.
/// </summary>
public sealed class ScheduledDeployTests : IDisposable
{
    private readonly string _folder = Path.Combine(Path.GetTempPath(),
        "plantoir-schedule-" + Guid.NewGuid().ToString("N"));
    private readonly FakeLauncher _launcher = new();

    public ScheduledDeployTests()
    {
        string course = Path.Combine(_folder, "courses", "ICS3U");
        Directory.CreateDirectory(Path.Combine(course, "section1", "All Classes"));
        Directory.CreateDirectory(Path.Combine(course, ".netlify_sites"));
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        File.WriteAllText(Path.Combine(course, ".netlify_sites", "section1.json"), "{}");
        File.WriteAllText(Path.Combine(course, "course_config.json"),
            """
            {
              "course_code": "ICS3U",
              "course_name": "Computer Science",
              "deploy_target": "netlify",
              "num_sections": 1,
              "per_section_folders": ["All Classes"],
              "per_section_files": [],
              "section_numbers": [1]
            }
            """);
    }

    private void ClassPage(string title, bool published) =>
        File.WriteAllText(
            Path.Combine(_folder, "courses", "ICS3U", "section1", "All Classes", title + ".md"),
            $"---\ntitle: {title}\npublish: {(published ? "true" : "false")}\n---\nBody.\n");

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private AssistWorkspace Open() => new(_folder, _launcher);
    private static DateTime Tomorrow => DateTime.Now.AddDays(1).Date.AddHours(6).AddMinutes(30);

    // ---- The guard both doors share --------------------------------------

    [Fact]
    public void TheSameRefusalsApplyWhereverTheDeployIsScheduledFrom()
    {
        // The sidebar's "Schedule Deploy…" and the assistant's schedule_deploy
        // call ONE checker. A refusal only one of them made would be a refusal
        // a teacher could walk around by using the other door.
        var course = Open().Course("ICS3U");
        var now = new DateTime(2026, 8, 14, 9, 0, 0);

        Assert.Contains("has already passed",
            ScheduledDeploy.Problem(course, 1, now.AddHours(-1), now));
        Assert.Null(ScheduledDeploy.Problem(course, 1, now.AddDays(1), now));
    }

    [Fact]
    public void ASectionNeverDeployedCannotBeScheduled()
    {
        // deploy.py would ask what to call the website, and at 6:30 in the
        // morning nobody is there to answer — it would simply wait.
        File.Delete(Path.Combine(_folder, "courses", "ICS3U", ".netlify_sites", "section1.json"));
        var course = Open().Course("ICS3U");
        var now = new DateTime(2026, 8, 14, 9, 0, 0);

        string? problem = ScheduledDeploy.Problem(course, 1, now.AddDays(1), now);

        Assert.Contains("has never been deployed", problem);
        Assert.Contains("Nobody would be there to answer", problem);
    }

    [Fact]
    public void ACloudflareCourseCannotBeScheduled()
    {
        File.WriteAllText(Path.Combine(_folder, "courses", "ICS3U", "course_config.json"),
            """
            {
              "course_code": "ICS3U",
              "course_name": "Computer Science",
              "deploy_target": "cloudflare_pages",
              "num_sections": 1,
              "per_section_folders": ["All Classes"],
              "per_section_files": [],
              "section_numbers": [1]
            }
            """);
        var course = Open().Course("ICS3U");
        var now = new DateTime(2026, 8, 14, 9, 0, 0);

        // The account ID lives in Plantoir's settings, and an unattended run
        // has no way to be given it.
        Assert.Contains("needs your Account ID",
            ScheduledDeploy.Problem(course, 1, now.AddDays(1), now));
    }

    [Fact]
    public void PlanScheduledDeployReadsTheRealCloudflareAccountIdRatherThanAlwaysRefusing()
    {
        // Found while auditing this feature for mac parity: PlanScheduledDeploy
        // called ScheduledDeploy.Problem with no cloudflareAccountID argument
        // at all, so it defaulted to "" — a Cloudflare-destination course
        // scheduled through the assistant always refused with "Paste your
        // Cloudflare Account ID," even when one was correctly configured in
        // Plantoir's own settings. CloudflareAccountIdOverrideForTests stands
        // in for AppSettings.Load() here so the assertion does not depend on
        // whatever is (or isn't) in the real machine's settings.json.
        File.WriteAllText(Path.Combine(_folder, "courses", "ICS3U", "course_config.json"),
            """
            {
              "course_code": "ICS3U",
              "course_name": "Computer Science",
              "deploy_target": "cloudflare_pages",
              "num_sections": 1,
              "per_section_folders": ["All Classes"],
              "per_section_files": [],
              "section_numbers": [1]
            }
            """);
        Directory.CreateDirectory(Path.Combine(_folder, "courses", "ICS3U", ".cloudflare_sites"));
        File.WriteAllText(Path.Combine(_folder, "courses", "ICS3U", ".cloudflare_sites", "section1.json"), "{}");

        AssistWorkspace.CloudflareAccountIdOverrideForTests = () => "0123456789abcdef0123456789abcdef";
        try
        {
            var plan = Open().PlanScheduledDeploy("ICS3U", 1, Tomorrow);
            Assert.True(plan.Describe().Length > 0);   // did not throw AssistRefusal
        }
        finally
        {
            AssistWorkspace.CloudflareAccountIdOverrideForTests = null;
        }
    }

    [Fact]
    public void PlanScheduledDeployStillRefusesWithNoCloudflareAccountIdConfigured()
    {
        File.WriteAllText(Path.Combine(_folder, "courses", "ICS3U", "course_config.json"),
            """
            {
              "course_code": "ICS3U",
              "course_name": "Computer Science",
              "deploy_target": "cloudflare_pages",
              "num_sections": 1,
              "per_section_folders": ["All Classes"],
              "per_section_files": [],
              "section_numbers": [1]
            }
            """);

        AssistWorkspace.CloudflareAccountIdOverrideForTests = () => "";
        try
        {
            var refusal = Assert.Throws<AssistRefusal>(
                () => Open().PlanScheduledDeploy("ICS3U", 1, Tomorrow));
            Assert.Contains("needs your Account ID", refusal.Message);
        }
        finally
        {
            AssistWorkspace.CloudflareAccountIdOverrideForTests = null;
        }
    }

    [Fact]
    public void ATimeThatHasPassedIsRefused()
    {
        var refusal = Assert.Throws<AssistRefusal>(
            () => Open().PlanScheduledDeploy("ICS3U", 1, DateTime.Now.AddHours(-1)));

        Assert.Contains("has already passed", refusal.Message);
    }

    [Fact]
    public void ItSaysWhatMustBeTrueOfTheComputer()
    {
        string described = Open().PlanScheduledDeploy("ICS3U", 1, Tomorrow).Describe();

        // Said up front, because the alternative is a teacher walking into
        // class to find yesterday's site still up.
        Assert.Contains("switched on, and awake", described);
        Assert.Contains("plugged in, if it is a laptop", described);
        Assert.Contains("lid open", described);
        Assert.Contains("Plantoir does not wake the computer up", described);
    }

    [Fact]
    public void AnUnpublishedClassIsCaughtBeforeTheDeployIsScheduled()
    {
        ClassPage("Unit 2, Day 3", published: false);

        var plan = Open().PlanScheduledDeploy("ICS3U", 1, Tomorrow, new[] { "Unit 2, Day 3" });

        // The failure this exists to prevent: a deploy that runs perfectly at
        // half six and ships a site without tomorrow's class.
        Assert.Equal("Unit 2, Day 3", Assert.Single(plan.UnpublishedClasses));
        Assert.Contains("not published yet", plan.Describe());
        Assert.Contains("Publish first", plan.Describe());
    }

    [Fact]
    public void APublishedClassRaisesNothing()
    {
        ClassPage("Unit 2, Day 3", published: true);

        var plan = Open().PlanScheduledDeploy("ICS3U", 1, Tomorrow, new[] { "Unit 2, Day 3" });

        Assert.Empty(plan.UnpublishedClasses);
        Assert.DoesNotContain("not published yet", plan.Describe());
    }

    [Fact]
    public void ThePlanNamesTheDestinationAndTheTime()
    {
        string described = Open().PlanScheduledDeploy("ICS3U", 1, Tomorrow).Describe();

        Assert.Contains("ICS3U Section 1", described);
        Assert.Contains("Netlify", described);
        Assert.Contains("6:30", described);
    }

    [Fact]
    public void TheTaskNameIsPerSectionSoTwoSectionsDoNotCollide()
    {
        var one = Open().PlanScheduledDeploy("ICS3U", 1, Tomorrow);
        Assert.Equal("Plantoir deploy ICS3U section 1", one.TaskName);
    }
}

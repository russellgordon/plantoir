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

    private void DatedClassPage(string title, bool published, string created) =>
        File.WriteAllText(
            Path.Combine(_folder, "courses", "ICS3U", "section1", "All Classes", title + ".md"),
            $"---\ntitle: {title}\ncreated: {created}\npublish: {(published ? "true" : "false")}\n---\nBody.\n");

    // ---- What the sidebar's own dialog says about unpublished classes ------

    /// <summary>
    /// The sidebar has no list of named classes the way the assistant's tool
    /// does, so EVERY unpublished class is named — dated after the deploy or
    /// not at all, it is still a page students cannot see, which is the
    /// contract's rule and the mac's behaviour. The section's front page is
    /// never a class, even when it sits inside the class folder.
    /// </summary>
    [Fact]
    public void TheClassesADeployWouldLeaveBehindAreEveryUnpublishedOne()
    {
        DatedClassPage("Unit 1, Day 1", published: true, created: "2026-09-08");
        DatedClassPage("Unit 1, Day 2", published: false, created: "2026-09-09");
        DatedClassPage("Unit 1, Day 4", published: false, created: "2026-12-14");
        ClassPage("Unit 9, Day 1", published: false);       // undated, still named
        File.WriteAllText(Path.Combine(_folder, "courses", "ICS3U", "section1", "All Classes", "index.md"),
            "---\ntitle: All Classes\npublish: false\n---\n");
        var course = Open().Course("ICS3U");

        Assert.Equal(new[] { "Unit 1, Day 2", "Unit 1, Day 4", "Unit 9, Day 1" },
                     ScheduledDeploy.UnpublishedClassesIn(course, 1));
    }

    [Fact]
    public void TheDialogsSentenceCarriesTheSameContentAsTheAssistantsDescription()
    {
        Assert.Null(ScheduledDeploy.UnpublishedClassesSentence(Array.Empty<string>()));

        string one = ScheduledDeploy.UnpublishedClassesSentence(new[] { "Unit 1, Day 2" })!;
        Assert.StartsWith("One thing first — 1 class is not published yet: Unit 1, Day 2.", one);
        Assert.Contains("Deploying now would put the site up without it.", one);
        Assert.EndsWith("Publish first, look the preview over, then schedule this.", one);

        var many = Enumerable.Range(1, 10).Select(n => $"Unit 2, Day {n}").ToList();
        string sentence = ScheduledDeploy.UnpublishedClassesSentence(many)!;
        Assert.Contains("10 classes are not published yet", sentence);
        Assert.Contains("Unit 2, Day 8 …and 2 more.", sentence);
        Assert.DoesNotContain("Unit 2, Day 9", sentence);
        Assert.Contains("without them.", sentence);
    }

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
    public void ASwitchedDestinationIsNotConsideredDeployedJustBecauseTheOldOneWas()
    {
        // The divergence this regression-tests (documentation/07-deployment.md,
        // contracts/file-formats.json → firstDeployMarkers): a course
        // deployed to Netlify (leaving a .netlify_sites marker) and then
        // switched to Cloudflare has NEVER been deployed to Cloudflare, and
        // its first Cloudflare deploy will ask what to call the site. The
        // .netlify_sites marker from the OLD destination is left in place
        // (nothing deletes it on a switch), so the check must read the
        // marker for the destination the course is configured for NOW, not
        // any marker it happens to find.
        Assert.True(File.Exists(Path.Combine(_folder, "courses", "ICS3U", ".netlify_sites", "section1.json")));
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

        string? problem = ScheduledDeploy.Problem(
            course, 1, now.AddDays(1), now, cloudflareAccountID: "0123456789abcdef0123456789abcdef");

        // The PRIMARY-destination wording doesn't name the destination (only
        // an ADDITIONAL destination's refusal does) — the case that matters
        // here is that this refuses at all, rather than reading the leftover
        // Netlify marker as proof Cloudflare has already been deployed.
        Assert.Contains("has never been deployed", problem);
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

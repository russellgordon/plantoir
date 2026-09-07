using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// The last of the case lists WINDOWS-HANDOFF item 29 found this suite was not
/// running — renaming a course, the problem report's question about the
/// assistant, the working folder's path bar, what a page is CALLED, where a
/// built site is kept, what a payload may contain, and which folders make up
/// the recipe.
///
/// <para>They have little in common except that each is a rule with inputs and
/// an expected output, which is the test `contracts/README.md` gives for
/// whether a rule is the product's or the platform's. None was unreachable;
/// each was simply a test nobody had written.</para>
/// </summary>
[Collection(ProcessEnvironment.Name)]
public sealed class SharedRuleContractTests : IDisposable
{
    private readonly string _folder = Path.Combine(Path.GetTempPath(),
        "plantoir-shared-rules-" + Guid.NewGuid().ToString("N"));

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private static string RepoRoot
    {
        get
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            for (int i = 0; i < 8 && dir is not null; i++, dir = dir.Parent)
            {
                if (File.Exists(Path.Combine(dir.FullName, "Dockerfile")))
                    return dir.FullName;
            }
            throw new DirectoryNotFoundException("Could not find repository root containing Dockerfile.");
        }
    }

    // ---- Renaming a course ------------------------------------------------

    /// <summary>
    /// What renaming a course does, and — the half that matters — what it
    /// deliberately does NOT do.
    ///
    /// <para>Four of the six effects are observable from a real rename here.
    /// The fifth and sixth are about the scheduled publish, which lives in
    /// Windows Task Scheduler: creating one in a test would put a real job on
    /// the machine, so what is asserted is that a rename REPORTS a cancelled
    /// schedule in words a teacher would recognise. Silently losing a
    /// scheduled publish is the failure the alert exists to spend itself
    /// on.</para>
    /// </summary>
    [Fact]
    public void RenamingACourseHasEveryEffectTheContractNamesAndNoOthers()
    {
        var doc = ContractLoader.LoadJson("course-management.json");
        var expected = new Dictionary<string, bool>(StringComparer.Ordinal);
        foreach (var entry in doc["courseCode"]!["renameEffects"]!.AsArray())
            expected[entry!["effect"]!.ToString()] = entry["expect"]!.GetValue<bool>();
        Assert.NotEmpty(expected);

        var unanswered = new HashSet<string>(expected.Keys, StringComparer.Ordinal);
        bool Expect(string effect)
        {
            Assert.True(unanswered.Remove(effect),
                $"No effect in the contract is called \"{effect}\" any more.");
            return expected[effect];
        }

        string courses = Path.Combine(_folder, "courses");
        string before = Path.Combine(courses, "ZZT4Q");
        Directory.CreateDirectory(Path.Combine(before, "section1"));
        Directory.CreateDirectory(Path.Combine(before, ".netlify_sites"));
        Directory.CreateDirectory(Path.Combine(courses, "_backups", "ZZT4Q"));
        File.WriteAllText(Path.Combine(courses, "_backups", "ZZT4Q", "backup.zip"), "zip");
        File.WriteAllText(Path.Combine(before, ".netlify_sites", "section1.json"), """{"site":"ics3u-s1"}""");
        File.WriteAllText(Path.Combine(before, "course_config.json"),
            """
            {
              "course_code": "ZZT4Q",
              "course_name": "Introduction to Computer Science",
              "deploy_target": "netlify",
              "num_sections": 1,
              "section_numbers": [1]
            }
            """);
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");

        var workspace = new AssistWorkspace(_folder, new FakeLauncher());
        var course = workspace.Course("ZZT4Q");
        Assert.NotNull(course);

        var outcome = CourseRenamer.Rename(course!, "ZZT4R", courses, new[] { "ZZT4Q" });
        Assert.Equal("ZZT4R", outcome.NewCode);

        string after = Path.Combine(courses, "ZZT4R");

        // The code IS the folder name, so renaming is a move.
        Assert.Equal(Expect("courseFolderMoves"), Directory.Exists(after) && !Directory.Exists(before));

        // The app reads the code from the FOLDER while the site builder reads
        // it from course_config.json. A pair that disagree produce a sidebar
        // saying one thing and a published page saying another, with no error.
        string written = File.ReadAllText(Path.Combine(after, "course_config.json"));
        Assert.Equal(Expect("courseCodeInSettingsRewritten"), written.Contains("\"ZZT4R\"", StringComparison.Ordinal));

        // The teacher's own wording is left alone.
        Assert.Equal(
            Expect("courseNameRewritten"),
            !written.Contains("Introduction to Computer Science", StringComparison.Ordinal));

        // Backups stay where they were made, under the name they were made
        // with: that is what they are — the course as it stood when it was
        // called that.
        Assert.Equal(
            Expect("backupsAndArchivesMove"),
            Directory.Exists(Path.Combine(courses, "_backups", "ZZT4R")));

        // Not moved is not the same as not there: a renamer that DELETED the
        // backups would satisfy the line above.
        Assert.True(File.Exists(Path.Combine(courses, "_backups", "ZZT4Q", "backup.zip")),
            "The backup was made when the course was called ZZT4Q and belongs under that name. " +
            "Renaming must leave it exactly where it is — restoring one still works, because the " +
            "restorer names the restored folder after the ITEM rather than after whatever the zip " +
            "holds inside.");

        // Where a section publishes to is recorded INSIDE the course folder, so
        // it travels and the students' address does not change.
        Assert.Equal(
            Expect("publishingIdentityTravelsWithTheFolder"),
            File.Exists(Path.Combine(after, ".netlify_sites", "section1.json")));

        // The one thing renaming has to break, and has to SAY it broke: a
        // scheduled publish is an alarm held outside the working folder,
        // addressed by the old code, which after a rename would fire at a
        // course that is no longer there.
        var notice = CourseRenamer.NoticeAfterRenaming(
            new CourseRenamer.Outcome("ZZT4R", new[] { 1 }, Array.Empty<int>()));
        Assert.NotNull(notice);
        Assert.Contains("Section 1", notice!.Message, StringComparison.Ordinal);
        Assert.Contains("Renaming turned that off", notice.Message, StringComparison.Ordinal);
        Assert.True(Expect("scheduledPublishingCancelled"));

        // And a rename with nothing scheduled says nothing at all — an alert
        // that fires every time is one nobody reads.
        Assert.Null(CourseRenamer.NoticeAfterRenaming(
            new CourseRenamer.Outcome("ZZT4R", Array.Empty<int>(), Array.Empty<int>())));

        Assert.True(unanswered.Count == 0,
            "contracts/course-management.json names effects of renaming a course that no test " +
            "here answers: " + string.Join("; ", unanswered.OrderBy(e => e, StringComparer.Ordinal)));
    }

    // ---- The problem report's question about the assistant -----------------

    /// <summary>
    /// Whether the teacher is ASKED about their own sentences, and what the
    /// report says about them either way.
    ///
    /// <para>A teacher who has never typed to the local assistant must not be
    /// shown a question implying they might have: the box governs their
    /// sentences, and with none recorded, ticking it would change nothing. An
    /// unanswerable choice reads as the app knowing something about them they
    /// do not recognise.</para>
    /// </summary>
    [Fact]
    public void TheReportAsksAboutTypedSentencesOnlyWhenThereAreSome()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        foreach (var entry in doc["problemReportDialog"]!["askAboutPromptsWhen"]!.AsArray())
        {
            bool hasPrompts = entry!["trailHasPromptLines"]!.GetValue<bool>();
            bool shouldAsk = entry["expect"]!.ToString() == "ask";

            // With nothing recorded the answer is the same whichever way the
            // box is ticked, which is what makes the question unanswerable and
            // is why it must not be asked.
            var ticked = ProblemReportBuilder.PromptState(hasPrompts, including: true);
            var unticked = ProblemReportBuilder.PromptState(hasPrompts, including: false);

            Assert.Equal(shouldAsk, ticked != unticked);
            if (!shouldAsk)
                Assert.Equal(ProblemReportBuilder.AssistantPrompts.None, ticked);
        }

        // The dialog itself lives in the interface project, which this suite
        // cannot reference, so the wiring is read from its source — the same
        // shape the wizard's answers are checked with. What is checked is that
        // the box's presence is decided by whether anything was recorded, not
        // shown unconditionally.
        string dialog = File.ReadAllText(Path.Combine(
            RepoRoot, "windows-app", "Plantoir", "MainWindow.xaml.cs"));
        Assert.Contains("if (store.HasAssistantPrompts)", dialog, StringComparison.Ordinal);
    }

    /// <summary>
    /// What the report's own note says about the assistant, in each of the
    /// three states. Promising that something was left out, to somebody who
    /// never used it, invites them to wonder what else the app thinks they did.
    /// </summary>
    [Fact]
    public void TheReportsNoteSaysTheRightThingInEachPromptState()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var unanswered = new HashSet<string>(StringComparer.Ordinal);
        foreach (var entry in doc["problemReportDialog"]!["promptStates"]!.AsArray())
            unanswered.Add(entry!["state"]!.ToString());
        Assert.Equal(3, unanswered.Count);

        var now = new DateTime(2026, 9, 6, 10, 0, 0, DateTimeKind.Local);
        const string Mentions = "local AI assistant";

        string none = ProblemReportBuilder.About(3, ProblemReportBuilder.AssistantPrompts.None, now);
        Assert.DoesNotContain(Mentions, none, StringComparison.Ordinal);
        Assert.True(unanswered.Remove("none"));

        string excluded = ProblemReportBuilder.About(3, ProblemReportBuilder.AssistantPrompts.Excluded, now);
        Assert.Contains(Mentions, excluded, StringComparison.Ordinal);
        Assert.True(SaidUnder(excluded, "NOT IN THIS REPORT", Mentions),
            "A teacher who left the box unticked is promised their sentences were left out. " +
            "That promise is the point of the note, and it has to appear under the heading " +
            "that makes it a promise.");
        Assert.True(unanswered.Remove("excluded"));

        string included = ProblemReportBuilder.About(3, ProblemReportBuilder.AssistantPrompts.Included, now);
        Assert.True(SaidUnder(included, "IN THIS REPORT", Mentions),
            "A teacher who ticked the box should see their sentences listed as included, and " +
            "the note should record that it was their choice.");
        Assert.Contains("because you asked for it", included, StringComparison.Ordinal);
        Assert.True(unanswered.Remove("included"));

        Assert.True(unanswered.Count == 0,
            "contracts/shared-rules.json names prompt states the report does not answer: " +
            string.Join("; ", unanswered));
    }

    /// <summary>Whether <paramref name="phrase"/> appears under that heading, before the next one.</summary>
    private static bool SaidUnder(string note, string heading, string phrase)
    {
        int start = note.IndexOf(heading, StringComparison.Ordinal);
        if (start < 0) return false;
        start += heading.Length;

        int end = note.Length;
        foreach (string other in new[] { "IN THIS REPORT", "NOT IN THIS REPORT", "Where something was taken out" })
        {
            int at = note.IndexOf(other, start, StringComparison.Ordinal);
            if (at >= 0 && at < end) end = at;
        }
        return note[start..end].Contains(phrase, StringComparison.Ordinal);
    }

    // ---- The working folder's path bar -------------------------------------

    /// <summary>
    /// Every ancestor from the drive down to and including the folder itself.
    /// The root is included: a teacher scanning for where their folder lives
    /// reads the whole line.
    ///
    /// <para>The contract's own cases are mac paths, so this side had a
    /// hand-typed copy. `windowsCases` was proposed 2026-09-06 so the list is
    /// data on both platforms — the rule is shared even though the spelling of
    /// a root is not.</para>
    /// </summary>
    [Fact]
    public void ThePathBarShowsEveryAncestorTheContractNames()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var cases = doc["workingFolderPathBar"]!["ancestorPaths"]!["windowsCases"]!.AsArray();
        Assert.NotEmpty(cases);

        foreach (var entry in cases)
        {
            string path = entry!["path"]!.ToString();
            var expected = new List<string>();
            foreach (var crumb in entry["expect"]!.AsArray()) expected.Add(crumb!.ToString());

            Assert.Equal(expected, FolderCrumb.AncestorPaths(path).ToList());
        }
    }

    // ---- What a page is called ---------------------------------------------

    /// <summary>
    /// The three-step rule for a page's displayed name, each step exercised on
    /// its own so that a change to one is not hidden by another answering the
    /// same case.
    ///
    /// <para>Copied from Quartz's own <c>fileTrie.ts</c> rather than invented,
    /// so that what the assistant says and what the site's sidebar shows cannot
    /// drift. A teacher told that "index" still links to a page has been told
    /// nothing — every folder in a course has an <c>index.md</c>.</para>
    /// </summary>
    [Fact]
    public void APagesNameFollowsEachStepOfTheRuleInOrder()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var rule = doc["pageNaming"]!["theRule"]!.AsArray();
        Assert.Equal(3, rule.Count);

        // Step one: the frontmatter title, unless it is literally "index".
        Assert.Equal("the frontmatter title, unless it is literally 'index'", rule[0]!.ToString());
        Assert.Equal("Day One",
            PagePaths.DisplayTitle("Unit 1/Lesson.md", "---\ntitle: Day One\n---\nBody"));

        // Step two: for a file called index.md, the name of its FOLDER — and
        // that is also what happens when the title IS "index", which is the
        // case step one exists to hand on rather than answer.
        Assert.Equal("for a file called index.md, the name of its FOLDER", rule[1]!.ToString());
        Assert.Equal("Unit 1", PagePaths.DisplayTitle("Unit 1/index.md", "Body without frontmatter"));
        Assert.Equal("Unit 1", PagePaths.DisplayTitle("Unit 1/index.md", "---\ntitle: index\n---\nBody"));

        // Step three: otherwise the file name without .md.
        Assert.Equal("otherwise the file name without .md", rule[2]!.ToString());
        Assert.Equal("Lesson", PagePaths.DisplayTitle("Unit 1/Lesson.md", "Body without frontmatter"));

        // And the name the rule exists to make impossible.
        Assert.Equal(doc["pageNaming"]!["neverShown"]!.ToString(), "index");
        foreach (string file in new[] { "Unit 1/index.md", "Curriculum/index.md" })
            Assert.NotEqual("index", PagePaths.DisplayTitle(file, "---\ntitle: index\n---\nBody"));
    }

    // ---- Where a built site is kept ----------------------------------------

    /// <summary>
    /// The builds root, which the contract records for this platform and which
    /// — its own note says — was asserted by nobody on either side.
    /// </summary>
    [Fact]
    public void TheBuiltSitesAreKeptWhereTheContractSays()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        string shape = doc["buildOutputLocation"]!["windowsLocation"]!["buildsRoot"]!.ToString();

        // %LOCALAPPDATA%\Plantoir\builds\{folder id}
        Assert.Equal(@"%LOCALAPPDATA%\Plantoir\builds\{folder id}", shape);

        string previous = Environment.GetEnvironmentVariable("PLANTOIR_BUILD_ROOT") ?? "";
        try
        {
            Environment.SetEnvironmentVariable("PLANTOIR_BUILD_ROOT", null);

            string working = Path.Combine(_folder, "Courses");
            Directory.CreateDirectory(working);
            string root = BuildOutputLocation.BuildsRootFor(working);

            string expectedPrefix = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Plantoir", "builds");
            Assert.StartsWith(expectedPrefix, root, StringComparison.OrdinalIgnoreCase);

            // …\builds\{folder id} — one segment, and the same one for the same
            // folder, since a course's .merged_output has to resolve to it.
            string identifier = root[(expectedPrefix.Length + 1)..];
            Assert.DoesNotContain(Path.DirectorySeparatorChar.ToString(), identifier);
            Assert.NotEmpty(identifier);
            Assert.Equal(root, BuildOutputLocation.BuildsRootFor(working));

            // The environment variable is honoured, which is what the launchers
            // set and what the contract's `how` describes.
            Environment.SetEnvironmentVariable("PLANTOIR_BUILD_ROOT", @"D:\elsewhere");
            Assert.Equal(@"D:\elsewhere", BuildOutputLocation.BuildsRootFor(working));
        }
        finally
        {
            Environment.SetEnvironmentVariable("PLANTOIR_BUILD_ROOT",
                previous.Length == 0 ? null : previous);
        }
    }

    // ---- What a ready-made course may contain ------------------------------

    /// <summary>
    /// The payload rules, and in particular the one the contract calls "the
    /// direction that fails silently": anything sitting in a payload's trees
    /// that the manifest does not name is never installed. The work is in the
    /// repository, looks finished, and reaches no teacher.
    /// </summary>
    [Fact]
    public void EveryPayloadRuleIsAnsweredAndNothingUnnamedShipsInAPayload()
    {
        var doc = ContractLoader.LoadJson("example-content.json");
        var unanswered = new HashSet<string>(StringComparer.Ordinal);
        foreach (var rule in doc["rules"]!.AsArray()) unanswered.Add(rule!["rule"]!.ToString());
        Assert.NotEmpty(unanswered);

        void Answer(string rule) =>
            Assert.True(unanswered.Remove(rule), $"No payload rule reads \"{rule}\" any more.");

        var exceptions = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var rule in doc["rules"]!.AsArray())
            if (rule!["exceptions"] is JsonArray allowed)
                foreach (var name in allowed) exceptions.Add(name!.ToString());
        Assert.Contains("index.md", exceptions);

        string payloads = Path.Combine(RepoRoot, "support", "example_content");
        var offenders = new List<string>();
        var withoutAManifest = new List<string>();
        int checkedPayloads = 0;

        // Mirrors setup_course.py's `top_level_allowed`, which is the function
        // that actually decides. Matching the manifest as TEXT — the first
        // version of this test — is not the same rule and passes on a
        // coincidental hit: "Curriculum" appears in `hidden` and
        // `curriculum_folder` as well as in `shared_folders`, so dropping it
        // from the list the installer reads would have gone unnoticed, which is
        // precisely the silent direction this rule exists to catch.
        static bool Installs(JsonNode manifest, string tree, string name, bool isFolder,
                             HashSet<string> exceptions)
        {
            if (exceptions.Contains(name)) return true;

            string folderKey = tree == "shared" ? "shared_folders" : "per_section_folders";
            string fileKey = tree == "shared" ? "shared_files" : "per_section_files";

            var allowed = manifest[isFolder ? folderKey : fileKey] as JsonArray;
            if (allowed is null) return false;

            foreach (var listed in allowed)
                if (string.Equals(listed!.ToString(), name, StringComparison.Ordinal)) return true;
            return false;
        }

        foreach (string payload in Directory.EnumerateDirectories(payloads))
        {
            string code = Path.GetFileName(payload);
            if (code.StartsWith('.')) continue;

            string manifestPath = Path.Combine(payload, "manifest.json");
            if (!File.Exists(manifestPath))
            {
                // Not skipped quietly: the wizard discovers a payload BY its
                // manifest, so a folder here without one is a course that looks
                // ready and reaches nobody.
                withoutAManifest.Add(code);
                continue;
            }
            checkedPayloads++;

            var manifest = JsonNode.Parse(File.ReadAllText(manifestPath))!;
            foreach (string tree in new[] { "shared", "per_section" })
            {
                string treePath = Path.Combine(payload, tree);
                if (!Directory.Exists(treePath)) continue;

                foreach (string entry in Directory.EnumerateFileSystemEntries(treePath))
                {
                    string name = Path.GetFileName(entry);
                    bool isFolder = Directory.Exists(entry);
                    if (!Installs(manifest, tree, name, isFolder, exceptions))
                        offenders.Add($"{code}/{tree}/{name}");
                }
            }
        }

        Assert.True(withoutAManifest.Count == 0,
            "These sit in support/example_content and carry no manifest.json, so the wizard finds " +
            "no payload for them: " + string.Join(", ", withoutAManifest));

        int payloadFolders = Directory.EnumerateDirectories(payloads)
            .Count(d => !Path.GetFileName(d).StartsWith('.'));
        Assert.Equal(payloadFolders, checkedPayloads);
        Assert.True(checkedPayloads >= 30,
            $"Only {checkedPayloads} payloads were checked; the repository ships far more, so the " +
            "walk is looking in the wrong place and this test is proving nothing.");

        Assert.True(offenders.Count == 0,
            "These sit in a payload's trees and the manifest's own allow-list for that tree does " +
            "not name them, so setup_course.py filters them out and no teacher ever sees them: " +
            string.Join(", ", offenders) + ". Naming a folder under `hidden` or `graded_folders` " +
            "is not enough — the installer reads shared_folders/shared_files for shared/ and " +
            "per_section_folders/per_section_files for per_section/, and matches the name exactly, " +
            "extension included.");
        Answer("Anything IN the payload trees must be named in the manifest");

        // The curriculum folder installs only when the teacher asked for it —
        // which is the wizard answer key `include_curriculum_pages`, and the
        // reason the wizard writes `hasContent && teacherSaidYes` rather than a
        // stale true. Answered by the format contract's own wizard test; named
        // here so the rule is not silently unowned.
        var wizardKeys = ContractLoader.LoadJson("file-formats.json")
            ["courseConfigKeys"]!["wizardAnswerKeys"]!["keys"]!.AsArray()
            .Select(k => k!["key"]!.ToString()).ToList();
        Assert.Contains("include_curriculum_pages", wizardKeys);
        Answer("The curriculum folder installs only when the teacher asked for curriculum");

        // The remaining three are about how the INSTALLER is written rather
        // than about what a payload contains, so nothing in this suite can
        // execute them: `setup_course.py`'s own tests and `lint_skeletons.py`
        // are where they live, and both run from verify.sh — which does not run
        // on Windows. Named rather than dropped, so a fourth joining them is a
        // decision somebody takes rather than a line nobody notices.
        foreach (string elsewhere in new[]
        {
            "The manifest is the WHOLE structure",
            "The manifest's lists are an ALLOW-LIST over the payload trees, not a packing list",
            "ADA1O is the reference payload",
        })
        {
            Assert.True(unanswered.Remove(elsewhere),
                $"\"{elsewhere}\" is recorded here as a payload rule this suite cannot execute, " +
                "and the contract no longer states it in those words.");
        }

        Assert.True(unanswered.Count == 0,
            "contracts/example-content.json states payload rules that no test here answers and " +
            "that are not on the list of rules answered elsewhere: " +
            string.Join("; ", unanswered.OrderBy(r => r, StringComparer.Ordinal)));
    }

    // ---- Which folders make up the recipe -----------------------------------

    /// <summary>
    /// The recipe's folders, as data, because there were four hand-maintained
    /// copies of this list and they drifted the moment a fifth folder was
    /// added.
    ///
    /// <para><c>scripts/test_recipe_folders.py</c> pins the other carriers, and
    /// it runs from <c>verify.sh</c> — which does not run on Windows at all. So
    /// this app's own copy was pinned by nothing here.</para>
    /// </summary>
    [Fact]
    public void TheRecipeFoldersAreTheOnesTheContractLists()
    {
        var doc = ContractLoader.LoadJson("toolchain.json");
        var expected = new List<string>();
        foreach (var folder in doc["recipeFolders"]!["folders"]!.AsArray())
            expected.Add(folder!.ToString());
        Assert.NotEmpty(expected);

        Assert.Equal(expected, ToolchainMirror.RecipeFolders.ToList());

        // The app's own project file ships them, and a folder bundled by
        // nobody arrives in a working folder as an empty one.
        string project = File.ReadAllText(Path.Combine(
            RepoRoot, "windows-app", "Plantoir", "Plantoir.csproj"));
        foreach (string folder in expected)
        {
            Assert.True(project.Contains($"..\\..\\{folder}\\", StringComparison.OrdinalIgnoreCase)
                     || project.Contains($"../../{folder}/", StringComparison.Ordinal),
                $"Plantoir.csproj does not bundle \"{folder}\", so it reaches no teacher's " +
                "working folder however faithfully it is mirrored.");
        }
    }

    // ---- What a scheduled deploy tells the teacher first ---------------------

    /// <summary>
    /// Not a refusal — a teacher may be deploying deliberately without them —
    /// but the plan NAMES the class pages students cannot see yet.
    ///
    /// <para>A deploy that runs perfectly at half six and puts up a site
    /// missing tomorrow's class is the failure worth catching while somebody is
    /// awake. The rule was in the contract and read by nobody on this side;
    /// WINDOWS-HANDOFF item 28 records separately that the interface does not
    /// yet CALL this — which this suite cannot see, since it cannot reference
    /// the interface project.</para>
    /// </summary>
    [Fact]
    public void AScheduledDeployNamesTheClassesStudentsCannotSeeYet()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var alsoSaid = doc["scheduledDeployRefusals"]!["alsoSaid"]!;
        Assert.Equal("list the class pages students cannot see yet, by name", alsoSaid["rule"]!.ToString());

        var plan = new ScheduledDeploy
        {
            CourseCode = "ICS3U",
            SectionNumber = 1,
            When = new DateTime(2026, 9, 8, 6, 30, 0),
            Destination = "Netlify",
            UnpublishedClasses = new[] { "Unit 2, Day 3", "Unit 2, Day 4" },
        };

        string described = plan.Describe();
        Assert.Contains("Unit 2, Day 3", described, StringComparison.Ordinal);
        Assert.Contains("Unit 2, Day 4", described, StringComparison.Ordinal);

        // By NAME is the whole rule: a count alone tells a teacher there is a
        // problem and not which class it is.
        Assert.Contains("not published yet", described, StringComparison.Ordinal);

        // And with nothing outstanding it says nothing about it, so the warning
        // means something on the occasions it appears.
        var clean = new ScheduledDeploy
        {
            CourseCode = "ICS3U",
            SectionNumber = 1,
            When = new DateTime(2026, 9, 8, 6, 30, 0),
            Destination = "Netlify",
            UnpublishedClasses = Array.Empty<string>(),
        };
        Assert.DoesNotContain("not published yet", clean.Describe(), StringComparison.Ordinal);
    }
}

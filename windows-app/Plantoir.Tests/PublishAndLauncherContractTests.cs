using System.Text.RegularExpressions;
using System.Reflection;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// Three `app-rules.json` lists that this suite mirrored by hand but never
/// READ — the " — Edited" marker's cases, the credential requests, and the
/// launcher's extra flags — plus the preview's ports.
///
/// <para><b>Mirroring by hand is not the same as running the list, and the
/// difference is the whole point of the 2026-09-06 contract audit.</b> A hand-written test
/// answers the cases that existed on the day somebody read the contract. It
/// cannot notice a case the mac ADDS, because nothing compares the two
/// collections — so the gap is invisible from both sides until a teacher finds
/// it. Every list here is therefore checked for COMPLETENESS as well as
/// correctness: each case must be answered by a named test, and a case nobody
/// answers fails naming itself.</para>
/// </summary>
public class PublishAndLauncherContractTests
{
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

    /// <summary>
    /// Asserts a test method of that name exists on that class and is a real
    /// test — the completeness check's other half.
    ///
    /// <para>Names rather than a shared HashSet drained across several methods,
    /// because xUnit builds a fresh instance for every <c>[Fact]</c> and runs
    /// them in no fixed order: a set filled by ten tests and emptied by an
    /// eleventh passes or fails depending on what ran, and reports nothing at
    /// all under <c>--filter</c>. A name map is order-free, and it keeps the
    /// per-case granularity that makes a failure readable.</para>
    /// </summary>
    private static void AnsweredBy(Type testClass, string methodName, string caseName)
    {
        var method = testClass.GetMethod(methodName,
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static);

        Assert.True(method is not null,
            $"The case \"{caseName}\" is said to be answered by {testClass.Name}.{methodName}, " +
            "and no such test exists — it has been renamed or deleted, and the case is now " +
            "answered by nothing.");

        Assert.True(method!.GetCustomAttributes<FactAttribute>().Any()
                    || method.GetCustomAttributes<TheoryAttribute>().Any(),
            $"{testClass.Name}.{methodName} answers the case \"{caseName}\" and is not a test " +
            "any more, so nothing runs it.");
    }

    // ---- When the " — Edited" marker is shown -----------------------------

    /// <summary>
    /// Every case in <c>publishedFreshness.whenShown</c> is answered by a test,
    /// and the two the mac added that this side had never answered are answered
    /// here.
    /// </summary>
    [Fact]
    public void EveryCaseForShowingTheEditedMarkerIsAnsweredByATest()
    {
        var answers = new Dictionary<string, (Type Class, string Method)>(StringComparer.Ordinal)
        {
            ["the section has never been published"] =
                (typeof(SectionPublishStateTests), nameof(SectionPublishStateTests.NeverPublished_ShowsNoEdits)),
            ["nothing has changed since the last publish"] =
                (typeof(SectionPublishStateTests), nameof(SectionPublishStateTests.UnchangedSincePublish_ShowsNoEdits)),
            ["a page this section alone uses has changed"] =
                (typeof(SectionPublishStateTests), nameof(SectionPublishStateTests.EditingAPageAfterPublish_ShowsEdits)),
            ["a page this section SHARES with other sections has changed"] =
                (typeof(SectionPublishStateTests), nameof(SectionPublishStateTests.SharedCourseLevelPageChanging_ShowsEditsForEverySection)),
            ["a page has been DELETED since the last publish"] =
                (typeof(SectionPublishStateTests), nameof(SectionPublishStateTests.DeletingAPageAfterPublish_ShowsEdits)),
            ["the stamp file cannot be read"] =
                (typeof(SectionPublishStateTests), nameof(SectionPublishStateTests.UnreadableStamp_ShowsNoEdits)),
            ["a SYMLINKED page, or a page inside a symlinked folder, has changed"] =
                (typeof(SectionPublishStateTests), nameof(SectionPublishStateTests.SymlinkedFolder_ContributesItsContents)),

            // Neither of these had an answer on this side until item 29 asked
            // the question. Both are below.
            ["course_config.json has changed"] =
                (typeof(PublishAndLauncherContractTests), nameof(ChangingTheConfigurationShowsEdits)),
            ["a page was restored from a backup that preserved its modification date and its size did not change"] =
                (typeof(PublishAndLauncherContractTests), nameof(ARestoredPageOfTheSameSizeAndDateIsNotNoticed)),
        };

        var unanswered = new List<string>();
        var doc = ContractLoader.LoadJson("app-rules.json");
        var cases = doc["publishedFreshness"]!["whenShown"]!.AsArray();
        Assert.NotEmpty(cases);

        foreach (var entry in cases)
        {
            string when = entry!["when"]!.ToString();
            if (!answers.TryGetValue(when, out var answer)) { unanswered.Add(when); continue; }
            AnsweredBy(answer.Class, answer.Method, when);
        }

        Assert.True(unanswered.Count == 0,
            "contracts/app-rules.json names cases for the \" — Edited\" marker that no test on " +
            "this side answers: " + string.Join("; ", unanswered) + ". A case added on the mac " +
            "is behaviour a teacher gets there and not here, and nothing else would have said so.");
    }

    /// <summary>
    /// The configuration is an input to the built site — fonts, the sidebar,
    /// the coverage map — so changing it changes what students see as surely as
    /// editing a page does.
    /// </summary>
    [Fact]
    public void ChangingTheConfigurationShowsEdits()
    {
        string course = Directory.CreateTempSubdirectory("publish-freshness-config").FullName;
        Directory.CreateDirectory(Path.Combine(course, "section1", "Classes"));
        File.WriteAllText(Path.Combine(course, "section1", "Classes", "Day 1.md"), "hello");
        File.WriteAllText(Path.Combine(course, "course_config.json"), """{"course_code": "ICS3U"}""");

        SectionPublishState.RecordPublish(
            course, 1, SectionPublishState.Fingerprint(course, 1), new[] { "netlify" });
        Assert.False(SectionPublishState.HasUnpublishedEdits(course, 1));

        Thread.Sleep(20);
        File.WriteAllText(Path.Combine(course, "course_config.json"),
            """{"course_code": "ICS3U", "show_grade_in_title": true}""");

        Assert.True(SectionPublishState.HasUnpublishedEdits(course, 1),
            "course_config.json is an input to the built site, so changing it must mark the " +
            "section edited — a teacher who changes the sidebar and publishes nothing has a " +
            "live site that no longer matches their settings.");
    }

    /// <summary>
    /// The one accepted false negative, written down rather than left to be
    /// rediscovered as a bug: the fingerprint is of the file INVENTORY — each
    /// file's path, size and modification date — so a page restored from a
    /// backup that preserved both reads as unchanged.
    ///
    /// <para>The price of never reading file contents, and cheap at the price:
    /// publishing is never BLOCKED by the marker, so the cost is a teacher not
    /// being reminded, not a teacher being stopped.</para>
    /// </summary>
    [Fact]
    public void ARestoredPageOfTheSameSizeAndDateIsNotNoticed()
    {
        string course = Directory.CreateTempSubdirectory("publish-freshness-restore").FullName;
        string page = Path.Combine(course, "section1", "Classes", "Day 1.md");
        Directory.CreateDirectory(Path.GetDirectoryName(page)!);
        File.WriteAllText(page, "hello there");
        var when = File.GetLastWriteTimeUtc(page);

        SectionPublishState.RecordPublish(
            course, 1, SectionPublishState.Fingerprint(course, 1), new[] { "netlify" });

        // Restored from a backup: different words, same length, same date.
        File.WriteAllText(page, "HELLO THERE");
        File.SetLastWriteTimeUtc(page, when);

        Assert.False(SectionPublishState.HasUnpublishedEdits(course, 1),
            "This is the accepted false negative. If it has started reporting an edit, the " +
            "fingerprint has begun reading file CONTENTS — which is a real change in cost, " +
            "since it runs every time a window comes to the front.");
    }

    // ---- When a publish is recorded --------------------------------------

    /// <summary>
    /// A section is marked published only when every destination it is
    /// configured for succeeded. A course publishing to two hosts, one of which
    /// failed, has not published, and its marker must stay up.
    /// </summary>
    [Fact]
    public void APublishIsRecordedOnlyWhenEveryDestinationSucceeded()
    {
        var netlify = new CourseConfiguration.DeployDestination { Type = "netlify" };
        var none = Array.Empty<CourseConfiguration.DeployDestination>();

        // Each contract case, as the outcome the runner would produce for it.
        var outcomes = new Dictionary<string, MultiDestinationDeployRunner.Outcome>(StringComparer.Ordinal)
        {
            ["every configured destination succeeded"] = new(true, none),
            ["one of two destinations failed"] = new(true, new[] { netlify }),
            // Nothing succeeded, in all three cases, and for the marker that is
            // the only fact that matters: cancelled, build-failed and never-ran
            // are different stories about the same unpublished section.
            ["the publish was cancelled or stopped"] = new(false, none),
            ["the shared build failed"] = new(false, none),
            ["no destination ran at all"] = new(false, none),
        };

        var unanswered = new List<string>();
        var doc = ContractLoader.LoadJson("app-rules.json");
        foreach (var entry in doc["publishedFreshness"]!["whenRecorded"]!.AsArray())
        {
            // The list is not uniformly keyed: five entries are `when` cases,
            // one records the MOMENT the fingerprint is taken and one the path
            // a scheduled deploy takes. Both of the latter are answered by
            // named tests rather than by an outcome.
            if (entry!["when"] is null) continue;

            string when = entry["when"]!.ToString();
            if (!outcomes.TryGetValue(when, out var outcome)) { unanswered.Add(when); continue; }

            Assert.Equal(entry["expectRecorded"]!.GetValue<bool>(), outcome.AllSucceeded);
        }

        Assert.True(unanswered.Count == 0,
            "contracts/app-rules.json names publish outcomes this test does not decide: " +
            string.Join("; ", unanswered) + ".");
    }

    /// <summary>
    /// The two entries in <c>whenRecorded</c> that are not `when` cases: WHEN
    /// the fingerprint is taken, and that an overnight deploy records the same
    /// way. Both are answered by tests elsewhere; this pins that they still
    /// exist, and fails if the contract grows a third.
    /// </summary>
    [Fact]
    public void TheTwoRulesThatAreNotOutcomesAreAnsweredByTests()
    {
        var answers = new Dictionary<string, (Type Class, string Method)>(StringComparer.Ordinal)
        {
            ["before anything runs - before the BUILD, not merely before the first upload"] =
                (typeof(SectionPublishStateTests), nameof(SectionPublishStateTests.UnchangedSincePublish_ShowsNoEdits)),
            ["a deploy scheduled to run overnight records the same way"] =
                (typeof(ScheduledDeployCompletionTests), nameof(ScheduledDeployCompletionTests.ConsumePending_StampsPublishState_AndDeletesTheSentinel)),
        };

        var unanswered = new List<string>();
        var doc = ContractLoader.LoadJson("app-rules.json");
        foreach (var entry in doc["publishedFreshness"]!["whenRecorded"]!.AsArray())
        {
            if (entry!["when"] is not null) continue;

            string rule = (entry["moment"] ?? entry["path"])!.ToString();
            if (!answers.TryGetValue(rule, out var answer)) { unanswered.Add(rule); continue; }
            AnsweredBy(answer.Class, answer.Method, rule);
        }

        Assert.True(unanswered.Count == 0,
            "contracts/app-rules.json names rules about recording a publish that no test here " +
            "claims: " + string.Join("; ", unanswered) + ".");
    }

    // ---- What a teacher is asked for, and how it is shown -----------------

    /// <summary>
    /// Every credential this app can ask for is described by the contract, and
    /// every one the contract describes exists here.
    ///
    /// <para><c>credentialRequests.requests</c> is already checked the first
    /// way, contract → code. This is the other direction, by reflection over
    /// the real definitions: a request ADDED here and not written down is one
    /// the other app will not know to show, and no amount of walking the
    /// contract can see it.</para>
    /// </summary>
    [Fact]
    public void EveryCredentialThisAppAsksForIsInTheContract()
    {
        var doc = ContractLoader.LoadJson("app-rules.json");
        var described = new HashSet<string>(StringComparer.Ordinal);
        foreach (var entry in doc["credentialPrompts"]!["everyRequest"]!.AsArray())
            described.Add(entry!["name"]!.ToString());
        Assert.NotEmpty(described);

        var defined = new List<CredentialRequest>();
        foreach (var field in typeof(CredentialRequests).GetFields(BindingFlags.Public | BindingFlags.Static))
            if (field.GetValue(null) is CredentialRequest request) defined.Add(request);

        Assert.NotEmpty(defined);
        foreach (var request in defined)
        {
            Assert.True(described.Contains(request.Name),
                $"This app can ask a teacher for \"{request.Name}\" and no contract describes it. " +
                "The other app cannot show a request it has never been told about, so the same " +
                "first publish stops at a prompt on one platform and asks properly on the other.");
        }
    }

    /// <summary>
    /// Whether a typed answer is hidden on screen, and where the teacher is
    /// sent to find it. A token shown in the clear on a projector is the kind
    /// of mistake that is only noticed afterwards.
    /// </summary>
    [Fact]
    public void EachCredentialIsHiddenOrShownAsTheContractSays()
    {
        var doc = ContractLoader.LoadJson("app-rules.json");
        var byName = new Dictionary<string, CredentialRequest>(StringComparer.Ordinal);
        foreach (var field in typeof(CredentialRequests).GetFields(BindingFlags.Public | BindingFlags.Static))
            if (field.GetValue(null) is CredentialRequest request) byName[request.Name] = request;

        foreach (var entry in doc["credentialPrompts"]!["everyRequest"]!.AsArray())
        {
            string name = entry!["name"]!.ToString();
            Assert.True(byName.TryGetValue(name, out var request),
                $"The contract describes a credential request called \"{name}\" that this app " +
                "does not have.");

            Assert.Equal(entry["expectSecret"]!.GetValue<bool>(), request!.IsSecret);
            Assert.Equal(entry["expectLink"]!.ToString(), request.LinkAddress ?? "");
        }
    }

    // ---- The launcher's extra flags --------------------------------------

    /// <summary>
    /// The flags <c>deploy</c> accepts beyond a course and a section.
    ///
    /// <para><c>--image</c> is in the contract's list and is the MAC's alone:
    /// <c>deploy.sh</c> takes it, <c>deploy.ps1</c> does not, and this platform
    /// has had no image to name since it dropped Docker on 2026-08-19. The
    /// contract now says so; before item 29 nothing did, and the honest fix was
    /// to record the divergence rather than add a dead flag to a launcher so a
    /// test would go green.</para>
    /// </summary>
    [Fact]
    public void TheDeployLauncherAcceptsTheExtraFlagsTheContractGivesIt()
    {
        var doc = ContractLoader.LoadJson("app-rules.json");
        string launcher = File.ReadAllText(Path.Combine(RepoRoot, "deploy.ps1"));

        var flags = doc["launcherFlags"]!["deployExtras"]!.AsArray();
        Assert.NotEmpty(flags);

        foreach (var entry in flags)
        {
            string flag = entry!["flag"]!.ToString();
            string name = flag.Split(' ')[0];

            // The PARSER, not the usage text. `--diagnose` appears three times
            // in deploy.ps1 — twice in the help — so plain containment would
            // stay green after the flag stopped being accepted, which is the
            // whole failure this list is meant to catch: the launcher prints
            // "Unknown option" and exits, and to a teacher that is a publish
            // that just did not start. Coupled to the `'^--flag$'` switch idiom
            // both launchers use on purpose; a rewrite that changes the idiom
            // should change this line with it.
            bool parsed = launcher.Contains($"'^{name}$'", StringComparison.Ordinal)
                       || launcher.Contains($"'^{name}=", StringComparison.Ordinal);

            if (entry["macOnly"]?.GetValue<bool>() == true)
            {
                Assert.False(parsed,
                    $"\"{name}\" is recorded as the mac's alone and deploy.ps1 now parses it. " +
                    "If this platform has grown a use for it, take the macOnly note off the " +
                    "contract entry rather than leaving the two disagreeing.");
                continue;
            }

            Assert.True(parsed,
                $"deploy.ps1 does not parse \"{name}\", which the contract says a teacher — or " +
                "somebody helping one — can pass it.");
        }
    }

    /// <summary>
    /// <c>--non-interactive</c> is FORWARDED to the Python, not merely parsed.
    /// </summary>
    /// <remarks>
    /// <para>The test above checks the parser, which is not the property that
    /// matters here. <c>deploy.ps1</c> builds <c>$deployArgs</c> by hand and
    /// then invokes <c>deploy.py</c> with it, and the site-name question — the
    /// one that blocked a harness for 45 minutes — lives in the PYTHON. A
    /// launcher that took the flag, never added it to <c>$deployArgs</c> and
    /// exited <c>$nativeExit</c> would leave a green suite and an unchanged
    /// hang, which is exactly the shape of failure this whole piece of work is
    /// about.</para>
    ///
    /// <para>Coupled to the <c>$deployArgs +=</c> idiom the launcher uses for
    /// every other flag; a rewrite that changes the idiom should change this
    /// line with it.</para>
    /// </remarks>
    [Fact]
    public void TheDeployLauncherForwardsNonInteractiveToThePython()
    {
        string launcher = File.ReadAllText(Path.Combine(RepoRoot, "deploy.ps1"));

        Assert.Contains("$deployArgs += '--non-interactive'", launcher, StringComparison.Ordinal);

        // And the guard is the flag itself, not something that always fires: a
        // launcher that passed it unconditionally would refuse every question a
        // teacher standing at the keyboard is entitled to answer.
        Assert.Contains("if ($NON_INTERACTIVE) { $deployArgs += '--non-interactive' }",
                        launcher, StringComparison.Ordinal);
    }

    /// <summary>
    /// Every question <c>deploy.ps1</c> asks is guarded, and the guard comes
    /// BEFORE the question.
    /// </summary>
    /// <remarks>
    /// One unguarded <c>Read-Host</c> is one way for a scheduled publish to sit
    /// waiting at half six with nobody there, which is the whole failure. The
    /// launcher asks four things — the 'Open' course-code correction, the
    /// Cloudflare Account ID, and the two token prompts — and this fails if a
    /// fifth is added without a guard.
    /// </remarks>
    [Fact]
    public void EveryQuestionTheDeployLauncherAsksIsGuarded()
    {
        var unguarded = UnguardedQuestionLines("deploy.ps1");

        Assert.True(unguarded.Count == 0,
            "deploy.ps1 asks a question with no Assert-CanAsk above it, at line(s) " +
            string.Join(", ", unguarded) + ". Under --non-interactive that question is put to " +
            "nobody: the publish either waits for ever or takes a default and publishes the " +
            "teacher's site to an address they never chose.");
    }

    /// <summary>
    /// Every question <c>preview.ps1</c> asks is guarded too, and the guard
    /// comes BEFORE the question.
    /// </summary>
    /// <remarks>
    /// <para><b>A build launcher needs this as much as the publishing one, and
    /// that is the part that is easy to miss.</b> A scheduled publish BUILDS
    /// before it publishes — <c>TaskScheduling.WriteWrapperScript</c> runs
    /// <c>preview.ps1 &lt;course&gt; &lt;section&gt; --build-only</c> as its
    /// first step — so every question this script asks at half six in the
    /// morning is put to nobody just as surely.</para>
    ///
    /// <para>What happens then is worse than a hang. A <c>Read-Host</c> with no
    /// console reads end of input and returns empty, and both questions here
    /// have a DEFAULT: the course-code guard's is "yes, fix it", which
    /// retargets the build at a DIFFERENT course code and announces it to
    /// nobody — and the publish that follows then succeeds against the wrong
    /// course, with nothing anywhere looking wrong.</para>
    ///
    /// <para><b>This script asks TWO things and the shared contract lists
    /// one.</b> <c>preview.sh</c> has only the course-code guard;
    /// "Continue anyway?" — the warning when a section is not listed in
    /// <c>course_config.json</c> — is this platform's alone, so
    /// <c>app-rules.json</c> → <c>launcherFlags.nonInteractive.refusals</c>
    /// does not name it. That file is GENERATED on the mac, so the entry was
    /// asked for by issue rather than added here; this test is what holds the
    /// behaviour in the meantime.</para>
    /// </remarks>
    [Fact]
    public void EveryQuestionThePreviewLauncherAsksIsGuarded()
    {
        var unguarded = UnguardedQuestionLines("preview.ps1");

        Assert.True(unguarded.Count == 0,
            "preview.ps1 asks a question with no Assert-CanAsk above it, at line(s) " +
            string.Join(", ", unguarded) + ". A scheduled publish builds before it publishes, so " +
            "that question is put to nobody — and an unanswered [Y/n] takes its default, which " +
            "for the course-code guard means building a DIFFERENT course and publishing it.");

        // And the flag is really parsed, not merely mentioned in the help text.
        // A launcher that printed it and then said "Unknown option: " is, to a
        // teacher, a scheduled publish that simply did not happen.
        Assert.Contains("'--non-interactive'               { $NON_INTERACTIVE = $true",
                        File.ReadAllText(Path.Combine(RepoRoot, "preview.ps1")),
                        StringComparison.Ordinal);
    }

    /// <summary>
    /// Every flag the SCHEDULED wrapper hands a launcher is one that launcher
    /// actually accepts.
    /// </summary>
    /// <remarks>
    /// <para><b>The gap this closes is a whole class, and it was nearly walked
    /// into on 2026-09-09.</b> The wrapper is generated C# and the launchers
    /// are hand-written PowerShell, and nothing joined the two: adding
    /// <c>--non-interactive</c> to the wrapper's build leg without adding it to
    /// <c>preview.ps1</c>'s parser would have made that launcher print
    /// "Unknown option: --non-interactive" and exit 1 — whereupon the wrapper's
    /// own <c>if ($buildExit -ne 0)</c> guard publishes nothing and says so to
    /// a console nobody is watching. Every scheduled publish on this machine
    /// would simply stop happening, silently, and every existing test would
    /// stay green.</para>
    ///
    /// <para><c>AppRules_LauncherFlags_MatchesContract</c> checks
    /// contract→script and never wrapper→script, which is the direction this
    /// one runs. Both are needed: a flag can be in the contract and not the
    /// wrapper, or in the wrapper and not the contract.</para>
    ///
    /// <para>Coupled to the <c>'^--flag$'</c> and <c>'--flag'</c> switch idioms
    /// the two launchers use; a rewrite that changes the idiom should change
    /// this with it.</para>
    /// </remarks>
    [Fact]
    public void EveryFlagTheScheduledWrapperPassesIsOneTheLauncherAccepts()
    {
        string folder = Directory.CreateTempSubdirectory("plantoir-wrapper-flags").FullName;
        string? wrapper = null;
        try
        {
            File.WriteAllText(Path.Combine(folder, "deploy.ps1"), "# stub");
            File.WriteAllText(Path.Combine(folder, "preview.ps1"), "# stub");

            wrapper = TaskScheduling.WriteWrapperScript(
                $"Plantoir-flagcheck-{Guid.NewGuid():N}", folder,
                Path.Combine(folder, "deploy.ps1"), "ICS3U", 1,
                Path.Combine(folder, "courses", "ICS3U"), Array.Empty<string>(),
                new[]
                {
                    new CourseConfiguration.DeployDestination("cloudflare_pages", ""),
                    new CourseConfiguration.DeployDestination("local_folder", folder),
                },
                "0123456789abcdef0123456789abcdef");
            Assert.NotNull(wrapper);

            var launchers = new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["preview.ps1"] = File.ReadAllText(Path.Combine(RepoRoot, "preview.ps1")),
                ["deploy.ps1"] = File.ReadAllText(Path.Combine(RepoRoot, "deploy.ps1")),
            };

            var unknown = new List<string>();
            foreach (string line in File.ReadAllLines(wrapper!))
            {
                string which = line.Contains("preview.ps1", StringComparison.OrdinalIgnoreCase)
                    ? "preview.ps1"
                    : line.Contains("deploy.ps1", StringComparison.OrdinalIgnoreCase) ? "deploy.ps1" : "";
                // Only the lines that RUN one. The generated script names both
                // in comments and in the path it builds for Start-Process.
                if (which.Length == 0) continue;
                if (!line.TrimStart().StartsWith("& ", StringComparison.Ordinal)
                    && !line.Contains("$buildArgs =", StringComparison.Ordinal)) continue;

                foreach (string word in line.Split(' ', '\'', '"'))
                {
                    if (!word.StartsWith("--", StringComparison.Ordinal)) continue;
                    string flag = word.Trim();
                    string parser = launchers[which];
                    bool accepted = parser.Contains($"'^{flag}$'", StringComparison.Ordinal)
                                 || parser.Contains($"'^{flag}=", StringComparison.Ordinal)
                                 || parser.Contains($"'{flag}'", StringComparison.Ordinal);
                    if (!accepted) unknown.Add($"{which} does not parse {flag}");
                }
            }

            // Distinct: the build leg appears twice in the wrapper (captured
            // and fallback), so one missing flag would otherwise be reported
            // twice in the same sentence.
            unknown = unknown.Distinct(StringComparer.Ordinal).ToList();
            Assert.True(unknown.Count == 0,
                "The scheduled wrapper passes a flag its launcher would reject: " +
                string.Join("; ", unknown) + ". That launcher prints \"Unknown option\" and exits, " +
                "the wrapper publishes nothing, and nobody is awake to read either — so every " +
                "scheduled publish stops happening and no test says so.");
        }
        finally
        {
            if (wrapper is not null) try { File.Delete(wrapper); } catch { }
            try { Directory.Delete(folder, recursive: true); } catch { }
        }
    }

    /// <summary>
    /// Which lines of a launcher ask a question with no <c>Assert-CanAsk</c>
    /// directly above them. One scanner for both launchers, because the rule is
    /// one rule.
    /// </summary>
    /// <remarks>
    /// <para>Three properties, each of which was a hole first.</para>
    ///
    /// <para><b>The guard must be on the line IMMEDIATELY above the
    /// question.</b> Anywhere else is a guard somebody moves code past.</para>
    ///
    /// <para><b>A COMMENTED-OUT guard is not a guard.</b> The first version of
    /// this counted one — proved by commenting a real guard out and watching
    /// the test stay green, which is the only way that kind of hole is ever
    /// found.</para>
    ///
    /// <para><b>A COMMENT that merely mentions Read-Host is not a
    /// question.</b> Found on 2026-09-09, the moment this scanner was pointed
    /// at preview.ps1 — whose own explanation of why the flag exists says the
    /// words "a Read-Host with no console reads end of input". The scan
    /// reported two unguarded questions that do not exist. A test that fails
    /// for prose is one somebody deletes.</para>
    /// </remarks>
    private static List<int> UnguardedQuestionLines(string launcherFileName)
    {
        var lines = File.ReadAllLines(Path.Combine(RepoRoot, launcherFileName));
        var unguarded = new List<int>();

        for (int i = 0; i < lines.Length; i++)
        {
            string line = lines[i].TrimStart();
            if (line.StartsWith("#", StringComparison.Ordinal)) continue;
            if (!line.Contains("Read-Host", StringComparison.Ordinal)) continue;

            string above = i == 0 ? "" : lines[i - 1].TrimStart();
            if (above.StartsWith("#", StringComparison.Ordinal)
                || !above.Contains("Assert-CanAsk", StringComparison.Ordinal))
                unguarded.Add(i + 1);
        }

        return unguarded;
    }

    /// <summary>
    /// The same for <c>deploy.sh</c> — and with the rule that caught the one
    /// bug a "guard on the line above" check could not see.
    /// </summary>
    /// <remarks>
    /// <para>The mac's launcher is not run on this machine, so this is the only
    /// gate it has here. Worth having anyway: the flag is in
    /// <c>app-rules.json</c>, both suites read it, and a guard missing from one
    /// launcher is a scheduled publish that hangs on one platform only.</para>
    ///
    /// <para><b>A guard inside a function whose output is CAPTURED does
    /// nothing</b>, and that is not a hypothetical. The Cloudflare Account ID
    /// guard was first written inside <c>prompt_for_cf_account</c>, which is
    /// called as <c>CF_ACCOUNT="$(prompt_for_cf_account)"</c> — a subshell. The
    /// refusal text went into the VARIABLE instead of onto the screen, and its
    /// <c>exit 3</c> exited the subshell, so the script reported an ordinary
    /// failure and printed nothing at all. Reproduced before it was fixed. So
    /// this asserts the guard is at the TOP LEVEL: in a function body, the
    /// caller decides where its output goes, and the guard cannot know.</para>
    /// </remarks>
    [Fact]
    public void EveryQuestionTheMacDeployLauncherAsksIsGuardedAtTheTopLevel()
    {
        var lines = File.ReadAllLines(Path.Combine(RepoRoot, "deploy.sh"));
        var unguarded = new List<string>();
        bool insideAFunction = false;
        string function = "";

        for (int i = 0; i < lines.Length; i++)
        {
            string line = lines[i];
            // Good enough for this file's shape, which declares functions as
            // `name() {` at column zero and closes them with `}` at column zero.
            var declared = Regex.Match(line, @"^([A-Za-z_][A-Za-z0-9_]*)\(\) \{");
            if (declared.Success) { insideAFunction = true; function = declared.Groups[1].Value; }
            else if (line.StartsWith("}", StringComparison.Ordinal)) { insideAFunction = false; function = ""; }

            if (!Regex.IsMatch(line, @"(^|\s)read -r[sp]*p\s")) continue;

            string above = i == 0 ? "" : lines[i - 1].TrimStart();
            bool guarded = !above.StartsWith("#", StringComparison.Ordinal)
                           && above.Contains("assert_can_ask", StringComparison.Ordinal);

            if (insideAFunction)
            {
                // One function is allowed to hold a question, and it is checked
                // separately below rather than waved through: the guard sits at
                // its single call site, where the output goes to the screen and
                // the exit code is the script's.
                if (function != GuardedAtItsCallSite)
                    unguarded.Add($"line {i + 1} is inside {function}(), where a guard's output " +
                                  "and exit code belong to whoever calls it");
            }
            else if (!guarded)
                unguarded.Add($"line {i + 1} has no assert_can_ask above it");
        }

        Assert.True(unguarded.Count == 0,
            "deploy.sh asks a question that --non-interactive cannot refuse: " +
            string.Join("; ", unguarded) + ". Under a scheduled publish that question is put to " +
            "nobody, and the run either waits for ever or takes a default.");

        // The exception is only safe while it stays true, so it is ASSERTED
        // rather than assumed: exactly one call site, and a guard immediately
        // above it. A second caller, or a guard that drifts away from the call,
        // and the question is unanswerable again with nothing to say so.
        var callers = new List<int>();
        for (int i = 0; i < lines.Length; i++)
            if (lines[i].Contains(GuardedAtItsCallSite + ")", StringComparison.Ordinal)
                && !lines[i].TrimStart().StartsWith("#", StringComparison.Ordinal)
                && !Regex.IsMatch(lines[i], @"^" + GuardedAtItsCallSite + @"\(\) \{"))
                callers.Add(i);

        int caller = Assert.Single(callers);
        Assert.Contains("assert_can_ask", lines[caller - 1], StringComparison.Ordinal);
    }

    /// <summary>
    /// The one function in <c>deploy.sh</c> that asks a question, guarded at its
    /// call site because its OUTPUT is captured.
    /// </summary>
    /// <remarks>
    /// <c>CF_ACCOUNT="$(prompt_for_cf_account)"</c> is a subshell: a refusal
    /// printed inside it lands in the variable rather than on the screen, and
    /// its <c>exit 3</c> exits the subshell. Reproduced before it was fixed —
    /// nothing printed, and the wrong exit code, so the launchd wrapper would
    /// read it as an ordinary failure and leave no note.
    /// </remarks>
    private const string GuardedAtItsCallSite = "prompt_for_cf_account";

    // ---- The address handed to the teacher's browser ----------------------

    /// <summary>
    /// `localhost` becomes `127.0.0.1` in the address a preview hands the
    /// browser.
    ///
    /// <para>The reason is the mac's — Safari tries IPv6 (::1) first and the
    /// container publishes IPv4 only, which reads to a teacher as "the server
    /// dropped the connection". This platform does the same rewrite, and the
    /// contract's own note asks each side to check whether ITS default browser
    /// needs it: measured here on 2026-08-23 against a real preview, Edge was
    /// indistinguishable either way, so the rewrite is a harmless no-op rather
    /// than a fix for an observed problem (contracts/README.md). Kept, because it
    /// costs nothing — and pinned here, because a no-op nobody tests is a
    /// no-op somebody eventually deletes.</para>
    /// </summary>
    [Fact]
    public void ThePreviewAddressIsMadeBrowserSafe()
    {
        var doc = ContractLoader.LoadJson("app-rules.json");
        var cases = doc["linkRules"]!["browserSafe"]!["cases"]!.AsArray();
        Assert.NotEmpty(cases);

        foreach (var entry in cases)
        {
            string input = entry!["input"]!.ToString();
            string expected = entry["expect"]!.ToString();

            // The rewrite happens where the address is READ, out of the
            // launcher's own announcement, so it is exercised the way it runs.
            var found = OutputParsers.PreviewAddress($"Preview will be available at: {input}");

            Assert.True(found is not null,
                $"The preview address \"{input}\" was not recognised in the launcher's " +
                "announcement at all, so the teacher is handed nothing to click.");
            Assert.Equal(expected, found!.ToString());
        }
    }

    // ---- The preview's ports ---------------------------------------------

    /// <summary>
    /// Several previews run at once and must not collide. The numbers are the
    /// toolchain's rather than either app's, which is why they are in the
    /// contract at all.
    /// </summary>
    [Fact]
    public void ThePreviewUsesThePortsTheToolchainReserves()
    {
        var doc = ContractLoader.LoadJson("app-rules.json");
        var ports = doc["previewPorts"]!;

        var expected = new List<int>();
        foreach (var port in ports["containerPorts"]!.AsArray()) expected.Add(port!.GetValue<int>());

        Assert.Equal(expected, PreviewLeases.AvailablePorts.ToList());
    }
}

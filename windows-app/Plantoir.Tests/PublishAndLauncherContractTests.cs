using System.Reflection;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// Three `app-rules.json` lists that this suite mirrored by hand but never
/// READ — the " — Edited" marker's cases, the credential requests, and the
/// launcher's extra flags — plus the preview's ports.
///
/// <para><b>Mirroring by hand is not the same as running the list, and the
/// difference is the whole of contracts/README.md.</b> A hand-written test
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

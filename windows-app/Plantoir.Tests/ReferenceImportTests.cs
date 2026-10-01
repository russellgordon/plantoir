using System.Diagnostics;
using System.Text.Json.Nodes;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Models;
using Xunit;
using Xunit.Abstractions;

namespace Plantoir.Tests;

/// <summary>
/// Import Courses for Reference… (#244, mac #206 branch B; #245's claim, #287's
/// trail, #298's add-ons). Contract lists deserialised and run with floors;
/// every tree under a temp folder; every lock removed in Dispose.
/// </summary>
[Collection(ReferenceDiskCollection.Name)]
public class ReferenceImportTests : IDisposable
{
    private readonly string _root = Directory.CreateTempSubdirectory("plantoir-import").FullName;
    private readonly ITestOutputHelper _output;
    private static readonly DateOnly Today = new(2026, 9, 20);

    public ReferenceImportTests(ITestOutputHelper output)
    {
        _output = output;
        ReferenceStaging.ForgetEveryClaimForTesting();
    }

    public void Dispose()
    {
        ReferenceStaging.ForgetEveryClaimForTesting();
        ReferenceFixtures.Remove(_root);
    }

    private static JsonNode Importing => ContractLoader.LoadJson("shared-rules.json")["referenceCourses"]!["importing"]!;

    // ---- The contract's pure lists -----------------------------------------------

    [Fact]
    public void EverySentenceIsTheContracts()
    {
        int compared = 0;
        foreach (var (key, value) in Importing["wording"]!.AsObject())
        {
            if (ReferenceImport.IsNotSaidHere(key)) continue;
            Assert.True(ReferenceImport.Wording.TryGetValue(key, out string? mine), $"importing.wording.{key} is not said here");
            Assert.Equal(value!.ToString(), mine);
            compared++;
        }
        Assert.True(compared >= 26, $"only {compared}");
    }

    [Fact]
    public void TheLeftBehindNamesAreTheContracts()
    {
        var names = Importing["leftBehind"]!["names"]!.AsArray().Select(n => n!["name"]!.ToString()).OrderBy(n => n, StringComparer.Ordinal);
        Assert.Equal(names, ReferenceImport.LeftBehindNames.OrderBy(n => n, StringComparer.Ordinal));
        Assert.True(names.Count() >= 15);
    }

    [Fact]
    public void TheSchoolYearProposedIsTheContracts()
    {
        var cases = Importing["schoolYearProposed"]!["cases"]!.AsArray();
        foreach (var c in cases)
        {
            var years = c!["pageYears"]!.AsArray().Select(y => y!.GetValue<int>());
            int? expected = c["expect"] is null ? null : c["expect"]!.GetValue<int>();
            Assert.True(expected == ReferenceImport.SuggestedSchoolYear(years, DateOnly.Parse(c["today"]!.ToString())), c["name"]!.ToString());
        }
        Assert.True(cases.Count >= 4);
    }

    [Fact]
    public void TheFolderShapesAreTheContractsShapes()
    {
        var cases = Importing["foldersAccepted"]!["cases"]!.AsArray();
        int ran = 0;
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            string tree = Path.Combine(_root, $"shape{ran}");
            ReferenceFixtures.Build(tree, c["tree"]!.AsArray());
            string chosen = Path.GetFullPath(Path.Combine(tree, c["choose"]!.ToString().Replace('/', '\\')));
            string? open = null;
            if (c["isTheFolderAlreadyOpen"]?.GetValue<bool>() == true) open = chosen;
            if (c["openFolderIsTheRoot"]?.GetValue<bool>() == true) open = tree;
            if (c["openFolderIsAChildNamed"] is { } child) open = Path.Combine(tree, child.ToString());
            var (found, refusal) = ReferenceImport.Resolve(chosen, open, Today);
            if (c["expect"]!.ToString() == "accepted")
            {
                Assert.True(found is not null, $"{name}: refused with {refusal}");
                Assert.Equal(c["expectCourses"]!.AsArray().Select(x => x!.ToString()), found!.Courses.Select(x => x.FolderName));
                Assert.Equal(c["expectTicked"]!.AsArray().Select(x => x!.ToString()).OrderBy(x => x), found.TickedWhenOpened.OrderBy(x => x));
            }
            else
            {
                string folder = Path.GetFileName(chosen);
                string expected = c["refusal"]!.ToString() switch
                {
                    "noCoursesThere" => ReferenceImport.NoCoursesThere(folder),
                    "theFolderYouHaveOpen" => ReferenceImport.ThatIsTheFolderYouHaveOpen,
                    "insideTheFolderYouHaveOpen" => ReferenceImport.InsideTheFolderYouHaveOpen(folder),
                    "holdsTheFolderYouHaveOpen" => ReferenceImport.HoldsTheFolderYouHaveOpen(folder),
                    var other => throw new InvalidOperationException("unknown refusal " + other),
                };
                Assert.Null(found);
                Assert.Equal(expected, refusal);
            }
            ran++;
        }
        Assert.True(ran >= 9, $"only {ran}");
    }

    // ---- The claim: oneImportPerCourseAtATime -------------------------------------

    [Fact]
    public void EveryClaimCaseThroughTheRealClaim()
    {
        var cases = Importing["oneImportPerCourseAtATime"]!["cases"]!.AsArray();
        int ran = 0;
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            var given = c["given"]!;
            var expect = c["expect"]!;
            string courses = Directory.CreateDirectory(Path.Combine(_root, $"claim{ran}", "courses")).FullName;
            const string folder = "ICS4U-2025";
            string staging = Path.Combine(courses, ReferenceStaging.StagingName(folder));
            Process? other = null;
            try
            {
                ReferenceStaging.ForgetEveryClaimForTesting();
                if (given["claimedInThisApp"]!.GetValue<bool>()) ReferenceStaging.ClaimInThisAppForTesting(courses, folder);
                if (given["anotherLiveLease"]!.GetValue<bool>())
                {
                    other = Process.Start(new ProcessStartInfo("cmd.exe", "/c ping -n 60 127.0.0.1 > nul") { CreateNoWindow = true, UseShellExecute = false })!;
                    Directory.CreateDirectory(ReferenceStaging.ActivityDirectory(courses));
                    File.WriteAllText(Path.Combine(ReferenceStaging.ActivityDirectory(courses), $"{folder}.import.{other.Id}.lease"),
                        $"{other.Id}\ncmd\n{DateTime.UtcNow:O}\n");
                }
                string leftover = given["leftover"]!.ToString();
                if (leftover != "none")
                {
                    Directory.CreateDirectory(staging);
                    File.WriteAllText(Path.Combine(staging, "half.md"), "half-made");
                }
                string create = given["create"]!.ToString();
                var claim = ReferenceStaging.TryClaim(courses, folder, ReferenceImport.AlreadyBeingImported,
                    removeLeftover: leftover == "cannotBeRemoved" ? _ => false : null,
                    create: create switch
                    {
                        "alreadyThere" => _ => (ReferenceStaging.CreateAnswer.AlreadyThere, null),
                        "failed" => _ => (ReferenceStaging.CreateAnswer.Failed, "The disk is full."),
                        _ => null,
                    });

                string outcome = claim.Outcome switch
                {
                    ReferenceStaging.Outcome.Claimed => "claimed",
                    ReferenceStaging.Outcome.Refused => "refused",
                    _ => "couldNotStart",
                };
                Assert.True(expect["outcome"]!.ToString() == outcome, $"{name}: {outcome}");
                string expectLeftover = expect["leftover"]!.ToString();
                bool fileThere = File.Exists(Path.Combine(staging, "half.md"));
                if (expectLeftover == "removed") Assert.False(fileThere, name);
                if (expectLeftover == "leftAlone") Assert.True(fileThere, name);
                bool leaseKept = File.Exists(Path.Combine(ReferenceStaging.ActivityDirectory(courses), ReferenceStaging.LeaseName(folder)));
                Assert.True(expect["leaseKept"]!.GetValue<bool>() == leaseKept, $"{name}: lease kept {leaseKept}");
                string? reason = expect["reason"]?.ToString();
                string? expectedReason = reason switch
                {
                    null => null,
                    "wording.alreadyBeingImported" => ReferenceImport.AlreadyBeingImported,
                    "wording.leftoverInTheWay" => ReferenceImport.LeftoverInTheWay,
                    "theCreateFailure" => "The disk is full.",
                    _ => throw new InvalidOperationException(reason),
                };
                Assert.True(expectedReason == claim.Reason, $"{name}: reason {claim.Reason}");
                if (claim.Outcome == ReferenceStaging.Outcome.Claimed) ReferenceStaging.GiveBack(courses, folder);
            }
            finally
            {
                try { other?.Kill(); other?.WaitForExit(5000); } catch { }
            }
            ran++;
        }
        Assert.True(ran >= 9, $"only {ran}");
    }

    /// <summary>
    /// The loser of a race never tidies the winner's work away (#245): the
    /// folder another process made between the check and the create, with its
    /// half-made copy in it, is left exactly as it is.
    /// </summary>
    [Fact]
    public void TwoWindowsImportingOneCourse()
    {
        string courses = Directory.CreateDirectory(Path.Combine(_root, "Race", "courses")).FullName;
        var claim = ReferenceStaging.TryClaim(courses, "ICS4U-2025", ReferenceImport.AlreadyBeingImported, create: staging =>
        {
            Directory.CreateDirectory(staging);                                   // the winner slips in
            File.WriteAllText(Path.Combine(staging, "winner.md"), "theirs");
            return ReferenceStaging.CreateExclusively(staging);                   // and the real create says so
        });
        Assert.Equal(ReferenceStaging.Outcome.Refused, claim.Outcome);
        Assert.True(File.Exists(Path.Combine(courses, ReferenceStaging.StagingName("ICS4U-2025"), "winner.md")));
        Assert.False(File.Exists(Path.Combine(ReferenceStaging.ActivityDirectory(courses), ReferenceStaging.LeaseName("ICS4U-2025"))));
    }

    [Fact]
    public void TwoSpellingsOfOneFolderAreOneClaim()
    {
        string courses = Directory.CreateDirectory(Path.Combine(_root, "Spelled", "courses")).FullName;
        var first = ReferenceStaging.TryClaim(courses, "ICS4U-2025", ReferenceImport.AlreadyBeingImported);
        Assert.Equal(ReferenceStaging.Outcome.Claimed, first.Outcome);
        var second = ReferenceStaging.TryClaim(courses.ToLowerInvariant(), "ics4u-2025", ReferenceImport.AlreadyBeingImported);
        Assert.Equal(ReferenceStaging.Outcome.Refused, second.Outcome);
        Assert.True(Directory.Exists(Path.Combine(courses, ReferenceStaging.StagingName("ICS4U-2025"))));
        ReferenceStaging.GiveBack(courses, "ICS4U-2025");
    }

    [Fact]
    public void TheImportLeaseCarriesItsOwnersStartOnLineFour()
    {
        string courses = Directory.CreateDirectory(Path.Combine(_root, "Lease", "courses")).FullName;
        ReferenceStaging.TryClaim(courses, "ICS4U-2025", ReferenceImport.AlreadyBeingImported);
        string[] lines = File.ReadAllText(Path.Combine(ReferenceStaging.ActivityDirectory(courses), ReferenceStaging.LeaseName("ICS4U-2025"))).Split('\n');
        Assert.Equal(Environment.ProcessId.ToString(), lines[0]);
        Assert.Matches(@"^\d+\.\d{6}$", lines[3]);
        Assert.True(ReferenceStaging.SomeoneIsWorkingOn(courses, "ICS4U-2025", ignoringMyself: false));
        ReferenceStaging.GiveBack(courses, "ICS4U-2025");
    }

    /// <summary>Bundle-6 ruling 4 / review M2: a half-LOCKED leftover with a dead owner is unlocked, then swept.</summary>
    [Fact]
    public void ASweptLeftoverHalfLockedIsRemoved()
    {
        string courses = Directory.CreateDirectory(Path.Combine(_root, "Sweep", "courses")).FullName;
        string staging = Directory.CreateDirectory(Path.Combine(courses, ReferenceStaging.StagingName("ICS4U-2025"), "Unit 1")).FullName;
        File.WriteAllText(Path.Combine(staging, "a.md"), "x");
        File.WriteAllText(Path.Combine(staging, "b.md"), "x");
        ReferenceLock.Lock(staging);
        Directory.CreateDirectory(ReferenceStaging.ActivityDirectory(courses));
        File.WriteAllText(Path.Combine(ReferenceStaging.ActivityDirectory(courses), "ICS4U-2025.import.999999.lease"), "999999\nPlantoir\nx\n");
        string mine = Directory.CreateDirectory(Path.Combine(courses, ".my-own-dot-folder")).FullName;

        var swept = ReferenceStaging.SweepLeftovers(courses);

        Assert.Equal(new[] { "ICS4U-2025" }, swept);
        Assert.False(Directory.Exists(Path.Combine(courses, ReferenceStaging.StagingName("ICS4U-2025"))));
        Assert.True(Directory.Exists(mine));
        Assert.Equal("tidied away an unfinished import left behind by an earlier run — ICS4U-2025", ReferenceStaging.SweptTrailLine(swept));
    }

    [Fact]
    public void ARunningImportIsLeftAloneByTheSweep()
    {
        string courses = Directory.CreateDirectory(Path.Combine(_root, "Running", "courses")).FullName;
        ReferenceStaging.TryClaim(courses, "ICS4U-2025", ReferenceImport.AlreadyBeingImported);
        Assert.Empty(ReferenceStaging.SweepLeftovers(courses));
        ReferenceStaging.ForgetEveryClaimForTesting();   // another WINDOW is not this one; the lease still guards it
        Assert.Empty(ReferenceStaging.SweepLeftovers(courses));
        Assert.True(Directory.Exists(Path.Combine(courses, ReferenceStaging.StagingName("ICS4U-2025"))));
        ReferenceStaging.GiveBack(courses, "ICS4U-2025");
    }

    // ---- Importing, on disk -------------------------------------------------------------

    /// <summary>Last year's working folder: two courses, one a reference course already (locked, read-only), a built website, a junction, a shortcut.</summary>
    private string LastYear(long mergedOutputBytes = 1 << 20)
    {
        string root = Path.Combine(_root, "Last year");
        foreach (string code in new[] { "ICS3U", "ICS4U" })
        {
            string course = Path.Combine(root, "courses", code);
            Directory.CreateDirectory(Path.Combine(course, "Concepts"));
            Directory.CreateDirectory(Path.Combine(course, "section1"));
            Directory.CreateDirectory(Path.Combine(course, ".netlify_sites"));
            Directory.CreateDirectory(Path.Combine(course, ".obsidian"));
            File.WriteAllText(Path.Combine(course, "course_config.json"),
                JObject.Parse($$$"""{"course_code":"{{{code}}}","section_numbers":[1],"num_sections":1,"deploy_target":"netlify"}""").ToString());
            File.WriteAllText(Path.Combine(course, "Concepts", "Bone Apétit.md"), "---\ndraft: true\n---\n# NFD name\n");
            File.WriteAllText(Path.Combine(course, "section1", "index.md"), "# Section 1\n");
            File.WriteAllText(Path.Combine(course, ".netlify_sites", "section1.json"), """{"site_id":"live"}""");
            File.WriteAllText(Path.Combine(course, ".obsidian", "app.json"), "{}");
            File.WriteAllText(Path.Combine(course, "course_config copy.json"), "{}");
            File.WriteAllBytes(Path.Combine(course, "Concepts", "Shortcut.lnk"), new byte[] { 0x4C, 0, 0, 0 });
            string built = Directory.CreateDirectory(Path.Combine(course, ".merged_output", "section1", "public")).FullName;
            File.WriteAllBytes(Path.Combine(built, "big.bin"), new byte[mergedOutputBytes]);
            foreach (string page in Directory.GetFiles(course, "*.md", SearchOption.AllDirectories)) File.SetLastWriteTime(page, new DateTime(2025, 11, 3));
        }
        // ICS3U was already a reference course there: locked, and read-only from an older tool.
        string kept = Path.Combine(root, "courses", "ICS3U");
        var config = JObject.Parse(File.ReadAllText(Path.Combine(kept, "course_config.json")));
        config["kept_for_reference"] = true;
        File.WriteAllText(Path.Combine(kept, "course_config.json"), config.ToString());
        File.SetAttributes(Path.Combine(kept, ".netlify_sites", "section1.json"), FileAttributes.ReadOnly);
        ReferenceLock.Lock(kept);
        ReferenceFixtures.Junction(Path.Combine(root, "courses", "ICS4U", "Linked"), Path.Combine(root, "courses", "ICS3U", "Concepts"));
        return root;
    }

    private string HereCourses() => Directory.CreateDirectory(Path.Combine(_root, "This year", "courses")).FullName;

    [Fact]
    public void TheSourceIsNeverWritten()
    {
        string root = LastYear(mergedOutputBytes: 50 << 20);
        var before = ReferenceFixtures.Manifest(root);
        var (found, _) = ReferenceImport.Resolve(root, null, Today);
        var requests = found!.Courses.Select(c => new ReferenceImport.Request(c, 2025)).ToList();
        var outcomes = ReferenceImport.ImportCourses(requests, HereCourses(), Array.Empty<string>(), Array.Empty<ReferenceCourse.Shelved>(),
            "Last year", null, CancellationToken.None);
        Assert.All(outcomes, o => Assert.NotNull(o.Made));
        Assert.Equal(before, ReferenceFixtures.Manifest(root));
        Assert.True(before.Count >= 20, $"the manifest holds {before.Count} entries");
    }

    [Fact]
    public void ACourseComesInFrozenAndFilledWithWhatItShould()
    {
        string root = LastYear();
        string here = HereCourses();
        long mark = ReferenceFixtures.TrailMark();
        var (found, _) = ReferenceImport.Resolve(root, null, Today);
        var ics4u = found!.Courses.Single(c => c.CourseCode == "ICS4U");
        Assert.Equal(2025, ics4u.SuggestedSchoolYear);
        Assert.Equal(6, ics4u.FileCount);   // settings, the page, the front page, app.json, the shortcut, the site marker

        var outcome = Assert.Single(ReferenceImport.ImportCourses(new[] { new ReferenceImport.Request(ics4u, 2025) }, here,
            Array.Empty<string>(), Array.Empty<ReferenceCourse.Shelved>(), "Last year", null, CancellationToken.None));

        string made = Path.Combine(here, "ICS4U-2025");
        Assert.Equal("ICS4U-2025", outcome.Made!.FolderName);
        Assert.False(Directory.Exists(Path.Combine(made, ".merged_output")));      // not walked, not copied
        Assert.False(File.Exists(Path.Combine(made, "course_config copy.json")));
        Assert.False(Directory.Exists(Path.Combine(made, "Linked")));                // a link is left behind on Windows
        Assert.True(File.Exists(Path.Combine(made, "Concepts", "Shortcut.lnk")));    // a .lnk is an ordinary file
        Assert.True(File.Exists(Path.Combine(made, "Concepts", "Bone Apétit.md")));   // the NFD name, byte for byte
        Assert.False(File.Exists(Path.Combine(made, "Concepts", "Bone Appétit.md".Replace("App", "Ap"))));
        Assert.True(ReferenceLock.IsLocked(Path.Combine(made, "Concepts", "Bone Apétit.md")));
        Assert.Contains("draft: true", File.ReadAllText(Path.Combine(made, "Concepts", "Bone Apétit.md")));   // never rewritten
        Assert.Equal(new DateTime(2025, 11, 3), File.GetLastWriteTime(Path.Combine(made, "Concepts", "Bone Apétit.md")));
        var config = CourseConfiguration.Load(Path.Combine(made, "course_config.json"));
        Assert.True(config.KeptForReference);
        Assert.Equal("local_folder", config.DeployTarget);
        Assert.Single(Directory.GetFiles(Path.Combine(made, ".netlify_sites"), "section1.previous-*.json"));
        Assert.Contains(ReferenceFixtures.TrailSince(mark), l => l.Contains("imported ICS4U for reference from Last year as ICS4U-2025 — 2025–26, 1 section ("));
    }

    /// <summary>Must-fail (e) of the plan, reworded by ruling 2: a source that is itself a reference course still comes in, and its copy arrives clean before it is locked.</summary>
    [Fact]
    public void ImportFromAFolderHoldingAReferenceCourse()
    {
        string root = LastYear();
        var (found, _) = ReferenceImport.Resolve(root, null, Today);
        var ics3u = found!.Courses.Single(c => c.CourseCode == "ICS3U");
        var outcome = Assert.Single(ReferenceImport.ImportCourses(new[] { new ReferenceImport.Request(ics3u, 2024) }, HereCourses(),
            Array.Empty<string>(), Array.Empty<ReferenceCourse.Shelved>(), "Last year", null, CancellationToken.None));
        Assert.NotNull(outcome.Made);
        string made = Path.Combine(_root, "This year", "courses", "ICS3U-2024");
        Assert.False(File.GetAttributes(Path.Combine(made, ".netlify_sites", Path.GetFileName(Directory.GetFiles(Path.Combine(made, ".netlify_sites"))[0]))).HasFlag(FileAttributes.ReadOnly));
    }

    /// <summary>The staging files arrive with no read-only bit and no lock entry — the stream copy carries neither (ruling 2).</summary>
    [Fact]
    public void AStreamCopyCarriesNeitherTheBitNorTheLock()
    {
        string root = LastYear();
        string source = Path.Combine(root, "courses", "ICS3U");
        string into = Directory.CreateDirectory(Path.Combine(_root, "plain")).FullName;
        var survey = ReferenceTreeCopier.Walk(source, ReferenceImport.LeftBehindNames, ObsidianAddOns.LeftBehindFromTheCourse);
        ReferenceTreeCopier.Copy(survey, source, into, null, CancellationToken.None);
        foreach (string file in Directory.GetFiles(into, "*", SearchOption.AllDirectories))
        {
            Assert.False(File.GetAttributes(file).HasFlag(FileAttributes.ReadOnly), file);
            Assert.False(ReferenceLock.IsLocked(file), file);
        }
    }

    /// <summary>Must-fail (a): the walk is never handed a path under a left-behind folder.</summary>
    [Fact]
    public void TheWalkNeverListsWhatIsLeftBehind()
    {
        string root = LastYear();
        var listed = new List<string>();
        ReferenceTreeCopier.Walk(Path.Combine(root, "courses", "ICS4U"), ReferenceImport.LeftBehindNames, ObsidianAddOns.LeftBehindFromTheCourse, listed.Add);
        Assert.DoesNotContain(listed, path => path.Contains(".merged_output", StringComparison.OrdinalIgnoreCase));
        Assert.DoesNotContain(listed, path => path.Contains("Linked", StringComparison.OrdinalIgnoreCase));
        Assert.True(listed.Count >= 4);
    }

    [Fact]
    public void OneFailingCourseDoesNotTakeTheOthersAndEveryOneLeavesALine()
    {
        string root = LastYear();
        string here = HereCourses();
        Directory.CreateDirectory(Path.Combine(here, "ICS4U-2025"));            // a folder of that name already there
        var (found, _) = ReferenceImport.Resolve(root, null, Today);
        long mark = ReferenceFixtures.TrailMark();
        var shelf = new[] { new ReferenceCourse.Shelved("ICS3U", 2025, "ICS3U-2025-OLD") };   // the shelf rule
        var outcomes = ReferenceImport.ImportCourses(found!.Courses.Select(c => new ReferenceImport.Request(c, 2025)).ToList(),
            here, new[] { "ICS4U-2025" }, shelf, "Last year", null, CancellationToken.None);

        // ICS3U refused by the shelf; ICS4U gets the next free name, -2.
        Assert.Equal(ReferenceCourse.CodeAlreadyInThatYear("ICS3U", "2025–26"), outcomes.Single(o => o.Course == "ICS3U").NotImportedBecause);
        Assert.Equal("ICS4U-2025-2", outcomes.Single(o => o.Course == "ICS4U").Made!.FolderName);
        var lines = ReferenceFixtures.TrailSince(mark);
        Assert.Contains(lines, l => l.Contains("could not import ICS3U for reference from Last year — You already have a ICS3U"));
    }

    [Fact]
    public void AShelfRefusalLeavesALineOnTheTrailEvenForTwoOfOneCodeInOneRun()
    {
        string root = LastYear();
        var (found, _) = ReferenceImport.Resolve(root, null, Today);
        var ics4u = found!.Courses.Single(c => c.CourseCode == "ICS4U");
        long mark = ReferenceFixtures.TrailMark();
        var outcomes = ReferenceImport.ImportCourses(new[] { new ReferenceImport.Request(ics4u, 2025), new ReferenceImport.Request(ics4u, 2025) },
            HereCourses(), Array.Empty<string>(), Array.Empty<ReferenceCourse.Shelved>(), "Last year", null, CancellationToken.None);
        Assert.NotNull(outcomes[0].Made);
        Assert.NotNull(outcomes[1].NotImportedBecause);
        Assert.Single(ReferenceFixtures.TrailSince(mark), l => l.Contains("could not import ICS4U"));
    }

    [Fact]
    public void StopRemovesTheCourseInHandAndKeepsWhatLanded()
    {
        string root = LastYear(mergedOutputBytes: 1);
        File.WriteAllBytes(Path.Combine(root, "courses", "ICS4U", "Concepts", "video.bin"), new byte[30 << 20]);
        var (found, _) = ReferenceImport.Resolve(root, null, Today);
        string here = HereCourses();
        using var stop = new CancellationTokenSource();
        long mark = ReferenceFixtures.TrailMark();
        var progress = new Synchronous(p => { if (p.Course == "ICS4U" && p.Copied > (5 << 20)) stop.Cancel(); });
        var outcomes = ReferenceImport.ImportCourses(found!.Courses.Select(c => new ReferenceImport.Request(c, 2025)).ToList(),
            here, Array.Empty<string>(), Array.Empty<ReferenceCourse.Shelved>(), "Last year", progress, stop.Token);
        Assert.NotNull(outcomes.Single(o => o.Course == "ICS3U").Made);
        Assert.True(outcomes.Single(o => o.Course == "ICS4U").WasStopped);
        Assert.False(Directory.Exists(Path.Combine(here, "ICS4U-2025")));
        Assert.Empty(Directory.GetDirectories(here, ReferenceStaging.Prefix + "*"));
        var lines = ReferenceFixtures.TrailSince(mark);
        Assert.Contains(lines, l => l.Contains("stopped importing ICS4U for reference from Last year — nothing was kept for that course"));
        Assert.DoesNotContain(lines, l => l.Contains("could not import ICS4U"));
    }

    [Fact]
    public void ProgressIsInBytesAndNeverSilentForLong()
    {
        string root = LastYear(mergedOutputBytes: 1);
        File.WriteAllBytes(Path.Combine(root, "courses", "ICS4U", "Concepts", "video.bin"), new byte[40 << 20]);
        var (found, _) = ReferenceImport.Resolve(root, null, Today);
        var ics4u = found!.Courses.Single(c => c.CourseCode == "ICS4U");
        var told = new List<ReferenceImport.Progress>();
        ReferenceImport.ImportCourses(new[] { new ReferenceImport.Request(ics4u, 2025) }, HereCourses(), Array.Empty<string>(),
            Array.Empty<ReferenceCourse.Shelved>(), "Last year", new Synchronous(told.Add), CancellationToken.None);
        Assert.True(told.Count >= 2);
        Assert.Equal(0, told[0].Copied);
        Assert.Equal(told[0].Total, told[^1].Copied);
        Assert.True(told[^1].Total >= 40 << 20);
        Assert.True(told.Zip(told.Skip(1)).All(pair => pair.Second.Copied >= pair.First.Copied));
    }

    /// <summary><c>referenceCourses.obsidianAddOns.cases</c> through a modern import (Keep a Copy runs them too).</summary>
    [Fact]
    public void EveryAddOnCaseThroughAnImport()
    {
        var cases = ContractLoader.LoadJson("shared-rules.json")["referenceCourses"]!["obsidianAddOns"]!["cases"]!.AsArray();
        int ran = 0;
        foreach (var c in cases)
        {
            string root = Path.Combine(_root, $"addons{ran}");
            ReferenceFixtures.Build(root, c!["tree"]!.AsArray());
            var before = ReferenceFixtures.Manifest(root);
            string courseDir = Path.Combine(root, c["course"]!.ToString().Replace('/', '\\'));
            var (found, refusal) = ReferenceImport.Resolve(root, null, Today);
            Assert.True(found is not null, refusal);
            var course = found!.Courses.Single(x => x.DirectoryPath == courseDir);
            string here = Directory.CreateDirectory(Path.Combine(_root, $"addons-into{ran}", "courses")).FullName;
            var outcome = ReferenceImport.ImportCourses(new[] { new ReferenceImport.Request(course, null) }, here,
                Array.Empty<string>(), Array.Empty<ReferenceCourse.Shelved>(), Path.GetFileName(root), null, CancellationToken.None).Single();
            AddOnCaseChecks.Assert(c, Path.Combine(here, outcome.Made!.FolderName), courseDir, course.AddOns);
            Assert.Equal(before, ReferenceFixtures.Manifest(root));
            ran++;
        }
        Assert.True(ran >= 9);
    }

    /// <summary>The import measured on a real-sized tree (opt-in, <c>PLANTOIR_MEASURE=1</c>): MB/s on this PC.</summary>
    [Fact]
    public void MeasureARealSizedImport()
    {
        if (Environment.GetEnvironmentVariable("PLANTOIR_MEASURE") != "1") return;
        string root = Path.Combine(_root, "Big");
        string course = Path.Combine(root, "courses", "ICS4U");
        Directory.CreateDirectory(Path.Combine(course, "Media"));
        File.WriteAllText(Path.Combine(course, "course_config.json"), """{"course_code":"ICS4U","section_numbers":[1,2]}""");
        var random = new Random(7);
        byte[] big = new byte[110 << 20]; random.NextBytes(big);
        for (int v = 0; v < 4; v++) File.WriteAllBytes(Path.Combine(course, "Media", $"video{v}.mp4"), big);
        byte[] small = new byte[150 << 10]; random.NextBytes(small);
        for (int unit = 0; unit < 10; unit++)
        {
            Directory.CreateDirectory(Path.Combine(course, $"Unit {unit}"));
            for (int p = 0; p < 30; p++)
            {
                File.WriteAllBytes(Path.Combine(course, "Media", $"img{unit}-{p}.png"), small);
                File.WriteAllText(Path.Combine(course, $"Unit {unit}", $"Day {p}.md"), "# day\n");
            }
        }
        string built = Directory.CreateDirectory(Path.Combine(course, ".merged_output", "section1")).FullName;
        File.WriteAllBytes(Path.Combine(built, "site.bin"), big);
        var (found, _) = ReferenceImport.Resolve(root, null, DateOnly.FromDateTime(DateTime.Now));
        int reports = 0;
        var clock = Stopwatch.StartNew();
        ReferenceImport.ImportCourses(found!.Courses.Select(c => new ReferenceImport.Request(c, 2025)).ToList(), HereCourses(),
            Array.Empty<string>(), Array.Empty<ReferenceCourse.Shelved>(), "Big", new Synchronous(_ => reports++), CancellationToken.None);
        double seconds = clock.Elapsed.TotalSeconds;
        long bytes = found.Courses[0].ByteCount;
        _output.WriteLine($"imported {bytes / 1e6:0} MB in {found.Courses[0].FileCount} files in {seconds:0.00} s = {bytes / 1e6 / seconds:0} MB/s, {reports} progress reports");
    }

    private sealed class Synchronous(Action<ReferenceImport.Progress> report) : IProgress<ReferenceImport.Progress>
    {
        public void Report(ReferenceImport.Progress value) => report(value);
    }
}

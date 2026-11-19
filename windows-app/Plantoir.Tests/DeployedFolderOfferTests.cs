using System.Diagnostics;
using System.Text;
using System.Text.Json.Nodes;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Xunit;
using static Plantoir.Tests.DeployedFolderFixtures;

namespace Plantoir.Tests;

/// <summary>
/// When Open in Browser is offered for a deployed folder, which folder it is,
/// which address it gets, and the words (#889, the mac's #850):
/// <c>deployedFolderInBrowser.offeredCases</c>, <c>offeredDefaults</c>,
/// <c>wording</c>, <c>address</c>, <c>contentTypes</c>, and
/// <c>folderPublishTarget.cases</c> through the app's own resolver, which is
/// held against <c>deploy.ps1</c>'s <c>Resolve-PublishFolder</c> run for real.
/// In <see cref="SharedActivityState"/> because <see cref="DeployedFolderOffer.LookUp"/>
/// reads <see cref="CourseActivity"/>.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class DeployedFolderOfferTests : IDisposable
{
    private readonly string _base = RunOwnedTempFolders.Create("plantoir-dfolder-offer-");

    public void Dispose() => ReferenceFixtures.Remove(_base);

    // ---- When it is offered -----------------------------------------------------------

    private static DeployedFolderOffer.Facts FactsOf(JsonNode given)
    {
        var defaults = Block["offeredDefaults"]!;
        bool Read(string key) => (bool)(given[key] ?? defaults[key])!;
        return new DeployedFolderOffer.Facts
        {
            HasFolderDestination = Read("hasFolderDestination"),
            KeptForReference = Read("keptForReference"),
            DeployIsRunning = Read("deployIsRunning"),
            FolderExists = Read("folderExists"),
            SectionIndexExists = Read("sectionIndexExists"),
        };
    }

    private static string Spoken(DeployedFolderOffer.Decision decision) => decision.Kind switch
    {
        DeployedFolderOffer.Kind.Offered => "offered",
        DeployedFolderOffer.Kind.Absent => "absent",
        _ => "greyed:" + decision.ReasonKey,
    };

    private static string Spoken(JsonNode expect) =>
        expect is JsonObject greyed ? "greyed:" + greyed["greyed"] : expect.ToString();

    [Fact]
    public void EveryOfferedCaseIsDecidedAsTheContractSays()
    {
        var cases = Block["offeredCases"]!.AsArray();
        Assert.Equal(6, cases.Count);
        foreach (var testCase in cases)
            Assert.True(Spoken(testCase!["expect"]!) == Spoken(DeployedFolderOffer.Decide(FactsOf(testCase["given"]!))),
                        $"{testCase["name"]}: {Spoken(DeployedFolderOffer.Decide(FactsOf(testCase["given"]!)))}");
    }

    [Fact]
    public void TheDefaultsAreTheContracts()
    {
        var defaults = Block["offeredDefaults"]!.AsObject();
        Assert.Equal(new DeployedFolderOffer.Facts(), FactsOf(new JsonObject()));
        Assert.Equal(5, defaults.Count);
        Assert.All(defaults, pair => Assert.False((bool)pair.Value!));
    }

    [Fact]
    public void EveryReasonHasItsSentence()
    {
        Assert.Equal(CourseActivity.AvailableOnceDeployCompleted, DeployedFolderOffer.Sentence("deployIsRunning"));
        Assert.Equal(DeployedFolderWording.FolderNotFound, DeployedFolderOffer.Sentence("folderNotFound"));
        Assert.Equal(DeployedFolderWording.NotDeployedYet, DeployedFolderOffer.Sentence("notDeployedYet"));
        Assert.Null(DeployedFolderOffer.Sentence(null));
        foreach (var testCase in Block["offeredCases"]!.AsArray())
            if (testCase!["expect"] is JsonObject greyed) Assert.NotNull(DeployedFolderOffer.Sentence(greyed["greyed"]!.ToString()));
    }

    // ---- The words ----------------------------------------------------------------------

    [Fact]
    public void TheWordsAreTheContracts()
    {
        var mine = new Dictionary<string, string>
        {
            ["resultButton"] = DeployedFolderWording.ResultButton,
            ["menuItem"] = DeployedFolderWording.MenuItem,
            ["stopMenuItem"] = DeployedFolderWording.StopMenuItem,
            ["notice"] = DeployedFolderWording.NoticeTemplate,
            ["stopButton"] = DeployedFolderWording.StopButton,
            ["stopHint"] = DeployedFolderWording.StopHint,
            ["help"] = DeployedFolderWording.Help,
            ["previewHelp"] = DeployedFolderWording.PreviewHelp,
            ["notDeployedYet"] = DeployedFolderWording.NotDeployedYet,
            ["folderNotFound"] = DeployedFolderWording.FolderNotFound,
            ["stoppedFolderGone"] = DeployedFolderWording.StoppedFolderGone,
            ["couldNotOpenTitle"] = DeployedFolderWording.CouldNotOpenTitle,
            ["couldNotOpen"] = DeployedFolderWording.CouldNotOpen,
            ["renderNote"] = DeployedFolderWording.RenderNote,
            ["dismissButton"] = DeployedFolderWording.DismissButton,
            ["couldNotOpenButton"] = DeployedFolderWording.CouldNotOpenButton,
        };
        var wording = Block["wording"]!.AsObject();
        Assert.Equal(wording.Select(p => p.Key).Order(), mine.Keys.Order());
        foreach (var (key, value) in wording) Assert.True(mine[key] == value!.ToString(), key);
        Assert.Equal(wording["notice"]!.ToString().Replace("{section}", "3"), DeployedFolderWording.Notice(3));
    }

    // ---- The address --------------------------------------------------------------------

    [Fact]
    public void EveryAddressCaseStartsWhereTheContractSays()
    {
        var address = Block["address"]!;
        Assert.Equal((int)address["firstPort"]!, DeployedFolderAddress.FirstPort);
        Assert.Equal((int)address["blockSize"]!, DeployedFolderAddress.BlockSize);
        foreach (var testCase in address["cases"]!.AsArray())
        {
            int? remembered = testCase!["remembered"] is { } r ? (int)r : null;
            Assert.Equal((int)testCase["expectFirst"]!, DeployedFolderAddress.Candidates(testCase["canonicalPath"]!.ToString(), remembered)[0]);
        }
    }

    [Theory]
    [InlineData("/Users/teacher/Sites/ics3u/section1", null)]
    [InlineData("/Users/teacher/Sites/ics3u/section1", 41007)]
    [InlineData(@"C:\Users\teacher\Sites\ics3u\section1", 41399)]
    [InlineData("", 52000)]
    public void EveryCandidateIsTheBlockOnceAndNothingElse(string path, int? remembered)
    {
        var candidates = DeployedFolderAddress.Candidates(path, remembered);
        Assert.Equal(DeployedFolderAddress.BlockSize, candidates.Count);
        Assert.Equal(candidates.Count, candidates.Distinct().Count());
        Assert.All(candidates, port => Assert.True(DeployedFolderAddress.IsInTheBlock(port)));
        Assert.DoesNotContain(candidates, port => port is >= 8081 and <= 9474 or >= 49152);
        if (remembered is { } wanted && DeployedFolderAddress.IsInTheBlock(wanted)) Assert.Equal(wanted, candidates[0]);
    }

    [Fact]
    public void AWindowsPathHashesByItsSpelling()
    {
        // The planner's independent FNV-1a (plans/new-issues-plan.md 3.4) gave
        // these, which is why the canonical path is the ON-DISK spelling.
        Assert.Equal(41143, DeployedFolderAddress.StartingPort(@"C:\Users\teacher\Sites\ics3u\section1"));
        Assert.Equal(41047, DeployedFolderAddress.StartingPort(@"c:\users\teacher\sites\ics3u\section1"));
    }

    [Fact]
    public void TheCanonicalPathIsTheDisksOwnSpelling()
    {
        string folder = Path.Combine(_base, "Sites", "Section1");
        Directory.CreateDirectory(folder);
        string asTyped = folder.ToLowerInvariant();
        Assert.Equal(DeployedFolderAddress.CanonicalPath(folder), DeployedFolderAddress.CanonicalPath(asTyped));
        Assert.EndsWith(@"\Sites\Section1", DeployedFolderAddress.CanonicalPath(asTyped));
        Assert.Null(DeployedFolderAddress.CanonicalPath(Path.Combine(_base, "missing")));
    }

    // ---- The types ----------------------------------------------------------------------

    [Fact]
    public void TheContentTypesAreTheContracts()
    {
        var types = Block["contentTypes"]!.AsObject();
        Assert.Equal(types.Count, DeployedFolderContentTypes.ByExtension.Count);
        foreach (var (extension, type) in types)
        {
            Assert.Equal(type!.ToString(), DeployedFolderContentTypes.TypeOf("a." + extension));
            Assert.Equal(type.ToString(), DeployedFolderContentTypes.TypeOf("A." + extension.ToUpperInvariant()));
        }
        Assert.Equal(Block["unknownContentType"]!.ToString(), DeployedFolderContentTypes.Unknown);
        Assert.Equal(DeployedFolderContentTypes.Unknown, DeployedFolderContentTypes.TypeOf("noextension"));
        Assert.Equal(DeployedFolderContentTypes.Unknown, DeployedFolderContentTypes.TypeOf("a.exe"));
    }

    // ---- Which folder (the plan review's M5) --------------------------------------------

    [Fact]
    public void EveryPortableFolderTargetCaseResolvesAsTheLauncherDoes()
    {
        string workingFolder = Path.Combine(_base, "Working Folder");
        int ran = 0;
        foreach (var testCase in ContractLoader.LoadJson("shared-rules.json")["folderPublishTarget"]!["cases"]!.AsArray())
        {
            if (testCase!["appliesOn"] is JsonArray only && !only.Any(p => p!.ToString() == "windows")) continue;
            string expected = testCase["expectTarget"]!.ToString().Replace("@WF@", workingFolder).Replace('/', '\\');
            Assert.Equal(expected, DeployedFolderOffer.SectionFolder(testCase["toFolder"]!.ToString(), workingFolder, 1));
            ran++;
        }
        Assert.Equal(2, ran);
    }

    public static readonly string[] Settings =
    [
        "-x", "sub/site", "  sub/site  ", "sub\\site\\", @"C:foo", @"\out", "/out", @"D:\Sites\x\", "D:/Sites/y",
        @"\\server\share\site", "a\\..\\b", "out.", "out ", "", "   ", @"C:\Users\Prof Élise\Cours #3",
    ];

    [Fact]
    public void ADriveOrRootRelativeFolderIsNotFound()
    {
        string workingFolder = Path.Combine(_base, "wf");
        Assert.Null(DeployedFolderOffer.SectionFolder(@"C:foo", workingFolder, 1));
        Assert.Null(DeployedFolderOffer.SectionFolder(@"\out", workingFolder, 1));
        Assert.Null(DeployedFolderOffer.SectionFolder("   ", workingFolder, 1));
        Assert.Equal(@"D:\Sites\x\section2", DeployedFolderOffer.SectionFolder(@" D:\Sites\x\ ", workingFolder, 2));
    }

    // ---- The facts, read from the saved settings and the disk ------------------------------

    private (Course Course, string WorkingFolder) MakeCourse(JObject settings)
    {
        string workingFolder = Path.Combine(_base, "wf");
        string courseFolder = Path.Combine(workingFolder, "courses", "ICS3U");
        Directory.CreateDirectory(courseFolder);
        File.WriteAllText(Path.Combine(courseFolder, "course_config.json"), settings.ToString());
        // The window's copy says Netlify: LookUp must read what is SAVED.
        var unsaved = CourseConfiguration.FromDictionary(new JObject { ["deploy_target"] = "netlify" });
        return (new Course("ICS3U", courseFolder, unsaved), workingFolder);
    }

    [Fact]
    public void LookUpReadsTheSavedSettingsAndTheDisk()
    {
        string sites = Path.Combine(_base, "Sites");
        var (course, workingFolder) = MakeCourse(new JObject { ["deploy_target"] = "local_folder", ["deploy_folder_path"] = sites });

        var lookup = DeployedFolderOffer.LookUp(course, 1, workingFolder);
        Assert.Equal("greyed:folderNotFound", Spoken(lookup.Decision));
        Assert.Equal(Path.Combine(sites, "section1"), lookup.SectionFolder);

        Directory.CreateDirectory(Path.Combine(sites, "section1"));
        Assert.Equal("greyed:notDeployedYet", Spoken(DeployedFolderOffer.LookUp(course, 1, workingFolder).Decision));

        File.WriteAllText(Path.Combine(sites, "section1", "index.html"), "x");
        Assert.Equal("offered", Spoken(DeployedFolderOffer.LookUp(course, 1, workingFolder).Decision));

        using (CourseActivity.BeginPublish(workingFolder, "ICS3U", 1))
            Assert.Equal("greyed:deployIsRunning", Spoken(DeployedFolderOffer.LookUp(course, 1, workingFolder).Decision));
        Assert.Equal("offered", Spoken(DeployedFolderOffer.LookUp(course, 1, workingFolder).Decision));
    }

    [Fact]
    public void ARelativeFolderAnAdditionalOneAndNone()
    {
        var (course, workingFolder) = MakeCourse(new JObject
        {
            ["deploy_target"] = "cloudflare_pages",
            ["additional_deploy_targets"] = new JArray(new JObject { ["type"] = "local_folder", ["path"] = "out site" }),
        });
        var lookup = DeployedFolderOffer.LookUp(course, 2, workingFolder);
        Assert.True(lookup.Facts.HasFolderDestination);
        Assert.Equal(Path.Combine(workingFolder, "out site", "section2"), lookup.SectionFolder);

        var (netlify, wf) = MakeCourse(new JObject { ["deploy_target"] = "netlify" });
        var none = DeployedFolderOffer.LookUp(netlify, 1, wf);
        Assert.Equal("absent", Spoken(none.Decision));
        Assert.Null(none.SectionFolder);
    }

    [Fact]
    public void AnotherProgramsDeployOfTheCourseGreysIt()
    {
        string sites = Path.Combine(_base, "Sites");
        Directory.CreateDirectory(Path.Combine(sites, "section1"));
        File.WriteAllText(Path.Combine(sites, "section1", "index.html"), "x");
        var (course, workingFolder) = MakeCourse(new JObject { ["deploy_target"] = "local_folder", ["deploy_folder_path"] = sites });
        Assert.Equal("offered", Spoken(DeployedFolderOffer.LookUp(course, 1, workingFolder).Decision));

        // A live program's publish lease on the course (another section's
        // deploy greys it too: leases are per course). The desktop's own
        // explorer.exe stands in as that program, alive for the whole test.
        string activity = Path.Combine(workingFolder, "courses", ".internal", "activity");
        Directory.CreateDirectory(activity);
        using var other = Process.GetProcessesByName("explorer").First();
        string lease = Path.Combine(activity, $"ICS3U.{WorkLease.Publishing}.{other.Id}.lease");
        File.WriteAllText(lease, $"{other.Id}\n{other.ProcessName}\n2026-11-13T00:00:00Z\n");
        Assert.True(WorkLease.IsHeld(workingFolder, "ICS3U", WorkLease.Publishing));
        Assert.Equal("greyed:deployIsRunning", Spoken(DeployedFolderOffer.LookUp(course, 1, workingFolder).Decision));
        File.Delete(lease);
        Assert.Equal("offered", Spoken(DeployedFolderOffer.LookUp(course, 1, workingFolder).Decision));
    }

    [Fact]
    public void AKeptForReferenceCourseIsNeverOffered()
    {
        string sites = Path.Combine(_base, "Sites");
        Directory.CreateDirectory(Path.Combine(sites, "section1"));
        File.WriteAllText(Path.Combine(sites, "section1", "index.html"), "x");
        var (course, workingFolder) = MakeCourse(new JObject
        {
            ["deploy_target"] = "local_folder", ["deploy_folder_path"] = sites, ["kept_for_reference"] = true,
        });
        Assert.Equal("absent", Spoken(DeployedFolderOffer.LookUp(course, 1, workingFolder).Decision));
    }

    [Fact]
    public void UnreadableSavedSettingsAreNeverOfferedOnTheWindowsCopy()
    {
        string sites = Path.Combine(_base, "Sites");
        Directory.CreateDirectory(Path.Combine(sites, "section1"));
        File.WriteAllText(Path.Combine(sites, "section1", "index.html"), "x");
        string workingFolder = Path.Combine(_base, "wf");
        string courseFolder = Path.Combine(workingFolder, "courses", "ICS3U");
        Directory.CreateDirectory(courseFolder);
        File.WriteAllText(Path.Combine(courseFolder, "course_config.json"), "{ not json");
        // The window's unsaved copy names the folder; the saved file cannot be read.
        var unsaved = CourseConfiguration.FromDictionary(new JObject { ["deploy_target"] = "local_folder", ["deploy_folder_path"] = sites });
        var lookup = DeployedFolderOffer.LookUp(new Course("ICS3U", courseFolder, unsaved), 1, workingFolder);
        Assert.Equal("absent", Spoken(lookup.Decision));
        Assert.Null(lookup.SectionFolder);
    }
}

/// <summary>
/// <c>deploy.ps1</c>'s own <c>Resolve-PublishFolder</c> beside the app's, in
/// the wall-clock collection because it starts Windows PowerShell 5.1 (the
/// review's L5).
/// </summary>
[Collection(DeployedFolderTimings.Name)]
public sealed class DeployedFolderLauncherFolderTests : IDisposable
{
    private readonly string _base = RunOwnedTempFolders.Create("plantoir-dfolder-launcher-");

    public void Dispose() => ReferenceFixtures.Remove(_base);

    public static readonly string[] Settings = DeployedFolderOfferTests.Settings;

    /// <summary>
    /// The launcher's OWN function, cut out of <c>deploy.ps1</c> and run in
    /// Windows PowerShell 5.1 (what deploy.ps1 runs in), beside
    /// <see cref="DeployedFolderOffer.SectionFolder"/> on the same settings,
    /// with deploy.ps1's own section join: a change to either that the other
    /// has not made fails here.
    /// </summary>
    [Fact]
    public void TheAppResolvesTheFolderExactlyAsDeployPs1Does()
    {
        string workingFolder = Path.Combine(_base, "Working Folder");
        Directory.CreateDirectory(workingFolder);
        string deploy = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "deploy.ps1"));
        int start = deploy.IndexOf("function Resolve-PublishFolder", StringComparison.Ordinal);
        Assert.True(start >= 0, "deploy.ps1 has no Resolve-PublishFolder");
        int end = deploy.IndexOf("\n}", start, StringComparison.Ordinal);
        string function = deploy[start..(end + 2)];
        // deploy.ps1, where it builds the target from Resolve-PublishFolder's answer:
        // [IO.Path]::Combine($folderAsked.TrimEnd('\','/'), ("section{0}" -f $SECTION_NUM))
        Assert.Contains("[IO.Path]::Combine($folderAsked.TrimEnd('\\','/'), (\"section{0}\" -f $SECTION_NUM))", deploy);

        string inputs = Path.Combine(_base, "inputs.txt");
        File.WriteAllLines(inputs, Settings.Select(s => Convert.ToBase64String(Encoding.UTF8.GetBytes(s))));
        string script = Path.Combine(_base, "resolve.ps1");
        File.WriteAllText(script, function + "\n" +
            "$wf = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($args[1]))\n" +
            "foreach ($line in [IO.File]::ReadAllLines($args[0])) {\n" +
            "  $asked = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($line))\n" +
            "  $r = $null; try { $r = Resolve-PublishFolder $asked $wf } catch { $r = $null }\n" +
            "  if ($null -eq $r) { 'NULL' } else { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([IO.Path]::Combine($r.TrimEnd('\\','/'), 'section1'))) }\n" +
            "}\n", new UTF8Encoding(true));
        var info = new ProcessStartInfo("powershell.exe")
        {
            UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true,
        };
        foreach (string argument in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script, inputs,
                                            Convert.ToBase64String(Encoding.UTF8.GetBytes(workingFolder)) })
            info.ArgumentList.Add(argument);
        using var process = Process.Start(info)!;
        string output = process.StandardOutput.ReadToEnd();
        process.WaitForExit(60_000);
        var answers = output.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        Assert.Equal(Settings.Length, answers.Length);
        for (int i = 0; i < Settings.Length; i++)
        {
            string? launcher = answers[i] == "NULL" ? null : Encoding.UTF8.GetString(Convert.FromBase64String(answers[i]));
            Assert.True(launcher == DeployedFolderOffer.SectionFolder(Settings[i], workingFolder, 1),
                        $"'{Settings[i]}': deploy.ps1 {launcher ?? "null"}, the app {DeployedFolderOffer.SectionFolder(Settings[i], workingFolder, 1) ?? "null"}");
        }
    }
}

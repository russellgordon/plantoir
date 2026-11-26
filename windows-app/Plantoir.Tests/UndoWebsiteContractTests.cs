using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Models;
using Plantoir.Core.Undo;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #899 piece W5 (#949 step 8): <c>shared-rules.json</c> → <c>undo.rule.deployed</c>,
/// walked from <c>undo.deployedCases</c> (18) twice: once through the pure
/// <see cref="UndoWebsite.Answer"/>, and once through a real course folder read
/// by <see cref="UndoWebsite.Inputs"/>, so the seam reads what the case says it
/// holds. Tests named <c>Proposed_</c> cover what the contract does not say;
/// their cases are proposed to the Mac in the director's draft, not written
/// into the contract. No clock, no static state, every folder a temp folder of
/// its own.
/// </summary>
public class UndoWebsiteContractTests : IDisposable
{
    private readonly string _root = Directory.CreateTempSubdirectory("undo-website-").FullName;

    public void Dispose()
    {
        try { Directory.Delete(_root, true); } catch { }
    }

    private static JsonArray DeployedCases() =>
        ContractLoader.LoadJson("shared-rules.json")["undo"]!["deployedCases"]!.AsArray();

    private static UndoWebsiteAnswer AnswerNamed(string answer) => answer switch
    {
        "offerToDeploy" => UndoWebsiteAnswer.OfferToDeploy,
        "noOffer" => UndoWebsiteAnswer.NoOffer,
        "cannotTell" => UndoWebsiteAnswer.CannotTell,
        _ => throw new InvalidOperationException($"deployedCases names an answer this test does not know: {answer}"),
    };

    private static List<string> Strings(JsonNode? node) =>
        node is JsonArray array ? array.Select(item => item!.GetValue<string>()).ToList() : new List<string>();

    private static List<UndoWebsiteMove> Moves(JsonNode c) =>
        c["moves"]!.AsArray().Select(move => new UndoWebsiteMove(
            move!["path"]!.GetValue<string>(),
            move["visibleBefore"]!.GetValue<bool>(),
            move["visibleAfter"]!.GetValue<bool>())).ToList();

    private static List<UndoWebsiteFragment> Record(JsonNode c) =>
        c["record"]!.AsArray().Select(file => new UndoWebsiteFragment(
            file!["name"]!.GetValue<string>(),
            file["places"] is JsonArray places ? places.Select(p => p!.GetValue<string>()).ToList() : null)).ToList();

    private static bool ChangesMore(JsonNode c) => c["changesMoreThanVisibility"]?.GetValue<bool>() ?? false;

    // -------------------------------------------------------------------
    // The 18 cases.
    // -------------------------------------------------------------------

    [Fact]
    public void EveryDeployedCase()
    {
        var cases = DeployedCases();
        // 18 when U1 merged; a list that shrinks or empties fails here
        // rather than passing having walked nothing.
        Assert.True(cases.Count >= 18, $"deployedCases has {cases.Count} cases; U1 wrote 18");
        var red = new List<string>();
        int walked = 0;
        foreach (var c in cases)
        {
            string name = c!["name"]!.GetValue<string>();
            var expected = AnswerNamed(c["answer"]!.GetValue<string>());
            var actual = UndoWebsite.Answer(Moves(c), ChangesMore(c), Record(c),
                Strings(c["destinations"]), Strings(c["siteMarkers"]));
            walked++;
            if (actual != expected) red.Add($"RED: {name} (expected {expected}, got {actual})");
        }
        Assert.Equal(cases.Count, walked);
        Assert.True(red.Count == 0, string.Join(Environment.NewLine, red));
    }

    [Fact]
    public void EveryDeployedCaseThroughARealCourseFolder()
    {
        var cases = DeployedCases();
        Assert.True(cases.Count >= 18);
        var red = new List<string>();
        int index = 0;
        foreach (var c in cases)
        {
            string name = c!["name"]!.GetValue<string>();
            var expected = AnswerNamed(c["answer"]!.GetValue<string>());
            var course = CourseFor(c, index++);
            var inputs = UndoWebsite.Inputs(course, 1);
            var actual = UndoWebsite.Answer(Moves(c), ChangesMore(c), inputs.Record, inputs.Destinations, inputs.SiteMarkers);
            if (actual != expected) red.Add($"RED: {name} (expected {expected}, got {actual})");
            // The seam says what the case holds.
            Assert.Equal(Strings(c["destinations"]), inputs.Destinations);
            Assert.Equal(Strings(c["siteMarkers"]).OrderBy(s => s, StringComparer.Ordinal),
                         inputs.SiteMarkers.OrderBy(s => s, StringComparer.Ordinal));
        }
        Assert.True(red.Count == 0, string.Join(Environment.NewLine, red));
    }

    /// <summary>The Windows course_config.json type a contract destination is spelled with.</summary>
    private static string ConfigTypeFor(string destination) => destination switch
    {
        "netlify" => "netlify",
        "cloudflare" => "cloudflare_pages",
        "folder" => "local_folder",
        _ => throw new InvalidOperationException(destination),
    };

    /// <summary>A course folder holding the case's record and markers, its settings naming the case's destinations.</summary>
    private Course CourseFor(JsonNode c, int index)
    {
        string courseDir = Path.Combine(_root, $"w{index}", "courses", "TST1O");
        Directory.CreateDirectory(courseDir);
        var destinations = Strings(c["destinations"]);
        var settings = new JObject
        {
            ["course_code"] = "TST1O",
            ["section_numbers"] = new JArray(1),
            ["deploy_target"] = ConfigTypeFor(destinations[0]),
            ["deploy_folder_path"] = Path.Combine(_root, "site"),
        };
        if (destinations.Count > 1)
            settings["additional_deploy_targets"] = new JArray(destinations.Skip(1)
                .Select(d => new JObject { ["type"] = ConfigTypeFor(d) }));
        foreach (string marker in Strings(c["siteMarkers"]))
        {
            string folder = Path.Combine(courseDir, marker == "cloudflare" ? ".cloudflare_sites" : ".netlify_sites");
            Directory.CreateDirectory(folder);
            File.WriteAllText(Path.Combine(folder, "section1.json"), "{\"site_id\": \"test\"}\n");
        }
        string record = UndoWebsite.RecordFolder(courseDir, 1);
        Directory.CreateDirectory(record);
        foreach (var file in c["record"]!.AsArray())
        {
            string path = Path.Combine(record, file!["name"]!.GetValue<string>());
            if (file["places"] is JsonArray places) WriteFragment(path, places.Select(p => p!.GetValue<string>()));
            else File.WriteAllText(path, "{\"version\": 1, \"places\": [\"Section 1/ind");
        }
        return new Course("TST1O", courseDir, CourseConfiguration.FromDictionary(settings));
    }

    private static void WriteFragment(string path, IEnumerable<string> places, string? version = "1")
    {
        var data = new JsonObject();
        if (version is not null) data["version"] = int.Parse(version);
        data["course"] = "TST1O";
        data["section"] = 1;
        data["buildId"] = "build-1";
        data["places"] = new JsonArray(places.Select(p => (JsonNode)JsonValue.Create(p)!).ToArray());
        File.WriteAllText(path, data.ToJsonString() + "\n", new UTF8Encoding(false));
    }

    // -------------------------------------------------------------------
    // What the cases do not say, built from the rule's own words.
    // -------------------------------------------------------------------

    private static readonly UndoWebsiteMove HideDay1 = new("courses/TST1O/Section 1/Classes/Day 1.md", true, false);
    private const string Day1 = "Section 1/Classes/Day 1";

    private Course Course(string primary, params string[] additional)
    {
        string courseDir = Path.Combine(_root, Guid.NewGuid().ToString("N"), "courses", "TST1O");
        Directory.CreateDirectory(courseDir);
        var settings = new JObject { ["course_code"] = "TST1O", ["section_numbers"] = new JArray(1) };
        if (primary.Length > 0) settings["deploy_target"] = primary;
        if (additional.Length > 0)
            settings["additional_deploy_targets"] = new JArray(additional.Select(t => new JObject { ["type"] = t }));
        return new Course("TST1O", courseDir, CourseConfiguration.FromDictionary(settings));
    }

    private static string Fragment(Course course, string name)
    {
        string folder = UndoWebsite.RecordFolder(course.DirectoryPath, 1);
        Directory.CreateDirectory(folder);
        return Path.Combine(folder, name);
    }

    private static void Marker(Course course, string folderName)
    {
        string folder = Path.Combine(course.DirectoryPath, folderName);
        Directory.CreateDirectory(folder);
        File.WriteAllText(Path.Combine(folder, "section1.json"), "{}\n");
    }

    private static UndoWebsiteAnswer AnswerFor(Course course, bool changesMore = false, params UndoWebsiteMove[] moves)
    {
        var inputs = UndoWebsite.Inputs(course, 1);
        return UndoWebsite.Answer(moves.Length == 0 ? new[] { HideDay1 } : moves, changesMore,
            inputs.Record, inputs.Destinations, inputs.SiteMarkers);
    }

    [Fact]
    public void WindowsConfigTypesAreTheContractsDestinations()
    {
        // The plan review's L7: local_folder is the record's `folder`.
        Assert.Equal(UndoWebsite.Folder, UndoWebsite.DestinationFor("local_folder"));
        Assert.Equal(UndoWebsite.Cloudflare, UndoWebsite.DestinationFor("cloudflare_pages"));
        Assert.Equal(UndoWebsite.Netlify, UndoWebsite.DestinationFor("netlify"));
        foreach (string type in CourseConfiguration.KnownDeployTargetTypes)
            Assert.NotNull(UndoWebsite.DestinationFor(type));

        // deploy_target absent means Netlify, as deploy.ps1 and the app read it.
        Assert.Equal(new[] { "netlify" }, UndoWebsite.Inputs(Course(""), 1).Destinations);
        Assert.Equal(new[] { "folder", "netlify", "cloudflare" },
            UndoWebsite.Inputs(Course("local_folder", "netlify", "cloudflare_pages"), 1).Destinations);
    }

    [Fact]
    public void AFolderDeployIsReadUnderItsRecordsName()
    {
        // deploy.ps1 names a folder publish's fragment `-folder.json`.
        var course = Course("local_folder");
        WriteFragment(Fragment(course, "20261113T090000Z-folder.json"), new[] { Day1 });
        Assert.Equal(UndoWebsiteAnswer.OfferToDeploy, AnswerFor(course));
        // and a fragment spelled after the config type is not one of its fragments.
        var other = Course("local_folder");
        WriteFragment(Fragment(other, "20261113T090000Z-local_folder.json"), new[] { Day1 });
        Assert.Equal(UndoWebsiteAnswer.NoOffer, AnswerFor(other));
    }

    [Fact]
    public void Proposed_ADestinationTypeNoDeployAcceptsIsNotRead()
    {
        // deploy.ps1 refuses a type it does not know, so nothing was deployed there.
        Assert.Null(UndoWebsite.DestinationFor("ftp"));
        var course = Course("ftp");
        WriteFragment(Fragment(course, "20261113T090000Z-ftp.json"), new[] { Day1 });
        Assert.Empty(UndoWebsite.Inputs(course, 1).Destinations);
        Assert.Equal(UndoWebsiteAnswer.NoOffer, AnswerFor(course));
    }

    [Fact]
    public void TheMarkersReadAreTheOnesTheScheduledDeployReads()
    {
        var course = Course("netlify", "cloudflare_pages", "local_folder");
        Marker(course, ".cloudflare_sites");
        var inputs = UndoWebsite.Inputs(course, 1);
        Assert.Equal(new[] { "cloudflare" }, inputs.SiteMarkers);
        Assert.False(DeployCommand.HasDeployedBefore(1, course, "netlify"));
        Assert.True(DeployCommand.HasDeployedBefore(1, course, "cloudflare_pages"));
        // A marker for another section is not this one's.
        Assert.Empty(UndoWebsite.Inputs(course, 2).SiteMarkers);
    }

    [Fact]
    public void ARecordFolderThatIsMissingIsNoFragments()
    {
        var never = Course("netlify");
        Assert.Equal(UndoWebsiteAnswer.NoOffer, AnswerFor(never));
        var marked = Course("netlify");
        Marker(marked, ".netlify_sites");
        Assert.Equal(UndoWebsiteAnswer.CannotTell, AnswerFor(marked));
    }

    [Fact]
    public void Proposed_ARecordFolderThatCannotBeListedCannotTell()
    {
        // Pure half: no listing at all is every destination unread.
        Assert.Equal(UndoWebsiteAnswer.CannotTell,
            UndoWebsite.Answer(new[] { HideDay1 }, false, null, new[] { "netlify" }, Array.Empty<string>()));
        // and a section that deploys nowhere has nothing to offer.
        Assert.Equal(UndoWebsiteAnswer.NoOffer,
            UndoWebsite.Answer(new[] { HideDay1 }, false, null, Array.Empty<string>(), Array.Empty<string>()));

        // On disk, through the listing seam: a folder that refuses to be
        // listed (as a deny ACE does) is every destination unread. Green
        // under any token, which the ACL fact below is not (the W5 review's
        // second round: an administrator's token over SSH passes a deny ACE).
        foreach (Exception refusal in new Exception[] { new UnauthorizedAccessException("denied"), new IOException("the network went away") })
        {
            var course = Course("netlify");
            WriteFragment(Fragment(course, "20261113T090000Z-netlify.json"), new[] { "Section 1/index" });
            var inputs = UndoWebsite.Inputs(course, 1, _ => throw refusal);
            Assert.Null(inputs.Record);
            Assert.Equal(UndoWebsiteAnswer.CannotTell,
                UndoWebsite.Answer(new[] { HideDay1 }, false, inputs.Record, inputs.Destinations, inputs.SiteMarkers));
        }
    }

    /// <summary>
    /// The same through a real deny ACE on the folder. Skipped, saying why,
    /// where this account's token passes over a deny ACE (an administrator's
    /// over SSH), so the totals line counts it as not run rather than failed.
    /// </summary>
    [DenyBitesFact]
    public void ARecordFolderThatDeniesListingCannotTell()
    {
        var course = Course("netlify");
        string folder = UndoWebsite.RecordFolder(course.DirectoryPath, 1);
        WriteFragment(Fragment(course, "20261113T090000Z-netlify.json"), new[] { "Section 1/index" });
        var info = new DirectoryInfo(folder);
        var rights = info.GetAccessControl();
        var me = WindowsIdentity.GetCurrent().User!;
        var deny = new FileSystemAccessRule(me, FileSystemRights.ListDirectory, AccessControlType.Deny);
        rights.AddAccessRule(deny);
        info.SetAccessControl(rights);
        try
        {
            var inputs = UndoWebsite.Inputs(course, 1);
            Assert.Null(inputs.Record);
            Assert.Equal(UndoWebsiteAnswer.CannotTell, AnswerFor(course));
        }
        finally
        {
            rights.RemoveAccessRule(deny);
            info.SetAccessControl(rights);
        }
    }

    [Fact]
    public void Proposed_APageWhoseNameEndsInUpperCaseMdIsAPageAsOnTheMac()
    {
        // The Mac's UndoWebsite.place(ofPath:) lowercases before the .md test.
        Assert.Equal(Day1, UndoWebsite.PlaceOf("courses/TST1O/Section 1/Classes/Day 1.MD"));
        Assert.Equal(Day1, UndoWebsite.PlaceOf("courses/TST1O/Section 1/Classes/Day 1.Md"));
    }

    [Fact]
    public void AFragmentNameHasAsciiDigitsOnlyAsOnTheMac()
    {
        // Arabic-Indic digits are \d to .NET but not a moment the writers spell.
        string arabic = string.Concat(Enumerable.Repeat("\u0661", 8)) + "T" + string.Concat(Enumerable.Repeat("\u0661", 6)) + "Z-netlify.json";
        var record = new[] { new UndoWebsiteFragment(arabic, new[] { Day1 }) };
        Assert.Empty(UndoWebsite.NewestFragments(record, new[] { "netlify" }));
        var ascii = new[] { new UndoWebsiteFragment("20261113T090000Z-netlify.json", new[] { Day1 }) };
        Assert.Single(UndoWebsite.NewestFragments(ascii, new[] { "netlify" }));
    }

    [Fact]
    public void AFragmentThatCannotBeReadIsUnreadOnlyWhenItIsTheNewest()
    {
        foreach (string text in new[] { "{ not json", "[1, 2]", "{\"version\": 1}", "{\"places\": \"Section 1/index\"}",
                                        "{\"places\": [\"Section 1/index\", 3]}", "" })
        {
            var course = Course("netlify");
            File.WriteAllText(Fragment(course, "20261113T090000Z-netlify.json"), text);
            Assert.Null(UndoWebsite.ReadPlaces(Fragment(course, "20261113T090000Z-netlify.json")));
            Assert.Equal(UndoWebsiteAnswer.CannotTell, AnswerFor(course));

            // Beneath a readable newer one it is never opened.
            WriteFragment(Fragment(course, "20261114T090000Z-netlify.json"), new[] { "Section 1/index" });
            Assert.Equal(UndoWebsiteAnswer.NoOffer, AnswerFor(course));
        }
    }

    [Fact]
    public void AFragmentHeldOpenByAnotherProgramCannotTell()
    {
        var course = Course("netlify");
        string path = Fragment(course, "20261113T090000Z-netlify.json");
        WriteFragment(path, new[] { Day1 });
        using (new FileStream(path, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
            Assert.Equal(UndoWebsiteAnswer.CannotTell, AnswerFor(course));
        Assert.Equal(UndoWebsiteAnswer.OfferToDeploy, AnswerFor(course));
    }

    [Fact]
    public void AFragmentWithAByteOrderMarkIsRead()
    {
        var course = Course("netlify");
        string path = Fragment(course, "20261113T090000Z-netlify.json");
        File.WriteAllText(path, "{\"version\": 1, \"places\": [\"Section 1/Classes/Day 1\"]}\n", new UTF8Encoding(true));
        Assert.Equal(new[] { Day1 }, UndoWebsite.ReadPlaces(path));
        Assert.Equal(UndoWebsiteAnswer.OfferToDeploy, AnswerFor(course));
    }

    [Fact]
    public void AFragmentWhoseTextIsNotValidUnicodeCannotTell()
    {
        // The W5 review's M1: bytes that are not UTF-8 inside a place, and an
        // escaped half of a surrogate pair, are a fragment that "cannot be
        // read" (the rule's CANNOT TELL), never an exception out of Inputs.
        byte[] invalidUtf8 = Encoding.ASCII.GetBytes("{\"version\": 1, \"places\": [\"Section 1/")
            .Concat(new byte[] { 0xFF, 0xFE })
            .Concat(Encoding.ASCII.GetBytes("\"]}\n")).ToArray();
        byte[] loneSurrogate = Encoding.ASCII.GetBytes("{\"version\": 1, \"places\": [\"Section 1/\\ud800x\"]}\n");
        foreach (byte[] bytes in new[] { invalidUtf8, loneSurrogate })
        {
            var course = Course("netlify");
            string path = Fragment(course, "20261113T090000Z-netlify.json");
            File.WriteAllBytes(path, bytes);
            Assert.Null(UndoWebsite.ReadPlaces(path));
            Assert.Equal(UndoWebsiteAnswer.CannotTell, AnswerFor(course));

            // Beneath a readable newer one it is never opened.
            WriteFragment(Fragment(course, "20261114T090000Z-netlify.json"), new[] { "Section 1/index" });
            Assert.Equal(UndoWebsiteAnswer.NoOffer, AnswerFor(course));
        }
    }

    [Fact]
    public void AnUnpairedSurrogateInAMoveOrAPlaceCannotTell()
    {
        // The W5 review's M1, the pure half: NTFS allows a name holding half a
        // surrogate pair, which cannot be put in normalization form C. Such a
        // path is not a page the record could name, and such a place is a
        // fragment that cannot be read: both CANNOT TELL, never an exception.
        string halfPair = "courses/TST1O/Section 1/Classes/Day \ud800.md";
        Assert.Null(UndoWebsite.PlaceOf(halfPair));
        var shown = new[] { new UndoWebsiteFragment("20261113T090000Z-netlify.json", new[] { "Section 1/index" }) };
        Assert.Equal(UndoWebsiteAnswer.CannotTell, UndoWebsite.Answer(
            new[] { new UndoWebsiteMove(halfPair, true, false) }, false, shown, new[] { "netlify" }, Array.Empty<string>()));

        var unreadable = new[] { new UndoWebsiteFragment("20261113T090000Z-netlify.json", new[] { "Section 1/Day \udc00" }) };
        Assert.Equal(UndoWebsiteAnswer.CannotTell, UndoWebsite.Answer(
            new[] { HideDay1 }, false, unreadable, new[] { "netlify" }, Array.Empty<string>()));

        // Another destination that gives the offer still gives it.
        var both = new[]
        {
            new UndoWebsiteFragment("20261113T090000Z-netlify.json", new[] { "Section 1/Day \udc00" }),
            new UndoWebsiteFragment("20261113T090000Z-cloudflare.json", new[] { Day1 }),
        };
        Assert.Equal(UndoWebsiteAnswer.OfferToDeploy, UndoWebsite.Answer(
            new[] { HideDay1 }, false, both, new[] { "netlify", "cloudflare" }, Array.Empty<string>()));
    }

    [Fact]
    public void Proposed_AFragmentIsReadByItsPlacesWhateverItsVersion()
    {
        foreach (string? version in new[] { null, "2" })
        {
            var course = Course("netlify");
            WriteFragment(Fragment(course, "20261113T090000Z-netlify.json"), new[] { Day1 }, version);
            Assert.Equal(UndoWebsiteAnswer.OfferToDeploy, AnswerFor(course));
        }
    }

    [Fact]
    public void TwoWebHostsInDifferentStatesEachAnswerForThemselves()
    {
        // #799: each host is built for its own address and records its own
        // fragment after its own upload, so each is read on its own.
        var hostsAgree = Course("netlify", "cloudflare_pages");
        WriteFragment(Fragment(hostsAgree, "20261113T090000Z-netlify.json"), new[] { "Section 1/index" });
        WriteFragment(Fragment(hostsAgree, "20261113T091000Z-cloudflare.json"), new[] { "Section 1/index" });
        Assert.Equal(UndoWebsiteAnswer.NoOffer, AnswerFor(hostsAgree));

        // The primary already matches; the additional still shows the page.
        var secondBehind = Course("netlify", "cloudflare_pages");
        WriteFragment(Fragment(secondBehind, "20261113T090000Z-netlify.json"), new[] { "Section 1/index" });
        WriteFragment(Fragment(secondBehind, "20261101T090000Z-cloudflare.json"), new[] { Day1 });
        Assert.Equal(UndoWebsiteAnswer.OfferToDeploy, AnswerFor(secondBehind));

        // One host matches, the other has a marker and no fragment: cannot tell.
        var secondUnknown = Course("netlify", "cloudflare_pages");
        WriteFragment(Fragment(secondUnknown, "20261113T090000Z-netlify.json"), new[] { "Section 1/index" });
        Marker(secondUnknown, ".cloudflare_sites");
        Assert.Equal(UndoWebsiteAnswer.CannotTell, AnswerFor(secondUnknown));

        // One host matches, the other was never deployed (no marker, no fragment): no offer.
        var secondNever = Course("netlify", "cloudflare_pages");
        WriteFragment(Fragment(secondNever, "20261113T090000Z-netlify.json"), new[] { "Section 1/index" });
        Assert.Equal(UndoWebsiteAnswer.NoOffer, AnswerFor(secondNever));

        // Fragments with the same moment for two hosts are each their own host's.
        var sameMoment = Course("netlify", "cloudflare_pages");
        WriteFragment(Fragment(sameMoment, "20261113T090000Z-netlify.json"), new[] { "Section 1/index" });
        WriteFragment(Fragment(sameMoment, "20261113T090000Z-cloudflare.json"), new[] { Day1 });
        Assert.Equal(UndoWebsiteAnswer.OfferToDeploy, AnswerFor(sameMoment));
    }

    [Fact]
    public void Proposed_AChangeToWhatAPageSaysInASectionNeverDeployedHasNoOffer()
    {
        // The rule's NO OFFER sentence ("no destination deployed to now has a
        // fragment or a site marker") comes before what a page says.
        var course = Course("netlify");
        Assert.Equal(UndoWebsiteAnswer.NoOffer,
            UndoWebsite.Answer(Array.Empty<UndoWebsiteMove>(), true, UndoWebsite.Inputs(course, 1).Record,
                new[] { "netlify" }, Array.Empty<string>()));
    }

    [Fact]
    public void Proposed_AMoveWhosePathIsNotAPageCannotTell()
    {
        foreach (string path in new[] { "courses/TST1O/course_config.json", "Section 1/Classes/Day 1.md", "courses/TST1O/.md" })
        {
            Assert.Null(UndoWebsite.PlaceOf(path));
            var course = Course("netlify");
            WriteFragment(Fragment(course, "20261113T090000Z-netlify.json"), new[] { "Section 1/index" });
            Assert.Equal(UndoWebsiteAnswer.CannotTell, AnswerFor(course, false, new UndoWebsiteMove(path, true, false)));
        }
        Assert.Equal(Day1, UndoWebsite.PlaceOf("courses/TST1O/Section 1/Classes/Day 1.md"));
        Assert.Equal("Shared/Unit 1/Reading", UndoWebsite.PlaceOf("courses/TST1O/Shared/Unit 1/Reading.md"));
    }

    [Fact]
    public void OnlyTheNewestFragmentOfEachDestinationIsOpened()
    {
        // A year of deploys is hundreds of fragments; the reader opens one per
        // destination, so an unreadable old one costs nothing.
        var course = Course("netlify", "cloudflare_pages");
        for (int day = 1; day <= 9; day++)
            File.WriteAllText(Fragment(course, $"2026110{day}T090000Z-netlify.json"), "{ not json");
        WriteFragment(Fragment(course, "20261110T090000Z-netlify.json"), new[] { "Section 1/index" });
        WriteFragment(Fragment(course, "20261110T090000Z-cloudflare.json"), new[] { "Section 1/index" });
        var inputs = UndoWebsite.Inputs(course, 1);
        Assert.Equal(new[] { "20261110T090000Z-cloudflare.json", "20261110T090000Z-netlify.json" },
            inputs.Record!.Select(f => f.Name).OrderBy(n => n, StringComparer.Ordinal));
        Assert.Equal(UndoWebsiteAnswer.NoOffer, AnswerFor(course));
    }

    [Fact]
    public void ReadingTheRecordWritesNothing()
    {
        // Reading is reading: the working folder ends with exactly the files it began with.
        var course = Course("netlify");
        WriteFragment(Fragment(course, "20261113T090000Z-netlify.json"), new[] { Day1 });
        string workingFolder = Path.GetDirectoryName(Path.GetDirectoryName(course.DirectoryPath)!)!;
        string[] Files() => Directory.GetFileSystemEntries(workingFolder, "*", SearchOption.AllDirectories)
            .OrderBy(p => p, StringComparer.Ordinal).ToArray();
        var before = Files();
        Assert.Equal(UndoWebsiteAnswer.OfferToDeploy, AnswerFor(course));
        Assert.Equal(before, Files());
    }
}

/// <summary>
/// A fact that needs a deny ACE to stop this account listing a folder:
/// SKIPPED, saying why, when it does not (an administrator's token, as over
/// SSH, passes over it), so the totals line counts it as not run rather than
/// failed, the convention of <see cref="FileLinkFactAttribute"/>. The probe
/// makes a temporary folder, denies itself listing, tries, and removes both.
/// </summary>
public sealed class DenyBitesFactAttribute : FactAttribute
{
    private static readonly Lazy<bool> DenyBites = new(Probe);

    public DenyBitesFactAttribute()
    {
        if (!DenyBites.Value)
            Skip = "A deny ACE does not stop this account listing a folder (an administrator's token, as over SSH), so "
                 + "'a record folder that denies listing cannot tell' cannot be tried on the disk here; "
                 + "Proposed_ARecordFolderThatCannotBeListedCannotTell covers it through the listing seam.";
    }

    private static bool Probe()
    {
        string folder = Directory.CreateTempSubdirectory("deny-probe-").FullName;
        var info = new DirectoryInfo(folder);
        var rights = info.GetAccessControl();
        var deny = new FileSystemAccessRule(WindowsIdentity.GetCurrent().User!, FileSystemRights.ListDirectory, AccessControlType.Deny);
        try
        {
            rights.AddAccessRule(deny);
            info.SetAccessControl(rights);
            try
            {
                _ = Directory.EnumerateFiles(folder).ToList();
                return false;
            }
            catch (UnauthorizedAccessException) { return true; }
            catch (IOException) { return true; }
        }
        catch { return false; }
        finally
        {
            try { rights.RemoveAccessRule(deny); info.SetAccessControl(rights); } catch { }
            try { Directory.Delete(folder); } catch { }
        }
    }
}

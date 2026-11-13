using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// <c>contracts/app-rules.json</c> → <c>publishingDestinations</c> (#739, the
/// mac's #668): where a NEW course deploys, the picker's order, the sentences a
/// teacher reads while choosing and when each shows, and the Account ID — the
/// new-course dialog lets a missing one wait, the first deploy refuses it, says
/// so on the trail by kind, and offers Open Settings…. Every list is read from
/// the contract, never retyped: the mac's <c>PublishingDestinationsTests</c>
/// runs the same cases.
/// </summary>
public class PublishingDestinationsContractTests
{
    private static JsonNode Block => ContractLoader.LoadJson("app-rules.json")["publishingDestinations"]!;

    private static List<string> Strings(JsonNode? array) =>
        array?.AsArray().Select(item => item!.ToString()).ToList() ?? new List<string>();

    private static CourseConfiguration FromJson(string json) =>
        CourseConfiguration.FromBytes(Encoding.UTF8.GetBytes(json));

    // ---- The default, the fallback, and the order ---------------------------

    [Fact]
    public void ANewCourseStartsOnTheContractsDefault()
    {
        Assert.Equal(Block["newCourseDefault"]!.ToString(), PublishingDestinations.NewCourseDefault);
    }

    /// <summary>
    /// The fallback is READ, not just declared: a file naming no destination
    /// deploys to <c>whenTheKeyIsAbsent</c>, and that is NOT the new-course
    /// default (<c>whyTheyDiffer</c>) — the test fails if either side drifts
    /// onto the other.
    /// </summary>
    [Fact]
    public void AnAbsentKeyStillDeploysWhereTheContractSays()
    {
        string absent = Block["whenTheKeyIsAbsent"]!.ToString();
        Assert.Equal(absent, PublishingDestinations.WhenTheKeyIsAbsent);
        Assert.Equal(absent, FromJson("""{"course_code":"ICS3U"}""").DeployTarget);
        Assert.Equal(absent, FromJson("""{"course_code":"ICS3U","deploy_target":""}""").DeployTarget);
        Assert.NotEqual(PublishingDestinations.NewCourseDefault, absent);
    }

    [Fact]
    public void ThePickerOffersTheDestinationsInTheContractsOrder()
    {
        Assert.Equal(Strings(Block["pickerOrder"]), PublishingDestinations.PickerOrder);
        // The additional list is drawn from the same order, less the primary.
        var order = Strings(Block["pickerOrder"]);
        foreach (string primary in order)
            Assert.Equal(order.Where(type => type != primary).ToList(),
                         CourseConfiguration.AvailableAdditionalDeployTargetTypes(primary));
    }

    [Fact]
    public void TheSentencesAreTheContracts()
    {
        var sentences = Block["sentences"]!;
        Assert.Equal(sentences["accountIDCanWait"]!.ToString(), PublishingDestinations.AccountIdCanWait);
        Assert.Equal(sentences["cloudflareCaption"]!.ToString(), PublishingDestinations.CloudflareCaption);
        Assert.Equal(sentences["netlifyNote"]!.ToString(), PublishingDestinations.NetlifyNote);
        Assert.Equal(sentences["netlifyScheduleNote"]!.ToString(), PublishingDestinations.NetlifyScheduleNote);
        Assert.Equal(sentences["wizardCaption"]!.ToString(), PublishingDestinations.WizardCaption);
        // The 25 MB sentence under Cloudflare Pages became the contract's on
        // 2026-11-12 (mac #775, Windows #787): the words Windows already showed.
        Assert.Equal(sentences["cloudflareSizeNote"]!.ToString(), PublishingDestinations.CloudflareSizeNote);
        // Six today; a seventh added on the mac must be wired here, not ignored.
        Assert.Equal(6, sentences.AsObject().Count);
    }

    // ---- netlifyNoteCases -------------------------------------------------

    [Fact]
    public void TheNotesShowWhereTheContractSays()
    {
        var cases = Block["netlifyNoteCases"]!.AsArray();
        Assert.NotEmpty(cases);
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            string primary = c["primary"]!.ToString();
            var additional = Strings(c["additional"]);
            Assert.True(c["expectNetlifyNote"]!.GetValue<bool>() == PublishingDestinations.ShowsNetlifyNote(primary, additional),
                        $"{name}: the Netlify note");
            Assert.True(c["expectCloudflareCaption"]!.GetValue<bool>() == PublishingDestinations.ShowsCloudflareCaption(primary, additional),
                        $"{name}: the Cloudflare caption");
        }
    }

    /// <summary>
    /// Schedule a deploy says <c>netlifyScheduleNote</c> when the SAVED settings
    /// deploy to Netlify, read through the same rule as the note: each
    /// <c>netlifyNoteCases</c> case written as a saved file, an empty primary
    /// as a file with no key at all.
    /// </summary>
    [Fact]
    public void ScheduleADeployCarriesTheNoteWhenTheSavedSettingsDeployToNetlify()
    {
        foreach (var c in Block["netlifyNoteCases"]!.AsArray())
        {
            string name = c!["name"]!.ToString();
            string primary = c["primary"]!.ToString();
            var file = new JsonObject { ["course_code"] = "ICS3U" };
            if (primary.Length > 0) file["deploy_target"] = primary;
            var additional = new JsonArray();
            foreach (string type in Strings(c["additional"]))
                additional.Add(new JsonObject { ["type"] = type });
            if (additional.Count > 0) file["additional_deploy_targets"] = additional;

            string? note = PublishingDestinations.ScheduleNote(FromJson(file.ToJsonString()));
            string? expected = c["expectNetlifyNote"]!.GetValue<bool>()
                ? Block["sentences"]!["netlifyScheduleNote"]!.ToString()
                : null;
            Assert.True(expected == note, $"{name}: expected {expected ?? "no note"}, got {note ?? "no note"}");
        }
    }

    // ---- wizardAccountID.cases --------------------------------------------

    /// <summary>
    /// The new-course dialog: what it says about the ID, whether "it can wait"
    /// follows, and whether Create is refused. The warning is the first run of
    /// the ONE block, the ID's sentence before the 25 MB note, and "it can wait"
    /// follows it directly — the orange block the dialog draws.
    /// </summary>
    [Fact]
    public void TheNewCourseDialogLetsAMissingIdWaitAndRefusesAWrongOne()
    {
        var cases = Block["wizardAccountID"]!["cases"]!.AsArray();
        Assert.NotEmpty(cases);
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            string id = c["accountID"]!.ToString();
            string? expectWarning = c["expectWarning"]?.ToString();
            string? expectRefusal = c["expectCreateRefusal"]?.ToString();
            bool expectCanWait = c["expectAccountIDCanWait"]!.GetValue<bool>();

            Assert.True(expectRefusal == PublishingDestinations.WizardCreateRefusal(id), $"{name}: Create's refusal");

            var parts = PublishingDestinations.CloudflareNotice(id, accountIdMayWait: true);
            Assert.Equal(PublishingDestinations.CloudflareSizeNote, parts[^1].Text);
            Assert.True(parts[^1].Caution, $"{name}: the 25 MB note is orange");
            if (expectWarning is null)
            {
                Assert.True(parts.Count == 1, $"{name}: nothing but the 25 MB note was to be said");
            }
            else
            {
                Assert.Equal(expectWarning + " ", parts[0].Text);
                Assert.True(parts[0].Caution, $"{name}: the ID's sentence is orange");
            }
            bool saysItCanWait = parts.Any(part => part.Text.TrimEnd() == PublishingDestinations.AccountIdCanWait);
            Assert.True(expectCanWait == saysItCanWait, $"{name}: \"it can wait\"");
            if (expectCanWait)
            {
                Assert.Equal(PublishingDestinations.AccountIdCanWait + " ", parts[1].Text);
                Assert.False(parts[1].Caution, $"{name}: \"it can wait\" is in the secondary colour");
            }

            // Course Settings never lets it wait: the same warning, no
            // "it can wait", and Save is held back by whatever is wrong.
            var inSettings = PublishingDestinations.CloudflareNotice(id, accountIdMayWait: false);
            Assert.DoesNotContain(inSettings, part => part.Text.TrimEnd() == PublishingDestinations.AccountIdCanWait);
            Assert.True(expectWarning == CourseConfiguration.CloudflareAccountProblem(id), $"{name}: the warning");
        }
    }

    // ---- deployWithoutAnAccountID.cases -------------------------------------

    private static List<CourseConfiguration.DeployDestination> Destinations(JsonNode c) =>
        Strings(c["destinations"]).Select(type => new CourseConfiguration.DeployDestination(type, "")).ToList();

    /// <summary>
    /// The deploy-time refusal, Open Settings… beside OK, and the trail line,
    /// each against the case. The refusal is the one every in-app deploy door
    /// reads (<see cref="MultiDestinationDeployRunner.RefusalReason"/>), and the
    /// cases pin only its START: the rest names where it is put right.
    /// </summary>
    [Fact]
    public void TheFirstDeployRefusesTheIdAndSaysSoOnTheTrailByKind()
    {
        var cases = Block["deployWithoutAnAccountID"]!["cases"]!.AsArray();
        Assert.NotEmpty(cases);
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            string id = c["accountID"]!.ToString();
            var destinations = Destinations(c);
            string? expectStart = c["expectRefusalStartsWith"]?.ToString();
            string? expectLine = c["expectTrailLine"]?.ToString();
            bool expectOpenSettings = c["expectOpenSettings"]!.GetValue<bool>();

            string? refusal = MultiDestinationDeployRunner.RefusalReason(destinations, id);
            if (expectStart is null) Assert.True(refusal is null, $"{name}: refused with \"{refusal}\"");
            else Assert.True(refusal is not null && refusal.StartsWith(expectStart, StringComparison.Ordinal),
                             $"{name}: expected a refusal starting \"{expectStart}\", got \"{refusal}\"");

            bool opens = refusal is not null && PublishingDestinations.DeployRefusalOpensSettings(refusal, id);
            Assert.True(expectOpenSettings == opens, $"{name}: Open Settings…");

            string? line = PublishingDestinations.AccountIdRefusalTrailLine(destinations, id);
            Assert.True(expectLine == line, $"{name}: expected the line \"{expectLine}\", got \"{line}\"");
            // By kind, never the ID.
            if (line is not null && id.Trim().Length > 0)
                Assert.DoesNotContain(id.Trim(), line);
        }
    }

    /// <summary>The event the line is written under is the contract's, word for word.</summary>
    [Fact]
    public void TheRefusalsLineIsWrittenUnderTheContractsEvent()
    {
        var events = ContractLoader.LoadJson("shared-rules.json")["activityTrail"]!["mustRecord"]!.AsArray()
            .Select(entry => entry!["event"]!.ToString());
        string key = ActivityTrail.KeyFor(ActivityTrail.Event.DeployRefusedForTheCloudflareAccountId);
        Assert.Contains(key, events);
        var entry = ContractLoader.LoadJson("shared-rules.json")["activityTrail"]!["mustRecord"]!.AsArray()
            .Single(item => item!["event"]!.ToString() == key)!;
        // The example line is "<course>/<section> · " plus a case's line.
        string example = entry["line"]!.ToString();
        var lines = Block["deployWithoutAnAccountID"]!["cases"]!.AsArray()
            .Select(c => c!["expectTrailLine"]?.ToString()).Where(l => l is not null).ToList();
        Assert.Contains(lines, l => example.EndsWith(" · " + l, StringComparison.Ordinal));
    }

    /// <summary>
    /// OK stays the refusal's DEFAULT button when Open Settings… is offered
    /// (#739, the mac's "OK stays the default button"): Enter must leave the
    /// refusal, not open another window. Read from the source, since a
    /// ContentDialog cannot be built in this suite: the initializer that sets
    /// the Open Settings… button must say <c>ContentDialogButton.Close</c>.
    /// </summary>
    [Fact]
    public void OkStaysTheRefusalsDefaultButton()
    {
        string source = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot,
            "windows-app", "Plantoir", "Views", "SectionDetailView.xaml.cs"));
        int button = source.IndexOf("PrimaryButtonText = opensSettings ? \"Open Settings…\"", StringComparison.Ordinal);
        Assert.True(button >= 0, "the Deploy refusal no longer offers Open Settings… where this test looks");
        int start = source.LastIndexOf("new ContentDialog", button, StringComparison.Ordinal);
        int end = source.IndexOf("};", button, StringComparison.Ordinal);
        string initializer = source[start..end];
        Assert.Contains("DefaultButton = ContentDialogButton.Close", initializer);
        Assert.DoesNotContain("ContentDialogButton.Primary", initializer);
    }

    /// <summary>
    /// A folder's refusal never offers Open Settings…, however the ID stands:
    /// it is put right in the course's own settings.
    /// </summary>
    [Fact]
    public void AFoldersRefusalNeverOpensSettings()
    {
        var folderFirst = new[]
        {
            new CourseConfiguration.DeployDestination("local_folder", ""),
            new CourseConfiguration.DeployDestination("cloudflare_pages", ""),
        };
        string refusal = MultiDestinationDeployRunner.RefusalReason(folderFirst, "")!;
        Assert.False(PublishingDestinations.DeployRefusalOpensSettings(refusal, ""));
        Assert.False(PublishingDestinations.DeployRefusalOpensSettings(refusal, "abc"));
    }
}

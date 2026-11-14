using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Plantoir.Core.Models;

namespace Plantoir.Core.Undo;

/// <summary>What <see cref="UndoWebsite.Answer"/> says about one Undo or Redo.</summary>
public enum UndoWebsiteAnswer
{
    /// <summary>Some website the section deploys to shows a page as the course had it BEFORE the move.</summary>
    OfferToDeploy,
    /// <summary>Every website read already shows what the move leaves, or the section was never deployed where it deploys now.</summary>
    NoOffer,
    /// <summary>The record cannot say (a site marker and no fragment, a newest fragment that cannot be read, or a change to what a page says).</summary>
    CannotTell,
}

/// <summary>
/// One page an Undo or Redo changes: its op path inside the working folder
/// (<c>courses/&lt;CODE&gt;/&lt;place&gt;.md</c>, forward slashes) and whether
/// students can see it in the course before and after the move, worked out by
/// the caller with the build's own hide rule.
/// </summary>
public sealed record UndoWebsiteMove(string Path, bool VisibleBefore, bool VisibleAfter);

/// <summary>
/// One file of the section's published-pages folder, by its name, with the
/// places it lists; <see cref="Places"/> is null when the file could not be read.
/// </summary>
public sealed record UndoWebsiteFragment(string Name, IReadOnlyList<string>? Places);

/// <summary>
/// The inputs <see cref="UndoWebsite.Answer"/> needs that come from disk, as
/// <see cref="UndoWebsite.Inputs"/> read them. <see cref="Record"/> is null
/// when the published-pages folder exists and could not be listed.
/// </summary>
public sealed record UndoWebsiteInputs(
    IReadOnlyList<UndoWebsiteFragment>? Record,
    IReadOnlyList<string> Destinations,
    IReadOnlyList<string> SiteMarkers);

/// <summary>
/// <c>shared-rules.json</c> → <c>undo.rule.deployed</c> (#899, ruling 19):
/// after an Undo or a Redo, does some website the section deploys to NOW
/// still show a page the way the course had it before the move, so Plantoir
/// must offer to deploy? Read from the published-pages record
/// (<c>file-formats.json</c> → <c>publishedPagesRecord</c>), which every deploy
/// path writes (deploy.py after each Netlify or Cloudflare upload, deploy.ps1
/// after a folder publish), and NEVER from the undo journal: nothing a
/// launcher does touches the journal. Pure: no clock, no static state, and
/// the one reader of the disk (<see cref="Inputs"/>) takes the folder it reads.
/// Nothing calls it yet; U6 (Windows' W10) makes the offer.
/// </summary>
public static class UndoWebsite
{
    /// <summary>The destination types the record and the contract name.</summary>
    public const string Netlify = "netlify";
    public const string Cloudflare = "cloudflare";
    public const string Folder = "folder";

    // yyyyMMddTHHmmssZ-<destination>.json, the whole name. Anything else
    // (a write in progress, .<name>.<pid>.tmp, a misnamed file) is not a fragment.
    private static readonly Regex FragmentName =
        new(@"^(\d{8}T\d{6}Z)-(.+)\.json$", RegexOptions.CultureInvariant);

    /// <summary>
    /// The contract's destination for one of Windows' <c>course_config.json</c>
    /// types (<see cref="CourseConfiguration.KnownDeployTargetTypes"/>): the
    /// type deploy.ps1 names each fragment after (<c>netlify</c>,
    /// <c>cloudflare</c>, and <c>folder</c> for <c>local_folder</c>, the plan
    /// review's L7). Null for a type no deploy accepts: deploy.ps1 refuses it,
    /// so nothing was ever deployed there and nothing is read for it.
    /// </summary>
    public static string? DestinationFor(string configurationType) => configurationType switch
    {
        "" or "netlify" => Netlify,
        "cloudflare_pages" => Cloudflare,
        "local_folder" => Folder,
        _ => null,
    };

    /// <summary>
    /// <c>undo.rule.deployed</c>, word for word. For each destination the section
    /// deploys to now, its newest fragment by the moment in its name says which
    /// pages that website shows. The move offers to deploy when, for some page
    /// whose visibility it changes, some destination's newest fragment shows the
    /// page as the course has it BEFORE the move. Otherwise it cannot tell when a
    /// destination has a site marker and no fragment, when a destination's newest
    /// fragment cannot be read, or when the move also changes what a page says;
    /// and there is no offer when every destination read already shows what the
    /// move leaves, or none has a fragment or a site marker.
    /// </summary>
    /// <param name="record">Every file of the section's published-pages folder;
    /// null when the folder could not be listed (every destination is then one
    /// whose newest fragment cannot be read).</param>
    /// <param name="destinations">The contract's types (netlify, cloudflare, folder) the section deploys to now, primary and additional.</param>
    /// <param name="siteMarkers">Those of <paramref name="destinations"/> that have a site marker.</param>
    public static UndoWebsiteAnswer Answer(
        IReadOnlyList<UndoWebsiteMove> moves,
        bool changesMoreThanVisibility,
        IReadOnlyList<UndoWebsiteFragment>? record,
        IReadOnlyList<string> destinations,
        IReadOnlyCollection<string> siteMarkers)
    {
        var newest = record is null ? null : NewestFragments(record, destinations);
        bool deployedSomewhere = false;
        bool cannotTell = false;

        foreach (string destination in destinations.Distinct(StringComparer.Ordinal))
        {
            if (newest is null)
            {
                // The folder could not be listed: what this destination shows is unknown.
                deployedSomewhere = true;
                cannotTell = true;
                continue;
            }
            if (!newest.TryGetValue(destination, out var fragment))
            {
                if (siteMarkers.Contains(destination))
                {
                    deployedSomewhere = true;
                    cannotTell = true;
                }
                continue;
            }
            deployedSomewhere = true;
            if (fragment.Places is null)
            {
                cannotTell = true;
                continue;
            }
            var shown = new HashSet<string>(fragment.Places.Select(Composed), StringComparer.Ordinal);
            foreach (var move in moves)
            {
                if (move.VisibleBefore == move.VisibleAfter) continue;
                string? place = PlaceOf(move.Path);
                if (place is null)
                {
                    // Not a page the record could name: what the site shows of it is unknown.
                    cannotTell = true;
                    continue;
                }
                if (shown.Contains(place) == move.VisibleBefore) return UndoWebsiteAnswer.OfferToDeploy;
            }
        }

        if (!deployedSomewhere) return UndoWebsiteAnswer.NoOffer;
        if (cannotTell || changesMoreThanVisibility) return UndoWebsiteAnswer.CannotTell;
        return UndoWebsiteAnswer.NoOffer;
    }

    /// <summary>
    /// The newest fragment of each of <paramref name="destinations"/>, by the
    /// moment in its own name (fixed width, so ordinal order is time order).
    /// A destination with no fragment is absent. Fragments of a destination the
    /// section no longer deploys to are never chosen (the contract review's I1).
    /// </summary>
    public static Dictionary<string, UndoWebsiteFragment> NewestFragments(
        IEnumerable<UndoWebsiteFragment> record, IReadOnlyCollection<string> destinations)
    {
        var newest = new Dictionary<string, (string Stamp, UndoWebsiteFragment Fragment)>(StringComparer.Ordinal);
        foreach (var fragment in record)
        {
            var found = FragmentName.Match(fragment.Name);
            if (!found.Success) continue;
            string stamp = found.Groups[1].Value, destination = found.Groups[2].Value;
            if (!destinations.Contains(destination)) continue;
            if (!newest.TryGetValue(destination, out var held) || string.CompareOrdinal(stamp, held.Stamp) > 0)
                newest[destination] = (stamp, fragment);
        }
        return newest.ToDictionary(pair => pair.Key, pair => pair.Value.Fragment, StringComparer.Ordinal);
    }

    /// <summary>
    /// The record's name for an op path: <c>courses/&lt;CODE&gt;/&lt;place&gt;.md</c>
    /// is <c>&lt;place&gt;</c>, in Unicode normalization form C. Null for a path
    /// of any other shape.
    /// </summary>
    public static string? PlaceOf(string opPath)
    {
        string[] parts = opPath.Split('/');
        if (parts.Length < 3 || parts[0] != "courses" || parts[1].Length == 0) return null;
        string rest = string.Join('/', parts, 2, parts.Length - 2);
        if (!rest.EndsWith(".md", StringComparison.Ordinal) || rest.Length == 3) return null;
        return Composed(rest[..^3]);
    }

    private static string Composed(string text) =>
        text.IsNormalized(NormalizationForm.FormC) ? text : text.Normalize(NormalizationForm.FormC);

    // -------------------------------------------------------------------
    // The one reader of the disk.
    // -------------------------------------------------------------------

    /// <summary>
    /// The inputs of <see cref="Answer"/> for one section, read where Windows
    /// keeps them: the destinations from the course's configuration
    /// (<see cref="CourseConfiguration.AllDeployDestinations"/>, primary and
    /// additional, mapped by <see cref="DestinationFor"/>), the site markers
    /// at the paths <see cref="DeployCommand.FirstDeployMarkerPath(int, Course, string)"/>
    /// names (<c>file-formats.json</c> → <c>firstDeployMarkers</c>, the ones the
    /// scheduled deploy reads), and the record at
    /// <c>courses\&lt;CODE&gt;\.publish_state\section&lt;N&gt;.published-pages\</c>.
    /// Of the record, only the newest fragment of each destination read is
    /// opened (the others cannot change the answer, and a year of deploys is
    /// hundreds of files); it is not <see cref="Assist.LinksChecklist.PublishedPlaces"/>,
    /// which is the union of every fragment and the wrong question here.
    /// </summary>
    public static UndoWebsiteInputs Inputs(Course course, int section)
    {
        var destinations = new List<string>();
        var markers = new List<string>();
        foreach (var target in course.Configuration.AllDeployDestinations)
        {
            string? destination = DestinationFor(target.Type);
            if (destination is null || destinations.Contains(destination)) continue;
            destinations.Add(destination);
            string? marker = DeployCommand.FirstDeployMarkerPath(section, course, target.Type);
            if (marker is not null && File.Exists(marker)) markers.Add(destination);
        }

        string folder = RecordFolder(course.DirectoryPath, section);
        List<string> names;
        try
        {
            names = Directory.Exists(folder)
                ? Directory.EnumerateFiles(folder).Select(file => System.IO.Path.GetFileName(file)).ToList()
                : new List<string>();
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return new UndoWebsiteInputs(null, destinations, markers);
        }

        var unread = names.Select(name => new UndoWebsiteFragment(name, Array.Empty<string>()));
        var record = NewestFragments(unread, destinations).Values
            .Select(fragment => new UndoWebsiteFragment(fragment.Name, ReadPlaces(System.IO.Path.Combine(folder, fragment.Name))))
            .ToList();
        return new UndoWebsiteInputs(record, destinations, markers);
    }

    /// <summary><c>courses/&lt;CODE&gt;/.publish_state/section&lt;N&gt;.published-pages</c>.</summary>
    public static string RecordFolder(string courseDirectory, int section) =>
        System.IO.Path.Combine(courseDirectory, ".publish_state", $"section{section}.published-pages");


    /// <summary>
    /// A fragment's <c>places</c>, or null when it cannot be read: the file
    /// will not open, is not JSON, or has no <c>places</c> that is a list of
    /// strings. <c>version</c> is not read: the rule reads only the places, and
    /// a fragment with no version, or a later one, still says which pages its
    /// site shows (a proposal, not a contract case: drafts/899-w5-mac-issue.md).
    /// </summary>
    public static IReadOnlyList<string>? ReadPlaces(string fragmentPath)
    {
        try
        {
            byte[] bytes;
            using (var stream = new FileStream(fragmentPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            using (var copy = new MemoryStream())
            {
                stream.CopyTo(copy);
                bytes = copy.ToArray();
            }
            ReadOnlySpan<byte> json = bytes;
            if (json.StartsWith(Encoding.UTF8.Preamble)) json = json[Encoding.UTF8.Preamble.Length..];
            using var document = JsonDocument.Parse(json.ToArray());
            if (document.RootElement.ValueKind != JsonValueKind.Object) return null;
            if (!document.RootElement.TryGetProperty("places", out var places) || places.ValueKind != JsonValueKind.Array) return null;
            var result = new List<string>();
            foreach (var place in places.EnumerateArray())
            {
                if (place.ValueKind != JsonValueKind.String) return null;
                result.Add(place.GetString()!);
            }
            return result;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException)
        {
            return null;
        }
    }
}

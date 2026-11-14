using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Xunit;
using static Plantoir.Tests.DeployedFolderFixtures;

namespace Plantoir.Tests;

/// <summary>
/// Every case of <c>contracts/shared-rules.json</c> → <c>deployedFolderInBrowser.resolution.cases</c>
/// (#889, the mac's #850), walked from the JSON, TWICE: through
/// <see cref="DeployedFolderResolver"/> on a real folder (links laid over the
/// disk by <see cref="DiskWithLinks"/>, so both link cases run on this account),
/// and through the real <see cref="DeployedFolderServer"/> over a socket (the
/// folder link a real junction; the file link a real symbolic link, which only
/// <see cref="TheFileLinkCaseOverASocket"/> needs and skips by name when this
/// account cannot make one).
/// </summary>
[Collection(DeployedFolderTimings.Name)]
public sealed class DeployedFolderResolutionTests : IDisposable
{
    private readonly string _base = Path.Combine(Path.GetTempPath(), "plantoir-deployed-" + Guid.NewGuid().ToString("N"));

    public void Dispose() => ReferenceFixtures.Remove(_base);

    public static IEnumerable<object[]> CaseNames() =>
        ResolutionCases.Select(c => new object[] { c!["name"]!.ToString() });

    public static IEnumerable<object[]> CaseNamesOverASocket() =>
        ResolutionCases.Where(c => !IsFileLink(c!)).Select(c => new object[] { c!["name"]!.ToString() });

    private static bool IsFileLink(JsonNode testCase) =>
        testCase["files"]!.AsObject().Any(pair => pair.Value is JsonObject link && link["symlinkTo"]!.ToString().EndsWith(".html", StringComparison.Ordinal));

    private static JsonNode Case(string name) => ResolutionCases.Single(c => c!["name"]!.ToString() == name)!;

    private Places NewPlaces(int port)
    {
        string folder = Path.Combine(_base, Guid.NewGuid().ToString("N")[..8]);
        return new Places(Path.Combine(folder, "site"), Path.Combine(folder, "outside"), port);
    }

    [Fact]
    public void TheContractHasTheCasesTheMacRuns()
    {
        Assert.Equal(76, ResolutionCases.Count);
        Assert.Equal(76, ResolutionCases.Select(c => c!["name"]!.ToString()).Distinct().Count());
        Assert.Equal(2, ResolutionCases.Count(c => c!["files"]!.AsObject().Any(p => p.Value is JsonObject)));
    }

    // ---- Through the resolver ----------------------------------------------------------

    [Theory]
    [MemberData(nameof(CaseNames))]
    public void EveryCaseThroughTheResolver(string name)
    {
        var testCase = Case(name);
        var places = NewPlaces(41209);
        WriteFiles(testCase, places);
        var links = Links(testCase, places).ToDictionary(p => Path.Combine(places.Root, p.Key.Replace('/', '\\')), p => p.Value);
        var resolver = new DeployedFolderResolver(places.Root, new DiskWithLinks(links));

        using var answer = resolver.Answer(Request(testCase, places), places.Port);
        byte[] body = BodyOf(answer);
        Check(testCase, answer.Status, answer.Headers, body, answer.ClosesTheConnection, isHead: testCase["request"]!["method"]!.ToString() == "HEAD");
        if (testCase["expect"]!["file"] is { } file)
            Assert.Equal(file.ToString().Normalize(NormalizationForm.FormC), answer.ServedFile?.Normalize(NormalizationForm.FormC));
    }

    private static byte[] BodyOf(DeployedFolderAnswer answer)
    {
        if (answer.Data is { } data) return data;
        if (answer.File is not { } file) return [];
        file.Seek(answer.Offset, SeekOrigin.Begin);
        var bytes = new byte[answer.Length];
        int total = 0;
        while (total < bytes.Length)
        {
            int read = file.Read(bytes, total, bytes.Length - total);
            if (read == 0) break;
            total += read;
        }
        return bytes[..total];
    }

    // ---- Through the real listener ------------------------------------------------------

    [Theory]
    [MemberData(nameof(CaseNamesOverASocket))]
    public void EveryCaseOverASocket(string name) => RunOverASocket(Case(name));

    [DeployedFolderFileLinkFact]
    public void TheFileLinkCaseOverASocket()
    {
        foreach (var testCase in ResolutionCases.Where(c => IsFileLink(c!))) RunOverASocket(testCase!);
    }

    private void RunOverASocket(JsonNode testCase)
    {
        int port = FreePort();
        var places = NewPlaces(port);
        WriteFiles(testCase, places);
        foreach (var (name, target) in Links(testCase, places))
        {
            string link = Path.Combine(places.Root, name.Replace('/', '\\'));
            bool isFolder = !target.EndsWith(".html", StringComparison.Ordinal);
            Assert.True(LocalSiteFixtures.MakeLink(link, target.Replace('/', '\\'), isFolder),
                        "could not make the link for " + testCase["name"]);
        }
        var started = DeployedFolderServer.Start(places.Root, [port]);
        using var server = started.Server ?? throw new InvalidOperationException("the server did not start on " + port);
        var request = Request(testCase, places);
        bool isHead = request.Method == "HEAD";
        using var socket = Connect(port);
        socket.Send(Wire(request));
        var reader = new WireReader(socket);
        var response = reader.ReadResponse(isHead, TimeSpan.FromMilliseconds(testCase["expect"]!["closes"] is not null ? 3000 : 300));
        Check(testCase, response.Status, response.Headers, response.Body, response.Closed, isHead);
        // A HEAD's answer carries no body: nothing arrives after its headers.
        if (isHead) Assert.Equal(0, reader.Extra);
    }

    /// <summary>
    /// The review's L1: a junction inside the folder that leads out answers
    /// EXACTLY as a missing path does, even when the outside folder holds an
    /// index.html (the first version answered 308 to <c>/junc</c>, which told a
    /// caller that file exists). Over a real junction, through the resolver and
    /// over a socket.
    /// </summary>
    [Fact]
    public void AJunctionLeadingOutAnswersAsAMissingPathDoes()
    {
        int port = FreePort();
        var places = NewPlaces(port);
        Directory.CreateDirectory(places.Root);
        File.WriteAllText(Path.Combine(places.Root, "index.html"), "home");
        Directory.CreateDirectory(Path.Combine(places.Outside, "folder"));
        File.WriteAllText(Path.Combine(places.Outside, "index.html"), SecretMarker);
        File.WriteAllText(Path.Combine(places.Outside, "folder", "index.html"), SecretMarker);
        ReferenceFixtures.Junction(Path.Combine(places.Root, "junc"), places.Outside);

        var resolver = new DeployedFolderResolver(places.Root);
        using var missing = resolver.Answer(DeployedFolderRequest.Get("/missing", port), port);
        using var server = DeployedFolderServer.Start(places.Root, [port]).Server!;
        var missingWire = Exchange(port, Wire(DeployedFolderRequest.Get("/missing", port)), false, TimeSpan.Zero);
        foreach (string target in new[] { "/junc", "/junc/", "/junc/index.html", "/junc/folder", "/junc/folder/", "/junc/secret" })
        {
            using var answer = resolver.Answer(DeployedFolderRequest.Get(target, port), port);
            Assert.True(answer.Status == missing.Status, $"{target}: {answer.Status}");
            Assert.Null(answer.Value("Location"));
            Assert.Equal(BodyOf(missing), BodyOf(answer));

            var wire = Exchange(port, Wire(DeployedFolderRequest.Get(target, port)), false, TimeSpan.Zero);
            Assert.Equal(missingWire.Status, wire.Status);
            Assert.Null(wire.Value("Location"));
            Assert.Equal(missingWire.Body, wire.Body);
            Assert.DoesNotContain(SecretMarker, wire.BodyText);
        }
    }

    // ---- What each expectation means ------------------------------------------------------

    private static void Check(JsonNode testCase, int status, IReadOnlyList<KeyValuePair<string, string>> headers, byte[] body,
                              bool closed, bool isHead)
    {
        string name = testCase["name"]!.ToString();
        var expect = testCase["expect"]!.AsObject();
        string? Header(string wanted) => headers.FirstOrDefault(h => string.Equals(h.Key, wanted, StringComparison.OrdinalIgnoreCase)).Value;

        // On every answer.
        foreach (var (header, value) in DeployedFolderFixtures.Block["everyAnswer"]!["headers"]!.AsObject())
            Assert.True(Header(header) == value!.ToString(), $"{name}: {header} was {Header(header) ?? "missing"}");
        string never = DeployedFolderFixtures.Block["everyAnswer"]!["never"]!.ToString();
        Assert.DoesNotContain(headers, h => h.Key.StartsWith(never, StringComparison.OrdinalIgnoreCase));
        Assert.DoesNotContain(SecretMarker, Encoding.UTF8.GetString(body));

        if (expect["status"] is { } wantedStatus) Assert.True((int)wantedStatus == status, $"{name}: status {status}, expected {wantedStatus}");
        if (expect["refused"] is { } refused && (bool)refused)
            Assert.True(status is 400 or 404, $"{name}: a refusal answered {status}");
        if (expect["contentType"] is { } type) Assert.Equal(type.ToString(), Header("Content-Type"));
        if (expect["location"] is { } location) Assert.Equal(location.ToString(), Header("Location"));
        if (expect["noLocation"] is { } noLocation && (bool)noLocation) Assert.Null(Header("Location"));
        if (expect["headers"] is JsonObject wantedHeaders)
            foreach (var (header, value) in wantedHeaders)
                Assert.True(Header(header) == value!.ToString(), $"{name}: {header} was {Header(header) ?? "missing"}, expected {value}");
        if (expect["noHeaderStartingWith"] is { } prefix)
            Assert.DoesNotContain(headers, h => h.Key.StartsWith(prefix.ToString(), StringComparison.OrdinalIgnoreCase));
        if (expect["noBody"] is { } noBody && (bool)noBody) Assert.Empty(body);
        if (expect["bodyLacks"] is { } lacks) Assert.DoesNotContain(lacks.ToString(), Encoding.UTF8.GetString(body));
        if (expect["closes"] is { } closes && (bool)closes) Assert.True(closed, $"{name}: the connection stayed open");
        if (expect["file"] is { } file && ExpectedContent(testCase, file.ToString()) is { } content && !isHead)
            Assert.Equal(content, body);
    }
}

/// <summary>
/// A fact that needs a FILE symbolic link on disk: SKIPPED, naming the case,
/// when this account cannot make one (WinError 1314 without Developer Mode), so
/// the totals line counts it as not run. The same case runs through the
/// resolver's seam in <see cref="DeployedFolderResolutionTests.EveryCaseThroughTheResolver"/>.
/// </summary>
public sealed class DeployedFolderFileLinkFactAttribute : FactAttribute
{
    public DeployedFolderFileLinkFactAttribute()
    {
        if (!LocalSiteFixtures.CanMakeFileLinks)
            Skip = "This account cannot make a file symbolic link (WinError 1314: Developer Mode is off), so the resolution case "
                 + "'a file linked from outside the folder' runs through the resolver's disk seam only, not over a socket.";
    }
}

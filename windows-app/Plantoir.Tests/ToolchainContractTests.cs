using System;
using System.IO;
using System.Linq;
using System.Text.Json.Nodes;
using Xunit;

namespace Plantoir.Tests;

public class ToolchainContractTests
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

    [Fact]
    public void Dockerfile_CarriesPinnedVersions()
    {
        var doc = ContractLoader.LoadJson("toolchain.json");
        string dockerfile = File.ReadAllText(Path.Combine(RepoRoot, "Dockerfile"));
        var pins = doc["pins"]!.AsArray();

        foreach (var pin in pins)
        {
            if (pin is null) continue;
            string name = pin["pin"]!.ToString();
            string value = pin["value"]!.ToString();
            string why = pin["why"]?.ToString() ?? "";

            // A pin that says where to look for itself needs no case here, so
            // the next one costs a contract entry rather than a code change on
            // two platforms. The mac's ToolchainContractTests does the same.
            if (pin["dockerfileContains"]?.ToString() is { } expected)
            {
                // The two fields must say the same thing, or a pin could be
                // raised in `value` and still pass because the line it watches
                // for never mentioned the version.
                Assert.True(expected.Contains(value, StringComparison.Ordinal),
                    $"{name}: the contract watches the Dockerfile for \"{expected}\", which does " +
                    $"not carry the pinned version {value}. {why}");
                Assert.True(dockerfile.Contains(expected, StringComparison.Ordinal), $"{name}: {why}");
                continue;
            }

            switch (name)
            {
                case "baseImage":
                    Assert.Contains($"FROM {value}", dockerfile);
                    break;
                case "node":
                    Assert.Contains($"setup_{value}.x", dockerfile);
                    break;
                case "wrangler":
                    Assert.Contains($"wrangler@{value}", dockerfile);
                    break;
                case "quartz":
                    Assert.Contains($"--branch {value}", dockerfile);
                    break;
                default:
                    Assert.Fail($"Unknown pin: {name}");
                    break;
            }
        }
    }

    /// <summary>
    /// The pins that also have to hold on the runtime a WINDOWS teacher's site
    /// is really built by.
    /// </summary>
    /// <remarks>
    /// <para><c>windows-app/Vendor/fetch-runtime.ps1</c> is the second place
    /// these three are installed, and it is not a mirror of the Dockerfile —
    /// it is the one that matters here, since nothing on this machine builds
    /// the image. Until 2026-09-19 it did an UNPINNED
    /// <c>pip install python-frontmatter Pillow</c>, so the YAML 1.1 table the
    /// whole visibility rule rests on could have moved underneath a teacher
    /// with no test anywhere failing (issue #140).</para>
    ///
    /// <para>The script is not run by any suite — it fetches ~600 MB — so this
    /// asserts the RECIPE rather than the result. The runtime snapshot on this
    /// machine already carries exactly these versions, which is how the pins
    /// were chosen; what is NOT verified here is that a fresh fetch still
    /// resolves them.</para>
    /// </remarks>
    [Fact]
    public void TheWindowsRuntimeRecipeCarriesTheSamePins()
    {
        var doc = ContractLoader.LoadJson("toolchain.json");
        string recipe = File.ReadAllText(
            Path.Combine(RepoRoot, "windows-app", "Vendor", "fetch-runtime.ps1"));

        var watched = doc["pins"]!.AsArray()
            .Where(pin => pin?["windowsRuntimeContains"] is not null)
            .Select(pin => (
                name: pin!["pin"]!.ToString(),
                value: pin["value"]!.ToString(),
                expected: pin["windowsRuntimeContains"]!.ToString(),
                why: pin["why"]?.ToString() ?? ""))
            .ToList();

        // A pin for a runtime piece a later batch brings (#496, #503) is held
        // open by name: its recipe check is skipped, and the ledger fails the
        // day the recipe starts carrying it.
        var deferred = NamedGapLedger.GapsIn(
            NamedGapLedger.ToolchainRuntimePins,
            watched.Select(pin => pin.name),
            watched.Where(pin => recipe.Contains(pin.expected, StringComparison.Ordinal)).Select(pin => pin.name));

        int checked_ = 0;
        foreach (var (name, value, expected, why) in watched)
        {
            // The contract agreeing with itself is checked for EVERY pin,
            // ledgered or not: that half is not this app's to owe.
            Assert.True(expected.Contains(value, StringComparison.Ordinal),
                $"{name}: the contract watches fetch-runtime.ps1 for \"{expected}\", which does " +
                $"not carry the pinned version {value}. {why}");
            if (deferred.Contains(name)) continue;
            Assert.True(recipe.Contains(expected, StringComparison.Ordinal),
                $"{name}: windows-app/Vendor/fetch-runtime.ps1 does not pin {expected}. {why}");
            checked_++;
        }

        Assert.True(checked_ > 0,
            "No pin in contracts/toolchain.json names a windowsRuntimeContains any more. " +
            "The two fetch paths can drift again the moment nothing holds them together.");
    }

    /// <summary>
    /// fetch-runtime.ps1 decides whether runtime\vendor is current by
    /// comparing the manifest against its <c>$&lt;Name&gt;Version</c>
    /// variables, while the addresses it fetches are written out in full. A
    /// pin bump that edited one and not the other would never fetch the new
    /// bytes, or record old bytes under the new version (batch 5A review,
    /// L2). The script refuses when an address and its variable disagree;
    /// this holds each variable against the version in the contract's
    /// <c>windowsRuntimeContains</c>.
    /// </summary>
    [Fact]
    public void TheWindowsRuntimeRecipesVendorVersionsAreTheContracts()
    {
        var doc = ContractLoader.LoadJson("toolchain.json");
        string recipe = File.ReadAllText(
            Path.Combine(RepoRoot, "windows-app", "Vendor", "fetch-runtime.ps1"));
        var vendorPins = new[] { "pagedjs", "latinModern", "functionPlot", "nodeTikzjax", "pyodide", "geogebra" };

        foreach (string name in vendorPins)
        {
            var pin = doc["pins"]!.AsArray().First(p => p?["pin"]?.ToString() == name)!;
            string contains = pin["windowsRuntimeContains"]!.ToString();
            string variable = "$" + char.ToUpperInvariant(name[0]) + name[1..] + "Version";
            var match = System.Text.RegularExpressions.Regex.Match(recipe,
                System.Text.RegularExpressions.Regex.Escape(variable) + @"\s*=\s*""([^""]*)""");
            Assert.True(match.Success, $"fetch-runtime.ps1 no longer sets {variable}.");
            // The version is the one inside the contract's
            // windowsRuntimeContains (latinModern's `value` is the apt
            // package's NAME, fonts-lmodern; its version lives only there).
            string version = match.Groups[1].Value;
            Assert.True(version.Length > 0 && contains.Contains(version, StringComparison.Ordinal),
                $"fetch-runtime.ps1 sets {variable} = \"{version}\", but the contract's windowsRuntimeContains " +
                $"for {name} is \"{contains}\": the two name different versions.");
        }
    }

    /// <summary>
    /// #568: Pyodide is the one vendor pin whose contract carries the
    /// tarball's hash AND the hash of every file kept from it, and the recipe
    /// checks both, as the Dockerfile does. A contract bump that changed the
    /// hashes without the recipe would otherwise fetch the old bytes and
    /// refuse them only on a build PC, at release time. (nodeTikzjax's sha256
    /// is for the record: npm ci verifies its lockfile's integrity itself.)
    /// </summary>
    [Fact]
    public void TheWindowsRuntimeRecipeChecksPyodidesContractHashes()
    {
        var doc = ContractLoader.LoadJson("toolchain.json");
        string recipe = File.ReadAllText(
            Path.Combine(RepoRoot, "windows-app", "Vendor", "fetch-runtime.ps1"));
        var pin = doc["pins"]!.AsArray().First(p => p?["pin"]?.ToString() == "pyodide")!;

        string tarball = pin["sha256"]!.ToString();
        Assert.True(recipe.Contains($"\"{tarball}\"", StringComparison.Ordinal),
            $"fetch-runtime.ps1 does not check the Pyodide tarball against the contract's sha256 {tarball}.");
        // The tarball's LENGTH lives only in the pin's `why` prose ("the core
        // tarball (6,757,104 bytes, `sha256`)"), so it is read from there.
        var stated = System.Text.RegularExpressions.Regex.Match(pin["why"]!.ToString(),
            @"core tarball \(([0-9,]+) bytes");
        Assert.True(stated.Success, "toolchain.json's pyodide `why` no longer states the tarball's length.");
        long length = long.Parse(stated.Groups[1].Value.Replace(",", ""), System.Globalization.CultureInfo.InvariantCulture);
        Assert.True(System.Text.RegularExpressions.Regex.IsMatch(recipe, @"\$PyodideTarLength\s*=\s*" + length + @"\b"),
            $"fetch-runtime.ps1's $PyodideTarLength is not the {length} bytes the contract states.");
        var files = pin["files"]!.AsObject();
        Assert.Equal(5, files.Count);
        foreach (var (name, digest) in files)
        {
            var line = System.Text.RegularExpressions.Regex.Match(recipe,
                "\"" + System.Text.RegularExpressions.Regex.Escape(name) + @"""\s*=\s*""([0-9a-f]{64})""");
            Assert.True(line.Success, $"fetch-runtime.ps1 keeps no hash for Pyodide's {name}.");
            Assert.Equal(digest!.ToString(), line.Groups[1].Value);
        }
    }

    /// <summary>
    /// #568: the runtime on THIS machine, read back. Skipped (and reported
    /// so) only where there is no runtime at all; a runtime whose manifest
    /// predates Pyodide FAILS, because the app's build refuses it too
    /// (Plantoir.csproj → CheckNativeRuntimeManifest), and one that names
    /// Pyodide must hold the five files at the contract's hashes and the
    /// Dockerfile's README line, or a teacher's site would carry other bytes
    /// than every Mac's.
    /// </summary>
    [NativeRuntimeFact]
    public void TheNativeRuntimeCarriesPyodideAtTheContractsHashes()
    {
        string runtime = NativeRuntime.Folder!;
        var manifest = JsonNode.Parse(File.ReadAllText(Path.Combine(runtime, "manifest.json")))!.AsObject();
        var pin = ContractLoader.LoadJson("toolchain.json")["pins"]!.AsArray()
            .First(p => p?["pin"]?.ToString() == "pyodide")!;
        string version = pin["value"]!.ToString();

        Assert.True(manifest.ContainsKey("pyodide"),
            $"{runtime}\\manifest.json has no \"pyodide\": this runtime predates #568. Re-run " +
            "windows-app\\Vendor\\fetch-runtime.ps1 (it fetches only runtime\\vendor).");
        Assert.Equal(version, manifest["pyodide"]!.ToString());

        string folder = Path.Combine(runtime, "vendor", "pyodide");
        var expected = pin["files"]!.AsObject().Select(f => f.Key).Append("README.txt").OrderBy(n => n, StringComparer.Ordinal);
        var present = Directory.GetFiles(folder).Select(Path.GetFileName).OrderBy(n => n, StringComparer.Ordinal);
        Assert.Equal(expected, present);
        foreach (var (name, digest) in pin["files"]!.AsObject())
        {
            using var stream = File.OpenRead(Path.Combine(folder, name));
            string got = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(stream)).ToLowerInvariant();
            Assert.True(got == digest!.ToString(), $"runtime\\vendor\\pyodide\\{name}: SHA-256 {got}, the contract's is {digest}.");
        }
        Assert.Equal(
            $"Pyodide {version} (MPL-2.0). Source: https://github.com/pyodide/pyodide/tree/{version}\n",
            File.ReadAllText(Path.Combine(folder, "README.txt")));
    }

    /// <summary>
    /// #687: GeoGebra is the vendor pin with TWO addresses (GeoGebra's own
    /// host, which timed out on 4 of 8 connections, then plantoir.app's
    /// mirror of the same zip) and one hash for whichever answered. The
    /// recipe must carry both addresses in full, the contract's zip hash and
    /// size, and run the shared adapter whose own VERSION is the pin's, as
    /// the Dockerfile tests with <c>geogebra_engine.py version</c>.
    /// </summary>
    [Fact]
    public void TheWindowsRuntimeRecipeFetchesGeoGebraAtTheContractsHashAndAddresses()
    {
        var doc = ContractLoader.LoadJson("toolchain.json");
        string recipe = File.ReadAllText(
            Path.Combine(RepoRoot, "windows-app", "Vendor", "fetch-runtime.ps1"));
        var pin = doc["pins"]!.AsArray().First(p => p?["pin"]?.ToString() == "geogebra")!;

        string zip = pin["sha256"]!.ToString();
        Assert.True(recipe.Contains($"\"{zip}\"", StringComparison.Ordinal),
            $"fetch-runtime.ps1 does not check GeoGebra's zip against the contract's sha256 {zip}.");
        var urls = pin["urls"]!.AsArray().Select(u => u!.ToString()).ToList();
        Assert.Equal(2, urls.Count);
        foreach (string url in urls)
            Assert.True(recipe.Contains($"\"{url}\"", StringComparison.Ordinal),
                $"fetch-runtime.ps1 does not write out {url} in full.");
        // GeoGebra's own host is tried first, the mirror second.
        Assert.True(recipe.IndexOf(urls[0], StringComparison.Ordinal) < recipe.IndexOf(urls[1], StringComparison.Ordinal),
            "fetch-runtime.ps1 names plantoir.app's mirror before GeoGebra's own address.");

        // The zip's LENGTH lives only in the pin's `why` prose.
        var stated = System.Text.RegularExpressions.Regex.Match(pin["why"]!.ToString(),
            @"the zip `sha256`, ([0-9,]+) bytes");
        Assert.True(stated.Success, "toolchain.json's geogebra `why` no longer states the zip's length.");
        long length = long.Parse(stated.Groups[1].Value.Replace(",", ""), System.Globalization.CultureInfo.InvariantCulture);
        Assert.True(System.Text.RegularExpressions.Regex.IsMatch(recipe, @"\$GeogebraZipLength\s*=\s*" + length + @"\b"),
            $"fetch-runtime.ps1's $GeogebraZipLength is not the {length} bytes the contract states.");

        // The ONE recipe: the shared adapter, never a PowerShell copy of it.
        Assert.Contains(@"scripts\geogebra_engine.py", recipe);
        Assert.Contains("$ggbRecipe adapt", recipe);
        string adapter = File.ReadAllText(Path.Combine(RepoRoot, "scripts", "geogebra_engine.py"));
        var version = System.Text.RegularExpressions.Regex.Match(adapter, @"(?m)^VERSION = ""([^""]+)""");
        Assert.True(version.Success, "scripts/geogebra_engine.py no longer sets VERSION.");
        Assert.Equal(pin["value"]!.ToString(), version.Groups[1].Value);
        var adapterZip = System.Text.RegularExpressions.Regex.Match(adapter, @"(?m)^ZIP_SHA256 = ""([0-9a-f]{64})""");
        Assert.True(adapterZip.Success, "scripts/geogebra_engine.py no longer sets ZIP_SHA256.");
        Assert.Equal(zip, adapterZip.Groups[1].Value);
    }

    /// <summary>
    /// #687: the runtime on THIS machine, read back, as Pyodide's is above. A
    /// runtime that names GeoGebra must hold exactly <c>fileCount</c> files,
    /// <c>bytes</c> in all, and the pin's <c>files</c> at their hashes - the
    /// bytes every Mac's image carries, since both run the same adapter.
    /// </summary>
    [NativeRuntimeFact]
    public void TheNativeRuntimeCarriesGeoGebraAtTheContractsHashes()
    {
        string runtime = NativeRuntime.Folder!;
        var manifest = JsonNode.Parse(File.ReadAllText(Path.Combine(runtime, "manifest.json")))!.AsObject();
        var pin = ContractLoader.LoadJson("toolchain.json")["pins"]!.AsArray()
            .First(p => p?["pin"]?.ToString() == "geogebra")!;

        Assert.True(manifest.ContainsKey("geogebra"),
            $"{runtime}\\manifest.json has no \"geogebra\": this runtime predates #687. Re-run " +
            "windows-app\\Vendor\\fetch-runtime.ps1 (it fetches only runtime\\vendor).");
        Assert.Equal(pin["value"]!.ToString(), manifest["geogebra"]!.ToString());

        string folder = Path.Combine(runtime, "vendor", "geogebra");
        var files = Directory.GetFiles(folder, "*", SearchOption.AllDirectories);
        Assert.Equal(pin["fileCount"]!.GetValue<int>(), files.Length);
        Assert.Equal(pin["bytes"]!.GetValue<long>(), files.Sum(f => new FileInfo(f).Length));
        foreach (var (name, digest) in pin["files"]!.AsObject())
        {
            string path = Path.Combine(new[] { folder }.Concat(name.Split('/')).ToArray());
            using var stream = File.OpenRead(path);
            string got = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(stream)).ToLowerInvariant();
            Assert.True(got == digest!.ToString(), $"runtime\\vendor\\geogebra\\{name}: SHA-256 {got}, the contract's is {digest}.");
        }
    }

    /// <summary>
    /// #675, #687: what the app's build refuses. CheckNativeRuntimeManifest
    /// names every vendor key (GeoGebra's included) and the Node the runtime
    /// must carry, and that Node is the contract's: a pin bump that forgot the
    /// project file would let a release ship the old Node silently.
    /// </summary>
    [Fact]
    public void TheBuildRefusesARuntimeWithoutGeoGebraOrOnAnotherNode()
    {
        string project = File.ReadAllText(Path.Combine(RepoRoot, "windows-app", "Plantoir", "Plantoir.csproj"));
        var pins = ContractLoader.LoadJson("toolchain.json")["pins"]!.AsArray();
        string node = pins.First(p => p?["pin"]?.ToString() == "node")!["value"]!.ToString();
        Assert.Contains($"<_PlantoirRuntimeNode>{node}</_PlantoirRuntimeNode>", project);
        Assert.Contains("_PlantoirRuntimeManifest.Contains('&quot;geogebra&quot;')", project);
    }

    /// <summary>
    /// #687: the first binary in any payload. <c>Plantoir.csproj</c> takes all
    /// of <c>support\**</c> as content; this proves the .ggb is INCLUDED -
    /// nothing excludes it, it is the bytes the payload holds, and git treats
    /// it as binary so no line-ending rule can touch it. (It reads the
    /// project as text, as the other bundle tests do: the test project does
    /// not reference the app, so the installer's output is not in reach.)
    /// </summary>
    [Fact]
    public void TheBundleIncludesTheSlopeAngleSketchAsTheFileThePayloadHolds()
    {
        string project = File.ReadAllText(Path.Combine(RepoRoot, "windows-app", "Plantoir", "Plantoir.csproj"));
        var support = System.Text.RegularExpressions.Regex.Match(project,
            @"<Content Include=""\.\.\\\.\.\\support\\\*\*""([^>]*)/>");
        Assert.True(support.Success, "Plantoir.csproj no longer takes support\\** as content.");
        Assert.DoesNotContain("Exclude", support.Groups[1].Value);
        Assert.Contains(@"Link=""Toolchain\support\%(RecursiveDir)%(Filename)%(Extension)""", support.Groups[1].Value);

        string sketch = Path.Combine(RepoRoot, "support", "example_content", "MPM2D", "shared", "Explorations", "Slope Angle Conjecture.ggb");
        Assert.True(File.Exists(sketch), $"{sketch} is missing.");
        byte[] bytes = File.ReadAllBytes(sketch);
        Assert.Equal(1_594_544, bytes.Length);
        Assert.Equal("504b0304", Convert.ToHexString(bytes, 0, 4).ToLowerInvariant());
        Assert.Matches(new System.Text.RegularExpressions.Regex(@"(?m)^\*\.ggb\s+binary\s*$"),
            File.ReadAllText(Path.Combine(RepoRoot, ".gitattributes")));
    }

    /// <summary>
    /// The mac's <c>testTheImagesNodeSatisfiesWranglersEngines</c>, mirrored:
    /// the shared <c>node</c> pin - the image's Node and, since #675, the
    /// runtime's - must satisfy wrangler's own <c>engines.node</c>, or
    /// publishing to Cloudflare breaks with every site build still green.
    /// </summary>
    [Fact]
    public void TheRuntimesNodeSatisfiesWranglersEngines()
    {
        var pins = ContractLoader.LoadJson("toolchain.json")["pins"]!.AsArray();
        string node = pins.First(p => p?["pin"]?.ToString() == "node")!["value"]!.ToString();
        string? engine = pins.First(p => p?["pin"]?.ToString() == "wrangler")!["nodeEngine"]?.ToString();
        Assert.True(engine is not null,
            "The wrangler pin must say which Node its engines need (nodeEngine), as wrangler's own package.json does.");
        // Only the one shape wrangler has ever used is understood.
        Assert.True(engine!.StartsWith(">=", StringComparison.Ordinal),
            $"wrangler's nodeEngine is \"{engine}\"; this test understands only \">=X.Y.Z\".");
        var floor = Version.Parse(engine[2..]);
        var ours = Version.Parse(node);
        Assert.True(ours >= floor,
            $"The image and Windows' runtime run Node {node}, but wrangler's engines need {engine}: publishing to " +
            "Cloudflare would break. Raise Node, or keep wrangler at a version whose engines it satisfies.");
    }

    [Fact]
    public void Wrangler_StaysBelowVersionThatNeedsNode22()
    {
        var doc = ContractLoader.LoadJson("toolchain.json");
        var pins = doc["pins"]!.AsArray();
        var wrangler = pins.First(p => p?["pin"]?.ToString() == "wrangler")!;

        string pinned = wrangler["value"]!.ToString();
        string ceiling = wrangler["mustStayBelow"]!.ToString();

        var pinnedParts = pinned.Split('.').Select(int.Parse).ToList();
        var ceilingParts = ceiling.Split('.').Select(int.Parse).ToList();

        Assert.Equal(pinnedParts[0], ceilingParts[0]);
        Assert.True(pinnedParts[1] < ceilingParts[1],
            $"wrangler {pinned} is at or past {ceiling}, whose engines need Node 22. Both platforms run Node 22 " +
            "now (the image since #640, Windows' runtime since #675), so the ceiling no longer protects anything: " +
            "moving wrangler is its own piece, which re-checks nodeEngine and retires mustStayBelow on both " +
            "platforms. Raise the pin in that piece, not here.");
    }

    [Fact]
    public void Patches_AllExistAndAreAppliedInDockerfile()
    {
        var doc = ContractLoader.LoadJson("toolchain.json");
        string dockerfile = File.ReadAllText(Path.Combine(RepoRoot, "Dockerfile"));
        string patchesDir = Path.Combine(RepoRoot, "patches");

        var patches = doc["patches"]!.AsArray();
        var described = patches.Select(p => p!["file"]!.ToString()).ToHashSet();

        foreach (var patch in patches)
        {
            if (patch is null) continue;
            string file = patch["file"]!.ToString();
            string replaces = patch["replaces"]!.ToString();

            string patchFile = Path.Combine(patchesDir, file);
            Assert.True(File.Exists(patchFile), $"Patch file {file} described in toolchain.json does not exist.");
            Assert.True(dockerfile.Contains($"COPY patches/{file}") && dockerfile.Contains(replaces),
                $"Dockerfile does not copy {file} over {replaces}.");
        }

        foreach (var file in Directory.GetFiles(patchesDir))
        {
            string fileName = Path.GetFileName(file);
            Assert.Contains(fileName, described);
        }
    }
}

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
        var vendorPins = new[] { "pagedjs", "latinModern", "functionPlot", "nodeTikzjax", "pyodide" };

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
        var files = pin["files"]!.AsObject();
        Assert.Equal(5, files.Count);
        foreach (var (name, digest) in files)
        {
            var line = System.Text.RegularExpressions.Regex.Match(recipe,
                "\"" + System.Text.RegularExpressions.Regex.Escape(name) + "\"\s*=\s*\"([0-9a-f]{64})\"");
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
            $"{runtime}\manifest.json has no \"pyodide\": this runtime predates #568. Re-run " +
            "windows-app\Vendor\fetch-runtime.ps1 (it fetches only runtime\vendor).");
        Assert.Equal(version, manifest["pyodide"]!.ToString());

        string folder = Path.Combine(runtime, "vendor", "pyodide");
        var expected = pin["files"]!.AsObject().Select(f => f.Key).Append("README.txt").OrderBy(n => n, StringComparer.Ordinal);
        var present = Directory.GetFiles(folder).Select(Path.GetFileName).OrderBy(n => n, StringComparer.Ordinal);
        Assert.Equal(expected, present);
        foreach (var (name, digest) in pin["files"]!.AsObject())
        {
            using var stream = File.OpenRead(Path.Combine(folder, name));
            string got = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(stream)).ToLowerInvariant();
            Assert.True(got == digest!.ToString(), $"runtime\vendor\pyodide\{name}: SHA-256 {got}, the contract's is {digest}.");
        }
        Assert.Equal(
            $"Pyodide {version} (MPL-2.0). Source: https://github.com/pyodide/pyodide/tree/{version}\n",
            File.ReadAllText(Path.Combine(folder, "README.txt")));
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
            $"wrangler {pinned} must stay below {ceiling} because Node 20 is required by Quartz v4.5.0.");
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

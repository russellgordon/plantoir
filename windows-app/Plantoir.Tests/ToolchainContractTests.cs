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

        int checked_ = 0;
        foreach (var pin in doc["pins"]!.AsArray())
        {
            if (pin?["windowsRuntimeContains"]?.ToString() is not { } expected) continue;
            string name = pin["pin"]!.ToString();
            string value = pin["value"]!.ToString();
            string why = pin["why"]?.ToString() ?? "";

            Assert.True(expected.Contains(value, StringComparison.Ordinal),
                $"{name}: the contract watches fetch-runtime.ps1 for \"{expected}\", which does " +
                $"not carry the pinned version {value}. {why}");
            Assert.True(recipe.Contains(expected, StringComparison.Ordinal),
                $"{name}: windows-app/Vendor/fetch-runtime.ps1 does not pin {expected}. {why}");
            checked_++;
        }

        Assert.True(checked_ > 0,
            "No pin in contracts/toolchain.json names a windowsRuntimeContains any more. " +
            "The two fetch paths can drift again the moment nothing holds them together.");
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

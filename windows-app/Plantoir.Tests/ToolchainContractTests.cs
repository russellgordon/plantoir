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

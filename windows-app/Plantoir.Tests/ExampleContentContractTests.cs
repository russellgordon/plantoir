using System;
using System.IO;
using System.Linq;
using System.Text.Json.Nodes;
using Newtonsoft.Json.Linq;
using Xunit;

namespace Plantoir.Tests;

public class ExampleContentContractTests
{
    private static string RepoRoot
    {
        get
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            for (int i = 0; i < 8 && dir is not null; i++, dir = dir.Parent)
            {
                if (Directory.Exists(Path.Combine(dir.FullName, "support", "example_content")))
                    return dir.FullName;
            }
            throw new DirectoryNotFoundException("Could not find repository root containing support/example_content.");
        }
    }

    [Fact]
    public void EveryPayloadMatchesContract()
    {
        var doc = ContractLoader.LoadJson("example-content.json");
        string exampleContentDir = Path.Combine(RepoRoot, "support", "example_content");
        var requiredKeys = doc["manifestKeys"]!.AsArray()
            .Where(k => k?["required"]?.GetValue<bool>() == true)
            .Select(k => k!["key"]!.ToString())
            .ToList();

        var directories = Directory.GetDirectories(exampleContentDir)
            .Select(Path.GetFileName)
            .Where(name => !string.IsNullOrEmpty(name) && !name.StartsWith('.'))
            .OrderBy(n => n)
            .ToList();

        Assert.True(directories.Count >= 30, $"Expected >= 30 example content payloads, found {directories.Count}");

        foreach (string code in directories)
        {
            string payloadPath = Path.Combine(exampleContentDir, code);
            string manifestPath = Path.Combine(payloadPath, "manifest.json");

            Assert.True(File.Exists(manifestPath), $"Payload {code} is missing manifest.json.");

            var manifest = JObject.Parse(File.ReadAllText(manifestPath));
            foreach (string required in requiredKeys)
            {
                Assert.True(manifest.ContainsKey(required),
                    $"Payload {code}/manifest.json is missing required key '{required}'.");
            }

            Assert.True(Directory.Exists(Path.Combine(payloadPath, "shared")),
                $"Payload {code} is missing shared/ directory.");
            Assert.True(Directory.Exists(Path.Combine(payloadPath, "per_section")),
                $"Payload {code} is missing per_section/ directory.");

            if (manifest["curriculum_folder"]?.ToString() is { } curriculum && !string.IsNullOrEmpty(curriculum))
            {
                var sharedFolders = manifest["shared_folders"] is JArray arr
                    ? arr.Select(t => t.ToString()).ToList()
                    : new();
                Assert.True(sharedFolders.Contains(curriculum),
                    $"{code} names '{curriculum}' as curriculum folder but does not list it in shared_folders.");
            }
        }
    }
}

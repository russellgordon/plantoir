using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// The headless deploy (<c>plantoir-mcp</c>'s <c>deploy_section</c>, and
/// Plantoir's own assistant with no window to press in) and the Cloudflare
/// Account ID (#739). Until #739 it refused EVERY Cloudflare destination with
/// a sentence of its own, saved ID or not; with Cloudflare the default for
/// every new course, that left an outside assistant able to schedule a new
/// course's deploy but never to deploy it. Now it refuses exactly when the
/// window's Deploy does (<see cref="MultiDestinationDeployRunner.RefusalReason"/>,
/// <c>publishingDestinations.deployWithoutAnAccountID</c>), with the same
/// sentence, and otherwise hands the launcher the ID as the window does.
/// The launcher is a stub (<see cref="FakeLauncher"/>): nothing is built or
/// deployed, and the ID is a made-up one.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class HeadlessCloudflareDeployTests : IDisposable
{
    private const string Code = "SNC1W";
    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-headless-cf").FullName;
    private readonly string _published = Directory.CreateTempSubdirectory("plantoir-headless-cf-out").FullName;
    private readonly string _trail = Path.Combine(Path.GetTempPath(), "plantoir-tests",
        "headless-cf-" + Guid.NewGuid().ToString("N") + ".txt");
    private readonly FakeLauncher _launcher = new();

    public HeadlessCloudflareDeployTests()
    {
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        Directory.CreateDirectory(Path.GetDirectoryName(_trail)!);
        ActivityTrail.SetCustomLogPathForTesting(_trail);
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        AssistWorkspace.CloudflareAccountIdOverrideForTests = null;
        foreach (string path in new[] { _folder, _published })
            try { Directory.Delete(path, recursive: true); } catch { }
        try { File.Delete(_trail); } catch { }
    }

    private string Trail() => File.Exists(_trail) ? File.ReadAllText(_trail) : "";

    /// <summary>A one-section course deploying to <paramref name="types"/> in order, each deployed before (so the first-deploy question is not what is tested).</summary>
    private List<CourseConfiguration.DeployDestination> WriteCourse(IReadOnlyList<string> types, string folderPath)
    {
        string dir = Path.Combine(_folder, "courses", Code);
        Directory.CreateDirectory(Path.Combine(dir, "section1"));
        var config = new JsonObject
        {
            ["course_code"] = Code,
            ["course_name"] = "Science",
            ["deploy_target"] = types[0],
            ["num_sections"] = 1,
            ["per_section_folders"] = new JsonArray("All Classes"),
            ["per_section_files"] = new JsonArray(),
            ["section_numbers"] = new JsonArray(1),
        };
        if (types[0] == "local_folder") config["deploy_folder_path"] = folderPath;
        var additional = new JsonArray();
        foreach (string type in types.Skip(1))
        {
            var entry = new JsonObject { ["type"] = type };
            if (type == "local_folder") entry["path"] = folderPath;
            additional.Add(entry);
        }
        if (additional.Count > 0) config["additional_deploy_targets"] = additional;
        File.WriteAllText(Path.Combine(dir, "course_config.json"), config.ToJsonString());
        foreach (string marker in new[] { ".cloudflare_sites", ".netlify_sites" })
        {
            Directory.CreateDirectory(Path.Combine(dir, marker));
            File.WriteAllText(Path.Combine(dir, marker, "section1.json"), """{"name": "snc1w-s1"}""");
        }
        return types.Select(type => new CourseConfiguration.DeployDestination(type, type == "local_folder" ? folderPath : "")).ToList();
    }

    /// <summary>
    /// Every <c>deployWithoutAnAccountID</c> case through the headless deploy:
    /// a case the window refuses is refused here with the SAME sentence, before
    /// any launcher runs; one it lets through is deployed, every leg handed
    /// what the window's Deploy hands it (<see cref="MultiDestinationDeployRunner"/>'s
    /// <c>DeployCommand.Arguments(…, cloudflareAccountID)</c>) plus only the
    /// <c>--non-interactive</c> nobody-is-here flag. No trail line on this
    /// path, either way: the contract's event names a window that was open,
    /// and says in its <c>why</c> that this path writes none, as the mac's does.
    /// </summary>
    [Fact]
    public async Task EveryCaseRefusesAsTheWindowDoesOrDeploysWithTheIdTheWindowWouldPass()
    {
        var cases = ContractLoader.LoadJson("app-rules.json")["publishingDestinations"]!
            ["deployWithoutAnAccountID"]!["cases"]!.AsArray();
        Assert.NotEmpty(cases);
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            string id = c["accountID"]!.ToString();
            var types = c["destinations"]!.AsArray().Select(t => t!.ToString()).ToList();
            // The contract's folder case is a folder NOT chosen; that is what it tests.
            var destinations = WriteCourse(types, folderPath: "");
            _launcher.Runs.Clear();
            File.WriteAllText(_trail, "");
            AssistWorkspace.CloudflareAccountIdOverrideForTests = () => id;
            var workspace = new AssistWorkspace(_folder, _launcher);
            string? expectStart = c["expectRefusalStartsWith"]?.ToString();

            if (expectStart is not null)
            {
                var refusal = await Assert.ThrowsAsync<AssistRefusal>(() => workspace.Deploy(Code, 1));
                Assert.True(refusal.Message.StartsWith(expectStart, StringComparison.Ordinal),
                            $"{name}: expected a refusal starting \"{expectStart}\", got \"{refusal.Message}\"");
                Assert.Equal(MultiDestinationDeployRunner.RefusalReason(destinations, id), refusal.Message);
                Assert.True(_launcher.Runs.Count == 0, $"{name}: a launcher ran before the refusal");
            }
            else
            {
                var result = await workspace.Deploy(Code, 1);
                Assert.True(result.Succeeded, $"{name}: {result.Message}");
                var deploys = _launcher.Runs.Where(run => run.Launcher == "deploy").ToList();
                Assert.Equal(destinations.Count, deploys.Count);
                for (int leg = 0; leg < destinations.Count; leg++)
                {
                    var window = DeployCommand.Arguments(Code, 1, destinations[leg], id.Trim());
                    var headless = deploys[leg].Arguments.Where(a => a != "--non-interactive").ToList();
                    Assert.Equal(window, headless);
                }
            }
            Assert.DoesNotContain("deploy refused: ", Trail());
            if (id.Trim().Length > 0) Assert.DoesNotContain(id.Trim(), Trail());
        }
    }

    /// <summary>A folder that IS chosen beside Cloudflare, with the ID saved: both legs go, the ID on the Cloudflare one only.</summary>
    [Fact]
    public async Task AChosenFolderBesideCloudflareDeploysBothLegs()
    {
        const string fakeId = "0123456789abcdef0123456789abcdef";
        WriteCourse(new[] { "local_folder", "cloudflare_pages" }, _published);
        AssistWorkspace.CloudflareAccountIdOverrideForTests = () => fakeId;

        var result = await new AssistWorkspace(_folder, _launcher).Deploy(Code, 1);

        Assert.True(result.Succeeded, result.Message);
        var deploys = _launcher.Runs.Where(run => run.Launcher == "deploy").ToList();
        Assert.Equal(2, deploys.Count);
        Assert.Contains("--to-folder", deploys[0].Arguments);
        Assert.DoesNotContain(fakeId, deploys[0].Arguments);
        Assert.Equal(new[] { "--target", "cloudflare", "--account", fakeId }, deploys[1].Arguments[^4..]);
    }

    /// <summary>The old sentence is gone: nothing on this path sends a Cloudflare section back to Plantoir any more.</summary>
    [Fact]
    public async Task NoCloudflareSectionIsSentBackToPlantoirWithTheOldSentence()
    {
        WriteCourse(new[] { "cloudflare_pages" }, "");
        AssistWorkspace.CloudflareAccountIdOverrideForTests = () => "";
        var refusal = await Assert.ThrowsAsync<AssistRefusal>(() => new AssistWorkspace(_folder, _launcher).Deploy(Code, 1));
        Assert.DoesNotContain("the account ID Plantoir stores", refusal.Message);
        Assert.StartsWith(CourseConfiguration.CloudflareAccountProblem("")!, refusal.Message);
    }
}

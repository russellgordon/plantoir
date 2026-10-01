using System;
using System.Linq;
using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #386 (mac #381): a preview of a section cannot start while that same
/// section is being deployed. The launcher layer is
/// <see cref="LauncherRulesContractTests"/>; this is the window's and the
/// assistant's, plus the wording and the panel's explanation, against
/// <c>shared-rules.json → previewWhileItsSectionDeploys</c> and
/// <c>assist-wording.json</c>.
/// </summary>
[Collection(SharedActivityState.Name)]
public class PreviewWhileDeployingTests : IDisposable
{
    private const string Folder = @"C:\Users\t\Plantoir Here";

    public PreviewWhileDeployingTests() => CourseActivity.Reset();
    public void Dispose() => CourseActivity.Reset();

    private static JsonNode Rule => ContractLoader.LoadJson("shared-rules.json")["previewWhileItsSectionDeploys"]!;
    private static JsonObject Wording => ContractLoader.LoadJson("assist-wording.json")["wording"]!.AsObject();

    /// <summary>
    /// The window-layer cases, through the one question every way into a
    /// preview asks first. On Windows the in-app assistant's windowless deploy
    /// runs in plantoir-mcp.exe, ANOTHER process, so it is the lease layer's
    /// (#289) to refuse, not this in-process record's — skipped here by name.
    /// </summary>
    [Fact]
    public void TheWindowAsksThisAppsOwnPublishRecordForTheSection()
    {
        int ran = 0;
        foreach (var c in Rule["cases"]!.AsArray().Where(c => c!["layer"]!.ToString() == "window"))
        {
            string deployer = c!["deployer"]!.ToString();
            if (deployer == "inAppAssistant") continue;   // another process on Windows: the lease layer
            CourseActivity.Reset();
            int deploying = c["section"]!.ToString() == "same" ? 2 : 3;
            using var publish = CourseActivity.BeginPublish(Folder, "ICS4U", deploying);
            bool refused = CourseActivity.IsPublishingSection(Folder, "ICS4U", 2);
            Assert.True(refused == (c["expect"]!.ToString() == "refused"), c["name"]!.ToString());
            ran++;
        }
        Assert.True(ran >= 2, "the contract lost its window cases");
    }

    private sealed class NoModel : IChatModel
    {
        public System.Threading.Tasks.Task<ModelReply?> Ask(JsonArray messages, JsonArray tools,
                                                            System.Threading.CancellationToken cancellation) =>
            System.Threading.Tasks.Task.FromResult<ModelReply?>(null);
    }

    private sealed class NoTools : IToolServer
    {
        public int Calls;
        public System.Threading.Tasks.Task<AssistToolAnswer> CallTool(string name, JsonObject arguments,
            Action<string>? progress = null, System.Threading.CancellationToken cancellation = default)
        {
            Calls++;
            throw new InvalidOperationException("no tool should run while the section is being deployed");
        }
    }

    /// <summary>
    /// The contract's layer-<c>assistant</c> case: the in-app assistant asks
    /// the same publish record FIRST, and says so, rather than telling the
    /// teacher the preview is on its way while the window refuses it.
    /// </summary>
    [Theory]
    [InlineData("preview")]
    [InlineData("rebuild the preview")]
    public async System.Threading.Tasks.Task TheAssistantAsksBeforeOpeningAPreview(string said)
    {
        var assistantCase = Rule["cases"]!.AsArray().Single(c => c!["layer"]!.ToString() == "assistant")!;
        Assert.Equal("refused", assistantCase["expect"]!.ToString());
        int opened = 0;
        var tools = new NoTools();
        var agent = new AssistAgent(new NoModel(), tools, new JsonArray(), "ICS4U", 2)
        {
            ShowPreviewInApp = () => opened++,
            SectionIsBeingDeployed = () => true,
        };
        var lines = await agent.Say(said, System.Threading.CancellationToken.None);
        Assert.Equal(0, opened);
        Assert.Equal(0, tools.Calls);
        Assert.Contains(lines, line => line.Text == AssistWording.SectionIsBeingDeployed("ICS4U", "2"));
    }

    [Fact]
    public void ThePublishRecordEndsWithTheDeploy()
    {
        var publish = CourseActivity.BeginPublish(Folder, "ICS4U", 2);
        Assert.True(CourseActivity.IsPublishingSection(Folder, "ICS4U", 2));
        publish.Dispose();
        Assert.False(CourseActivity.IsPublishingSection(Folder, "ICS4U", 2));
    }

    [Fact]
    public void TheSentencesAreTheContracts()
    {
        Assert.Equal(Wording["sectionIsBeingDeployed"]!.ToString(), AssistWording.SectionIsBeingDeployed("{course}", "{section}"));
        Assert.Equal(Wording["deployNeedsAnAnswer"]!.ToString(), AssistWording.DeployNeedsAnAnswer("{course}", "{section}"));
        Assert.Equal(Wording["deployNeedsAnAnswerAt"]!.ToString(),
                     AssistWording.DeployNeedsAnAnswerAt("{course}", "{section}", "{destinations}"));
        Assert.Equal(Wording["deployWentOutTo"]!.ToString(), AssistWording.DeployWentOutTo("{destinations}"));
        Assert.Equal(Wording["previewBuildNeedsAnAnswer"]!.ToString(), AssistWording.PreviewBuildNeedsAnAnswer("{course}", "{section}"));
        Assert.Equal("Cannot Preview Yet", Rule["sentences"]!["windowTitle"]!.ToString());
    }

    [Fact]
    public void ThePanelLiftsTheLaunchersFirstLine()
    {
        foreach (var c in Rule["failureExplanationCases"]!.AsArray())
            Assert.Equal(c!["expect"]!.ToString(), FailureExplainer.Explanation(c["output"]!.ToString()));
    }

    [Fact]
    public void TheLaunchersSentenceIsTheContracts()
    {
        // preview.ps1 builds the first line from a format and a code point
        // (no BOM, so no non-ASCII in its strings); the words are pinned here.
        string source = System.IO.File.ReadAllText(System.IO.Path.Combine(ContractLoader.RepositoryRoot, "preview.ps1"));
        var lines = Rule["sentences"]!["launcher"]!.AsArray().Select(l => l!.ToString()).ToList();
        string first = lines[0].Replace("\u274C ", "").Replace("{course}", "{1}").Replace("{section}", "{2}");
        Assert.Contains("\"{0} " + first + "\"", source);
        Assert.Contains("Write-Host \"" + lines[1] + "\"", source);
    }
}

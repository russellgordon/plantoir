using System;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Net.Sockets;
using System.Text.Json.Nodes;
using System.Threading.Tasks;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #278 (mac #235): the announced address is read a whole line at a time, and
/// #233 (mac #225): the wait bounds the QUIET after the server line and gives
/// up honestly. Both against <c>app-rules.json → previewPorts</c> and the mac's
/// real first-build capture (<c>mac-app/Tests/Goldens/235-preview-first-build.json</c>,
/// read as data).
/// </summary>
[Collection(SharedActivityState.Name)]
public class PreviewAppearanceTests
{
    private static JsonNode PreviewPorts => ContractLoader.LoadJson("app-rules.json")["previewPorts"]!;

    private static JsonNode Golden => JsonNode.Parse(File.ReadAllText(Path.Combine(
        ContractLoader.RepositoryRoot, "mac-app", "Tests", "Goldens", "235-preview-first-build.json")))!;

    // MARK: - #278: the address

    [Fact]
    public void TheContractsMarkerIsTheOneRead() =>
        Assert.Equal(PreviewPorts["announcedAddress"]!["marker"]!.ToString(), OutputParsers.PreviewAnnouncementMarker);

    [Theory]
    [InlineData(7)]
    [InlineData(256)]
    [InlineData(1024)]
    public void TheRealFirstBuildGivesTheWholeAddressHoweverItIsCut(int pieceLength)
    {
        string output = Golden["output"]!.ToString();
        string expected = Golden["announcedAddress"]!.ToString();
        var runner = new ScriptRunner(uiContext: null);
        for (int at = 0; at < output.Length; at += pieceLength)
            runner.ReceiveOutput(output.Substring(at, Math.Min(pieceLength, output.Length - at)));
        Assert.Equal(expected, runner.PreviewAddress?.ToString());
    }

    /// <summary>
    /// Every cut point of the announcement line, two pieces each: chunk-wise
    /// parsing with nothing carried over gave a WRONG port at three of them
    /// (after ":8", ":81", ":810"), measured on the mac.
    /// </summary>
    [Theory]
    [InlineData("Preview will be available at: http://localhost:8101/\r\n")]
    [InlineData("Preview will be available at: \u001b[1mhttp://localhost:8101/\u001b[0m\r\n")]
    public void EveryCutOfTheAnnouncementGivesTheRightAddressOrNoneYet(string line)
    {
        for (int cut = 1; cut < line.Length; cut++)
        {
            var runner = new ScriptRunner(uiContext: null);
            runner.ReceiveOutput(line[..cut]);
            // Before the line's end has arrived: nothing yet, never a wrong port.
            if (cut <= line.IndexOf("\r", StringComparison.Ordinal)) Assert.Null(runner.PreviewAddress);
            runner.ReceiveOutput(line[cut..]);
            Assert.Equal("http://127.0.0.1:8101/", runner.PreviewAddress?.ToString());
        }
    }

    [Fact]
    public void NothingIsReadBackOffTheEndOfTheOutput()
    {
        // A transcript holding an announcement the runner never RECEIVED as a
        // line (only possible through the old tail fallback) gives nothing.
        var runner = new ScriptRunner(uiContext: null);
        runner.ReceiveOutput("Building...\n");
        Assert.Null(runner.PreviewAddress);
    }

    // MARK: - #233: the wait

    private static readonly DateTime T0 = new(2026, 9, 30, 12, 0, 0, DateTimeKind.Utc);
    private static readonly Uri Address = new("http://127.0.0.1:8101/");

    [Fact]
    public void TheNumbersAreTheContracts()
    {
        var never = PreviewPorts["whenThePreviewNeverAppears"]!;
        Assert.Equal(never["secondsOfSilenceAllowed"]!.GetValue<int>(), PreviewReachability.SecondsOfSilenceAllowed);
        Assert.Equal(never["theClockStartsAt"]!.ToString(), PreviewReachability.ServerStartedLine);
        Assert.Equal(never["alertTitle"]!.ToString(), PreviewReachability.AlertTitle);
        var noAddress = never["whenNoAddressWasAnnounced"]!;
        Assert.Equal(noAddress["stopsWhen"]!.ToString(), PreviewReachability.ServerStartedLine);
        Assert.Equal("plantoirCouldNotTell", noAddress["verdict"]!.ToString());
    }

    [Fact]
    public void TheRunIsNeverBoundedOnlyTheQuietAfterTheServerLine()
    {
        // Twenty minutes into a first build, still printing, no server line yet.
        Assert.Equal(PreviewReachability.Step.KeepWaiting,
            PreviewReachability.NextStep(false, null, null, T0.AddMinutes(20), T0.AddMinutes(20)));
        Assert.Equal(PreviewReachability.Step.TryTheAddress,
            PreviewReachability.NextStep(false, Address, null, T0, T0.AddMinutes(20)));
        // Server line, then 44 s of quiet: still trying. 45: give up.
        Assert.Equal(PreviewReachability.Step.TryTheAddress,
            PreviewReachability.NextStep(false, Address, T0, T0, T0.AddSeconds(44)));
        Assert.Equal(PreviewReachability.Step.GiveUpSilence,
            PreviewReachability.NextStep(false, Address, T0, T0, T0.AddSeconds(45)));
        // Output after the server line restarts the clock.
        Assert.Equal(PreviewReachability.Step.TryTheAddress,
            PreviewReachability.NextStep(false, Address, T0, T0.AddSeconds(30), T0.AddSeconds(70)));
    }

    [Fact]
    public void AServerWithNoAddressStopsAtOnceAndNothingIsGuessed() =>
        Assert.Equal(PreviewReachability.Step.GiveUpNoAddress,
            PreviewReachability.NextStep(false, null, T0, T0, T0));

    [Fact]
    public void APreviewTheTeacherStoppedIsLeftWithoutAWord()
    {
        Assert.Equal(PreviewReachability.Step.LeaveIt,
            PreviewReachability.NextStep(true, null, T0, T0, T0.AddMinutes(5)));
        Assert.Equal(PreviewReachability.Step.LeaveIt,
            PreviewReachability.NextStep(true, Address, T0, T0, T0.AddMinutes(5)));
    }

    [Fact]
    public void OnlyARefusalFromThisPcIsAnAnswer()
    {
        var refused = new HttpRequestException("refused", new SocketException((int)SocketError.ConnectionRefused));
        Assert.Equal(PreviewReachability.Verdict.TheSiteNeverAnswered, PreviewReachability.VerdictFrom(refused));
        Assert.Equal(PreviewReachability.Verdict.PlantoirCouldNotTell,
            PreviewReachability.VerdictFrom(new TaskCanceledException("timed out")));
        Assert.Equal(PreviewReachability.Verdict.PlantoirCouldNotTell, PreviewReachability.VerdictFrom(null));
    }

    /// <summary>
    /// The sentences are the contract's, with its one platform word said the
    /// Windows way (the specialNames.platformWording convention) — proposed to
    /// the mac rather than reworded silently.
    /// </summary>
    [Fact]
    public void TheSentencesAreTheContractsSaidOnThisPc()
    {
        var cases = PreviewPorts["whenThePreviewNeverAppears"]!["cases"]!.AsArray();
        string SentenceFor(string verdict) => cases.First(c => c!["verdict"]!.ToString() == verdict)!["sentence"]!.ToString()
            .Replace("your Mac", "your PC");
        Assert.Equal(SentenceFor("theSiteNeverAnswered"), PreviewReachability.Sentence(PreviewReachability.Verdict.TheSiteNeverAnswered));
        Assert.Equal(SentenceFor("plantoirCouldNotTell"), PreviewReachability.Sentence(PreviewReachability.Verdict.PlantoirCouldNotTell));
        foreach (var verdict in Enum.GetValues<PreviewReachability.Verdict>())
            Assert.DoesNotContain("Mac", PreviewReachability.Sentence(verdict));
    }

    // MARK: - #395 and the one machine-line rule

    [Fact]
    public void TheCloudflareMarkersExamplesAreRead()
    {
        var marker = ContractLoader.LoadJson("shared-rules.json")["activityTrail"]!["mustRecord"]!.AsArray()
            .First(e => e!["event"]!.ToString() == "cloudflare project made again")!["marker"]!;
        var examples = marker["examples"]!.AsArray().Select(e => e!.ToString()).ToList();
        var first = CloudflareProjectRemade.Parse(examples[0])!;
        Assert.Equal(("ICS4U", 1, "ics4u-s1-2026-gordon", "ics4u-s1-2026-gordon.pages.dev"),
                     (first.Course, first.Section, first.Project, first.Address));
        var spaced = CloudflareProjectRemade.Parse(examples[1])!;
        Assert.Equal("AP CALC", spaced.Course);
        Assert.Equal(2, spaced.Section);
    }

    [Theory]
    [InlineData("PLANTOIR_CLOUDFLARE_REMADE: ICS4U/1 ics4u-s1 C:\\Users\\pat\\site")]
    [InlineData("PLANTOIR_CLOUDFLARE_REMADE: ICS4U/1 ics4u-s1 ics4u-s1.pages.dev/path")]
    [InlineData("PLANTOIR_CLOUDFLARE_REMADE: ICS4U/1 ics4u-s1")]
    [InlineData("PLANTOIR_CLOUDFLARE_REMADE: ICS4U/1 ics4u-s1 ics4u-s1.pages.dev and more words")]
    [InlineData("PLANTOIR_CLOUDFLARE_REMADE: setup ics4u-s1 ics4u-s1.pages.dev")]
    [InlineData("PLANTOIR_CLOUDFLARE_REMADE: ICS4U/1 ics4u.s1 ics4u-s1.pages.dev")]
    [InlineData("the Cloudflare project was made again")]
    public void AnythingNotOfTheMarkersShapeRecordsNothing(string line) =>
        Assert.Null(CloudflareProjectRemade.Parse(line));

    [Fact]
    public void ARunThatRemadeTheProjectLeavesTheTrailLine()
    {
        string trail = Path.Combine(Path.GetTempPath(), "cf-remade-" + Guid.NewGuid().ToString("N") + ".txt");
        ActivityTrail.SetCustomLogPathForTesting(trail);
        try
        {
            var runner = new ScriptRunner(uiContext: null);
            runner.ReceiveOutput("Made the project again.\nPLANTOIR_CLOUDFLARE_REMADE: AP+CALC/2 ap-calc-s2 ap-calc-s2-7x2.pages.dev\n");
            string written = File.ReadAllText(trail);
            Assert.Contains("AP CALC/2 · the Cloudflare project ap-calc-s2 was not in this Cloudflare account, so it was made again; the website is now at ap-calc-s2-7x2.pages.dev", written);
            Assert.DoesNotContain("PLANTOIR_", runner.Transcript.DisplayText);
        }
        finally
        {
            ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
            try { File.Delete(trail); } catch { }
        }
    }

    [Fact]
    public void EveryMachineLineCaseIsHiddenAsTheContractSays()
    {
        var cases = ContractLoader.LoadJson("shared-rules.json")["transcriptStripping"]!["machineLines"]!["cases"]!.AsArray();
        Assert.NotEmpty(cases);
        foreach (var c in cases)
        {
            string line = c!["line"]!.ToString();
            bool hidden = c["hidden"]!.GetValue<bool>();
            var transcript = new TranscriptBuilder();
            transcript.Append(line + "\n");
            Assert.True(hidden == !transcript.DisplayText.Contains(line.Trim(), StringComparison.Ordinal), line);
            // …including while it is still arriving.
            if (hidden)
            {
                var arriving = new TranscriptBuilder();
                arriving.Append(line[..Math.Min(line.Length, line.IndexOf("PLANTOIR_", StringComparison.Ordinal) + 12)]);
                Assert.DoesNotContain("PLANTOIR_", arriving.DisplayText);
            }
        }
    }
}

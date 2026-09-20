using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// The <c>PLANTOIR_HEALTH:</c> line is machinery, and a teacher reads this
/// console (CLAUDE.md rule 1). It must not appear there — and the finding it
/// carries must survive being hidden.
///
/// <para>Every test here ends its lines with <c>\r\n</c> on purpose. A pseudo
/// console converts every <c>\n</c> the script prints into <c>\r\n</c>, so a
/// test written against bare <c>\n</c> passes whether or not the real ending is
/// handled — mac row 366 shipped exactly that.</para>
/// </summary>
public class TranscriptHealthFilterTests
{
    private static string HealthLine(string name = "mediaFolderMissing") =>
        $"{SiteHealthFinding.Marker} {{\"name\": \"{name}\", \"sentence\": \"The Media folder for ICS3U is not there.\", " +
        "\"detail\": \"Some detail.\", \"fixable\": true, \"course\": \"ICS3U\", \"section\": 1}";

    [Fact]
    public void TheMarkerLineNeverReachesTheConsole()
    {
        var transcript = new TranscriptBuilder();
        transcript.Append("Checking this course's folders...\r\n");
        transcript.Append(HealthLine() + "\r\n");
        transcript.Append("Static build complete.\r\n");

        Assert.DoesNotContain(SiteHealthFinding.Marker, transcript.DisplayText);
        Assert.DoesNotContain(SiteHealthFinding.Marker, transcript.RecentText(8000));
        Assert.DoesNotContain(transcript.Lines, line => line.Contains(SiteHealthFinding.Marker));
        // The lines either side are ordinary output and are untouched.
        Assert.Contains("Checking this course's folders...", transcript.DisplayText);
        Assert.Contains("Static build complete.", transcript.DisplayText);
    }

    [Fact]
    public void TheHumanSentenceBesideItSurvives()
    {
        // site_health.py prints the sentence separately, in words. Hiding the
        // marker costs the teacher nothing precisely because of that.
        var transcript = new TranscriptBuilder();
        transcript.Append("The Media folder for ICS3U is not there.\r\n");
        transcript.Append(HealthLine() + "\r\n");

        Assert.Contains("The Media folder for ICS3U is not there.", transcript.DisplayText);
        Assert.DoesNotContain("\"fixable\"", transcript.DisplayText);
    }

    [Fact]
    public void AHalfArrivedMarkerLineIsNotRenderedWhileItWaitsForItsNewline()
    {
        // The console renders the line under construction, and a pseudo console
        // hands over whatever bytes are ready — so the payload would otherwise
        // sit on screen for as long as the rest of the line takes to arrive.
        var transcript = new TranscriptBuilder();
        transcript.Append("Static build complete.\r\n");
        transcript.Append(HealthLine()[..40]);

        Assert.DoesNotContain(SiteHealthFinding.Marker, transcript.DisplayText);
        Assert.Equal("", transcript.CurrentLine);
    }

    [Fact]
    public void AMarkerGluedToTheTailOfBuildChatterTakesTheWholeLineWithIt()
    {
        // The launchers interleave this output, so a finding can arrive stuck
        // to the end of another line. What precedes it there is progress noise,
        // not a sentence a teacher needs.
        var transcript = new TranscriptBuilder();
        transcript.Append("  ...done. " + HealthLine() + "\r\n");

        Assert.DoesNotContain(SiteHealthFinding.Marker, transcript.DisplayText);
        Assert.Empty(transcript.Lines);
    }

    [Fact]
    public void HidingTheLineDoesNotHideTheFinding()
    {
        // ScriptRunner hands the RAW text to CollectHealthFindings and only
        // then to the transcript, so the two cannot interfere. This pins that
        // ordering, which is the thing a later refactor would break silently.
        var runner = new ScriptRunner();
        runner.ReceiveOutput(HealthLine() + "\r\n");

        Assert.Single(runner.HealthFindings);
        Assert.Equal("mediaFolderMissing", runner.HealthFindings[0].Name);
        Assert.DoesNotContain(SiteHealthFinding.Marker, runner.Transcript.DisplayText);
    }

    [Fact]
    public void OrdinaryOutputStillCountsAsOutput()
    {
        // RefreshChrome and HasAnyOutput ask "did anything happen" by looking
        // at Lines.Count. A build that printed only a health line is not a real
        // shape — but pinning it says the filter cannot flip that answer for
        // any build that also printed a word.
        var transcript = new TranscriptBuilder();
        transcript.Append(HealthLine() + "\r\n");
        Assert.Empty(transcript.Lines);

        transcript.Append("Running the website builder on this PC ...\r\n");
        Assert.Single(transcript.Lines);
    }
}

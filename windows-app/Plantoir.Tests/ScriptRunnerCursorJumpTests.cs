using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// The app's console no longer joins the two lines either side of a cursor
/// jump (#661). Under ConPTY a blank line printed in the first screenful does
/// not arrive as CR LF CR LF: the frame is drawn by moving the cursor
/// (<c>…unchanged.\e[15;1H📁 Shared…</c>), and the stripper removed the move
/// and glued the lines. <see cref="ScriptRunner.ReceiveOutput"/> now passes
/// every read through <see cref="CursorMoveLineBreaks"/> before anything reads
/// it.
///
/// <para>Every input here is CAPTURED, not invented, unless it says otherwise:
/// the reads were recorded on 2026-10-28 (Lenovo 20QES70500, i5-8365U,
/// Windows 11 Pro 26200) by a probe that runs a launcher exactly as
/// ScriptRunner does — <c>ConPtyProcess.Start</c> at
/// <c>LauncherColumns</c> x 30, the same UTF-8 decoder — and logs each read.
/// documentation/12-windows-app.md → "Line breaks ConPTY draws as cursor moves
/// (#623, #661)".</para>
/// </summary>
/// <remarks>
/// In the serialized collection because a health finding writes a line to
/// the activity trail, whose path is a process-wide static.
/// </remarks>
[Collection(SharedActivityState.Name)]
public class ScriptRunnerCursorJumpTests : IDisposable
{
    private const string E = "\u001b";
    private readonly string _trailPath;

    public ScriptRunnerCursorJumpTests()
    {
        _trailPath = Path.Combine(Path.GetTempPath(), $"plantoir-trail-{Guid.NewGuid():N}.txt");
        ActivityTrail.SetCustomLogPathForTesting(_trailPath);
    }

    public void Dispose()
    {
        // Back to the suite's scratch trail, never to null (the real trail).
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { File.Delete(_trailPath); } catch { }
    }

    private static ScriptRunner Fed(params string[] reads)
    {
        var runner = new ScriptRunner();
        foreach (string read in reads) runner.ReceiveOutput(read);
        return runner;
    }

    /// <summary>The same reads straight into a TranscriptBuilder: the app before #661.</summary>
    private static TranscriptBuilder WithoutTheStage(params string[] reads)
    {
        var transcript = new TranscriptBuilder();
        foreach (string read in reads) transcript.Append(read);
        return transcript;
    }

    private static string HealthLine(string name) =>
        $"{SiteHealthFinding.Marker} {{\"name\": \"{name}\", \"sentence\": \"A sentence.\", " +
        "\"detail\": \"Some detail.\", \"fixable\": false, \"course\": \"PRB1O\", \"section\": 1}";

    // ---- The build -------------------------------------------------------

    /// <summary>
    /// <c>preview.ps1 PRB1O 1 --build-only</c> on a fresh section, reads 7-10
    /// of the capture: build_site.py's own <c>print("\n🔎 Preflight…")</c> and
    /// <c>print("\n📁 Shared folders…")</c>, drawn as jumps to rows 7 and 15.
    /// Read 10 is cut after its first two lines past the jump (the "📁 Shared
    /// folders" header and " - Discussions"); the rest of that read is left out.
    /// The app's saved transcript of the same run, before the fix, carried
    /// both joins at its lines 8 and 14.
    /// </summary>
    [Fact]
    public void TheBuildsPreflightLinesArriveApart()
    {
        string[] reads =
        {
            "📋 Timetable sections for this course: [1]",
            E + "[?25l" + E + "[7;1H🔎 Preflight: discovering new shared and per-section items...\r\n" + E + "[?25h",
            "\r\n📌 Auto-discovered shared folders: ['Discussions']",
            E + "[?25l\r\n📌 Auto-discovered shared files: —\r\n📌 Auto-discovered per-section folders: ['All Classes']\r\n"
                + "📌 Auto-discovered per-section files: —\r\nℹ️ No new items discovered; course_config.json unchanged."
                + E + "[15;1H📁 Shared folders to include for 'section1':\r\n - Discussions\r\n" + E + "[?25h",
        };

        // What the console showed before #661, so the test is known to bite.
        Assert.Contains(WithoutTheStage(reads).Lines, line => line.Contains("[1]🔎", StringComparison.Ordinal));

        var lines = Fed(reads).Transcript.Lines;
        Assert.Contains("📋 Timetable sections for this course: [1]", lines);
        Assert.Contains("🔎 Preflight: discovering new shared and per-section items...", lines);
        Assert.Contains("ℹ️ No new items discovered; course_config.json unchanged.", lines);
        Assert.Contains("📁 Shared folders to include for 'section1':", lines);
        Assert.DoesNotContain(lines, line => line.Contains("]🔎", StringComparison.Ordinal)
                                             || line.Contains(".📁", StringComparison.Ordinal));
    }

    // ---- Questions -------------------------------------------------------

    /// <summary>
    /// A stub that prints <c>"\nGot testing.\n"</c> and then asks
    /// <c>input("Continue anyway? [y/N] ")</c>, run at LauncherColumns x 30:
    /// the read that came back. <see cref="ScriptRunner.MayBeWaitingForInput"/>
    /// and the question box read <c>Transcript.CurrentLine</c>; before #661 it
    /// was "Got testing.Continue anyway? [y/N] ".
    /// </summary>
    [Fact]
    public void AQuestionAfterAJumpIsTheQuestionAlone()
    {
        string read = E + "[?25l\r\nGot testing." + E + "[7;1HContinue anyway? [y/N] " + E + "[?25h";
        Assert.Equal("Got testing.Continue anyway? [y/N] ", WithoutTheStage(read).CurrentLine);

        Assert.Equal("Continue anyway? [y/N] ", Fed(read).Transcript.CurrentLine);
    }

    /// <summary>
    /// A first publish to Netlify (<c>deploy.ps1 ICS3U 1</c>, a working
    /// folder with no site record), the read that carried the site-name
    /// question. Before #661 the question box would have asked "This name is
    /// shared globally with all users across the world.Enter Netlify site
    /// name"; now it asks the question alone, with the offered name lifted
    /// into the answer field.
    /// </summary>
    [Fact]
    public void TheSiteNameQuestionIsAskedAlone()
    {
        string read = E + "[?25l\r\n Timestamp TZ offset: -0400" + E + "[6;1HChoose a Website Address.\r\n"
            + "Every website deployed to Netlify (*.netlify.app) needs a unique web address.\r\n"
            + "This name is shared globally with all users across the world." + E
            + "[10;1HEnter Netlify site name [ics3u-s1-2026-vdopkqmy]: " + E + "[?25h";
        Assert.StartsWith("This name is shared globally", WithoutTheStage(read).CurrentLine, StringComparison.Ordinal);

        var runner = new ScriptRunner();
        runner.StageAsRunningForCapture(Array.Empty<TaskMilestone>(), read, quietSeconds: 5);

        Assert.Equal("Enter Netlify site name [ics3u-s1-2026-vdopkqmy]: ", runner.Transcript.CurrentLine);
        Assert.True(runner.MayBeWaitingForInput(DateTime.UtcNow));
        var asked = QuestionParser.SeparateDefaultAnswer(runner.Transcript.CurrentLine.Trim());
        Assert.DoesNotContain("world", asked.Question, StringComparison.Ordinal);
        Assert.Equal("ics3u-s1-2026-vdopkqmy", asked.SuggestedAnswer);
        Assert.Contains("Choose a Website Address.", runner.Transcript.Lines);
    }

    /// <summary>
    /// The setup wizard's colour picker, captured while browsing it (the
    /// second scheme of section 1, after one → ). Its footer is drawn with a
    /// jump to row 24 straight after the last swatch; before #661 it was
    /// glued onto "textHighlight", and NewCourseCreator matched it only
    /// because its prompt test uses Contains. Now the footer is a line of
    /// its own — the last non-empty line, which is what NewCourseCreator
    /// answers — so the wizard still gets its Return.
    /// </summary>
    [Fact]
    public void TheColourPickersFooterIsStillTheLineTheWizardAnswers()
    {
        string clearing = E + "[2J";
        string blankRows = E + "[?25l" + E + "[H" + string.Concat(Enumerable.Repeat(E + "[K\r\n", 29)) + E + "[K" + E + "[H" + E + "[?25h";
        string picker = "\u001b[?25l\u001b[1mColour Scheme for Section 1\r\n(4/43) Desert Sandstone\u001b[4;1HLight Mode:\u001b[22m\r\n  light\u001b[9X\u001b[48;2;252;247;241m\u001b[9C\u001b[10X\u001b[m\r\n  lightgray     \u001b[48;2;234;223;206m\u001b[10X\u001b[m\r\n  gray\u001b[10X\u001b[48;2;194;178;159m\u001b[10C\u001b[10X\u001b[m\r\n  darkgray      \u001b[48;2;110;91;72m\u001b[10X\u001b[m\r\n  dark\u001b[10X\u001b[48;2;63;47;34m\u001b[10C\u001b[10X\u001b[m\r\n  secondary     \u001b[48;2;192;108;67m\u001b[10X\u001b[m\r\n  tertiary      \u001b[48;2;47;115;102m\u001b[10X\u001b[m\r\n  textHighlight \u001b[48;2;128;128;128m\u001b[10X\u001b[m\u001b[1m\u001b[14;1HDark Mode:\u001b[22m\r\n  light\u001b[9X\u001b[48;2;26;20;16m\u001b[9C\u001b[10X\u001b[m\r\n  lightgray     \u001b[48;2;58;48;39m\u001b[10X\u001b[m\r\n  gray\u001b[10X\u001b[48;2;117;101;87m\u001b[10C\u001b[10X\u001b[m\r\n  darkgray      \u001b[48;2;225;214;199m\u001b[10X\u001b[m\r\n  dark\u001b[10X\u001b[48;2;241;232;221m\u001b[10C\u001b[10X\u001b[m\r\n  secondary     \u001b[48;2;240;162;119m\u001b[10X\u001b[m\r\n  tertiary      \u001b[48;2;91;199;179m\u001b[10X\u001b[m\r\n  textHighlight \u001b[48;2;128;128;128m\u001b[10X\u001b[m\u001b[24;1HUse ← / → (or 'p' / 'n') to browse, Enter to select. Press 'q' to keep previous choice.\r\n\u001b[?25h";

        var before = WithoutTheStage(clearing, blankRows, picker);
        Assert.Contains(before.Lines, line => line.StartsWith("(4/43) Desert SandstoneLight Mode:", StringComparison.Ordinal));

        var transcript = Fed(clearing, blankRows, picker).Transcript;
        Assert.Equal("", transcript.CurrentLine);
        string lastNonEmpty = transcript.Lines.Last(line => line.Trim().Length > 0).Trim();
        Assert.StartsWith("Use ← / → (or 'p' / 'n') to browse, Enter to select.", lastNonEmpty, StringComparison.Ordinal);
        Assert.True(NewCourseCreator.LooksLikePrompt(lastNonEmpty));
        Assert.Contains("(4/43) Desert Sandstone", transcript.Lines);
        Assert.Contains("Light Mode:", transcript.Lines);
        // The blank repaint ConPTY draws after the picker's \e[2J\e[H adds
        // no line of its own: its jumps land on lines that are empty.
        Assert.Equal(before.Lines.Count + 3, transcript.Lines.Count);
    }

    // ---- Machine lines ---------------------------------------------------

    /// <summary>
    /// Invented from the shape, not seen in a real run: a health line with a
    /// jump straight after it. Before #661 the payload carried "Next" on its
    /// end, the JSON did not parse, and the finding — with its trail line —
    /// was lost.
    /// </summary>
    [Fact]
    public void AHealthLineFollowedByAJumpIsStillAFinding()
    {
        string read = HealthLine("noGradedFolders") + E + "[9;1HNext\r\n";
        // What CollectHealthFindings parsed before #661: the stripped line.
        Assert.Null(SiteHealthFinding.Parse(TranscriptBuilder.StripControlSequences(read).TrimEnd()));

        var runner = Fed(read);
        Assert.Equal("noGradedFolders", Assert.Single(runner.HealthFindings).Name);
        Assert.Contains("Next", runner.Transcript.Lines);
    }

    /// <summary>
    /// Invented from the shape: a sentence with a health line jumped to after
    /// it. Glued, the whole line is a machine line and the console hid the
    /// teacher's sentence with it (transcriptStripping.machineLines).
    /// </summary>
    [Fact]
    public void ASentenceBeforeAHealthLineStaysVisible()
    {
        var runner = Fed("⚠️ Sentence." + E + "[9;1H" + HealthLine("noGradedFolders") + "\r\n");

        Assert.Single(runner.HealthFindings);
        Assert.Contains("⚠️ Sentence.", runner.Transcript.Lines);
        Assert.Contains("⚠️ Sentence.", runner.Transcript.DisplayText);
        Assert.DoesNotContain(SiteHealthFinding.Marker, runner.Transcript.DisplayText);
    }

    // ---- Escapes cut by a read -------------------------------------------

    /// <summary>
    /// A colour code cut between two reads. The stripper keeps no state
    /// between chunks, so before #661 the first half was dropped and "33m"
    /// was left in the console; the stage holds an unfinished escape back
    /// until it is whole.
    ///
    /// <para>The limit, kept on purpose (F6 of #661's review): the stage ends a
    /// CSI at any final byte 0x40-0x7E, but the stripper ends one only at an
    /// ASCII LETTER, so a CSI with a final like <c>~</c> (<c>\e[3~</c>) still
    /// eats text up to the next letter. That is the stateless stripper's
    /// behaviour, unchanged here and pinned by the contract's
    /// transcriptStripping cases; none of the four real runs measured carried
    /// one.</para>
    /// </summary>
    [Fact]
    public void AnEscapeCutBetweenTwoReadsLeavesNoTrace()
    {
        Assert.Equal("Done 33mok", WithoutTheStage("Done " + E + "[", "33mok" + E + "[m\r\n").Lines[0]);

        var runner = Fed("Done " + E + "[", "33mok" + E + "[m\r\n");
        Assert.Equal("Done ok", runner.Transcript.Lines[0]);
    }

    // ---- What the stage must NOT change ----------------------------------

    /// <summary>
    /// The repaint shapes seen in four real runs, every one on a line with no
    /// text yet, or moving the cursor anywhere but column 1: the opening
    /// modes; the clear and home at the start of a run; the blank repaint
    /// after the picker's clear; the spinner's <c>\r\e[K\e[37C</c>. None may
    /// add a line.
    /// </summary>
    [Fact]
    public void RepaintShapesAddNoLines()
    {
        string[] reads =
        {
            E + "[?9001h" + E + "[?1004h",
            E + "[?25l" + E + "[2J" + E + "[m" + E + "[HChecking allowed timetable sections for PRB1O ..."
                + E + "]0;C:\\WINDOWS\\System32\\WindowsPowerShell\\v1.0\\powershell.exe\a" + E + "[?25h",
            "\r\n",
            E + "[?25l" + E + "[H" + E + "[K\r\n" + E + "[K\r\n" + E + "[K" + E + "[H" + E + "[?25h",
            "Cleaned output directory `public` in " + E + "[33m35ms\r",
            E + "[m\n",
            E + "[K",
            "⠋ Parsing input files using 1 threads",
            "\r" + E + "[K",
            "⠙ Parsing input files using 1 threads",
            "\r" + E + "[K" + E + "[37C",
            "\r⠹ Parsing input files using 1 threads",
            "\r" + E + "[K",
        };

        var before = WithoutTheStage(reads);
        var after = Fed(reads).Transcript;
        Assert.Equal(before.Lines, after.Lines);
        Assert.Equal(before.CurrentLine, after.CurrentLine);
    }

    [Fact]
    public void AJumpOnAnEmptyLineAddsNoBlank()
    {
        var runner = Fed("done\r\n" + E + "[5;1Hnext\r\n");
        Assert.Equal(new[] { "done", "next" }, runner.Transcript.Lines);
    }

    /// <summary>
    /// The cost accepted with the stage (as in #623), pinned so nobody reads
    /// it as a bug and "fixes" it by tracking rows: when ConPTY repaints an
    /// EARLIER row with <c>CSI r;1H</c> while the current line has text, the
    /// repainted text shows as a line of its own, so it appears twice. Before
    /// the stage the same repaint was glued onto the current line instead.
    /// Invented from the shape; no repaint of an earlier row was seen in the
    /// runs measured (four launcher runs, the wizard while browsing, and a
    /// Cloudflare deploy).
    /// </summary>
    [Fact]
    public void ARepaintOfAnEarlierRowShowsTwice_Accepted()
    {
        string[] reads = { "Uploading 3 files\r\nProgress 1/3", E + "[1;1HUploading 3 files" + E + "[2;1HProgress 2/3\r\n" };

        Assert.Equal(new[] { "Uploading 3 files", "Progress 1/3Uploading 3 filesProgress 2/3" }, WithoutTheStage(reads).Lines);
        Assert.Equal(new[] { "Uploading 3 files", "Progress 1/3", "Uploading 3 files", "Progress 2/3" }, Fed(reads).Transcript.Lines);
    }

    // ---- Redaction (F7 of #661's review) ---------------------------------

    /// <summary>
    /// The saved transcript is redacted LINE BY LINE, so a value the stage
    /// moves onto a line of its own is out of reach of the labelledSecret
    /// rule, which needs its label on the same line. That is the shape an
    /// ordinary CR LF between a label and its value already had, and a
    /// prompt's echoed answer stays on the prompt's row (no jump to column 1).
    /// A token-shaped value is still caught by the 40-character rule.
    /// Invented from the shape.
    /// </summary>
    [Fact]
    public void ATokenJumpedOntoALineOfItsOwnIsStillRedacted()
    {
        const string token = "qQb7Z_kL8mN3pR5tV9wX1yA2cD4eF6gH8jK0lM2n";
        var runner = Fed("Cloudflare token:" + E + "[6;1H" + token + "\r\n");

        Assert.Equal(new[] { "Cloudflare token:", token }, runner.Transcript.Lines);
        Assert.Equal(LogRedactor.RemovedToken, LogRedactor.Redacting(runner.Transcript.Lines[1]));
    }

    // ---- A runner that runs again ----------------------------------------

    /// <summary>
    /// What the stage holds back belongs to the output it came from: a
    /// half-escape fed and then followed by ordinary text is completed by
    /// that text, not lost.
    /// </summary>
    [Fact]
    public void AHeldBackEscapeIsCompletedByTheNextRead()
    {
        var runner = Fed("Building" + E + "[1", "0;1HDone\r\n");
        Assert.Equal(new[] { "Building", "Done" }, runner.Transcript.Lines);
    }
}

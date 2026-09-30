using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// #279: the build rewrites a teacher's pages with their class's date (mac
/// #275/#276, shared Python — inherited), and this app owes three things
/// around it: the <c>PLANTOIR_DATED:</c> line kept out of the console a
/// teacher reads, the trail event <c>pages dated by the build</c> from a
/// console AND from a scheduled publish's record, and the front-page pointer
/// run against <c>class-planning.json</c> → <c>sectionIndexPointer.dateCases</c>.
/// Everything asserted is read from the contract, never retyped.
/// </summary>
[Collection(SharedActivityState.Name)]
public class PagesDatedByTheBuildTests
{
    private static JsonObject Marker =>
        ContractLoader.LoadJson("shared-rules.json")["pagesDatedByTheBuild"]!["marker"]!.AsObject();

    // MARK: - The marker

    [Fact]
    public void ThePrefixIsTheContracts()
    {
        Assert.Equal(Marker["prefix"]!.ToString(), PagesDatedByTheBuild.Marker);
    }

    [Fact]
    public void EveryContractExampleIsRead()
    {
        foreach (var example in Marker["examples"]!.AsArray())
        {
            var report = PagesDatedByTheBuild.Parse(example!.ToString());
            Assert.NotNull(report);
            Assert.False(string.IsNullOrEmpty(report!.Course));
            Assert.True(report.Section > 0);
            Assert.NotEmpty(report.Pages);
        }
    }

    [Fact]
    public void AMarkerGluedToOtherOutputIsReadFromThePrefix()
    {
        string example = Marker["examples"]![0]!.ToString();
        var report = PagesDatedByTheBuild.Parse("Building step 3 of 7" + example);
        Assert.NotNull(report);
        Assert.Equal("ICS4U", report!.Course);
        Assert.Equal(new[] { "section1/index", "Exercises/Using Aggregate Functions" }, report.Pages);
    }

    [Fact]
    public void ALineThatIsNotAReportIsNotRead()
    {
        Assert.Null(PagesDatedByTheBuild.Parse("Gave 2 of your pages the date of the first class that links to them"));
        Assert.Null(PagesDatedByTheBuild.Parse("PLANTOIR_DATED: {not json"));
        Assert.Null(PagesDatedByTheBuild.Parse("PLANTOIR_DATED: {\"course\": \"ICS4U\", \"section\": 1, \"pages\": []}"));
    }

    // MARK: - The console

    /// <summary>
    /// Rule 1: the JSON line never reaches the console, whole or while it is
    /// still arriving; the build's own sentence beside it is left alone. The
    /// shape of the mac's <c>testAGluedOrHalfArrivedLineIsReadAndNeverShown</c>.
    /// </summary>
    [Fact]
    public void TheLineIsNeverShownWholeOrHalfArrived()
    {
        string example = Marker["examples"]![0]!.ToString();
        var transcript = new TranscriptBuilder();
        transcript.Append("Gave 2 of your pages the date of the first class that links to them\n");
        transcript.Append(example[..20]);
        Assert.DoesNotContain("PLANTOIR_DATED", transcript.DisplayText);
        transcript.Append(example[20..] + "\n");
        transcript.Append("step 4" + example + "\n");

        Assert.DoesNotContain("PLANTOIR_DATED", transcript.DisplayText);
        Assert.DoesNotContain("PLANTOIR_DATED", string.Join("\n", transcript.Lines));
        Assert.Contains("Gave 2 of your pages", transcript.DisplayText);
    }

    // MARK: - The trail line

    [Fact]
    public void TheTrailLineHasTheContractsShape()
    {
        var one = new PagesDatedByTheBuild("ICS4U", 1, new[] { "section1/index" });
        Assert.Equal("the build gave 1 page the date of their class: section1/index", one.TrailSentence);

        var many = new PagesDatedByTheBuild("ICS4U", 1, Enumerable.Range(1, 43).Select(n => $"Exercises/P{n}").ToArray());
        Assert.StartsWith("the build gave 43 pages the date of their class: Exercises/P1, ", many.TrailSentence);
        Assert.EndsWith("Exercises/P40 and 3 more", many.TrailSentence);

        // The shape the contract states: count first, then the names.
        string shape = ContractLoader.LoadJson("shared-rules.json")["pagesDatedByTheBuild"]!["trailLine"]!["shape"]!.ToString();
        Assert.StartsWith(shape[..shape.IndexOf(" N ", StringComparison.Ordinal)], one.TrailSentence);
    }

    [Fact]
    public void AScheduledPublishsRecordLeavesTheTrailLine()
    {
        string folder = Path.Combine(Path.GetTempPath(), "dated-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        string trail = Path.Combine(folder, "activity.txt");
        ActivityTrail.SetCustomLogPathForTesting(trail);
        try
        {
            File.WriteAllLines(
                Path.Combine(folder, TaskScheduling.HealthRecordName("ICS4U", 1)),
                new[] { Marker["examples"]![0]!.ToString() });

            var findings = ScheduledHealthFindings.TakeFrom(folder, "ICS4U", 1);

            Assert.Empty(findings);
            string written = File.ReadAllText(trail);
            Assert.Contains("the build gave 2 pages the date of their class: section1/index, Exercises/Using Aggregate Functions", written);
        }
        finally
        {
            ActivityTrail.SetCustomLogPathForTesting(null);
            try { Directory.Delete(folder, recursive: true); } catch { }
        }
    }

    // MARK: - The pointer's date cases

    /// <summary>
    /// Every <c>dateCases</c> case with a <c>pointAt</c>, through the transform
    /// <c>AssistWorkspace.ApplyIndexChange</c> writes: repoint at
    /// <c>pointAt</c>, handed that class's date, then read the front page's
    /// <c>created</c> back. <c>expectCreatedDayOnWindows</c> wins where present
    /// (this app inserts an embed under the heading and then dates the page it
    /// has made); <c>null</c> means the page is left byte for byte.
    /// </summary>
    [Fact]
    public void ThePointerFollowsTheContractsDateCases()
    {
        var cases = ContractLoader.LoadJson("class-planning.json")["sectionIndexPointer"]!["dateCases"]!["cases"]!
            .AsArray()
            .Where(c => c!["pointAt"] is not null)
            .ToList();
        Assert.True(cases.Count >= 7, $"dateCases lost its pointAt cases: {cases.Count}");

        var failures = new List<(string Name, string Why)>();
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            string index = c["indexText"]!.ToString();
            string pointAt = c["pointAt"]!.ToString();
            // An undated class hands the pointer no date: it repoints and
            // writes no `created` (the plan carries a date only for a dated
            // class), which is the case "the embed names a class with no date".
            string? created = c["classes"]!.AsArray().First(k => k!["title"]!.ToString() == pointAt)!["created"]?.ToString();
            string? expect = (c["expectCreatedDayOnWindows"] ?? c["expectCreatedDay"])?.ToString();
            if (c.AsObject().ContainsKey("expectCreatedDayOnWindows") && c["expectCreatedDayOnWindows"] is null)
                expect = null;

            string after = created is null
                ? SectionIndex.WithMostRecent(index, pointAt) ?? index
                : SectionIndex.PointedAndDated(index, pointAt, DateOnly.Parse(created[..10]), "T07:00:00.000+0000") ?? index;
            string? day = CreatedDay(after);

            if (expect is null)
            {
                if (CreatedDay(after) != CreatedDay(index))
                    failures.Add((name, $"the page's date should have been left alone, and reads {day}"));
            }
            else if (day != expect)
            {
                failures.Add((name, $"expected created {expect}, got {day ?? "none"}"));
            }
        }
        // A case this app owes and has not built is held open by name against
        // the issue that owns it; the ledger fails the day it starts passing.
        var names = cases.Select(c => c!["name"]!.ToString()).ToList();
        var failing = failures.Select(f => f.Name).ToHashSet();
        var deferred = NamedGapLedger.GapsIn(
            NamedGapLedger.FrontPageDateCases, names, names.Where(n => !failing.Contains(n)));
        var unexplained = failures.Where(f => !deferred.Contains(f.Name)).Select(f => $"{f.Name}: {f.Why}").ToList();
        Assert.True(unexplained.Count == 0, string.Join("\n", unexplained));
    }

    private static string? CreatedDay(string page)
    {
        foreach (string raw in page.Split('\n').Skip(1))
        {
            string line = raw.TrimEnd('\r');
            if (line.Trim() == "---") break;
            if (line.StartsWith("created:", StringComparison.Ordinal))
            {
                string value = line["created:".Length..].Trim().Trim('"', '\'');
                return value.Length >= 10 ? value[..10] : value;
            }
        }
        return null;
    }
}

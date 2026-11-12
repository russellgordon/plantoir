using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The Problems store (#734): read through the builds root the launchers
/// wrote to, keyed by <see cref="SectionKey"/>, a course read whole, one
/// alert per alert key still answered after a relaunch, one trail line per
/// alert key, ticks and the tab in memory. Process-wide state, so serialised.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class SectionProblemsStoreTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "plantoir-problems-" + Guid.NewGuid().ToString("N")[..8]);
    private readonly string _folder;
    private readonly string _builds;
    private readonly string _trail;
    private readonly Func<string, string> _previousRoot;

    public SectionProblemsStoreTests()
    {
        _folder = Path.Combine(_root, "Work");
        _builds = Path.Combine(_root, "builds");
        _trail = Path.Combine(_root, "state", "activity.txt");
        Directory.CreateDirectory(Path.Combine(_folder, "courses", "MPM2D"));
        Directory.CreateDirectory(Path.GetDirectoryName(_trail)!);
        File.WriteAllText(Path.Combine(_folder, "courses", "MPM2D", "course_config.json"),
            """{"course_code": "MPM2D", "course_name": "Maths", "section_numbers": [1, 2], "num_sections": 2}""");
        _previousRoot = SectionProblems.BuildsRootFor;
        SectionProblems.BuildsRootFor = _ => _builds;
        SectionProblems.Reset();
        ActivityTrail.SetCustomLogPathForTesting(_trail);
    }

    public void Dispose()
    {
        SectionProblems.BuildsRootFor = _previousRoot;
        SectionProblems.Reset();
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { File.Delete(ProblemsAcknowledgements.PathFor(_folder)); } catch { }
        try { Directory.Delete(_root, true); } catch { }
    }

    private Course Course() => new("MPM2D", Path.Combine(_folder, "courses", "MPM2D"),
        CourseConfiguration.Load(Path.Combine(_folder, "courses", "MPM2D", "course_config.json")));

    private void WriteRecord(int section, string json)
    {
        string path = SectionProblemsRecord.PathFor(_builds, "MPM2D", section);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, json);
        // A later write than the last one, whatever the clock's grain.
        File.SetLastWriteTimeUtc(path, DateTime.UtcNow.AddSeconds(section + File.ReadAllText(path).Length % 7));
    }

    private string TrailText() => File.Exists(_trail) ? File.ReadAllText(_trail) : "";

    [Fact]
    public void TheKeyIsCanonical_AndACourseIsReadWhole()
    {
        WriteRecord(1, SectionProblemsContractTests.RecordJson);
        Assert.True(SectionProblems.Reload(_folder, Course()));

        Assert.True(SectionProblems.HasMarker(_folder, "MPM2D", 1));
        Assert.False(SectionProblems.HasMarker(_folder, "MPM2D", 2));
        Assert.True(SectionProblems.HasMarker(_folder.ToUpperInvariant() + "\\", "mpm2d", 1),
            "a folder typed two ways and a course however it is cased are one section");
        Assert.NotNull(SectionProblems.Record(_folder, "MPM2D", 1));
        Assert.Empty(SectionProblems.OtherRecords(_folder, Course(), 1));
        Assert.Single(SectionProblems.OtherRecords(_folder, Course(), 2));
    }

    [Fact]
    public void ARecordReadAgainUnchangedRaisesNothing_AndAChangedOneRaisesChanged()
    {
        int changed = 0;
        void Count(string folder, string course) => changed++;
        SectionProblems.Changed += Count;
        try
        {
            WriteRecord(1, SectionProblemsContractTests.RecordJson);
            Assert.True(SectionProblems.Reload(_folder, Course()));
            Assert.False(SectionProblems.Reload(_folder, Course()), "nothing moved on disk, so nothing is re-read or raised");
            Assert.Equal(1, changed);
            // A clean build rewrites the record: the marker goes.
            WriteRecord(1, """{"version": 1, "course": "MPM2D", "section": 1, "buildId": "B3", "builtAt": "2026-11-01T14:00:00Z", "rows": [], "changed": {"new": [], "gone": ["figuresCouldNotBeDrawn|Unit 1/Graphs|tikz|k1"]}, "alertKey": "B3"}""");
            Assert.True(SectionProblems.Reload(_folder, Course()));
            Assert.False(SectionProblems.HasMarker(_folder, "MPM2D", 1));
            Assert.Equal(2, changed);
        }
        finally { SectionProblems.Changed -= Count; }
    }

    [Fact]
    public void AMissingOrBrokenRecordIsNoRecord()
    {
        Assert.False(SectionProblems.Reload(_folder, Course()));
        Assert.Null(SectionProblems.Record(_folder, "MPM2D", 1));
        WriteRecord(1, "{broken");
        SectionProblems.Reload(_folder, Course());
        Assert.Null(SectionProblems.Record(_folder, "MPM2D", 1));
        Assert.False(SectionProblems.HasMarker(_folder, "MPM2D", 1));
    }

    [Fact]
    public void AnAnsweredAlertIsNotRaisedAgain_EvenAfterARelaunch()
    {
        WriteRecord(1, SectionProblemsContractTests.RecordJson);
        SectionProblems.Reload(_folder, Course());
        var due = SectionProblems.RecordWithAnAlertDue(_folder, "MPM2D", 1);
        Assert.NotNull(due);
        SectionProblems.Answer(due!, SectionProblemsRules.AnsweredShow, _folder, "MPM2D", 1);
        Assert.Null(SectionProblems.RecordWithAnAlertDue(_folder, "MPM2D", 1));

        SectionProblems.Reset();   // a relaunch: memory gone, the file stays
        SectionProblems.Reload(_folder, Course());
        Assert.Null(SectionProblems.RecordWithAnAlertDue(_folder, "MPM2D", 1));
        Assert.Contains("MPM2D/1 · answered the alert about new problems: Show", TrailText());
    }

    /// <summary>
    /// An answer the file could not keep (a replace refused by a scanner, seen
    /// once in the full UI run) still holds while the app is open; only a
    /// relaunch reads the file alone.
    /// </summary>
    [Fact]
    public void AnAnswerHoldsForTheSessionEvenWhenTheFileLostIt()
    {
        WriteRecord(1, SectionProblemsContractTests.RecordJson);
        SectionProblems.Reload(_folder, Course());
        var due = SectionProblems.RecordWithAnAlertDue(_folder, "MPM2D", 1)!;
        SectionProblems.Answer(due, SectionProblemsRules.AnsweredNotNow, _folder, "MPM2D", 1);
        File.Delete(ProblemsAcknowledgements.PathFor(_folder));
        Assert.Null(SectionProblems.RecordWithAnAlertDue(_folder, "MPM2D", 1));
        SectionProblems.Reset();
        SectionProblems.Reload(_folder, Course());
        Assert.NotNull(SectionProblems.RecordWithAnAlertDue(_folder, "MPM2D", 1));
    }

    /// <summary>
    /// Once a record has been read, whether its alert is due is answered from
    /// memory: the interface thread asks every 300 ms while the links checklist
    /// waits, and must not read the disk to answer (#734 review, finding 3).
    /// </summary>
    [Fact]
    public void WhetherTheAlertIsDueIsAnsweredFromMemory()
    {
        WriteRecord(1, SectionProblemsContractTests.RecordJson);
        SectionProblems.Reload(_folder, Course());
        // Another program's answer, written after the read: not seen until a relaunch.
        var outside = ProblemsAcknowledgements.Read(_folder);
        outside.RememberAnswered("B2", "MPM2D", 1);
        outside.Write(_folder);
        Assert.NotNull(SectionProblems.RecordWithAnAlertDue(_folder, "MPM2D", 1));
        SectionProblems.Reset();
        SectionProblems.Reload(_folder, Course());
        Assert.Null(SectionProblems.RecordWithAnAlertDue(_folder, "MPM2D", 1));
    }

    [Fact]
    public void TheTrailLineIsWrittenOncePerAlertKey_NotAgainAfterARelaunch()
    {
        WriteRecord(1, SectionProblemsContractTests.RecordJson);
        SectionProblems.Reload(_folder, Course());
        SectionProblems.Reset();
        SectionProblems.Reload(_folder, Course());
        string line = "MPM2D/1 · the preview found 1 new and 1 fewer problems (new: figuresCouldNotBeDrawn; gone: quizzesNotReady)";
        Assert.Equal(1, TrailText().Split(line).Length - 1);
        Assert.Equal(new[] { "B2" }, ProblemsAcknowledgements.Read(_folder).Noted("MPM2D", 1));
        Assert.DoesNotContain("Unit 1", TrailText());
    }

    [Fact]
    public void ARecordWhoseSetDidNotChangeWritesNoLine()
    {
        WriteRecord(1, SectionProblemsContractTests.RecordJson
            .Replace("\"new\": [\"figuresCouldNotBeDrawn|Unit 1/Graphs|tikz|k1\"]", "\"new\": []")
            .Replace("\"gone\": [\"quizzesNotReady|Unit 1/Quiz|\"]", "\"gone\": []"));
        SectionProblems.Reload(_folder, Course());
        Assert.DoesNotContain("problems", TrailText());
        Assert.Null(SectionProblems.RecordWithAnAlertDue(_folder, "MPM2D", 1));
        Assert.True(SectionProblems.HasMarker(_folder, "MPM2D", 1), "the marker stays while the record has rows");
    }

    [Fact]
    public void TwentyAreKeptPerSection()
    {
        IReadOnlyList<string> many = Array.Empty<string>();
        for (int index = 0; index < 30; index++) many = ProblemsAcknowledgements.Adding("k" + index, many);
        Assert.Equal(ProblemsAcknowledgements.Kept, many.Count);
        Assert.Equal("k29", many[^1]);
        Assert.Equal("k10", many[0]);
        Assert.Equal(new[] { "a", "b" }, ProblemsAcknowledgements.Adding("b", new[] { "b", "a" }));

        var kept = ProblemsAcknowledgements.Read(_folder);
        for (int index = 0; index < 25; index++) kept.RememberAnswered("k" + index, "MPM2D", 1);
        kept.Write(_folder);
        Assert.Equal(20, ProblemsAcknowledgements.Read(_folder).Answered("MPM2D", 1).Count);
        Assert.Empty(ProblemsAcknowledgements.Read(_folder).Answered("MPM2D", 2));
    }

    [Fact]
    public void TicksAndTheTabAreKeptInMemory_AndProblemsNeedsProblems()
    {
        WriteRecord(1, SectionProblemsContractTests.RecordJson);
        SectionProblems.Reload(_folder, Course());
        const string row = "figuresCouldNotBeDrawn|Unit 1/Graphs|tikz|k1";
        Assert.True(SectionProblems.IsTicked(row, _folder, "MPM2D", 1), "ticked means included, and every row starts ticked");
        SectionProblems.SetTicked(false, row, _folder, "mpm2d", 1);
        Assert.False(SectionProblems.IsTicked(row, _folder, "MPM2D", 1));

        Assert.Equal(SectionProblems.Tab.Website, SectionProblems.TabFor(_folder, "MPM2D", 1));
        SectionProblems.Show(SectionProblems.Tab.Problems, _folder, "MPM2D", 1);
        Assert.Equal(SectionProblems.Tab.Problems, SectionProblems.TabFor(_folder, "MPM2D", 1));
        SectionProblems.Show(SectionProblems.Tab.Problems, _folder, "MPM2D", 2);
        Assert.Equal(SectionProblems.Tab.Website, SectionProblems.TabFor(_folder, "MPM2D", 2));
    }

    [Fact]
    public void OneViewHoldsTheAlertForASection()
    {
        Assert.True(SectionProblems.ClaimTheAlert(_folder, "MPM2D", 1, "B2"));
        Assert.False(SectionProblems.ClaimTheAlert(_folder.ToLowerInvariant(), "mpm2d", 1, "B2"), "a second window on the section waits");
        Assert.True(SectionProblems.ClaimTheAlert(_folder, "MPM2D", 2, "B3"));
        SectionProblems.ReleaseTheAlert(_folder, "MPM2D", 1);
        Assert.True(SectionProblems.ClaimTheAlert(_folder, "MPM2D", 1, "B2"));
    }

    /// <summary>
    /// The store reads where the LAUNCHERS build (#664): the real
    /// <c>LOCALAPPDATA</c>, never <see cref="AppDataRoot"/> (redirected under
    /// this suite, as under <c>--state-dir</c>) and never
    /// <c>PLANTOIR_BUILD_ROOT</c>, which every launcher overwrites.
    /// </summary>
    [Fact]
    public void TheRecordsAreWhereTheLaunchersBuild()
    {
        Assert.Equal((Func<string, string>)BuildOutputLocation.WhereTheLaunchersBuild, _previousRoot);
        string? before = Environment.GetEnvironmentVariable("PLANTOIR_BUILD_ROOT");
        Environment.SetEnvironmentVariable("PLANTOIR_BUILD_ROOT", Path.Combine(_root, "ignored"));
        try
        {
            string where = BuildOutputLocation.WhereTheLaunchersBuild(_folder);
            string expected = Path.Combine(Environment.GetEnvironmentVariable("LOCALAPPDATA")!, "Plantoir", "builds",
                                           FolderContainers.FolderIdentifier(_folder));
            Assert.Equal(expected, where);
            Assert.DoesNotContain(AppDataRoot.Current, where, StringComparison.OrdinalIgnoreCase);
            Assert.NotEqual(BuildOutputLocation.BuildsRootFor(_folder), where);
        }
        finally { Environment.SetEnvironmentVariable("PLANTOIR_BUILD_ROOT", before); }
        // And the launcher really writes there: the same expression, in each of them.
        foreach (string launcher in new[] { "preview.ps1", "deploy.ps1", "setup.ps1" })
            Assert.Contains("Join-Path $env:LOCALAPPDATA ('Plantoir\\builds\\' + $WORKDIR_ID)",
                            File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, launcher)));
    }

    [Fact]
    public void AReadOffTheInterfaceThreadKeepsWhatItRead()
    {
        WriteRecord(2, SectionProblemsContractTests.RecordJson.Replace("\"section\": 1", "\"section\": 2"));
        Assert.True(SectionProblems.ReloadAsync(_folder, "MPM2D", new[] { 1, 2 }).GetAwaiter().GetResult());
        Assert.True(SectionProblems.HasMarker(_folder, "MPM2D", 2));
    }
}

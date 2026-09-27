using System.Globalization;
using System.Text.RegularExpressions;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// GitHub #144: a date rendered with <c>ToString("yyyy-MM-dd")</c> and no
/// culture takes its YEAR from the machine's default calendar, so a Windows
/// PC whose regional format is Thai wrote <c>created: 2569-…</c> into
/// teachers' pages and remembered a timetable 543 years out. Every test here
/// runs under such a culture for its duration, and the first thing each one
/// proves is that the swap TOOK — a machine running with invariant
/// globalization, where <c>th-TH</c> is Gregorian, would otherwise pass
/// every assertion while proving nothing.
///
/// <para>Plain temp folders and a per-thread culture: nothing process-wide,
/// so this class stays out of <c>SharedActivityState</c>.</para>
/// </summary>
public class DateTextTests
{
    private static readonly DateOnly Day = new(2026, 9, 9);
    private static readonly DateTime Moment = new(2026, 9, 9, 14, 15, 30);

    /// <summary>
    /// Cultures whose DEFAULT calendar is not Gregorian, with the year each
    /// one renders 2026 as. Thai Buddhist is the case the issue measured on
    /// Windows 11; Umm al-Qura is a second, unrelated calendar so the fix is
    /// not shown to work for one offset only.
    /// </summary>
    public static IEnumerable<object[]> NonGregorianCultures =>
    [
        ["th-TH", "2569"],
        ["ar-SA", "1448"],
    ];

    private static void Under(string cultureName, string expectedBareYear, Action body)
    {
        var culture = new CultureInfo(cultureName);
        var was = CultureInfo.CurrentCulture;
        var wasUi = CultureInfo.CurrentUICulture;
        CultureInfo.CurrentCulture = culture;
        CultureInfo.CurrentUICulture = culture;
        try
        {
            // The guard: a bare rendering really does shift under this culture
            // here, on this machine. If it does not, nothing below is a test.
            string bare = Moment.ToString("yyyy-MM-dd");
            Assert.True(bare.StartsWith(expectedBareYear, StringComparison.Ordinal),
                $"Under {cultureName} a bare ToString(\"yyyy-MM-dd\") rendered {bare}; expected the year " +
                $"{expectedBareYear}. The culture swap did not take (invariant globalization?), so this " +
                "run proves nothing about #144.");
            body();
        }
        finally
        {
            CultureInfo.CurrentCulture = was;
            CultureInfo.CurrentUICulture = wasUi;
        }
    }

    [Theory]
    [MemberData(nameof(NonGregorianCultures))]
    public void TheHelperRendersTheGregorianYearWhateverTheRegionalFormat(string culture, string bareYear) =>
        Under(culture, bareYear, () =>
        {
            Assert.Equal("2026-09-09", DateText.Iso(Day));
            Assert.Equal("2026-09-09 14:15:30", DateText.Stamp(Moment));
            Assert.Equal("2026-09-09_141530", DateText.Invariant(Moment, "yyyy-MM-dd_HHmmss"));
            Assert.Equal("2026-09-09 at 14.15.30", DateText.Invariant(Moment, "yyyy-MM-dd 'at' HH.mm.ss"));
            Assert.Equal("2026-09-09", DateText.Invariant(Day, "yyyy-MM-dd"));
        });

    [Theory]
    [MemberData(nameof(NonGregorianCultures))]
    public void ReadingTheAppsOwnSpellingBackIsGregorianToo(string culture, string bareYear) =>
        Under(culture, bareYear, () =>
        {
            // The reader half of the fault: an invariant write read back with a
            // bare parse takes the digits as a year in the machine's calendar.
            // Measured 1483 under th-TH in the #159 work; here it is only
            // asserted to be WRONG, since the exact wrong year is the
            // calendar's business.
            // (Under ar-SA the bare parse fails outright rather than
            // misreading, measured on .NET 9 and 10: either way it is not Day.)
            bool bareRead = DateOnly.TryParse("2026-09-09", out var bare);
            Assert.True(!bareRead || bare != Day, "A bare parse read the app's own spelling correctly here, so this proves nothing.");

            Assert.True(DateText.TryReadDay("2026-09-09", out var read));
            Assert.Equal(Day, read);
            Assert.True(DateText.TryReadDay("  2026-09-09 ", out read));
            Assert.Equal(Day, read);

            Assert.False(DateText.TryReadDay(null, out _));
            Assert.False(DateText.TryReadDay("", out _));
            Assert.False(DateText.TryReadDay("tomorrow", out _));
        });

    [Fact]
    public void TheReaderTakesOnlyTheShapeTheToolsAskFor()
    {
        // EXACT, not lenient: a lenient invariant parse reads "09/08/2026" as
        // September the 8th (US order). The tools that reach this reader ask
        // for YYYY-MM-DD and refuse anything else by name, and a teacher in
        // Canada who typed the 9th of August must get that refusal rather
        // than a class dated a month later.
        Assert.False(DateText.TryReadDay("09/08/2026", out _));
        Assert.False(DateText.TryReadDay("2026-09-09T07:00:00", out _));
        Assert.False(DateText.TryReadDay("9 September 2026", out _));
        Assert.True(DateText.TryReadDay("2026-09-09", out var day));
        Assert.Equal(Day, day);
    }

    [Fact]
    public void TheStampKeepsColonsWhereTheCultureWouldWriteDots()
    {
        // The ":" in a custom format is the culture's TIME SEPARATOR, so a
        // bare HH:mm:ss renders 14.15.30 on a Finnish machine — the same
        // fault as the year, one column over, and it reached the trail and
        // every run transcript. Guarded the same way: first prove the bare
        // rendering really does shift here.
        var was = CultureInfo.CurrentCulture;
        CultureInfo.CurrentCulture = new CultureInfo("fi-FI");
        try
        {
            string bare = Moment.ToString("HH:mm:ss");
            Assert.True(bare == "14.15.30",
                $"Under fi-FI a bare HH:mm:ss rendered {bare}; expected 14.15.30, so this test proves nothing here.");
            Assert.Equal("2026-09-09 14:15:30", DateText.Stamp(Moment));
            Assert.Equal("2026-09-09 14:15:30 " + Moment.ToString("zzz", CultureInfo.InvariantCulture),
                DateText.Invariant(Moment, "yyyy-MM-dd HH:mm:ss zzz"));
        }
        finally
        {
            CultureInfo.CurrentCulture = was;
        }
    }

    [Fact]
    public void TheHelperIsIdenticalToTheBareRenderingOnAGregorianMachine()
    {
        // en-US, en-CA and the invariant culture are all Gregorian: the fix
        // changes nothing a teacher on such a machine has ever seen. Pinned so
        // a future "improvement" to the helper cannot quietly change the
        // spelling every existing file already carries.
        var was = CultureInfo.CurrentCulture;
        CultureInfo.CurrentCulture = new CultureInfo("en-CA");
        try
        {
            Assert.Equal(Day.ToString("yyyy-MM-dd"), DateText.Iso(Day));
            Assert.Equal(Moment.ToString("yyyy-MM-dd HH:mm:ss"), DateText.Stamp(Moment));
        }
        finally
        {
            CultureInfo.CurrentCulture = was;
        }
    }

    // ---- The writers the issue named, end to end -----------------------------

    [Fact]
    public void TimetableMemory_RoundTripsUnderABuddhistCalendar() =>
        Under("th-TH", "2569", () =>
        {
            string workspace = Path.Combine(Path.GetTempPath(), "plantoir-144-" + Guid.NewGuid().ToString("N"));
            try
            {
                var dates = new[] { new DateOnly(2026, 9, 8), new DateOnly(2026, 9, 10), new DateOnly(2026, 9, 12) };
                Assert.True(TimetableMemory.Write(workspace, "ICS3U", 1, dates, "typed in by hand", Day));

                string file = Path.Combine(workspace, "courses", "ICS3U", ".internal", "timetable", "section1.json");
                string written = File.ReadAllText(file);
                Assert.Contains("2026-09-08", written);
                Assert.DoesNotContain("2569", written);

                var read = TimetableMemory.Read(workspace, "ICS3U", 1);
                Assert.NotNull(read);
                Assert.Equal(dates, read!.Dates);
                Assert.Equal(Day, read.Recorded);
            }
            finally
            {
                try { Directory.Delete(workspace, recursive: true); } catch { }
            }
        });

    [Fact]
    public void SetCreated_WritesAGregorianYear() =>
        Under("th-TH", "2569", () =>
        {
            const string page = "---\ntitle: Unit 1, Day 1\ncreated: 2026-09-01T07:00:00.000-0400\n---\nHello.\n";
            var (text, changed) = PageFrontmatter.SetCreated(page, "created", Day);
            Assert.True(changed);
            Assert.Contains("created: 2026-09-09T07:00:00.000-0400", text);
            Assert.DoesNotContain("2569", text);
        });

    [Fact]
    public void SaveRunTranscript_NamesTheFileAndItsFirstLinesInTheGregorianYear() =>
        Under("th-TH", "2569", () =>
        {
            string logs = Path.Combine(Path.GetTempPath(), "plantoir-144-" + Guid.NewGuid().ToString("N"));
            try
            {
                var store = new ProblemReportStore(logs);
                string path = store.SaveRunTranscript("setup.ps1", "finished", Moment, ["one line"]);

                // The NAME decides what gets deleted: RunFilePaths and PruneRuns
                // sort transcripts by file name, ordinally, so a name in another
                // calendar's year would outrank every real one for ever.
                Assert.Equal("2026-09-09 141530 setup.ps1.txt", Path.GetFileName(path));
                string[] lines = File.ReadAllLines(path);
                Assert.Equal("Started 2026-09-09 14:15:30.", lines[1]);
            }
            finally
            {
                try { Directory.Delete(logs, recursive: true); } catch { }
            }
        });

    [Fact]
    public void ARunsFolderAlreadyHoldingThaiYearNamesStillKeepsTheNewestTranscripts()
    {
        // The fix itself makes this folder MIXED on every affected machine:
        // twenty old transcripts named 2569-… beside the new 2026-… ones.
        // Ordinally the old names win, so ordering by name would have kept
        // the old twenty for ever and deleted each new transcript on
        // arrival. The order is by the file's write time now, which has no
        // calendar.
        string logs = Path.Combine(Path.GetTempPath(), "plantoir-144-" + Guid.NewGuid().ToString("N"));
        try
        {
            var store = new ProblemReportStore(logs);
            Directory.CreateDirectory(store.RunsFolder);
            var lastWeek = DateTime.UtcNow.AddDays(-7);
            for (int i = 0; i < ProblemReportStore.MostRetainedRuns; i++)
            {
                string old = Path.Combine(store.RunsFolder, $"2569-09-{(i % 28) + 1:00} {i:000000} preview.ps1.txt");
                File.WriteAllText(old, "an old run");
                File.SetLastWriteTimeUtc(old, lastWeek.AddMinutes(i));
            }

            string fresh = store.SaveRunTranscript("setup.ps1", "finished", Moment, ["today's run"]);

            var listed = store.RunFilePaths();
            Assert.Equal(ProblemReportStore.MostRetainedRuns, listed.Count);
            Assert.Equal(fresh, listed[0]);
            Assert.True(File.Exists(fresh), "The new transcript was pruned on arrival, which is the failure this guards against.");
            Assert.DoesNotContain(listed, path => Path.GetFileName(path).StartsWith("2569-09-01 000000", StringComparison.Ordinal));
        }
        finally
        {
            try { Directory.Delete(logs, recursive: true); } catch { }
        }
    }

    [Fact]
    public void ATimetableRememberedInAnotherCalendarsYearReadsAsNotRemembered()
    {
        // Such a file is on every affected teacher's disk: the old writer put
        // 2569-09-08 there, and this reader has always taken that as the
        // Gregorian year 2569. Reading it as nothing makes the assistant ask
        // again, and the next Write replaces it with a file it can read.
        string workspace = Path.Combine(Path.GetTempPath(), "plantoir-144-" + Guid.NewGuid().ToString("N"));
        try
        {
            string folder = Path.Combine(workspace, "courses", "ICS3U", ".internal", "timetable");
            Directory.CreateDirectory(folder);
            File.WriteAllText(Path.Combine(folder, "section1.json"),
                """{"section":1,"dates":["2569-09-08","2569-09-10"],"source":"typed in by hand","recorded":"2569-09-09"}""");
            Assert.Null(TimetableMemory.Read(workspace, "ICS3U", 1, today: Day));

            // The bounds, both sides, and a real memory just inside them.
            File.WriteAllText(Path.Combine(folder, "section1.json"),
                """{"section":1,"dates":["2024-12-31","2026-09-10"],"source":"typed in by hand","recorded":"2026-09-09"}""");
            Assert.Null(TimetableMemory.Read(workspace, "ICS3U", 1, today: Day));
            File.WriteAllText(Path.Combine(folder, "section1.json"),
                """{"section":1,"dates":["2026-09-08","2029-09-10"],"source":"typed in by hand","recorded":"2026-09-09"}""");
            Assert.Null(TimetableMemory.Read(workspace, "ICS3U", 1, today: Day));
            File.WriteAllText(Path.Combine(folder, "section1.json"),
                """{"section":1,"dates":["2025-01-01","2029-09-09"],"source":"typed in by hand","recorded":"2026-09-09"}""");
            var kept = TimetableMemory.Read(workspace, "ICS3U", 1, today: Day);
            Assert.NotNull(kept);
            Assert.Equal(2, kept!.Dates.Count);
        }
        finally
        {
            try { Directory.Delete(workspace, recursive: true); } catch { }
        }
    }

    [Fact]
    public void TheProblemReportStampIsGregorian() =>
        Under("th-TH", "2569", () =>
        {
            Assert.Equal("2026-09-09 at 14.15.30", ProblemReportBuilder.Stamp(Moment));
            Assert.Contains("Made on 2026-09-09 14:15:30",
                string.Join("\n", ProblemReportBuilder.About(3, ProblemReportBuilder.AssistantPrompts.None, Moment)));
        });

    // ---- The tripwire ---------------------------------------------------------

    /// <summary>
    /// A site that is deliberately in the machine's culture, and why. An
    /// entry excuses ONE line, matched by file name and a substring of the
    /// line, so that it cannot quietly excuse a second site added beside it.
    /// </summary>
    private static readonly (string File, string Contains, string Why)[] DeliberatelyCultural =
    [
        ("TaskScheduling.cs", "when.ToString(format)",
            "schtasks.exe accepts a date only in the machine's own short format; DateFormats is walked until it takes one."),
        ("TaskScheduling.cs", "DateTime.TryParse(value, out var when)",
            "parses schtasks' Next Run Time row, which Windows wrote in the machine's culture."),
        // The three below are fixed on origin/issue/159-settle-the-day-once
        // (ScheduledDeploy.ReadTheMoment, one reader). They are excused here so
        // that this test does not change lines that branch also changes; the
        // entries go when #159 lands, and ReadTheMoment's own cultural
        // FALLBACK (a human-written shape) will want an entry of its own.
        ("AssistAgent.cs", "_dateline = $\" (Today is {today:yyyy-MM-dd}",
            "#159 rewrites this dateline invariantly from its one clock; left for that branch."),
        ("AssistAgent.cs", "{DateTime.Now.AddDays(1):yyyy-MM-dd} {hour:00}:{minute:00}",
            "#159 rewrites the card's moment invariantly from its one clock; left for that branch."),
        ("AssistAgent.cs", "DateTime.TryParse(when, out var parsed)",
            "#159 replaces this with ScheduledDeploy.ReadTheMoment; left for that branch."),
        ("PlantoirTools.cs", "DateTime.TryParse(when, out var moment)",
            "#159 replaces both of these (plan_scheduled_deploy, schedule_deploy) with ScheduledDeploy.ReadTheMoment; left for that branch."),
    ];

    private static readonly Regex RendersAYear = new(
        @"ToString\(\s*""[^""]*yyyy|:yyyy[^""}]*\}|\.ToString\(\s*format\s*\)", RegexOptions.Compiled);

    private static readonly Regex ParsesADate = new(
        @"\b(DateTime|DateOnly|DateTimeOffset)\.(Try)?Parse(Exact)?\(", RegexOptions.Compiled);

    [Fact]
    public void NoProductSourceRendersOrReadsAYearInTheMachinesCalendar()
    {
        string root = ContractLoader.RepositoryRoot;
        string[] projects = ["Plantoir.Core", "Plantoir.Mcp", "Plantoir"];
        var offenders = new List<string>();
        int filesRead = 0;
        int helperCalls = 0;

        foreach (string project in projects)
        {
            string folder = Path.Combine(root, "windows-app", project);
            Assert.True(Directory.Exists(folder), $"{folder} is missing; the walk is looking in the wrong place.");
            foreach (string file in Directory.EnumerateFiles(folder, "*.cs", SearchOption.AllDirectories))
            {
                string relative = Path.GetRelativePath(folder, file).Replace('\\', '/');
                if (relative.StartsWith("bin/", StringComparison.Ordinal) ||
                    relative.StartsWith("obj/", StringComparison.Ordinal)) continue;
                if (relative == "Models/DateText.cs") continue; // the helper is where the culture is passed
                filesRead++;

                string[] lines = File.ReadAllLines(file);
                for (int i = 0; i < lines.Length; i++)
                {
                    string line = lines[i];
                    string trimmed = line.TrimStart();
                    if (trimmed.StartsWith("//", StringComparison.Ordinal)) continue;
                    if (line.Contains("DateText.", StringComparison.Ordinal)) helperCalls++;
                    if (line.Contains("InvariantCulture", StringComparison.Ordinal)) continue;
                    if (line.Contains("CultureInfo.CurrentCulture", StringComparison.Ordinal)) continue; // said out loud
                    // string.Create(CultureInfo.InvariantCulture, $"…") puts the
                    // culture on the line BEFORE the interpolation (the #159 shape).
                    if (i > 0 && lines[i - 1].Contains("string.Create(CultureInfo.InvariantCulture", StringComparison.Ordinal)) continue;
                    if (!RendersAYear.IsMatch(line) && !ParsesADate.IsMatch(line)) continue;

                    string name = Path.GetFileName(file);
                    bool excused = DeliberatelyCultural.Any(entry =>
                        entry.File == name && line.Contains(entry.Contains, StringComparison.Ordinal));
                    if (excused) continue;

                    offenders.Add($"{project}/{relative}:{i + 1}: {trimmed}");
                }
            }
        }

        Assert.True(filesRead > 100, $"Only {filesRead} source files were read; this test is proving nothing.");
        Assert.True(helperCalls > 40, $"Only {helperCalls} lines call DateText; the walk missed the product code.");

        Assert.True(offenders.Count == 0,
            "These lines render a year, or read one, in whatever calendar the machine's regional format " +
            "uses — on a Thai PC that is 2569 for 2026, written into files this app reads back as Gregorian " +
            "(#144). Go through DateText, pass CultureInfo.InvariantCulture on the same line, or — only for " +
            "text the machine itself wrote or must read, like schtasks' — add an entry to DeliberatelyCultural " +
            "saying why:\n  " + string.Join("\n  ", offenders));
    }

    [Fact]
    public void EveryExcuseStillExcusesALineThatExists()
    {
        // An entry that matches nothing is an entry that has rotted — the
        // line it excused was fixed or moved — and a dead excuse is the one
        // that will one day excuse a NEW site by accident. The #159 entries
        // are the exception this test has to live with until that branch
        // lands: they name lines that branch removes.
        string root = ContractLoader.RepositoryRoot;
        var missing = new List<string>();
        foreach (var entry in DeliberatelyCultural)
        {
            if (entry.Why.Contains("#159", StringComparison.Ordinal)) continue;
            bool found = Directory.EnumerateFiles(Path.Combine(root, "windows-app"), entry.File, SearchOption.AllDirectories)
                .Where(path => !path.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}") &&
                               !path.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}"))
                .Any(path => File.ReadLines(path).Any(line => line.Contains(entry.Contains, StringComparison.Ordinal)));
            if (!found) missing.Add($"{entry.File}: {entry.Contains}");
        }
        Assert.True(missing.Count == 0,
            "These DeliberatelyCultural entries no longer match any line; remove them:\n  " + string.Join("\n  ", missing));
    }
}

using System.Diagnostics;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// <c>contracts/app-rules.json → buildFreshness.reuseTheLastBuild</c> (#799,
/// the mac's #768): every case, built on the real clock by
/// <see cref="FreshnessCases"/>, asked of the app's reader
/// (<see cref="BuildFreshness.WhyRebuild(string, string, DateTime?)"/>) and,
/// for the two linked-course cases the Python suite cannot make on a PC
/// without Developer Mode, of the runtime Python's
/// <c>toolchain_paths.why_build_before_deploying</c> (what deploy.ps1 and
/// deploy.py ask) through JUNCTIONS. The mac's runner is
/// <c>mac-app/Tests/QuartzTeachersTests/ReuseTheLastBuildTests.swift</c>.
///
/// <para>The cases are deserialised, never retyped: a case the mac adds runs
/// here at once and goes red if this reader disagrees, which is the request
/// working. A case carrying <c>knownLimitOn: ["windows"]</c> is left out BY
/// NAME, and <see cref="TheKnownLimitsOnWindowsAreSkippedByName"/> pins
/// exactly which, so nothing else can ever be left out quietly (xUnit 2 has
/// no runtime skip).</para>
/// </summary>
public class ReuseTheLastBuildTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "plantoir-reuse-" + Guid.NewGuid().ToString("N"));

    public ReuseTheLastBuildTests() => Directory.CreateDirectory(_root);

    public void Dispose() => ReferenceFixtures.Remove(_root);

    public static IEnumerable<object[]> CasesTheAppRuns() =>
        FreshnessCases.Contract["cases"]!.AsArray()
            .Select(c => c!.AsObject())
            .Where(c => !FreshnessCases.IsAKnownLimitHere(c))
            .Select(c => new object[] { c["name"]!.GetValue<string>() });

    public static IEnumerable<object[]> TheLinkedCourseCases() =>
        FreshnessCases.Contract["cases"]!.AsArray()
            .Select(c => c!.AsObject())
            .Where(c => c["courseFolderIsALink"]?.GetValue<bool>() == true && !FreshnessCases.IsAKnownLimitHere(c))
            .Select(c => new object[] { c["name"]!.GetValue<string>() });

    private static string Said(string? reason) => reason is null ? "reuse" : "build because " + reason;

    [Theory]
    [MemberData(nameof(CasesTheAppRuns))]
    public void TheAppsAnswerIsTheContracts(string name)
    {
        var @case = FreshnessCases.Case(name);
        var notes = new FreshnessCases.Notes();
        var built = FreshnessCases.Build(_root, @case, notes);

        string? reason = BuildFreshness.WhyRebuild(built.Course, built.Section);

        var (expect, because) = FreshnessCases.Expected(@case, readsTheStamp: false);
        string wanted = expect == "reuse" ? "reuse" : "build because " + because;
        Assert.True(wanted == Said(reason), $"{name}: the contract says {wanted}; BuildFreshness said {Said(reason)}");

        // Moved over the old file (MoveFileEx with REPLACE_EXISTING, which is
        // os.replace too), the new copy keeps its OWN creation time, made after
        // the build: measured on this PC, no tunnelling on that path. Media's
        // time changes as well; that is what carries the case when the copy is
        // made the other way (below).
        if (notes.ReplacedFile is { } replaced)
        {
            DateTime reference = FreshnessCases.Reference(built.Section);
            string media = Path.GetDirectoryName(replaced)!;
            Assert.True(Later(Directory.GetLastWriteTimeUtc(media), Directory.GetCreationTimeUtc(media)) > reference,
                "Media's own time did not change when its picture was replaced");
        }
    }

    private static DateTime Later(DateTime a, DateTime b) => a > b ? a : b;

    /// <summary>
    /// The copy made the OTHER way, as Explorer, robocopy or a sync service
    /// can: the old file deleted and a new one written under its name, its
    /// modification time set back. NTFS tunnelling (a name removed and made
    /// again in the same folder within 15 s) then hands the new file the OLD
    /// creation time, so the FILE reads as unchanged by every time it has, and
    /// only Media's own time shows it. Pinned so a "files only"
    /// simplification fails here, loudly, for the right reason. Windows only:
    /// tunnelling is NTFS's.
    /// </summary>
    [Fact]
    public void APictureDeletedAndWrittenAgainIsCaughtByItsFolderAlone()
    {
        var built = FreshnessCases.Build(_root, FreshnessCases.Case("nothing has changed since the build"));
        string picture = Path.Combine(built.Course, "Media", "diagram.png");
        DateTime oldWrite = File.GetLastWriteTimeUtc(picture);
        File.Delete(picture);
        File.WriteAllText(picture, "a new copy\n");
        File.SetLastWriteTimeUtc(picture, oldWrite);
        DateTime reference = FreshnessCases.Reference(built.Section);

        DateTime fileTime = Later(File.GetLastWriteTimeUtc(picture), File.GetCreationTimeUtc(picture));
        Assert.True(fileTime <= reference,
            $"NTFS did not tunnel the old creation time ({fileTime:O} after {reference:O}): this test no longer proves the folder is needed");
        Assert.Equal(BuildFreshness.ReasonPages, BuildFreshness.WhyRebuild(built.Course, built.Section));
    }

    [Fact]
    public void TheKnownLimitsOnWindowsAreSkippedByName()
    {
        var all = FreshnessCases.Contract["cases"]!.AsArray().Select(c => c!["name"]!.GetValue<string>()).ToList();
        var run = CasesTheAppRuns().Select(row => (string)row[0]).ToHashSet();
        var left = all.Where(name => !run.Contains(name)).ToList();

        // Exactly the cases the contract marks as a known limit on Windows.
        Assert.Equal(
            all.Where(name => FreshnessCases.IsAKnownLimitHere(FreshnessCases.Case(name))).OrderBy(n => n),
            left.OrderBy(n => n));
        // Today one, and the contract's knownLimits says why for Windows.
        Assert.Single(left);
        Assert.Contains(FreshnessCases.Contract["knownLimits"]!.AsArray(),
            limit => limit!.GetValue<string>().StartsWith("On Windows", StringComparison.Ordinal) &&
                     limit.GetValue<string>().Contains("knownLimitOn", StringComparison.Ordinal));
        // And every other case is run, the linked ones included.
        Assert.Equal(all.Count - 1, run.Count);
    }

    /// <summary>
    /// Hidden is judged by the NAME: a folder carrying Windows' hidden
    /// attribute but named without a dot is read like any other. Windows
    /// only, and not a contract case (the plan's §11: it would oblige the mac
    /// to make a Finder-flag fixture for a rule its readers already follow).
    /// </summary>
    [Fact]
    public void AFolderWithTheHiddenAttributeButNoDotIsStillRead()
    {
        var @case = FreshnessCases.Case("nothing has changed since the build");
        var built = FreshnessCases.Build(_root, @case);
        string lessons = Path.Combine(built.Course, "notes");
        File.SetAttributes(lessons, File.GetAttributes(lessons) | FileAttributes.Hidden | FileAttributes.System);
        Thread.Sleep(FreshnessCases.PauseMilliseconds);
        // The attribute itself changes no time; the edit does.
        string? before = BuildFreshness.WhyRebuild(built.Course, built.Section);
        File.AppendAllText(Path.Combine(lessons, "day-1.md"), "\nedited\n");
        string? after = BuildFreshness.WhyRebuild(built.Course, built.Section);
        File.SetAttributes(lessons, FileAttributes.Directory);

        Assert.Null(before);
        Assert.Equal(BuildFreshness.ReasonPages, after);
    }

    /// <summary>
    /// A junction INSIDE the course is followed, as the runtime Python's
    /// os.walk follows one (measured on this PC by the #799 plan review, L2),
    /// and a junction that leads back into the course ends rather than
    /// walking for ever.
    /// </summary>
    [Fact]
    public void AJunctionInsideTheCourseIsFollowedAndALoopEnds()
    {
        var @case = FreshnessCases.Case("nothing has changed since the build");
        string elsewhere = Path.Combine(_root, "section-kept-elsewhere");
        Directory.CreateDirectory(elsewhere);
        File.WriteAllText(Path.Combine(elsewhere, "lesson.md"), "a lesson\n");
        Thread.Sleep(FreshnessCases.PauseMilliseconds);
        var built = FreshnessCases.Build(_root, @case);
        // Made before the build is dated? No: the junctions are made after,
        // and making an entry changes the course folder's own time, so date
        // the comparison from after they exist.
        ReferenceFixtures.Junction(Path.Combine(built.Course, "linked-in"), elsewhere);
        ReferenceFixtures.Junction(Path.Combine(built.Course, "notes", "loop"), built.Course);
        Thread.Sleep(FreshnessCases.PauseMilliseconds);
        DateTime afterTheLinks = DateTime.UtcNow;
        Thread.Sleep(FreshnessCases.PauseMilliseconds);

        var clock = Stopwatch.StartNew();
        bool quiet = BuildFreshness.SomethingInTheCourseIsNewer(built.Course, afterTheLinks);
        clock.Stop();
        File.AppendAllText(Path.Combine(elsewhere, "lesson.md"), "\nedited\n");
        bool seen = BuildFreshness.SomethingInTheCourseIsNewer(built.Course, afterTheLinks);

        Assert.False(quiet);
        Assert.True(clock.ElapsedMilliseconds < 5000, $"the walk took {clock.ElapsedMilliseconds} ms: the loop did not end");
        Assert.True(seen, "a change behind a junction inside the course was not seen; os.walk sees it");
    }

    /// <summary>
    /// The same two linked-course cases through the RUNTIME Python's
    /// <c>why_build_before_deploying</c>, the reader deploy.ps1 and deploy.py
    /// ask, on junctions: the only proof on a PC without Developer Mode that
    /// they read a course folder through a junction and read the junction's
    /// own times. It reads the stamp, so <c>expect</c>/<c>because</c> apply
    /// without <c>inTheApps</c>. With no fetched runtime it says so and
    /// proves nothing (PythonToolchainTests is where a missing interpreter
    /// fails the suite).
    /// </summary>
    [Theory]
    [MemberData(nameof(TheLinkedCourseCases))]
    public void TheRuntimePythonReadsALinkedCourseFolderAsTheContractSays(string name)
    {
        if (NativeRuntime.Folder is not { } runtime) return;
        string python = Path.Combine(runtime, "python", "python.exe");
        var @case = FreshnessCases.Case(name);
        var built = FreshnessCases.Build(_root, @case);

        var info = new ProcessStartInfo(python)
        {
            RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false, CreateNoWindow = true,
        };
        info.ArgumentList.Add("-c");
        info.ArgumentList.Add(
            "import sys; sys.path.insert(0, sys.argv[1]); import toolchain_paths as t; " +
            "r = t.why_build_before_deploying(sys.argv[2], sys.argv[3], toolchain_id=sys.argv[4]); " +
            "sys.stdout.write(r or 'reuse')");
        info.ArgumentList.Add(Path.Combine(ContractLoader.RepositoryRoot, "scripts"));
        info.ArgumentList.Add(built.Course);
        info.ArgumentList.Add(built.Section);
        info.ArgumentList.Add(FreshnessCases.ThisToolchain);
        info.Environment["PLANTOIR_CONTRACTS_DIR"] = Path.Combine(ContractLoader.RepositoryRoot, "contracts");
        using var process = Process.Start(info)!;
        string said = process.StandardOutput.ReadToEnd().Trim();
        string errors = process.StandardError.ReadToEnd();
        process.WaitForExit(60_000);
        Assert.True(process.ExitCode == 0, errors);

        var (expect, because) = FreshnessCases.Expected(@case, readsTheStamp: true);
        Assert.Equal(expect == "reuse" ? "reuse" : because, said);
    }
}

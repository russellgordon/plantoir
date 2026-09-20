using System.Text.Json.Nodes;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// The progress bar, pinned against the contract rather than against memory.
///
/// <para>Two apps read the SAME output from the same shared Python and move the
/// same bar, but their launchers are different programs printing different
/// words. <c>contracts/app-rules.json</c> → <c>markerOrigins.origins</c> says,
/// for every marker, which of those two it is — and that classification is the
/// thing that decides whether Windows must match a string to the character or
/// write its own. Getting it wrong crashes nothing: the bar simply stops
/// moving, which reads as a slow build (documentation/12-windows-app.md, where
/// exactly that shipped).</para>
///
/// <para>The mac runs this classification against its own files
/// (<c>AppRulesContractTests.testEveryMarkerIsClassified</c>). Nothing ran it
/// here, which the 2026-09-06 contract audit found. What follows is the same check
/// pointed the other way, plus the parity half the mac cannot do: that a step
/// the mac's list gains is a step this side's list gains too.</para>
///
/// <para>Windows' OWN launcher markers are deliberately not in the contract —
/// they are the platform's text, not the product's — and are pinned against the
/// real <c>.ps1</c> files by <see cref="TaskMilestoneLauncherMarkerTests"/>.</para>
/// </summary>
public class MilestoneContractTests
{
    private static string RepoRoot
    {
        get
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            for (int i = 0; i < 8 && dir is not null; i++, dir = dir.Parent)
            {
                if (File.Exists(Path.Combine(dir.FullName, "Dockerfile")))
                    return dir.FullName;
            }
            throw new DirectoryNotFoundException("Could not find repository root containing Dockerfile.");
        }
    }

    /// <summary>Marker text → "shared-python", "launcher" or "elsewhere".</summary>
    private static Dictionary<string, string> Origins()
    {
        var doc = ContractLoader.LoadJson("app-rules.json");
        var origins = doc["markerOrigins"]!["origins"]!.AsObject();
        var map = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var (marker, origin) in origins)
            map[marker] = origin!.ToString();
        return map;
    }

    /// <summary>Every distinct marker this app watches for.</summary>
    private static IEnumerable<string> WindowsMarkers()
    {
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var list in TaskMilestones.AllLists)
            foreach (var milestone in list)
                if (seen.Add(milestone.Marker))
                    yield return milestone.Marker;
    }

    /// <summary>
    /// Whether anything under <c>scripts/</c> carries this text.
    ///
    /// <para>Plain containment, so a marker named in a COMMENT or a docstring
    /// counts as printed — <c>"Netlify site"</c> and <c>"timetable section
    /// numbers"</c> both appear in both forms today. Deliberately the same
    /// weakness as the mac's <c>text(_:appearsUnder:)</c>: the two suites
    /// should go red together or not at all, and tightening one side alone
    /// would mean a marker that fails here and passes there, which is worse
    /// than a shared false positive. Tighten both, or neither.</para>
    /// </summary>
    private static bool AppearsUnderScripts(string marker)
    {
        string scripts = Path.Combine(RepoRoot, "scripts");
        foreach (string file in Directory.EnumerateFiles(scripts, "*.py", SearchOption.AllDirectories))
        {
            // A stale .pyc from an earlier Python can carry a string the source
            // no longer prints, which would keep this green after a rename.
            if (file.Contains("__pycache__", StringComparison.Ordinal)) continue;
            if (File.ReadAllText(file).Contains(marker, StringComparison.Ordinal)) return true;
        }
        return false;
    }

    private static bool AppearsInAWindowsLauncher(string marker)
    {
        foreach (string launcher in new[] { "setup.ps1", "preview.ps1", "deploy.ps1" })
        {
            string path = Path.Combine(RepoRoot, launcher);
            if (File.Exists(path) && File.ReadAllText(path).Contains(marker, StringComparison.Ordinal)) return true;
        }
        return false;
    }

    // ---- Is the string still printed by whatever is supposed to print it? ----

    /// <summary>
    /// A marker the contract calls shared Python must still be printed by
    /// something in <c>scripts/</c>. This is the half that protects the bar:
    /// shared Python is byte-identical on both platforms, so a phrase that
    /// changes there stalls BOTH apps, and only a test that reads the real
    /// files can notice.
    /// </summary>
    [Fact]
    public void EverySharedPythonMarkerIsStillPrintedByTheSharedScripts()
    {
        var origins = Origins();
        foreach (string marker in WindowsMarkers())
        {
            if (!origins.TryGetValue(marker, out string? origin) || origin != "shared-python") continue;

            Assert.True(AppearsUnderScripts(marker),
                $"\"{marker}\" is classified as shared Python in contracts/app-rules.json → " +
                "markerOrigins.origins, and nothing under scripts/ prints it any more. " +
                "TaskMilestones.cs is watching for text that will never arrive, so this " +
                "step of the progress bar can never be reached.");
        }
    }

    /// <summary>
    /// The reverse, and the one that found a real gap: a marker the contract
    /// does NOT classify, which shared Python nevertheless prints, is a shared
    /// string masquerading as this platform's own. Both apps must match it
    /// exactly and only one of them knows that.
    ///
    /// <para>This is how <c>"Example Course installed to"</c> and
    /// <c>"EXAMPLE_COURSE_CODE="</c> were found: printed by
    /// <c>scripts/setup_course.py</c>, matched by BOTH apps' example-course
    /// task, and classified nowhere — because the mac's classification test
    /// walked the contract's generated <c>milestones</c> readout, and
    /// <c>AppRulesContract.milestones()</c> left that one task out of it. A
    /// forward check is only as complete as the list it walks; this one does
    /// not walk a list at all, which is why it saw what the forward check could
    /// not.</para>
    ///
    /// <para><b>The readout no longer omits the task</b> — issue #82 landed on
    /// the mac on 2026-09-08, and <c>milestones</c> carries <c>exampleCourse</c>
    /// now. The structural fix was better than the one-line one the issue
    /// proposed: that side gained a <c>TaskMilestones.allLists</c> (this app had
    /// <c>AllLists</c> already) and the readout ITERATES it, because a readout
    /// assembled from a hand-kept list of what to read is a readout that can
    /// silently omit things. This test is kept all the same: it is the check
    /// that does not depend on any list being complete, and that is the property
    /// that found the gap.</para>
    /// </summary>
    [Fact]
    public void AMarkerTheSharedScriptsPrintIsClassifiedAsShared()
    {
        var origins = Origins();
        foreach (string marker in WindowsMarkers())
        {
            if (origins.ContainsKey(marker)) continue;

            Assert.False(AppearsUnderScripts(marker),
                $"\"{marker}\" is printed by shared Python and is not classified in " +
                "contracts/app-rules.json → markerOrigins.origins. Add it there as " +
                "\"shared-python\", so the other app is told to match it exactly rather " +
                "than being left to invent its own wording for a line it also receives.");
        }
    }

    /// <summary>
    /// Anything left — not classified by the contract, and not printed by the
    /// shared scripts — has to be this platform's own launcher text, and the
    /// launcher has to actually print it.
    /// </summary>
    [Fact]
    public void AMarkerTheContractDoesNotClassifyIsOurOwnLauncherText()
    {
        var origins = Origins();
        foreach (string marker in WindowsMarkers())
        {
            if (origins.ContainsKey(marker)) continue;

            Assert.True(AppearsInAWindowsLauncher(marker),
                $"\"{marker}\" is classified by nobody: the contract does not name it, no shared " +
                "script prints it, and neither does setup.ps1, preview.ps1 or deploy.ps1. " +
                "Either it is dead text in TaskMilestones.cs or the launcher that printed it " +
                "has been rewritten.");
        }
    }

    /// <summary>
    /// A marker the contract calls launcher text, which this app also watches
    /// for, must be printed by one of THIS platform's launchers. The mac
    /// checks the same names against its own three; the strings that are the
    /// mac's alone are guarded separately, below.
    /// </summary>
    [Fact]
    public void EveryLauncherMarkerWeShareWithTheMacIsPrintedByOurLaunchers()
    {
        var origins = Origins();
        foreach (string marker in WindowsMarkers())
        {
            if (!origins.TryGetValue(marker, out string? origin) || origin != "launcher") continue;

            Assert.True(AppearsInAWindowsLauncher(marker),
                $"\"{marker}\" is launcher text and none of this platform's launchers print it.");
        }
    }

    /// <summary>
    /// The mac's launcher phrasings must never reach this app's milestones.
    ///
    /// <para>Read from the contract rather than typed here: the list used to be
    /// a hand-kept array in <c>ParsingTests</c>, and a hand-kept list of the
    /// other platform's words is the thing that goes stale the day that
    /// platform changes them.</para>
    /// </summary>
    [Fact]
    public void NoMilestoneWatchesForTheMacsOwnLauncherWording()
    {
        var doc = ContractLoader.LoadJson("app-rules.json");
        var macOnly = doc["markerOrigins"]!["knownDivergence"]!["macOnlyLauncherMarkers"]!.AsArray();
        Assert.NotEmpty(macOnly);

        foreach (var entry in macOnly)
        {
            string marker = entry!.ToString();
            foreach (var list in TaskMilestones.AllLists)
                foreach (var milestone in list)
                    Assert.False(milestone.Marker.Contains(marker, StringComparison.Ordinal),
                        $"TaskMilestones is watching for \"{marker}\", which is the MAC launcher's " +
                        "wording. Nothing on this platform prints it, so the bar stops there.");
        }
    }

    // ---- Did the mac gain a step this side never heard about? ----

    /// <summary>
    /// The mac's milestone list for a task, and this app's, name the same
    /// shared-Python steps in the same order.
    ///
    /// <para>The two lists are NOT the same list and are not meant to be: the
    /// launcher steps differ by design, and since Windows dropped the container
    /// on 2026-08-19 several of the mac's have no counterpart here at all. What
    /// must agree is the part that comes out of the shared scripts, because a
    /// step the mac added there is a step this side is also receiving and
    /// simply not showing.</para>
    /// </summary>
    [Fact]
    public void EveryTaskShowsTheSharedStepsTheMacShows()
    {
        var origins = Origins();
        var doc = ContractLoader.LoadJson("app-rules.json");
        var milestones = doc["milestones"]!.AsObject();

        var ours = new Dictionary<string, IReadOnlyList<TaskMilestone>>(StringComparer.Ordinal)
        {
            ["courseCreation"] = TaskMilestones.CourseCreation,
            ["preview"] = TaskMilestones.Preview,
            ["deploy"] = TaskMilestones.Deploy,
            ["deployToFolder"] = TaskMilestones.DeployToFolder,
            ["deployToCloudflare"] = TaskMilestones.DeployToCloudflare,
            ["buildAndDeploy"] = TaskMilestones.BuildAndDeploy,
            ["buildAndDeployToFolder"] = TaskMilestones.BuildAndDeployToFolder,
            ["buildAndDeployToCloudflare"] = TaskMilestones.BuildAndDeployToCloudflare,

            // Answered before the contract asked, and now the contract asks.
            // Both apps have always had an example-course task, but the mac's
            // AppRulesContract.milestones() omitted it from the readout, so its
            // two markers were classified by nobody until 2026-09-06. Listing
            // it here ahead of time is why the mac's fix (issue #82, landed
            // 2026-09-08) regenerated the contract and arrived GREEN rather
            // than failing this suite by name for a change that was entirely
            // correct.
            //
            // Which is worth keeping as the pattern rather than deleting as
            // history: answering a task the contract does not yet name costs
            // one line, and it turns the other platform's correct change from
            // a red suite into a no-op.
            ["exampleCourse"] = TaskMilestones.ExampleCourse,
        };

        // Every task the contract names must be answered here. A task list the
        // mac ADDS therefore fails by name, which is the whole point of wiring
        // these lists: the gap announces itself in the run after it lands
        // rather than being found months later.
        var unanswered = new HashSet<string>(StringComparer.Ordinal);
        foreach (var (task, _) in milestones)
            if (task != "note" && !ours.ContainsKey(task)) unanswered.Add(task);

        Assert.True(unanswered.Count == 0,
            "contracts/app-rules.json names milestone lists this app has no counterpart for: " +
            string.Join(", ", unanswered.OrderBy(t => t, StringComparer.Ordinal)) +
            ". Either add the list to TaskMilestones.cs, or say here why this platform has no " +
            "such task — but do not leave it unanswered.");

        foreach (var (task, steps) in milestones)
        {
            if (task == "note") continue;

            var expected = new List<string>();
            foreach (var step in steps!.AsArray())
            {
                string marker = step!["marker"]!.ToString();
                if (origins.TryGetValue(marker, out string? origin) && origin == "shared-python")
                    expected.Add(marker);
            }

            // Built from the CLASSIFICATION, not by filtering to what the mac
            // happens to list. Filtering the other way would drop a shared step
            // this app shows and the mac does not — the one direction the mac
            // cannot see from its side — and print two identical lists while
            // passing.
            var actual = new List<string>();
            foreach (var milestone in ours[task])
                if (origins.TryGetValue(milestone.Marker, out string? origin) && origin == "shared-python")
                    actual.Add(milestone.Marker);

            Assert.True(expected.SequenceEqual(actual, StringComparer.Ordinal),
                $"The \"{task}\" progress bar shows the shared steps [{string.Join(", ", actual)}] " +
                $"where the mac shows [{string.Join(", ", expected)}]. These come out of the shared " +
                "Python, so this app is receiving every one of them; a missing step is a bar that " +
                "jumps, and a reordered one is a bar that goes backwards.");
        }
    }

    // TheExampleCourseMarkersAreClassifiedThoughTheReadoutOmitsTheTask stood
    // here until 2026-09-09. It checked that the example-course task's two
    // markers were classified even though the contract's milestones readout
    // left that task out — "until the mac's readout is fixed (issue #82),
    // this is the only thing checking them".
    //
    // The readout was fixed on 2026-09-08 and `milestones` now carries
    // `exampleCourse`, so it is neither the only thing checking them nor
    // checking anything the two tests above do not: EveryTaskShowsTheShared
    // StepsTheMacShows now VISITS that task, and AMarkerTheSharedScriptsPrint
    // IsClassifiedAsShared walks TaskMilestones.AllLists, which has always
    // included ExampleCourse and never depended on the readout at all.
    //
    // Deleted rather than left passing, because a test whose own comment
    // describes a state that no longer exists is read as the current state by
    // whoever meets it next. Issue #121.
}

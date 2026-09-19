using System.Text;
using System.Text.Json.Nodes;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Tools;

namespace Plantoir.UiTests;

/// <summary>
/// Removing a folder in Course Settings, driven through the real interface,
/// and read back off the file the teacher's build will use.
///
/// <para><b>What no unit test here can see.</b>
/// <c>GradedFolderChoicesTests.WhatARemovalDoesToTheMarksPoolMatchesTheContract</c>
/// plays the six contract cases through
/// <c>FolderRemoval.RemoveFolderFromCourse</c>, which proves the RULE. It
/// cannot prove that the gesture a teacher makes reaches that rule: the remove
/// button could be wired to something else, the confirmation could not go
/// ahead, Save could write a pool the form invented. That whole path — click,
/// confirm, Save, file on disk — is what this drives, and the assertion is the
/// one the rule exists for: a course nobody has asked about marks still has no
/// <c>graded_folders</c> key afterwards.</para>
///
/// <para>Its own fixture rather than <c>CourseFixtures.WriteBoth</c>, for two
/// reasons. The floor that refuses to leave a course with nothing counting for
/// marks would REPLACE the remove button with a blocked-reason one if the
/// course had only a single inferred marks folder, so this course has two
/// (<c>Tasks</c> and <c>Thinking Tasks</c>) — and the second one is also what
/// makes the never-asked case interesting, since the historical rule counts it
/// and a frozen pool would not. And adding a course to the shared fixture
/// would change what every other suite in this project sees.</para>
///
/// <para>Nothing here previews or schedules anything: the app is driven with
/// <c>--state-dir</c>, and the only writes are to the run's own working folder.
/// See <c>DrivenApp</c> for why a test that drove Preview would NOT be
/// safe.</para>
///
/// <para><b>Mutation-measured 2026-09-18, because a UI test that pins nothing
/// is worse than none.</b> Restoring the pre-fix body in full — the walk taken
/// before the exclusion, materialised over, then <c>RemoveAll</c> — fails this
/// test with <c>graded_folders: ["Thinking Tasks"]</c> written to the file,
/// which is the teacher-visible damage itself. Worth knowing for anyone
/// tempted to simplify it: the old POOL SEMANTICS alone, over a correct
/// post-exclusion walk, leave it GREEN, because `InferredPool` then no longer
/// contains the removed name. What this test guards is the ORDER reaching the
/// file, not the arithmetic.</para>
///
/// <para>Serialised with the other suites that drive the app: two at once would
/// fight over the foreground window.</para>
/// </summary>
[Collection("drives the real app")]
public class MarksPoolRemovalUiTests
{
    private const string Code = "SPH3U";

    /// <summary>
    /// A course that has NEVER been asked about marks — no
    /// <c>graded_folders</c> key at all — with two folders the historical rule
    /// counts.
    /// </summary>
    private static void WriteNeverAskedCourse(string coursesDir)
    {
        var config = new JsonObject
        {
            ["course_code"] = Code,
            ["course_name"] = "Physics",
            ["shared_folders"] = new JsonArray("Concepts", "Tasks", "Thinking Tasks"),
            ["per_section_folders"] = new JsonArray("All Classes"),
            ["shared_files"] = new JsonArray(),
            ["per_section_files"] = new JsonArray(),
            ["num_sections"] = 1,
            ["section_numbers"] = new JsonArray(1),
        };

        string dir = Path.Combine(coursesDir, Code);
        Directory.CreateDirectory(Path.Combine(dir, "section1"));
        // The folders must EXIST: the marks list is drawn from what is on disk
        // as well as from the lists, and the rule under test re-walks the
        // course after the removal is recorded.
        foreach (var name in config["shared_folders"]!.AsArray())
            Directory.CreateDirectory(Path.Combine(dir, name!.ToString()));
        foreach (var name in config["per_section_folders"]!.AsArray())
            Directory.CreateDirectory(Path.Combine(dir, "section1", name!.ToString()));
        File.WriteAllText(Path.Combine(dir, "section1", "index.md"), $"# {Code}\n", new UTF8Encoding(false));

        File.WriteAllText(Path.Combine(dir, "course_config.json"),
                          config.ToJsonString(new System.Text.Json.JsonSerializerOptions { WriteIndented = true }),
                          new UTF8Encoding(false));
    }

    [UiFact]
    public void RemovingAFolderLeavesANeverAskedCourseWithNoMarksPool()
    {
        using var app = new DrivenApp(WriteNeverAskedCourse);
        app.SelectCourse(Code);

        string configPath = Path.Combine(app.WorkspacePath, "courses", Code, "course_config.json");
        Assert.DoesNotContain("graded_folders", File.ReadAllText(configPath));   // the fixture, proved

        // The row's own button, found by the id FormBuilders gives it. A
        // BLOCKED row carries a different button entirely, so finding this one
        // is itself the assertion that the floor let the removal through.
        app.Find("remove:Tasks", "the remove button on the shared folder Tasks").AsButton().Invoke();

        // Removing a folder that counts for marks asks first, and the
        // confirmation's own promise is what the rule under test is keeping.
        var confirm = Retry.WhileNull(
            () => app.Window.FindAllDescendants(cf => cf.ByControlType(ControlType.Button))
                     .FirstOrDefault(b => Name(b) == "Remove"),
            TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result;
        Assert.True(confirm is not null, "the removal confirmation never appeared");
        confirm!.AsButton().Invoke();

        var save = Retry.WhileFalse(
            () => app.Find("saveButton", "the Save button").AsButton().IsEnabled,
            TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200));
        Assert.True(save.Result, "Save never became available after the removal");
        app.Find("saveButton", "the Save button").AsButton().Invoke();

        // Read back what was WRITTEN, waiting for it: Save is asynchronous and
        // an immediate read would test the fixture rather than the gesture.
        var written = Retry.WhileNull(() =>
        {
            var parsed = JsonNode.Parse(File.ReadAllText(configPath))!.AsObject();
            return parsed["shared_folders"]!.AsArray()
                       .Any(f => f!.ToString() == "Tasks") ? null : parsed;
        }, TimeSpan.FromSeconds(15), TimeSpan.FromMilliseconds(250)).Result;
        Assert.True(written is not null, "the removal never reached course_config.json");

        // The whole point: no key, rather than a key holding an empty list or
        // the historical rule's answer minus one folder.
        // The message is built from what is THERE — an assertion message that
        // reads the missing key crashes on the passing path, which is how the
        // first version of this test failed.
        Assert.False(written!.ContainsKey("graded_folders"),
            "a removal froze the marks pool on a course that had never been asked: "
            + (written["graded_folders"]?.ToJsonString() ?? "(absent)"));

        // And the removal itself really happened, so the assertion above is not
        // passing because nothing did.
        Assert.Contains("Tasks",
            written["excluded_items"]!["shared"]!.AsArray().Select(n => n!.ToString()));
    }

    private static string Name(AutomationElement element)
    {
        try { return element.Name ?? ""; } catch { return ""; }
    }
}

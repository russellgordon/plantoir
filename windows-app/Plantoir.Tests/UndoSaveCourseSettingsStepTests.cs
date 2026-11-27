using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W8-12 (the mac's U4a, <c>CourseConfiguration.writeAsOneStep</c>):
/// Save of Course Settings is ONE step, one <c>editJSON</c> per top-level
/// member whose VALUE the Save changes, keys sorted, made by <c>sheet</c>,
/// held by the course. Each before is the member as the file held it when the
/// step was planned (none when absent); a step refused because one of its own
/// members changed between plan and make is planned again, up to three times;
/// a Save that changes no value writes nothing and makes no step; Revert
/// writes nothing. Undo takes back only the step's own members.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class UndoSaveCourseSettingsStepTests : IDisposable
{
    // ---- Stored properties ---------------------------------------------------------

    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-save-course-settings-");

    // ---- Computed properties -------------------------------------------------------

    private string Folder => Path.Combine(_root, "wf");
    private string ListFolder => Path.Combine(_root, "state", "undo");
    private string CourseFolder => Path.Combine(Folder, "courses", "ICS3U");
    private string ConfigPath => Path.Combine(CourseFolder, "course_config.json");

    /// <summary>The recorded step's file, as the mac's fixture laid it and as its Save left it.</summary>
    private static JsonElement RecordedFile => WindowsActionsOnTheMacFixture.Recorded("saveCourseSettings").GetProperty("files")[0];

    private static byte[] RecordedBefore => WindowsActionsOnTheMacFixture.Bytes(RecordedFile.GetProperty("before"))!;

    // ---- Initializer ---------------------------------------------------------------

    public UndoSaveCourseSettingsStepTests()
    {
        Directory.CreateDirectory(Path.Combine(CourseFolder, "section1", "All Classes"));
        File.WriteAllText(Path.Combine(Folder, Workspace.MarkerLauncher), "");
        File.WriteAllBytes(ConfigPath, RecordedBefore);
    }

    // ---- Functions -------------------------------------------------------------------

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private UndoForThisProcess List(UndoMode mode = UndoMode.Shadow) => new(ListFolder, mode, null);

    private static UndoDoor Door(UndoForThisProcess list, UndoSeams? seams = null) =>
        new(list.Journal, list.Mode, list.Maintainers, seams: seams, trail: list.Trail);

    private Course TheCourse() => new("ICS3U", CourseFolder, CourseConfiguration.Load(ConfigPath));

    private static CourseConfiguration.SaveReport Save(Course course, UndoForThisProcess list, UndoSeams? seams = null) =>
        CourseConfiguration.SaveCourseSettings(course, list, Door(list, seams));

    private List<JsonObject> AppliedSteps()
    {
        var steps = new List<JsonObject>();
        foreach (JsonObject begin in WindowsActionsOnTheMacFixture.AppliedBegins(ListFolder)) steps.Add(begin["step"]!.AsObject());
        return steps;
    }

    private static List<JsonObject> Ops(JsonObject step)
    {
        var ops = new List<JsonObject>();
        foreach (JsonNode? op in step["ops"]!.AsArray()) ops.Add(op!.AsObject());
        return ops;
    }

    private void ChangeOnDisk(string key, JsonNode value)
    {
        JsonObject settings = JsonNode.Parse(File.ReadAllText(ConfigPath))!.AsObject();
        settings[key] = value;
        File.WriteAllText(ConfigPath, settings.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
    }

    private JsonObject OnDisk() => JsonNode.Parse(File.ReadAllText(ConfigPath))!.AsObject();

    [Fact]
    public void ASaveIsOneStepOfOneEditJsonPerChangedMemberKeysSorted()
    {
        Course course = TheCourse();
        course.Configuration.HiddenItems = ["Media"];
        course.Configuration.GradedFolders = ["Tests"];

        Save(course, List());

        JsonObject step = Assert.Single(AppliedSteps());
        Assert.Equal("saveCourseSettings", (string?)step["action"]!["key"]);
        Assert.Equal("sheet", (string?)step["madeBy"]);
        Assert.Equal("course", (string?)step["holds"]);
        Assert.Null(step["section"]);
        List<JsonObject> ops = Ops(step);
        Assert.Equal(2, ops.Count);
        Assert.All(ops, op => Assert.Equal(UndoOp.EditJson, (string?)op["kind"]));
        Assert.All(ops, op => Assert.Equal("courses/ICS3U/course_config.json", (string?)op["path"]));
        Assert.Equal("[\"graded_folders\"]", ops[0]["keyPath"]!.ToJsonString());
        Assert.Equal("[\"hidden\"]", ops[1]["keyPath"]!.ToJsonString());
        Assert.Equal("[\"Media\",\"Tasks\"]", ops[1]["before"]!.ToJsonString());
        Assert.Equal("[\"Media\"]", ops[1]["after"]!.ToJsonString());
        // The member rule's bytes, compact, the mac's recorded after byte for byte.
        Assert.Equal(WindowsActionsOnTheMacFixture.Bytes(RecordedFile.GetProperty("after")), File.ReadAllBytes(ConfigPath));
        Assert.False(course.Configuration.HasUnsavedChanges);
    }

    [Fact]
    public void AMemberAbsentBeforeHasNoBefore()
    {
        Course course = TheCourse();
        course.Configuration.GradedFolders = ["Tests"];

        Save(course, List());

        JsonObject op = Assert.Single(Ops(Assert.Single(AppliedSteps())));
        Assert.Equal("[\"graded_folders\"]", op["keyPath"]!.ToJsonString());
        Assert.False(op.ContainsKey("before"));
        Assert.Equal("[\"Tests\"]", op["after"]!.ToJsonString());
    }

    [Fact]
    public void AnotherMemberChangedBetweenPlanAndMakeIsOnDiskAndInThisCopy()
    {
        Course course = TheCourse();
        course.Configuration.HiddenItems = ["Media"];
        var seams = new UndoSeams { BeforeTheBegin = () => ChangeOnDisk("course_name", "Changed Elsewhere") };

        Save(course, List(), seams);

        Assert.Equal("Changed Elsewhere", (string?)OnDisk()["course_name"]);
        Assert.Equal("[\"Media\"]", OnDisk()["hidden"]!.ToJsonString(JsonSerializerOptions.Default));
        // This copy is the file as it is after the make, not the plan's read (U4a review 1, LOW 2).
        Assert.Equal("Changed Elsewhere", (string?)course.Configuration.Values["course_name"]);
        Assert.False(course.Configuration.HasUnsavedChanges);
    }

    [Fact]
    public void AnotherWindowsSaveOfAnotherMemberIsLeftAtUndo()
    {
        UndoForThisProcess list = List(UndoMode.Live);
        Course course = TheCourse();
        course.Configuration.HiddenItems = ["Media"];
        Save(course, list);
        // Another window, with its own copy, saves another member.
        Course other = TheCourse();
        other.Configuration.Values["course_name"] = "Saved In Another Window";
        other.Configuration.Write(ConfigPath);

        UndoOutcome outcome = Door(list).Undo();

        Assert.Equal(UndoOutcomeKind.Undone, outcome.Kind);
        Assert.Equal("[\"Media\",\"Tasks\"]", OnDisk()["hidden"]!.ToJsonString());
        Assert.Equal("Saved In Another Window", (string?)OnDisk()["course_name"]);
    }

    [Fact]
    public void TheStepsOwnMemberChangedAgainRefusesTheUndoNamingTheFile()
    {
        UndoForThisProcess list = List(UndoMode.Live);
        Course course = TheCourse();
        course.Configuration.HiddenItems = ["Media"];
        Save(course, list);
        ChangeOnDisk("hidden", new JsonArray("Other"));
        byte[] changed = File.ReadAllBytes(ConfigPath);

        UndoOutcome outcome = Door(list).Undo();

        Assert.Equal(UndoOutcomeKind.Refused, outcome.Kind);
        Assert.Equal(UndoRefusalKind.ChangedSince, outcome.Refusal!.Kind);
        Assert.EndsWith("course_config.json", outcome.Refusal.Path);
        Assert.True(outcome.ClearedTheList);
        Assert.Equal(changed, File.ReadAllBytes(ConfigPath));
    }

    [Fact]
    public void TheStepsOwnMemberChangedBetweenThePlanAndTheMakeRefusesTheStep()
    {
        Course course = TheCourse();
        course.Configuration.HiddenItems = ["Media"];
        UndoForThisProcess list = List();
        var step = new UndoActionStep(new UndoStepMaker("sheet", "saveCourseSettings"), Folder, "ICS3U", section: null,
                                      holds: "course", undo: list, door: Door(list));

        course.Configuration.PlanWrite(ConfigPath, step);
        // The befores are the plan's read: another window's hides are never written over.
        ChangeOnDisk("hidden", new JsonArray("Theirs"));
        byte[] theirs = File.ReadAllBytes(ConfigPath);
        var refused = Assert.Throws<UndoStepRefusedException>(step.Make);

        Assert.Equal(UndoRefusalKind.ChangedSince, refused.Refusal.Kind);
        Assert.Equal(theirs, File.ReadAllBytes(ConfigPath));
        Assert.Empty(AppliedSteps());
    }

    [Fact]
    public void AFourthRefusalInARowWritesNothingAndKeepsTheEditsUnsaved()
    {
        Course course = TheCourse();
        course.Configuration.HiddenItems = ["Media"];
        int races = 0;
        var seams = new UndoSeams
        {
            BeforeTheBegin = () =>
            {
                races++;
                ChangeOnDisk("hidden", new JsonArray($"Race {races}"));
            },
        };

        var refused = Assert.Throws<UndoStepRefusedException>(() => Save(course, List(), seams));

        Assert.Equal(4, races);
        Assert.Equal(UndoRefusalKind.ChangedSince, refused.Refusal.Kind);
        // The sheet shows "Could not save: " and this sentence, a teacher's.
        Assert.Equal("“course_config.json” was changed by another program while it was being saved.", refused.Message);
        Assert.Equal("[\"Race 4\"]", OnDisk()["hidden"]!.ToJsonString());
        Assert.True(course.Configuration.HasUnsavedChanges);
        Assert.Equal(new List<string> { "Media" }, course.Configuration.HiddenItems);
        Assert.Empty(AppliedSteps());
    }

    [Fact]
    public void ASettingsFileThatIsALinkIsSavedThroughTheLinkAndStaysALink()
    {
        string real = Path.Combine(CourseFolder, "real_config.json");
        File.Move(ConfigPath, real);
        File.CreateSymbolicLink(ConfigPath, real);
        Course course = TheCourse();
        course.Configuration.HiddenItems = ["Media"];

        Save(course, List());

        Assert.Equal(UndoLinks.What.Link, UndoLinks.Look(ConfigPath));
        Assert.Equal("[\"Media\"]", JsonNode.Parse(File.ReadAllText(real))!["hidden"]!.ToJsonString());
        JsonObject op = Assert.Single(Ops(Assert.Single(AppliedSteps())));
        Assert.Equal("courses/ICS3U/real_config.json", (string?)op["path"]);
        Assert.False(course.Configuration.HasUnsavedChanges);
    }

    [Fact]
    public void ASaveThatChangesNoValueWritesNothingAndMakesNoStep()
    {
        Course course = TheCourse();
        // Changed and changed back: no value differs from the file.
        course.Configuration.HiddenItems = ["Media"];
        course.Configuration.HiddenItems = ["Media", "Tasks"];

        Save(course, List());

        Assert.Empty(WindowsActionsOnTheMacFixture.BeginKeys(ListFolder));
        Assert.Equal(RecordedBefore, File.ReadAllBytes(ConfigPath));
    }

    [Fact]
    public void RevertWritesNothing()
    {
        Course course = TheCourse();
        course.Configuration.HiddenItems = ["Media"];

        Assert.True(course.Configuration.RevertToFile(ConfigPath));

        Assert.Empty(WindowsActionsOnTheMacFixture.BeginKeys(ListFolder));
        Assert.Equal(RecordedBefore, File.ReadAllBytes(ConfigPath));
        Assert.Equal(new List<string> { "Media", "Tasks" }, course.Configuration.HiddenItems);
        Assert.False(course.Configuration.HasUnsavedChanges);
    }
}

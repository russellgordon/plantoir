using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W8-11 (the mac's U4a, <c>SetSchoolYearSheet.write</c>): Set School
/// Year is ONE step, one <c>editJSON</c> op on <c>reference_school_year</c> in
/// the course's <c>course_config.json</c>, made by <c>sheet</c>, held by the
/// course, all or none. Its before is the member as the file held it when the
/// step was planned (no before when it was absent); its bytes move by the
/// member rule (<c>undo-json-cases.json</c> → <c>editJSONCases</c>); a file
/// that is not one JSON object is one <c>writeFile</c> of today's whole
/// bytes; a choice that changes nothing writes nothing and makes no step.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class UndoSetSchoolYearStepTests : IDisposable
{
    // ---- Stored properties ---------------------------------------------------------

    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-set-school-year-");
    private static readonly DateOnly Today = new(2026, 11, 20);

    // ---- Computed properties -------------------------------------------------------

    private string Folder => Path.Combine(_root, "wf");
    private string ListFolder => Path.Combine(_root, "state", "undo");
    private string CourseFolder => Path.Combine(Folder, "courses", "ICS3U");
    private string ConfigPath => Path.Combine(CourseFolder, "course_config.json");

    /// <summary>The recorded step's file, as the mac's fixture laid it and as its step left it.</summary>
    private static JsonElement RecordedFile => WindowsActionsOnTheMacFixture.Recorded("setSchoolYear").GetProperty("files")[0];

    // ---- Initializer ---------------------------------------------------------------

    public UndoSetSchoolYearStepTests()
    {
        Directory.CreateDirectory(Path.Combine(CourseFolder, "section1", "All Classes"));
        File.WriteAllText(Path.Combine(Folder, Workspace.MarkerLauncher), "");
    }

    // ---- Functions -------------------------------------------------------------------

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private UndoForThisProcess List() => new(ListFolder, UndoMode.Shadow, null);

    private UndoDoor Door(UndoForThisProcess list) => new(list.Journal, list.Mode, list.Maintainers, trail: list.Trail);

    private Course TheCourse() => new("ICS3U", CourseFolder, CourseConfiguration.Load(ConfigPath));

    private string? SetTheYear(Course course, int? year)
    {
        UndoForThisProcess list = List();
        return ReferenceCourseUpkeep.WriteSchoolYear(course, year, Today, list, Door(list));
    }

    private List<JsonObject> AppliedSteps()
    {
        var steps = new List<JsonObject>();
        foreach (JsonObject begin in WindowsActionsOnTheMacFixture.AppliedBegins(ListFolder)) steps.Add(begin["step"]!.AsObject());
        return steps;
    }

    private static byte[] Utf8(string text) => new UTF8Encoding(false).GetBytes(text);

    private UndoActionStep NewStep(UndoForThisProcess list) =>
        new(new UndoStepMaker("sheet", "setSchoolYear"), Folder, "ICS3U", section: null, holds: "course", undo: list, door: Door(list));

    [Fact]
    public void SettingTheYearIsOneStepOfOneEditJsonOnTheMember()
    {
        File.WriteAllBytes(ConfigPath, Utf8("{\n  \"course_code\" : \"ICS3U\",\n  \"reference_school_year\" : 2024,\n  \"num_sections\" : 1\n}"));

        Assert.Null(SetTheYear(TheCourse(), 2025));

        JsonObject step = Assert.Single(AppliedSteps());
        Assert.Equal("setSchoolYear", (string?)step["action"]!["key"]);
        Assert.Equal("sheet", (string?)step["madeBy"]);
        Assert.Equal("course", (string?)step["holds"]);
        Assert.Equal("ICS3U", (string?)step["course"]);
        Assert.Null(step["section"]);
        JsonObject op = Assert.Single(step["ops"]!.AsArray())!.AsObject();
        Assert.Equal(UndoOp.EditJson, (string?)op["kind"]);
        Assert.Equal("courses/ICS3U/course_config.json", (string?)op["path"]);
        Assert.Equal("[\"reference_school_year\"]", op["keyPath"]!.ToJsonString());
        Assert.Equal(2024, (int)op["before"]!);
        Assert.Equal(2025, (int)op["after"]!);
        // The member rule's bytes: only the member's value changes.
        Assert.Equal("{\n  \"course_code\" : \"ICS3U\",\n  \"reference_school_year\" : 2025,\n  \"num_sections\" : 1\n}", File.ReadAllText(ConfigPath));
    }

    [Fact]
    public void AMemberAbsentBeforeHasNoBeforeAndIsAddedByTheMemberRule()
    {
        File.WriteAllBytes(ConfigPath, WindowsActionsOnTheMacFixture.Bytes(RecordedFile.GetProperty("before"))!);

        Assert.Null(SetTheYear(TheCourse(), 2025));

        JsonObject step = Assert.Single(AppliedSteps());
        JsonObject op = Assert.Single(step["ops"]!.AsArray())!.AsObject();
        Assert.Equal(UndoOp.EditJson, (string?)op["kind"]);
        Assert.False(op.ContainsKey("before"));
        Assert.Equal(2025, (int)op["after"]!);
        // The mac's recorded after, byte for byte.
        Assert.Equal(WindowsActionsOnTheMacFixture.Bytes(RecordedFile.GetProperty("after")), File.ReadAllBytes(ConfigPath));
    }

    [Fact]
    public void FilingUnderNoYearTakesTheMemberOut()
    {
        File.WriteAllBytes(ConfigPath, WindowsActionsOnTheMacFixture.Bytes(RecordedFile.GetProperty("after"))!);

        Assert.Null(SetTheYear(TheCourse(), null));

        JsonObject op = Assert.Single(Assert.Single(AppliedSteps())["ops"]!.AsArray())!.AsObject();
        Assert.Equal(2025, (int)op["before"]!);
        Assert.False(op.ContainsKey("after"));
        Assert.Equal(WindowsActionsOnTheMacFixture.Bytes(RecordedFile.GetProperty("before")), File.ReadAllBytes(ConfigPath));
    }

    [Fact]
    public void AnotherMemberChangedByAnotherWindowBetweenPlanAndMakeIsLeft()
    {
        File.WriteAllBytes(ConfigPath, Utf8("{\n  \"course_code\" : \"ICS3U\",\n  \"course_name\" : \"Old\",\n  \"num_sections\" : 1\n}"));
        Course course = TheCourse();
        course.Configuration.SetReferenceSchoolYear(2025);
        UndoForThisProcess list = List();
        UndoActionStep step = NewStep(list);

        Assert.True(course.Configuration.PlanMemberWrite(ConfigPath, "reference_school_year", step));
        // Another window saves its own member between the plan and the make.
        File.WriteAllBytes(ConfigPath, Utf8("{\n  \"course_code\" : \"ICS3U\",\n  \"course_name\" : \"New\",\n  \"num_sections\" : 1\n}"));
        step.Make();

        Assert.Equal("{\n  \"course_code\" : \"ICS3U\",\n  \"course_name\" : \"New\",\n  \"num_sections\" : 1,\n  \"reference_school_year\" : 2025\n}",
                     File.ReadAllText(ConfigPath));
        JsonObject op = Assert.Single(Assert.Single(AppliedSteps())["ops"]!.AsArray())!.AsObject();
        Assert.Equal("[\"reference_school_year\"]", op["keyPath"]!.ToJsonString());
    }

    [Fact]
    public void TheYearChangedByAnotherWindowBetweenPlanAndMakeRefusesTheStep()
    {
        File.WriteAllBytes(ConfigPath, Utf8("{\n  \"course_code\" : \"ICS3U\",\n  \"reference_school_year\" : 2024\n}"));
        Course course = TheCourse();
        course.Configuration.SetReferenceSchoolYear(2025);
        UndoForThisProcess list = List();
        UndoActionStep step = NewStep(list);

        Assert.True(course.Configuration.PlanMemberWrite(ConfigPath, "reference_school_year", step));
        // The before is the plan's read: another window's year is never written over.
        byte[] theirs = Utf8("{\n  \"course_code\" : \"ICS3U\",\n  \"reference_school_year\" : 2023\n}");
        File.WriteAllBytes(ConfigPath, theirs);
        var refused = Assert.Throws<UndoStepRefusedException>(step.Make);

        Assert.Equal(UndoRefusalKind.ChangedSince, refused.Refusal.Kind);
        Assert.Equal(theirs, File.ReadAllBytes(ConfigPath));
        Assert.Empty(AppliedSteps());
    }

    [Fact]
    public void AFileThatIsNotJsonIsOneWriteFileOfTodaysWholeBytes()
    {
        File.WriteAllBytes(ConfigPath, Utf8("{\"course_code\":\"ICS3U\",\"num_sections\":1,\"section_numbers\":[1]}"));
        Course course = TheCourse();
        File.WriteAllBytes(ConfigPath, Utf8("this is not JSON {"));

        Assert.Null(SetTheYear(course, 2025));

        JsonObject op = Assert.Single(Assert.Single(AppliedSteps())["ops"]!.AsArray())!.AsObject();
        Assert.Equal(UndoOp.WriteFile, (string?)op["kind"]);
        JsonNode written = JsonNode.Parse(File.ReadAllText(ConfigPath))!;
        Assert.Equal(2025, (int)written["reference_school_year"]!);
        Assert.Equal("ICS3U", (string?)written["course_code"]);
    }

    /// <summary>
    /// W8-11 to 13 review 1, LOW 1: a file planned whole takes as its before
    /// the bytes the plan was built from, as the mac's
    /// <c>editJSON(at:read:members:[] leaving: whole)</c> does, never a
    /// second read of the disk. Bytes another program wrote after the plan's
    /// read are a change since the plan, refused at the make and kept.
    /// </summary>
    [Fact]
    public void AFilePlannedWholeTakesThePlansOwnReadAsItsBefore()
    {
        byte[] planRead = Utf8("this is not JSON {");
        byte[] theirs = Utf8("written by another program after the plan read the file");
        byte[] whole = Utf8("{\n  \"course_code\" : \"ICS3U\"\n}\n");
        File.WriteAllBytes(ConfigPath, theirs);
        UndoForThisProcess list = List();
        UndoActionStep step = NewStep(list);

        CourseConfiguration.PlanWhole(step, ConfigPath, new HeldFiles.FileBytes(HeldFiles.ReadOutcome.Read, planRead), whole);

        var planned = Assert.Single(step.ChangedFiles);
        Assert.Equal(planRead, planned.BeforeBytes);
        Assert.Throws<UndoStepRefusedException>(step.Make);
        Assert.Equal(theirs, File.ReadAllBytes(ConfigPath));
        Assert.Empty(AppliedSteps());
    }

    /// <summary>A file the plan found not there is planned whole with no before.</summary>
    [Fact]
    public void AFileNotThereWhenPlannedIsPlannedWholeWithNoBefore()
    {
        byte[] whole = Utf8("{\n  \"course_code\" : \"ICS3U\"\n}\n");
        UndoActionStep step = NewStep(List());

        CourseConfiguration.PlanWhole(step, ConfigPath, new HeldFiles.FileBytes(HeldFiles.ReadOutcome.NotThere, null), whole);

        var planned = Assert.Single(step.ChangedFiles);
        Assert.Null(planned.BeforeBytes);
        step.Make();
        Assert.Equal(whole, File.ReadAllBytes(ConfigPath));
    }

    public static IEnumerable<object[]> FilesAlreadyFiledUnder2025() =>
    [
        ["{\n  \"course_code\" : \"ICS3U\",\n  \"reference_school_year\" : 2025\n}"],
        // A key the member rule is not measured to walk (beyond printable
        // ASCII): the member cannot be moved, and still nothing is written.
        ["{\n  \"course_code\" : \"ICS3U\",\n  \"café\" : 1,\n  \"reference_school_year\" : 2025\n}"],
    ];

    [Theory]
    [MemberData(nameof(FilesAlreadyFiledUnder2025))]
    public void AChoiceThatChangesNothingWritesNothingAndMakesNoStep(string config)
    {
        byte[] before = Utf8(config);
        File.WriteAllBytes(ConfigPath, before);

        Assert.Null(SetTheYear(TheCourse(), 2025));

        Assert.Empty(WindowsActionsOnTheMacFixture.BeginKeys(ListFolder));
        Assert.Equal(before, File.ReadAllBytes(ConfigPath));
    }
}

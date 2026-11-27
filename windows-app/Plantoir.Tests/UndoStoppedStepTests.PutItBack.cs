using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W8c-1b (the mac's <c>SettingPutBackAlert</c>, <c>SetSchoolYearSheet.writeJudged</c>,
/// <c>CourseSettingsView.save</c>, <c>putBackOffer</c>, <c>putBack</c> and
/// <c>answerARenameOffer</c>): each of the three one-file settings callers
/// answers W8c-1a's door as the mac does, and only "could not finish" reaches
/// the teacher as something new, the ONE alert with the setting's own name
/// and old value. Every case runs a LIVE door.
/// </summary>
public sealed partial class UndoStoppedStepTests
{
    // ---- The trail ------------------------------------------------------------------

    /// <summary>The trail, in a file of this test's own, for <see cref="TrailSays"/>.</summary>
    private string TrailPath => Path.Combine(_root, "activity.txt");

    private void KeepTheTrail() => ActivityTrail.SetCustomLogPathForTesting(TrailPath);

    private static void PutTheTrailBack() => ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);

    private bool TrailSays(string line) => File.Exists(TrailPath) && File.ReadAllText(TrailPath).Contains(line, StringComparison.Ordinal);

    // ---- The rename's course ------------------------------------------------------------

    /// <summary>A per-section folder no section has: its rename is the settings file alone.</summary>
    private void TheSettingsNameLabs()
    {
        File.WriteAllBytes(ConfigPath, new UTF8Encoding(false).GetBytes(
            "{\n  \"course_code\" : \"ICS3U\",\n  \"course_name\" : \"Introduction to Computer Science\",\n  \"num_sections\" : 1,\n"
            + "  \"per_section_folders\" : [\"All Classes\", \"Labs\"]\n}"));
    }

    private Exception? RenameLabs(UndoForThisProcess list, UndoDoor door, string newName = "Workshop")
    {
        CourseConfiguration configuration = CourseConfiguration.Load(ConfigPath);
        var settings = SpecialFolderRenamer.RenamingTheSettings(configuration, ConfigPath, "Labs", newName, FolderScope.PerSection, CourseFolder);
        try
        {
            SpecialFolderRenamer.Rename("Labs", newName, FolderScope.PerSection, CourseFolder, new[] { 1 }, settings, false, list, door);
            return null;
        }
        catch (Exception error)
        {
            return error;
        }
    }

    private string FolderNamesOnDisk() =>
        JsonNode.Parse(File.ReadAllText(ConfigPath))!["per_section_folders"]!.ToJsonString();

    private string? CourseNameOnDisk() => (string?)JsonNode.Parse(File.ReadAllText(ConfigPath))!["course_name"];

    private Exception? Save(Course course, UndoForThisProcess list, UndoDoor door)
    {
        try
        {
            CourseConfiguration.SaveCourseSettings(course, list, door);
            return null;
        }
        catch (Exception error)
        {
            return error;
        }
    }

    // ---- The words ---------------------------------------------------------------------

    /// <summary>The offer's words are the contract's, read by key, placeholders filled; the buttons as the list says them. MUST FAIL with a sentence retyped.</summary>
    [Fact]
    public void TheOffersWordsAreTheContracts()
    {
        JsonObject wording = ContractLoader.LoadJson("shared-rules.json")["referenceCourses"]!["wording"]!.AsObject();
        var named = new SettingPutBackOffer(7, "course name", "Computer Studies");
        var together = new SettingPutBackOffer(8, "course settings", null);

        Assert.Equal(((string)wording["settingCouldNotBeChanged"]!).Replace("{setting}", "course name"), named.Title);
        Assert.Equal(((string)wording["settingCanBePutBack"]!).Replace("{value}", "Computer Studies"), named.InformativeText);
        Assert.Equal(((string)wording["settingCouldNotBeChanged"]!).Replace("{setting}", "course settings"), together.Title);
        Assert.Equal((string)wording["settingsCanBePutBack"]!, together.InformativeText);
        JsonArray buttons = wording["settingCouldNotBeChangedButtons"]!.AsArray();
        Assert.Equal((string)buttons[0]!, named.NotNowButton);
        Assert.Equal((string)buttons[1]!, named.PutItBackButton);
    }

    /// <summary>The sentence that names no file is the one the contract's note quotes for Save.</summary>
    [Fact]
    public void TheSentenceNamingNoFileIsTheNotesOwn()
    {
        string note = (string)ContractLoader.LoadJson("shared-rules.json")["referenceCourses"]!["wording"]!["settingCouldNotBeChangedNote"]!;
        Assert.Contains("'Could not save: " + SettingPutBack.NamingNoFile + "'", note, StringComparison.Ordinal);
    }

    // ---- The answer, whichever order the dialog runs ---------------------------------------

    /// <summary>
    /// Put It Back is the answer when its button was pressed, whether the
    /// press is seen before the close or only in the close's result; a close
    /// alone is Not Now (the mac's HIGH 1). MUST FAIL with the closing
    /// answered as Not Now before the button's action runs.
    /// </summary>
    [Theory]
    [InlineData(true, false, SettingPutBackAnswer.PutItBack)]
    [InlineData(false, true, SettingPutBackAnswer.PutItBack)]
    [InlineData(true, true, SettingPutBackAnswer.PutItBack)]
    [InlineData(false, false, SettingPutBackAnswer.NotNow)]
    public void TheButtonPressedDecidesTheAnswer(bool pressed, bool closedByIt, SettingPutBackAnswer expected) =>
        Assert.Equal(expected, SettingPutBack.AnswerOnceClosed(pressed, closedByIt));

    // ---- Set School Year's four outcomes -------------------------------------------------

    /// <summary>The new year: saved, nothing said, no offer.</summary>
    [Fact]
    public void SetSchoolYearHoldingTheNewYearIsSaved()
    {
        UndoForThisProcess list = List();
        Course course = CourseIn2026(list);

        SettingWriteResult result = ReferenceCourseUpkeep.WriteSchoolYearJudged(course, 2027, Today, list, Door(list, StopTheSwapPartWay(StoppedWith.TheNewValue)));

        Assert.IsType<SettingWriteResult.Saved>(result);
        Assert.Equal(2027, YearOnDisk());
    }

    /// <summary>The old year (retried, then refused) and neither year (never retried): <c>couldNotSetSchoolYear</c>, never an offer.</summary>
    [Theory]
    [InlineData("theOldValue", 5)]
    [InlineData("aThirdValue", 2)]
    public void SetSchoolYearHoldingTheOldYearOrNeitherSaysItsSentence(string word, int steps)
    {
        UndoForThisProcess list = List();
        Course course = CourseIn2026(list);

        SettingWriteResult result = ReferenceCourseUpkeep.WriteSchoolYearJudged(course, 2027, Today, list, Door(list, StopTheSwapPartWay(FileHolds(word))));

        var refused = Assert.IsType<SettingWriteResult.Refused>(result);
        Assert.Equal(ReferenceCourse.CouldNotSetSchoolYear("ICS3U"), refused.Sentence);
        Assert.Equal(steps, StepCount(list));
        Assert.Equal(0, InFlightCount(list));
    }

    /// <summary>
    /// Could not finish: the offer, "school year" and the old year as the
    /// picker labels it, its line on the trail, the step left in flight.
    /// </summary>
    [Fact]
    public void SetSchoolYearThatCannotFinishOffersTheOldYearByThePickersLabel()
    {
        KeepTheTrail();
        try
        {
            UndoForThisProcess list = List();
            Course course = CourseIn2026(list);

            SettingWriteResult result = ReferenceCourseUpkeep.WriteSchoolYearJudged(course, 2027, Today, list, Door(list, StopTheSwapPartWay(StoppedWith.Unreadable)));

            LetGoOfTheFile();
            var couldNotFinish = Assert.IsType<SettingWriteResult.CouldNotFinish>(result);
            Assert.Equal(new SettingPutBackOffer(2, "school year", "2026–27"), couldNotFinish.Offer);
            Assert.Equal("The school year could not be changed.", couldNotFinish.Offer.Title);
            Assert.Equal(1, InFlightCount(list));
            Assert.True(TrailSays(SettingPutBack.OfferedLine("school year", "ICS3U")));
            Assert.Equal(2026, (int?)course.Configuration.StoredReferenceSchoolYear);
        }
        finally { PutTheTrailBack(); }
    }

    /// <summary>A course with no year before offers the picker's own no-year label.</summary>
    [Fact]
    public void SetSchoolYearWithNoYearBeforeOffersThePickersNoYearLabel()
    {
        UndoForThisProcess list = List();

        SettingWriteResult result = ReferenceCourseUpkeep.WriteSchoolYearJudged(TheCourse(), 2027, Today, list,
            Door(list, StopTheSwapPartWay(StoppedWith.Unreadable)));

        LetGoOfTheFile();
        var couldNotFinish = Assert.IsType<SettingWriteResult.CouldNotFinish>(result);
        Assert.Equal(SchoolYear.PickerLabel(null), couldNotFinish.Offer.ValueBefore);
    }

    /// <summary>Put It Back writes the old year, closes the step and leaves its line; nothing said.</summary>
    [Fact]
    public void SetSchoolYearsPutItBackPutsTheOldYearBack()
    {
        KeepTheTrail();
        try
        {
            UndoForThisProcess list = List();
            Course course = CourseIn2026(list);
            var result = (SettingWriteResult.CouldNotFinish)ReferenceCourseUpkeep.WriteSchoolYearJudged(
                course, 2027, Today, list, Door(list, StopTheSwapPartWay(StoppedWith.Unreadable)));
            LetGoOfTheFile();

            string? said = SettingPutBack.AnswerForTheSchoolYear(SettingPutBackAnswer.PutItBack, result.Offer, course, Door(list));

            Assert.Null(said);
            Assert.Equal(2026, YearOnDisk());
            Assert.Equal(0, InFlightCount(list));
            Assert.Equal(UndoStepState.RolledBack, StateOf(list, 2));
            Assert.True(TrailSays(SettingPutBack.PutItBackLine("school year", "ICS3U", putBack: true)));
            Assert.Equal(2026, (int?)course.Configuration.StoredReferenceSchoolYear);
        }
        finally { PutTheTrailBack(); }
    }

    /// <summary>Not Now (the alert's close alone) writes nothing: the step stays in flight for the next launch, and its line is left.</summary>
    [Fact]
    public void NotNowWritesNothingAndLeavesTheStep()
    {
        KeepTheTrail();
        try
        {
            UndoForThisProcess list = List();
            Course course = CourseIn2026(list);
            var result = (SettingWriteResult.CouldNotFinish)ReferenceCourseUpkeep.WriteSchoolYearJudged(
                course, 2027, Today, list, Door(list, StopTheSwapPartWay(StoppedWith.Unreadable)));
            LetGoOfTheFile();
            byte[] onDisk = File.ReadAllBytes(ConfigPath);
            SettingPutBackAnswer closedAlone = SettingPutBack.AnswerOnceClosed(putItBackWasPressed: false, closedByPutItBack: false);

            string? said = SettingPutBack.AnswerForTheSchoolYear(closedAlone, result.Offer, course, Door(list));

            Assert.Null(said);
            Assert.Equal(onDisk, File.ReadAllBytes(ConfigPath));
            Assert.Equal(1, InFlightCount(list));
            Assert.True(TrailSays(SettingPutBack.NotNowLine("school year", "ICS3U")));
        }
        finally { PutTheTrailBack(); }
    }

    /// <summary>A Put It Back that fails too says <c>couldNotSetSchoolYear</c>, naming no file, and leaves its line.</summary>
    [Fact]
    public void SetSchoolYearsFailedPutItBackSaysItsOwnSentence()
    {
        KeepTheTrail();
        try
        {
            UndoForThisProcess list = List();
            Course course = CourseIn2026(list);
            var result = (SettingWriteResult.CouldNotFinish)ReferenceCourseUpkeep.WriteSchoolYearJudged(
                course, 2027, Today, list, Door(list, StopTheSwapPartWay(StoppedWith.Unreadable)));
            LetGoOfTheFile();
            File.WriteAllText(ConfigPath, File.ReadAllText(ConfigPath).Replace("2027", "2030", StringComparison.Ordinal));

            string? said = SettingPutBack.AnswerForTheSchoolYear(SettingPutBackAnswer.PutItBack, result.Offer, course, Door(list));

            Assert.Equal(ReferenceCourse.CouldNotSetSchoolYear("ICS3U"), said);
            Assert.DoesNotContain("course_config", said!, StringComparison.Ordinal);
            Assert.True(TrailSays(SettingPutBack.PutItBackLine("school year", "ICS3U", putBack: false)));
        }
        finally { PutTheTrailBack(); }
    }

    // ---- Save Course Settings' four outcomes ---------------------------------------------

    private UndoSeams StopTheNameChange(StoppedWith holding) =>
        StopTheSwapPartWay(holding, oldText: "Introduction to Computer Science", newText: "Computer Studies", thirdText: "Workshop");

    /// <summary>The new value: saved, nothing said.</summary>
    [Fact]
    public void SaveHoldingTheNewValueIsSaved()
    {
        UndoForThisProcess list = List();
        Course course = TheCourse();
        course.Configuration.Values["course_name"] = "Computer Studies";

        Assert.Null(Save(course, list, Door(list, StopTheNameChange(StoppedWith.TheNewValue))));

        Assert.Equal("Computer Studies", CourseNameOnDisk());
    }

    /// <summary>
    /// The old value (retried, then refused) and neither value (never
    /// retried): Save's failure line, naming NO file (the mac's LOW A2), no
    /// offer. MUST FAIL with a file name in the sentence.
    /// </summary>
    [Theory]
    [InlineData("theOldValue", 4)]
    [InlineData("aThirdValue", 1)]
    public void SaveHoldingTheOldValueOrNeitherSaysItsLineNamingNoFile(string word, int steps)
    {
        UndoForThisProcess list = List();
        Course course = TheCourse();
        course.Configuration.Values["course_name"] = "Computer Studies";

        Exception? thrown = Save(course, list, Door(list, StopTheNameChange(FileHolds(word))));

        Assert.NotNull(thrown);
        Assert.IsNotType<SettingCouldNotFinishException>(thrown);
        string line = CourseConfiguration.SaveFailureLine(thrown!);
        Assert.Equal("Could not save: " + SettingPutBack.NamingNoFile, line);
        Assert.DoesNotContain("course_config", line, StringComparison.Ordinal);
        Assert.Equal(steps, StepCount(list));
        Assert.Equal(0, InFlightCount(list));
        Assert.True(course.Configuration.HasUnsavedChanges);
    }

    /// <summary>
    /// Could not finish, one setting a teacher can be offered by name: "course
    /// name" with its old value, the offer line on the trail. MUST FAIL with
    /// Save's offer always "course settings".
    /// </summary>
    [Fact]
    public void SaveThatCannotFinishOffersTheCourseNameByName()
    {
        KeepTheTrail();
        try
        {
            UndoForThisProcess list = List();
            Course course = TheCourse();
            course.Configuration.Values["course_name"] = "Computer Studies";

            Exception? thrown = Save(course, list, Door(list, StopTheNameChange(StoppedWith.Unreadable)));

            LetGoOfTheFile();
            var couldNotFinish = Assert.IsType<SettingCouldNotFinishException>(thrown);
            Assert.Equal(new SettingPutBackOffer(1, "course name", "Introduction to Computer Science"), couldNotFinish.Offer);
            Assert.DoesNotContain("course_config", couldNotFinish.Message, StringComparison.Ordinal);
            Assert.Equal(1, InFlightCount(list));
            Assert.True(TrailSays("could not save the settings for ICS3U — stopped part way, offered to put back"));
        }
        finally { PutTheTrailBack(); }
    }

    /// <summary>Two settings changed at once: "course settings", put back together.</summary>
    [Fact]
    public void SaveOfSeveralSettingsThatCannotFinishOffersThemTogether()
    {
        UndoForThisProcess list = List();
        Course course = TheCourse();
        course.Configuration.Values["course_name"] = "Computer Studies";
        course.Configuration.Values["num_sections"] = 2;

        Exception? thrown = Save(course, list, Door(list, StopTheNameChange(StoppedWith.Unreadable)));

        LetGoOfTheFile();
        var couldNotFinish = Assert.IsType<SettingCouldNotFinishException>(thrown);
        Assert.Equal(new SettingPutBackOffer(1, "course settings", null), couldNotFinish.Offer);
        Assert.Equal(ReferenceCourse.SettingsCanBePutBack, couldNotFinish.Offer.InformativeText);
    }

    /// <summary>A setting not named one at a time is offered as the course settings too.</summary>
    [Fact]
    public void ASettingNotNamedOneAtATimeIsOfferedAsTheCourseSettings()
    {
        byte[] before = Encoding.UTF8.GetBytes("{\"course_code\":\"ICS3U\",\"num_sections\":1}");
        var wanted = Newtonsoft.Json.Linq.JObject.Parse("{\"course_code\":\"ICS3U\",\"num_sections\":2}");
        Assert.Equal(new SettingPutBackOffer(3, "course settings", null), CourseConfiguration.PutBackOffer(3, before, wanted));
    }

    /// <summary>Save's Put It Back writes the old name back, the copy reads the file again; a failed one says Save's line naming no file.</summary>
    [Fact]
    public void SavesPutItBackPutsTheOldNameBackAndAFailedOneNamesNoFile()
    {
        KeepTheTrail();
        try
        {
            UndoForThisProcess list = List();
            Course course = TheCourse();
            course.Configuration.Values["course_name"] = "Computer Studies";
            var offer = Assert.IsType<SettingCouldNotFinishException>(
                Save(course, list, Door(list, StopTheNameChange(StoppedWith.Unreadable)))).Offer;
            LetGoOfTheFile();

            Assert.Null(SettingPutBack.AnswerForASave(SettingPutBackAnswer.PutItBack, offer, course, Door(list)));

            Assert.Equal("Introduction to Computer Science", CourseNameOnDisk());
            Assert.Equal("Introduction to Computer Science", course.Configuration.CourseName);
            Assert.Equal(0, InFlightCount(list));
            Assert.True(TrailSays(SettingPutBack.PutItBackLine("course name", "ICS3U", putBack: true)));

            FreshFolders("failed");
            UndoForThisProcess second = List();
            Course again = TheCourse();
            again.Configuration.Values["course_name"] = "Computer Studies";
            var secondOffer = Assert.IsType<SettingCouldNotFinishException>(
                Save(again, second, Door(second, StopTheNameChange(StoppedWith.Unreadable)))).Offer;
            LetGoOfTheFile();
            File.WriteAllText(ConfigPath, File.ReadAllText(ConfigPath).Replace("Computer Studies", "Workshop", StringComparison.Ordinal));

            string? said = SettingPutBack.AnswerForASave(SettingPutBackAnswer.PutItBack, secondOffer, again, Door(second));

            Assert.Equal("Could not save: " + SettingPutBack.NamingNoFile, said);
        }
        finally { PutTheTrailBack(); }
    }

    // ---- Rename folder's four outcomes (moves no folder, relinks no page) ------------------

    private UndoSeams StopTheRename(StoppedWith holding) =>
        StopTheSwapPartWay(holding, oldText: "\"Labs\"", newText: "\"Workshop\"", thirdText: "\"Studio\"");

    /// <summary>The new name: renamed, its usual sentence.</summary>
    [Fact]
    public void ARenameHoldingTheNewNameIsRenamed()
    {
        TheSettingsNameLabs();
        UndoForThisProcess list = List();

        Assert.Null(RenameLabs(list, Door(list, StopTheRename(StoppedWith.TheNewValue))));

        Assert.Contains("Workshop", FolderNamesOnDisk(), StringComparison.Ordinal);
        Assert.Equal(0, InFlightCount(list));
    }

    /// <summary>The old name (retried, then refused) and neither (never retried): "was not renamed, and nothing was changed", no offer.</summary>
    [Theory]
    [InlineData("theOldValue", 4)]
    [InlineData("aThirdValue", 1)]
    public void ARenameHoldingTheOldNameOrNeitherWasNotRenamed(string word, int steps)
    {
        TheSettingsNameLabs();
        UndoForThisProcess list = List();

        Exception? thrown = RenameLabs(list, Door(list, StopTheRename(FileHolds(word))));

        var refused = Assert.IsType<SpecialFolderRenamer.RenameException>(thrown);
        Assert.StartsWith(SpecialNames.RenameFolderNothingWasChanged.Replace("{old}", "Labs").Replace("{said}", ""), refused.Message, StringComparison.Ordinal);
        Assert.Equal(steps, StepCount(list));
        Assert.Equal(0, InFlightCount(list));
    }

    /// <summary>
    /// Could not finish: the alert by "folder name" and the old name, the
    /// offer line under <c>folder renamed</c>, the step in flight. MUST FAIL
    /// with the could-not-finish skipped (the old "was not renamed" sentence).
    /// </summary>
    [Fact]
    public void ARenameThatCannotFinishOffersTheOldName()
    {
        KeepTheTrail();
        try
        {
            TheSettingsNameLabs();
            UndoForThisProcess list = List();

            Exception? thrown = RenameLabs(list, Door(list, StopTheRename(StoppedWith.Unreadable)));

            LetGoOfTheFile();
            var couldNotFinish = Assert.IsType<SettingCouldNotFinishException>(thrown);
            Assert.Equal(new SettingPutBackOffer(1, "folder name", "Labs"), couldNotFinish.Offer);
            Assert.Equal("Plantoir can put it back to Labs.", couldNotFinish.Offer.InformativeText);
            Assert.Equal(1, InFlightCount(list));
            Assert.True(TrailSays(SettingPutBack.OfferedLine("folder name Labs", "ICS3U")));
        }
        finally { PutTheTrailBack(); }
    }

    /// <summary>The rename's Put It Back writes the old name back; Not Now leaves its line; a failed one says <c>renameFolderStoppedPartWay</c>, naming no file.</summary>
    [Fact]
    public void ARenamesAnswersLeaveTheirLinesAndAFailedPutBackNamesNoFile()
    {
        KeepTheTrail();
        try
        {
            TheSettingsNameLabs();
            UndoForThisProcess list = List();
            var offer = Assert.IsType<SettingCouldNotFinishException>(RenameLabs(list, Door(list, StopTheRename(StoppedWith.Unreadable)))).Offer;
            LetGoOfTheFile();
            Course course = TheCourse();

            Assert.Null(SettingPutBack.AnswerForARename(SettingPutBackAnswer.NotNow, offer, course, Door(list)));
            Assert.True(TrailSays(SettingPutBack.NotNowLine("folder name Labs", "ICS3U")));
            Assert.Equal(1, InFlightCount(list));

            Assert.Null(SettingPutBack.AnswerForARename(SettingPutBackAnswer.PutItBack, offer, course, Door(list)));
            Assert.Contains("Labs", FolderNamesOnDisk(), StringComparison.Ordinal);
            Assert.DoesNotContain("Workshop", FolderNamesOnDisk(), StringComparison.Ordinal);
            Assert.True(TrailSays(SettingPutBack.PutItBackLine("folder name Labs", "ICS3U", putBack: true)));

            FreshFolders("renameFailed");
            TheSettingsNameLabs();
            UndoForThisProcess second = List();
            var secondOffer = Assert.IsType<SettingCouldNotFinishException>(RenameLabs(second, Door(second, StopTheRename(StoppedWith.Unreadable)))).Offer;
            LetGoOfTheFile();
            File.WriteAllText(ConfigPath, File.ReadAllText(ConfigPath).Replace("\"Workshop\"", "\"Studio\"", StringComparison.Ordinal));

            string? said = SettingPutBack.AnswerForARename(SettingPutBackAnswer.PutItBack, secondOffer, TheCourse(), Door(second));

            Assert.Equal(SpecialNames.RenameFolderStoppedPartWay.Replace("{old}", "Labs").Replace("{said}", SettingPutBack.NamingNoFile), said);
            Assert.DoesNotContain("course_config", said!, StringComparison.Ordinal);
            Assert.True(TrailSays(SettingPutBack.PutItBackLine("folder name Labs", "ICS3U", putBack: false)));
        }
        finally { PutTheTrailBack(); }
    }
}

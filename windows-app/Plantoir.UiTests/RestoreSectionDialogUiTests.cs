using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;
using Plantoir.Core.Models;

namespace Plantoir.UiTests;

/// <summary>
/// Restore from Backup… for a backup made for ONE section (#911 step 4), read
/// through UI Automation in the real window: the one question has Restore
/// Section 1, Restore Whole Course and Cancel, in that order (the order the
/// app's other three-button questions use: primary, secondary, close);
/// Escape is Cancel and archives nothing; Enter is the default, Restore
/// Section 1, which archives the course, puts the section back and shows
/// the finished sentence in the result dialog. The backup is a real one made
/// by <see cref="CourseArchiver.BackUpCourse"/> for Section 1 from the
/// Section menu; every wait is on a condition, never a fixed delay.
/// </summary>
[Collection("drives the real app")]
public class RestoreSectionDialogUiTests
{
    private const string Code = "RSD3U";
    private static readonly TimeSpan Patience = TimeSpan.FromSeconds(15);

    private static string Lesson(DrivenApp app) =>
        Path.Combine(app.WorkspacePath, "courses", Code, "section1", "All Classes", "Lesson.md");

    private static int ArchivedCount(DrivenApp app) => Workspace.FindArchivedItems(app.WorkspacePath).Count;

    private static AutomationElement OpenTheRestoreQuestion(DrivenApp app, string backupName)
    {
        app.PressRowMenuItem("backupsGroup", "All Backups…");
        var row = Retry.WhileNull(() => app.OpenDialog()?.FindFirstDescendant(cf => cf.ByAutomationId("allBackups-" + backupName)),
                                  Patience).Result;
        Assert.True(row is not null, "All Backups does not list the backup");
        app.RightClickMiddleOf(row!);
        var restore = Retry.WhileNull(() => app.Desktop.FindFirstDescendant(cf => cf.ByName("Restore…").And(cf.ByControlType(ControlType.MenuItem))),
                                      Patience).Result;
        Assert.True(restore is not null, "the backup's menu offers no Restore…");
        DrivenApp.PressMenuItem(restore!);
        var question = Retry.WhileNull(() =>
        {
            var dialog = app.OpenDialog();
            var primary = dialog?.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"));
            return primary?.Name == OneSectionRestoreWording.RestoreSectionButton(1) ? dialog : null;
        }, Patience).Result;
        Assert.True(question is not null, "Restore… did not ask the one-section question");
        return question!;
    }

    [UiFact]
    public void TheOneSectionQuestionHasThreeButtons_EscapeCancels_EnterRestoresTheSection()
    {
        string backupName = "";
        using var app = new DrivenApp(courses =>
        {
            EndToEnd.WriteCourse(courses, Code, "Restore Section Course", new[] { "Concepts" });
            string lesson = Path.Combine(courses, Code, "section1", "All Classes", "Lesson.md");
            File.WriteAllText(lesson, "as backed up");
            var course = Workspace.DiscoverCourses(Path.GetDirectoryName(courses)!).First(found => found.Code == Code);
            backupName = Path.GetFileName(CourseArchiver.BackUpCourse(course, courses, new BackupMaker.Menu(1, SubjectMenuLayout.Menu.Section)));
            File.WriteAllText(lesson, "changed since");
        });

        var question = OpenTheRestoreQuestion(app, backupName);
        var primary = question.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"))!;
        var secondary = question.FindFirstDescendant(cf => cf.ByAutomationId("SecondaryButton"));
        var close = question.FindFirstDescendant(cf => cf.ByAutomationId("CloseButton"));
        Assert.True(secondary is not null && close is not null, "the question does not have three buttons");
        Assert.Equal(OneSectionRestoreWording.RestoreWholeCourseButton, secondary!.Name);
        Assert.Equal("Cancel", close!.Name);
        Assert.True(question.FindFirstDescendant(cf => cf.ByName(OneSectionRestoreWording.Title(Code))) is not null, "the question's title is not the contract's");
        Assert.True(primary.BoundingRectangle.Left < secondary.BoundingRectangle.Left
                    && secondary.BoundingRectangle.Left < close.BoundingRectangle.Left,
                    "the buttons are not in the order Restore Section 1, Restore Whole Course, Cancel");

        // Escape is Cancel: the question goes, nothing is archived, nothing changes.
        CopyAPageEscapeUiTests.Front(app);
        FlaUI.Core.Input.Keyboard.Type(VirtualKeyShort.ESCAPE);
        Assert.True(Retry.WhileFalse(() => app.OpenDialog() is null, Patience).Result, "Escape left the question up");
        Assert.Equal(0, ArchivedCount(app));
        Assert.Equal("changed since", File.ReadAllText(Lesson(app)));

        // Enter is the default: Restore Section 1.
        OpenTheRestoreQuestion(app, backupName);
        CopyAPageEscapeUiTests.Front(app);
        FlaUI.Core.Input.Keyboard.Type(VirtualKeyShort.RETURN);
        var done = Retry.WhileNull(() => app.OpenDialog()?.FindFirstDescendant(cf => cf.ByName(OneSectionRestoreWording.DoneTitle(1, Code))),
                                   TimeSpan.FromSeconds(60)).Result;
        Assert.True(done is not null, "Enter did not restore the section (no finished dialog): " + string.Join("; ", app.Answered));
        Assert.Equal("as backed up", File.ReadAllText(Lesson(app)));
        Assert.Equal(1, ArchivedCount(app));
        app.OpenDialog()!.FindFirstDescendant(cf => cf.ByAutomationId("CloseButton"))!.AsButton().Invoke();
        Assert.True(Retry.WhileFalse(() => app.OpenDialog() is null, Patience).Result, "the finished dialog did not close on OK");
    }
}

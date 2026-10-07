using Plantoir.Core.Models;

namespace Plantoir.UiTests;

/// <summary>
/// #428 item 5: a run's temporary folder goes even when it holds a course
/// kept for reference, wherever in the run folder that course is. Plain facts,
/// not [UiFact]s — no desktop and no app — so they run in any <c>dotnet
/// test</c> of this project, beside <see cref="AssertAbsentRuleTests"/>.
/// </summary>
public class RunFolderTeardownTests
{
    private static string LockedCourse(string coursesDir, string name)
    {
        string course = Path.Combine(coursesDir, name);
        Directory.CreateDirectory(Path.Combine(course, "section1"));
        File.WriteAllText(Path.Combine(course, "section1", "index.md"), "# Section 1\n");
        File.WriteAllText(Path.Combine(course, "course_config.json"), "{}");
        ReferenceLock.Lock(course);
        return course;
    }

    [Fact]
    public void ALockedReferenceCourseAnywhereInTheRunFolderDoesNotKeepItBehind()
    {
        string root = Path.Combine(Path.GetTempPath(), "plantoir-ui-teardown-" + Guid.NewGuid().ToString("N")[..8]);
        try
        {
            LockedCourse(Path.Combine(root, "workspace", "courses"), "ICS3U-2025");
            // Last year's working folder, kept beside this run's by the import test.
            LockedCourse(Path.Combine(root, "last year", "courses"), "UIREF4");

            // The precondition that makes this test worth having: the lock bites.
            Assert.ThrowsAny<Exception>(() => Directory.Delete(root, recursive: true));
            Assert.True(Directory.Exists(root));

            Assert.True(DrivenApp.DeleteRunFolder(root), "the run folder was left behind");
            Assert.False(Directory.Exists(root));
        }
        finally
        {
            if (Directory.Exists(root))
            {
                ReferenceLock.Unlock(root);
                Directory.Delete(root, recursive: true);
            }
        }
    }

    [Fact]
    public void AFolderThatIsAlreadyGoneIsGone() =>
        Assert.True(DrivenApp.DeleteRunFolder(Path.Combine(Path.GetTempPath(), "plantoir-ui-never-" + Guid.NewGuid().ToString("N"))));
}

using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The other half of "A scheduled deploy needs its own path to the same
/// record" — applying the sentinel a scheduled deploy's wrapper script
/// leaves behind, since <see cref="ScheduledDeployCompletion.PendingDirectory"/>
/// and <see cref="ActivityTrail"/> are both process-wide state.
/// </summary>
[Collection(SharedActivityState.Name)]
public class ScheduledDeployCompletionTests : IDisposable
{
    private readonly string _originalLogPath;
    private readonly string _tempLogPath;

    public ScheduledDeployCompletionTests()
    {
        _originalLogPath = ActivityTrail.CurrentLogPath;
        _tempLogPath = Path.Combine(Directory.CreateTempSubdirectory("scheduled-deploy-completion-tests").FullName, "activity.txt");
        ActivityTrail.SetCustomLogPathForTesting(_tempLogPath);
    }

    // Restore the path this class FOUND, never null. Null does not mean
    // "no override", it means "use the teacher's real activity.txt" - so
    // this line used to switch every test class that ran after it onto
    // %LOCALAPPDATA%\Plantoir\Logs\activity.txt, defeating the
    // [ModuleInitializer] redirect in TestTrailRedirect for the rest of the
    // process. It had already put 263 lines about fixture courses into the
    // real trail on this machine - the same file a problem report gathers,
    // where a course that never existed reads as a fault that never
    // happened. Found by review, 2026-09-05; the field was already here and
    // simply never used.
    public void Dispose() => ActivityTrail.SetCustomLogPathForTesting(_originalLogPath);

    private static string NewCourseDirectory()
    {
        string path = Directory.CreateTempSubdirectory("scheduled-deploy-completion-course").FullName;
        Directory.CreateDirectory(Path.Combine(path, "section3"));
        return path;
    }

    private static void WriteSentinel(string pendingDir, string courseCode, int section, string courseDirectory,
                                      string fingerprint, string destinationTypesJson = "[\"local_folder\"]")
    {
        Directory.CreateDirectory(pendingDir);
        string json = $$"""
        {
          "courseCode": "{{courseCode}}",
          "sectionNumber": {{section}},
          "courseDirectory": {{System.Text.Json.JsonSerializer.Serialize(courseDirectory)}},
          "fingerprint": "{{fingerprint}}",
          "destinationTypes": {{destinationTypesJson}},
          "destinationNames": ["your folder"],
          "completedAtUtc": "2026-08-22T11:00:00Z"
        }
        """;
        File.WriteAllText(Path.Combine(pendingDir, Guid.NewGuid().ToString("N") + ".json"), json);
    }

    [Fact]
    public void ConsumePending_StampsPublishState_AndDeletesTheSentinel()
    {
        string pendingDir = Directory.CreateTempSubdirectory("scheduled-deploy-completion-pending").FullName;
        string courseDir = NewCourseDirectory();
        string fingerprint = SectionPublishState.Fingerprint(courseDir, sectionNumber: 3);
        WriteSentinel(pendingDir, "ICS3U", 3, courseDir, fingerprint);

        ScheduledDeployCompletion.ConsumePendingFrom(pendingDir);

        Assert.Empty(Directory.EnumerateFiles(pendingDir));
        var stamp = SectionPublishState.ReadStamp(courseDir, 3);
        Assert.NotNull(stamp);
        Assert.Equal(fingerprint, stamp!.Fingerprint);
        Assert.False(SectionPublishState.HasUnpublishedEdits(courseDir, 3));
    }

    [Fact]
    public void ConsumePending_NotesTheTrail()
    {
        string pendingDir = Directory.CreateTempSubdirectory("scheduled-deploy-completion-pending").FullName;
        string courseDir = NewCourseDirectory();
        string fingerprint = SectionPublishState.Fingerprint(courseDir, sectionNumber: 3);
        WriteSentinel(pendingDir, "ICS3U", 3, courseDir, fingerprint);

        ScheduledDeployCompletion.ConsumePendingFrom(pendingDir);

        string logged = File.ReadAllText(_tempLogPath);
        Assert.Contains("ICS3U/3", logged);
        Assert.Contains("marked ICS3U-S3", logged);
        Assert.Contains("scheduled deploy", logged);
    }

    [Fact]
    public void ConsumePending_DeletesAMalformedSentinel_WithoutThrowing()
    {
        string pendingDir = Directory.CreateTempSubdirectory("scheduled-deploy-completion-pending").FullName;
        File.WriteAllText(Path.Combine(pendingDir, "broken.json"), "{ not json");

        var exception = Record.Exception(() => ScheduledDeployCompletion.ConsumePendingFrom(pendingDir));

        Assert.Null(exception);
        Assert.Empty(Directory.EnumerateFiles(pendingDir));
    }

    [Fact]
    public void ConsumePending_SkipsACourseThatNoLongerExists_ButStillDeletesTheSentinel()
    {
        string pendingDir = Directory.CreateTempSubdirectory("scheduled-deploy-completion-pending").FullName;
        string vanishedCourseDir = Path.Combine(Path.GetTempPath(), "scheduled-deploy-completion-vanished-" + Guid.NewGuid().ToString("N"));
        WriteSentinel(pendingDir, "ICS3U", 1, vanishedCourseDir, "deadbeef");

        ScheduledDeployCompletion.ConsumePendingFrom(pendingDir);

        Assert.Empty(Directory.EnumerateFiles(pendingDir));
    }

    [Fact]
    public void ConsumePending_WithNothingPending_DoesNothing()
    {
        string pendingDir = Path.Combine(Path.GetTempPath(), "scheduled-deploy-completion-never-created-" + Guid.NewGuid().ToString("N"));

        var exception = Record.Exception(() => ScheduledDeployCompletion.ConsumePendingFrom(pendingDir));

        Assert.Null(exception);
    }
}

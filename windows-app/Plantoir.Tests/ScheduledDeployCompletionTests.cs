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

    public void Dispose() => ActivityTrail.SetCustomLogPathForTesting(null);

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

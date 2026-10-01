using Plantoir.Core.Assist;

namespace Plantoir.Tests;

/// <summary>
/// Bundle 6a ruling 1 (#360, mac #351): while plantoir-mcp zips the assistant's
/// copy of a course, the course is BUSY — Plantoir's Preview and Deploy, a
/// scheduled publish and another assistant stand off, and an assistant is told
/// <c>courseIsBeingCopied</c>.
/// </summary>
public class CourseBeingCopiedTests
{
    private static WorkLease.Other Copy(int pid) => new("ICS3U", WorkLease.Copying, pid, null, Alive: true);

    [Fact]
    public void ACopyBeingZippedStopsEveryBuilder()
    {
        Assert.NotNull(WorkLease.FirstInTheWay(WorkLease.Asker.ABuild, "ICS3U", 1, null, new[] { Copy(2) }));
        Assert.NotNull(WorkLease.FirstInTheWay(WorkLease.Asker.AScheduledPublish, "ICS3U", 1, null, new[] { Copy(2) }));
        // Its own process's copy is not in its own way (the assistant rebuilds after its own zip).
        Assert.Null(WorkLease.FirstInTheWay(WorkLease.Asker.ABuild, "ICS3U", 2, null, new[] { Copy(2) }));
    }

    [Fact]
    public void TheZipHoldsTheLeaseAndTheRefusalSaysACopyIsBeingSaved()
    {
        Assert.Equal(
            ContractLoader.LoadJson("assist-wording.json")["wording"]!["courseIsBeingCopied"]!.ToString().Replace("{course}", "X"),
            AssistWording.CourseIsBeingCopied("X"));
        string source = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot,
            "windows-app", "Plantoir.Core", "Assist", "AssistWorkspace.cs"));
        int door = source.IndexOf("private string AssistantBackup(", StringComparison.Ordinal);
        Assert.True(door >= 0);
        Assert.Contains("WorkLease.Take(_folder, course.Code, WorkLease.Copying)",
            source.Substring(door, source.IndexOf("CourseArchiver.BackUpCourse", door, StringComparison.Ordinal) - door));
    }
}

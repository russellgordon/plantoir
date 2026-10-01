using Plantoir.Core.Assist;

namespace Plantoir.Tests;

/// <summary>
/// #155 / #337: "is anything working that closing or replacing Plantoir would
/// cut short?" A running outside-assistant server is stood in for by a FAKE
/// pid list — never by finding or touching a real plantoir-mcp.
/// </summary>
public class MachineWorkTests : IDisposable
{
    private readonly string _folder = Path.Combine(Path.GetTempPath(), $"plantoir-machinework-{Guid.NewGuid():N}");

    public MachineWorkTests() => Directory.CreateDirectory(Activity);

    public void Dispose() { try { Directory.Delete(_folder, recursive: true); } catch { } }

    private string Activity => Path.Combine(_folder, "courses", ".internal", "activity");

    [Fact]
    public void NothingRunningIsNotBusy() =>
        Assert.Null(MachineWork.WhyBusy(MachineWork.Read(new[] { _folder }, () => Array.Empty<int>())));

    [Fact]
    public void AnyRunningAssistantServerIsBusy()
    {
        string? why = MachineWork.WhyBusy(MachineWork.Read(new[] { _folder }, () => new[] { 424242 }));
        Assert.NotNull(why);
        Assert.Contains("424242", why);
    }

    [Fact]
    public void ALiveLeaseOfAnotherProcessIsBusy()
    {
        var snapshot = new MachineWork.Snapshot(
            new[] { (_folder, new WorkLease.Other("ICS3U", WorkLease.Publishing, 4242, null, Alive: true)) },
            Array.Empty<int>());
        Assert.Equal("Plantoir is publishing ICS3U (pid 4242).", MachineWork.WhyBusy(snapshot));
    }

    [Fact]
    public void AStaleLeaseFileIsNotBusy()
    {
        // A pid that cannot be running: Others() reads it, the liveness rule drops it.
        File.WriteAllText(Path.Combine(Activity, "ICS3U.build.2147483646.lease"), "Plantoir\n\n2026-10-01T00:00:00.0000000Z\n");
        Assert.Null(MachineWork.WhyBusy(MachineWork.Read(new[] { _folder }, () => Array.Empty<int>())));
    }

    [Fact]
    public void ASweepRemovesOnlyTheKilledProcesssLeases()
    {
        string mine = Path.Combine(Activity, "ICS3U.preview.111.lease");
        string theirs = Path.Combine(Activity, "ICS3U.publish.222.lease");
        File.WriteAllText(mine, "x");
        File.WriteAllText(theirs, "x");
        var removed = MachineWork.SweepLeasesOf(111, new[] { _folder });
        Assert.Equal(new[] { mine }, removed);
        Assert.True(File.Exists(theirs), "Another program's lease was swept: that is live work.");
    }
}

using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// #303: a trail line must not be dropped because ANOTHER process has the
/// file open to write at the same instant. The app, plantoir-mcp.exe and a
/// scheduled run all write <c>activity.txt</c>; the old append opened with
/// <c>FileShare.Read</c>, so the second writer's open threw a sharing
/// violation into an empty catch and the line was gone, silently.
/// </summary>
/// <remarks>
/// The cross-PROCESS number (4,444 of 5,000 kept before, 5,000 of 5,000
/// after, on this Windows PC) comes from a two-process harness recorded in
/// documentation/09 → "Two writers at once"; a test host cannot start a
/// second copy of itself cheaply. What a unit test CAN hold is the cause:
/// another writer's open handle, which is exactly what the other process
/// holds for the length of its own write.
/// </remarks>
[Collection(SharedActivityState.Name)]
public class ActivityTrailWritersTests : IDisposable
{
    private readonly string _path = Path.Combine(Path.GetTempPath(), "plantoir-tests",
        "trail-writers-" + Guid.NewGuid().ToString("N") + ".txt");

    public ActivityTrailWritersTests()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        ActivityTrail.SetCustomLogPathForTesting(_path);
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { File.Delete(_path); } catch { }
    }

    [Fact]
    public void ALineIsKeptWhileAnotherWriterHasTheFileOpen()
    {
        // What another process holds while it appends: the file open for
        // writing, shared for reading and writing.
        using (var other = new FileStream(_path, FileMode.Append, FileAccess.Write,
                   FileShare.ReadWrite | FileShare.Delete))
        {
            ActivityTrail.Note(ActivityTrail.Event.TaskStarted, "written while another writer held the file");
        }

        Assert.Contains("written while another writer held the file", File.ReadAllText(_path));
    }

    [Fact]
    public void ALineIsKeptWhileAReaderHasTheFileOpen()
    {
        // A problem report reading the trail while a line is written.
        using (var reader = new FileStream(_path, FileMode.OpenOrCreate, FileAccess.Read,
                   FileShare.ReadWrite | FileShare.Delete))
        {
            ActivityTrail.Note(ActivityTrail.Event.TaskStarted, "written while a reader held the file");
        }

        Assert.Contains("written while a reader held the file", File.ReadAllText(_path));
    }

    [Fact]
    public void LinesFromManyThreadsAtOnceAreAllKeptWhole()
    {
        Parallel.For(0, 400, i =>
            ActivityTrail.Note(ActivityTrail.Event.TaskStarted, $"parallel line {i:D3} end"));

        var lines = File.ReadAllLines(_path).Where(line => line.Contains("parallel line")).ToList();
        Assert.Equal(400, lines.Count);
        Assert.All(lines, line => Assert.EndsWith(" end", line));
    }
}

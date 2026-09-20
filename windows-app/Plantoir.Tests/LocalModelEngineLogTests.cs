using Plantoir.Core.Assist;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// Pins <see cref="LocalModel.LinesSinceLastLook"/> — the "since last look"
/// half of sampling the engine's own output onto the activity trail. Mirrors
/// the intent of mac's file-based <c>AssistServerHost.lines(in:since:atMost:)</c>
/// tests, adapted to Windows' in-memory ring buffer (the engine's stdout/
/// stderr are drained by event handlers rather than written to a file — see
/// <c>LocalModel.Start</c> for why that is equally safe against the pipe
/// wedge those mac tests guard).
/// </summary>
public class LocalModelEngineLogTests
{
    [Fact]
    public void EachLookShowsOnlyWhatIsNew()
    {
        var model = new LocalModel(AssistModelTier.Small);
        model.NoteServerLine("first");
        model.NoteServerLine("second");

        long mark = 0;
        Assert.Equal(new[] { "first", "second" }, model.LinesSinceLastLook(ref mark));
        Assert.Empty(model.LinesSinceLastLook(ref mark));

        model.NoteServerLine("third");
        Assert.Equal(new[] { "third" }, model.LinesSinceLastLook(ref mark));
    }

    [Fact]
    public void ALogChattierThanTheBufferSkipsItsOldestLinesRatherThanFail()
    {
        var model = new LocalModel(AssistModelTier.Small);
        long mark = 0;

        // More than the 60-line buffer, all before the first look.
        for (int i = 0; i < 90; i++)
        {
            model.NoteServerLine($"line {i}");
        }

        var lines = model.LinesSinceLastLook(ref mark);
        // Only the most recent 60 survive in the buffer; the earliest of
        // those still counts as "new" since mark started at zero.
        Assert.Equal(60, lines.Count);
        Assert.Equal("line 30", lines[0]);
        Assert.Equal("line 89", lines[^1]);

        // Nothing new since.
        Assert.Empty(model.LinesSinceLastLook(ref mark));
    }
}

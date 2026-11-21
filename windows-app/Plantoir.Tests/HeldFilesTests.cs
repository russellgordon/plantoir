using System.Text;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The one helper for a file another program holds for a moment (#953, #874):
/// asked again for <see cref="HeldFiles.Pauses"/>, then the truth. Every hold
/// here is a REAL open handle with the share mode that matters, never a flag;
/// the pause is the test's own, so "the hold ends inside the bound" is driven
/// (the holder lets go on the first pause) and "not a hold" is a count of zero.
/// </summary>
public sealed class HeldFilesTests : IDisposable
{
    private readonly string _dir = Directory.CreateTempSubdirectory("held-files-").FullName;

    public void Dispose()
    {
        foreach (string file in Directory.EnumerateFiles(_dir))
            try { File.SetAttributes(file, FileAttributes.Normal); } catch { }
        try { Directory.Delete(_dir, true); } catch { }
    }

    private string Target(string text = "before")
    {
        string path = Path.Combine(_dir, "target.json");
        File.WriteAllText(path, text);
        return path;
    }

    private static FileStream Hold(string path, FileShare share) => new(path, FileMode.Open, FileAccess.Read, share);

    private void RenameOnto(string target, string text, Action<int> pause)
    {
        string temporary = HeldFiles.TemporaryBeside(target);
        File.WriteAllText(temporary, text);
        try { HeldFiles.Replace(temporary, target, () => File.Move(temporary, target, overwrite: true), pause); }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    [Fact]
    public void ARenameOntoAHeldFileIsAskedAgainForTheBoundThenSaidAsInUse()
    {
        string target = Target();
        var pauses = new List<int>();
        using (Hold(target, FileShare.Read))
        {
            var refused = Assert.Throws<FileInUseException>(() => RenameOnto(target, "after", pauses.Add));
            Assert.Equal("target.json is in use by another program, so nothing was changed.", refused.Message);
            Assert.Equal(unchecked((int)0x80070020), refused.HResult);
        }
        Assert.Equal(HeldFiles.Pauses, pauses);
        Assert.Equal("before", File.ReadAllText(target));
        Assert.Single(Directory.EnumerateFiles(_dir));
    }

    [Fact]
    public void AHoldThatEndsInsideTheBoundLetsTheRenameLand()
    {
        string target = Target();
        var pauses = new List<int>();
        var holder = Hold(target, FileShare.Read);
        RenameOnto(target, "after", milliseconds => { pauses.Add(milliseconds); holder.Dispose(); });
        Assert.Equal(new[] { HeldFiles.Pauses[0] }, pauses);
        Assert.Equal("after", File.ReadAllText(target));
    }

    [Fact]
    public void AReadOnlyFileIsAPermissionNotAHoldAndIsNeverAskedAgain()
    {
        string target = Target();
        File.SetAttributes(target, FileAttributes.ReadOnly);
        var pauses = new List<int>();
        var refused = Assert.ThrowsAny<Exception>(() => RenameOnto(target, "after", pauses.Add));
        Assert.IsNotType<FileInUseException>(refused);
        Assert.Empty(pauses);
        Assert.False(HeldFiles.IsHeld(target));
        Assert.Equal("before", File.ReadAllText(target));
    }

    [Fact]
    public void TheProbeSeesAReaderWithoutDeleteSharingAndNothingElse()
    {
        string target = Target();
        Assert.False(HeldFiles.IsHeld(target));
        using (Hold(target, FileShare.Read)) Assert.True(HeldFiles.IsHeld(target));
        using (Hold(target, FileShare.Read | FileShare.Delete)) Assert.False(HeldFiles.IsHeld(target));
        Assert.False(HeldFiles.IsHeld(Path.Combine(_dir, "not-there.json")));
    }

    [Fact]
    public void AReadAnswersReadNotThereOrCouldNotReadNowNeverEmpty()
    {
        Assert.Equal(HeldFiles.ReadOutcome.NotThere, HeldFiles.ReadBytes(Path.Combine(_dir, "not-there.json")).Outcome);
        string target = Target();
        var pauses = new List<int>();
        using (Hold(target, FileShare.None))
        {
            var read = HeldFiles.ReadBytes(target, pauses.Add);
            Assert.Equal(HeldFiles.ReadOutcome.CouldNotReadNow, read.Outcome);
            Assert.Null(read.Data);
        }
        Assert.Equal(HeldFiles.Pauses, pauses);

        var holder = Hold(target, FileShare.None);
        var released = HeldFiles.ReadBytes(target, _ => holder.Dispose());
        Assert.Equal(HeldFiles.ReadOutcome.Read, released.Outcome);
        Assert.Equal("before", Encoding.UTF8.GetString(released.Data!));
    }

    [Fact]
    public void ATemporaryIsHiddenUniqueAndBesideItsFile()
    {
        string target = Path.Combine(_dir, "course_config.json");
        string one = HeldFiles.TemporaryBeside(target), two = HeldFiles.TemporaryBeside(target);
        Assert.NotEqual(one, two);
        Assert.Equal(_dir, Path.GetDirectoryName(one));
        Assert.StartsWith(".course_config.json.", Path.GetFileName(one));
        Assert.EndsWith(".tmp", one);
    }
}

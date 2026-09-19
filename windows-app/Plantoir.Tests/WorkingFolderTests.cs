using System.IO;
using System.Linq;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// One notion of "the same working folder" (issue #162). Two of them is how
/// re-choosing the folder a window already shows came to stop that folder's
/// container, taking a running preview with it.
/// </summary>
public class WorkingFolderTests
{
    [Fact]
    public void OneFolderSpelledSeveralWaysIsOneFolder()
    {
        Assert.True(WorkingFolder.IsTheSame(@"C:\Work", @"C:\work"));
        Assert.True(WorkingFolder.IsTheSame(@"C:\Work", @"C:\WORK\"));
        Assert.True(WorkingFolder.IsTheSame(@"C:\Work\", @"C:\Work"));
        Assert.True(WorkingFolder.IsTheSame(@"C:\Work/", @"C:\Work"));
        Assert.True(WorkingFolder.IsTheSame(@"C:\Work\Courses\..\", @"C:\work\courses\..\"));

        Assert.False(WorkingFolder.IsTheSame(@"C:\Work", @"C:\Work2"));
        Assert.False(WorkingFolder.IsTheSame(@"C:\Work", @"D:\Work"));
    }

    [Fact]
    public void ANullFolderIsOnlyTheSameAsAnotherNull()
    {
        Assert.True(WorkingFolder.IsTheSame(null, null));
        Assert.False(WorkingFolder.IsTheSame(null, @"C:\Work"));
        Assert.False(WorkingFolder.IsTheSame(@"C:\Work", null));
    }

    [Fact]
    public void AFolderThatCannotBeResolvedStillMatchesItself()
    {
        // Path.GetFullPath throws on some shapes; the fallback must at least
        // keep a folder equal to itself, or a window would fail to recognise
        // the folder it is already showing.
        string awkward = "C:\\Work\0broken";
        Assert.True(WorkingFolder.IsTheSame(awkward, awkward));
        Assert.Equal("", WorkingFolder.Resolved(""));
    }

    [Fact]
    public void ReChoosingTheOpenFolderSpelledDifferentlyReleasesNothing()
    {
        // The reported shape: the OS picker hands back the true on-disk
        // casing ("C:\Work"), while the window is holding the casing it was
        // stored with ("C:\work"). This is exactly what ChooseWorkspace asks,
        // in the order it asks it.
        const string asStored = @"C:\work";
        const string asPicked = @"C:\Work";
        var openWindows = new[] { asPicked };   // this window, now on the picked spelling

        bool theContainerWouldBeStopped =
            WorkingFolder.IsLeavingAFolderBehind(asStored, asPicked)
            && !WorkingFolder.AnyWindowStillHolds(openWindows, asStored);

        Assert.False(theContainerWouldBeStopped);

        // Both halves have to hold on their own: with an ordinal comparison
        // the first says "a folder was left behind" and the second says "no
        // window holds it", and the container of the folder STILL OPEN is
        // stopped — a running preview killed by re-choosing the folder it is
        // running in.
        Assert.False(WorkingFolder.IsLeavingAFolderBehind(asStored, asPicked));
        Assert.True(WorkingFolder.AnyWindowStillHolds(openWindows, asStored));
    }

    [Fact]
    public void LeavingARealDifferentFolderStillReleasesIt()
    {
        // The other half of the rule: the fix must not turn the release off.
        var openWindows = new[] { @"C:\WorkB" };
        Assert.True(WorkingFolder.IsLeavingAFolderBehind(@"C:\WorkA", @"C:\WorkB"));
        Assert.False(WorkingFolder.AnyWindowStillHolds(openWindows, @"C:\WorkA"));

        // A window with no folder yet leaves nothing behind.
        Assert.False(WorkingFolder.IsLeavingAFolderBehind(null, @"C:\WorkB"));

        // A second window still on the folder being left keeps it alive.
        Assert.True(WorkingFolder.AnyWindowStillHolds(new[] { @"C:\workb", @"C:\WorkA\" }, @"C:\worka"));

        // Windows with no folder at all must not throw or match.
        Assert.False(WorkingFolder.AnyWindowStillHolds(new string?[] { null }, @"C:\WorkA"));
    }

    [Fact]
    public void TheComparerAgreesWithTheComparison()
    {
        var folders = new[] { @"C:\Work", @"C:\work\", @"C:\Other" };
        Assert.Equal(2, folders.Distinct(WorkingFolder.Comparer).Count());
        Assert.Equal(WorkingFolder.Comparer.GetHashCode(@"C:\Work"),
                     WorkingFolder.Comparer.GetHashCode(@"C:\work\"));
    }

    [Fact]
    public void ANewWindowInheritsTheOpenSpellingOfTheKeyFolder()
    {
        // The remembered key path and the window holding that folder can be
        // spelled differently; inheriting the remembered spelling is how one
        // folder comes to look like two windows on two folders.
        Assert.Equal(@"C:\Work",
            Workspace.FolderForNewWindow(new[] { @"C:\Other", @"C:\Work" }, @"C:\work\"));
    }
}

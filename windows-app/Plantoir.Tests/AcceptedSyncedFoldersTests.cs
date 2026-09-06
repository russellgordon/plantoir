using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// Remembering that a teacher was told about a synced folder and carried on.
///
/// <para>The contract's rule: going ahead is remembered for THAT folder, keyed
/// by its resolved path, and neither the choice nor the notice is shown for it
/// again. A folder that opens on every launch must not interrupt every
/// launch.</para>
/// </summary>
public class AcceptedSyncedFoldersTests
{
    private static AppSettings Fresh() => new();

    [Fact]
    public void NothingIsRememberedToBeginWith()
    {
        Assert.False(Fresh().HasAcceptedSyncFor(@"C:\Users\teacher\OneDrive\Teaching"));
    }

    [Fact]
    public void AcceptingAFolderIsRememberedForThatFolder()
    {
        var settings = Fresh();
        settings.RememberAcceptedSyncFor(@"C:\Users\teacher\OneDrive\Teaching");
        Assert.True(settings.HasAcceptedSyncFor(@"C:\Users\teacher\OneDrive\Teaching"));
    }

    [Fact]
    public void AnsweringForOneFolderSaysNothingAboutAnother()
    {
        // A teacher can have several working folders, and the trade they
        // accepted for one is not a trade they accepted for all of them.
        var settings = Fresh();
        settings.RememberAcceptedSyncFor(@"C:\Users\teacher\OneDrive\Teaching");
        Assert.False(settings.HasAcceptedSyncFor(@"C:\Users\teacher\OneDrive\Marking"));
    }

    [Fact]
    public void TheSameFolderSpelledDifferentlyIsTheSameFolder()
    {
        // Keyed by RESOLVED path: a trailing separator, a different case, or a
        // walk through "." is the same folder, and asking again would look
        // like the answer had not been recorded.
        var settings = Fresh();
        settings.RememberAcceptedSyncFor(@"C:\Users\teacher\OneDrive\Teaching");
        Assert.True(settings.HasAcceptedSyncFor(@"C:\Users\teacher\OneDrive\Teaching\"));
        Assert.True(settings.HasAcceptedSyncFor(@"c:\users\teacher\onedrive\teaching"));
        Assert.True(settings.HasAcceptedSyncFor(@"C:\Users\teacher\OneDrive\.\Teaching"));
        Assert.True(settings.HasAcceptedSyncFor(@"C:\Users\teacher\OneDrive\Marking\..\Teaching"));
    }

    [Fact]
    public void RememberingTwiceDoesNotRecordItTwice()
    {
        var settings = Fresh();
        settings.RememberAcceptedSyncFor(@"C:\Users\teacher\OneDrive\Teaching");
        settings.RememberAcceptedSyncFor(@"C:\Users\teacher\OneDrive\Teaching\");
        Assert.Single(settings.AcceptedSyncedFolders);
    }

    [Fact]
    public void NothingIsNotRemembered()
    {
        var settings = Fresh();
        settings.RememberAcceptedSyncFor(null);
        settings.RememberAcceptedSyncFor("");
        settings.RememberAcceptedSyncFor("   ");
        Assert.Empty(settings.AcceptedSyncedFolders);
        Assert.False(settings.HasAcceptedSyncFor(null));
    }
}

using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// A copy out of a reference course arrives UNLOCKED and writable
/// (<c>copyingAPageBetweenCourses.theCopyArrivesUnlocked</c>): the source is
/// locked first — design A's deny entries AND a read-only bit, the one
/// mechanism that would travel through a copy — and the page and picture
/// written must carry neither. Every entry set here is on a temp folder and is
/// removed in Dispose.
/// </summary>
[Collection(CopyAPageDiskCollection.Name)]
public class CopyAPageClearsTheLockTests : IDisposable
{
    private readonly string _root = Directory.CreateTempSubdirectory("plantoir-copy-lock").FullName;

    public void Dispose()
    {
        ReferenceLock.Clear(_root);
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    [Fact]
    public void APageCopiedOutOfALockedCourseIsWritable()
    {
        var source = CopyAPageTests.Build(_root, JsonNode.Parse("""{"folder":"ICS4U-2025","sharedFolders":["Concepts"],"pages":[{"path":"Concepts/Loops.md","text":"---\ndraft: true\n---\n![[one.png]]\n"}],"media":[{"name":"one.png","bytes":"aaa"}]}""")!);
        var destination = CopyAPageTests.Build(_root, JsonNode.Parse("""{"folder":"ICS4U","sharedFolders":["Concepts"],"pages":[],"media":[]}""")!);
        string page = Path.Combine(source.DirectoryPath, "Concepts", "Loops.md");
        string picture = Path.Combine(source.DirectoryPath, "Media", "one.png");
        File.SetAttributes(page, FileAttributes.ReadOnly);
        File.SetAttributes(picture, FileAttributes.ReadOnly);
        ReferenceLock.Lock(source.DirectoryPath);
        Assert.True(ReferenceLock.IsLocked(page));

        var request = new CoursePageCopy.Request(source, destination, "Concepts/Loops.md", "Concepts", false);
        var outcome = CoursePageCopy.Copy(CoursePageCopy.MakePlan(request), request, new CoursePageCopy.Session(_ => "B.zip"));

        string copiedPage = Path.Combine(destination.DirectoryPath, "Concepts", "Loops.md");
        string copiedPicture = Path.Combine(destination.DirectoryPath, "Media", "one.png");
        Assert.Single(outcome.PagesCreated);
        foreach (string written in new[] { copiedPage, copiedPicture })
        {
            Assert.False(File.GetAttributes(written).HasFlag(FileAttributes.ReadOnly), written);
            Assert.False(ReferenceLock.IsLocked(written), written);
            File.AppendAllText(written, "\nedited");                     // writable
        }
    }
}

using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// Names are written as the SOURCE spelled them, and an accent twin is never
/// a second file (#247; bundle-6 ruling 5). NTFS does not refuse a name that
/// differs only by NFC/NFD spelling — measured here as well as in the plan —
/// so the name index, updated after each write, is the only guard.
/// </summary>
[Collection(CopyAPageDiskCollection.Name)]
public class CopyAPageNamesTests : IDisposable
{
    private readonly string _root = Directory.CreateTempSubdirectory("plantoir-copy-names").FullName;

    // Built from code points so no editor or tool can quietly re-spell them.
    private static readonly string ComposedE = ((char)0x00E9).ToString();
    private static readonly string DecomposedE = "e" + (char)0x0301;

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    [Fact]
    public void NtfsDoesNotRefuseAnAccentTwinButDoesRefuseACaseTwin()
    {
        string folder = Directory.CreateDirectory(Path.Combine(_root, "measure")).FullName;
        File.WriteAllText(Path.Combine(folder, $"Caf{ComposedE}.md"), "nfc");
        using (new FileStream(Path.Combine(folder, $"Caf{DecomposedE}.md"), FileMode.CreateNew)) { }   // NOT refused
        Assert.Equal(2, Directory.GetFiles(folder).Length);
        var refused = Assert.Throws<IOException>(() => new FileStream(Path.Combine(folder, $"CAF{ComposedE.ToUpperInvariant()}.md"), FileMode.CreateNew));
        Assert.Equal(unchecked((int)0x80070050), refused.HResult);   // ERROR_FILE_EXISTS: the ordinary skip
    }

    private (Course Source, Course Destination) Courses(string pageName, string pageText, IEnumerable<(string Name, string Bytes)> media)
    {
        var sourceSide = new JsonObject
        {
            ["folder"] = "ICS4U-2025",
            ["sharedFolders"] = new JsonArray("Tutorials"),
            ["pages"] = new JsonArray(new JsonObject { ["path"] = "Tutorials/" + pageName, ["text"] = pageText }),
            ["media"] = new JsonArray(media.Select(m => (JsonNode)new JsonObject { ["name"] = m.Name, ["bytes"] = m.Bytes }).ToArray()),
        };
        var destinationSide = JsonNode.Parse("""{"folder":"ICS4U","sharedFolders":["Tutorials"],"pages":[],"media":[]}""")!;
        return (CopyAPageTests.Build(_root, sourceSide), CopyAPageTests.Build(_root, destinationSide));
    }

    [Fact]
    public void ADecomposedNameIsWrittenBackDecomposed()
    {
        string picture = $"Bone Appe{(char)0x0301}tit.jpg";
        string page = $"Bone Appe{(char)0x0301}tit.md";
        var (source, destination) = Courses(page, $"![[{picture}]]\n", new[] { (picture, "aaa") });
        var request = new CoursePageCopy.Request(source, destination, "Tutorials/" + page, "Tutorials", false);
        var outcome = CoursePageCopy.Copy(CoursePageCopy.MakePlan(request), request, new CoursePageCopy.Session(_ => "B.zip"));
        Assert.Equal(picture, Assert.Single(Directory.GetFiles(Path.Combine(destination.DirectoryPath, "Media")).Select(Path.GetFileName)));
        Assert.Equal(page, Assert.Single(Directory.GetFiles(Path.Combine(destination.DirectoryPath, "Tutorials")).Select(Path.GetFileName)));
        Assert.Single(outcome.PagesCreated);
    }

    [Fact]
    public void AnAccentTwinOfAPageAlreadyThereIsASkipNotASecondFile()
    {
        var (source, destination) = Courses($"Caf{DecomposedE}.md", "Body\n", Array.Empty<(string, string)>());
        File.WriteAllText(Path.Combine(destination.DirectoryPath, "Tutorials", $"Caf{ComposedE}.md"), "the teacher's own");
        var request = new CoursePageCopy.Request(source, destination, $"Tutorials/Caf{DecomposedE}.md", "Tutorials", false);
        var outcome = CoursePageCopy.Copy(CoursePageCopy.MakePlan(request), request, new CoursePageCopy.Session(_ => "B.zip"));
        Assert.Empty(outcome.PagesCreated);
        Assert.Single(Directory.GetFiles(Path.Combine(destination.DirectoryPath, "Tutorials")));
        Assert.Contains(outcome.Skipped, s => s.Reason == "aPageOfThatNameIsAlreadyHere");
    }

    /// <summary>
    /// Ruling 5: two accent-twin pictures copied in ONE run. Both plan as new;
    /// the index updated after the first write is what stops the second.
    /// </summary>
    [Fact]
    public void TwoAccentTwinPicturesInOneRunMakeOneFileAndOneSkip()
    {
        string composed = $"caf{ComposedE}.png", decomposed = $"caf{DecomposedE}.png";
        var (source, destination) = Courses("Twins.md", $"![[{composed}]] and ![[{decomposed}]]\n",
            new[] { (composed, "first"), (decomposed, "second, different") });
        var request = new CoursePageCopy.Request(source, destination, "Tutorials/Twins.md", "Tutorials", false);
        var outcome = CoursePageCopy.Copy(CoursePageCopy.MakePlan(request), request, new CoursePageCopy.Session(_ => "B.zip"));
        var files = Directory.GetFiles(Path.Combine(destination.DirectoryPath, "Media"));
        Assert.Single(files);
        Assert.Single(outcome.MediaCreated);
        Assert.Contains(outcome.Skipped, s => s.Reason == "aPictureCouldNotBeCopied");
    }
}

using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The rename record in the contract's shape (#899 W8b-18a;
/// <c>file-formats.json</c> → <c>folderRenameRecord</c>). Windows writes
/// <c>moved</c> and <c>mayHaveMoved</c> as the mac does
/// (<c>RenameRecordClaim.renameIsStarting</c>), and reads any record by
/// shape: <c>from</c>, <c>to</c> and <c>scope</c> only as strings, every
/// other key only in its own shape, never making the record unreadable
/// (the mac's <c>readRenameRecord</c> and <c>stringsIn</c>).
/// </summary>
public class RenameRecordShapeTests : IDisposable
{
    // ---- Stored properties ---------------------------------------------------------

    private readonly string _root;

    // ---- Computed properties -------------------------------------------------------

    private string CourseFolder => Path.Combine(_root, "courses", "ICS3U");
    private string RecordPath => SpecialFolderRenamer.RenameRecordPath(CourseFolder);

    // ---- Initializer ---------------------------------------------------------------

    public RenameRecordShapeTests()
    {
        _root = Directory.CreateTempSubdirectory("plantoir-rename-record-shape").FullName;
        Directory.CreateDirectory(CourseFolder);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    // ---- Functions -----------------------------------------------------------------

    private void MakeFolders(params string[] relativeFolders)
    {
        foreach (string folder in relativeFolders)
            Directory.CreateDirectory(Path.Combine(CourseFolder, folder.Replace('/', Path.DirectorySeparatorChar)));
    }

    private void LayTheRecord(string json)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(RecordPath)!);
        File.WriteAllBytes(RecordPath, Encoding.UTF8.GetBytes(json));
    }

    /// <summary>The claim a Rename folder makes, written as it starts: the record on disk read first, then this run's moves.</summary>
    private JObject StartTheRename(string oldName, string newName, FolderScope scope, IReadOnlyList<int> sections,
                                   IReadOnlyList<(string From, string To, int? Section)>? moves = null)
    {
        var claim = new RenameRecordClaim(oldName, newName, scope, CourseFolder, changesTheSettings: true);
        claim.RenameIsStarting(moves ?? SpecialFolderRenamer.Moves(CourseFolder, oldName, newName, scope, sections), sections);
        return JObject.Parse(File.ReadAllText(RecordPath));
    }

    private static List<string>? StringsOf(JToken? value)
    {
        if (value is not JArray items) return null;
        var strings = new List<string>();
        foreach (JToken item in items) strings.Add(item.Type == JTokenType.String ? item.ToString() : "<" + item.Type + ">");
        return strings;
    }

    private static string Listed(IReadOnlyList<string>? places) => places is null ? "(not said)" : "[" + string.Join(", ", places) + "]";

    // ---- Reading -------------------------------------------------------------------

    /// <summary>
    /// Every <c>folderRenameRecord</c> example, by name, read as its
    /// <c>expect</c> says: <c>read</c> is the verdict (record or not), and
    /// a key missing from <c>expect</c> is one the record does not say
    /// (<c>moved</c> null, <c>mayHaveMoved</c> empty), as the note's rule has it.
    /// </summary>
    [Fact]
    public void EveryContractExampleIsReadAsTheContractSays()
    {
        var examples = ContractLoader.LoadJson("file-formats.json")["folderRenameRecord"]!["examples"]!.AsArray();
        Assert.NotEmpty(examples);
        var wrongCases = new List<string>();
        foreach (var example in examples)
        {
            string name = example!["name"]!.ToString();
            byte[] bytes = Encoding.UTF8.GetBytes(example["bytes"]!.GetValue<string>());
            var expect = example["expect"]!;
            bool expectRead = expect["read"]!.GetValue<bool>();
            var note = SpecialFolderRenamer.ReadRenameRecord(bytes);
            if ((note is not null) != expectRead)
            {
                wrongCases.Add(name + ": read " + (note is not null) + ", expected " + expectRead);
                continue;
            }
            if (note is null) continue;
            if (note.From != expect["from"]!.ToString()) wrongCases.Add(name + ": from " + note.From);
            if (note.To != expect["to"]!.ToString()) wrongCases.Add(name + ": to " + note.To);
            if (note.Scope != expect["scope"]!.ToString()) wrongCases.Add(name + ": scope " + note.Scope);
            List<string>? expectMoved = null;
            if (expect["moved"] is { } movedNode)
            {
                expectMoved = new List<string>();
                foreach (var place in movedNode.AsArray()) expectMoved.Add(place!.GetValue<string>());
            }
            if (Listed(note.Moved) != Listed(expectMoved))
                wrongCases.Add(name + ": moved " + Listed(note.Moved) + ", expected " + Listed(expectMoved));
            var expectMayHaveMoved = new List<string>();
            if (expect["mayHaveMoved"] is { } mayNode)
                foreach (var place in mayNode.AsArray()) expectMayHaveMoved.Add(place!.GetValue<string>());
            if (Listed(note.MayHaveMoved) != Listed(expectMayHaveMoved))
                wrongCases.Add(name + ": mayHaveMoved " + Listed(note.MayHaveMoved) + ", expected " + Listed(expectMayHaveMoved));
        }
        Assert.True(wrongCases.Count == 0,
            wrongCases.Count + " of " + examples.Count + " folderRenameRecord examples read wrongly: " + string.Join(" | ", wrongCases));
    }

    /// <summary>
    /// <c>from</c>, <c>to</c> or <c>scope</c> that is not a string makes the
    /// file not a record (night25-4 sweep LOW 3: <c>ToString()</c> read a
    /// number as its text).
    /// </summary>
    [Fact]
    public void AFromToOrScopeThatIsNotAStringIsNotARecord()
    {
        var wrong = new List<string>();
        foreach (string key in new[] { "from", "to", "scope" })
        {
            foreach (string value in new[] { "3", "true", "null", "[\"Tasks\"]", "{\"name\": \"Tasks\"}" })
            {
                var parts = new Dictionary<string, string> { ["from"] = "\"Tasks\"", ["to"] = "\"Assessments\"", ["scope"] = "\"per_section\"" };
                parts[key] = value;
                string json = "{\"from\": " + parts["from"] + ", \"to\": " + parts["to"] + ", \"scope\": " + parts["scope"] + "}";
                if (SpecialFolderRenamer.ReadRenameRecord(Encoding.UTF8.GetBytes(json)) is not null) wrong.Add(json);
            }
        }
        Assert.True(wrong.Count == 0, "read as a record: " + string.Join(" | ", wrong));
    }

    /// <summary>A number in <c>from</c> never agrees with the disk: the sheet offers no finish for a folder named "3".</summary>
    [Fact]
    public void ANumberInFromIsNotAnInterruptedRenameOfAFolderSoNamed()
    {
        MakeFolders("section1/Assessments");
        LayTheRecord("{\"from\": 3, \"to\": \"Assessments\", \"scope\": \"per_section\"}");

        Assert.False(SpecialFolderRenamer.LooksLikeAnInterruptedRename("3", "Assessments", FolderScope.PerSection, CourseFolder, new[] { 1 }));
        Assert.Null(SpecialFolderRenamer.InterruptedRenameTarget("3", FolderScope.PerSection, CourseFolder, new[] { 1 }));
    }

    /// <summary>A key this build does not know, or a known one in another shape, is not said; the record is still read.</summary>
    [Fact]
    public void AKeyInAnotherShapeIsNotSaidAndTheRecordIsStillRead()
    {
        string json = "{\"from\": \"Tasks\", \"to\": \"Assessments\", \"scope\": \"per_section\", "
                      + "\"moved\": [\"section1/Assessments\", 2], \"mayHaveMoved\": \"section2/Assessments\", \"written\": 3}";
        var note = SpecialFolderRenamer.ReadRenameRecord(Encoding.UTF8.GetBytes(json));

        Assert.NotNull(note);
        Assert.Null(note!.Moved);
        Assert.Empty(note.MayHaveMoved);

        MakeFolders("section1/Assessments");
        LayTheRecord(json);
        Assert.True(SpecialFolderRenamer.LooksLikeAnInterruptedRename("Tasks", "Assessments", FolderScope.PerSection, CourseFolder, new[] { 1 }));
    }

    // ---- Writing -------------------------------------------------------------------

    /// <summary>A start run with no earlier record writes this run's places as an array, and no <c>mayHaveMoved</c>, as Newtonsoft indented plus one LF.</summary>
    [Fact]
    public void AStartRunWritesMovedAsAnArrayOfThisRunsPlaces()
    {
        MakeFolders("section1/Tasks", "section2/Tasks");

        var written = StartTheRename("Tasks", "Assessments", FolderScope.PerSection, new[] { 1, 2 });

        Assert.Equal(JTokenType.Array, written["moved"]?.Type);
        Assert.Equal(new List<string> { "section1/Assessments", "section2/Assessments" }, StringsOf(written["moved"]));
        Assert.Null(written["mayHaveMoved"]);
        var expected = new JObject { ["from"] = "Tasks", ["to"] = "Assessments", ["scope"] = "per_section",
                                     ["moved"] = new JArray { "section1/Assessments", "section2/Assessments" } };
        Assert.Equal(expected.ToString(Newtonsoft.Json.Formatting.Indented) + "\n", File.ReadAllText(RecordPath));
    }

    /// <summary>A shared folder's place is its name at the course's top.</summary>
    [Fact]
    public void ASharedFoldersPlaceIsItsNewName()
    {
        MakeFolders("Concepts");

        var written = StartTheRename("Concepts", "Ideas", FolderScope.Shared, new[] { 1 });

        Assert.Equal(new List<string> { "Ideas" }, StringsOf(written["moved"]));
    }

    /// <summary>A re-run of the same rename keeps the places the earlier run's record says it moved, then adds its own.</summary>
    [Fact]
    public void ASameRenameReRunKeepsTheEarlierRunsMovedPlaces()
    {
        MakeFolders("section1/Assessments", "section2/Tasks");
        LayTheRecord("{\"from\": \"tasks\", \"to\": \"Assessments\", \"scope\": \"per_section\", \"moved\": [\"section1/Assessments\"]}");

        var written = StartTheRename("Tasks", "Assessments", FolderScope.PerSection, new[] { 1, 2 });

        Assert.Equal(new List<string> { "section1/Assessments", "section2/Assessments" }, StringsOf(written["moved"]));
        Assert.Null(written["mayHaveMoved"]);
    }

    /// <summary>A place the earlier record and this run both name is written once.</summary>
    [Fact]
    public void APlaceBothRunsNameIsWrittenOnce()
    {
        MakeFolders("section1/Tasks");
        LayTheRecord("{\"from\": \"Tasks\", \"to\": \"Assessments\", \"scope\": \"per_section\", \"moved\": [\"section1/Assessments\"]}");

        var written = StartTheRename("Tasks", "Assessments", FolderScope.PerSection, new[] { 1 });

        Assert.Equal(new List<string> { "section1/Assessments" }, StringsOf(written["moved"]));
    }

    /// <summary>Another rename's record lends this run no places: neither its <c>moved</c> nor its <c>mayHaveMoved</c>.</summary>
    [Fact]
    public void AnotherRenamesRecordLendsNoPlaces()
    {
        MakeFolders("section1/Tasks", "section2/Homework");
        LayTheRecord("{\"from\": \"Tasks\", \"to\": \"Homework\", \"scope\": \"per_section\", "
                     + "\"moved\": [\"section2/Homework\"], \"mayHaveMoved\": [\"section3/Homework\"]}");

        var written = StartTheRename("Tasks", "Assessments", FolderScope.PerSection, new[] { 1, 2 });

        Assert.Equal(new List<string> { "section1/Assessments" }, StringsOf(written["moved"]));
        Assert.Null(written["mayHaveMoved"]);
    }

    /// <summary>
    /// An earlier record of this rename that does not say what it moved
    /// (what a released Windows build writes): each folder at the new name
    /// whose old name beside it is absent is one this run cannot tell is
    /// the rename's, read before anything moves, less what this run moves.
    /// A new-name folder beside its old name, or beside a file of the old
    /// name, is not.
    /// </summary>
    [Fact]
    public void AStartRunWritesTheCannotTellPlacesItReadsBeforeItMovesAnything()
    {
        MakeFolders("section1/Assessments", "section2/Tasks", "section3/Assessments", "section4/Assessments", "section4/Tasks");
        File.WriteAllText(Path.Combine(CourseFolder, "section3", "Tasks"), "a file, not the folder");
        LayTheRecord("{\r\n  \"from\": \"Tasks\",\r\n  \"to\": \"Assessments\",\r\n  \"scope\": \"per_section\"\r\n}\n");

        var written = StartTheRename("Tasks", "Assessments", FolderScope.PerSection, new[] { 1, 2, 3, 4 },
            new List<(string, string, int?)>
            {
                (Path.Combine(CourseFolder, "section2", "Tasks"), Path.Combine(CourseFolder, "section2", "Assessments"), 2),
            });

        Assert.Equal(new List<string> { "section2/Assessments" }, StringsOf(written["moved"]));
        Assert.Equal(new List<string> { "section1/Assessments" }, StringsOf(written["mayHaveMoved"]));
    }

    /// <summary>The earlier record's <c>mayHaveMoved</c> is carried forward, less anything this run's <c>moved</c> names.</summary>
    [Fact]
    public void TheEarlierMayHaveMovedIsCarriedForwardLessWhatIsMoved()
    {
        MakeFolders("section1/Tasks", "section2/Assessments", "section3/Assessments");
        LayTheRecord("{\"from\": \"Tasks\", \"to\": \"Assessments\", \"scope\": \"per_section\", "
                     + "\"moved\": [\"section2/Assessments\"], \"mayHaveMoved\": [\"section1/Assessments\", \"section3/Assessments\"]}");

        var written = StartTheRename("Tasks", "Assessments", FolderScope.PerSection, new[] { 1, 2, 3 });

        Assert.Equal(new List<string> { "section2/Assessments", "section1/Assessments" }, StringsOf(written["moved"]));
        Assert.Equal(new List<string> { "section3/Assessments" }, StringsOf(written["mayHaveMoved"]));
    }

    /// <summary>
    /// A capitalisation-only rename asks the folder's listing for each
    /// spelling (the mac's <c>presence(spelledExactly:)</c>): on a volume
    /// that ignores capitals, "tasks" beside "Tasks" is the same folder, so
    /// only the listing says the old spelling is gone.
    /// </summary>
    [Fact]
    public void ACapitalisationOnlyRenameAsksTheListingForEachSpelling()
    {
        MakeFolders("section1/Tasks", "section2/tasks");
        LayTheRecord("{\"from\": \"tasks\", \"to\": \"Tasks\", \"scope\": \"per_section\"}");

        var written = StartTheRename("tasks", "Tasks", FolderScope.PerSection, new[] { 1, 2 },
            new List<(string, string, int?)>
            {
                (Path.Combine(CourseFolder, "section2", "tasks"), Path.Combine(CourseFolder, "section2", "Tasks"), 2),
            });

        Assert.Equal(new List<string> { "section2/Tasks" }, StringsOf(written["moved"]));
        Assert.Equal(new List<string> { "section1/Tasks" }, StringsOf(written["mayHaveMoved"]));
    }
}

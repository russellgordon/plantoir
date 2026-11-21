using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W6's fix round (the first review's MEDIUM): an <c>external</c> op on
/// the app's own settings (<see cref="UndoAppSettingsPlaces"/>) writes through
/// the real store, a settings file of the test's own: it replaces exactly the
/// named member with exactly the recorded value (a list and a dictionary
/// replaced, never merged), checks before it writes, changes nothing on a
/// mismatch, and writes into the file as it is on the disk now, never a
/// process's older copy; the copy the process runs on then agrees. Undo and
/// Redo go through the door. A kill at every step is the harness's
/// (<c>Plantoir.UndoHarness kinds-kill</c>, whose preference is a list member
/// of this store).
/// </summary>
public sealed class UndoAppSettingsPlacesTests : IDisposable
{
    private readonly string _folder = RunOwnedTempFolders.Create("plantoir-undo-settings-");

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private string SettingsFile(string json)
    {
        string file = Path.Combine(_folder, Guid.NewGuid().ToString("N"), "settings.json");
        Directory.CreateDirectory(Path.GetDirectoryName(file)!);
        File.WriteAllText(file, json);
        return file;
    }

    private static UndoJson Value(string json)
    {
        using JsonDocument document = JsonDocument.Parse(json);
        return UndoJson.From(document.RootElement)!;
    }

    private static JsonNode OnTheDisk(string file, string member) => JsonNode.Parse(File.ReadAllText(file))![member]!;

    /// <summary>A list is replaced by exactly the recorded list, both ways; the running copy holds the same list.</summary>
    [Fact]
    public void AListMemberIsReplacedNeverAppendedTo()
    {
        string file = SettingsFile("{\"AcceptedSyncedFolders\": [\"C:\\\\one\"]}");
        AppSettings running = AppSettings.Load(file);
        var places = new UndoAppSettingsPlaces(file, () => running);

        Assert.True(places.Write("preference:AcceptedSyncedFolders", Value("[\"C:\\\\one\", \"C:\\\\two\"]")));
        Assert.Equal("[\"C:\\\\one\",\"C:\\\\two\"]", OnTheDisk(file, "AcceptedSyncedFolders").ToJsonString());
        Assert.Equal(["C:\\one", "C:\\two"], running.AcceptedSyncedFolders);

        Assert.True(places.Write("preference:AcceptedSyncedFolders", Value("[\"C:\\\\one\"]")));
        Assert.Equal("[\"C:\\\\one\"]", OnTheDisk(file, "AcceptedSyncedFolders").ToJsonString());
        Assert.Equal(["C:\\one"], running.AcceptedSyncedFolders);
        Assert.True(places.Read("preference:AcceptedSyncedFolders").Matches(Value("[\"C:\\\\one\"]")));
    }

    /// <summary>A dictionary is replaced by exactly the recorded one: a key the record does not hold is gone, never merged in.</summary>
    [Fact]
    public void ADictionaryMemberIsReplacedNeverMergedInto()
    {
        string file = SettingsFile("{\"DeployedFolderPorts\": {\"C:\\\\a\": 8101, \"C:\\\\b\": 8102}}");
        AppSettings running = AppSettings.Load(file);
        var places = new UndoAppSettingsPlaces(file, () => running);

        Assert.True(places.Write("preference:DeployedFolderPorts", Value("{\"C:\\\\a\": 8200}")));
        Assert.Equal("{\"C:\\\\a\":8200}", OnTheDisk(file, "DeployedFolderPorts").ToJsonString());
        Assert.Equal(new Dictionary<string, int> { ["C:\\a"] = 8200 }, running.DeployedFolderPorts);
    }

    /// <summary>
    /// A scalar set by a process whose copy is older than the file (another
    /// process saved since it loaded) keeps that other process's change: only
    /// the one member is written, into the file as it is on the disk now.
    /// </summary>
    [Fact]
    public void AProcessHoldingAnOlderCopyWritesOnlyTheMemberIntoTheFileAsItIsNow()
    {
        string file = SettingsFile("{\"WorkspacePath\": \"C:\\\\old\", \"PreviewOpensAt\": \"frontPage\"}");
        AppSettings stale = AppSettings.Load(file);
        // Another process (the app, while plantoir-mcp holds this copy) saves a change.
        File.WriteAllText(file, "{\"WorkspacePath\": \"C:\\\\new\", \"PreviewOpensAt\": \"frontPage\"}");
        var places = new UndoAppSettingsPlaces(file, () => stale);

        Assert.True(places.Write("preference:PreviewOpensAt", new UndoJson.Text("lastViewed")));
        Assert.Equal("C:\\new", OnTheDisk(file, "WorkspacePath").GetValue<string>());
        Assert.Equal("lastViewed", OnTheDisk(file, "PreviewOpensAt").GetValue<string>());
        Assert.Equal("lastViewed", stale.PreviewOpensAt);
        // Read from the file, never from the older copy.
        stale.PreviewOpensAt = "frontPage";
        Assert.True(places.Read("preference:PreviewOpensAt").Matches(new UndoJson.Text("lastViewed")));
    }

    /// <summary>
    /// A value that would not read back as itself (a number for a text
    /// setting, which the app's reader turns into the text "5") is refused
    /// before anything is written: the file byte for byte as it was, the
    /// running copy unchanged.
    /// </summary>
    [Fact]
    public void AMismatchWritesNothing()
    {
        string file = SettingsFile("{\n  \"PreviewOpensAt\": \"frontPage\",\n  \"AcceptedSyncedFolders\": [\"C:\\\\one\"]\n}\n");
        byte[] before = File.ReadAllBytes(file);
        AppSettings running = AppSettings.Load(file);
        var places = new UndoAppSettingsPlaces(file, () => running);

        Assert.False(places.Write("preference:PreviewOpensAt", new UndoJson.Number(5)));
        Assert.False(places.Write("preference:AcceptedSyncedFolders", Value("[1, 2]")));
        Assert.Equal(before, File.ReadAllBytes(file));
        Assert.Equal("frontPage", running.PreviewOpensAt);
        Assert.Equal(["C:\\one"], running.AcceptedSyncedFolders);
        Assert.False(File.Exists(file + ".undo-writing"));
    }

    /// <summary>
    /// A file the app's own reader cannot read (JSON, but a list where a text
    /// setting goes) is never written over: refused, byte for byte as it was.
    /// </summary>
    [Fact]
    public void AFileTheAppCannotReadIsNeverWrittenOver()
    {
        string file = SettingsFile("{\"PreviewOpensAt\": [\"not\", \"text\"], \"WorkspacePath\": \"C:\\\\w\"}");
        byte[] before = File.ReadAllBytes(file);
        var places = new UndoAppSettingsPlaces(file, () => null);
        Assert.True(places.Read("preference:PreviewOpensAt").CannotTell);
        Assert.False(places.Write("preference:PreviewOpensAt", new UndoJson.Text("lastViewed")));
        Assert.Equal(before, File.ReadAllBytes(file));
    }

    /// <summary>A step of one external op on a list member, made, undone and redone through the door, the file exactly each way.</summary>
    [Fact]
    public void AStepOnAListMemberIsMadeUndoneAndRedoneThroughTheDoor()
    {
        string file = SettingsFile("{\"AcceptedSyncedFolders\": [\"C:\\\\one\"], \"WorkspacePath\": \"C:\\\\w\"}");
        AppSettings running = AppSettings.Load(file);
        var places = new UndoAppSettingsPlaces(file, () => running);
        using var scribe = new UndoScribe();
        UndoDoor Door() => new(scribe.Journal, UndoMode.Live, scribe.Maintainers, places: places);
        var op = UndoKindsForTheCases.External("preference:AcceptedSyncedFolders",
            JsonNode.Parse("[\"C:\\\\one\"]"), JsonNode.Parse("[\"C:\\\\one\", \"C:\\\\two\"]"));

        Assert.Equal(UndoOutcomeKind.Applied, Door().Perform(scribe.OpsDraft(null, new JsonArray(op), [])).Kind);
        Assert.Equal("[\"C:\\\\one\",\"C:\\\\two\"]", OnTheDisk(file, "AcceptedSyncedFolders").ToJsonString());
        Assert.Equal(UndoOutcomeKind.Undone, Door().Undo().Kind);
        Assert.Equal("[\"C:\\\\one\"]", OnTheDisk(file, "AcceptedSyncedFolders").ToJsonString());
        Assert.Equal(UndoOutcomeKind.Redone, Door().Redo().Kind);
        Assert.Equal("[\"C:\\\\one\",\"C:\\\\two\"]", OnTheDisk(file, "AcceptedSyncedFolders").ToJsonString());
        Assert.Equal(["C:\\one", "C:\\two"], running.AcceptedSyncedFolders);
        Assert.Equal("C:\\w", OnTheDisk(file, "WorkspacePath").GetValue<string>());
    }

    /// <summary>
    /// A dictionary keyed beyond ASCII (a folder path with an accent) is still
    /// set in the app's own settings file, which the mac never reads or writes:
    /// only an editJSON on a file the mac shares refuses such a key (#899 W6
    /// review 2, <see cref="UndoJson.IsMeasured"/>).
    /// </summary>
    [Fact]
    public void ADictionaryKeyedBeyondAsciiIsStillSetInTheAppsOwnSettings()
    {
        string file = SettingsFile("{\"DeployedFolderPorts\": {\"C:\\\\a\": 8101}}");
        AppSettings running = AppSettings.Load(file);
        var places = new UndoAppSettingsPlaces(file, () => running);

        Assert.True(places.Write("preference:DeployedFolderPorts", Value("{\"C:\\\\Fran\u00e7ais\": 8200}")));
        Assert.Equal(new Dictionary<string, int> { ["C:\\Fran\u00e7ais"] = 8200 }, running.DeployedFolderPorts);
        Assert.True(places.Read("preference:DeployedFolderPorts").Matches(Value("{\"C:\\\\Fran\u00e7ais\": 8200}")));
    }

    /// <summary>
    /// The review's LOW 3 (#899 W6 review 2): while another program holds the
    /// settings file open without letting it be replaced (as the app's own
    /// <c>Save</c> does while it writes), the rename is refused: the set is
    /// refused (couldNotWrite), the file byte for byte as it was, the running
    /// copy unchanged, and no temporary file left beside it.
    /// </summary>
    [Fact]
    public void ARenameRefusedBecauseTheFileIsOpenChangesNothing()
    {
        string file = SettingsFile("{\"AcceptedSyncedFolders\": [\"C:\\\\one\"]}");
        byte[] before = File.ReadAllBytes(file);
        AppSettings running = AppSettings.Load(file);
        var places = new UndoAppSettingsPlaces(file, () => running);

        using (var holder = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            Assert.False(places.Write("preference:AcceptedSyncedFolders", Value("[\"C:\\\\two\"]")));
        }

        Assert.Equal(before, File.ReadAllBytes(file));
        Assert.Equal(["C:\\one"], running.AcceptedSyncedFolders);
        Assert.False(File.Exists(file + ".undo-writing"));
    }

    /// <summary>
    /// The review's LOW 2 (#899 W6 review 2): a write killed between its
    /// temporary file and the rename leaves <c>settings.json.undo-writing</c>.
    /// Nothing reads it (a read is the settings file's alone), and the next
    /// set writes over it and renames it in, so none is left after.
    /// </summary>
    [Fact]
    public void ATemporaryLeftByAKilledWriteIsNeverReadAndGoesWithTheNextSet()
    {
        string file = SettingsFile("{\"AcceptedSyncedFolders\": [\"C:\\\\one\"]}");
        File.WriteAllText(file + ".undo-writing", "{\"AcceptedSyncedFolders\": [\"C:\\\\left\", \"over\"]}");
        var places = new UndoAppSettingsPlaces(file, () => null);

        Assert.True(places.Read("preference:AcceptedSyncedFolders").Matches(Value("[\"C:\\\\one\"]")));
        Assert.True(places.Write("preference:AcceptedSyncedFolders", Value("[\"C:\\\\two\"]")));
        Assert.Equal("[\"C:\\\\two\"]", OnTheDisk(file, "AcceptedSyncedFolders").ToJsonString());
        Assert.False(File.Exists(file + ".undo-writing"));
    }
}

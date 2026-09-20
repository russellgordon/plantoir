using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// A fake machine: the environment variables and the one file the rule reads.
/// </summary>
internal sealed class FakeEnvironment : IEnvironmentReader
{
    private readonly Dictionary<string, string> _variables = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, string> _files = new(StringComparer.OrdinalIgnoreCase);

    public FakeEnvironment Set(string name, string value) { _variables[name] = value; return this; }
    public FakeEnvironment WithFile(string path, string content) { _files[path] = content; return this; }

    public string? Variable(string name) => _variables.TryGetValue(name, out var v) ? v : null;
    public bool FileExists(string path) => _files.ContainsKey(path);
    public string ReadAllText(string path) => _files.TryGetValue(path, out var c) ? c : throw new FileNotFoundException(path);
}

/// <summary>
/// Detecting a cloud-synced working folder on Windows.
///
/// <para>The contract's eleven detection cases are all MAC paths — the markers
/// are explicitly not shared (<c>shared-rules.json</c> →
/// <c>cloudSyncedFolders.detection</c> has <c>macMarkers</c> and
/// <c>windowsMarkers</c>). What IS shared, and what these tests pin, is every
/// sentence a teacher reads and the rule that a synced folder is never
/// refused.</para>
/// </summary>
public class CloudSyncedFolderTests
{
    private static FakeEnvironment Machine() => new FakeEnvironment()
        .Set("USERPROFILE", @"C:\Users\teacher")
        .Set("APPDATA", @"C:\Users\teacher\AppData\Roaming")
        .Set("LOCALAPPDATA", @"C:\Users\teacher\AppData\Local");

    // ---------------------------------------------------------------- OneDrive

    [Fact]
    public void AFolderInsideOneDriveIsRecognised()
    {
        var machine = Machine().Set("OneDrive", @"C:\Users\teacher\OneDrive");
        Assert.Equal("OneDrive", CloudSyncedFolder.ServiceFor(@"C:\Users\teacher\OneDrive\Course Notes", machine));
    }

    [Fact]
    public void TheOneDriveRootItselfCounts()
    {
        var machine = Machine().Set("OneDrive", @"C:\Users\teacher\OneDrive");
        Assert.Equal("OneDrive", CloudSyncedFolder.ServiceFor(@"C:\Users\teacher\OneDrive", machine));
    }

    [Fact]
    public void ADesktopMovedIntoOneDriveByKnownFolderMoveIsCaughtByThePrefixRule()
    {
        // The whole reason the rule is a prefix rule rather than a list of
        // special folders: Known Folder Move physically relocates Desktop and
        // Documents under the OneDrive root.
        var machine = Machine().Set("OneDriveCommercial", @"C:\Users\teacher\OneDrive - School Board");
        Assert.Equal("OneDrive",
            CloudSyncedFolder.ServiceFor(@"C:\Users\teacher\OneDrive - School Board\Desktop\Teaching", machine));
    }

    [Fact]
    public void ASiblingFolderWithTheSamePrefixIsNotInsideIt()
    {
        // C:\...\OneDrive2 is not inside C:\...\OneDrive. The same boundary
        // trap as section1 / section10.
        var machine = Machine().Set("OneDrive", @"C:\Users\teacher\OneDrive");
        Assert.Null(CloudSyncedFolder.ServiceFor(@"C:\Users\teacher\OneDrive2\Course Notes", machine));
    }

    // ---------------------------------------------------------------- Dropbox

    [Fact]
    public void DropboxIsReadFromItsOwnInfoJsonRatherThanGuessed()
    {
        var machine = Machine().WithFile(
            @"C:\Users\teacher\AppData\Roaming\Dropbox\info.json",
            """{"personal":{"path":"D:\\Dropbox","host":1}}""");
        Assert.Equal("Dropbox", CloudSyncedFolder.ServiceFor(@"D:\Dropbox\Course Notes", machine));
    }

    [Fact]
    public void ABusinessDropboxRootCountsToo()
    {
        var machine = Machine().WithFile(
            @"C:\Users\teacher\AppData\Local\Dropbox\info.json",
            """{"business":{"path":"C:\\Users\\teacher\\Dropbox (School)"}}""");
        Assert.Equal("Dropbox",
            CloudSyncedFolder.ServiceFor(@"C:\Users\teacher\Dropbox (School)\Teaching", machine));
    }

    [Fact]
    public void AMalformedInfoJsonIsNotACrash()
    {
        // This runs while a teacher is choosing a folder. An unrecognised
        // service is allowed; an exception there is not.
        var machine = Machine().WithFile(
            @"C:\Users\teacher\AppData\Roaming\Dropbox\info.json", "{not json at all");
        Assert.Null(CloudSyncedFolder.ServiceFor(@"C:\Users\teacher\Dropbox\Course Notes", machine));
    }

    [Fact]
    public void AFolderCalledDropboxProvesNothing()
    {
        // The name rule that would catch this is the one that would also be
        // wrong. A wrong answer here is shown to the teacher as fact.
        Assert.Null(CloudSyncedFolder.ServiceFor(@"C:\Users\teacher\Desktop\Dropbox\Course Notes", Machine()));
    }

    // ------------------------------------------------------------ iCloud etc.

    [Fact]
    public void ICloudForWindowsAtItsDefaultLocationIsRecognised()
    {
        Assert.Equal("iCloud Drive",
            CloudSyncedFolder.ServiceFor(@"C:\Users\teacher\iCloudDrive\Course Notes", Machine()));
    }

    [Fact]
    public void AnOrdinaryFolderIsNotSynced()
    {
        Assert.Null(CloudSyncedFolder.ServiceFor(@"C:\Users\teacher\Desktop\Teaching", Machine()));
        Assert.Null(CloudSyncedFolder.ServiceFor(@"D:\Courses", Machine()));
    }

    [Fact]
    public void NothingIsNotSynced()
    {
        Assert.Null(CloudSyncedFolder.ServiceFor(null, Machine()));
        Assert.Null(CloudSyncedFolder.ServiceFor("", Machine()));
        Assert.Null(CloudSyncedFolder.ServiceFor("   ", Machine()));
    }

    [Fact]
    public void AnUnsetVariableNeverMatchesEverything()
    {
        // An empty OneDrive root must not make every folder on the machine
        // "synced" — the failure a naive prefix test produces.
        var machine = Machine().Set("OneDrive", "");
        Assert.Null(CloudSyncedFolder.ServiceFor(@"C:\Users\teacher\Desktop\Teaching", machine));
    }

    // ----------------------------------------------------------- the contract

    [Fact]
    public void TheSentencesMatchTheContractWordForWord()
    {
        var wording = ContractLoader.LoadJson("shared-rules.json")["cloudSyncedFolders"]!["wording"]!;
        const string service = "OneDrive";

        Assert.Equal(wording["headline"]!.ToString().Replace("{service}", service),
                     CloudSyncWording.Headline(service));
        Assert.Equal(wording["summary"]!.ToString(), CloudSyncWording.Summary);
        Assert.Equal(wording["notesStayPut"]!.ToString(), CloudSyncWording.NotesStayPut);
        Assert.Equal(wording["offloadedPagesAreSlow"]!.ToString().Replace("{service}", service),
                     CloudSyncWording.OffloadedPagesAreSlow(service));
        Assert.Equal(wording["syncingCanInterruptAMove"]!.ToString().Replace("{service}", service),
                     CloudSyncWording.SyncingCanInterruptAMove(service));
        Assert.Equal(wording["whatToDo"]!.ToString(), CloudSyncWording.WhatToDo);
        Assert.Equal(wording["useAnywayButton"]!.ToString(), CloudSyncWording.UseAnywayButton);
        Assert.Equal(wording["chooseDifferentFolderButton"]!.ToString(), CloudSyncWording.ChooseDifferentFolderButton);
        Assert.Equal(wording["dismissNoticeButton"]!.ToString(), CloudSyncWording.DismissNoticeButton);
        Assert.Equal(wording["showDetailsButton"]!.ToString(), CloudSyncWording.ShowDetailsButton);
        Assert.Equal(wording["hideDetailsButton"]!.ToString(), CloudSyncWording.HideDetailsButton);
    }

    [Fact]
    public void TheExplanationIsInTheContractsOrderAndHasFourSentences()
    {
        var cloud = ContractLoader.LoadJson("shared-rules.json")["cloudSyncedFolders"]!;
        var order = cloud["wording"]!["explanationOrder"]!.AsArray().Select(x => x!.ToString()).ToList();
        Assert.Equal(4, order.Count);
        Assert.Equal(new[] { "notesStayPut", "offloadedPagesAreSlow", "syncingCanInterruptAMove", "whatToDo" }, order);

        var explanation = CloudSyncWording.Explanation("Dropbox");
        Assert.Equal(4, explanation.Count);
        // Reassurance first: "kept in sync" beside a warning reads as "your
        // notes are at risk", and they are not.
        Assert.Equal(CloudSyncWording.NotesStayPut, explanation[0]);
        Assert.Equal(CloudSyncWording.WhatToDo, explanation[^1]);
    }

    [Fact]
    public void TheRetiredSentenceIsNotShownAnywhere()
    {
        // Retired on BOTH platforms because neither builds inside the working
        // folder any more. The contract keeps its words under
        // `buildFilesAreCopiedRetired` precisely so nobody adds them back.
        var wording = ContractLoader.LoadJson("shared-rules.json")["cloudSyncedFolders"]!["wording"]!;
        Assert.Null(wording["buildFilesAreCopied"]);
        Assert.NotNull(wording["buildFilesAreCopiedRetired"]);

        foreach (string sentence in CloudSyncWording.Explanation("OneDrive"))
            Assert.DoesNotContain("thousands of small files", sentence);
    }

    [Fact]
    public void TheUnknownServiceIsNamedHonestlyRatherThanGuessed()
    {
        var detection = ContractLoader.LoadJson("shared-rules.json")["cloudSyncedFolders"]!["detection"]!;
        Assert.Equal(detection["unknownServiceName"]!.ToString(), CloudSyncedFolder.UnknownServiceName);
    }

    [Fact]
    public void TheTwoTrailEventsAreTheOnesTheContractNames()
    {
        Assert.Equal("synced folder noticed", ActivityTrail.KeyFor(ActivityTrail.Event.SyncedFolderNoticed));
        Assert.Equal("synced folder accepted", ActivityTrail.KeyFor(ActivityTrail.Event.SyncedFolderAccepted));
    }
}

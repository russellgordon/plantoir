using System.Diagnostics;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// <c>shared-rules.json</c> → <c>howITeachPage.settingsButton</c> (GitHub
/// issue #360, the mac's #329): Course Settings' How I Teach row, against a
/// real course folder.
/// </summary>
[Collection(SharedActivityState.Name)]
public class HowITeachSettingsRowTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "plantoir-tests", "hit-row-" + Guid.NewGuid().ToString("N"));

    public HowITeachSettingsRowTests() => Directory.CreateDirectory(_root);

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private static JsonNode Button => ContractLoader.LoadJson("shared-rules.json")["howITeachPage"]!["settingsButton"]!;

    [Fact]
    public void TheRowsWordsAreTheContracts()
    {
        Assert.Equal(Button["rowLabel"]!.ToString(), HowITeachSettingsRow.RowLabel);
        Assert.Equal(Button["openButton"]!.ToString(), HowITeachSettingsRow.OpenButton);
        Assert.Equal(Button["createButton"]!.ToString(), HowITeachSettingsRow.CreateButton);
        Assert.Equal(Button["caption"]!.ToString(), HowITeachSettingsRow.Caption);
        Assert.Equal(Button["couldNotCreate"]!.ToString(), HowITeachSettingsRow.CouldNotCreateTemplate);
        Assert.Equal(Button["createdBytes"]!.ToString(), HowITeachSettingsRow.CreatedBytes);
    }

    [Fact]
    public void EveryCaseIsPressedAsTheContractSays()
    {
        var cases = Button["cases"]!.AsArray();
        Assert.True(cases.Count >= 6, $"settingsButton lost cases: {cases.Count} (6 when this was written)");

        var failures = new List<string>();
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            string course = Path.Combine(_root, Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(course);
            if (c["existing"] is JsonObject existing)
                File.WriteAllText(Path.Combine(course, existing["file"]!.ToString()), existing["text"]!.ToString());
            bool unwritable = c["unwritable"]?.GetValue<bool>() == true;
            if (unwritable) Icacls($"\"{course}\" /deny \"{Environment.UserName}\":(WD,AD)");
            var before = Directory.GetFiles(course).ToDictionary(f => f, File.ReadAllText);

            string button = HowITeachSettingsRow.ButtonFor(course);
            string expectedButton = c["button"]!.ToString() == "openButton" ? HowITeachSettingsRow.OpenButton : HowITeachSettingsRow.CreateButton;
            if (button != expectedButton) failures.Add($"{name}: the button says {button}");

            var (outcome, page, problem) = HowITeachSettingsRow.Press(course, "TEST");
            if (unwritable) Icacls($"\"{course}\" /remove:d \"{Environment.UserName}\"");

            switch (c["expect"]!.ToString())
            {
                case "created":
                    if (outcome != HowITeachSettingsRow.Outcome.Created) { failures.Add($"{name}: {outcome}"); break; }
                    if (File.ReadAllText(page!) != HowITeachSettingsRow.CreatedBytes) failures.Add($"{name}: the made page is not exactly createdBytes");
                    if (Path.GetFileName(page) != HowITeachPage.FileName) failures.Add($"{name}: made {Path.GetFileName(page)}");
                    break;
                case "opened":
                    if (outcome != HowITeachSettingsRow.Outcome.Opened) failures.Add($"{name}: {outcome}");
                    if (Directory.GetFiles(course).Length != before.Count) failures.Add($"{name}: a second file was made");
                    if (before.Any(f => File.ReadAllText(f.Key) != f.Value)) failures.Add($"{name}: the page was written");
                    break;
                default:
                    if (outcome != HowITeachSettingsRow.Outcome.CouldNotCreate || problem is null) failures.Add($"{name}: {outcome}");
                    if (Directory.GetFiles(course).Length != 0) failures.Add($"{name}: something was made");
                    break;
            }
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }

    /// <summary>
    /// The trap: a page the teacher made between the look and the write is
    /// THEIRS, and is what is opened — never written over.
    /// </summary>
    [Fact]
    public void ACreatedPageNeverWritesOverOneMadeAMomentEarlier()
    {
        string course = Path.Combine(_root, "race");
        Directory.CreateDirectory(course);
        string theirs = Path.Combine(course, HowITeachPage.FileName);
        var (outcome, page, _) = HowITeachSettingsRow.Press(course, "TEST",
            betweenTheLookAndTheWrite: () => File.WriteAllText(theirs, "I wrote this just now.\n"));
        Assert.Equal(HowITeachSettingsRow.Outcome.Opened, outcome);
        Assert.Equal(theirs, page);
        Assert.Equal("I wrote this just now.\n", File.ReadAllText(theirs));
    }

    private static void Icacls(string arguments)
    {
        var start = new ProcessStartInfo("icacls", arguments) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true };
        using var process = Process.Start(start)!;
        process.WaitForExit(15000);
        Assert.True(process.ExitCode == 0, "icacls " + arguments + " failed: " + process.StandardError.ReadToEnd());
    }
}

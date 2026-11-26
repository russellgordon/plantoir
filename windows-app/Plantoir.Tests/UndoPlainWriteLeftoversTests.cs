using System.Diagnostics;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// The W7a final review's LOW 3: a plain write (a step swapped in without the
/// list) labels its staged files <c>shadow-&lt;pid&gt;-&lt;id&gt;</c>, and
/// the next swap that meets a gone process's leftovers beside its target
/// tidies them: the staged <c>-new</c>, and a kept <c>-orig</c> that is a copy
/// of its page; a differing <c>-orig</c> (an only copy) and a running
/// process's files stay.
/// </summary>
public sealed class UndoPlainWriteLeftoversTests : IDisposable
{
    // ---- Stored properties ---------------------------------------------------------

    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-plain-leftovers-");

    // ---- Computed properties -------------------------------------------------------

    private string Page => Path.Combine(_root, "Unit 1, Day 1.md");

    // ---- Functions -------------------------------------------------------------------

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private string Beside(string label, string role) => UndoSwap.BesidePath(Page, label, role);

    /// <summary>A process id that has run and ended.</summary>
    private static int AGoneProcess()
    {
        using var process = Process.Start(new ProcessStartInfo("cmd.exe", "/c exit 0") { CreateNoWindow = true, UseShellExecute = false })!;
        process.WaitForExit();
        return process.Id;
    }

    [Fact]
    public void APlainWriteLabelsItsFilesWithItsProcess()
    {
        string label = UndoSwap.PlainLabel();
        Assert.StartsWith($"shadow-{Environment.ProcessId}-", label);
        Assert.NotEqual(label, UndoSwap.PlainLabel());
    }

    [Fact]
    public void TheNextSwapTidiesAGoneProcesssLeftoversAndKeepsAnOnlyCopy()
    {
        File.WriteAllText(Page, "what the page holds");
        int gone = AGoneProcess();
        string staged = Beside($"shadow-{gone}-1", "new");
        string copy = Beside($"shadow-{gone}-1", "orig");
        string onlyCopy = Beside($"shadow-{gone}-2", "orig");
        string running = Beside($"shadow-{Environment.ProcessId}-999", "new");
        File.WriteAllText(staged, "content that never went in");
        File.WriteAllText(copy, "what the page holds");
        File.WriteAllText(onlyCopy, "what the page held before");
        File.WriteAllText(running, "this process's own");

        var step = new UndoActionStep(new UndoStepMaker("menu", "publishPages"), null, null, null,
                                      undo: new UndoForThisProcess(Path.Combine(_root, "undo"), UndoMode.Shadow, null));
        step.Write(Page, "the new content");
        step.Make();

        Assert.Equal("the new content", File.ReadAllText(Page));
        Assert.False(File.Exists(staged), "a gone process's staged file was left");
        Assert.False(File.Exists(copy), "a gone process's kept copy of the page was left");
        Assert.True(File.Exists(onlyCopy), "an only copy was deleted");
        Assert.True(File.Exists(running), "a running process's staged file was removed");
        // The plain write itself leaves nothing of its own behind.
        foreach (string entry in Directory.EnumerateFiles(_root, "." + Path.GetFileName(Page) + UndoSwap.StagedMarker + "*"))
            Assert.True(entry == onlyCopy || entry == running, $"left beside the page: {Path.GetFileName(entry)}");
    }
}

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #899 W6: every contract file Windows PowerShell reads, or may, is read by
/// the REAL Windows PowerShell 5.1 <c>ConvertFrom-Json</c>, the reader
/// <c>windows-app/test_launcher_rules.ps1</c> and <c>test_stop_preview.ps1</c>
/// use on <c>shared-rules.json</c>. It builds each object as a
/// case-insensitive dictionary, so a file holding keys <c>X1</c> and
/// <c>x1</c> in one object cannot be read at all: W6 once put such rows in
/// <c>shared-rules.json</c> and the launcher runners could not start. Those
/// rows live in <c>undo-json-cases.json</c>, which no PowerShell reads.
/// <c>scripts/test_make_undo_traces.py</c> holds the same list of exceptions.
/// </summary>
public class ContractFilesWindowsPowerShellReadsTests
{
    /// <summary>The one contract file no PowerShell reads (its editJSON rows hold keys that differ only by case).</summary>
    private static readonly string[] NotForWindowsPowerShell = { "undo-json-cases.json" };

    // Reads each file named on its own line of PLANTOIR_CONTRACT_FILES and
    // prints "ok <name>" or "FAIL <name>: <why>".
    private const string Reader =
        "foreach ($path in ($env:PLANTOIR_CONTRACT_FILES -split \"`n\")) { if ($path) { " +
        "$name = Split-Path -Leaf $path; " +
        "try { $null = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop; Write-Output \"ok $name\" } " +
        "catch { Write-Output \"FAIL ${name}: $($_.Exception.Message)\" } } }";

    [Fact]
    public void EveryOtherContractFileIsReadByWindowsPowerShellsConvertFromJson()
    {
        string folder = Path.Combine(ContractLoader.RepositoryRoot, "contracts");
        var all = Directory.GetFiles(folder, "*.json").OrderBy(path => path, StringComparer.Ordinal).ToList();
        var names = all.Select(path => Path.GetFileName(path)).ToList();
        Assert.Contains("shared-rules.json", names);
        foreach (string exception in NotForWindowsPowerShell) Assert.Contains(exception, names);
        var read = all.Where(path => !NotForWindowsPowerShell.Contains(Path.GetFileName(path))).ToList();

        string output = RunWindowsPowerShell(read);

        var lines = output.Split('\n').Select(line => line.TrimEnd('\r')).Where(line => line.Length > 0).ToList();
        var failed = lines.Where(line => !line.StartsWith("ok ", StringComparison.Ordinal)).ToList();
        Assert.True(failed.Count == 0,
            "Windows PowerShell 5.1's ConvertFrom-Json cannot read these contract files, so the launcher runners cannot start: " +
            "move the rows it cannot read into a file of their own (as undo-json-cases.json):\n" + string.Join("\n", failed));
        foreach (string path in read) Assert.Contains("ok " + Path.GetFileName(path), lines);
    }

    private static string RunWindowsPowerShell(IReadOnlyList<string> files)
    {
        var info = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        foreach (string argument in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", Reader })
            info.ArgumentList.Add(argument);
        info.Environment["PLANTOIR_CONTRACT_FILES"] = string.Join("\n", files);

        using var process = Process.Start(info);
        Assert.NotNull(process);
        var standardOutput = process!.StandardOutput.ReadToEndAsync();
        var standardError = process.StandardError.ReadToEndAsync();
        if (!process.WaitForExit(120_000))
        {
            try { process.Kill(entireProcessTree: true); } catch { }
            Assert.Fail("Windows PowerShell did not finish reading the contract files within 120 s");
        }
        string output = standardOutput.GetAwaiter().GetResult();
        string errors = standardError.GetAwaiter().GetResult();
        Assert.True(errors.Trim().Length == 0, "Windows PowerShell wrote errors: " + errors);
        return output;
    }
}

using System.Diagnostics;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// <c>referenceCourses.markerAgreement</c>, every row, against the REAL
/// <c>deploy.ps1</c> (#241 §h; door 12, the folder publish, whose branch never
/// enters the shared Python). Each row runs
/// <c>deploy.ps1 &lt;FOLDER&gt; 1 --to-folder &lt;tmp&gt;</c> in a throwaway
/// working folder and asserts: exit 1 and the sentence for a refused row,
/// that the launcher got PAST the check for an allowed one (it prints the
/// timezone line straight after — so a script-path typo is never read as a
/// refusal), and that nothing at all reached the publishing folder.
/// </summary>
public class ReferenceMarkerAgreementTests : IDisposable
{
    private readonly string _root = Directory.CreateTempSubdirectory("plantoir-marker").FullName;

    public void Dispose()
    {
        foreach (string file in Directory.GetFiles(_root, "course_config.json", SearchOption.AllDirectories))
        {
            try
            {
                var info = new FileInfo(file);
                var security = info.GetAccessControl();
                foreach (var rule in security.GetAccessRules(true, false, typeof(SecurityIdentifier)).Cast<FileSystemAccessRule>()
                             .Where(r => r.AccessControlType == AccessControlType.Deny))
                    security.RemoveAccessRuleSpecific(rule);
                info.SetAccessControl(security);
            }
            catch { }
        }
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private const string PastTheCheck = "Host timezone offset:";

    [Fact]
    public void EveryRowAgainstTheRealLauncher()
    {
        var cases = ContractLoader.LoadJson("shared-rules.json")["referenceCourses"]!["markerAgreement"]!["cases"]!.AsArray();
        string runtime = Directory.CreateDirectory(Path.Combine(_root, "runtime")).FullName;
        File.WriteAllText(Path.Combine(runtime, "manifest.json"), "{}");   // a stand-in: the check runs before the runtime is used
        var failures = new List<string>();
        int ran = 0, index = 0;
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            string working = Path.Combine(_root, $"row{index++}");
            string course = Path.Combine(working, "courses", "REF");
            Directory.CreateDirectory(course);
            File.Copy(Path.Combine(ContractLoader.RepositoryRoot, "deploy.ps1"), Path.Combine(working, "deploy.ps1"));
            string config = Path.Combine(course, "course_config.json");
            if (c["configIsADirectory"]?.GetValue<bool>() == true) Directory.CreateDirectory(config);
            else if (c["noConfigFile"]?.GetValue<bool>() != true)
            {
                byte[] text = Encoding.UTF8.GetBytes(c["configText"]!.ToString());
                if (c["bom"]?.GetValue<bool>() == true) text = new byte[] { 0xEF, 0xBB, 0xBF }.Concat(text).ToArray();
                File.WriteAllBytes(config, text);
                if (c["unreadable"]?.GetValue<bool>() == true)
                {
                    var security = new FileInfo(config).GetAccessControl();
                    security.AddAccessRule(new FileSystemAccessRule(WindowsIdentity.GetCurrent().User!, FileSystemRights.ReadData, AccessControlType.Deny));
                    new FileInfo(config).SetAccessControl(security);
                }
            }
            string target = Path.Combine(_root, $"published{index}");
            var (exit, output) = Run(working, runtime, target);
            bool refused = c["expect"]!.ToString() == "refused";
            bool wentPast = output.Contains(PastTheCheck, StringComparison.Ordinal);
            bool saidIt = output.Contains("is kept for reference, so it is never deployed", StringComparison.Ordinal)
                          || output.Contains("cannot tell whether", StringComparison.Ordinal);
            if (Directory.Exists(target) && Directory.EnumerateFileSystemEntries(target, "*", SearchOption.AllDirectories).Any())
                failures.Add($"{name}: something was published");
            if (refused && (exit != 1 || wentPast || !saidIt))
                failures.Add($"{name}: expected a refusal, got exit {exit}: {Tail(output)}");
            if (!refused && (!wentPast || saidIt))
                failures.Add($"{name}: expected the launcher to go on, got exit {exit}: {Tail(output)}");
            if (c["appReadsAsReference"]!.GetValue<bool>() && !refused)
                failures.Add($"{name}: the app reads it as kept, and the launcher let it through");
            ran++;
        }
        Assert.True(ran >= 26, $"only {ran} rows ran");
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }

    private static string Tail(string text) => text.Length > 300 ? text[^300..] : text;

    private static (int Exit, string Output) Run(string working, string runtime, string target)
    {
        var start = new ProcessStartInfo("powershell.exe",
            $"-NoProfile -NonInteractive -ExecutionPolicy Bypass -File deploy.ps1 REF 1 --to-folder \"{target}\" --non-interactive")
        {
            WorkingDirectory = working, UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true,
        };
        start.Environment["PLANTOIR_RUNTIME"] = runtime;
        start.Environment["LOCALAPPDATA"] = Path.Combine(working, "appdata");
        using var process = Process.Start(start)!;
        var output = process.StandardOutput.ReadToEndAsync();
        var errors = process.StandardError.ReadToEndAsync();
        if (!process.WaitForExit(120_000)) { process.Kill(true); return (-1, "timed out"); }
        return (process.ExitCode, output.Result + errors.Result);
    }
}

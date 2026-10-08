using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// Is ANYTHING working on this computer that closing Plantoir — or replacing
/// it — would cut short? One answer for two askers: the UI-test runner before
/// it kills a running copy (#155), and the updater before it installs (#337).
///
/// <para><b>Busy</b> (bundle-8 rulings 2 and 4): any LIVE lease, of any kind,
/// in any working folder this machine's Plantoir knows (its remembered folder
/// and windows), held by another process; OR any running <c>plantoir-mcp</c>
/// at all — one may be publishing in a folder this app has never opened, and
/// the installer would kill it. Liveness is <see cref="WorkLease"/>'s own rule
/// (name and start time match), never a second copy of it.</para>
///
/// <para><b>Known limit</b>: a folder opened only through an outside assistant,
/// or only under <c>--state-dir</c>, is not among the known folders; the
/// running-<c>plantoir-mcp</c> half of the rule covers the first.</para>
/// </summary>
public static class MachineWork
{
    public sealed record Snapshot(IReadOnlyList<(string Folder, WorkLease.Other Lease)> Leases, IReadOnlyList<int> AssistantServers);

    /// <summary>The process name of the outside-assistant server.</summary>
    public const string AssistantServerName = "plantoir-mcp";

    /// <summary>
    /// The working folders the REAL settings name — read from the path given,
    /// never through <see cref="AppDataRoot"/>, which a test or a
    /// <c>--state-dir</c> run may have redirected (plan risk 6).
    /// </summary>
    public static IReadOnlyList<string> KnownFolders(string settingsPath)
    {
        try
        {
            var settings = AppSettings.Load(settingsPath);
            return new[] { settings.WorkspacePath }
                .Concat(settings.RememberedWindows.Select(w => w.Path))
                .Where(p => !string.IsNullOrWhiteSpace(p) && Directory.Exists(p))
                .Select(p => p!)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList();
        }
        catch (Exception) { return Array.Empty<string>(); }
    }

    /// <summary>The real settings file, unredirected.</summary>
    public static string RealSettingsPath() =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Plantoir", "settings.json");

    public static Snapshot Read(IEnumerable<string> folders, Func<IReadOnlyList<int>>? assistantServers = null)
    {
        var leases = folders
            .SelectMany(folder => WorkLease.LiveLeasesOfOthers(folder).Select(lease => (folder, lease)))
            .ToList();
        var servers = (assistantServers ?? RunningAssistantServers)();
        return new Snapshot(leases, servers);
    }

    public static IReadOnlyList<int> RunningAssistantServers()
    {
        try { return Process.GetProcessesByName(AssistantServerName).Select(p => p.Id).ToList(); }
        catch (Exception) { return Array.Empty<int>(); }
    }

    /// <summary>Why the machine is busy, in a sentence for a developer's console; null when it is not.</summary>
    public static string? WhyBusy(Snapshot snapshot)
    {
        if (snapshot.Leases.FirstOrDefault() is { Lease: not null } held)
            return $"Plantoir is {Verb(held.Lease.Kind)} {held.Lease.Course} (pid {held.Lease.Pid}).";
        if (snapshot.AssistantServers.Count > 0)
            return $"An outside assistant's Plantoir server is running (pid {string.Join(", ", snapshot.AssistantServers)}); it may be publishing or deploying.";
        return null;
    }

    private static string Verb(string kind) => kind switch
    {
        WorkLease.Building => "building",
        WorkLease.Publishing => "deploying",
        WorkLease.Previewing => "previewing",
        WorkLease.Assisting => "working with an assistant on",
        WorkLease.Copying => "copying",
        _ => $"busy ({kind}) with",
    };

    /// <summary>
    /// After a KILL, the lease files the killed process can no longer delete:
    /// <c>*.&lt;pid&gt;.lease</c> only, never <c>*.lease</c> — another
    /// program's lease is live work. Returns what was removed.
    /// </summary>
    public static IReadOnlyList<string> SweepLeasesOf(int pid, IEnumerable<string> folders)
    {
        var removed = new List<string>();
        foreach (string folder in folders)
        {
            string dir = Path.Combine(Workspace.CoursesDirectory(folder), ".internal", "activity");
            if (!Directory.Exists(dir)) continue;
            foreach (string file in Directory.EnumerateFiles(dir, $"*.{pid}.lease"))
            {
                try { File.Delete(file); removed.Add(file); } catch (Exception) { }
            }
        }
        return removed;
    }
}

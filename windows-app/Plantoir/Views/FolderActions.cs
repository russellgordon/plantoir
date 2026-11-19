using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.Win32;
using Newtonsoft.Json.Linq;

namespace Plantoir.Views;

/// <summary>
/// Folder and Obsidian actions — every "Show in File Explorer" goes through
/// the same reveal-selected helper so one phrase means one behaviour.
/// </summary>
public static class FolderActions
{
    /// <summary>Reveal the folder selected inside its parent (the file manager's own idiom).</summary>
    public static void ShowInFileExplorer(string path)
    {
        try { Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{path}\"") { UseShellExecute = false }); }
        catch { }
    }

    public static void OpenFolder(string path)
    {
        try { Process.Start(new ProcessStartInfo("explorer.exe", $"\"{path}\"") { UseShellExecute = false }); }
        catch { }
    }

    /// <summary>
    /// Windows Terminal at the folder; classic console as fallback. The folder
    /// is a course's path on disk — a teacher may name a course with a <c>'</c>,
    /// <c>;</c>, <c>&amp;</c> or a trailing <c>\</c> — so it goes as an ARGUMENT,
    /// never spliced into a string. <c>wt.exe</c>'s <c>-d</c> takes it through
    /// <c>ArgumentList</c> (which splits at <c>;</c> if the folder is joined
    /// into the string), and the fallback uses the start info's own
    /// <c>WorkingDirectory</c> with no <c>-Command</c> at all, so there is no
    /// script for a <c>'</c> to break out of.
    /// </summary>
    public static void OpenTerminal(string path)
    {
        try { Process.Start(StartInfoFor(Plantoir.Core.Models.OutsideTerminal.WindowsTerminal(path))); }
        catch
        {
            try { Process.Start(StartInfoFor(Plantoir.Core.Models.OutsideTerminal.Fallback(path))); }
            catch { }
        }
    }

    private static ProcessStartInfo StartInfoFor(Plantoir.Core.Models.OutsideTerminal.Launch launch)
    {
        var info = new ProcessStartInfo(launch.File)
        {
            UseShellExecute = launch.UseShellExecute,
            WorkingDirectory = launch.WorkingDirectory,
        };
        foreach (string argument in launch.Arguments) info.ArgumentList.Add(argument);
        return info;
    }

    // ---- Obsidian --------------------------------------------------------

    public static string ObsidianRegistryPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                     "obsidian", "obsidian.json");

    /// <summary>Something answers obsidian:// links.</summary>
    public static bool ObsidianIsInstalled
    {
        get
        {
            try
            {
                using var key = Registry.ClassesRoot.OpenSubKey("obsidian");
                if (key is not null) return true;
                using var userKey = Registry.CurrentUser.OpenSubKey(@"Software\Classes\obsidian");
                return userKey is not null;
            }
            catch { return false; }
        }
    }

    /// <summary>
    /// Obsidian is running for this teacher: an Obsidian.exe in this Windows
    /// session owns a top-level window, shown or not (#581,
    /// <see cref="ObsidianProcesses"/>). Until #581 this was any process named
    /// Obsidian — another account's, or a crash reporter outliving the windows.
    /// </summary>
    public static bool ObsidianIsRunning => ObsidianProcesses.IsRunning;

    /// <summary>
    /// Obsidian's registry as it is on disk now, or null. Read with
    /// <c>FileShare.ReadWrite</c>: Obsidian rewrites it in place, and a read
    /// that refuses to share would fail at exactly that moment (#581).
    /// </summary>
    public static string? ReadObsidianRegistry()
    {
        try
        {
            if (!File.Exists(ObsidianRegistryPath)) return null;
            using var stream = new FileStream(ObsidianRegistryPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            using var reader = new StreamReader(stream);
            return reader.ReadToEnd();
        }
        catch { return null; }
    }

    /// <summary>Obsidian opens FILES, not folders: target the landing page.</summary>
    public static string ObsidianTarget(string folderPath, string vaultPath)
    {
        if (string.Equals(folderPath, vaultPath, StringComparison.OrdinalIgnoreCase)) return folderPath;
        string index = Path.Combine(folderPath, "index.md");
        return File.Exists(index) ? index : vaultPath;
    }

    public static string ObsidianUri(string path) => Plantoir.Core.Models.PreviewedPageSource.ObsidianLink(path);

    public static bool FolderIsInRegisteredVault(string folderPath, string? registryJson)
    {
        if (registryJson is null) return false;
        try
        {
            if (JToken.Parse(registryJson) is not JObject registry ||
                registry["vaults"] is not JObject vaults) return false;
            foreach (var entry in vaults.Properties())
            {
                if (entry.Value is not JObject vault || vault["path"]?.ToString() is not { } vaultPath) continue;
                if (string.Equals(folderPath, vaultPath, StringComparison.OrdinalIgnoreCase)) return true;
                if (folderPath.StartsWith(vaultPath.TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase))
                    return true;
            }
        }
        catch { }
        return false;
    }

    /// <summary>Adds the vault, preserving every vault the teacher already has.</summary>
    public static string RegistryJsonAfterRegistering(string? existingJson, string vaultPath,
                                                     string identifier, long timestampMs)
    {
        JObject registry;
        try { registry = existingJson is null ? new JObject() : (JObject)JToken.Parse(existingJson); }
        catch { registry = new JObject(); }
        if (registry["vaults"] is not JObject vaults) { vaults = new JObject(); registry["vaults"] = vaults; }
        vaults[identifier] = new JObject { ["path"] = vaultPath, ["ts"] = timestampMs };
        return registry.ToString(Newtonsoft.Json.Formatting.None);
    }

    public static void RegisterVault(string vaultPath)
    {
        try
        {
            string? existing = ReadObsidianRegistry();
            // A registry that is there and could not be read is never replaced
            // by one holding only this vault: that would lose every other one.
            if (existing is null && File.Exists(ObsidianRegistryPath)) return;
            string identifier = string.Concat(Enumerable.Range(0, 16)
                .Select(_ => "0123456789abcdef"[Random.Shared.Next(16)]));
            string updated = RegistryJsonAfterRegistering(existing, vaultPath, identifier,
                DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
            Directory.CreateDirectory(Path.GetDirectoryName(ObsidianRegistryPath)!);
            File.WriteAllText(ObsidianRegistryPath, updated);
        }
        catch { }
    }

    /// <summary>
    /// Opens a folder's landing page, or <paramref name="page"/> when one is
    /// named (the How I Teach row and a section's previewed page), in
    /// Obsidian, registering the course first when Obsidian has never seen it.
    ///
    /// <para><b>Never closes Obsidian (#1003, the mac's #995, D21).</b> Until
    /// #1003 a course a running Obsidian had never seen was registered here by
    /// quitting it, with every vault it had open, and nobody was asked. Now
    /// that case hands nothing over and answers false: the route
    /// (<c>ObsidianOpenRoute</c>) asks "Close Obsidian to open {course}?"
    /// first, and on Close Obsidian and Open calls
    /// <see cref="CloseObsidianAndRegister"/>, after which the course IS
    /// registered and this opens it straight away. The false is also the
    /// backstop for the one moment the route cannot see: Obsidian started
    /// between its check and this call.</para>
    /// </summary>
    public static Task<bool> OpenInObsidian(string revealFolder, string vaultPath, string bundledDefaultsPath,
                                            string? page = null)
    {
        string target = page ?? ObsidianTarget(revealFolder, vaultPath);
        string uri = ObsidianUri(target);
        string? registryJson = ReadObsidianRegistry();
        bool running = ObsidianIsRunning;

        if (FolderIsInRegisteredVault(target, registryJson))
        {
            if (!running) EnableAutoRevealInLayout(vaultPath);
            OpenUri(uri);
            return Task.FromResult(true);
        }
        if (running) return Task.FromResult(false);
        // Obsidian is not running, so its list can be written without closing
        // anything: it reads the list fresh when the link starts it.
        RegisterWithDefaults(vaultPath, bundledDefaultsPath);
        OpenUri(uri);
        return Task.FromResult(true);
    }

    /// <summary>
    /// The answer Close Obsidian and Open (#1003), and ONLY that answer:
    /// notes every vault Obsidian's list marks open (the add-ons' reopen's
    /// rule, <c>ObsidianFigureAddOnsOffer.VaultsOpen</c>, so a hidden
    /// Obsidian's courses come back too), quits Obsidian and waits, and - only
    /// once it is gone - seeds the defaults, patches auto-reveal, registers the
    /// course and opens again what was open. The caller then opens the course
    /// itself, last. If Obsidian did not close (a question of its own on
    /// screen), nothing is written under it and nothing is handed to it.
    /// Answers whether Obsidian closed. The rule is <c>ObsidianClosingRule.CloseAndRegisterAsync</c>.
    /// </summary>
    public static Task<bool> CloseObsidianAndRegister(string vaultPath, string bundledDefaultsPath) =>
        Plantoir.Core.Models.ObsidianClosingRule.CloseAndRegisterAsync(
            vaultPath,
            vaultsMarkedOpen: () => Plantoir.Core.Models.ObsidianFigureAddOnsOffer.VaultsOpen(ObsidianIsRunning, ReadObsidianRegistry()),
            quit: () => QuitObsidianAndWait(),
            stillRunning: () => ObsidianIsRunning,
            register: vault => RegisterWithDefaults(vault, bundledDefaultsPath),
            reopen: paths => ReopenVaults(paths));

    /// <summary>The writes that may happen only while Obsidian is closed: the defaults, auto-reveal, and the course in its list.</summary>
    private static void RegisterWithDefaults(string vaultPath, string bundledDefaultsPath)
    {
        SeedObsidianDefaultsIfMissing(vaultPath, bundledDefaultsPath);
        EnableAutoRevealInLayout(vaultPath);
        RegisterVault(vaultPath);
    }

    private static void OpenUri(string uri)
    {
        try { Process.Start(new ProcessStartInfo(uri) { UseShellExecute = true }); } catch { }
    }

    /// <summary>
    /// Asks Obsidian to quit and waits for it to be gone: up to 5 s for its
    /// windows, then up to 3 s for its processes — at most about 8 s. Returns
    /// whether its processes are gone (<see cref="ObsidianProcesses.QuitAndWaitAsync"/>);
    /// callers decide on <see cref="ObsidianIsRunning"/>, which is its windows.
    /// Since #581 this closes EVERY Obsidian window (<see cref="ObsidianProcesses.QuitAndWaitAsync"/>);
    /// before, <c>CloseMainWindow</c> on each process closed one, so an
    /// Obsidian with two vaults open kept running — and the registration and
    /// rename paths that call this went on to write under it.
    /// </summary>
    public static Task<bool> QuitObsidianAndWait() => ObsidianProcesses.QuitAndWaitAsync();

    /// <summary>
    /// Opens each of these vaults again, in order, so the last is in front
    /// (#581's reopen). The first link starts Obsidian; the rest wait for its
    /// window (at most ten seconds) and then follow a moment apart, rather than
    /// racing Electron's single-instance lock with several starts at once.
    /// </summary>
    public static async Task ReopenVaults(IReadOnlyList<string> vaultPaths)
    {
        for (int i = 0; i < vaultPaths.Count; i++)
        {
            OpenUri(ObsidianUri(vaultPaths[i]));
            if (i == 0) await ObsidianProcesses.WaitUntilRunningAsync(10_000);
            await Task.Delay(400);
        }
    }

    /// <summary>The same defaults every wizard-built course gets (attachments land in Media).</summary>
    public static void SeedObsidianDefaultsIfMissing(string vaultPath, string bundledDefaultsPath)
    {
        try
        {
            string destination = Path.Combine(vaultPath, ".obsidian");
            if (Directory.Exists(destination)) return;
            CopyTree(bundledDefaultsPath, destination);
        }
        catch { }
    }

    private static void CopyTree(string source, string destination)
    {
        Directory.CreateDirectory(destination);
        foreach (string file in Directory.EnumerateFiles(source, "*", SearchOption.AllDirectories))
        {
            string target = Path.Combine(destination, Path.GetRelativePath(source, file));
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            File.Copy(file, target, overwrite: true);
        }
    }

    /// <summary>
    /// Flip autoReveal on in every file-explorer leaf of the vault's saved
    /// layout — only effective while Obsidian is closed (its first open
    /// rebuilds the layout; patching the one it wrote survives).
    /// </summary>
    public static void EnableAutoRevealInLayout(string vaultPath)
    {
        try
        {
            string layoutPath = Path.Combine(vaultPath, ".obsidian", "workspace.json");
            if (!File.Exists(layoutPath)) return;
            var layout = JToken.Parse(File.ReadAllText(layoutPath));
            PatchAutoReveal(layout);
            File.WriteAllText(layoutPath, layout.ToString(Newtonsoft.Json.Formatting.None));
        }
        catch { }
    }

    internal static void PatchAutoReveal(JToken node)
    {
        switch (node)
        {
            case JObject obj:
                foreach (var property in obj.Properties()) PatchAutoReveal(property.Value);
                if (obj["state"] is JObject state && state["type"]?.ToString() == "file-explorer")
                {
                    if (state["state"] is not JObject inner) { inner = new JObject(); state["state"] = inner; }
                    inner["autoReveal"] = true;
                }
                break;
            case JArray array:
                foreach (var element in array) PatchAutoReveal(element);
                break;
        }
    }
}

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

    /// <summary>Windows Terminal at the folder; classic console as fallback.</summary>
    public static void OpenTerminal(string path)
    {
        try
        {
            Process.Start(new ProcessStartInfo("wt.exe", $"-d \"{path}\"") { UseShellExecute = false });
        }
        catch
        {
            try
            {
                Process.Start(new ProcessStartInfo("powershell.exe", $"-NoExit -Command \"Set-Location '{path}'\"")
                { UseShellExecute = true });
            }
            catch { }
        }
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
    /// The full dance. A running Obsidian keeps its vault list in memory and
    /// overwrites the registry on exit, so an unknown vault means: note the
    /// vaults open now, quit it, and — only once it is no longer running —
    /// seed defaults, patch auto-reveal, register, open every vault that was
    /// open again, then open the link, this course last. Obsidian does NOT
    /// bring them back by itself when it is started with a link (measured on
    /// 1.14.4, #581: closing its windows one by one unmarks all but the last).
    /// If Obsidian did not close (a question of its own on screen), nothing is
    /// written under it: the link is opened as it is, the course unregistered.
    /// </summary>
    public static async Task OpenInObsidian(string revealFolder, string vaultPath, string bundledDefaultsPath,
                                            string? page = null)
    {
        // A PAGE, when one is named (the How I Teach row opens the page, not the vault).
        string target = page ?? ObsidianTarget(revealFolder, vaultPath);
        string uri = ObsidianUri(target);
        string? registryJson = ReadObsidianRegistry();

        if (FolderIsInRegisteredVault(target, registryJson))
        {
            if (!ObsidianIsRunning) EnableAutoRevealInLayout(vaultPath);
            OpenUri(uri);
            return;
        }

        var wereOpen = Plantoir.Core.Models.ObsidianFigureAddOnsOffer.VaultsOpen(ObsidianIsRunning, registryJson);
        await QuitObsidianAndWait();
        if (ObsidianIsRunning)
        {
            // Never write under a running Obsidian: it would write its own list back over ours.
            OpenUri(uri);
            return;
        }
        SeedObsidianDefaultsIfMissing(vaultPath, bundledDefaultsPath);
        EnableAutoRevealInLayout(vaultPath);
        RegisterVault(vaultPath);
        await ReopenVaults(wereOpen.Where(path => !Plantoir.Core.Models.ObsidianFigureAddOnsOffer.SamePath(path, vaultPath)).ToList());
        OpenUri(uri);
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

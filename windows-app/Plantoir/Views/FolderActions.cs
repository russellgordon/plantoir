using System;
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

    public static bool ObsidianIsRunning => Process.GetProcessesByName("Obsidian").Length > 0;

    /// <summary>Obsidian opens FILES, not folders: target the landing page.</summary>
    public static string ObsidianTarget(string folderPath, string vaultPath)
    {
        if (string.Equals(folderPath, vaultPath, StringComparison.OrdinalIgnoreCase)) return folderPath;
        string index = Path.Combine(folderPath, "index.md");
        return File.Exists(index) ? index : vaultPath;
    }

    public static string ObsidianUri(string path) =>
        "obsidian://open?path=" + Uri.EscapeDataString(path);

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
            string? existing = File.Exists(ObsidianRegistryPath) ? File.ReadAllText(ObsidianRegistryPath) : null;
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
    /// overwrites the registry on exit, so an unknown vault means: quit it,
    /// seed defaults, patch auto-reveal, register, then open the link
    /// (Obsidian restores its windows on relaunch).
    /// </summary>
    public static async Task OpenInObsidian(string revealFolder, string vaultPath, string bundledDefaultsPath,
                                            string? page = null)
    {
        // A PAGE, when one is named (the How I Teach row opens the page, not the vault).
        string target = page ?? ObsidianTarget(revealFolder, vaultPath);
        string uri = ObsidianUri(target);
        string? registryJson = null;
        try { registryJson = File.Exists(ObsidianRegistryPath) ? File.ReadAllText(ObsidianRegistryPath) : null; }
        catch { }

        if (FolderIsInRegisteredVault(target, registryJson))
        {
            if (!ObsidianIsRunning) EnableAutoRevealInLayout(vaultPath);
            OpenUri(uri);
            return;
        }

        await QuitObsidianAndWait();
        SeedObsidianDefaultsIfMissing(vaultPath, bundledDefaultsPath);
        EnableAutoRevealInLayout(vaultPath);
        RegisterVault(vaultPath);
        OpenUri(uri);
    }

    private static void OpenUri(string uri)
    {
        try { Process.Start(new ProcessStartInfo(uri) { UseShellExecute = true }); } catch { }
    }

    public static async Task QuitObsidianAndWait()
    {
        var running = Process.GetProcessesByName("Obsidian");
        if (running.Length == 0) return;
        foreach (var process in running)
        {
            try { process.CloseMainWindow(); } catch { }
        }
        for (int attempt = 0; attempt < 50; attempt++)
        {
            await Task.Delay(100);
            if (Process.GetProcessesByName("Obsidian").Length == 0) return;
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

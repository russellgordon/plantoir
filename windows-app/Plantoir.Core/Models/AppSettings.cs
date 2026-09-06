using System;
using System.Collections.Generic;
using System.IO;
using Newtonsoft.Json;

namespace Plantoir.Core.Models;

/// <summary>
/// One remembered window: its folder, frame, and sidebar state (row 99).
/// The three sidebar fields are optional so entries written before they
/// existed still load: a null ExpandedCourses restores all-expanded (the
/// Windows fallback), null Selection restores none.
/// </summary>
public sealed record RememberedWindow(string Path, double X, double Y, double Width, double Height,
                                      string? ExpandedCourses = null, bool ShowsArchived = false,
                                      string? Selection = null, bool ShowsBackups = false);

/// <summary>
/// The app's own settings store (%LOCALAPPDATA%\Plantoir\settings.json).
/// Windows has no system window restoration, so the remembered-windows
/// list IS the restoration mechanism — recorded at quit while the windows
/// still exist, replayed at launch when the preference asks for it.
/// </summary>
public sealed class AppSettings
{
    private static AppSettings? _current;
    public static AppSettings Current
    {
        get => _current ??= Load();
        set => _current = value;
    }

    public string? WorkspacePath { get; set; }

    /// <summary>
    /// The teacher's Cloudflare account, asked for once and remembered for
    /// every course. It belongs here rather than in a course's settings for
    /// the same reason the token lives in Credential Manager: it identifies
    /// the teacher, not the course. It is an identifier, not a secret.
    /// </summary>
    public string CloudflareAccountId { get; set; } = "";

    public List<RememberedWindow> RememberedWindows { get; set; } = new();
    /// <summary>No OS-level setting exists here, so it is an app preference — default restore.</summary>
    public bool RestoreWindowsOnLaunch { get; set; } = true;

    /// <summary>
    /// Which assistant the teacher has chosen: "automatic", "smaller", or "larger".
    /// </summary>
    public string AssistantModelChoice { get; set; } = Plantoir.Core.Assist.AssistModelChoice.Automatic;

    /// <summary>
    /// Whether the assistant asks for confirmation before changing anything.
    /// </summary>
    public bool AssistantAsksBeforeChanging { get; set; } = true;

    /// <summary>
    /// How many plans the teacher has accepted app-wide across all sessions.
    /// </summary>
    public int PlansAcceptedCount { get; set; } = 0;

    /// <summary>
    /// Whether the confirmation switch discovery has been mentioned to the teacher.
    /// </summary>
    public bool ConfirmationMentioned { get; set; } = false;

    /// <summary>
    /// Which prompt shelf groups are open in the local AI assistant window (pipe-separated).
    /// </summary>
    public string AssistPromptShelfOpenGroups { get; set; } = "";

    /// <summary>
    /// Stored prompt history per section, keyed by $"AssistPromptHistory-{course.Code}-{section}".
    /// </summary>
    public Dictionary<string, string> AssistPromptHistories { get; set; } = new();

    /// <summary>
    /// Working folders the teacher has already been told are kept in sync by a
    /// cloud service, and said to carry on with anyway.
    ///
    /// <para>Keyed by RESOLVED path, so the same folder reached by a different
    /// spelling is the same folder. Going ahead is remembered for that folder
    /// and neither the choice nor the notice is shown for it again: a folder
    /// that opens on every launch must not interrupt every launch, and the
    /// teacher already answered.</para>
    ///
    /// <para>A list rather than a single flag because a teacher can have
    /// several working folders, and answering for one says nothing about
    /// another.</para>
    /// </summary>
    public List<string> AcceptedSyncedFolders { get; set; } = new();

    /// <summary>
    /// Whether this folder's sync has already been explained and accepted.
    /// Case-insensitive, because Windows paths are.
    /// </summary>
    public bool HasAcceptedSyncFor(string? path)
    {
        if (string.IsNullOrWhiteSpace(path)) return false;
        string resolved = ResolvedForComparison(path!);
        foreach (string accepted in AcceptedSyncedFolders)
            if (ResolvedForComparison(accepted).Equals(resolved, StringComparison.OrdinalIgnoreCase))
                return true;
        return false;
    }

    /// <summary>Remember that this folder's sync was explained and accepted.</summary>
    public void RememberAcceptedSyncFor(string? path)
    {
        if (string.IsNullOrWhiteSpace(path)) return;
        if (HasAcceptedSyncFor(path)) return;
        AcceptedSyncedFolders.Add(path!);
    }

    private static string ResolvedForComparison(string path)
    {
        try { return Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar); }
        catch { return path.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar); }
    }

    /// <summary>
    /// One settings FILE, when a caller wants to name it directly.
    ///
    /// <para><b>This is NOT how a run is isolated.</b> <c>--state-dir</c>
    /// moves the whole <see cref="AppDataRoot"/>, and settings follow it
    /// through <see cref="DefaultPath"/> along with everything else Plantoir
    /// keeps on this PC. Redirecting only the settings file was the first
    /// attempt and it was the wrong shape: it left a UI test consuming the
    /// teacher's real scheduled-deploy sentinels on launch. Reach for
    /// <c>AppDataRoot.RedirectTo</c>, not for this.</para>
    ///
    /// <para>What remains here is the narrow case of a unit test that wants
    /// one named file and nothing else moved.</para>
    /// </summary>
    public static string? PathOverride { get; set; }

    public static string DefaultPath => PathOverride ?? AppDataRoot.Combine("settings.json");

    public static AppSettings Load(string? path = null)
    {
        try
        {
            string file = path ?? DefaultPath;
            if (File.Exists(file) &&
                JsonConvert.DeserializeObject<AppSettings>(File.ReadAllText(file)) is { } settings)
            {
                // A stored folder that no longer exists must not be presented
                // as the working folder.
                if (settings.WorkspacePath is not null && !Directory.Exists(settings.WorkspacePath))
                    settings.WorkspacePath = null;
                settings.RememberedWindows.RemoveAll(w => !Directory.Exists(w.Path));
                return settings;
            }
        }
        catch { }
        return new AppSettings();
    }

    public void Save(string? path = null)
    {
        try
        {
            string file = path ?? DefaultPath;
            Directory.CreateDirectory(Path.GetDirectoryName(file)!);
            File.WriteAllText(file, JsonConvert.SerializeObject(this, Formatting.Indented));
        }
        catch { }
    }
}

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

    public static string DefaultPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                     "Plantoir", "settings.json");

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

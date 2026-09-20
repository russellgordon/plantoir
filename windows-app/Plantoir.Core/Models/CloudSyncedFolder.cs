using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;

namespace Plantoir.Core.Models;

/// <summary>
/// Whether a working folder is kept in sync by a cloud service, and which one.
///
/// <para><b>A synced folder is never refused.</b> Teachers keep their notes in
/// one on purpose — it is how the notes reach an iPad and a second machine — so
/// Plantoir recognises it, says once and in plain words what it costs, lets the
/// teacher decide, and leaves their content where they put it. Refusing was
/// considered and rejected: a hard block is the one answer a teacher cannot opt
/// out of, and it would mean telling them to give up reaching their own notes
/// from other devices. Detection is unreliable in both directions besides — a
/// false refusal is unrecoverable for them, and a synced folder Plantoir cannot
/// see still works.</para>
///
/// <para><b>From markers the system exposes, never from a folder's NAME.</b> A
/// teacher can have a folder literally called "Dropbox" that is not one, and a
/// wrong answer here is shown to them as fact.</para>
///
/// <para>The Windows markers differ from the mac's and are deliberately not
/// shared — see <c>shared-rules.json</c> → <c>cloudSyncedFolders.detection</c>,
/// whose eleven cases are all mac paths. What IS shared is everything a teacher
/// reads and every rule about when they read it.</para>
/// </summary>
public static class CloudSyncedFolder
{
    /// <summary>
    /// What a service is called when the folder is recognisably synced but the
    /// service is not one Plantoir names. Saying so honestly beats guessing.
    /// </summary>
    public const string UnknownServiceName = "your cloud service";

    /// <summary>
    /// The service syncing this folder, or null when nothing says one is.
    ///
    /// <para>Null is a perfectly ordinary answer and never blocks anything: a
    /// service whose client publishes no marker Plantoir can read is simply
    /// unrecognised, which the contract explicitly allows.</para>
    /// </summary>
    public static string? ServiceFor(string? path) => ServiceFor(path, new EnvironmentReader());

    /// <summary>
    /// The rule, with the environment injected so it can be tested without
    /// installing five cloud clients.
    /// </summary>
    public static string? ServiceFor(string? path, IEnvironmentReader environment)
    {
        if (string.IsNullOrWhiteSpace(path)) return null;

        string full;
        try { full = Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar); }
        catch { return null; }
        if (full.Length == 0) return null;

        // OneDrive publishes its roots in the environment. A Desktop or
        // Documents folder moved into OneDrive by "Known Folder Move"
        // physically lives under one of these, so the prefix rule catches it
        // without a special case.
        foreach (string variable in new[] { "OneDrive", "OneDriveConsumer", "OneDriveCommercial" })
        {
            string? root = environment.Variable(variable);
            if (IsInside(full, root)) return "OneDrive";
        }

        // Dropbox records every synced root, personal and business, in its own
        // info.json. Read rather than guessed: a teacher can move the Dropbox
        // folder anywhere.
        foreach (string root in DropboxRoots(environment))
            if (IsInside(full, root)) return "Dropbox";

        // iCloud for Windows, at its default location. The client's own
        // setting would be better and is not reliably readable; an unrecognised
        // custom location is allowed.
        string? profile = environment.Variable("USERPROFILE");
        if (!string.IsNullOrEmpty(profile) && IsInside(full, Path.Combine(profile!, "iCloudDrive")))
            return "iCloud Drive";

        // Google Drive and Box are recognised only where their clients publish
        // a mount point in the environment. Otherwise unrecognised — allowed.
        if (IsInside(full, environment.Variable("GoogleDriveMount"))) return "Google Drive";
        if (IsInside(full, environment.Variable("BoxDrive"))) return "Box";

        return null;
    }

    /// <summary>Whether this folder is synced by anything Plantoir can see.</summary>
    public static bool IsSynced(string? path) => ServiceFor(path) is not null;

    /// <summary>
    /// Every root Dropbox says it syncs, from its own info.json.
    ///
    /// <para>Both locations are read because Dropbox has used each: the file is
    /// in <c>%APPDATA%</c> for some installs and <c>%LOCALAPPDATA%</c> for
    /// others. A malformed or unreadable file yields nothing rather than
    /// throwing — this runs while a teacher is choosing a folder, and a crash
    /// there would be far worse than an unrecognised service.</para>
    /// </summary>
    private static IEnumerable<string> DropboxRoots(IEnvironmentReader environment)
    {
        var roots = new List<string>();
        foreach (string variable in new[] { "APPDATA", "LOCALAPPDATA" })
        {
            string? baseDir = environment.Variable(variable);
            if (string.IsNullOrEmpty(baseDir)) continue;
            string info = Path.Combine(baseDir!, "Dropbox", "info.json");
            string text;
            try
            {
                if (!environment.FileExists(info)) continue;
                text = environment.ReadAllText(info);
            }
            catch { continue; }

            try
            {
                using var document = JsonDocument.Parse(text);
                if (document.RootElement.ValueKind != JsonValueKind.Object) continue;
                // { "personal": { "path": "..." }, "business": { "path": "..." } }
                foreach (var account in document.RootElement.EnumerateObject())
                {
                    if (account.Value.ValueKind != JsonValueKind.Object) continue;
                    if (account.Value.TryGetProperty("path", out var p) && p.ValueKind == JsonValueKind.String)
                    {
                        string? root = p.GetString();
                        if (!string.IsNullOrWhiteSpace(root)) roots.Add(root!);
                    }
                }
            }
            catch (JsonException) { continue; }
        }
        return roots;
    }

    /// <summary>
    /// Whether <paramref name="candidate"/> IS <paramref name="root"/> or sits
    /// inside it — ending at a path boundary, never as a bare substring, so
    /// <c>C:\Users\x\OneDrive2</c> is not inside <c>C:\Users\x\OneDrive</c>.
    /// Case-insensitive, because Windows filesystems are.
    /// </summary>
    private static bool IsInside(string candidate, string? root)
    {
        if (string.IsNullOrWhiteSpace(root)) return false;
        string normalised;
        try { normalised = Path.GetFullPath(root!).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar); }
        catch { return false; }
        if (normalised.Length == 0) return false;

        if (candidate.Equals(normalised, StringComparison.OrdinalIgnoreCase)) return true;
        return candidate.StartsWith(normalised + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)
            || candidate.StartsWith(normalised + Path.AltDirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    }
}

/// <summary>
/// The bits of the machine the rule asks about. Injected so the detection can
/// be tested without five cloud clients installed.
/// </summary>
public interface IEnvironmentReader
{
    string? Variable(string name);
    bool FileExists(string path);
    string ReadAllText(string path);
}

/// <summary>The real machine.</summary>
public sealed class EnvironmentReader : IEnvironmentReader
{
    public string? Variable(string name) => Environment.GetEnvironmentVariable(name);
    public bool FileExists(string path) => File.Exists(path);
    public string ReadAllText(string path) => File.ReadAllText(path);
}

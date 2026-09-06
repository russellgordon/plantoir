using System.Text.Json;
using System.Text.Json.Serialization;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Assist;

/// <summary>
/// The other half of the record a scheduled deploy leaves behind. Its
/// wrapper script (see <see cref="TaskScheduling"/>) fingerprints the
/// section right before deploying and, if every destination succeeds,
/// writes a sentinel file naming what happened — because the scheduled
/// task runs `powershell.exe` directly, with no app process alive to stamp
/// <c>.publish_state</c> itself. This class is where the app applies that
/// sentinel: stamping the section's publish state the same way an
/// interactive deploy does, and consuming the sentinel either way, so a
/// deploy that failed to record cleanly cannot be mistaken, tomorrow, for
/// one that succeeded.
///
/// See WINDOWS-HANDOFF.md, "A scheduled deploy needs its own path to the
/// same record".
/// </summary>
public static class ScheduledDeployCompletion
{
    private sealed class Sentinel
    {
        [JsonPropertyName("courseCode")]
        public string CourseCode { get; set; } = "";

        [JsonPropertyName("sectionNumber")]
        public int SectionNumber { get; set; }

        [JsonPropertyName("courseDirectory")]
        public string CourseDirectory { get; set; } = "";

        [JsonPropertyName("fingerprint")]
        public string Fingerprint { get; set; } = "";

        [JsonPropertyName("destinationTypes")]
        public List<string> DestinationTypes { get; set; } = new();

        [JsonPropertyName("destinationNames")]
        public List<string> DestinationNames { get; set; } = new();

        [JsonPropertyName("completedAtUtc")]
        public DateTime CompletedAtUtc { get; set; }
    }

    private static readonly JsonSerializerOptions ReadOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    /// <summary>
    /// %LOCALAPPDATA%\Plantoir\scheduled\pending — not a temp folder, for the
    /// same reason the wrapper scripts themselves live under LOCALAPPDATA:
    /// nothing here should be swept away before the app gets a chance to
    /// look at it.
    /// </summary>
    public static string PendingDirectory() =>
        Plantoir.Core.Models.AppDataRoot.Combine("scheduled", "pending");

    /// <summary>
    /// Applies every pending scheduled-deploy sentinel found on disk, then
    /// deletes it — whether or not applying it actually worked, so a
    /// malformed or already-handled sentinel cannot sit there being reread
    /// forever. Call once when the app starts and once whenever it becomes
    /// active again, the same triggers <c>RefreshPublishedMarker</c> already
    /// uses for the interactive marker, so a scheduled deploy that ran
    /// overnight is reflected the moment a teacher looks at the window.
    /// Safe to call with nothing pending, and safe to call from more than
    /// one open window — applying the same sentinel twice would simply
    /// record the same publish twice, and it is deleted after the first.
    /// </summary>
    public static void ConsumePending() => ConsumePendingFrom(PendingDirectory());

    /// <summary>The same walk as <see cref="ConsumePending"/>, against an arbitrary directory — what the tests use.</summary>
    public static void ConsumePendingFrom(string dir)
    {
        IEnumerable<string> files;
        try { files = Directory.EnumerateFiles(dir, "*.json").ToList(); }
        catch { return; } // nothing pending, or the folder does not exist yet — both fine

        foreach (string file in files)
        {
            try { Apply(file); }
            catch { /* a malformed sentinel is litter, not a crash */ }
            finally { try { File.Delete(file); } catch { /* best effort */ } }
        }
    }

    private static void Apply(string sentinelPath)
    {
        string json = File.ReadAllText(sentinelPath);
        var sentinel = JsonSerializer.Deserialize<Sentinel>(json, ReadOptions);
        if (sentinel is null || string.IsNullOrEmpty(sentinel.Fingerprint)) return;
        if (!Directory.Exists(sentinel.CourseDirectory)) return; // course removed or renamed since scheduling

        bool recorded = SectionPublishState.RecordPublish(
            sentinel.CourseDirectory, sentinel.SectionNumber, sentinel.Fingerprint,
            sentinel.DestinationTypes, sentinel.CompletedAtUtc);

        string joined = MultiDestinationDeployRunner.JoinedWithAnd(sentinel.DestinationNames);
        string sentence = recorded
            ? $"marked {sentinel.CourseCode}-S{sentinel.SectionNumber}'s pages as published to {joined} (scheduled deploy)"
            : $"{sentinel.CourseCode}-S{sentinel.SectionNumber}'s scheduled deploy went out to {joined}, but could not be noted down — the window will still say Edited";
        ActivityTrail.Note(ActivityTrail.Event.SectionContentMarkedPublished, sentence, sentinel.CourseCode, sentinel.SectionNumber);
    }
}

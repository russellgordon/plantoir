namespace Plantoir.Core.Models;

/// <summary>
/// The three entries of a course's <c>.obsidian</c> that EVERY route making a
/// reference course leaves behind (#298, mac #255;
/// <c>shared-rules.json → referenceCourses.obsidianAddOns</c>):
/// <c>plugins/</c>, <c>community-plugins.json</c> and <c>publish.json</c>. An
/// add-on runs code with network access, and a publishing add-on keeps its
/// credential in its own settings — copied, it would be a way to publish a
/// reference course outside every refusal, and a credential in every backup.
///
/// <para>Anchored at the course's OWN top-level <c>.obsidian</c> and compared
/// as a PATH, never as a name: a teacher's own folder of pages called
/// <c>plugins</c> anywhere else comes across (case 4). A <c>.obsidian</c> that
/// is itself a link — any reparse point, a junction included — is not copied
/// at all, and nothing is ever written through it.</para>
/// </summary>
public static class ObsidianAddOns
{
    public const string SettingsFolderName = ".obsidian";

    /// <summary>What is left behind, relative to the settings folder.</summary>
    public static readonly IReadOnlyList<string> LeftBehindInsideTheSettingsFolder =
        new[] { "plugins", "community-plugins.json", "publish.json" };

    /// <summary>The same, relative to the course, '/'-separated — what the tree walk compares against.</summary>
    public static readonly IReadOnlySet<string> LeftBehindFromTheCourse =
        LeftBehindInsideTheSettingsFolder.Select(entry => SettingsFolderName + "/" + entry).ToHashSet(StringComparer.Ordinal);

    /// <summary>What a course had to leave behind. Names are FOLDER names; nothing inside an add-on is ever opened.</summary>
    public sealed record Found(
        IReadOnlyList<string> AddOnNames,
        bool AddOnsFolderIsALink = false,
        bool AddOnsFolderCouldNotBeRead = false,
        bool SettingsFolderIsALink = false,
        bool PublishSiteIsSet = false)
    {
        public static readonly Found None = new(Array.Empty<string>());

        /// <summary>
        /// Whether there is anything to SAY (<c>hasAddOnsWhen</c>). An empty
        /// <c>plugins/</c> and a <c>[]</c> list say nothing: telling a teacher
        /// their add-ons were left behind when they had none is false.
        /// </summary>
        public bool IsEmpty => AddOnNames.Count == 0 && !AddOnsFolderIsALink && !AddOnsFolderCouldNotBeRead
                               && !SettingsFolderIsALink && !PublishSiteIsSet;
    }

    /// <summary>Looks at a course's settings folder: names only, one level, never inside an add-on.</summary>
    public static Found FoundIn(string courseDirectory)
    {
        string settings = Path.Combine(courseDirectory, SettingsFolderName);
        var settingsInfo = new DirectoryInfo(settings);
        if (!settingsInfo.Exists) return Found.None;
        if (settingsInfo.Attributes.HasFlag(FileAttributes.ReparsePoint)) return Found.None with { SettingsFolderIsALink = true };

        var names = new List<string>();
        bool pluginsIsALink = false, pluginsUnreadable = false;
        var plugins = new DirectoryInfo(Path.Combine(settings, "plugins"));
        if (plugins.Exists)
        {
            if (plugins.Attributes.HasFlag(FileAttributes.ReparsePoint)) pluginsIsALink = true;
            else
            {
                try
                {
                    names = plugins.EnumerateFileSystemInfos("*", ReferenceLock.Unfiltered)
                        .Select(entry => entry.Name).Where(name => !name.StartsWith('.'))
                        .OrderBy(name => name, StringComparer.Ordinal).ToList();
                }
                catch { pluginsUnreadable = true; }
            }
        }
        bool publish = File.Exists(Path.Combine(settings, "publish.json")) || Directory.Exists(Path.Combine(settings, "publish.json"));
        return new Found(names, pluginsIsALink, pluginsUnreadable, false, publish);
    }

    /// <summary>
    /// What a trail line adds when there was anything — folder names only —
    /// and nothing at all when there was not, so the line is byte-identical to
    /// one written before #255.
    /// </summary>
    public static string TrailClause(Found found)
    {
        var clauses = new List<string>();
        if (found.AddOnNames.Count > 0)
            clauses.Add($"{found.AddOnNames.Count} Obsidian {(found.AddOnNames.Count == 1 ? "add-on" : "add-ons")} left behind ({string.Join(", ", found.AddOnNames)})");
        if (found.AddOnsFolderIsALink) clauses.Add("Obsidian's add-ons folder was a link and was left behind");
        if (found.AddOnsFolderCouldNotBeRead) clauses.Add("Obsidian's add-ons folder could not be read and was left behind");
        if (found.SettingsFolderIsALink) clauses.Add("Obsidian's settings folder was a link and was left behind");
        if (found.PublishSiteIsSet) clauses.Add("Obsidian Publish's site setting was left behind");
        return string.Concat(clauses.Select(clause => "; " + clause));
    }
}

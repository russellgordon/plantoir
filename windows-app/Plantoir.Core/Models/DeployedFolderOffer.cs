using System.Text.RegularExpressions;
using Plantoir.Core.Assist;

namespace Plantoir.Core.Models;

/// <summary>
/// Whether a section's deployed folder can be opened in the browser, and if
/// not, why (#889, the mac's #850). <see cref="Decide"/> is pure and is
/// <c>contracts/shared-rules.json</c> → <c>deployedFolderInBrowser.offeredCases</c>;
/// <see cref="LookUp"/> gathers the facts from the SAVED settings and the disk,
/// and is called on events (the section shows, a deploy ends, a menu opens, the
/// pointer reaches the button, a show starts or stops), never on a clock
/// (<c>offeredWhen</c>).
/// </summary>
public static class DeployedFolderOffer
{
    /// <summary>The facts the decision reads (<c>offeredDefaults</c> are the defaults).</summary>
    public sealed record Facts
    {
        /// <summary>The course deploys to a folder, as its first destination or another one.</summary>
        public bool HasFolderDestination { get; init; }

        /// <summary>The course is kept for reference: never deployed, so nothing to show.</summary>
        public bool KeptForReference { get; init; }

        /// <summary>A deploy of this section is running, from this app or another program (the course's publish lease), so the folder is half copied.</summary>
        public bool DeployIsRunning { get; init; }

        /// <summary>The folder the course deploys into is there.</summary>
        public bool FolderExists { get; init; }

        /// <summary><c>&lt;folder&gt;\section&lt;N&gt;\index.html</c> is there.</summary>
        public bool SectionIndexExists { get; init; }
    }

    /// <summary>What the decision is.</summary>
    public enum Kind
    {
        /// <summary>Open in Browser opens the deployed folder.</summary>
        Offered,

        /// <summary>Greyed, with <see cref="Decision.ReasonKey"/> saying why.</summary>
        Greyed,

        /// <summary>Not offered: the result panel has no button, the menu greys its item with no reason, the row's context menu hides it.</summary>
        Absent,
    }

    /// <summary>The decision, and for a greyed one the reason's key: <c>deployIsRunning</c>, <c>folderNotFound</c> or <c>notDeployedYet</c>.</summary>
    public sealed record Decision(Kind Kind, string? ReasonKey = null)
    {
        public static readonly Decision Offered = new(Kind.Offered);
        public static readonly Decision Absent = new(Kind.Absent);
    }

    /// <summary>The decision for a set of facts.</summary>
    public static Decision Decide(Facts facts)
    {
        if (facts.KeptForReference || !facts.HasFolderDestination) return Decision.Absent;
        if (facts.DeployIsRunning) return new Decision(Kind.Greyed, "deployIsRunning");
        if (!facts.FolderExists) return new Decision(Kind.Greyed, "folderNotFound");
        if (!facts.SectionIndexExists) return new Decision(Kind.Greyed, "notDeployedYet");
        return Decision.Offered;
    }

    /// <summary>The sentence a reason key stands for, or null for none: the greyed item's tooltip and the Section menu's reason.</summary>
    public static string? Sentence(string? reasonKey) => reasonKey switch
    {
        "deployIsRunning" => CourseActivity.AvailableOnceDeployCompleted,
        "folderNotFound" => DeployedFolderWording.FolderNotFound,
        "notDeployedYet" => DeployedFolderWording.NotDeployedYet,
        _ => null,
    };

    // ---- Which folder -----------------------------------------------------------------

    /// <summary>
    /// The folder setting a course deploys into, as written in its settings: the
    /// first destination when that is a folder, otherwise the first other one
    /// that is (a course has at most one). Null when it has none. A setting of
    /// only spaces is none, as <see cref="CourseConfiguration.DeploysToLocalFolder"/> says.
    /// </summary>
    public static string? FolderSetting(CourseConfiguration configuration)
    {
        if (configuration.DeployTarget == "local_folder" && configuration.DeployFolderPath.Trim().Length > 0)
            return configuration.DeployFolderPath;
        foreach (var target in configuration.AdditionalDeployTargets)
            if (target.Type == "local_folder" && target.Path.Trim().Length > 0) return target.Path;
        return null;
    }

    private static readonly Regex FullyQualified = new(@"^[A-Za-z]:[\\/]|^[\\/][\\/]", RegexOptions.CultureInvariant);
    private static readonly Regex DriveOrRootRelative = new(@"^[A-Za-z]:|^[\\/]", RegexOptions.CultureInvariant);

    /// <summary>
    /// Where <c>deploy.ps1 --to-folder</c> deploys, resolved exactly as its
    /// <c>Resolve-PublishFolder</c> resolves it (the plan review's M5): the value
    /// TRIMMED (the same trim <see cref="DeployCommand.Arguments(string, int, CourseConfiguration.DeployDestination, string, bool)"/>
    /// makes before handing it over); a drive and a separator, or a UNC path,
    /// made full as it is; a DRIVE-relative (<c>C:out</c>) or ROOT-relative
    /// (<c>\out</c>) path refused (null, so the folder is "not found", never a
    /// folder resolved against this app's own current folder); anything else
    /// taken from the working folder. <c>DeployedFolderOfferTests</c> runs the
    /// launcher's own function beside this one on the same inputs.
    /// </summary>
    public static string? DeployFolder(string setting, string workingFolder)
    {
        string p = setting.Trim();
        if (p.Length == 0) return null;
        try
        {
            if (FullyQualified.IsMatch(p)) return Path.GetFullPath(p);
            if (DriveOrRootRelative.IsMatch(p)) return null;
            return Path.GetFullPath(Path.Join(workingFolder, p));
        }
        catch (Exception e) when (e is ArgumentException or NotSupportedException or PathTooLongException)
        {
            return null;
        }
    }

    /// <summary>
    /// Where a section is deployed: <see cref="DeployFolder"/> with its trailing
    /// separators taken off and <c>section&lt;N&gt;</c> added, as deploy.ps1
    /// builds its target (<c>[IO.Path]::Combine($folderAsked.TrimEnd('\','/'), "section{N}")</c>).
    /// </summary>
    public static string? SectionFolder(string setting, string workingFolder, int sectionNumber) =>
        DeployFolder(setting, workingFolder) is { } folder
            ? Path.Combine(folder.TrimEnd('\\', '/'), "section" + sectionNumber)
            : null;

    // ---- The facts, read now ----------------------------------------------------------

    /// <summary>What a section's Open in Browser can do right now, and the folder it would show.</summary>
    /// <param name="Facts">What was read.</param>
    /// <param name="Decision">What it decides.</param>
    /// <param name="SectionFolder"><c>&lt;folder&gt;\section&lt;N&gt;</c> when the course deploys to a folder that can be resolved; null otherwise.</param>
    public sealed record Lookup(Facts Facts, Decision Decision, string? SectionFolder);

    /// <summary>
    /// The facts and the decision for a section, read NOW from its SAVED settings
    /// (<c>course_config.json</c> on disk, what a deploy uses, not the window's
    /// unsaved copy) and the disk. "A deploy is running" is this app's own deploy
    /// of the section (<see cref="CourseActivity.IsPublishingSection"/>) or ANY
    /// other program's publish lease on the course (scheduled, an outside
    /// assistant, the command line: leases are per course, so another section's
    /// deploy greys this one too while it runs).
    /// </summary>
    /// <param name="course">The course, as the window holds it.</param>
    /// <param name="sectionNumber">The section.</param>
    /// <param name="workingFolder">The working folder, spelt as the window registers its deploys with <see cref="CourseActivity"/>.</param>
    /// <param name="files">The disk; a test's map in tests.</param>
    public static Lookup LookUp(Course course, int sectionNumber, string workingFolder, ILocalFiles? files = null)
    {
        files ??= WindowsLocalFiles.Instance;
        CourseConfiguration configuration;
        try { configuration = CourseConfiguration.Load(course.ConfigFilePath); }
        catch { configuration = course.Configuration; }

        var facts = new Facts { KeptForReference = configuration.KeptForReference };
        if (FolderSetting(configuration) is not { } setting)
            return new Lookup(facts, Decide(facts), null);
        facts = facts with { HasFolderDestination = true };

        string? folder = DeployFolder(setting, workingFolder);
        string? section = SectionFolder(setting, workingFolder, sectionNumber);
        bool folderExists = folder is not null && files.FinalPath(folder) is { } realFolder && files.IsFolder(realFolder);
        bool indexExists = section is not null && files.FinalPath(Path.Join(section, "index.html")) is { } realIndex && !files.IsFolder(realIndex);
        bool running = CourseActivity.IsPublishingSection(workingFolder, course.Code, sectionNumber)
                       || WorkLease.IsHeld(workingFolder, course.Code, WorkLease.Publishing);
        facts = facts with { FolderExists = folderExists, SectionIndexExists = indexExists, DeployIsRunning = running };
        return new Lookup(facts, Decide(facts), section);
    }
}

/// <summary>
/// What a teacher reads about a deployed folder opened in the browser
/// (<c>deployedFolderInBrowser.wording</c>, pinned key by key by
/// <c>DeployedFolderOfferTests</c>). None of it promises how a web host will
/// behave (#849), and none names what answers the browser (rule 1).
/// </summary>
public static class DeployedFolderWording
{
    public const string ResultButton = "Open in Browser";
    public const string MenuItem = "Open in Browser";
    public const string StopMenuItem = "Stop Showing Deployed Folder";
    public const string StopButton = "Stop";
    public const string StopHint = "Stop showing the deployed folder in your web browser";
    public const string Help = "Open the deployed folder in your web browser, so its links and features work";
    public const string PreviewHelp = "Open this preview in your web browser";
    public const string NotDeployedYet = "Nothing has been deployed to this section’s folder yet. Deploy it first.";
    public const string FolderNotFound = "Plantoir can’t find this section’s deploy folder. If it’s on a drive, connect the drive, or deploy again.";
    public const string StoppedFolderGone = "Your deployed folder is no longer where it was, so Plantoir stopped showing it.";
    public const string CouldNotOpenTitle = "Your Deployed Folder Could Not Be Opened";
    public const string CouldNotOpen = "Plantoir could not show this folder in your web browser. Try again, or restart your computer if it happens again.";
    public const string RenderNote = "Opened straight from the folder, its pages won’t work. Click Open in Browser to see them working.";
    public const string DismissButton = "Dismiss";
    public const string CouldNotOpenButton = "OK";

    /// <summary>The notice in the section's window while its folder is shown.</summary>
    public static string Notice(int section) => $"Section {section}’s deployed folder is open in your web browser.";

    /// <summary>The template of <see cref="Notice"/>, as the contract writes it, for the test.</summary>
    public const string NoticeTemplate = "Section {section}’s deployed folder is open in your web browser.";
}

/// <summary>
/// Which address a deployed folder is shown at (<c>deployedFolderInBrowser.address</c>):
/// the same one each time, so ticked tasks and quiz answers the site keeps per
/// address are still there (Russell, 2026-11-13). A block of its own, 41000 to
/// 41399, below the range Windows hands out for outgoing connections and moves
/// Hyper-V reservations around in (49152 and up), and outside the preview walk
/// (8081 to 9474). The remembered port first, then the block from an FNV-1a hash
/// of the folder's canonical path, wrapping.
/// </summary>
public static class DeployedFolderAddress
{
    public const int FirstPort = 41000;
    public const int BlockSize = 400;

    /// <summary>FNV-1a, 32 bits, over the path's UTF-8 bytes.</summary>
    public static uint Hash(string path)
    {
        uint value = 2166136261;
        foreach (byte b in System.Text.Encoding.UTF8.GetBytes(path))
        {
            value ^= b;
            value = unchecked(value * 16777619);
        }
        return value;
    }

    /// <summary>Where the walk starts for a folder.</summary>
    public static int StartingPort(string canonicalPath) => FirstPort + (int)(Hash(canonicalPath) % BlockSize);

    /// <summary>Whether a port is one of the block's.</summary>
    public static bool IsInTheBlock(int port) => port >= FirstPort && port < FirstPort + BlockSize;

    /// <summary>Every port to try, in order: the remembered one when it is in the block, then the whole block from the folder's own starting port, wrapping, each once.</summary>
    public static IReadOnlyList<int> Candidates(string canonicalPath, int? remembered)
    {
        var result = new List<int>(BlockSize + 1);
        if (remembered is { } port && IsInTheBlock(port)) result.Add(port);
        int start = StartingPort(canonicalPath) - FirstPort;
        for (int step = 0; step < BlockSize; step++)
        {
            int candidate = FirstPort + (start + step) % BlockSize;
            if (!result.Contains(candidate)) result.Add(candidate);
        }
        return result;
    }

    /// <summary>
    /// The folder's canonical path: its ON-DISK spelling with every link
    /// followed (<c>GetFinalPathNameByHandle</c>, the <c>\\?\</c> prefix taken
    /// off), so <c>C:\users\…</c> and <c>C:\Users\…</c> hash to the same port
    /// (measured by the planner: the two spellings of one path hash 41143 and
    /// 41047). Null when nothing is there.
    /// </summary>
    public static string? CanonicalPath(string path, ILocalFiles? files = null) =>
        (files ?? WindowsLocalFiles.Instance).FinalPath(path);

    /// <summary>The address a browser is handed for a port.</summary>
    public static Uri AddressOf(int port) => new("http://127.0.0.1:" + port + "/");
}

/// <summary>Where the remembered ports are kept: by canonical folder path.</summary>
public interface IDeployedFolderPorts
{
    int? Remembered(string canonicalPath);

    void Remember(string canonicalPath, int port);
}

/// <summary>The remembered ports in <see cref="AppSettings.DeployedFolderPorts"/>, saved at once.</summary>
public sealed class SettingsDeployedFolderPorts : IDeployedFolderPorts
{
    public static readonly SettingsDeployedFolderPorts Instance = new();

    private static readonly object Gate = new();

    public int? Remembered(string canonicalPath)
    {
        lock (Gate)
            return AppSettings.Current.DeployedFolderPorts.TryGetValue(canonicalPath, out int port) ? port : null;
    }

    public void Remember(string canonicalPath, int port)
    {
        lock (Gate)
        {
            var settings = AppSettings.Current;
            if (settings.DeployedFolderPorts.TryGetValue(canonicalPath, out int known) && known == port) return;
            settings.DeployedFolderPorts[canonicalPath] = port;
            settings.Save();
        }
    }
}

/// <summary>A test's or a headless run's memory of ports, kept in the process only.</summary>
public sealed class InMemoryDeployedFolderPorts : IDeployedFolderPorts
{
    private readonly Dictionary<string, int> _ports = new(StringComparer.Ordinal);

    public int? Remembered(string canonicalPath)
    {
        lock (_ports) return _ports.TryGetValue(canonicalPath, out int port) ? port : null;
    }

    public void Remember(string canonicalPath, int port)
    {
        lock (_ports) _ports[canonicalPath] = port;
    }
}

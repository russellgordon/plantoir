namespace Plantoir.Core.Models;

/// <summary>Where Open in Browser was pressed, for the trail (<c>activityTrail.mustRecord</c> → "deployed folder opened in the web browser").</summary>
public enum DeployedFolderFrom
{
    /// <summary>Beside Show in File Explorer under a finished folder deploy.</summary>
    Result,
    SectionMenu,
    Toolbar,
    Sidebar,
}

/// <summary>Why a show ended, for the trail.</summary>
public enum DeployedFolderStopReason
{
    StopPressed,
    PlantoirQuit,
    FolderGone,
    /// <summary>The listener ended without being asked (the mac's implementation review L4).</summary>
    EndedOnItsOwn,
}

/// <summary>Why opening did not happen, for the trail and for which sentence the window shows.</summary>
public enum DeployedFolderCouldNotOpen
{
    FolderNotFound,
    NothingDeployed,
    NoFreeAddress,
    BrowserDidNotOpen,
}

/// <summary>
/// Something that happened to a show, raised by <see cref="DeployedFolderShows.Happened"/>
/// for the window to write on the trail (889b owns the three
/// <c>ActivityTrail.Event</c> members; this Core writes no trail line itself).
/// Each carries the course and section and nothing else that names a place:
/// never the folder's path, never the address (an address is a page name).
/// </summary>
public abstract record DeployedFolderHappening(string CourseCode, int SectionNumber)
{
    /// <summary>The trail's sentence for this happening, as <c>activityTrail.mustRecord</c> writes it.</summary>
    public abstract string TrailLine { get; }

    /// <summary>Open in Browser handed the browser an address.</summary>
    public sealed record Opened(string CourseCode, int SectionNumber, DeployedFolderFrom From, bool AlreadyOpen, bool AddressMoved)
        : DeployedFolderHappening(CourseCode, SectionNumber)
    {
        public override string TrailLine => DeployedFolderTrail.OpenedLine(From, AlreadyOpen, AddressMoved);
    }

    /// <summary>A show ended.</summary>
    public sealed record Stopped(string CourseCode, int SectionNumber, DeployedFolderStopReason Reason, int Requests, int Missing)
        : DeployedFolderHappening(CourseCode, SectionNumber)
    {
        public override string TrailLine => DeployedFolderTrail.StoppedLine(Reason, Requests, Missing);
    }

    /// <summary>Open in Browser could not open it.</summary>
    public sealed record CouldNotOpen(string CourseCode, int SectionNumber, DeployedFolderCouldNotOpen Why)
        : DeployedFolderHappening(CourseCode, SectionNumber)
    {
        public override string TrailLine => DeployedFolderTrail.CouldNotOpenLine(Why);
    }
}

/// <summary>The trail's three sentences for a deployed folder (<c>activityTrail.mustRecord</c>), pinned against the contract's <c>line</c> templates by <c>DeployedFolderShowsTests</c>.</summary>
public static class DeployedFolderTrail
{
    public static string FromWords(DeployedFolderFrom from) => from switch
    {
        DeployedFolderFrom.Result => "from the deploy's result",
        DeployedFolderFrom.SectionMenu => "from the Section menu",
        DeployedFolderFrom.Toolbar => "from the toolbar",
        _ => "from the sidebar",
    };

    public static string ReasonWords(DeployedFolderStopReason reason) => reason switch
    {
        DeployedFolderStopReason.StopPressed => "Stop was pressed",
        DeployedFolderStopReason.PlantoirQuit => "Plantoir quit",
        DeployedFolderStopReason.FolderGone => "the folder was gone",
        _ => "it stopped on its own",
    };

    public static string CouldNotOpenWords(DeployedFolderCouldNotOpen why) => why switch
    {
        DeployedFolderCouldNotOpen.FolderNotFound => "the folder was not found",
        DeployedFolderCouldNotOpen.NothingDeployed => "nothing deployed there",
        DeployedFolderCouldNotOpen.NoFreeAddress => "no address on this computer was free",
        _ => "the browser did not open it",
    };

    public static string OpenedLine(DeployedFolderFrom from, bool alreadyOpen, bool addressMoved)
    {
        if (alreadyOpen) return $"opened the deployed folder in the web browser ({FromWords(from)}, already open)";
        if (addressMoved)
            return $"opened the deployed folder in the web browser ({FromWords(from)}, at a different address because its usual one was taken, so what the site remembered there is not shown)";
        return $"opened the deployed folder in the web browser ({FromWords(from)})";
    }

    public static string StoppedLine(DeployedFolderStopReason reason, int requests, int missing) =>
        $"stopped showing the deployed folder in the web browser — {ReasonWords(reason)} ({requests} requests, {missing} not found)";

    public static string CouldNotOpenLine(DeployedFolderCouldNotOpen why) =>
        $"could not open the deployed folder in the web browser — {CouldNotOpenWords(why)}";
}

/// <summary>
/// Every deployed folder this copy of the app is showing in the web browser
/// (#889, the mac's #850), one per section folder, app-wide: the result panel,
/// the Section menu, the toolbar and the sidebar all open through
/// <see cref="Shared"/>, so pressing Open again while one runs reopens the same
/// address and starts nothing.
/// </summary>
/// <remarks>
/// <para><b>It runs until Stop or quitting Plantoir</b> (Russell, 2026-11-13),
/// never until a window closes: the browser tab outlives the window. A deploy
/// to the same folder does not stop it: nothing is copied or built, the folder
/// is read at each request, and the next reload shows the new site. So it takes
/// no preview lease and no work lease, and quit never asks about it.</para>
///
/// <para><b>The rules of <c>stopCases</c></b>, each held by a test by name: two
/// presses before the first has started start ONE show (the second joins it);
/// Stop while it starts ends it once started and leaves nothing listening; Stop
/// on a section ends every show of that section; a listener that ends on its own
/// drops the show; a request that finds the folder gone stops it and the
/// section's window says so until dismissed.</para>
///
/// <para><b>Threads.</b> Every method may be called from any thread; the state
/// is behind one lock, and <see cref="Happened"/> and <see cref="Changed"/> are
/// raised OUTSIDE it, on whatever thread caused them (a listener's own thread
/// for a folder gone or a listener ended), so the window marshals to its
/// dispatcher.</para>
///
/// <para><b>A second copy of Plantoir</b> has its own registry. On the same
/// folder its walk finds the first copy's port held (another listener on
/// 127.0.0.1) and moves on to the next, so it shows the same folder at a
/// different address and the trail says the address moved.</para>
/// </remarks>
public sealed class DeployedFolderShows
{
    /// <summary>One folder being shown.</summary>
    /// <param name="Id">The served folder's canonical path (<see cref="DeployedFolderAddress.CanonicalPath"/>).</param>
    public sealed record Show(string Id, string CourseCode, int SectionNumber, string WorkingFolder, int Port)
    {
        /// <summary>The address the browser is handed.</summary>
        public Uri Address => DeployedFolderAddress.AddressOf(Port);
    }

    /// <summary>What <see cref="OpenAsync"/> did.</summary>
    /// <param name="Address">The address handed to the browser; null when nothing was opened.</param>
    /// <param name="Why">Why not, when <paramref name="Address"/> is null; null when a Stop pressed while it started ended it.</param>
    public sealed record OpenOutcome(Uri? Address, DeployedFolderCouldNotOpen? Why);

    private sealed class Running(Show show, DeployedFolderServer server)
    {
        public Show Show { get; } = show;
        public DeployedFolderServer Server { get; } = server;
    }

    private static readonly Lazy<DeployedFolderShows> SharedInstance = new(() => new DeployedFolderShows(SettingsDeployedFolderPorts.Instance));

    /// <summary>The app's one registry, remembering ports in the app's settings.</summary>
    public static DeployedFolderShows Shared => SharedInstance.Value;

    private readonly IDeployedFolderPorts _ports;
    private readonly ILocalFiles _files;
    private readonly object _gate = new();
    private readonly List<Running> _running = [];
    private readonly Dictionary<string, Task<Attempt>> _startsUnderWay = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, string> _startingFor = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _stopsAskedWhileStarting = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _folderWentAway = new(StringComparer.OrdinalIgnoreCase);

    /// <param name="ports">Where the remembered ports are kept.</param>
    /// <param name="files">The disk; a test's map in tests.</param>
    public DeployedFolderShows(IDeployedFolderPorts ports, ILocalFiles? files = null)
    {
        _ports = ports;
        _files = files ?? WindowsLocalFiles.Instance;
    }

    /// <summary>Something to write on the trail. Raised outside the lock, on the thread that caused it.</summary>
    public event Action<DeployedFolderHappening>? Happened;

    /// <summary>A show started or stopped, or a folder went away: redraw the notice and re-read the menus.</summary>
    public event Action? Changed;

    /// <summary>The ports a test made the walk start from instead of the block, or null. Tests only.</summary>
    internal Func<string, IReadOnlyList<int>>? CandidatesForTests { get; set; }

    // ---- Looking ---------------------------------------------------------------------

    /// <summary>Every show running now.</summary>
    public IReadOnlyList<Show> Shows
    {
        get { lock (_gate) return _running.Select(r => r.Show).ToList(); }
    }

    /// <summary>How many folders are shown, for <c>QuitConfirmation.UnderWay</c>'s <c>deployedFoldersShown</c> (quit never asks about them).</summary>
    public int Count
    {
        get { lock (_gate) return _running.Count; }
    }

    /// <summary>The show of a section, if one is running: what the notice and Stop Showing Deployed Folder read.</summary>
    public Show? ShowFor(string courseCode, int sectionNumber, string workingFolder)
    {
        lock (_gate)
            return _running.Select(r => r.Show).FirstOrDefault(s => IsSection(s, courseCode, sectionNumber, workingFolder));
    }

    /// <summary>Whether a section's folder stopped being shown because it went away (the window says <see cref="DeployedFolderWording.StoppedFolderGone"/> until dismissed).</summary>
    public bool FolderWentAway(string courseCode, int sectionNumber, string workingFolder)
    {
        lock (_gate) return _folderWentAway.Contains(Key(courseCode, sectionNumber, workingFolder));
    }

    /// <summary>Forgets that a section's folder went away: Dismiss was pressed, or it was opened again.</summary>
    public void DismissFolderWentAway(string courseCode, int sectionNumber, string workingFolder)
    {
        bool changed;
        lock (_gate) changed = _folderWentAway.Remove(Key(courseCode, sectionNumber, workingFolder));
        if (changed) Changed?.Invoke();
    }

    // ---- Opening -----------------------------------------------------------------------

    /// <summary>
    /// Opens a section's deployed folder in the browser, starting to show it when
    /// it is not already. <paramref name="sectionFolder"/> is
    /// <see cref="DeployedFolderOffer.Lookup.SectionFolder"/>; <paramref name="openInBrowser"/>
    /// hands the address to the browser (the window's <c>ExternalLinks</c>) and
    /// says whether it took it.
    /// </summary>
    public async Task<OpenOutcome> OpenAsync(string sectionFolder, string courseCode, int sectionNumber, string workingFolder,
                                             DeployedFolderFrom from, Func<Uri, bool> openInBrowser)
    {
        DismissFolderWentAway(courseCode, sectionNumber, workingFolder);
        string? canonical = DeployedFolderAddress.CanonicalPath(sectionFolder, _files);
        if (canonical is null || !_files.IsFolder(canonical))
            return CouldNot(DeployedFolderCouldNotOpen.FolderNotFound, courseCode, sectionNumber);

        Task<Attempt>? joining = null;
        Task<Attempt>? starting = null;
        Show? already;
        bool nothingDeployed = false;
        lock (_gate)
        {
            already = _running.Select(r => r.Show).FirstOrDefault(s => string.Equals(s.Id, canonical, StringComparison.OrdinalIgnoreCase));
            if (already is null && !_startsUnderWay.TryGetValue(canonical, out joining))
            {
                if (_files.FinalPath(Path.Join(canonical, "index.html")) is not { } index || _files.IsFolder(index))
                    nothingDeployed = true;
                else
                {
                    starting = Task.Run(() => StartShowing(canonical, courseCode, sectionNumber, workingFolder, from));
                    _startsUnderWay[canonical] = starting;
                    _startingFor[canonical] = Key(courseCode, sectionNumber, workingFolder);
                }
            }
        }

        if (already is not null)
        {
            Raise(new DeployedFolderHappening.Opened(courseCode, sectionNumber, from, AlreadyOpen: true, AddressMoved: false));
            return HandOver(already, courseCode, sectionNumber, openInBrowser);
        }
        if (nothingDeployed) return CouldNot(DeployedFolderCouldNotOpen.NothingDeployed, courseCode, sectionNumber);
        if (joining is not null)
        {
            // A second press while the first is still starting joins it: two
            // quick presses start ONE show (the mac's implementation review M1).
            var joined = await joining;
            if (joined.Show is null) return new OpenOutcome(null, joined.Why);
            Raise(new DeployedFolderHappening.Opened(courseCode, sectionNumber, from, AlreadyOpen: true, AddressMoved: false));
            return HandOver(joined.Show, courseCode, sectionNumber, openInBrowser);
        }

        Attempt attempt;
        try { attempt = await starting!; }
        finally
        {
            lock (_gate)
            {
                _startsUnderWay.Remove(canonical);
                _startingFor.Remove(canonical);
                _stopsAskedWhileStarting.Remove(canonical);
            }
        }
        // Null with no reason: a Stop pressed while it started ended it.
        if (attempt.Show is null) return new OpenOutcome(null, attempt.Why);
        return HandOver(attempt.Show, courseCode, sectionNumber, openInBrowser);
    }

    /// <summary>What one start came to: a show, or none and why (null: Stop was pressed while it started).</summary>
    private sealed record Attempt(Show? Show, DeployedFolderCouldNotOpen? Why);

    private Attempt StartShowing(string canonical, string courseCode, int sectionNumber, string workingFolder, DeployedFolderFrom from)
    {
        var candidates = CandidatesForTests?.Invoke(canonical)
                         ?? DeployedFolderAddress.Candidates(canonical, _ports.Remembered(canonical));
        var result = DeployedFolderServer.Start(canonical, candidates,
            onFolderGone: () => StopShow(canonical, DeployedFolderStopReason.FolderGone),
            onEnded: () => StopShow(canonical, DeployedFolderStopReason.EndedOnItsOwn),
            files: _files);
        if (result.Server is not { } server)
        {
            Raise(new DeployedFolderHappening.CouldNotOpen(courseCode, sectionNumber, DeployedFolderCouldNotOpen.NoFreeAddress));
            return new Attempt(null, DeployedFolderCouldNotOpen.NoFreeAddress);
        }
        _ports.Remember(canonical, server.Port);
        var show = new Show(canonical, courseCode, sectionNumber, workingFolder, server.Port);
        bool stopAsked;
        lock (_gate)
        {
            _running.Add(new Running(show, server));
            stopAsked = _stopsAskedWhileStarting.Remove(canonical);
        }
        Raise(new DeployedFolderHappening.Opened(courseCode, sectionNumber, from, AlreadyOpen: false, AddressMoved: result.FirstWasTaken));
        Changed?.Invoke();
        if (stopAsked)
        {
            // Stop was pressed while it started: stopped as soon as it has, and
            // nothing is left listening.
            StopShow(canonical, DeployedFolderStopReason.StopPressed);
            return new Attempt(null, null);
        }
        return new Attempt(show, null);
    }

    private OpenOutcome HandOver(Show show, string courseCode, int sectionNumber, Func<Uri, bool> openInBrowser)
    {
        bool took;
        try { took = openInBrowser(show.Address); }
        catch { took = false; }
        if (took) return new OpenOutcome(show.Address, null);
        return CouldNot(DeployedFolderCouldNotOpen.BrowserDidNotOpen, courseCode, sectionNumber);
    }

    private OpenOutcome CouldNot(DeployedFolderCouldNotOpen why, string courseCode, int sectionNumber)
    {
        Raise(new DeployedFolderHappening.CouldNotOpen(courseCode, sectionNumber, why));
        return new OpenOutcome(null, why);
    }

    // ---- Stopping ----------------------------------------------------------------------

    /// <summary>
    /// Stop on a section, from the notice's button or Section ▸ Stop Showing
    /// Deployed Folder: EVERY show of the section (one started before the
    /// course's deploy folder was changed is the section's too, the mac's
    /// implementation review L5), and a start still under way for it is stopped
    /// as soon as it has started.
    /// </summary>
    public void Stop(string courseCode, int sectionNumber, string workingFolder)
    {
        List<string> ending;
        lock (_gate)
        {
            ending = _running.Where(r => IsSection(r.Show, courseCode, sectionNumber, workingFolder)).Select(r => r.Show.Id).ToList();
            string section = Key(courseCode, sectionNumber, workingFolder);
            foreach (var (root, owner) in _startingFor)
                if (owner == section) _stopsAskedWhileStarting.Add(root);
        }
        foreach (string id in ending) StopShow(id, DeployedFolderStopReason.StopPressed);
    }

    /// <summary>
    /// Quitting: every show ends at once, synchronously, each with its trail
    /// line (Plantoir quit). The window's quit path calls this; quit never asks
    /// about a deployed folder (<c>quittingWhileWorkIsUnderWay</c>).
    /// </summary>
    public void StopEverything()
    {
        List<string> ending;
        lock (_gate)
        {
            ending = _running.Select(r => r.Show.Id).ToList();
            foreach (string root in _startingFor.Keys) _stopsAskedWhileStarting.Add(root);
        }
        foreach (string id in ending) StopShow(id, DeployedFolderStopReason.PlantoirQuit);
    }

    private void StopShow(string canonical, DeployedFolderStopReason reason)
    {
        Running? found;
        lock (_gate)
        {
            found = _running.FirstOrDefault(r => string.Equals(r.Show.Id, canonical, StringComparison.OrdinalIgnoreCase));
            if (found is null) return;
            _running.Remove(found);
            if (reason == DeployedFolderStopReason.FolderGone)
                _folderWentAway.Add(Key(found.Show.CourseCode, found.Show.SectionNumber, found.Show.WorkingFolder));
        }
        found.Server.Stop();
        Raise(new DeployedFolderHappening.Stopped(found.Show.CourseCode, found.Show.SectionNumber, reason,
                                                   found.Server.Requests, found.Server.NotFound));
        Changed?.Invoke();
    }

    // ---- Helpers ------------------------------------------------------------------------

    private void Raise(DeployedFolderHappening happening)
    {
        try { Happened?.Invoke(happening); }
        catch { }
    }

    private static bool IsSection(Show show, string courseCode, int sectionNumber, string workingFolder) =>
        string.Equals(show.CourseCode, courseCode, StringComparison.OrdinalIgnoreCase) && show.SectionNumber == sectionNumber
        && SameFolder(show.WorkingFolder, workingFolder);

    private static bool SameFolder(string a, string b) =>
        string.Equals(Path.GetFullPath(a).TrimEnd('\\'), Path.GetFullPath(b).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);

    private static string Key(string courseCode, int sectionNumber, string workingFolder) =>
        courseCode.ToUpperInvariant() + "/" + sectionNumber + "/" + Path.GetFullPath(workingFolder).TrimEnd('\\').ToUpperInvariant();
}

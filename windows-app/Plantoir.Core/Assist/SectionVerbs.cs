using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Assist;

/// <summary>
/// The Section menu's nine functions, run for ONE main window (#489, the
/// mac's <c>SectionVerbs</c>, #457 batch B): Publish Pages…, Hide Pages…,
/// Publish Class for a Date…, Rebuild Preview, Undo Last Change, Add Next
/// Class, Re-date Classes…, Make Room for Classes… — and Class Dates…, which
/// opens the class dates dialog and needs nothing here.
/// </summary>
/// <remarks>
/// <para><b>What runs is the tool's own code.</b> Each item's call is built
/// here, in code — never by a model — and handed to
/// <see cref="AssistToolRunner"/> with <see cref="AssistSurface.Menu"/>, the
/// one entry the in-app assistant's calls go through too. Behind it is a
/// <c>plantoir-mcp</c> started for this window on first use
/// (<c>McpClient.StartForTheMenu</c>), so the reference-course gate and the
/// outside-change hold are the server's request filter, met the same way by
/// every client. A teacher who declined the assistant's download can use
/// every item: nothing on this path asks whether a model exists.</para>
///
/// <para><b>One per window.</b> The server's undo list is this window's Undo
/// Last Change; opening another folder in the window makes a new one, and the
/// old folder's undo list goes with it (Russell's decision 4 on the mac).</para>
///
/// <para><b>Pages by folder and name.</b> <see cref="PageName"/> sends
/// <c>section1/All Classes/Unit 2, Day 3</c> as a JSON ARRAY: every shipped
/// course has five to nine <c>_DUPLICATE ME</c> pages, which a bare name
/// refuses as ambiguous, and a name holding a semicolon would be split in two
/// by a list read from a string.</para>
/// </remarks>
public sealed class SectionVerbs : IAsyncDisposable
{
    private readonly string _folder;
    private readonly Func<CancellationToken, Task<IToolServer?>> _startServer;
    private readonly Func<string, int, IToolServer, AssistToolRunner> _runnerFor;
    private readonly SemaphoreSlim _oneAtATime = new(1, 1);
    private IToolServer? _server;
    private int _running;

    /// <param name="folder">The working folder this window has open.</param>
    /// <param name="startServer">Starts this window's server; null when it could not be started.</param>
    /// <param name="runnerFor">
    /// A runner for one section, its seams wired to the window (the preview,
    /// whether a copy is being saved). Made per call, because the section is.
    /// </param>
    public SectionVerbs(string folder, Func<CancellationToken, Task<IToolServer?>> startServer,
                        Func<string, int, IToolServer, AssistToolRunner> runnerFor)
    {
        _folder = folder;
        _startServer = startServer;
        _runnerFor = runnerFor;
    }

    /// <summary>The working folder this window's functions act on.</summary>
    public string Folder => _folder;

    /// <summary>Where the last change made from the menu in this window was made, <c>CODE/N</c>; null for none.</summary>
    public string? LastChange { get; private set; }

    /// <summary>Whether Undo Last Change applies to this section (<c>subjectMenus</c> → <c>lastChangeIsHere</c>).</summary>
    public bool LastChangeIsIn(string courseCode, int section) =>
        LastChange is { } place && string.Equals(place, $"{courseCode}/{section}", StringComparison.OrdinalIgnoreCase);

    /// <summary>Whether one of this window's functions is running right now.</summary>
    public bool IsRunning => Volatile.Read(ref _running) > 0;

    /// <summary>Raised when <see cref="LastChange"/> or <see cref="IsRunning"/> changes, on whatever thread.</summary>
    public event Action? Changed;

    // ---- The calls, built in code ------------------------------------------------

    /// <summary>
    /// A page's name as the menu sends it: its place in the course, folders
    /// joined by "/", without ".md" — <c>section1/All Classes/Unit 2, Day 3</c>.
    /// </summary>
    public static string PageName(string courseDirectory, string pagePath)
    {
        string relative = Path.GetRelativePath(courseDirectory, pagePath).Replace('\\', '/');
        return relative.EndsWith(".md", StringComparison.OrdinalIgnoreCase) ? relative[..^3] : relative;
    }

    private static JsonObject Call(string name, JsonObject arguments) => new()
    {
        ["id"] = "menu-" + Guid.NewGuid().ToString("N"),
        ["type"] = "function",
        ["function"] = new JsonObject
        {
            ["name"] = name,
            ["arguments"] = arguments.ToJsonString(),
        },
    };

    private static JsonObject Place(string course, int section) => new() { ["course"] = course, ["section"] = section };

    private static JsonArray Pages(IEnumerable<string> pages)
    {
        var array = new JsonArray();
        foreach (string page in pages) array.Add(page);
        return array;
    }

    /// <summary><c>plan_publish_pages</c> / <c>publish_pages</c> with the ticked pages, each by folder and name.</summary>
    public static JsonObject PublishPages(string course, int section, IReadOnlyList<string> pages, bool plan)
    {
        var arguments = Place(course, section);
        arguments["pages"] = Pages(pages);
        return Call(plan ? "plan_publish_pages" : "publish_pages", arguments);
    }

    /// <summary><c>plan_unpublish_pages</c> / <c>unpublish_pages</c> with the ticked pages.</summary>
    public static JsonObject HidePages(string course, int section, IReadOnlyList<string> pages, bool plan)
    {
        var arguments = Place(course, section);
        arguments["pages"] = Pages(pages);
        return Call(plan ? "plan_unpublish_pages" : "unpublish_pages", arguments);
    }

    /// <summary><c>plan_publish_class_on</c> / <c>publish_class_on</c> for the chosen day.</summary>
    public static JsonObject PublishClassOn(string course, int section, DateOnly day, bool plan)
    {
        var arguments = Place(course, section);
        arguments["date"] = DateText.Iso(day);
        return Call(plan ? "plan_publish_class_on" : "publish_class_on", arguments);
    }

    /// <summary><c>rebuild_preview</c>: answered by the window, which stops and starts the preview.</summary>
    public static JsonObject RebuildPreview(string course, int section) => Call("rebuild_preview", Place(course, section));

    /// <summary><c>undo_last_change</c>: the last change made from the menu in this window.</summary>
    public static JsonObject UndoLastChange() => Call("undo_last_change", new JsonObject());

    /// <summary><c>add_next_class</c>: the page arrives hidden, and Undo Last Change takes it away.</summary>
    public static JsonObject AddNextClass(string course, int section) => Call("add_next_class", Place(course, section));

    /// <summary>
    /// <c>plan_re_date_classes</c> / <c>re_date_classes</c> onto the dates on
    /// file. Never a <c>website</c> key: that makes it a rollover.
    /// </summary>
    public static JsonObject ReDateClasses(string course, int section, bool plan) =>
        Call(plan ? "plan_re_date_classes" : "re_date_classes", Place(course, section));

    /// <summary><c>plan_make_room_for_classes</c> / <c>make_room_for_classes</c> in front of a class.</summary>
    public static JsonObject MakeRoomForClasses(string course, int section, int unit, int atDay, int howMany, bool plan)
    {
        var arguments = Place(course, section);
        arguments["unit"] = unit;
        arguments["atDay"] = atDay;
        arguments["howMany"] = howMany;
        return Call(plan ? "plan_make_room_for_classes" : "make_room_for_classes", arguments);
    }

    // ---- Running one ------------------------------------------------------------

    /// <summary>The sentence a call that could not reach its tools ends with.</summary>
    public const string CouldNotBeDone = "That could not be done just now. Try again in a moment.";

    /// <summary>
    /// Run one call. A plan only reads; a change holds the section
    /// (<see cref="SectionMenuActivity"/>) while it runs and leaves a "ran from
    /// a menu" line naming <paramref name="item"/> and how it ended.
    /// </summary>
    /// <param name="item">Where the item is in the menus: "Section ▸ Publish Pages…".</param>
    /// <param name="counts">What the line adds after how it ended — "3 pages ticked" — never a page's title.</param>
    /// <param name="progress">
    /// What the server says it is doing while the call runs — "Saving a copy
    /// of ICS3U first…" while the menu's copy is made — on whatever thread.
    /// The dialog shows that line only while it is TRUE (2B's implementation
    /// review, M2): Undo never saves a copy, and a refusal comes before one.
    /// </param>
    /// <param name="previewFollows">
    /// False for the hide the question at Deploy makes (#475): no preview is
    /// stopped before it or started after it (<see cref="AssistToolRunner.PreviewFollowsAChange"/>).
    /// </param>
    public async Task<AssistToolAnswer> Perform(JsonObject call, string item, string course, int section,
                                                string? counts = null, CancellationToken cancellation = default,
                                                Action<string>? progress = null, bool previewFollows = true)
    {
        string name = call["function"]?["name"]?.GetValue<string>() ?? "";
        bool writes = AssistToolRunner.IsWriteTool(name);
        await _oneAtATime.WaitAsync(cancellation);
        Interlocked.Increment(ref _running);
        Changed?.Invoke();
        IDisposable? claim = writes ? SectionMenuActivity.Begin(_folder, course, section) : null;
        try
        {
            int? before = _changesToUndo;
            AssistToolAnswer answer;
            try
            {
                // Rebuild Preview is answered by the window alone: no server
                // is started for it (half a second, measured, on a first use).
                bool needsTheServer = !name.Equals("rebuild_preview", StringComparison.OrdinalIgnoreCase);
                if (_server is null && needsTheServer)
                {
                    _server = await _startServer(cancellation);
                    // A fresh server's undo list is empty.
                    if (_server is not null) _changesToUndo = before = 0;
                }
                var server = _server ?? (needsTheServer ? null : NoServer.Instance);
                if (server is null) return AssistToolAnswer.Same(CouldNotBeDone);
                var runner = _runnerFor(course, section, progress is null ? server : new Relaying(server, progress));
                runner.PreviewFollowsAChange = previewFollows;
                (answer, _) = await runner.Run(call, cancellation);
            }
            catch (Exception error) when (error is not OperationCanceledException)
            {
                // The server went away under the call: forgotten, so the next
                // item starts a fresh one. Its undo list went with it.
                await ForgetTheServer();
                ActivityTrail.Note(ActivityTrail.Event.RanFromAMenu,
                    $"{item} — could not be done: {error.Message}", course, section);
                return AssistToolAnswer.Same(CouldNotBeDone);
            }
            if (answer.CarriesLastChange) LastChange = answer.LastChange;
            if (answer.ChangesToUndo is { } now) _changesToUndo = now;
            if (writes)
                ActivityTrail.Note(ActivityTrail.Event.RanFromAMenu,
                    TrailLine(item, Ending(name, answer, before, _changesToUndo, course, section), counts), course, section);
            return answer;
        }
        finally
        {
            claim?.Dispose();
            Interlocked.Decrement(ref _running);
            _oneAtATime.Release();
            Changed?.Invoke();
        }
    }

    private int? _changesToUndo;

    /// <summary>Hands the server's progress lines to the caller of one <see cref="Perform"/>, as well as to the runner's own.</summary>
    private sealed class Relaying(IToolServer inner, Action<string> progress) : IToolServer
    {
        public Task<AssistToolAnswer> CallTool(string name, JsonObject arguments, Action<string>? said = null,
                                               CancellationToken cancellation = default) =>
            inner.CallTool(name, arguments, note => { said?.Invoke(note); progress(note); }, cancellation);
    }

    /// <summary>Stands in for the server where the window answers on its own; a call reaching it is a fault.</summary>
    private sealed class NoServer : IToolServer
    {
        public static readonly NoServer Instance = new();
        public Task<AssistToolAnswer> CallTool(string name, JsonObject arguments, Action<string>? progress = null,
                                               CancellationToken cancellation = default) =>
            throw new InvalidOperationException($"{name} reached no server: the window answers it on its own.");
    }

    /// <summary>A "ran from a menu" line with the ending the caller knows — a plan twin that refused "changed nothing".</summary>
    public static void NoteRan(string item, string ending, string course, int section, string? counts = null) =>
        ActivityTrail.Note(ActivityTrail.Event.RanFromAMenu, TrailLine(item, ending, counts), course, section);

    /// <summary>A menu item that was cancelled at its plan: the line says so, and nothing ran.</summary>
    public static void NoteCancelled(string item, string course, int section, string? counts = null) =>
        ActivityTrail.Note(ActivityTrail.Event.RanFromAMenu, TrailLine(item, "cancelled at the plan", counts), course, section);

    /// <summary>A menu item with no tool behind it (Class Dates…, Help ▸ Publishing and Deploying…): it opened.</summary>
    public static void NoteOpened(string item, string course, int section) =>
        ActivityTrail.Note(ActivityTrail.Event.RanFromAMenu, TrailLine(item, "opened", null), course, section);

    /// <summary>"Section ▸ Publish Pages… — carried out, 3 pages ticked".</summary>
    public static string TrailLine(string item, string ending, string? counts) =>
        $"{item} — {ending}" + (string.IsNullOrWhiteSpace(counts) ? "" : ", " + counts);

    /// <summary>
    /// How a change ended, from what the server says and the undo list's
    /// depth — never from a sentence, except Rebuild Preview, whose ending
    /// compares the answer with the one sentence the window says when it
    /// rebuilds.
    /// </summary>
    /// <remarks>
    /// <para>The server says whether the call changed anything
    /// (<see cref="AssistToolAnswer.Changed"/>, the <c>plantoir.app/changed</c>
    /// key). It used to be read off the undo list's DEPTH alone, which was wrong
    /// for Make Room for Classes — it keeps no undo entry, on purpose — and for
    /// every change after the twentieth, when the list is full and its depth
    /// stops growing (2B's implementation review, M1). The depth is kept as the
    /// fallback for an answer that does not carry the key.</para>
    ///
    /// <para>Undo Last Change has three endings (#550, the mac's #531). The
    /// entry came off — the depth went DOWN — is "took the last change back":
    /// <c>UndoHistory.Undo</c> removes the entry exactly when nothing was
    /// left alone — a file an earlier press already put back no longer
    /// counts against it (#564) — so a whole undo always lowers the depth by one at any depth
    /// (the cap of twenty trims only when an entry is added). Some files went
    /// back and the entry stayed (the server noted a change, the depth did
    /// not move) is "took part of the last change back". Anything else changed
    /// nothing. It used to count an answer containing "is put back" as a
    /// whole undo, and the partial sentence contains those words too, so a
    /// partial undo read as a whole one.</para>
    /// </remarks>
    internal static string Ending(string tool, AssistToolAnswer answer, int? before, int? after, string course, int section)
    {
        if (tool.Equals("rebuild_preview", StringComparison.OrdinalIgnoreCase))
            return answer.Summary == AssistWording.PreviewIsRebuilding(course, section.ToString()) ? "rebuilt" : "not rebuilt";
        bool undo = tool.Equals("undo_last_change", StringComparison.OrdinalIgnoreCase);
        bool? changed = answer.Changed;
        if (undo)
        {
            if (before is { } was && after is { } now)
            {
                if (now < was) return "took the last change back";
                return changed == true ? "took part of the last change back" : "changed nothing";
            }
            // No depth to go by: what the server says, as a whole undo.
            return changed == true ? "took the last change back" : "changed nothing";
        }
        if (changed is null && before is { } earlier && after is { } later) changed = later > earlier;
        return changed == false ? "changed nothing" : "carried out";
    }

    private async Task ForgetTheServer()
    {
        var server = _server;
        _server = null;
        _changesToUndo = null;
        if (LastChange is not null)
        {
            LastChange = null;
            Changed?.Invoke();
        }
        if (server is IAsyncDisposable disposable)
        {
            try { await disposable.DisposeAsync(); } catch { }
        }
    }

    /// <summary>Stops this window's server; its undo list goes with it.</summary>
    public async ValueTask DisposeAsync() => await ForgetTheServer();

    /// <summary>
    /// Stops this window's server once the call running now has finished — for
    /// a window closing, or opening another folder, part way through a change
    /// (2B's implementation review, L4). Stopping it at once would kill the
    /// server mid-write three seconds later and leave the change half made;
    /// waiting here, off the interface thread, lets it finish and keeps the
    /// window's thread free of the server's <c>WaitForExit</c>.
    /// </summary>
    public async Task DisposeWhenIdleAsync()
    {
        await _oneAtATime.WaitAsync();
        try { await ForgetTheServer(); }
        finally { _oneAtATime.Release(); }
    }
}

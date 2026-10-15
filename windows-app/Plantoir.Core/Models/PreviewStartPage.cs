using System.Net.Http;

namespace Plantoir.Core.Models;

/// <summary>
/// Where a teacher's press of Preview opens the site (#514; the mac's #504):
/// the front page, as it always did, or the page last viewed in that
/// section's preview. An app-wide setting (File ▸ Settings ▸ Preview) decides
/// what a plain press does; holding Alt while pressing the button — or
/// choosing Section ▸'s second Preview item — does the opposite, and the
/// button and both items are TITLED by what will happen.
/// </summary>
/// <remarks>
/// <para>The rules, the cases and the words are in
/// <c>contracts/shared-rules.json</c> → <c>previewStartPage</c>, run by
/// <c>PreviewStartPageContractTests</c>; <c>documentation/12-windows-app.md</c>
/// → "Preview at Last Viewed on Windows (#514)" says what was measured here
/// and rejected, and <c>09-mac-app.md</c> → "Opening the preview at the page
/// last viewed (#504)" the mac's half.</para>
///
/// <para>Pure functions, so the contract's cases run without a window. The
/// stored values are the contract's <c>setting.values</c>: never rename one,
/// or a teacher's saved choice reads as the default.</para>
/// </remarks>
public static class PreviewStartPage
{
    /// <summary>The setting, as the contract names its two values.</summary>
    public enum Setting { FrontPage, LastViewed }

    /// <summary>The contract's <c>titles</c> keys.</summary>
    public enum Title { Preview, PreviewAtLastViewed, StopPreview }

    /// <summary>What asking the remembered page's address found out (<c>answers</c>).</summary>
    public enum Answer { Answered, Gone, DidNotAnswer }

    /// <summary>Where the preview opens (<c>cases[].opens</c>).</summary>
    public enum Opens { FrontPage, RememberedPage }

    // ---- The numbers (contract: attempts, secondsPerAttempt, goneStatuses) ----

    /// <summary>How many times the remembered page is asked before giving up.</summary>
    public const int Attempts = 3;

    /// <summary>How long each try may take. A request made during a rebuild WAITS for it, so silence is retried, never read as gone.</summary>
    public const int SecondsPerAttempt = 5;

    /// <summary>The pause between tries, as the mac's.</summary>
    public static readonly TimeSpan PauseBetweenTries = TimeSpan.FromSeconds(1);

    /// <summary>The statuses that mean the page is not on the site any more.</summary>
    public static readonly IReadOnlyList<int> GoneStatuses = [404, 410];

    // ---- The words (contract: wording, verbatim) ----

    public const string Preview = "Preview";
    public const string PreviewAtLastViewed = "Preview at Last Viewed";
    public const string StopPreview = "Stop Preview";
    public const string PaneTitle = "Preview";
    public const string SettingLabel = "When you press Preview, open";
    public const string FrontPageChoice = "The site's front page";
    public const string LastViewedChoice = "The page you last viewed";

    /// <summary>
    /// The mac's sentence, kept so the key set is the contract's — and NEVER
    /// shown here: its second half ("change their names while Option is
    /// held") is not true of a WinUI menu. <see cref="AltNote"/> is what
    /// Windows shows (<c>PreviewStartPageContractTests</c> keeps this one out
    /// of the app's source).
    /// </summary>
    public const string OptionNote = "Hold Option to do the other one. The Preview button and Section ▸ Preview change their names while Option is held, so they always say what will happen.";

    /// <summary>The sentence under the two choices on Windows (<c>previewStartPage.windowsWording.altNote</c>).</summary>
    public const string AltNote = "Hold Alt as you press the Preview button to do the other one. The button changes its name while Alt is held, so it always says what will happen, and the Section menu has both.";

    // ---- The setting ----

    /// <summary>The stored value read back: anything unreadable is the front page, what Preview did before the setting existed.</summary>
    public static Setting Read(string? stored) => stored switch
    {
        "lastViewed" => Setting.LastViewed,
        _ => Setting.FrontPage,
    };

    /// <summary>The value stored for a choice (<c>setting.values</c>).</summary>
    public static string Stored(Setting setting) => setting == Setting.LastViewed ? "lastViewed" : "frontPage";

    /// <summary>The XOR at the heart of it: the setting, or its opposite while the modifier is held.</summary>
    public static bool OpensAtLastViewed(Setting setting, bool modifierHeld) =>
        (setting == Setting.LastViewed) != modifierHeld;

    /// <summary>
    /// The modifier: Alt, and only Alt. Ctrl+Alt is AltGr on many keyboards —
    /// a teacher typing a character, never asking for the other start page.
    /// </summary>
    public static bool ModifierHeld(bool altDown, bool ctrlDown) => altDown && !ctrlDown;

    /// <summary>
    /// The ONE function behind the Preview button's title and both Section
    /// items' (contract: <c>titles</c>). While a preview runs it stops it,
    /// and the modifier changes nothing.
    /// </summary>
    public static Title TitleFor(Setting setting, bool modifierHeld, bool previewIsRunning)
    {
        if (previewIsRunning) return Title.StopPreview;
        return OpensAtLastViewed(setting, modifierHeld) ? Title.PreviewAtLastViewed : Title.Preview;
    }

    public static string Words(Title title) => title switch
    {
        Title.PreviewAtLastViewed => PreviewAtLastViewed,
        Title.StopPreview => StopPreview,
        _ => Preview,
    };

    /// <summary>The trail's words for a change of the setting (<c>settingChangedTrail</c>).</summary>
    public static string SettingChangedTrail(Setting choice) => choice == Setting.LastViewed
        ? "Settings ▸ Preview — Preview now opens at the page last viewed"
        : "Settings ▸ Preview — Preview now opens at the front page";

    // ---- Remembering (contract: remembering) ----

    /// <summary>
    /// What to remember of an address the pane showed: its path below the
    /// preview's root, percent-encoded as it arrived, with no query and no
    /// fragment (so <c>#plantoir-print=</c> is never replayed), or "" for the
    /// front page. Null means ignore it and keep what was remembered — one of
    /// the app's own loads under way, no address, <c>about:blank</c>, another
    /// site or another port.
    /// </summary>
    /// <remarks>The path is cut from the RAW string, not
    /// <see cref="Uri.AbsolutePath"/>, which unescapes some <c>%xx</c>
    /// (the mac uses <c>percentEncodedPath</c> for the same reason).</remarks>
    public static string? Remember(string? page, Uri root, bool appLoadUnderWay)
    {
        if (appLoadUnderWay || string.IsNullOrEmpty(page)) return null;
        if (!Uri.TryCreate(page, UriKind.Absolute, out var address)) return null;
        string scheme = address.Scheme.ToLowerInvariant();
        if (scheme != "http" && scheme != "https") return null;
        if (!string.Equals(scheme, root.Scheme, StringComparison.OrdinalIgnoreCase)) return null;
        if (!SameMachine(address.Host, root.Host)) return null;
        if (address.Port != root.Port) return null;

        int authority = page.IndexOf("://", StringComparison.Ordinal);
        if (authority < 0) return null;
        int pathStart = page.IndexOf('/', authority + 3);
        int end = page.IndexOfAny(['?', '#'], authority + 3);
        if (pathStart < 0 || (end >= 0 && end < pathStart)) return "";
        string path = end < 0 ? page[pathStart..] : page[pathStart..end];
        return path.TrimStart('/');
    }

    /// <summary><c>localhost</c> and <c>127.0.0.1</c> are the same PC: the launcher announces one and the pane may show either.</summary>
    public static bool SameMachine(string first, string second)
    {
        if (string.Equals(first, second, StringComparison.OrdinalIgnoreCase)) return true;
        static bool Local(string host) =>
            string.Equals(host, "localhost", StringComparison.OrdinalIgnoreCase) || host == "127.0.0.1";
        return Local(first) && Local(second);
    }

    /// <summary>
    /// The remembered page's address on THIS run's server — a path is kept,
    /// never an address, because the port changes between runs. Null when
    /// the result would leave the root's scheme, host or port (a stored
    /// <c>//elsewhere</c>), which the press reads as gone.
    /// </summary>
    public static Uri? PageAddress(Uri root, string path)
    {
        if (path.Contains("://", StringComparison.Ordinal)) return null;
        try
        {
            var built = new UriBuilder(root) { Path = "/" + path, Query = "", Fragment = "" }.Uri;
            if (!string.Equals(built.Scheme, root.Scheme, StringComparison.OrdinalIgnoreCase)
                || !string.Equals(built.Host, root.Host, StringComparison.OrdinalIgnoreCase)
                || built.Port != root.Port) return null;
            return built;
        }
        catch (UriFormatException) { return null; }
    }

    // ---- Asking (contract: answers) ----

    /// <summary>What one status means, or null for "ask again".</summary>
    public static Answer? AnswerFor(int? status)
    {
        if (status is null) return null;
        if (status == 200) return Answer.Answered;
        if (GoneStatuses.Contains(status.Value)) return Answer.Gone;
        return null;
    }

    /// <summary>
    /// The answer a run of statuses comes to: the first 200 or 404/410 ends
    /// it; <see cref="Attempts"/> with neither is <see cref="Answer.DidNotAnswer"/>;
    /// fewer is null — ask again.
    /// </summary>
    public static Answer? AfterTries(IReadOnlyList<int?> statuses)
    {
        for (int i = 0; i < statuses.Count && i < Attempts; i++)
            if (AnswerFor(statuses[i]) is { } answer) return answer;
        return statuses.Count >= Attempts ? Answer.DidNotAnswer : null;
    }

    /// <summary>
    /// Asks up to <see cref="Attempts"/> times, a second apart, stopping at
    /// the first answer that says something. Both the asking and the waiting
    /// are injected, so the rule is tested without a server or a clock.
    /// </summary>
    public static async Task<Answer> AskAsync(Func<CancellationToken, Task<int?>> askOnce,
                                              Func<TimeSpan, CancellationToken, Task> wait,
                                              CancellationToken cancel)
    {
        var statuses = new List<int?>();
        while (true)
        {
            cancel.ThrowIfCancellationRequested();
            statuses.Add(await askOnce(cancel).ConfigureAwait(false));
            if (AfterTries(statuses) is { } answer) return answer;
            await wait(PauseBetweenTries, cancel).ConfigureAwait(false);
        }
    }

    /// <summary>
    /// One try: the page's status, redirects followed, or null for a timeout
    /// or an error. <paramref name="perTry"/> defaults to
    /// <see cref="SecondsPerAttempt"/>. Throws only when
    /// <paramref name="cancel"/> was cancelled — the preview stopped.
    /// </summary>
    public static async Task<int?> StatusOfAsync(HttpClient client, Uri page, CancellationToken cancel, TimeSpan? perTry = null)
    {
        using var thisTry = CancellationTokenSource.CreateLinkedTokenSource(cancel);
        thisTry.CancelAfter(perTry ?? TimeSpan.FromSeconds(SecondsPerAttempt));
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, page);
            using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, thisTry.Token)
                                             .ConfigureAwait(false);
            return (int)response.StatusCode;
        }
        catch (OperationCanceledException) when (cancel.IsCancellationRequested) { throw; }
        catch { return null; }
    }

    // ---- Deciding (contract: cases) ----

    /// <summary>
    /// The path to ask about, or null when nothing has to be asked: the
    /// press did not ask for the page last viewed, Show on Front Page just
    /// wrote the front page (#397), or nothing — or the front page — was
    /// remembered.
    /// </summary>
    public static string? PathToAsk(bool atLastViewed, bool frontPageWasJustChanged, string? remembered) =>
        atLastViewed && !frontPageWasJustChanged && !string.IsNullOrEmpty(remembered) ? remembered : null;

    /// <summary>
    /// Where the preview opens and the trail's words, from what the press
    /// asked for, what was remembered and what the server answered (null
    /// when it was not asked). The press calls THIS; the contract's cases
    /// reach it through <see cref="DecideForCase"/>.
    /// </summary>
    public static (Opens Opens, string? Trail) Decide(bool atLastViewed, string? remembered, Answer? answer,
                                                       bool frontPageWasJustChanged)
    {
        if (!atLastViewed) return (Opens.FrontPage, null);
        if (frontPageWasJustChanged)
            return (Opens.FrontPage, "started preview at the front page because today's class was just put on it");
        if (remembered is null)
            return (Opens.FrontPage, "started preview at the front page because no page had been viewed yet");
        if (remembered.Length == 0)
            return (Opens.FrontPage, "started preview at the front page, the page last viewed");
        string place = Slug(remembered);
        return answer switch
        {
            Answer.Answered => (Opens.RememberedPage, "started preview at " + place),
            Answer.Gone => (Opens.FrontPage, "started preview at the front page because the page was gone (" + place + ")"),
            _ => (Opens.FrontPage, "started preview at the front page because the page did not answer (" + place + ")"),
        };
    }

    /// <summary>The contract's shape — (setting, modifierHeld, …) — over the press's own <see cref="Decide"/>.</summary>
    public static (Opens Opens, string? Trail) DecideForCase(Setting setting, bool modifierHeld, string? remembered,
                                                              Answer? answer, bool frontPageWasJustChanged) =>
        Decide(OpensAtLastViewed(setting, modifierHeld), remembered, answer, frontPageWasJustChanged);

    /// <summary>A remembered path as the trail writes it: decoded — the page's PLACE, never its words.</summary>
    public static string Slug(string path)
    {
        try { return Uri.UnescapeDataString(path); } catch { return path; }
    }
}

/// <summary>
/// Tells the teacher's navigations in the preview pane from the app's own
/// loads, so only the first are remembered (the mac's 504 plan review, the
/// BLOCKER): the first page of a fresh build, Reload, Rebuild Preview, the
/// assistant's restart all land on a page the teacher did not choose.
/// </summary>
/// <remarks>
/// <para>An app load is marked when the app REQUESTS it; the first
/// <c>NavigationStarting</c> after that names its NavigationId, and that
/// id's <c>ContentLoading</c> — WebView2's counterpart of the mac's
/// didCommit — ends it, with its <c>NavigationCompleted</c> as the backstop
/// for a failure. Matched on the CAPTURED id, never "the next one":
/// measured, a pushState or fragment click consumes NavigationIds without
/// a NavigationStarting. An app load whose id was never captured ends by
/// itself after <see cref="Backstop"/>.</para>
/// <para>A FLAG, not "the address equals the one asked for": that would
/// also ignore a teacher's own click on the site's Home link, and a
/// redirect (<c>/Concepts</c> → <c>/Concepts/</c>) never matches.</para>
/// </remarks>
public sealed class PreviewNavigationLedger
{
    /// <summary>How long an app load whose navigation never started counts as under way.</summary>
    public static readonly TimeSpan Backstop = TimeSpan.FromSeconds(15);

    private DateTime? _requestedAt;
    private ulong? _id;

    /// <summary>The app asked for a load. A second request replaces the first: its id is forgotten, so the first load's late end cannot end this one.</summary>
    public void AppLoadRequested(DateTime now)
    {
        _requestedAt = now;
        _id = null;
    }

    /// <summary>A navigation started; the first one after an app's request is that load.</summary>
    public void NavigationStarting(ulong id, bool isRedirected)
    {
        if (_requestedAt is null) return;
        if (_id is null && !isRedirected) _id = id;
    }

    /// <summary>The content of a navigation began to arrive: the app's load, if it is its id, is over.</summary>
    public void ContentLoading(ulong id) => EndIfItIs(id);

    /// <summary>A navigation finished or failed: the backstop for a load that never committed.</summary>
    public void NavigationCompleted(ulong id) => EndIfItIs(id);

    /// <summary>Whether an address change now would be the app's, not the teacher's.</summary>
    public bool AppLoadUnderWay(DateTime now)
    {
        if (_requestedAt is not { } requested) return false;
        if (_id is null && now - requested > Backstop)
        {
            _requestedAt = null;
            return false;
        }
        return true;
    }

    private void EndIfItIs(ulong id)
    {
        if (_requestedAt is not null && _id == id)
        {
            _requestedAt = null;
            _id = null;
        }
    }
}

using Plantoir.Core.Scripting;

namespace Plantoir.Core.Models;

/// <summary>Obsidian's add-ons question, or the reopen question, waiting to be shown before Obsidian opens.</summary>
/// <remarks><paramref name="Page"/> is the file a section's press opens for the page its preview shows (#681), carried through both questions so it is the page that opens once they are answered; null opens <paramref name="Folder"/> as before. <paramref name="OpenState"/> is what the offer's words say (#815); <see cref="CourseIsOpen"/> is what the route does, cannot tell counting as open.</remarks>
public sealed record ObsidianAddOnsRequest(Course Course, string Folder, IReadOnlyList<ObsidianFigureAddOn> Needed, ObsidianFigureAddOnsOffer.CourseOpenState OpenState, string? Page = null)
{
    /// <summary>Open or cannot tell: nothing is written into the course, and Add Them goes the reopen way.</summary>
    public bool CourseIsOpen => OpenState != ObsidianFigureAddOnsOffer.CourseOpenState.Closed;

    /// <summary>The offer's yes: "Close Obsidian and Add Them" whenever that yes closes Obsidian, "Add Them" otherwise (#1003, the mac's #995).</summary>
    public string AddButtonTitle => CourseIsOpen ? ObsidianClosingWording.OfferAddClosingObsidian : ObsidianFigureAddOnsWording.OfferAdd;
}

/// <summary>
/// What a press of Open in Obsidian came to, said as soon as it is known
/// (#690; the mac's <c>OpenInObsidianPress</c>) - before the route has
/// finished, because on Windows a question is an awaited dialog rather than
/// state the window shows.
/// </summary>
public abstract record OpenInObsidianPress
{
    /// <summary>Obsidian was handed something: the page in <paramref name="Answer"/>, or the section as before (null for a course press).</summary>
    public sealed record Opened(PreviewedPageSource.Answer? Answer) : OpenInObsidianPress;

    /// <summary>A question (the offer, the reopen question, a reference course's note, or another dialog) is up first; Obsidian opens once it is answered.</summary>
    public sealed record WaitingForAnAnswer : OpenInObsidianPress;

    /// <summary>Turned away: the same course is still being opened (its add-ons scan is running).</summary>
    public sealed record AlreadyOpening : OpenInObsidianPress;

    /// <summary>There was no window of that working folder to press it in.</summary>
    public sealed record NoWindow : OpenInObsidianPress;

    /// <summary>
    /// The press failed before Obsidian was handed anything - the add-ons scan,
    /// the pass or the open itself threw - so nothing was opened. Windows'
    /// own: the mac's press has no such outcome and the contract no sentence
    /// for it (<c>12-windows-app.md</c> → "The assistant's Open in Obsidian
    /// on Windows (#690, the mac's #610)" says which sentence is said, and why).
    /// </summary>
    public sealed record DidNotOpen : OpenInObsidianPress;
}

/// <summary>
/// Everything Open in Obsidian asks of the world outside the app — Obsidian
/// itself, its registry, the disk, the teacher — in one replaceable place, so
/// a test drives the whole route without a window or an Obsidian (#581; the
/// mac's <c>ObsidianOpening</c>). The app's own is <c>ObsidianWorld</c>.
/// </summary>
public interface IObsidianWorld
{
    /// <summary>Whether anything answers <c>obsidian://</c>.</summary>
    bool IsInstalled();

    /// <summary>Whether Obsidian is running in this session at all — hidden or minimised included.</summary>
    bool IsRunning();

    /// <summary>Obsidian's registry (<c>%APPDATA%\obsidian\obsidian.json</c>) as it is on disk now, or null.</summary>
    string? RegistryText();

    /// <summary>What Open in Obsidian hands Obsidian for a folder: the section's index page, or the course.</summary>
    string TargetFor(string folder, string vault);

    /// <summary>
    /// Opens a folder in Obsidian - or <paramref name="page"/>, a file, when one
    /// is named (the page door, #681) - registering the course first when
    /// Obsidian has never seen it and is NOT running. Never closes Obsidian
    /// (#1003): false means nothing was handed over, because Obsidian is
    /// running and does not know the course, so the route asks first.
    /// </summary>
    Task<bool> OpenAsync(string folder, string vault, string? page = null);

    /// <summary>Asks Obsidian to quit and waits for it to be gone, or for the wait to run out. Called only on an answer that said Obsidian closes.</summary>
    Task QuitAndWaitAsync();

    /// <summary>
    /// The answer Close Obsidian and Open (#1003): closes Obsidian, adds the
    /// course to its list and opens again what its list marked open
    /// (<see cref="ObsidianClosingRule.CloseAndRegisterAsync"/>). False:
    /// Obsidian did not close, and nothing was written or handed over.
    /// </summary>
    Task<bool> CloseAndRegisterAsync(string vault);

    /// <summary>Shows "Close Obsidian to open {course}?": true is Close Obsidian and Open, false is Cancel (Escape too).</summary>
    Task<bool> AskClosingAsync(ObsidianClosingRequest request);

    /// <summary>Shows "Could not open {course} in Obsidian", one sentence and OK, for an answer that could not finish (Russell's ruling 2 on #995).</summary>
    Task ShowCouldNotOpenAsync(ObsidianClosingRequest request, ObsidianClosingTrail.Outcome outcome);

    /// <summary>Opens these vaults again, in order, so the last is in front.</summary>
    Task ReopenAsync(IReadOnlyList<string> vaultPaths);

    /// <summary>Which add-ons a course needs and which a pass would add — off the UI thread.</summary>
    Task<(List<ObsidianFigureAddOn> Needed, List<ObsidianFigureAddOn> WouldAdd)> ScanAsync(string coursePath);

    /// <summary>Where the app carries the add-ons, and the course defaults.</summary>
    string? CarriedFolder { get; }
    string? DefaultsFolder { get; }

    /// <summary>The app-wide answer, read and stored.</summary>
    ObsidianFigureAddOnsAnswer Answer { get; set; }

    /// <summary>Shows the offer; closing it any other way is Not Now.</summary>
    Task<ObsidianFigureAddOnsTrail.Answered> AskOfferAsync(ObsidianAddOnsRequest request);

    /// <summary>Shows the reopen question: true is Reopen, false is Later.</summary>
    Task<bool> AskReopenAsync(ObsidianAddOnsRequest request);
}

/// <summary>
/// Open in Obsidian with Obsidian's add-ons for diagrams and graphs (#581;
/// the mac's <c>OpenInObsidianRoute.swift</c>), and the second trigger, a
/// finished preview — <c>obsidianAddOnsForFigures.sequence</c>, steps 2–8
/// (step 1, a course kept for reference, stays the caller's: its pages are
/// locked again and its note shown, and it is never scanned).
/// </summary>
/// <remarks>
/// Everything is decided BEFORE Obsidian opens, so in the common case Obsidian
/// reads the add-ons on its first load and nothing is reopened. Nothing is
/// ever written into a course open in Obsidian: Obsidian keeps the list in
/// memory and writes it back whole, so an id added under it is dropped.
/// </remarks>
public sealed class ObsidianOpenRoute
{
    private readonly IObsidianWorld _world;

    public ObsidianOpenRoute(IObsidianWorld world) => _world = world;

    /// <summary>
    /// Open in Obsidian for a course press. Returns false when nothing was
    /// done because the same course is already being opened (a second click
    /// while it scans). Awaits the whole route, questions included.
    /// </summary>
    public Task<bool> OpenAsync(Course course, string folder) => Press(course, folder, null, null).Finished;

    /// <summary>
    /// A press of Open in Obsidian (#681, #690). <paramref name="answer"/> is
    /// what a SECTION's press resolved for the page its preview shows - the
    /// page opens through the page door, a fallback opens
    /// <paramref name="folder"/> as before - and null for a course press.
    /// <c>Reported</c> completes as soon as the press's outcome is known
    /// (Obsidian handed something, a question about to be shown, or turned
    /// away), and ALWAYS completes; <c>Finished</c> is the route itself.
    /// A section press that goes ahead writes one trail line, after the
    /// guard against a second press and the scan, before any question; a
    /// course press writes none.
    /// </summary>
    public (Task<OpenInObsidianPress> Reported, Task<bool> Finished) Press(
        Course course, string folder, PreviewedPageSource.Answer? answer, int? section)
    {
        var report = new TaskCompletionSource<OpenInObsidianPress>(TaskCreationOptions.RunContinuationsAsynchronously);
        var finished = RunAsync(course, folder, answer, section, report);
        return (report.Task, finished);
    }

    private async Task<bool> RunAsync(Course course, string folder, PreviewedPageSource.Answer? answer, int? section,
                                      TaskCompletionSource<OpenInObsidianPress> report)
    {
        try
        {
            string coursePath = course.DirectoryPath;
            string? page = (answer as PreviewedPageSource.Page)?.File;
            var press = new Pressing(answer, report);
            bool reference = ReferenceCourse.IsKeptForReference(course);
            if (!ObsidianFigureAddOnsOffer.Scans(reference, _world.IsInstalled(), _world.Answer, ObsidianFigureAddOnsThisRun.Suppressed))
            {
                NoteThePress(answer, course, section);
                await OpenThenReportAsync(press, course, folder, page);
                return true;
            }
            if (!ObsidianFigureAddOnsThisRun.BeingOpened.Add(coursePath))
            {
                // Turned away: no trail line. While the first press's question
                // is up, the honest answer is that it waits for that answer.
                report.TrySetResult(ObsidianFigureAddOnsThisRun.Asking.Contains(coursePath)
                    ? new OpenInObsidianPress.WaitingForAnAnswer()
                    : new OpenInObsidianPress.AlreadyOpening());
                return false;
            }
            try
            {
                var (needed, wouldAdd) = await _world.ScanAsync(coursePath);
                // After the scan, so a scan that fails leaves no line saying
                // it opened; before any question, so a press that goes ahead
                // still writes exactly one.
                NoteThePress(answer, course, section);
                await OpenAfterTheScanAsync(press, course, folder, page, needed, wouldAdd);
            }
            finally { ObsidianFigureAddOnsThisRun.BeingOpened.Remove(coursePath); }
            return true;
        }
        catch
        {
            // A RESULT, never an exception: the assistant's reply is made from
            // it, and "nothing was opened" is the one thing known to be true.
            // A report already made (a question was up) stands.
            report.TrySetResult(new OpenInObsidianPress.DidNotOpen());
            throw;
        }
        finally
        {
            report.TrySetResult(new OpenInObsidianPress.Opened(answer));
        }
    }

    /// <summary>One press's answer and its report, carried through the route.</summary>
    private sealed record Pressing(PreviewedPageSource.Answer? Answer, TaskCompletionSource<OpenInObsidianPress> Report);

    private static void NoteThePress(PreviewedPageSource.Answer? answer, Course course, int? section)
    {
        if (answer is not null && section is int number) PreviewedPageSource.NoteThePress(answer, course.Code, number);
    }

    /// <summary>
    /// Opens without the add-ons scan, through the closing question: Course
    /// Settings' How I Teach row (the mac's <c>openHowITeachPageInObsidian</c>)
    /// and a course kept for reference once its note is answered (step 1 stays
    /// the caller's). <paramref name="report"/>, when handed, says what the
    /// press came to as soon as it is known, as <see cref="Press"/>'s does.
    /// </summary>
    public Task OpenWithoutTheScanAsync(Course course, string folder, string? page,
                                        PreviewedPageSource.Answer? answer = null,
                                        TaskCompletionSource<OpenInObsidianPress>? report = null)
    {
        var press = new Pressing(answer, report ?? new TaskCompletionSource<OpenInObsidianPress>(TaskCreationOptions.RunContinuationsAsynchronously));
        return OpenThenReportAsync(press, course, folder, page);
    }

    /// <summary>
    /// Every open in the route comes here (#1003, the mac's #995): when
    /// handing Obsidian the file means closing a running Obsidian first - a
    /// course it has never seen - nothing is opened or closed, and the closing
    /// question is asked instead. Obsidian starting between this check and
    /// the open is caught too: the open hands nothing over and answers false,
    /// and the question is asked rather than the press doing nothing.
    /// </summary>
    private async Task OpenThenReportAsync(Pressing press, Course course, string folder, string? page)
    {
        if (!MustCloseObsidian(course, folder, page) && await _world.OpenAsync(folder, course.DirectoryPath, page))
        {
            press.Report.TrySetResult(new OpenInObsidianPress.Opened(press.Answer));
            return;
        }
        await AskClosingAsync(press, new ObsidianClosingRequest(course, folder, page));
    }

    /// <summary><see cref="ObsidianClosingRule.MustAsk"/> for the file this open hands Obsidian, read now.</summary>
    private bool MustCloseObsidian(Course course, string folder, string? page) =>
        ObsidianClosingRule.MustAsk(page ?? _world.TargetFor(folder, course.DirectoryPath), _world.IsRunning(), _world.RegistryText());

    /// <summary>
    /// "Close Obsidian to open {course}?" and its answer (the mac's
    /// <c>answerObsidianClosing</c>). Cancel opens nothing and closes nothing.
    /// Close Obsidian and Open looks again first: if Obsidian has quit
    /// meanwhile, or now knows the course, it simply opens and nothing is
    /// closed. If Obsidian does not close, nothing is written or handed to it;
    /// if it closed but the course still cannot be handed over (its list
    /// could not be written), nothing more is tried. Each answer leaves one
    /// trail line, and each of the two failures its alert.
    /// </summary>
    private async Task AskClosingAsync(Pressing press, ObsidianClosingRequest request)
    {
        string coursePath = request.Course.DirectoryPath;
        string code = request.Course.Code;
        Asking(press, coursePath);
        bool close;
        try { close = await _world.AskClosingAsync(request); }
        finally { ObsidianFigureAddOnsThisRun.Asking.Remove(coursePath); }
        if (!close)
        {
            ObsidianClosingTrail.Note(ObsidianClosingTrail.Outcome.Cancelled, code);
            return;
        }
        if (!MustCloseObsidian(request.Course, request.Folder, request.Page))
        {
            ObsidianClosingTrail.Note(ObsidianClosingTrail.Outcome.NotNeeded, code);
            await OpenThenReportAsync(press, request.Course, request.Folder, request.Page);
            return;
        }
        if (!await _world.CloseAndRegisterAsync(coursePath))
        {
            await CouldNotOpenAsync(request, ObsidianClosingTrail.Outcome.DidNotClose);
            return;
        }
        if (!await _world.OpenAsync(request.Folder, coursePath, request.Page))
        {
            await CouldNotOpenAsync(request, ObsidianClosingTrail.Outcome.NotAdded);
            return;
        }
        ObsidianClosingTrail.Note(ObsidianClosingTrail.Outcome.Opened, code);
    }

    /// <summary>The trail line first, so it is written even if the alert cannot be shown; then the alert.</summary>
    private async Task CouldNotOpenAsync(ObsidianClosingRequest request, ObsidianClosingTrail.Outcome outcome)
    {
        ObsidianClosingTrail.Note(outcome, request.Course.Code);
        await _world.ShowCouldNotOpenAsync(request, outcome);
    }

    /// <summary>A question is about to be shown: the press is waiting for its answer.</summary>
    private static void Asking(Pressing press, string coursePath)
    {
        ObsidianFigureAddOnsThisRun.Asking.Add(coursePath);
        press.Report.TrySetResult(new OpenInObsidianPress.WaitingForAnAnswer());
    }

    /// <summary>
    /// A section's preview has just shown a fresh build: with the answer yes,
    /// add what the course needs, silently — unless the course is open in
    /// Obsidian, checked after the scan, right before writing.
    /// </summary>
    public async Task AfterAPreviewAsync(Course course)
    {
        if (ReferenceCourse.IsKeptForReference(course)) return;
        if (_world.Answer != ObsidianFigureAddOnsAnswer.Yes || !_world.IsInstalled()) return;
        string coursePath = course.DirectoryPath;
        var (needed, wouldAdd) = await _world.ScanAsync(coursePath);
        var decision = ObsidianFigureAddOnsOffer.AfterAPreview(
            reference: false, obsidianInstalled: true, _world.Answer, wouldAdd.Count > 0,
            ObsidianFigureAddOnsOffer.VaultIsTheCourse(coursePath, coursePath, _world.RegistryText()),
            CourseIsOpenInObsidian(coursePath));
        if (decision == ObsidianFigureAddOnsOffer.PreviewDecision.Install)
            await AddAsync(course, needed, ObsidianFigureAddOnsTrail.Trigger.AfterAPreview);
    }

    private async Task OpenAfterTheScanAsync(Pressing press, Course course, string folder, string? page, List<ObsidianFigureAddOn> needed, List<ObsidianFigureAddOn> wouldAdd)
    {
        string coursePath = course.DirectoryPath;
        var openState = CourseOpenStateInObsidian(coursePath);
        var situation = new ObsidianFigureAddOnsOffer.Situation(
            Reference: ReferenceCourse.IsKeptForReference(course),
            ObsidianInstalled: true,
            Answer: _world.Answer,
            SuppressedThisRun: ObsidianFigureAddOnsThisRun.Suppressed,
            WouldAdd: wouldAdd.Count > 0,
            VaultIsTheCourse: ObsidianFigureAddOnsOffer.VaultIsTheCourse(page ?? _world.TargetFor(folder, coursePath), coursePath, _world.RegistryText()),
            CourseOpenInObsidian: openState != ObsidianFigureAddOnsOffer.CourseOpenState.Closed,
            ReopenDeclinedThisRun: ObsidianFigureAddOnsThisRun.ReopenDeclined.Contains(coursePath));
        switch (ObsidianFigureAddOnsOffer.Decide(situation))
        {
            case ObsidianFigureAddOnsOffer.Decision.NotTheVault:
                ObsidianFigureAddOnsThisRun.NoteNotTheVault(course.Code);
                await OpenThenReportAsync(press, course, folder, page);
                break;
            case ObsidianFigureAddOnsOffer.Decision.Offer:
            case ObsidianFigureAddOnsOffer.Decision.OfferWhileOpen:
                await OfferAsync(press, new ObsidianAddOnsRequest(course, folder, needed, openState, page));
                break;
            case ObsidianFigureAddOnsOffer.Decision.InstallThenOpen:
                await AddAsync(course, needed, ObsidianFigureAddOnsTrail.Trigger.OpenInObsidian);
                await OpenThenReportAsync(press, course, folder, page);
                break;
            case ObsidianFigureAddOnsOffer.Decision.AskReopen:
                await AskReopenAsync(press, new ObsidianAddOnsRequest(course, folder, needed, openState, page));
                break;
            default:
                await OpenThenReportAsync(press, course, folder, page);
                break;
        }
    }

    /// <summary>The offer, and its answer. Obsidian opens after every answer.</summary>
    private async Task OfferAsync(Pressing press, ObsidianAddOnsRequest request)
    {
        Asking(press, request.Course.DirectoryPath);
        ObsidianFigureAddOnsTrail.Answered answered;
        try { answered = await _world.AskOfferAsync(request); }
        finally { ObsidianFigureAddOnsThisRun.Asking.Remove(request.Course.DirectoryPath); }
        ActivityTrail.Note(ActivityTrail.Event.ObsidianAddOnsOffered, ObsidianFigureAddOnsTrail.Offered(request.Course.Code, answered));
        switch (answered)
        {
            case ObsidianFigureAddOnsTrail.Answered.AddThem:
                _world.Answer = ObsidianFigureAddOnsAnswer.Yes;
                // The offer was shown with "Close Obsidian and Add Them": that answer closes Obsidian.
                if (request.CourseIsOpen)
                {
                    await ReopenWithAddOnsAsync(press, request);
                    return;
                }
                // Asked again NOW: the course may have been opened in Obsidian
                // while the question was up. The button pressed said "Add Them",
                // not that Obsidian would close, so the reopen question asks
                // first (#1003, the mac's #995; sequence step 6).
                if (CourseIsOpenInObsidian(request.Course.DirectoryPath))
                {
                    await AskReopenAsync(press, request);
                    return;
                }
                await AddAsync(request.Course, request.Needed, ObsidianFigureAddOnsTrail.Trigger.OpenInObsidian);
                break;
            case ObsidianFigureAddOnsTrail.Answered.NotNow:
                ObsidianFigureAddOnsThisRun.Suppressed = true;
                break;
            default:
                _world.Answer = ObsidianFigureAddOnsAnswer.No;
                break;
        }
        await OpenThenReportAsync(press, request.Course, request.Folder, request.Page);
    }

    private async Task AskReopenAsync(Pressing press, ObsidianAddOnsRequest request)
    {
        Asking(press, request.Course.DirectoryPath);
        bool reopen;
        try { reopen = await _world.AskReopenAsync(request); }
        finally { ObsidianFigureAddOnsThisRun.Asking.Remove(request.Course.DirectoryPath); }
        if (reopen)
        {
            await ReopenWithAddOnsAsync(press, request);
            return;
        }
        ObsidianFigureAddOnsThisRun.ReopenDeclined.Add(request.Course.DirectoryPath);
        ActivityTrail.Note(ActivityTrail.Event.ObsidianReopenedForAddOns, ObsidianFigureAddOnsTrail.ReopenDeclined(request.Course.Code));
        await OpenThenReportAsync(press, request.Course, request.Folder, request.Page);
    }

    /// <summary>
    /// Notes the vaults open now, quits Obsidian, adds the add-ons only once
    /// Obsidian is no longer RUNNING, and opens every vault that was open
    /// again, this course last. If Obsidian does not close, nothing is written.
    /// </summary>
    private async Task ReopenWithAddOnsAsync(Pressing press, ObsidianAddOnsRequest request)
    {
        var wereOpen = ObsidianFigureAddOnsOffer.VaultsOpen(_world.IsRunning(), _world.RegistryText());
        await _world.QuitAndWaitAsync();
        if (_world.IsRunning())
        {
            ActivityTrail.Note(ActivityTrail.Event.ObsidianReopenedForAddOns, ObsidianFigureAddOnsTrail.DidNotClose(request.Course.Code));
            await OpenThenReportAsync(press, request.Course, request.Folder, request.Page);
            return;
        }
        await AddAsync(request.Course, request.Needed, ObsidianFigureAddOnsTrail.Trigger.AfterReopening);
        ActivityTrail.Note(ActivityTrail.Event.ObsidianReopenedForAddOns, ObsidianFigureAddOnsTrail.Reopened(request.Course.Code));
        var others = wereOpen.Where(path => !ObsidianFigureAddOnsOffer.SamePath(path, request.Course.DirectoryPath)).ToList();
        await _world.ReopenAsync(others);
        await OpenThenReportAsync(press, request.Course, request.Folder, request.Page);
    }

    private bool CourseIsOpenInObsidian(string coursePath) =>
        ObsidianFigureAddOnsOffer.CourseIsOpen(coursePath, _world.IsRunning(), _world.RegistryText());

    private ObsidianFigureAddOnsOffer.CourseOpenState CourseOpenStateInObsidian(string coursePath) =>
        ObsidianFigureAddOnsOffer.OpenState(coursePath, _world.IsRunning(), _world.RegistryText());

    /// <summary>One pass, through the queue, and its trail line.</summary>
    private async Task AddAsync(Course course, IReadOnlyList<ObsidianFigureAddOn> needed, ObsidianFigureAddOnsTrail.Trigger trigger)
    {
        if (ReferenceCourse.IsKeptForReference(course) || needed.Count == 0) return;
        var results = await ObsidianFigureAddOnsQueue.InstallAsync(needed, course.DirectoryPath, _world.CarriedFolder, _world.DefaultsFolder);
        ObsidianFigureAddOnsThisRun.NotePass(course.Code, trigger, results);
    }
}

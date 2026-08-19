using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text;

namespace Plantoir.Core.Scripting;

/// <summary>
/// Runs one launcher script under a pseudo console and turns its output into
/// interface state: transcript, milestone progress, questions, outcomes.
///
/// Everything the interface learns arrives through <see cref="ReceiveOutput"/>
/// — tests feed simulated output through the same door. Progress is tracked
/// incrementally as output arrives, never by re-scanning the transcript on a
/// timer (the lesson of the blank-window saga).
/// </summary>
public sealed class ScriptRunner : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    private readonly SynchronizationContext? _ui;
    private ConPtyProcess? _process;
    private Thread? _readerThread;
    private Thread? _exitThread;
    private int _finished;                 // 0 until FinishRun runs, guards against a double finish
    private CancellationTokenSource? _promptCheck;
    private readonly StringBuilder _pendingOutput = new();
    private readonly object _outputGate = new();
    private bool _flushScheduled;
    private string _unscannedOutput = "";
    private int _reachedMilestoneCount;

    public TranscriptBuilder Transcript { get; private set; } = new();

    public bool IsRunning { get; private set; }
    public int? LastExitCode { get; private set; }
    public string? LaunchProblem { get; private set; }
    public DateTime LastOutputAt { get; private set; }
    public DateTime? StartedAt { get; private set; }
    public bool IsAwaitingInput { get; private set; }
    public string PendingQuestion { get; private set; } = "";
    public string SuggestedAnswer { get; private set; } = "";
    public string PendingCancelToken { get; private set; } = "";
    public bool WasCancelled { get; private set; }
    public bool WasStoppedByUser { get; private set; }
    public string StepDetail { get; private set; } = "";
    public string? CustomDomainForLinks { get; set; }

    private IReadOnlyList<TaskMilestone> _milestones = Array.Empty<TaskMilestone>();
    public IReadOnlyList<TaskMilestone> Milestones
    {
        get => _milestones;
        set
        {
            _milestones = value;
            _reachedMilestoneCount = 0;
            _unscannedOutput = "";
            Notify(nameof(MilestonesReached));
            Notify(nameof(ProgressFraction));
            Notify(nameof(CurrentMilestoneLabel));
            Notify(nameof(StepDescription));
        }
    }

    private string _launchedScriptName = "";

    public ScriptRunner(SynchronizationContext? uiContext = null)
    {
        _ui = uiContext ?? SynchronizationContext.Current;
    }

    // ---- Launch ---------------------------------------------------------

    /// <summary>
    /// Runs &lt;workingDirectory&gt;\&lt;scriptName&gt; via Windows PowerShell under a
    /// pseudo console (docker exec -it needs a real TTY). keepTranscript
    /// continues an earlier run's output so build-then-publish reads as one job.
    /// </summary>
    public void Run(string scriptName, IReadOnlyList<string> arguments, string workingDirectory,
                    bool keepTranscript = false)
    {
        if (IsRunning) return;
        if (!keepTranscript) { Transcript = new TranscriptBuilder(); Notify(nameof(Transcript)); }
        LastExitCode = null;
        LaunchProblem = null;
        WasCancelled = false;
        WasStoppedByUser = false;
        StepDetail = "";
        if (!keepTranscript) _announcedPreviewAddress = null;
        NotifyRunState();

        string scriptPath = Path.Combine(workingDirectory, scriptName);
        if (!File.Exists(scriptPath))
        {
            LaunchProblem = $"This working folder is missing a piece it needs ({scriptName}). Try choosing your working folder again from the File menu.";
            Notify(nameof(LaunchProblem));
            return;
        }

        var commandLine = new StringBuilder("powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ");
        commandLine.Append('"').Append(scriptPath).Append('"');
        foreach (string argument in arguments)
        {
            commandLine.Append(' ');
            if (argument.Contains(' ')) commandLine.Append('"').Append(argument).Append('"');
            else commandLine.Append(argument);
        }

        try
        {
            _process = ConPtyProcess.Start(commandLine.ToString(), workingDirectory);
        }
        catch (Exception error)
        {
            LaunchProblem = $"Could not get started: {error.Message}";
            Notify(nameof(LaunchProblem));
            return;
        }

        IsRunning = true;
        StartedAt = DateTime.UtcNow;
        _finished = 0;
        _launchedScriptName = scriptName;
        // "started preview.ps1 COMP 1" — the sentence a teacher would
        // recognise; Note() redacts the arguments on the way in.
        string argumentText = arguments.Count > 0 ? " " + string.Join(" ", arguments) : "";
        ActivityTrail.Note(ActivityTrail.Event.TaskStarted, $"started {scriptName}{argumentText}");
        NotifyRunState();

        var process = _process;
        _readerThread = new Thread(() => ReadLoop(process)) { IsBackground = true };
        _readerThread.Start();

        // Watch the CHILD PROCESS handle directly. The ConPTY output pipe is
        // NOT reliably closed when the child exits — WSL leaves a background
        // process holding it open — so waiting on end-of-stream alone can hang
        // forever and the "Done" state would never appear. When the process
        // exits we close the pseudo console (unblocking the reader) and finish.
        _exitThread = new Thread(() => ExitWatch(process)) { IsBackground = true };
        _exitThread.Start();
    }

    private void ReadLoop(ConPtyProcess process)
    {
        var decoder = Encoding.UTF8.GetDecoder();
        var buffer = new byte[8192];
        var chars = new char[16384];
        while (true)
        {
            int count = process.ReadOutput(buffer);
            if (count <= 0) break;
            int charCount = decoder.GetChars(buffer, 0, count, chars, 0);
            BufferOutput(new string(chars, 0, charCount));
        }
        // End of stream (the console closed on its own — the common case).
        process.WaitForExit(10_000);
        int exitCode = process.ExitCode ?? -1;
        Post(() => FinishRun(exitCode));
    }

    private void ExitWatch(ConPtyProcess process)
    {
        process.WaitForExit(-1);          // block until the child actually exits
        int exitCode = process.ExitCode ?? -1;
        process.ClosePty();               // unblock the reader so it drains and ends
        _readerThread?.Join(3000);        // let the final output flush through first
        Post(() => FinishRun(exitCode));
    }

    /// <summary>Coalesces chunks so the interface never redraws per byte (0.15 s cadence).</summary>
    private void BufferOutput(string text)
    {
        bool schedule;
        lock (_outputGate)
        {
            _pendingOutput.Append(text);
            schedule = !_flushScheduled;
            _flushScheduled = true;
        }
        if (schedule)
            Task.Delay(150).ContinueWith(_ => Post(FlushBufferedOutput));
    }

    private void FlushBufferedOutput()
    {
        string text;
        lock (_outputGate)
        {
            text = _pendingOutput.ToString();
            _pendingOutput.Clear();
            _flushScheduled = false;
        }
        if (text.Length > 0) ReceiveOutput(text);
    }

    // ---- The single entry point -----------------------------------------

    /// <summary>Feed output into the runner — the process does, and so do tests.</summary>
    public void ReceiveOutput(string text)
    {
        Transcript.Append(text);
        AdvanceMilestones(text);
        // Capture the announced preview address the instant it is printed. It
        // appears early (before the build), so by the time the site is serving
        // it has long scrolled out of the recent-text window — relying on that
        // window left the app polling the wrong host port when a second folder
        // got a different port block, and its preview never appeared (issue 7).
        if (OutputParsers.PreviewAddress(text) is { } address) _announcedPreviewAddress = address;
        LastOutputAt = DateTime.UtcNow;
        if (IsAwaitingInput) { IsAwaitingInput = false; Notify(nameof(IsAwaitingInput)); }
        Notify(nameof(Transcript));
        SchedulePromptCheck();
    }

    /// <summary>
    /// Make a runner that never launched anything LOOK like one in the middle
    /// of a task, so the marketing captures photograph the real progress view
    /// instead of a blank one.
    ///
    /// Capture-only: nothing in the product calls it. Without it the staged
    /// window rendered neither branch of <c>TaskProgressView.Render</c> — no
    /// step counter and no plain-language line — which made the Windows
    /// "progress" screenshot contradict its own caption ("Progress is
    /// described in words") by showing no words at all. The quiet seconds are
    /// backdated deliberately: four is what makes the view show its
    /// "still working…" timer, which is the state worth photographing.
    /// </summary>
    public void StageAsRunningForCapture(IReadOnlyList<TaskMilestone> milestones,
                                         string output,
                                         int quietSeconds = 4)
    {
        Milestones = milestones;
        IsRunning = true;
        StartedAt = DateTime.UtcNow;
        ReceiveOutput(output);
        LastOutputAt = DateTime.UtcNow.AddSeconds(-quietSeconds);
        NotifyRunState();
    }

    // ---- Question detection ---------------------------------------------

    /// <summary>
    /// A question is published when a prompt-shaped current line has sat in
    /// silence for three seconds — fresh output always cancels the pending
    /// check, so a busy script is never mistaken for a waiting one.
    /// </summary>
    private void SchedulePromptCheck()
    {
        _promptCheck?.Cancel();
        var check = new CancellationTokenSource();
        _promptCheck = check;
        Task.Delay(3000, check.Token).ContinueWith(t =>
        {
            if (t.IsCanceled) return;
            Post(() =>
            {
                if (!IsRunning) return;
                string line = Transcript.CurrentLine.Trim();
                if (line.Length == 0 || !QuestionParser.LooksLikeQuestion(line)) return;
                var asked = QuestionParser.SeparateDefaultAnswer(line);
                PendingQuestion = asked.Question;
                SuggestedAnswer = asked.SuggestedAnswer;
                PendingCancelToken = asked.CancelToken;
                IsAwaitingInput = true;
                Notify(nameof(PendingQuestion));
                Notify(nameof(SuggestedAnswer));
                Notify(nameof(IsAwaitingInput));
            });
        });
    }

    /// <summary>Safety-net hint: prompt-shaped line plus ≥4 s of silence.</summary>
    public bool MayBeWaitingForInput(DateTime asOf)
    {
        if (!IsRunning) return false;
        if ((asOf - LastOutputAt).TotalSeconds < 4) return false;
        string line = Transcript.CurrentLine.Trim();
        return line.Length > 0 && QuestionParser.LooksLikeQuestion(line);
    }

    // ---- Input ----------------------------------------------------------

    public void SendLine(string line)
    {
        if (IsAwaitingInput) { IsAwaitingInput = false; Notify(nameof(IsAwaitingInput)); }
        _process?.WriteInput(Encoding.UTF8.GetBytes(line + "\r"));
    }

    public void SendRaw(string text) => _process?.WriteInput(Encoding.UTF8.GetBytes(text));

    /// <summary>
    /// Cancel means what it says: send the script's own cancel key so its
    /// clean-up runs; when it offered no way out, stopping the task is the
    /// only way to honour the button.
    /// </summary>
    public void CancelPendingQuestion()
    {
        WasCancelled = true;
        if (IsAwaitingInput) { IsAwaitingInput = false; Notify(nameof(IsAwaitingInput)); }
        Notify(nameof(WasCancelled));
        if (PendingCancelToken.Length == 0) Terminate();
        else SendLine(PendingCancelToken);
    }

    /// <summary>
    /// Cancels the task because the teacher asked to cancel it.
    /// Sends an interrupt signal (Control-C) through the pseudo-terminal
    /// so foreground process groups and traps terminate cleanly, falling back
    /// to direct termination after two seconds.
    /// </summary>
    public void CancelByUser(Action? onCleanup = null)
    {
        WasCancelled = true;
        WasStoppedByUser = true;
        Notify(nameof(WasCancelled));
        Notify(nameof(WasStoppedByUser));
        onCleanup?.Invoke();
        SendRaw("\x03");
        Task.Delay(2000).ContinueWith(_ =>
        {
            if (IsRunning)
            {
                Terminate();
            }
        });
    }

    /// <summary>An ending the teacher asked for is not a fault.</summary>
    public void StopByUser()
    {
        WasStoppedByUser = true;
        Notify(nameof(WasStoppedByUser));
        Terminate();
    }

    public void Terminate() => _process?.Kill();

    /// <summary>
    /// Waits for the run to end, however long it takes. UNBOUNDED on
    /// purpose, as on the mac: a build or deploy runs for minutes, and a
    /// default timeout here once force-killed every deploy five seconds in
    /// — the console died between two launcher lines and the failure read
    /// as the toolchain's, not the app's. A bound belongs only where the
    /// caller has already asked the process to die: see
    /// <see cref="WaitUntilFinishedOrKill"/>.
    /// </summary>
    public async Task<bool> WaitUntilFinished()
    {
        while (IsRunning)
        {
            await Task.Delay(100);
        }
        return LastExitCode == 0;
    }

    /// <summary>
    /// Bounded wait for a process that has been TOLD to stop (StopByUser /
    /// Terminate): if it has not died by the deadline, force-finish it so a
    /// wedged teardown cannot hang its caller. Never use this to wait on
    /// live work — the force-finish kills the run it waits on.
    /// </summary>
    public async Task<bool> WaitUntilFinishedOrKill(int timeoutMs)
    {
        var start = DateTime.UtcNow;
        while (IsRunning && (DateTime.UtcNow - start).TotalMilliseconds < timeoutMs)
        {
            await Task.Delay(100);
        }
        if (IsRunning)
        {
            FinishRun(-1);
        }
        return LastExitCode == 0;
    }

    private void FinishRun(int exitCode)
    {
        // Either the reader (EOF) or the exit watcher can get here first;
        // only the first one finishes.
        if (Interlocked.Exchange(ref _finished, 1) != 0) return;
        _promptCheck?.Cancel();
        if (IsAwaitingInput) { IsAwaitingInput = false; Notify(nameof(IsAwaitingInput)); }
        FlushBufferedOutput();
        LastExitCode = exitCode;
        IsRunning = false;
        _process?.Dispose();
        _process = null;
        NoteTaskFinished(exitCode);
        NotifyRunState();
    }

    /// <summary>
    /// The trail line distinguishes a failure from a stop the teacher asked
    /// for and from backing out at a question — all three exit non-zero, and
    /// only one is a fault (see shared-rules.json → activityTrail.mustRecord).
    /// </summary>
    private void NoteTaskFinished(int exitCode)
    {
        string outcome = exitCode == 0 ? "succeeded"
            : WasStoppedByUser ? "stopped by the teacher"
            : WasCancelled ? "backed out at a question"
            : $"failed (exit code {exitCode})";
        string duration = "";
        if (StartedAt is { } startedAt)
        {
            TimeSpan elapsed = DateTime.UtcNow - startedAt;
            duration = elapsed.TotalSeconds < 60
                ? $" after {Math.Max(1, (int)elapsed.TotalSeconds)}s"
                : $" after {(int)elapsed.TotalMinutes}m {elapsed.Seconds}s";
        }
        ActivityTrail.Note(ActivityTrail.Event.TaskFinished,
            $"finished {_launchedScriptName} — {outcome}{duration}");
    }

    // ---- Milestones ------------------------------------------------------

    /// <summary>
    /// Takes the HIGHEST milestone the new output reveals — a later marker
    /// implies the earlier steps, so varying output never stalls or reverses
    /// the bar. A count belongs to the step that reported it, so stepDetail
    /// clears on every advance.
    /// </summary>
    private void AdvanceMilestones(string newText)
    {
        if (_milestones.Count == 0) { UpdateStepDetail(newText); return; }
        _unscannedOutput += newText;
        while (_reachedMilestoneCount < _milestones.Count)
        {
            int matchedIndex = -1;
            int matchedEnd = -1;
            for (int i = _reachedMilestoneCount; i < _milestones.Count; i++)
            {
                int index = _unscannedOutput.IndexOf(_milestones[i].Marker, StringComparison.Ordinal);
                if (index >= 0) { matchedIndex = i; matchedEnd = index + _milestones[i].Marker.Length; }
            }
            if (matchedIndex < 0) break;
            _reachedMilestoneCount = matchedIndex + 1;
            _unscannedOutput = _unscannedOutput[matchedEnd..];
            StepDetail = "";
            Notify(nameof(StepDetail));
            Notify(nameof(MilestonesReached));
            Notify(nameof(ProgressFraction));
            Notify(nameof(CurrentMilestoneLabel));
            Notify(nameof(StepDescription));
        }
        UpdateStepDetail(newText);
        if (_unscannedOutput.Length > 8000)
            _unscannedOutput = _unscannedOutput[^4000..];
    }

    private void UpdateStepDetail(string newText)
    {
        if (OutputParsers.UploadProgress(newText) is { } progress)
            StepDetail = $"{progress.Done} of {progress.Total}";
        else if (OutputParsers.UploadTotal(newText) is { } total)
            StepDetail = $"0 of {total}";
        else if (OutputParsers.BuildStepProgress(newText) is { } step)
            StepDetail = $"step {step.Done} of {step.Total}";
        else return;
        Notify(nameof(StepDetail));
    }

    /// <summary>A finished successful task has completed everything.</summary>
    public int MilestonesReached =>
        _milestones.Count == 0 ? 0
        : !IsRunning && LastExitCode == 0 ? _milestones.Count
        : _reachedMilestoneCount;

    public double ProgressFraction =>
        _milestones.Count == 0 ? 0 : (double)MilestonesReached / _milestones.Count;

    /// <summary>The milestone AFTER the last one reached; the final label when done.</summary>
    public string CurrentMilestoneLabel =>
        _milestones.Count == 0 ? ""
        : _milestones[Math.Min(MilestonesReached, _milestones.Count - 1)].Label;

    public string StepDescription =>
        _milestones.Count == 0 ? ""
        : $"Step {Math.Min(MilestonesReached + 1, _milestones.Count)} of {_milestones.Count}";

    // ---- Derived answers -------------------------------------------------

    private Uri? _announcedPreviewAddress;

    /// <summary>The address the launcher announced — captured when printed, so it survives a long build.</summary>
    public Uri? PreviewAddress =>
        _announcedPreviewAddress ?? OutputParsers.PreviewAddress(Transcript.RecentText(8000));

    public Uri? PublishedSiteUrl
    {
        get
        {
            Uri? url = OutputParsers.PublishedSiteUrl(Transcript.RecentText(8000));
            return url is null ? null : OutputParsers.ApplyingCustomDomain(CustomDomainForLinks, url);
        }
    }

    /// <summary>The folder a folder-mode publish landed in, or null (a Netlify publish).</summary>
    public string? PublishedFolder => OutputParsers.PublishedFolder(Transcript.RecentText(8000));

    public string? FailureExplanation => FailureExplainer.Explanation(Transcript.RecentText(8000));

    public bool LastRunSucceeded => LastExitCode == 0;

    // ---- Plumbing --------------------------------------------------------

    private void Post(Action action)
    {
        if (_ui is not null) _ui.Post(_ => action(), null);
        else action();
    }

    private void NotifyRunState()
    {
        Notify(nameof(IsRunning));
        Notify(nameof(LastExitCode));
        Notify(nameof(WasCancelled));
        Notify(nameof(WasStoppedByUser));
        Notify(nameof(MilestonesReached));
        Notify(nameof(ProgressFraction));
        Notify(nameof(CurrentMilestoneLabel));
        Notify(nameof(StepDescription));
    }

    private void Notify([CallerMemberName] string? property = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(property));
}

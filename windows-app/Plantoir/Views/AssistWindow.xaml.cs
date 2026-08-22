using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Documents;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Plantoir.Services;
using Windows.System;

namespace Plantoir.Views;

/// <summary>
/// A conversation about one section, in a window of its own.
///
/// Its own window rather than a pane, because of what the teacher needs to be
/// doing while it runs: looking at the preview of the very section being
/// changed. A pane inside the main window would put the conversation and the
/// thing it is about in competition for the same screen.
///
/// The safety story is not implemented here — it is inherited. The window
/// drives <see cref="AssistAgent"/>, which drives the same
/// <c>plantoir-mcp</c> that Claude Code drives, so the plan-before-write rule,
/// the backups, the refusals and the course lock are the tools' behaviour and
/// not a second copy of it. What this window owns is the last step: showing
/// the teacher what is about to happen and waiting to be told yes.
/// </summary>
public sealed partial class AssistWindow : Window
{
    private readonly string _folder;
    private readonly Course _course;
    private readonly int _section;
    private readonly MainWindow? _main;

    private readonly LocalModel _model = new();
    private McpClient? _tools;
    private AssistAgent? _agent;
    private readonly CancellationTokenSource _closing = new();
    private AssistPromptHistory _history;
    private string? _lastRecalled;
    private string HistoryKey => $"AssistPromptHistory-{_course.Code}-{_section}";

    public AssistWindow(string workspacePath, Course course, int section, MainWindow? main = null)
    {
        InitializeComponent();
        try { SystemBackdrop = new Microsoft.UI.Xaml.Media.MicaBackdrop(); } catch { }
        _folder = workspacePath;
        _course = course;
        _section = section;
        _main = main;

        string? stored = null;
        if (App.Settings.AssistPromptHistories.TryGetValue(HistoryKey, out var s))
        {
            stored = s;
        }
        _history = AssistPromptHistory.Read(stored);

        Input.TextChanged += Input_TextChanged;

        Title = $"Revise {course.Code} Section {section}";
        Heading.Text = $"Revising {course.Code} Section {section}";
        Subheading.Text = "Ask for a change in plain words. Every change is backed up and can be undone, " +
                          "and nothing reaches students until the section deploys — which always waits for your OK.";

        Closed += (_, _) => Shutdown();

        // Started on Loaded, not here: the download offer is a ContentDialog,
        // and a dialog needs a XamlRoot, which does not exist until the
        // window's content has actually been loaded. Raised once.
        Root.Loaded += OnceLoaded;
    }

    private void OnceLoaded(object sender, RoutedEventArgs e)
    {
        Root.Loaded -= OnceLoaded;
        _ = Begin();
    }

    // ---- Starting up -----------------------------------------------------

    /// <summary>
    /// Get the assistant to the point where it can answer: the model running,
    /// the tools connected, and the teacher told what those two words mean.
    ///
    /// Each step reports failure in the teacher's terms and stops. A half
    /// started session that accepts typing and cannot act on it would be worse
    /// than one that plainly says it is not available.
    /// </summary>
    private async Task Begin()
    {
        // Claimed as the window opens, not once the engine is ready — a
        // teacher three minutes into a download still has the assistant open
        // as far as Settings' "may I remove this model" question is
        // concerned. Mirrors the mac's AssistSession.prepare().
        AssistActivity.Begin(_folder, _course.Code, _section);

        ActivityTrail.Note(ActivityTrail.Event.AssistantOpened,
            "assistant opened", _course.Code, _section);
        var startingAt = DateTime.UtcNow;

        if (ClaudeCodeLauncher.FindServer() is not { } server)
        {
            ActivityTrail.Note(ActivityTrail.Event.AssistantWouldNotStart,
                "the assistant’s tools were missing", _course.Code, _section);
            Say("Assistant", "The Plantoir tools couldn’t be found, so there is nothing for the " +
                            "assistant to work with. Reinstalling Plantoir should put them back.");
            return;
        }

        if (!_model.IsInstalled())
        {
            // Shared with Settings' own housekeeping list through
            // AssistModelStores, rather than downloaded straight into
            // _model here — a teacher who pressed Download in Settings and
            // then opened the assistant while it ran used to get a SECOND
            // download racing the first onto the same file, each undoing
            // the other. Joining the same store means this window sees
            // (and can show progress for) a download started anywhere.
            var store = AssistModelStores.Store(_model.Tier);

            // Whether the download in flight was started from THIS window —
            // decides what closing the window does. A teacher who shuts
            // this window has finished with IT, but since the stores are
            // shared (AssistModelStores), the download this window can see
            // may have been started in Settings, where the whole point was
            // to fetch it ahead of time and get on with something else.
            // Closing a window that merely WATCHED must not cancel that —
            // mac parity, AssistSession.startedTheDownload; see
            // GUI-IMPROVEMENTS.md row 219 for the bug this exists to avoid
            // repeating.
            bool startedByThisWindow = false;

            // The one place a teacher gets to refuse it — but only when
            // nothing is already running. A download already in flight
            // (started from Settings, or from another assistant window on
            // this tier) was already agreed to once; asking again here
            // would be asking a question the teacher already answered.
            if (store.State != AssistModelStoreState.Downloading && !store.IsReady)
            {
                var offer = new ContentDialog
                {
                    Title = "Download the assistant?",
                    Content = "The assistant runs on this computer — nothing you write is sent anywhere. " +
                              "It needs a one-time download of about 1.1 GB, and then it works offline.",
                    PrimaryButtonText = "Download",
                    CloseButtonText = "Not now",
                    DefaultButton = ContentDialogButton.Primary,
                    XamlRoot = Root.XamlRoot,
                };
                if (await offer.ShowAsync() != ContentDialogResult.Primary)
                {
                    Say("Assistant", "No assistant, then — close this window whenever you like.");
                    return;
                }
                store.Download();
                startedByThisWindow = true;
            }

            var note = SayWithBar("Assistant", "Downloading the assistant…");

            // Reports arrive on the store's own thread; this handler is
            // POSTED to this window's thread, so one can still be in the
            // queue when the download finishes — and it would land after the
            // closing message and overwrite it with a stale byte count. The
            // flag makes anything arriving after the end a no-op.
            bool finished = false;
            var completion = new TaskCompletionSource();
            void OnStoreChanged()
            {
                DispatcherQueue.TryEnqueue(() =>
                {
                    if (finished) return;
                    if (store.State == AssistModelStoreState.Downloading)
                    {
                        var fetching = new LocalModel.Fetching(store.ReceivedBytes, store.TotalBytes);
                        note.Text.Text = fetching.Describe();
                        note.Bar.IsIndeterminate = !fetching.Known;
                        if (fetching.Known) note.Bar.Value = fetching.Percent;
                    }
                    else
                    {
                        completion.TrySetResult();
                    }
                });
            }
            store.Changed += OnStoreChanged;
            using (_closing.Token.Register(() =>
            {
                // Cancel the SHARED download only when this window is the
                // one that started it. A window that merely joined an
                // in-flight download (started from Settings, or another
                // assistant window) just stops watching on close — the
                // download itself keeps running for whoever else is
                // looking at it.
                if (startedByThisWindow) store.Cancel();
                completion.TrySetResult();
            }))
            {
                if (store.IsReady) completion.TrySetResult();   // already finished before we subscribed
                await completion.Task;
            }
            store.Changed -= OnStoreChanged;

            finished = true;
            note.Bar.Visibility = Visibility.Collapsed;
            if (!store.IsReady)
            {
                note.Text.Text = "The download didn’t finish. Check the network and try opening this window again.";
                return;
            }
            note.Text.Text = "The assistant is downloaded.";
        }

        if (!await _model.Start(null, _closing.Token))
        {
            ActivityTrail.Note(ActivityTrail.Event.AssistantWouldNotStart,
                "the assistant’s engine would not start", _course.Code, _section);
            Say("Assistant", "The assistant wouldn’t start. Restarting Plantoir usually settles it.");
            return;
        }

        _tools = await McpClient.Start(server, _folder, _course.Code, _closing.Token);
        if (_tools is null)
        {
            ActivityTrail.Note(ActivityTrail.Event.AssistantWouldNotStart,
                "the assistant’s tools did not answer", _course.Code, _section);
            Say("Assistant", "The assistant started, but Plantoir’s tools didn’t answer. Try opening this window again.");
            return;
        }

        // Narrowed before the model ever sees them — see AssistAgent for the
        // measurements. Fewer tools is both better routing and a shorter
        // prompt, and the prompt is what makes the first answer slow.
        var schemas = AssistAgent.NarrowToLocal(await _tools.Tools(_closing.Token), _course.Code);

        _agent = new AssistAgent(_model, _tools, schemas, _course.Code, _section)
        {
            // A tool that narrates gets its words on the thinking indicator,
            // where "Thinking" alone would be a lie minutes long.
            OnToolProgress = NoteToolProgress,
            // Building and deploying automate the main window's own flows —
            // once, on screen — rather than running again behind the chat.
            ShowPreviewInApp = () => _main?.ShowPreviewFor(_course.Code, _section),
            StartDeployInApp = () => _main?.DeployFor(_course.Code, _section),
            StartDeployInAppAsync = async () =>
            {
                if (_main is not null) await _main.DeployForAsync(_course.Code, _section);
            },
            StopPreviewInApp = () => _main?.StopPreviewFor(_course.Code, _section),
            StopPreviewInAppAsync = async () =>
            {
                if (_main is not null) await _main.StopPreviewForAsync(_course.Code, _section);
            },
            SectionIsBusy = () => _main?.IsSectionBusy(_course.Code, _section) == true,
            // Same process as the previews, so the in-memory leases are the
            // truth about whether one is on screen.
            PreviewIsShowing = () => PreviewLeases.Active.Any(lease =>
                lease.FolderPath == _folder &&
                string.Equals(lease.CourseCode, _course.Code, StringComparison.OrdinalIgnoreCase) &&
                lease.SectionNumber == _section),
            ConfirmationMode = () => App.Settings.AssistantAsksBeforeChanging,
            OnPlanAccepted = () =>
            {
                App.Settings.PlansAcceptedCount++;
                try { App.Settings.Save(); } catch { }
            },
            DestinationProvider = () =>
            {
                if (_course.Configuration.DeploysToLocalFolder) return "a folder on this computer";
                if (_course.Configuration.DeploysToCloudflare) return "Cloudflare Pages";
                return "Netlify";
            },
        };

        // Mount the prompt shelf at the top of the window with clickable cards.
        var shelf = new AssistPromptShelfView(phrasing =>
        {
            ShowRecalled(phrasing);
            _history.StopBrowsing();
            Input.Focus(FocusState.Programmatic);
        });
        PromptShelfHost.Content = shelf;
        PromptShelfArea.Visibility = Visibility.Visible;

        ActivityTrail.Note(ActivityTrail.Event.AssistantReady,
            $"the assistant was ready after {(DateTime.UtcNow - startingAt).TotalSeconds:F1}s",
            _course.Code, _section);
        // Typing is available from here.
        Input.IsEnabled = true;
        SendButton.IsEnabled = true;
        Input.Focus(FocusState.Programmatic);
        // Handed to the agent so the FIRST turn awaits it instead of racing
        // it into a timeout on the model's single slot.
        _agent.Priming = WarmUp(schemas);
    }

    /// <summary>
    /// Prime the model with the tool definitions in the background while the
    /// teacher reads the briefing and decides what to type.
    ///
    /// llama.cpp caches the prompt prefix in memory, so every turn starts warm.
    /// On the host GPU/CPU this takes a couple seconds and is fire-and-forget:
    /// if it fails, the first real message simply evaluates the prefix itself.
    /// </summary>
    private async Task WarmUp(JsonArray schemas)
    {
        try
        {
            if (_agent is not null)
            {
                await _model.Ask(_agent.PrimingMessages(), schemas, _closing.Token);
            }
        }
        catch
        {
            // Non-fatal: first turn evaluates prefix if warmup didn't complete
        }
    }

    // The opening menu of example requests lives on
    // AssistAgent.ExampleRequests, beside the loop that keeps its promises,
    // where the tests pin the two together.

    // ---- One turn --------------------------------------------------------

    private async void Send_Click(object sender, RoutedEventArgs e) => await SendWhatIsTyped();

    private void Input_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (_history.IsBrowsing && Input.Text != _lastRecalled)
        {
            _history.StopBrowsing();
        }
    }

    private void ShowRecalled(string text)
    {
        _lastRecalled = text;
        Input.Text = text;
        Input.SelectionStart = text.Length;
        Input.SelectionLength = 0;
    }

    private async void Input_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == VirtualKey.Enter)
        {
            e.Handled = true;
            await SendWhatIsTyped();
            return;
        }

        if (e.Key == VirtualKey.Up)
        {
            if (Input.Text.Contains('\n')) return;
            string? recalled = _history.Earlier(Input.Text);
            if (recalled is null) return;
            ShowRecalled(recalled);
            e.Handled = true;
            return;
        }

        if (e.Key == VirtualKey.Down)
        {
            if (Input.Text.Contains('\n')) return;
            string? recalled = _history.Later();
            if (recalled is null) return;
            ShowRecalled(recalled);
            e.Handled = true;
            return;
        }
    }

    private async Task SendWhatIsTyped()
    {
        if (_agent is null) return;
        string said = Input.Text.Trim();
        if (said.Length == 0) return;

        _history.Remember(said);
        App.Settings.AssistPromptHistories[HistoryKey] = _history.Stored;
        try { App.Settings.Save(); } catch { }
        _lastRecalled = null;

        Input.Text = "";
        Say("You", said);
        await Turn(() => _agent.Say(said, _closing.Token));
    }

    private async void Approve_Click(object sender, RoutedEventArgs e)
    {
        if (_agent is null) return;
        string word = ApproveButton.Content?.ToString()
            ?? (AssistAgent.NeedsApproval(_agent.PendingTool ?? "")
                ? AssistWording.DeployAccepted : AssistWording.PlanAccepted);
        HideApproval();
        Say("You", word);
        await Turn(async () =>
        {
            var lines = await _agent.Approve(_closing.Token);
            if (App.Settings.AssistantAsksBeforeChanging && !App.Settings.ConfirmationMentioned && App.Settings.PlansAcceptedCount >= 15)
            {
                App.Settings.ConfirmationMentioned = true;
                try { App.Settings.Save(); } catch { }
                lines.Add(new AssistAgent.Line("assistant",
                    "The assistant shows what it is about to do before doing it. You can change that in Settings."));
            }
            return lines;
        });
    }

    private async void Decline_Click(object sender, RoutedEventArgs e)
    {
        if (_agent is null) return;
        string word = DeclineButton.Content?.ToString() ?? AssistWording.Cancelled;
        HideApproval();
        Say("You", word);
        await Turn(() => _agent.Decline(_closing.Token));
    }

    /// <summary>
    /// Run one exchange and put it on screen.
    ///
    /// The input is disabled throughout — not for tidiness, but because a
    /// second request arriving mid-turn would interleave two conversations
    /// through one set of tools against one course.
    /// </summary>
    private async Task Turn(Func<Task<List<AssistAgent.Line>>> exchange)
    {
        Input.IsEnabled = false;
        SendButton.IsEnabled = false;
        ShowThinking();
        try
        {
            foreach (var line in await exchange())
            {
                Say(Speaker(line.Speaker), line.Text);
                if (line.NeedsApproval) ShowApproval(line.Text);
                if (line.Text.Contains(AssistWording.MayIAskForYourDates)) ShowDatesOffer();
            }
        }
        catch (OperationCanceledException) { /* the window is closing */ }
        catch (Exception error)
        {
            Say("Assistant", $"Something went wrong there: {error.Message}");
        }
        finally
        {
            HideThinking();
            // Never re-enable typing under a question that is still waiting —
            // the answer to "shall I go ahead?" is a button, not a sentence.
            bool waiting = _agent?.IsAwaitingApproval == true;
            Input.IsEnabled = _agent is not null && !waiting;
            SendButton.IsEnabled = Input.IsEnabled;
            if (Input.IsEnabled) Input.Focus(FocusState.Programmatic);
        }
    }

    // One name for everything on the assistant's side. Tool results used to
    // say "Plantoir" while the model said "Assistant", and a teacher reading
    // the conversation saw two strangers where there is one helper.
    private static string Speaker(string raw) => raw switch
    {
        "assistant" => "Assistant",
        "tools" => "Assistant",
        _ => raw,
    };

    // ---- The transcript --------------------------------------------------

    /// <summary>Add a turn and scroll to it. Returns its text block so slow work can update in place.</summary>
    private TextBlock Say(string speaker, string text)
    {
        var body = new TextBlock { TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true };
        Write(body, text);
        AddCard(speaker, body);
        return body;
    }

    /// <summary>
    /// Put text on a TextBlock with <c>**bold**</c> actually bold.
    ///
    /// The tools write for a Markdown reader — the briefing emphasises the two
    /// words it exists to distinguish, and the approval line emphasises the
    /// tool about to run. Setting <c>.Text</c> renders the asterisks literally,
    /// so the one visual cue in the most important sentence in the window was
    /// showing up as punctuation.
    ///
    /// This is not a Markdown parser and should not become one. It handles the
    /// one construct the tools actually emit; anything else is left exactly as
    /// written, which for a teacher's own page titles is the safer failure.
    /// </summary>
    private static void Write(TextBlock block, string text)
    {
        block.Inlines.Clear();

        string[] lines = text.Replace("\r\n", "\n").Split('\n');
        for (int line = 0; line < lines.Length; line++)
        {
            if (line > 0) block.Inlines.Add(new LineBreak());

            // Odd-numbered pieces sit between a pair of markers, so they are
            // the emphasised ones. An unpaired marker leaves a final piece with
            // an even index, and it stays plain — text, not an error.
            string[] pieces = lines[line].Split("**");
            for (int piece = 0; piece < pieces.Length; piece++)
            {
                if (pieces[piece].Length == 0) continue;
                bool emphasised = piece % 2 == 1 && piece < pieces.Length - 1;
                block.Inlines.Add(new Run
                {
                    Text = pieces[piece],
                    FontWeight = emphasised ? FontWeights.SemiBold : FontWeights.Normal,
                });
            }
        }
    }

    public void AddStagedBubbleForCapture(string speaker, bool fromTeacher, params UIElement[] contents)
    {
        AddCard(speaker, contents);
    }

    /// <summary>
    /// The one place a turn is built, so every bubble is the same bubble.
    ///
    /// Laid out the way every messaging app a teacher already uses lays it
    /// out: what they said on the right, what the assistant said on the left.
    /// Nobody has to learn that, and at a glance down the transcript the two
    /// voices separate without reading a word of it.
    ///
    /// Bubbles stop well short of the full width. A line of text running the
    /// whole way across a maximised window is hard to read and, worse here,
    /// makes the two sides indistinguishable — which is the one thing this
    /// layout exists to prevent.
    /// </summary>
    private void AddCard(string speaker, params UIElement[] contents)
    {
        bool fromTeacher = speaker == "You";

        var panel = new StackPanel { Spacing = 4 };
        panel.Children.Add(new TextBlock
        {
            Text = speaker,
            Opacity = 0.7,
            Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"],
        });
        foreach (var element in contents) panel.Children.Add(element);

        // The teacher's bubble is filled with the accent colour, so its text
        // has to be the ON-accent one. Left as the default it is dark ink on a
        // dark blue ground in the light theme — unreadable, and only in the
        // half of the conversation they wrote themselves.
        if (fromTeacher)
        {
            var onAccent = (Brush)Application.Current.Resources["TextOnAccentFillColorPrimaryBrush"];
            foreach (var child in panel.Children)
            {
                if (child is TextBlock block)
                {
                    block.Foreground = onAccent;
                    foreach (var inline in block.Inlines)
                    {
                        if (inline is Microsoft.UI.Xaml.Documents.TextElement te) te.Foreground = onAccent;
                    }
                }
            }
        }

        Transcript.Children.Add(new Border
        {
            Padding = new Thickness(12),
            // The tail corner is squared off on the side the bubble comes
            // from, which is what gives a chat its direction.
            CornerRadius = fromTeacher
                ? new CornerRadius(12, 12, 4, 12)
                : new CornerRadius(12, 12, 12, 4),
            HorizontalAlignment = fromTeacher ? HorizontalAlignment.Right : HorizontalAlignment.Left,
            MaxWidth = 620,
            Background = (Brush)Application.Current.Resources[
                fromTeacher ? "AccentFillColorDefaultBrush" : "CardBackgroundFillColorDefaultBrush"],
            Child = panel,
        });
        TranscriptScroller.UpdateLayout();
        TranscriptScroller.ChangeView(null, TranscriptScroller.ScrollableHeight, null);
    }

    // ---- "It is still thinking" -------------------------------------------

    private Border? _thinking;
    private TextBlock? _thinkingLabel;
    private DispatcherTimer? _tick;
    private DateTime _thinkingSince;

    /// <summary>
    /// Put a running tool's latest progress line in the thinking indicator.
    ///
    /// The thinking indicator carries the latest progress line while the tool
    /// is active, so the teacher sees what is happening without polluting the
    /// transcript with intermediate backup and finished messages.
    /// </summary>
    private void NoteToolProgress(string message)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            if (_thinkingLabel is not null) _thinkingLabel.Text = message;
        });
    }

    /// <summary>
    /// Show that the assistant is working, and for how long.
    ///
    /// Without this the window sits perfectly still while the model chews
    /// through a six-thousand-token prompt at twenty-one tokens a second,
    /// which on the first question of a session is minutes. Silence and a
    /// crash look identical, and a teacher who cannot tell them apart will
    /// reasonably close the window.
    ///
    /// The elapsed count is deliberate rather than decorative. Animated dots
    /// alone say "something is happening"; a number climbing past thirty
    /// seconds also says "this one is slow, and it is not stuck", which is the
    /// honest description of a first answer on two CPU cores.
    /// </summary>
    private void ShowThinking()
    {
        HideThinking();
        _thinkingSince = DateTime.Now;

        var label = new TextBlock { Text = "Thinking", Opacity = 0.8, TextWrapping = TextWrapping.Wrap };
        _thinkingLabel = label;
        var dots = new TextBlock { Text = "", Opacity = 0.8, MinWidth = 24 };
        var elapsed = new TextBlock { Text = "", Opacity = 0.55 };

        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 2 };
        row.Children.Add(label);
        row.Children.Add(dots);
        row.Children.Add(elapsed);

        // Left, like everything else the assistant says — it IS the assistant
        // speaking, and a centred or full-width indicator would break the line
        // the eye follows down the conversation.
        _thinking = new Border
        {
            Padding = new Thickness(12),
            CornerRadius = new CornerRadius(12, 12, 12, 4),
            HorizontalAlignment = HorizontalAlignment.Left,
            Background = (Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"],
            Child = row,
        };
        Transcript.Children.Add(_thinking);
        TranscriptScroller.UpdateLayout();
        TranscriptScroller.ChangeView(null, TranscriptScroller.ScrollableHeight, null);

        int step = 0;
        _tick = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(400) };
        _tick.Tick += (_, _) =>
        {
            step++;
            dots.Text = new string('.', step % 4);
            int seconds = (int)(DateTime.Now - _thinkingSince).TotalSeconds;
            // Quiet for the first few seconds; a stopwatch on every quick
            // answer would make the app feel slower than it is.
            elapsed.Text = seconds >= 5 ? $"  {seconds}s" : "";
        };
        _tick.Start();
    }

    private void HideThinking()
    {
        _tick?.Stop();
        _tick = null;
        if (_thinking is not null) Transcript.Children.Remove(_thinking);
        _thinking = null;
        _thinkingLabel = null;
    }

    /// <summary>A turn that carries a progress bar as well as words.</summary>
    private sealed record Reporting(TextBlock Text, ProgressBar Bar);

    /// <summary>
    /// Say something that will take a while, with a bar under it.
    ///
    /// The bar is added to a panel this method built and still holds, rather
    /// than to whatever <c>body.Parent</c> reports. Parent is a visual-tree
    /// property and is not reliably set the instant an element is put in a
    /// Children collection, so the first attempt silently added the bar to
    /// nothing at all: the download ran with no bar on screen, which is the
    /// very thing it was there to show.
    ///
    /// It starts indeterminate. The total arrives from the server a moment
    /// after the download begins, and a determinate bar pinned at zero in the
    /// meantime is exactly what "frozen" looks like.
    /// </summary>
    private Reporting SayWithBar(string speaker, string text)
    {
        var body = new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true };
        var bar = new ProgressBar
        {
            IsIndeterminate = true,
            Minimum = 0,
            Maximum = 100,
            Margin = new Thickness(0, 8, 0, 0),
            HorizontalAlignment = HorizontalAlignment.Stretch,
        };
        AddCard(speaker, body, bar);
        return new Reporting(body, bar);
    }

    private void ShowApproval(string question)
    {
        // A DEPLOY and a PLAN read differently to a teacher and should look
        // different: a deploy puts work in front of students and cannot be
        // taken back by us, while a plan is the assistant checking it
        // understood. A deploy set for half six tomorrow is still a deploy.
        bool isDeploy = AssistAgent.NeedsApproval(_agent?.PendingTool ?? "");
        ApproveButton.Content = isDeploy ? AssistWording.DeployAccepted : AssistWording.PlanAccepted;
        ApprovalBar.Visibility = Visibility.Visible;
    }

    private void HideApproval() => ApprovalBar.Visibility = Visibility.Collapsed;

    /// <summary>
    /// Presents an inline card asking whether the teacher would like to enter class dates,
    /// with "Enter class dates" (opens SectionScheduleDialog) and "Not now" buttons.
    /// </summary>
    private void ShowDatesOffer()
    {
        var box = new StackPanel { Spacing = 10, Margin = new Thickness(0, 4, 0, 4) };

        var headerRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        headerRow.Children.Add(new FontIcon { Glyph = "\uE787", FontSize = 16 });
        headerRow.Children.Add(new TextBlock
        {
            Text = AssistWording.MayIAskForYourDates,
            FontWeight = FontWeights.SemiBold,
            FontSize = 14,
        });
        box.Children.Add(headerRow);

        var subtext = new TextBlock
        {
            Text = "They can be typed in, chosen from a file, or read from a shared sheet.",
            FontSize = 13,
            Opacity = 0.8,
            TextWrapping = TextWrapping.Wrap,
        };
        box.Children.Add(subtext);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        var enterBtn = new Button
        {
            Content = "Enter class dates",
            Style = (Style)Application.Current.Resources["AccentButtonStyle"],
        };
        var notNowBtn = new Button
        {
            Content = "Not now",
        };

        enterBtn.Click += async (_, _) =>
        {
            buttons.Visibility = Visibility.Collapsed;
            Say("You", "Enter class dates");
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
            var xamlRoot = Root.XamlRoot ?? Content?.XamlRoot;
            if (xamlRoot is null)
            {
                Say("Assistant", "Could not open class dates dialog.");
                return;
            }
            var dialog = new SectionScheduleDialog(_folder, _course, _section, hwnd)
            {
                XamlRoot = xamlRoot,
            };
            try
            {
                var result = await dialog.ShowAsync();
                if (result == ContentDialogResult.Primary && dialog.SavedDates is { Count: > 0 } dates)
                {
                    Say("Assistant", $"Remembered {dates.Count} class {(dates.Count == 1 ? "date" : "dates")} for {_course.Code} Section {_section}.");
                }
                else
                {
                    Say("Assistant", "No class dates were recorded.");
                }
            }
            catch (Exception ex)
            {
                App.LogDiagnostic($"SectionScheduleDialog ShowAsync exception: {ex.Message}");
                Say("Assistant", "No class dates were recorded.");
            }
        };

        notNowBtn.Click += (_, _) =>
        {
            buttons.Visibility = Visibility.Collapsed;
            Say("You", "Not now");
            Say("Assistant", "No class dates recorded. You can add them anytime.");
        };

        buttons.Children.Add(enterBtn);
        buttons.Children.Add(notNowBtn);
        box.Children.Add(buttons);

        AddCard("Assistant", box);
    }

    // ---- Ending ----------------------------------------------------------

    /// <summary>
    /// Closing the window ends the session, and ending the session must give
    /// the machine its memory back and the course its freedom back: the model
    /// container stops, and the server exits, which drops the assist lease
    /// that has been holding Preview and Deploy off this course.
    /// </summary>
    private void Shutdown()
    {
        try { _closing.Cancel(); } catch { }

        // Released unconditionally, even if Begin() never got this far (the
        // server was missing, or the teacher declined a download): if this
        // does not run, Settings stays locked out of removing anything until
        // the app restarts, which is worse than briefly under-counting.
        try { AssistActivity.End(_folder, _course.Code, _section); } catch { }

        // WAITED ON, not fired and forgotten. The old version started this on
        // a background task and returned, so closing the window — or closing
        // Plantoir straight after — could end the process before the container
        // was removed and the WSL keepalive released. Two conversations left
        // four keepalives behind that way.
        //
        // Bounded, because a shutdown that hangs is worse than one that leaks:
        // if Docker is wedged, the keepalive now ends by itself anyway.
        var cleanup = Task.Run(async () =>
        {
            if (_tools is not null) await _tools.DisposeAsync();
            _model.Stop();
        });
        try { cleanup.Wait(TimeSpan.FromSeconds(8)); } catch { }
    }
}

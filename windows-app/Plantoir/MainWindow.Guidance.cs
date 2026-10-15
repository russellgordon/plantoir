using System;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Plantoir.Core.Models;
using Plantoir.Services;

namespace Plantoir;

/// <summary>
/// The window's half of the guidance for assistants (#496; the mac's #454,
/// <c>AgentGuidanceSheet.swift</c> and the notice above its path bar): the
/// dismissable notice when the guidance could not be written, and the
/// question asked before Plantoir's section is added to a teacher's own
/// AGENTS.md or CLAUDE.md. The pass itself runs in
/// <see cref="ToolchainReadiness"/>, after the folder's copy, on its own task.
/// </summary>
/// <remarks>
/// <para><b>One dialog at a time.</b> WinUI allows one open ContentDialog per
/// window and throws on a second. So the question is asked only when
/// <see cref="DialogGate.IsOpen"/> says none is up; otherwise it waits, and
/// is tried again when the window is next activated and every two seconds
/// while a file still waits (the timer stops when none does). The quit
/// question (<c>AskBeforeQuittingThroughWork</c>) takes this one DOWN first
/// rather than colliding with it (plan review M8), and a question taken down
/// that way — or by the window closing — is put back unanswered: closing a
/// window is not a Not Now.</para>
/// <para><b>Each file is asked about in exactly one window</b>
/// (<see cref="ToolchainReadiness.TakeNextPending"/>), AGENTS.md first.
/// Enter adds (the primary button is the default, as the mac's Return);
/// Escape is Not Now.</para>
/// </remarks>
public sealed partial class MainWindow
{
    private ContentDialog? _guidanceDialog;
    private bool _guidanceDialogTakenDown;
    private Microsoft.UI.Dispatching.DispatcherQueueTimer? _guidanceTimer;

    private void AttachGuidance()
    {
        void GuidanceChanged(string folder)
        {
            if (IsClosed) return;
            DispatcherQueue.TryEnqueue(() => { if (!IsClosed) RefreshGuidance(); });
        }
        ToolchainReadiness.GuidanceChanged += GuidanceChanged;
        Activated += (_, args) =>
        {
            if (args.WindowActivationState != WindowActivationState.Deactivated && !IsClosed) RefreshGuidance();
        };
        Closed += (_, _) =>
        {
            ToolchainReadiness.GuidanceChanged -= GuidanceChanged;
            _guidanceTimer?.Stop();
        };
        GuidanceNotice.CloseButtonClick += (_, _) =>
        {
            if (Workspace.WorkspacePath is { Length: > 0 } folder) ToolchainReadiness.DismissGuidanceNotice(folder);
        };
    }

    /// <summary>The notice for the folder on screen, and the next question if one waits.</summary>
    private void RefreshGuidance()
    {
        string? notice = ToolchainReadiness.GuidanceNoticeFor(Workspace.WorkspacePath);
        GuidanceNotice.Message = notice ?? "";
        GuidanceNotice.IsOpen = notice is not null;
        _ = AskAboutTheNextFileAsync();
    }

    private async System.Threading.Tasks.Task AskAboutTheNextFileAsync()
    {
        if (_guidanceDialog is not null || IsClosed || _waitingForCopies) return;
        string? folder = Workspace.WorkspacePath;
        if (string.IsNullOrEmpty(folder) || !ToolchainReadiness.HasPending(folder)) { _guidanceTimer?.Stop(); return; }
        if (Content?.XamlRoot is null || DialogGate.IsOpen(Content.XamlRoot))
        {
            LookAgainSoon();
            return;
        }
        var pending = ToolchainReadiness.TakeNextPending(folder);
        if (pending is null) return;

        var body = new StackPanel { Spacing = 8, MaxWidth = 460 };
        body.Children.Add(FormBuilders_DialogExplanation(AgentGuidanceWording.AskFound(pending.FileName)));
        body.Children.Add(new TextBlock { Text = AgentGuidanceWording.AskWhat, TextWrapping = TextWrapping.Wrap });
        body.Children.Add(new TextBlock { Text = AgentGuidanceWording.AskYoursStays, TextWrapping = TextWrapping.Wrap });
        var section = new TextBox
        {
            Text = pending.Section,
            IsReadOnly = true,
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            FontFamily = new FontFamily("Consolas"),
            FontSize = 12,
            MaxHeight = 220,
        };
        ScrollViewer.SetVerticalScrollBarVisibility(section, ScrollBarVisibility.Auto);
        AutomationProperties.SetAutomationId(section, "guidanceSectionText");
        var expander = new Expander
        {
            Header = AgentGuidanceWording.ShowWhatIsAdded,
            Content = section,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
        };
        AutomationProperties.SetAutomationId(expander, "guidanceShowWhatIsAdded");
        body.Children.Add(expander);

        var dialog = new ContentDialog
        {
            Title = AgentGuidanceWording.AskTitle(pending.FileName),
            Content = body,
            PrimaryButtonText = AgentGuidanceWording.Add,
            CloseButtonText = AgentGuidanceWording.NotNow,
            DefaultButton = ContentDialogButton.Primary,
            XamlRoot = Content.XamlRoot,
        };
        AutomationProperties.SetAutomationId(dialog, "guidanceAskDialog");
        _guidanceDialog = dialog;
        _guidanceDialogTakenDown = false;
        ContentDialogResult answer;
        try { answer = await dialog.ShowAsync(); }
        catch (Exception error)
        {
            // Another dialog won the race between the gate and ShowAsync.
            App.LogDiagnostic($"guidance question not shown: {error.Message}");
            _guidanceDialog = null;
            ToolchainReadiness.PutBack(folder, pending);
            LookAgainSoon();
            return;
        }
        _guidanceDialog = null;
        if (IsClosed || _guidanceDialogTakenDown)
        {
            ToolchainReadiness.PutBack(folder, pending);
            return;
        }
        bool add = answer == ContentDialogResult.Primary;
        await System.Threading.Tasks.Task.Run(() => ToolchainReadiness.Answer(folder, pending, add));
        if (!IsClosed) RefreshGuidance();
    }

    private static TextBlock FormBuilders_DialogExplanation(string text) => Views.FormBuilders.DialogExplanation(text);

    private void LookAgainSoon()
    {
        if (_guidanceTimer is null)
        {
            _guidanceTimer = DispatcherQueue.CreateTimer();
            _guidanceTimer.Interval = TimeSpan.FromSeconds(2);
            _guidanceTimer.IsRepeating = true;
            _guidanceTimer.Tick += (_, _) =>
            {
                if (IsClosed || !ToolchainReadiness.HasPending(Workspace.WorkspacePath)) { _guidanceTimer?.Stop(); return; }
                _ = AskAboutTheNextFileAsync();
            };
        }
        if (!_guidanceTimer.IsRunning) _guidanceTimer.Start();
    }

    /// <summary>
    /// Takes the guidance question down, unanswered, so another dialog can be
    /// shown — the quit question (plan review M8). It goes back in the queue.
    /// </summary>
    private void TakeTheGuidanceQuestionDown()
    {
        if (_guidanceDialog is not { } dialog) return;
        _guidanceDialogTakenDown = true;
        try { dialog.Hide(); } catch { }
    }
}

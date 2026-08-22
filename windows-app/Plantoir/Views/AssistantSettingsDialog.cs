using System;
using System.IO;
using System.Linq;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Plantoir.Services;

namespace Plantoir.Views;

/// <summary>
/// Settings dialog: Assistant confirmation switch, model choice (automatic, smaller, larger),
/// and model housekeeping (download status, download, remove).
/// </summary>
public sealed class AssistantSettingsDialog : ContentDialog
{
    private readonly AppSettings _settings;
    private readonly AssistHardwareBudget _budget;
    private readonly StackPanel _panel;
    private readonly TextBlock _confirmationCaution;
    private readonly TextBlock _whatHappensNext;
    private readonly TextBlock _spaceSummary;
    private readonly RadioButton _rbAuto;
    private readonly RadioButton _rbSmaller;
    private readonly RadioButton _rbLarger;
    private readonly TextBlock _smallerCaution;
    private readonly TextBlock _largerCaution;
    private readonly StackPanel _housekeepingList;

    public AssistantSettingsDialog(AppSettings settings, AssistHardwareBudget? budget = null)
    {
        _settings = settings;
        _budget = budget ?? new AssistHardwareBudget();

        Title = "Settings";
        CloseButtonText = "Done";
        DefaultButton = ContentDialogButton.Close;

        _panel = new StackPanel { Spacing = 18, MaxWidth = 520 };
        Content = new ScrollViewer
        {
            Content = _panel,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            MaxHeight = 560
        };

        // Note trail on open
        string currentChoice = _settings.AssistantModelChoice;
        ActivityTrail.Note(
            ActivityTrail.Event.AppSettingsOpened,
            $"opened Settings — the assistant is set to {AssistModelChoice.Label(currentChoice).ToLowerInvariant()}");

        // ---- Section 1: Before it changes your pages ----
        var section1 = new StackPanel { Spacing = 6 };
        section1.Children.Add(FormBuilders.SectionHeaderWithCaption("Before it changes your pages", null));

        var toggle = new ToggleSwitch
        {
            Header = "Ask me before changing anything",
            IsOn = _settings.AssistantAsksBeforeChanging,
            OffContent = "Off",
            OnContent = "On"
        };
        AutomationProperties.SetAutomationId(toggle, "assistantAsksBeforeChanging");
        section1.Children.Add(toggle);

        var toggleCaption = FormBuilders.ExampleCaption(
            "The assistant says what it is about to do, and waits, before it publishes or hides pages. " +
            "Deploying always asks, whatever this is set to.");
        section1.Children.Add(toggleCaption);

        _confirmationCaution = CautionLine("assistantConfirmationCaution");
        section1.Children.Add(_confirmationCaution);
        _panel.Children.Add(section1);

        // ---- Section 2: Which assistant runs on this PC ----
        var section2 = new StackPanel { Spacing = 8 };
        section2.Children.Add(FormBuilders.SectionHeaderWithCaption("Which assistant runs on this PC", null));

        var choicesPanel = new StackPanel { Spacing = 10 };

        // Option 1: Automatic
        _rbAuto = new RadioButton
        {
            GroupName = "AssistChoice",
            Content = CreateChoiceHeader("Choose for me", AssistModelChoice.Detail(AssistModelChoice.Automatic, _budget)),
            IsChecked = currentChoice == AssistModelChoice.Automatic
        };
        AutomationProperties.SetAutomationId(_rbAuto, "assistantChoiceAutomatic");
        choicesPanel.Children.Add(_rbAuto);

        // Option 2: Smaller
        var smallerStack = new StackPanel { Spacing = 4 };
        _rbSmaller = new RadioButton
        {
            GroupName = "AssistChoice",
            Content = CreateChoiceHeader(AssistModelTier.Small.ChoiceLabel(), AssistModelTier.Small.SizeGuidance()),
            IsChecked = currentChoice == AssistModelChoice.Smaller
        };
        AutomationProperties.SetAutomationId(_rbSmaller, "assistantChoiceSmaller");
        smallerStack.Children.Add(_rbSmaller);
        _smallerCaution = CautionLine("assistantChoiceCautionSmaller");
        string? sc = AssistModelChoice.Caution(AssistModelChoice.Smaller, _budget);
        if (sc is not null) { _smallerCaution.Text = sc; _smallerCaution.Visibility = Visibility.Visible; }
        smallerStack.Children.Add(_smallerCaution);
        choicesPanel.Children.Add(smallerStack);

        // Option 3: Larger
        var largerStack = new StackPanel { Spacing = 4 };
        _rbLarger = new RadioButton
        {
            GroupName = "AssistChoice",
            Content = CreateChoiceHeader(AssistModelTier.Large.ChoiceLabel(), AssistModelTier.Large.SizeGuidance()),
            IsChecked = currentChoice == AssistModelChoice.Larger
        };
        AutomationProperties.SetAutomationId(_rbLarger, "assistantChoiceLarger");
        largerStack.Children.Add(_rbLarger);
        _largerCaution = CautionLine("assistantChoiceCautionLarger");
        string? lc = AssistModelChoice.Caution(AssistModelChoice.Larger, _budget);
        if (lc is not null) { _largerCaution.Text = lc; _largerCaution.Visibility = Visibility.Visible; }
        largerStack.Children.Add(_largerCaution);
        choicesPanel.Children.Add(largerStack);

        section2.Children.Add(choicesPanel);

        _whatHappensNext = FormBuilders.ExampleCaption("");
        AutomationProperties.SetAutomationId(_whatHappensNext, "assistantWhatHappensNext");
        section2.Children.Add(_whatHappensNext);
        _panel.Children.Add(section2);

        // ---- Section 3: On this PC (Housekeeping) ----
        var section3 = new StackPanel { Spacing = 8 };
        section3.Children.Add(FormBuilders.SectionHeaderWithCaption("On this PC", null));

        _housekeepingList = new StackPanel { Spacing = 10 };
        section3.Children.Add(_housekeepingList);

        _spaceSummary = FormBuilders.ExampleCaption("");
        AutomationProperties.SetAutomationId(_spaceSummary, "assistantSpaceSummary");
        section3.Children.Add(_spaceSummary);
        _panel.Children.Add(section3);

        // Events
        toggle.Toggled += (_, _) =>
        {
            _settings.AssistantAsksBeforeChanging = toggle.IsOn;
            _settings.Save();
            ActivityTrail.Note(
                ActivityTrail.Event.AssistantConfirmationChanged,
                toggle.IsOn
                    ? "turned ON asking before the assistant changes anything"
                    : "turned OFF asking before the assistant changes anything — it will now act straight away");
            UpdateUI();
        };

        _rbAuto.Checked += (_, _) => SetChoice(AssistModelChoice.Automatic);
        _rbSmaller.Checked += (_, _) => SetChoice(AssistModelChoice.Smaller);
        _rbLarger.Checked += (_, _) => SetChoice(AssistModelChoice.Larger);

        // One store per rung, shared with every assistant window through
        // AssistModelStores — not one made here — so a download started in
        // Settings is still visible (and still the SAME download) if a
        // teacher opens the assistant while it runs, and vice versa.
        foreach (var tier in new[] { AssistModelTier.Small, AssistModelTier.Large })
            AssistModelStores.Store(tier).Changed += OnStoreChanged;
        Closed += (_, _) => DetachFromStores();

        UpdateUI();
    }

    private bool _detached;

    /// <summary>
    /// Undo the store subscriptions above. Idempotent, and public, so the
    /// caller can detach in a try/finally around ShowAsync too — a
    /// ContentDialog that never actually got shown (WinUI allows only one
    /// on screen at a time; a second Settings… invocation before the first
    /// closes throws) would otherwise never fire Closed, leaving this
    /// instance subscribed to the app-lifetime AssistModelStores forever.
    /// </summary>
    public void DetachFromStores()
    {
        if (_detached) return;
        _detached = true;
        foreach (var tier in new[] { AssistModelTier.Small, AssistModelTier.Large })
            AssistModelStores.Store(tier).Changed -= OnStoreChanged;
    }

    /// <summary>
    /// A store's progress arrives on whatever thread the download is running
    /// on; every WinUI element this dialog owns must only be touched from
    /// the UI thread that created them.
    /// </summary>
    private void OnStoreChanged() => DispatcherQueue?.TryEnqueue(UpdateUI);

    private void SetChoice(string choice)
    {
        if (_settings.AssistantModelChoice == choice) return;
        _settings.AssistantModelChoice = choice;
        _settings.Save();

        string desc = choice == AssistModelChoice.Automatic
            ? $"to have Plantoir choose — {_budget.Tier.DisplayName()} on this PC"
            : AssistModelChoice.Resolved(choice, _budget).DisplayName();

        ActivityTrail.Note(ActivityTrail.Event.AssistantModelChosen, $"chose {desc} in Settings");
        UpdateUI();
    }

    private void UpdateUI()
    {
        string choice = _settings.AssistantModelChoice;
        var chosenTier = AssistModelChoice.Resolved(choice, _budget);

        // Confirmation caution
        if (!_settings.AssistantAsksBeforeChanging && chosenTier == AssistModelTier.Small)
        {
            _confirmationCaution.Text =
                "The smaller assistant misreads about one request in five, so it will sometimes " +
                "do the wrong thing without asking first. “Undo that” takes back whatever it did.";
            _confirmationCaution.Visibility = Visibility.Visible;
        }
        else
        {
            _confirmationCaution.Visibility = Visibility.Collapsed;
        }

        // What happens next
        bool chosenDownloaded = AssistModelStores.Store(chosenTier).IsReady;
        if (chosenDownloaded)
        {
            _whatHappensNext.Text = $"{chosenTier.ChoiceLabel()} is ready. Opening the assistant will use it.";
        }
        else
        {
            _whatHappensNext.Text =
                $"{chosenTier.ChoiceLabel()} is not on this PC yet. Opening the assistant " +
                $"will offer to download it — {chosenTier.DownloadDescription()}.";
        }

        // Housekeeping rows
        _housekeepingList.Children.Clear();
        long totalBytes = 0;
        bool anyFound = false;

        foreach (var tier in new[] { AssistModelTier.Small, AssistModelTier.Large })
        {
            long? sizeOnDisk = AssistModelStore.BytesOnDisk(tier);
            if (sizeOnDisk.HasValue)
            {
                totalBytes += sizeOnDisk.Value;
                anyFound = true;
            }

            var row = CreateHousekeepingRow(tier, sizeOnDisk);
            _housekeepingList.Children.Add(row);
        }

        if (anyFound)
        {
            string formatted = FormatBytes(totalBytes);
            _spaceSummary.Text =
                $"The assistant is using {formatted} on this PC. " +
                "Removing one frees its space; opening the assistant offers to download " +
                "whichever one you have chosen.";
        }
        else
        {
            _spaceSummary.Text = "Nothing is downloaded yet, so the assistant is taking no space.";
        }
    }

    private UIElement CreateHousekeepingRow(AssistModelTier tier, long? sizeOnDisk)
    {
        var store = AssistModelStores.Store(tier);
        var rowPanel = new StackPanel { Spacing = 4 };
        var topRow = new Grid();
        topRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        topRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var info = new StackPanel { Spacing = 2 };
        info.Children.Add(new TextBlock { Text = tier.ChoiceLabel(), FontWeight = FontWeights.SemiBold });

        string statusText = sizeOnDisk.HasValue && sizeOnDisk.Value >= tier.DownloadBytes()
            ? $"Downloaded · {FormatBytes(sizeOnDisk.Value)} on this PC"
            : sizeOnDisk.HasValue
                ? "A part-finished download · downloading again replaces it"
                : $"Not downloaded · {tier.DownloadDescription()}";

        var statusBlock = new TextBlock
        {
            Text = statusText,
            FontSize = 12,
            Opacity = 0.7
        };
        AutomationProperties.SetAutomationId(statusBlock, $"assistantStatus{tier}");
        info.Children.Add(statusBlock);
        topRow.Children.Add(info);

        var button = new Button();
        Grid.SetColumn(button, 1);

        if (store.State == AssistModelStoreState.Downloading)
        {
            button.Content = "Stop";
            AutomationProperties.SetAutomationId(button, $"assistantStopDownload{tier}");
            button.Click += (_, _) => store.Cancel();
        }
        else if (store.IsReady)
        {
            button.Content = "Remove";
            AutomationProperties.SetAutomationId(button, $"assistantRemove{tier}");
            button.Click += (_, _) => store.Remove();
        }
        else
        {
            button.Content = "Download";
            AutomationProperties.SetAutomationId(button, $"assistantDownload{tier}");
            button.Click += (_, _) => store.Download();
        }

        topRow.Children.Add(button);
        rowPanel.Children.Add(topRow);

        if (store.State == AssistModelStoreState.Downloading)
        {
            var bar = new ProgressBar
            {
                IsIndeterminate = store.TotalBytes <= 0,
                Value = store.FractionComplete * 100,
            };
            AutomationProperties.SetAutomationId(bar, $"assistantDownloadProgress{tier}");
            rowPanel.Children.Add(bar);

            var progressText = new TextBlock
            {
                Text = store.TotalBytes > 0
                    ? $"{FormatBytes(store.ReceivedBytes)} of {FormatBytes(store.TotalBytes)} ({store.FractionComplete * 100:0}%)"
                    : $"{FormatBytes(store.ReceivedBytes)} so far",
                FontSize = 12,
                Opacity = 0.7,
            };
            rowPanel.Children.Add(progressText);
        }

        if (store.State == AssistModelStoreState.Failed && store.FailureReason is { } reason)
        {
            rowPanel.Children.Add(new TextBlock
            {
                Text = reason,
                FontSize = 12,
                TextWrapping = TextWrapping.Wrap,
                Foreground = (Brush)Application.Current.Resources["SystemFillColorCautionBrush"],
            });
        }

        return rowPanel;
    }

    private static StackPanel CreateChoiceHeader(string title, string detail)
    {
        var sp = new StackPanel { Spacing = 2, Margin = new Thickness(0, 0, 0, 4) };
        sp.Children.Add(new TextBlock { Text = title, FontWeight = FontWeights.SemiBold });
        sp.Children.Add(new TextBlock
        {
            Text = detail,
            FontSize = 12,
            Opacity = 0.7,
            TextWrapping = TextWrapping.Wrap
        });
        return sp;
    }

    private static TextBlock CautionLine(string automationId)
    {
        var line = new TextBlock
        {
            FontSize = 12,
            TextWrapping = TextWrapping.Wrap,
            Foreground = (Brush)Application.Current.Resources["SystemFillColorCautionBrush"],
            Visibility = Visibility.Collapsed,
        };
        AutomationProperties.SetAutomationId(line, automationId);
        return line;
    }

    private static string FormatBytes(long bytes)
    {
        if (bytes >= 1024 * 1024 * 1024)
            return $"{bytes / (1024.0 * 1024 * 1024):0.00} GB";
        if (bytes >= 1024 * 1024)
            return $"{bytes / (1024.0 * 1024):0.0} MB";
        return $"{bytes / 1024.0:0.0} KB";
    }

}

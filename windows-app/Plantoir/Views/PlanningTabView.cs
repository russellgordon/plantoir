using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.Web.WebView2.Core;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Plantoir.Services;

namespace Plantoir.Views;

/// <summary>
/// The course page's Planning tab (#801, #820; the mac's #708 and #803): the
/// course's unit plans, shown from <c>courses/&lt;CODE&gt;/.internal/planning</c>
/// on this PC only, through <see cref="GuardedSite"/>. A Unit popup, Back,
/// Forward, Reload and Open in Browser above the plan; with nothing to show,
/// the offer to plan a unit with each outside assistant installed; when the
/// guarded view cannot be made, <c>cannotShowTitle</c> and nothing loaded.
/// Every rule is Core's (<see cref="PlanningTab"/>, <see cref="PlanInTheBrowser"/>,
/// <see cref="PlanAUnit"/>, <see cref="PlanningAssets"/>), every word the
/// contract's (<see cref="PlanningTabWording"/>).
/// </summary>
/// <remarks>
/// <para><b>Kept, not rebuilt.</b> The course page collapses this view on the
/// Settings tab rather than removing it, so the web view, its page and its
/// history survive a switch to Settings and back (the course page's own
/// remarks say why the settings form is collapsed too).</para>
///
/// <para><b>When it looks again</b> (<c>unitPlanning.tab.whenItLooksAgain</c>):
/// when the tab appears, when the window is activated, when a unit is chosen,
/// and on Reload. Each time the plan's look is mirrored from the app's own
/// template (<see cref="PlanningAssets.Refresh"/>) and the folder read again
/// (<see cref="PlanningTab.LookIn"/>); the page on screen is reloaded from the
/// disk (every response says <c>no-store</c>). No watcher and no timer.</para>
///
/// <para><b>The popup is a drop-down button with a menu</b>, not a ComboBox:
/// a ComboBox raises nothing when the entry it already names is chosen again,
/// and the contract says choosing an entry always loads its page
/// (<c>followsThePage.rule</c>: after a link to the correlation page the
/// popup still names the unit, and choosing it must go back to the plan).</para>
///
/// <para><b>Nothing here speaks to the built-in assistant</b>: Plan a Unit opens
/// the outside doors only (Russell's ruling on #897: its surface is frozen).</para>
/// </remarks>
public sealed class PlanningTabView : UserControl
{
    private readonly MainWindow _window;
    private readonly Course _course;
    private readonly string _planningFolder;
    private readonly LocalSiteGuard _guard;

    private PlanningTab.Look _look = new(Array.Empty<UnitPlans.Plan>(), Array.Empty<PlanningTab.Choice>());
    private PlanningTab.Choice? _chosen;
    private bool _hasLooked;
    private bool _hasLoadedAPage;
    private bool _couldNotShow;
    private Task<bool>? _making;
    private bool _lookFailureNoted;
    private bool _linkRefusalNoted;

    private WebView2? _web;
    private GuardedSite? _site;

    private readonly Grid _bar = new() { Padding = new Thickness(8, 4, 8, 4), ColumnSpacing = 4 };
    private readonly TextBlock _unitLabel = new() { Text = PlanningTabWording.UnitPopup, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(4, 0, 4, 0) };
    private readonly DropDownButton _unitButton = new() { MinWidth = 160, MaxWidth = 420, HorizontalContentAlignment = HorizontalAlignment.Left };
    private readonly TextBlock _unitTitle = new() { TextTrimming = TextTrimming.CharacterEllipsis };
    private readonly MenuFlyout _unitMenu = new() { Placement = FlyoutPlacementMode.BottomEdgeAlignedLeft };
    private readonly Button _back = IconButton("", PlanningTabWording.Back, "planningBack");
    private readonly Button _forward = IconButton("", PlanningTabWording.Forward, "planningForward");
    private readonly Button _reload = IconButton("", PlanningTabWording.Reload, "planningReload");
    private readonly Button _browser = IconButton("", PlanningTabWording.OpenInBrowser, "planningOpenInBrowser");
    private readonly Grid _browserHolder = new();

    private readonly Grid _content = new() { MinHeight = 0 };
    private readonly StackPanel _empty = new() { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Spacing = 8, MaxWidth = 520, Padding = new Thickness(16) };
    private readonly StackPanel _emptyButtons = new() { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 8, 0, 0) };
    private readonly Button _planWithClaude = new() { Content = PlanAUnit.ClaudeButtonTitle };
    private readonly Button _planWithCodex = new() { Content = PlanAUnit.CodexButtonTitle };
    private readonly StackPanel _cannotShow = new() { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Spacing = 8, MaxWidth = 520, Padding = new Thickness(16) };

    /// <summary>
    /// Where #824's share bar goes (the plan's section 7): the tab's last row,
    /// its height the bar's own (<c>Auto</c>), empty until then. Nothing put
    /// here may take a fixed height, or the plan above it is squeezed out of
    /// the window (#838; the mac's 2,529-point share bar).
    /// </summary>
    public Border ShareBarSlot { get; } = new();

    public PlanningTabView(MainWindow window, Course course)
    {
        _window = window;
        _course = course;
        _planningFolder = UnitPlans.PlanningFolder(course.DirectoryPath);
        _guard = new LocalSiteGuard(_planningFolder, LocalSiteGuard.PlansHost, LocalSiteGuard.PlanContentTypes);

        var root = new Grid();
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star), MinHeight = 0 });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        BuildBar();
        Grid.SetRow(_bar, 0);
        root.Children.Add(_bar);

        BuildEmpty();
        BuildCannotShow();
        _content.Children.Add(_empty);
        _content.Children.Add(_cannotShow);
        Grid.SetRow(_content, 1);
        root.Children.Add(_content);

        AutomationProperties.SetAutomationId(ShareBarSlot, "planningShareBarSlot");
        Grid.SetRow(ShareBarSlot, 2);
        root.Children.Add(ShareBarSlot);

        Content = root;
        ShowState(State.Nothing);

        Loaded += (_, _) => OutsideAssistantPresence.Changed += PresenceChanged;
        Unloaded += (_, _) => OutsideAssistantPresence.Changed -= PresenceChanged;
        ActualThemeChanged += (_, _) => FollowTheTheme();
    }

    // ---- Building ---------------------------------------------------------------

    private static Button IconButton(string glyph, string name, string automationId)
    {
        var button = new Button
        {
            Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Transparent),
            BorderThickness = new Thickness(0),
            MinWidth = 34,
            MinHeight = 30,
            Content = new FontIcon { Glyph = glyph, FontSize = 14 },
            IsEnabled = false,
        };
        AutomationProperties.SetName(button, name);
        AutomationProperties.SetAutomationId(button, automationId);
        ToolTipService.SetToolTip(button, name);
        return button;
    }

    private void BuildBar()
    {
        for (int i = 0; i < 7; i++)
            _bar.ColumnDefinitions.Add(new ColumnDefinition { Width = i == 2 ? new GridLength(1, GridUnitType.Star) : GridLength.Auto });
        _bar.BorderBrush = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["DividerStrokeColorDefaultBrush"];
        _bar.BorderThickness = new Thickness(0, 0, 0, 1);

        _unitButton.Content = _unitTitle;
        _unitButton.Flyout = _unitMenu;
        AutomationProperties.SetName(_unitButton, PlanningTabWording.UnitPopup);
        AutomationProperties.SetAutomationId(_unitButton, "planningUnitPopup");
        AutomationProperties.SetLabeledBy(_unitButton, _unitLabel);
        Grid.SetColumn(_unitLabel, 0);
        Grid.SetColumn(_unitButton, 1);
        _bar.Children.Add(_unitLabel);
        _bar.Children.Add(_unitButton);

        _back.Click += (_, _) => { if (_web?.CoreWebView2 is { CanGoBack: true } core) core.GoBack(); };
        _forward.Click += (_, _) => { if (_web?.CoreWebView2 is { CanGoForward: true } core) core.GoForward(); };
        _reload.Click += async (_, _) => await LookAgainAsync(reloadThePage: true);
        _browser.Click += async (_, _) => await OpenInBrowserAsync();
        Grid.SetColumn(_back, 3);
        Grid.SetColumn(_forward, 4);
        Grid.SetColumn(_reload, 5);
        // A dimmed button takes no pointer, so its help is on the cell around
        // it, where a pointer resting on the dimmed button still finds it
        // (openInBrowser.rule: dimmed, with the refusal as its help).
        _browserHolder.Children.Add(_browser);
        Grid.SetColumn(_browserHolder, 6);
        _bar.Children.Add(_back);
        _bar.Children.Add(_forward);
        _bar.Children.Add(_reload);
        _bar.Children.Add(_browserHolder);
    }

    private void BuildEmpty()
    {
        var title = new TextBlock
        {
            Text = PlanningTabWording.EmptyTitle, FontSize = 20, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            HorizontalAlignment = HorizontalAlignment.Center, TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center,
        };
        AutomationProperties.SetAutomationId(title, "planningEmptyTitle");
        AutomationProperties.SetHeadingLevel(title, Microsoft.UI.Xaml.Automation.Peers.AutomationHeadingLevel.Level1);
        var description = new TextBlock
        {
            Text = PlanningTabWording.EmptyDescription, Opacity = 0.75, TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center,
        };
        AutomationProperties.SetAutomationId(description, "planningEmptyDescription");
        _empty.Children.Add(new FontIcon { Glyph = "", FontSize = 40, Opacity = 0.5, HorizontalAlignment = HorizontalAlignment.Center });
        _empty.Children.Add(title);
        _empty.Children.Add(description);

        AutomationProperties.SetAutomationId(_planWithClaude, "planAUnitWithClaude");
        AutomationProperties.SetName(_planWithClaude, PlanAUnit.ClaudeButtonTitle);
        AutomationProperties.SetAutomationId(_planWithCodex, "planAUnitWithCodex");
        AutomationProperties.SetName(_planWithCodex, PlanAUnit.CodexButtonTitle);
        _planWithClaude.Click += async (_, _) => await PlanAUnitAsync(FixWithAssistant.Assistant.Claude);
        _planWithCodex.Click += async (_, _) => await PlanAUnitAsync(FixWithAssistant.Assistant.Codex);
        // Claude's first (planAUnit.shownWhen). GitHub Copilot's is held by
        // name for #884 (NamedGapLedger: planAUnit.buttons → copilot).
        _emptyButtons.Children.Add(_planWithClaude);
        _emptyButtons.Children.Add(_planWithCodex);
        _empty.Children.Add(_emptyButtons);
        ShowTheButtons();
    }

    private void BuildCannotShow()
    {
        var title = new TextBlock
        {
            Text = PlanningTabWording.CannotShowTitle, FontSize = 20, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            HorizontalAlignment = HorizontalAlignment.Center, TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center,
        };
        AutomationProperties.SetAutomationId(title, "planningCannotShowTitle");
        AutomationProperties.SetHeadingLevel(title, Microsoft.UI.Xaml.Automation.Peers.AutomationHeadingLevel.Level1);
        var description = new TextBlock
        {
            Text = PlanningTabWording.CannotShowDescription, Opacity = 0.75, TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center,
        };
        AutomationProperties.SetAutomationId(description, "planningCannotShowDescription");
        _cannotShow.Children.Add(new FontIcon { Glyph = "", FontSize = 40, Opacity = 0.5, HorizontalAlignment = HorizontalAlignment.Center });
        _cannotShow.Children.Add(title);
        _cannotShow.Children.Add(description);
    }

    // ---- What shows -------------------------------------------------------------

    private enum State { Nothing, Empty, CannotShow, Plan }

    private State _state = State.Nothing;

    private void ShowState(State state)
    {
        _state = state;
        _bar.Visibility = state == State.Plan ? Visibility.Visible : Visibility.Collapsed;
        _empty.Visibility = state == State.Empty ? Visibility.Visible : Visibility.Collapsed;
        _cannotShow.Visibility = state == State.CannotShow ? Visibility.Visible : Visibility.Collapsed;
        if (_web is not null) _web.Visibility = state == State.Plan ? Visibility.Visible : Visibility.Collapsed;
    }

    private void PresenceChanged() => DispatcherQueue?.TryEnqueue(ShowTheButtons);

    /// <summary>One Plan a Unit button per outside assistant installed, Claude's first; hidden, never greyed, for one that is not.</summary>
    private void ShowTheButtons()
    {
        _planWithClaude.Visibility = OutsideAssistantPresence.ClaudeIsInstalled ? Visibility.Visible : Visibility.Collapsed;
        _planWithCodex.Visibility = OutsideAssistantPresence.CodexIsInstalled ? Visibility.Visible : Visibility.Collapsed;
    }

    /// <summary>Where the keyboard goes when the tab is chosen: never left wherever the Settings tab had it (790 plan review M3).</summary>
    public bool TakeTheKeyboard() => _state switch
    {
        State.Plan => _unitButton.Focus(FocusState.Programmatic),
        State.Empty when _planWithClaude.Visibility == Visibility.Visible => _planWithClaude.Focus(FocusState.Programmatic),
        State.Empty when _planWithCodex.Visibility == Visibility.Visible => _planWithCodex.Focus(FocusState.Programmatic),
        _ => false,
    };

    // ---- Appearing and looking again ------------------------------------------------

    /// <summary>
    /// The tab has appeared (chosen, or chosen again after Settings): look
    /// again, show the chosen unit reloaded from the disk, and say on the
    /// trail once what it had to offer, or that no plan could be shown.
    /// </summary>
    public async Task AppearAsync()
    {
        _lookFailureNoted = false;
        _linkRefusalNoted = false;
        await LookAgainAsync(reloadThePage: true);
        PlanningTab.NoteAppearance(_course.Code, _look.Choices, couldShow: !_couldNotShow);
    }

    /// <summary>The window came to the front (the teacher may have been building a plan in a terminal): look again, when this tab is showing.</summary>
    public void WindowBecameActive()
    {
        if (Visibility == Visibility.Visible && _hasLooked) _ = LookAgainAsync(reloadThePage: true);
    }

    private async Task LookAgainAsync(bool reloadThePage)
    {
        string bundled = PlanningAssets.BundledTemplateAssets(BundledToolchain.Root);
        string planning = _planningFolder, course = _course.DirectoryPath;
        var (outcome, whyNot, look) = await Task.Run(() =>
        {
            var why = PlanningAssets.WhyNot(planning, bundled);
            var refreshed = why is null ? PlanningAssets.Refresh(planning, bundled) : null;
            return (refreshed, why, PlanningTab.LookIn(planning, course));
        });
        if (outcome is { Failed: > 0 } failed && !_lookFailureNoted)
        {
            _lookFailureNoted = true;
            ActivityTrail.Note(ActivityTrail.Event.UnitPlansLookedAt,
                PlanningTab.CouldNotRefreshTheLookTrailText(_course.Code, failed.Failed));
        }
        if (whyNot == PlanningAssets.Refusal.ALink && !_linkRefusalNoted)
        {
            // The mac writes nothing for this either; the contract has no line
            // for it (a question in 790b's report). The plan shows with the
            // look it has.
            _linkRefusalNoted = true;
            App.LogDiagnostic($"Planning tab for {_course.Code}: the plan's look was left as it was, because a folder on the way is a link");
        }

        _look = look;
        _hasLooked = true;
        RebuildTheMenu();
        if (look.Choices.Count == 0)
        {
            _chosen = null;
            ShowState(State.Empty);
            RefreshTheButtons();
            return;
        }
        if (!await MakeTheViewAsync())
        {
            ShowState(State.CannotShow);
            return;
        }
        ShowState(State.Plan);
        if (_chosen is { } current && look.Choices.Contains(current) && _hasLoadedAPage)
        {
            if (reloadThePage) _site!.Reload();
            ShowTheChoice();
            RefreshTheButtons();
            return;
        }
        var starting = PlanningTab.StartingChoice(look.Plans, look.Choices, DateOnly.FromDateTime(DateTime.Now));
        if (starting is not null) Load(starting);
        RefreshTheButtons();
    }

    /// <summary>The guarded web view, made the first time a plan is to be shown; false when it could not be (the tab then says so and loads nothing).</summary>
    private Task<bool> MakeTheViewAsync()
    {
        if (_couldNotShow) return Task.FromResult(false);
        return _making ??= MakeAsync();

        async Task<bool> MakeAsync()
        {
            try
            {
                var environment = await LocalPagesEnvironment.GetAsync();
                _web = new WebView2 { MinHeight = 0, Visibility = Visibility.Collapsed };
                AutomationProperties.SetAutomationId(_web, "planningWebView");
                AutomationProperties.SetName(_web, PlanningTabWording.TabPlanning);
                _content.Children.Add(_web);
                await _web.EnsureCoreWebView2Async(environment,
                    LocalPagesEnvironment.ControllerOptions(environment, LocalPagesEnvironment.PlansProfile));
                var core = _web.CoreWebView2;
                _site = GuardedSite.Attach(core, environment, _guard, new GuardedSite.Options(
                    (address, newWindow, clicked) => PlanNavigation.Decide(address, newWindow, clicked, _guard),
                    uri => ExternalLinks.Open(uri),
                    HandToTheApp: null,
                    GuardedSite.PlansContentSecurityPolicy,
                    AllowPrint: true), App.LogDiagnostic);
                if (_site is null) throw new InvalidOperationException("the guards could not be put in place");
                core.SourceChanged += (_, _) => FollowThePage();
                core.HistoryChanged += (_, _) => RefreshTheButtons();
                core.NavigationCompleted += (_, _) =>
                {
                    if (_guard.PathOf(core.Source) is not null) _hasLoadedAPage = true;
                    RefreshTheButtons();
                };
                FollowTheTheme();
                return true;
            }
            catch (Exception error)
            {
                App.LogDiagnostic($"Planning tab for {_course.Code}: the guarded view could not be made: {error.Message}");
                _couldNotShow = true;
                if (_web is not null) { _content.Children.Remove(_web); _web = null; }
                _site = null;
                return false;
            }
        }
    }

    private void FollowTheTheme() =>
        _site?.FollowTheme(ActualTheme switch
        {
            ElementTheme.Dark => CoreWebView2PreferredColorScheme.Dark,
            ElementTheme.Light => CoreWebView2PreferredColorScheme.Light,
            _ => CoreWebView2PreferredColorScheme.Auto,
        });

    // ---- The popup ----------------------------------------------------------------

    private void RebuildTheMenu()
    {
        _unitMenu.Items.Clear();
        int index = 0;
        foreach (var choice in _look.Choices)
        {
            var item = new RadioMenuFlyoutItem
            {
                Text = PlanningTab.TitleFor(choice, _look.Plans),
                GroupName = "planningUnits",
                IsChecked = choice == _chosen,
                Tag = choice,
            };
            AutomationProperties.SetAutomationId(item, "planningUnit" + index++);
            var chosen = choice;
            // Always loads, even the entry already named (followsThePage.rule).
            item.Click += async (_, _) => await ChooseAsync(chosen);
            _unitMenu.Items.Add(item);
        }
        ShowTheChoice();
    }

    private void ShowTheChoice()
    {
        string title = _chosen is null ? "" : PlanningTab.TitleFor(_chosen, _look.Plans);
        _unitTitle.Text = title;
        AutomationProperties.SetItemStatus(_unitButton, title);
        foreach (var item in _unitMenu.Items.OfType<RadioMenuFlyoutItem>())
            item.IsChecked = Equals(item.Tag, _chosen);
    }

    /// <summary>A unit chosen in the popup: the folder read again, then that unit's page loaded.</summary>
    private async Task ChooseAsync(PlanningTab.Choice choice)
    {
        _chosen = choice;
        await LookAgainAsync(reloadThePage: false);
        if (_state == State.Plan && _look.Choices.Contains(choice)) Load(choice);
    }

    private void Load(PlanningTab.Choice choice)
    {
        _chosen = choice;
        ShowTheChoice();
        _site?.Show(PlanningTab.PageFor(choice, _planningFolder));
        RefreshTheButtons();
    }

    /// <summary>The popup follows the page on screen (<c>followsThePage</c>), without loading anything.</summary>
    private void FollowThePage()
    {
        if (_web?.CoreWebView2?.Source is not { } source || _guard.PathOf(source) is not { } page) { RefreshTheButtons(); return; }
        if (PlanningTab.ChoiceForPage(page, _planningFolder, _look.Choices) is { } followed && followed != _chosen)
        {
            _chosen = followed;
            ShowTheChoice();
        }
        RefreshTheButtons();
    }

    // ---- The buttons --------------------------------------------------------------

    /// <summary>The page the web view is on, or null before one of the plan's has loaded.</summary>
    private string? OnScreen => _hasLoadedAPage && _web?.CoreWebView2?.Source is { Length: > 0 } source ? source : null;

    /// <summary>The chosen entry's page, as the served address the rule reads.</summary>
    private string? ChosenAddress => _chosen is null ? null : _guard.AddressOf(PlanningTab.PageFor(_chosen, _planningFolder));

    private void RefreshTheButtons()
    {
        var core = _web?.CoreWebView2;
        _back.IsEnabled = core?.CanGoBack == true;
        _forward.IsEnabled = core?.CanGoForward == true;
        _reload.IsEnabled = _state == State.Plan;
        var answer = PlanInTheBrowser.PageToOpen(OnScreen, ChosenAddress, _guard);
        string help = PlanInTheBrowser.HelpText(answer);
        _browser.IsEnabled = answer.Refusal is null;
        ToolTipService.SetToolTip(_browser, help);
        ToolTipService.SetToolTip(_browserHolder, answer.Refusal is null ? null : help);
        AutomationProperties.SetHelpText(_browser, help);
        // A redirected run (--state-dir, the UI tests) says on Reload which
        // page the view is on: UI Automation cannot read a WebView2's own
        // address, and an ItemStatus set on the web view itself was measured
        // empty (the section preview's arrangement, SectionDetailView).
        if (AppDataRoot.IsRedirected) AutomationProperties.SetItemStatus(_reload, core?.Source ?? "");
    }

    /// <summary>Open in Browser (#820): the rule asked again at the click; a refusal or a failure is an alert, never a click that does nothing.</summary>
    private async Task OpenInBrowserAsync()
    {
        var pressed = PlanInTheBrowser.Press(OnScreen, ChosenAddress, _guard, WindowsDefaultBrowser.Instance, _course.Code);
        RefreshTheButtons();
        if (pressed.Alert is { } sentence)
            await ShowAlertAsync(PlanningTabWording.OpenInBrowserCouldNotOpenTitle, sentence, "planningOpenInBrowserAlert");
    }

    /// <summary>
    /// Plan a Unit with Claude… / Codex…: Revise With's refusal at the click,
    /// then the door with <c>planAUnit.message</c> in place of the greeting;
    /// a door that did not open says so in its own words and writes no line;
    /// one that did is said on the trail after the door's own line.
    /// </summary>
    private async Task PlanAUnitAsync(FixWithAssistant.Assistant assistant)
    {
        if (_window.Workspace.WorkspacePath is not { } folder) return;
        if (OutsideDoorWording.RefusedWhileRevised(folder, _course.Code) is { } refusal)
        {
            await ShowAlertAsync(refusal.Title, refusal.Message, "planAUnitRefused");
            return;
        }
        string message = PlanAUnit.OpeningMessage(_course.Code, _course.Configuration.CourseName);
        bool opened = assistant == FixWithAssistant.Assistant.Claude
            ? ClaudeCodeLauncher.Open(folder, _course.Code, _course.Configuration.CourseName, message)
            : CodexLauncher.Open(folder, _course.Code, _course.Configuration.CourseName, message);
        if (!opened)
        {
            await ShowAlertAsync(OutsideDoorWording.DidNotOpenTitle(assistant), OutsideDoorWording.CouldNotStart(assistant, _course.Code),
                                 "planAUnitDidNotOpen");
            return;
        }
        PlanAUnit.NoteOnTheTrail(_course.Code, assistant);
    }

    private async Task ShowAlertAsync(string title, string sentence, string automationId)
    {
        if (XamlRoot is not { } root || DialogGate.IsOpen(root)) return;
        var dialog = new ContentDialog
        {
            Title = title,
            Content = new TextBlock { Text = sentence, TextWrapping = TextWrapping.Wrap },
            CloseButtonText = "OK",
            DefaultButton = ContentDialogButton.Close,
            XamlRoot = root,
        };
        AutomationProperties.SetAutomationId(dialog, automationId);
        try { await dialog.ShowAsync(); }
        catch (Exception error) { App.LogDiagnostic($"Planning tab's alert '{title}' could not be shown: {error.Message}"); }
    }
}

using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Views;

/// <summary>
/// The links checklist (#392, #399, #405; mac <c>LinksChecklistSheet</c>):
/// pages students can reach a link to but cannot open, offered as a list the
/// teacher ticks. Every rule it shows is <see cref="LinksChecklistSheet"/>'s,
/// so the contract runner and these checkboxes cannot disagree; this file is
/// only the drawing.
/// </summary>
/// <remarks>
/// <para><b>Worked out once per change of the ticks, never per row per
/// redraw</b> (#405's measurement: 11.8 s for one redraw of a 461-row sheet
/// on the mac when it did). <see cref="Refresh"/> reads going, coming-with,
/// locked and shown-ticked once and paints every row from those four sets.</para>
///
/// <para>AutomationIds: <c>linksChecklistRow:&lt;place&gt;</c> on each row's
/// checkbox, <c>linksChecklistPublish</c> and <c>linksChecklistNotNow</c> on
/// the buttons (the primary and close buttons of the dialog).</para>
/// </remarks>
public sealed class LinksChecklistDialog
{
    private readonly LinksChecklistSheet _sheet;
    private readonly ContentDialog _dialog;
    private readonly Dictionary<string, (CheckBox Box, TextBlock Second)> _rows = new(StringComparer.Ordinal);
    private bool _painting;

    public const string PublishAutomationId = "linksChecklistPublish";
    public const string NotNowAutomationId = "linksChecklistNotNow";
    public static string RowAutomationId(string place) => "linksChecklistRow:" + LinksChecklist.Key(place);

    private LinksChecklistDialog(LinksChecklistSheet sheet)
    {
        _sheet = sheet;
        var fill = new Dictionary<string, string> { ["course"] = sheet.CourseCode, ["section"] = sheet.Section.ToString() };

        var list = new StackPanel { Spacing = 6 };
        list.Children.Add(new TextBlock { Text = LinksChecklistWording.Intro, TextWrapping = TextWrapping.Wrap });

        var shown = LinksChecklist.ShownOrder(sheet.Rows);
        var byKey = sheet.Rows.ToDictionary(r => LinksChecklist.Key(r.Place), StringComparer.Ordinal);
        foreach (string group in LinksChecklist.GroupOrder)
        {
            var inGroup = shown.Where(x => byKey.TryGetValue(LinksChecklist.Key(x.Place), out var row) && row.Group == group).ToList();
            if (inGroup.Count == 0) continue;
            list.Children.Add(new TextBlock
            {
                Text = group switch
                {
                    LinksChecklist.FromAClassGroup => LinksChecklistWording.FromAClassHeading,
                    LinksChecklist.NotReachedGroup => LinksChecklistWording.NotReachedHeading,
                    _ => LinksChecklistWording.ClassesHeading,
                },
                Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"],
                Margin = new Thickness(0, 10, 0, 0),
            });
            foreach (var (place, depth) in inGroup)
            {
                var row = byKey[LinksChecklist.Key(place)];
                var box = new CheckBox { Content = sheet.NameOf(row.Place), Margin = new Thickness(depth * 24, 0, 0, 0) };
                AutomationProperties.SetAutomationId(box, RowAutomationId(row.Place));
                var second = new TextBlock
                {
                    TextWrapping = TextWrapping.Wrap,
                    Opacity = 0.7,
                    Margin = new Thickness(depth * 24 + 28, -6, 0, 0),
                };
                string captured = row.Place;
                box.Checked += (_, _) => Toggled(captured, true);
                box.Unchecked += (_, _) => Toggled(captured, false);
                list.Children.Add(box);
                list.Children.Add(second);
                _rows[LinksChecklist.Key(row.Place)] = (box, second);
            }
        }
        if (sheet.Rows.Any(r => r.IsClass))
            list.Children.Add(new TextBlock { Text = LinksChecklistWording.FrontPageStaysPut, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 10, 0, 0) });
        list.Children.Add(new TextBlock { Text = LinksChecklistWording.NothingChangesUntilYouDeploy, TextWrapping = TextWrapping.Wrap });

        _dialog = new ContentDialog
        {
            Title = LinksChecklistWording.Fill(LinksChecklistWording.SheetTitle, fill),
            Content = new ScrollViewer { Content = list, MaxHeight = 520 },
            CloseButtonText = LinksChecklistWording.NotNow,
            DefaultButton = ContentDialogButton.Primary,
        };
        _dialog.Opened += (_, _) => TagButtons();
        Refresh();
    }

    /// <summary>The ContentDialog's own buttons are template parts; tag them once it is up.</summary>
    private void TagButtons()
    {
        if (_dialog.Content is not FrameworkElement) return;
        if (FindByName(_dialog, "PrimaryButton") is Button publish) AutomationProperties.SetAutomationId(publish, PublishAutomationId);
        if (FindByName(_dialog, "CloseButton") is Button notNow) AutomationProperties.SetAutomationId(notNow, NotNowAutomationId);
    }

    private static DependencyObject? FindByName(DependencyObject root, string name)
    {
        int count = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChildrenCount(root);
        for (int i = 0; i < count; i++)
        {
            var child = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChild(root, i);
            if (child is FrameworkElement { Name: var n } && n == name) return child;
            if (FindByName(child, name) is { } found) return found;
        }
        return null;
    }

    /// <summary>The one toggle the harness calls too; a tick on a row coming with a class is ignored there.</summary>
    private void Toggled(string place, bool on)
    {
        if (_painting) return;
        _sheet.Toggle(place, on);
        Refresh();
    }

    /// <summary>Paint every row from the four sets, worked out once.</summary>
    private void Refresh()
    {
        var going = _sheet.Going;
        var comingWith = _sheet.ComingWith;
        var locked = LinksChecklist.Locked(_sheet.Rows, going, comingWith);
        var shownTicked = LinksChecklist.ShownTicked(going, comingWith);
        _painting = true;
        try
        {
            foreach (var row in _sheet.Rows)
            {
                string key = LinksChecklist.Key(row.Place);
                if (!_rows.TryGetValue(key, out var ui)) continue;
                // Coming with a ticked class: shown ticked and disabled until
                // the class is unticked (#405). Locked: shown unticked and
                // disabled, its own tick kept but not shown (#399).
                ui.Box.IsChecked = shownTicked.Contains(key);
                ui.Box.IsEnabled = !comingWith.ContainsKey(key) && !locked.Contains(key);
                ui.Second.Text = _sheet.SecondLine(row);
                ui.Second.Visibility = ui.Second.Text.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
            }
        }
        finally { _painting = false; }

        // The button counts rows SHOWN ticked (going ∪ coming with).
        _dialog.PrimaryButtonText = _sheet.PublishButton();
        _dialog.IsPrimaryButtonEnabled = shownTicked.Count > 0;
    }

    /// <summary>
    /// Show the checklist for one section and act on the answer. Returns the
    /// sentence to tell the teacher afterwards, or null when nothing needs
    /// saying (Not Now, or the dialog never got on screen).
    /// </summary>
    /// <param name="show">The caller's way of putting a dialog up (one slot, retries).</param>
    public static async Task<string?> OfferAsync(string workspacePath, Course course, int section, LinksChecklistOffer offer,
                                                 string occasion, Func<ContentDialog, Task<ContentDialogResult?>> show,
                                                 Func<bool>? folderMovedMeanwhile = null)
    {
        // never: while this app is publishing the course (it is offered when that finishes).
        if (CourseActivity.IsPublishing(workspacePath, course.Code))
            return LinksChecklistWording.Fill(LinksChecklistWording.DeployUnderWay,
                new Dictionary<string, string> { ["course"] = course.Code });

        var workspace = new AssistWorkspace(workspacePath, new NoLauncher(), undo: new UndoHistory())
            { ServesTheLocalWindow = true };   // in-process: Plantoir's own, never an outside assistant (fix round ruling 7)
        var sheet = workspace.OpenLinksChecklist(offer);
        if (sheet.Rows.Count == 0) return LinksChecklistWording.NothingLeftToPublish;

        var ui = new LinksChecklistDialog(sheet);
        AssistWorkspace.NoteOffered(sheet, occasion);
        var choice = await show(ui._dialog);
        if (choice is null) return null;
        // Answered after the window moved to another folder: act on nothing.
        if (folderMovedMeanwhile?.Invoke() == true) return null;
        if (choice != ContentDialogResult.Primary)
        {
            workspace.NotNow(sheet);
            return null;
        }
        if (CourseActivity.IsPublishing(workspacePath, course.Code))
            return LinksChecklistWording.Fill(LinksChecklistWording.DeployUnderWay,
                new Dictionary<string, string> { ["course"] = course.Code });

        var published = workspace.PublishAndRemember(sheet);
        return published.Reply(sheet);
    }

    /// <summary>Publishing pages launches nothing; anything that tries is refused.</summary>
    private sealed class NoLauncher : ILauncherRunner
    {
        public Task<LaunchOutcome> Run(string launcher, IReadOnlyList<string> arguments, string workingFolder,
                                       IProgress<string>? progress, CancellationToken cancellation) =>
            Task.FromResult(new LaunchOutcome(false, "Not from the links checklist."));
    }
}

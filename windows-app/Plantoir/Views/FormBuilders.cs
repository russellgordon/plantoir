using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using System.Threading.Tasks;
using Microsoft.UI.Xaml.Automation;
using Plantoir.Core.Catalogs;
using Plantoir.Core.Models;
using Plantoir.Services;

namespace Plantoir.Views;

/// <summary>
/// The shared form vocabulary: section headers, quiet "e.g." captions,
/// orange warnings, recessed sample boxes, list editors. One place, so a
/// setting and its preview always read the same way.
/// </summary>
public static class FormBuilders
{
    public static TextBlock SectionHeader(string title, string? caption = null)
    {
        var panel = new StackPanel { Spacing = 2, Margin = new Thickness(0, 18, 0, 4) };
        var header = new TextBlock
        {
            Text = title,
            FontSize = 18,
            FontWeight = FontWeights.SemiBold,
        };
        if (caption is null) return header;
        return header;   // caption callers use SectionHeaderWithCaption
    }

    public static UIElement SectionHeaderWithCaption(string title, string? caption)
    {
        var panel = new StackPanel { Spacing = 2, Margin = new Thickness(0, 18, 0, 4) };
        panel.Children.Add(new TextBlock { Text = title, FontSize = 18, FontWeight = FontWeights.SemiBold });
        if (caption is not null) panel.Children.Add(ExampleCaption(caption));
        return panel;
    }

    /// <summary>Quiet guidance under a control — never embedded in its label.</summary>
    public static TextBlock ExampleCaption(string text) => new()
    {
        Text = text,
        FontSize = 12,
        TextWrapping = TextWrapping.Wrap,
        Opacity = 0.7,
    };

    /// <summary>Orange: worth a second look, but the control still does what it says.</summary>
    public static TextBlock WarningCaption(string text) => new()
    {
        Text = text,
        FontSize = 12,
        TextWrapping = TextWrapping.Wrap,
        Foreground = (Brush)Application.Current.Resources["SystemFillColorCautionBrush"],
    };

    /// <summary>Rendered previews sit in a recessed rounded box — illustrations, not settings.</summary>
    public static Border SampleBox(UIElement content) => new()
    {
        Child = content,
        Background = (Brush)Application.Current.Resources["CardBackgroundFillColorSecondaryBrush"],
        CornerRadius = new CornerRadius(8),
        Padding = new Thickness(14, 10, 14, 10),
        Margin = new Thickness(8, 4, 8, 0),
        HorizontalAlignment = HorizontalAlignment.Stretch,
    };

    public static StackPanel LabeledRow(string label, FrameworkElement control)
    {
        var panel = new StackPanel { Spacing = 4, Margin = new Thickness(0, 6, 0, 0) };
        panel.Children.Add(new TextBlock { Text = label, FontSize = 13 });
        panel.Children.Add(control);
        return panel;
    }

    // ---- Protected rows -------------------------------------------------

    /// <summary>
    /// The width a blocked row's ⓘ flyout is given, in effective pixels.
    ///
    /// <para>A FIXED width, with the text wrapping inside it. A flyout whose
    /// text only has a maximum is measured as ONE line and truncates: the mac
    /// shipped exactly that and it passed every unit test, showing "Each
    /// section needs at least one folder for it…". Sized against
    /// <see cref="SpecialNames.LastGradedFolderBlocked"/>, the longest
    /// sentence there is — a test names it, so a future longer one fails
    /// rather than quietly becoming the case nobody checked.</para>
    /// </summary>
    public const double BlockedReasonFlyoutWidth = 300;

    /// <summary>
    /// The ⓘ that REPLACES the minus on a blocked row, with the flyout saying
    /// why and naming the switch to turn off first.
    ///
    /// <para>Replaced rather than disabled: a greyed-out button with no
    /// explanation is the version of this that gets reported as "the app is
    /// broken". <paramref name="onShown"/> is how the refusal reaches the
    /// activity trail — "I could not remove the folder" is a report support
    /// will receive, and the line says which rule refused.</para>
    /// </summary>
    public static Button BlockedReasonButton(string reason, string display, Action? onShown = null)
    {
        var button = new Button
        {
            Content = new FontIcon { Glyph = Glyphs.Info, FontSize = 12 },
            Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
            BorderThickness = new Thickness(0),
            MinWidth = 28,
            MinHeight = 24,
            Padding = new Thickness(0),
            VerticalAlignment = VerticalAlignment.Center,
        };
        ToolTipService.SetToolTip(button, $"Why “{display}” cannot be removed");
        AutomationProperties.SetAutomationId(button, "blockedReason:" + display);
        AutomationProperties.SetName(button, $"Why {display} cannot be removed");

        var text = new TextBlock
        {
            Text = reason,
            TextWrapping = TextWrapping.Wrap,
            Width = BlockedReasonFlyoutWidth,
        };
        AutomationProperties.SetAutomationId(text, "blockedReasonText");
        var flyout = new Flyout { Content = text };
        button.Flyout = flyout;
        if (onShown is not null) flyout.Opened += (_, _) => onShown();
        return button;
    }

    /// <summary>
    /// The confirmation a consequential removal asks first; true means go
    /// ahead.
    ///
    /// <para>The DEFAULT button is Cancel. Enter on a dialog that appeared
    /// under the pointer must not delete a folder.</para>
    /// </summary>
    public static async Task<bool> ConfirmRemoval(XamlRoot? root, string title, string message)
    {
        if (root is null) return false;
        var dialog = new ContentDialog
        {
            Title = title,
            Content = new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap },
            PrimaryButtonText = "Remove",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Close,
            XamlRoot = root,
        };
        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }

    /// <summary>
    /// A folder/file list editor: rows with remove buttons and an add field
    /// whose + is always enabled (empty input is simply ignored). ".md" is
    /// never shown, always stored; "Media" is reserved for the toolchain.
    ///
    /// <para><paramref name="onRemoved"/> and <paramref name="onAdded"/> are
    /// how Course Settings records an exclusion and its undoing. They fire
    /// AFTER the list has changed, with the stored name (extension included),
    /// and only when something really moved — the wizard passes neither,
    /// because a course that does not exist yet has nothing to exclude
    /// from.</para>
    ///
    /// <para><paramref name="protectionFor"/> says what happens when the
    /// teacher presses minus on a given row: nothing special, ask first, or
    /// refuse with an explanation. <b>It is not optional in spirit.</b> An
    /// editor wired to <paramref name="onRemoved"/> and given no protection
    /// makes every removal permanent — the name goes into
    /// <c>excluded_items</c>, which the build treats as authoritative — so
    /// removing "All Classes" would quietly stop the next-class button and the
    /// schedule publishing anything.</para>
    /// </summary>
    public static StackPanel StringListEditor(string title, bool hidesMarkdownExtension,
                                              Func<List<string>> get, Action<List<string>> set,
                                              Action changed,
                                              Action<string>? onRemoved = null,
                                              Action<string>? onAdded = null,
                                              Func<string, ItemProtection>? protectionFor = null,
                                              Action<string, string>? onRemovalBlocked = null)
    {
        var panel = new StackPanel { Spacing = 6, Margin = new Thickness(0, 8, 0, 0) };
        panel.Children.Add(new TextBlock { Text = title, FontWeight = FontWeights.SemiBold, FontSize = 13 });
        var rows = new StackPanel { Spacing = 2 };
        panel.Children.Add(rows);

        void Rebuild()
        {
            rows.Children.Clear();
            var items = get();
            if (items.Count == 0)
                rows.Children.Add(new TextBlock { Text = "None", Opacity = 0.7, FontSize = 12 });
            foreach (string item in items)
            {
                var row = new Grid { ColumnSpacing = 8 };
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                string display = hidesMarkdownExtension && item.EndsWith(".md", StringComparison.Ordinal)
                    ? item[..^3] : item;
                row.Children.Add(new TextBlock { Text = display, VerticalAlignment = VerticalAlignment.Center });

                // Captured only to decide what this row LOOKS like. Never to
                // decide whether the removal may go ahead -- see DoRemove.
                var protection = protectionFor?.Invoke(item) ?? ItemProtection.Ordinary;

                void DoRemove()
                {
                    // Asked AGAIN, at the moment of the click. A row is drawn
                    // once and can be clicked much later, and the answer moves
                    // underneath it: removing a graded folder from one list
                    // changes whether the last one in ANOTHER list may go. That
                    // editor was not redrawn, so its captured answer is stale,
                    // and acting on it would empty the marks pool while the
                    // coverage map is on -- exactly the state the floor exists
                    // to forbid. The redraw is the cosmetics; this is the guard.
                    var now = protectionFor?.Invoke(item) ?? ItemProtection.Ordinary;
                    if (now.IsBlocked)
                    {
                        onRemovalBlocked?.Invoke(item, now.Reason);
                        Rebuild();
                        return;
                    }

                    var updated = get();
                    if (!updated.Remove(item)) return;
                    set(updated);
                    onRemoved?.Invoke(item);
                    changed();
                    Rebuild();
                }

                FrameworkElement trailing;
                if (protection.IsBlocked)
                {
                    trailing = BlockedReasonButton(protection.Reason, display,
                        () => onRemovalBlocked?.Invoke(item, protection.Reason));
                }
                else
                {
                    var remove = new Button
                    {
                        Content = new FontIcon { Glyph = Glyphs.Remove, FontSize = 12 },
                        Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
                        BorderThickness = new Thickness(0),
                        MinWidth = 28,
                        MinHeight = 24,
                        Padding = new Thickness(0),
                        VerticalAlignment = VerticalAlignment.Center,   // align with the row's label
                    };
                    ToolTipService.SetToolTip(remove, $"Remove {display}");
                    AutomationProperties.SetAutomationId(remove, "remove:" + display);
                    if (protection.AsksFirst)
                    {
                        remove.Click += async (_, _) =>
                        {
                            if (await ConfirmRemoval(panel.XamlRoot, protection.Title, protection.Message))
                                DoRemove();
                        };
                    }
                    else
                    {
                        remove.Click += (_, _) => DoRemove();
                    }
                    trailing = remove;
                }

                Grid.SetColumn(trailing, 1);
                row.Children.Add(trailing);
                rows.Children.Add(row);
            }
        }
        Rebuild();

        var addRow = new Grid { ColumnSpacing = 8, Margin = new Thickness(0, 4, 0, 0) };
        addRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        addRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var field = new TextBox
        {
            PlaceholderText = hidesMarkdownExtension ? "Type new file name here" : "Type new folder name here",
        };
        var addButton = new Button
        {
            Content = new FontIcon { Glyph = Glyphs.Add, FontSize = 12 },
            MinWidth = 28,
            MinHeight = 24,
            Padding = new Thickness(0),
        };
        ToolTipService.SetToolTip(addButton, hidesMarkdownExtension ? "Add new file…" : "Add new folder…");

        void Add()
        {
            string name = field.Text.Trim();
            field.Text = "";
            if (name.Length == 0) return;
            // Case-INSENSITIVE, because the filesystem is: "media" typed here
            // was accepted and then collided with the folder Plantoir links in.
            if (string.Equals(name, "Media", StringComparison.OrdinalIgnoreCase)) return;
            if (hidesMarkdownExtension && !name.EndsWith(".md", StringComparison.Ordinal)) name += ".md";
            var items = get();
            if (items.Contains(name)) return;
            items.Add(name);
            set(items);
            onAdded?.Invoke(name);
            changed();
            Rebuild();
        }
        addButton.Click += (_, _) => Add();
        field.KeyDown += (_, args) =>
        {
            if (args.Key == Windows.System.VirtualKey.Enter) { Add(); args.Handled = true; }
        };
        addRow.Children.Add(field);
        Grid.SetColumn(addButton, 1);
        addRow.Children.Add(addButton);
        panel.Children.Add(addRow);
        return panel;
    }

    /// <summary>
    /// Membership toggles over the sidebar items. Legacy members that no
    /// longer exist are preserved untouched — never "cleaned" on save.
    ///
    /// <para><paramref name="protectionFor"/> guards an UNTICK the same way
    /// the list editor guards a removal. A blocked box puts itself back and an
    /// ⓘ beside it says why: the Marks list is where the last graded folder
    /// would otherwise be un-ticked into an empty pool, which shows every
    /// expectation as never evaluated and reads as a bug in the coverage map
    /// rather than a choice the teacher made.</para>
    /// </summary>
    public static StackPanel MembershipToggleList(string title, IReadOnlyList<string> allItems,
                                                  Func<List<string>> get, Action<List<string>> set,
                                                  Action changed,
                                                  Func<string, ItemProtection>? protectionFor = null,
                                                  Action<string, string>? onRemovalBlocked = null)
    {
        var panel = new StackPanel { Spacing = 4, Margin = new Thickness(0, 8, 0, 0) };
        panel.Children.Add(new TextBlock { Text = title, FontWeight = FontWeights.SemiBold, FontSize = 13 });
        if (allItems.Count == 0)
        {
            panel.Children.Add(new TextBlock { Text = "No folders or files defined yet.", Opacity = 0.7, FontSize = 12 });
            return panel;
        }
        var members = get();
        foreach (string item in allItems)
        {
            string display = item.EndsWith(".md", StringComparison.Ordinal) ? item[..^3] : item;
            var check = new CheckBox { Content = display, IsChecked = members.Contains(item), MinHeight = 30 };
            AutomationProperties.SetAutomationId(check, "member:" + display);

            var row = new Grid { ColumnSpacing = 4 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.Children.Add(check);

            // Re-read on every interaction rather than closing over the value:
            // ticking a SECOND folder is exactly what un-blocks the first, and a
            // captured answer would still refuse.
            Button? reasonButton = null;
            void RefreshReason()
            {
                var protection = protectionFor?.Invoke(item) ?? ItemProtection.Ordinary;
                bool wanted = protection.IsBlocked && check.IsChecked == true;
                if (wanted && reasonButton is null)
                {
                    reasonButton = BlockedReasonButton(protection.Reason, display,
                        () => onRemovalBlocked?.Invoke(item, protection.Reason));
                    Grid.SetColumn(reasonButton, 1);
                    row.Children.Add(reasonButton);
                }
                else if (!wanted && reasonButton is not null)
                {
                    row.Children.Remove(reasonButton);
                    reasonButton = null;
                }
            }

            // Putting a refused tick back re-enters Checked. Without this
            // guard a REFUSED action would write the config and mark the form
            // dirty -- and on a course whose marks pool had never been set, it
            // would materialise one -- so the teacher's screen changes because
            // they were told no. It would also queue a rebuild that destroys
            // the very flyout meant to explain the refusal.
            bool puttingItBack = false;

            check.Checked += (_, _) =>
            {
                if (puttingItBack) return;
                var updated = get();
                if (!updated.Contains(item)) updated.Add(item);
                set(updated);
                changed();
                RefreshReason();
            };
            check.Unchecked += (_, _) =>
            {
                var protection = protectionFor?.Invoke(item) ?? ItemProtection.Ordinary;
                if (protection.IsBlocked)
                {
                    puttingItBack = true;
                    check.IsChecked = true;
                    puttingItBack = false;
                    onRemovalBlocked?.Invoke(item, protection.Reason);
                    // The button exists already -- RefreshReason put it there
                    // when the row was drawn, because the row was already
                    // blocked -- so showing its flyout is what explains the
                    // refusal without anything being rebuilt.
                    if (reasonButton is not null) reasonButton.Flyout?.ShowAt(reasonButton);
                    return;
                }
                var updated = get();
                updated.Remove(item);
                set(updated);
                changed();
                RefreshReason();
            };

            RefreshReason();
            panel.Children.Add(row);
        }
        return panel;
    }

    /// <summary>Preset menu + one-emoji field + a hint at the system panel (Win+.).</summary>
    public static StackPanel EmojiChoiceField(string label, Func<string> get, Action<string> set, Action changed)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        var field = new TextBox
        {
            Text = get(),
            Width = 52,
            TextAlignment = TextAlignment.Center,
            MaxLength = 8,   // ZWJ sequences are long in UTF-16
        };
        var presets = new DropDownButton { Content = "Presets" };
        var flyout = new MenuFlyout();
        foreach (string emoji in EmojiCatalog.Presets)
        {
            var item = new MenuFlyoutItem { Text = emoji };
            item.Click += (_, _) =>
            {
                field.Text = emoji;
                set(emoji);
                changed();
            };
            flyout.Items.Add(item);
        }
        presets.Flyout = flyout;

        field.LostFocus += (_, _) =>
        {
            string entry = field.Text.Trim();
            // Settle on one emoji: an empty field restores the current
            // choice; anything with content keeps its first emoji cluster.
            if (entry.Length == 0) { field.Text = get(); return; }
            var info = new System.Globalization.StringInfo(entry);
            string first = info.LengthInTextElements > 0 ? info.SubstringByTextElements(0, 1) : get();
            if (first != get()) { set(first); changed(); }
            field.Text = first;
        };

        row.Children.Add(presets);
        row.Children.Add(field);
        var panel = LabeledRow(label, row);
        panel.Children.Add(ExampleCaption("Press Win+. for the full emoji panel."));
        return panel;
    }

    // ---- Live previews (shared by the wizard and Course Settings) --------

    /// <summary>
    /// A live sample in the actual typeface. The bundled TTFs are referenced
    /// by an ms-appx URI (path#family) — a bare filesystem path is NOT a valid
    /// FontFamily source in WinUI, so it would silently fall back to the
    /// default font and the preview would never change. For an unpackaged app,
    /// ms-appx:/// resolves next to the executable, where the Toolchain lives.
    /// "Helvetica, Arial" previews as the system sans, and any font that isn't
    /// bundled falls back to it too.
    /// </summary>
    public static FontFamily BundledFontFamily(string familyName)
    {
        if (familyName == "Helvetica, Arial") return new FontFamily("Segoe UI");
        string file = FontCatalog.FileBaseName(familyName) + ".ttf";
        string path = BundledToolchain.SupportPath("fonts/" + file);
        return System.IO.File.Exists(path)
            ? new FontFamily($"ms-appx:///Toolchain/support/fonts/{file}#{familyName}")
            : new FontFamily("Segoe UI");
    }

    /// <summary>Fill a horizontal row with a "Preview:" label and the scheme's swatches.</summary>
    public static void FillSwatchRow(StackPanel row, IEnumerable<string> swatchValues)
    {
        row.Children.Clear();
        row.Children.Add(new TextBlock { Text = "Preview:", FontSize = 12, Opacity = 0.7 });
        foreach (string value in swatchValues)
        {
            row.Children.Add(new Border
            {
                Width = 22,
                Height = 14,
                CornerRadius = new CornerRadius(3),
                BorderThickness = new Thickness(1),
                BorderBrush = (Brush)Application.Current.Resources["ControlStrokeColorDefaultBrush"],
                Background = new SolidColorBrush(ColorFromCss(value)),
            });
        }
    }

    /// <summary>Parse a Quartz scheme colour — #rgb, #rrggbb, or rgba(...) — degrading to mid-grey.</summary>
    public static Windows.UI.Color ColorFromCss(string value)
    {
        try
        {
            string v = value.Trim();
            if (v.StartsWith("rgba(", StringComparison.Ordinal))
            {
                var parts = v[5..].TrimEnd(')').Split(',');
                return Windows.UI.Color.FromArgb(
                    (byte)(double.Parse(parts[3], System.Globalization.CultureInfo.InvariantCulture) * 255),
                    byte.Parse(parts[0]), byte.Parse(parts[1]), byte.Parse(parts[2]));
            }
            if (v.StartsWith('#')) v = v[1..];
            if (v.Length == 3) v = string.Concat(v.Select(c => $"{c}{c}"));
            byte r = Convert.ToByte(v[..2], 16);
            byte g = Convert.ToByte(v[2..4], 16);
            byte b = Convert.ToByte(v[4..6], 16);
            return Windows.UI.Color.FromArgb(255, r, g, b);
        }
        catch
        {
            return Windows.UI.Color.FromArgb(255, 128, 128, 128);   // mid-grey, like the terminal picker
        }
    }
}

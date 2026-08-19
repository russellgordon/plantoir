using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;

namespace Plantoir.Views;

/// <summary>
/// "When does this class meet?" — entered once per section.
///
/// Supports three routes:
/// 1. Type or paste (column of dates or comma-separated dates)
/// 2. A file (.csv, .ics, .txt, .xlsx)
/// 3. A Google Sheet (shared link)
///
/// Parses dates safely via SectionScheduleSource and saves to TimetableMemory.
/// </summary>
public sealed class SectionScheduleDialog : ContentDialog
{
    public IReadOnlyList<DateOnly>? SavedDates { get; private set; }
    public string? SavedSource { get; private set; }

    private readonly string _workspacePath;
    private readonly Course _course;
    private readonly int _sectionNumber;

    private readonly RadioButtons _routePicker = new();
    private readonly StackPanel _typedPanel = new() { Spacing = 6 };
    private readonly StackPanel _filePanel = new() { Spacing = 6 };
    private readonly StackPanel _sheetPanel = new() { Spacing = 6 };

    private readonly TextBox _typedBox = new()
    {
        AcceptsReturn = true,
        TextWrapping = TextWrapping.Wrap,
        MinHeight = 120,
        MaxHeight = 200,
        FontFamily = new FontFamily("Consolas, Courier New, monospace"),
        PlaceholderText = "2026-09-08\n2026-09-10\n2026-09-14…",
    };

    private string? _pickedFilePath;
    private readonly TextBlock _chosenFileLabel = new()
    {
        Text = "No file chosen",
        FontSize = 13,
        VerticalAlignment = VerticalAlignment.Center,
        TextTrimming = TextTrimming.CharacterEllipsis,
    };

    private readonly TextBox _sheetUrlBox = new()
    {
        PlaceholderText = "https://docs.google.com/spreadsheets/d/…/edit",
    };

    private readonly TextBox _sourceBox = new()
    {
        PlaceholderText = "e.g. timetable.xlsx, block H, or pasted by hand",
        Text = "pasted by hand",
    };

    private readonly StackPanel _orderingPanel = new() { Spacing = 8, Visibility = Visibility.Collapsed };
    private readonly TextBlock _orderingPrompt = new() { FontSize = 13, TextWrapping = TextWrapping.Wrap };
    private readonly Button _dayFirstBtn = new() { Content = "Day first" };
    private readonly Button _monthFirstBtn = new() { Content = "Month first" };
    private OrderingQuestion? _pendingQuestion;

    private readonly TextBlock _statusBlock = new()
    {
        FontSize = 13,
        TextWrapping = TextWrapping.Wrap,
        MinHeight = 24,
    };

    private IReadOnlyList<DateOnly>? _parsedDates;
    private ColumnOrdering? _chosenOrdering;

    private readonly IntPtr _hwnd;

    public SectionScheduleDialog(string workspacePath, Course course, int sectionNumber, IntPtr hwnd = default, string reason = "")
    {
        _workspacePath = workspacePath;
        _course = course;
        _sectionNumber = sectionNumber;
        _hwnd = hwnd;

        Title = $"When does {course.Code} Section {sectionNumber} meet?";
        PrimaryButtonText = "Remember these dates";
        SecondaryButtonText = "Check Dates";
        CloseButtonText = "Cancel";
        DefaultButton = ContentDialogButton.Primary;

        PrimaryButtonClick += OnPrimaryButtonClick;
        SecondaryButtonClick += OnSecondaryButtonClick;

        BuildContent(reason);
    }

    private void BuildContent(string reason)
    {
        var main = new StackPanel { Spacing = 14, MinWidth = 460, MaxWidth = 560 };

        var intro = new TextBlock
        {
            Text = "Give Plantoir the class dates once, so it can date new class pages for you. " +
                   "They are kept inside the course folder, so they travel with it through backup, archive and restore.",
            FontSize = 13,
            Opacity = 0.8,
            TextWrapping = TextWrapping.Wrap,
        };
        main.Children.Add(intro);

        if (!string.IsNullOrWhiteSpace(reason))
        {
            var reasonBlock = new TextBlock
            {
                Text = reason,
                FontSize = 12,
                Opacity = 0.7,
                TextWrapping = TextWrapping.Wrap,
            };
            main.Children.Add(reasonBlock);
        }

        // Route Picker
        _routePicker.ItemsSource = new[] { "Type or paste", "A file", "A Google Sheet" };
        _routePicker.SelectedIndex = 0;
        _routePicker.SelectionChanged += (_, _) => OnRouteChanged();
        _routePicker.MaxColumns = 3;
        main.Children.Add(_routePicker);

        // 1. Type / Paste Panel
        _typedPanel.Children.Add(new TextBlock
        {
            Text = "One date per line. A heading row and blank lines are fine.",
            FontSize = 12,
            Opacity = 0.7,
        });
        _typedPanel.Children.Add(_typedBox);
        _typedBox.TextChanged += (_, _) => ResetParsed();
        main.Children.Add(_typedPanel);

        // 2. File Panel
        _filePanel.Children.Add(new TextBlock
        {
            Text = "A .csv, .txt, or .xlsx file with one column of dates, or a .ics calendar export.",
            FontSize = 12,
            Opacity = 0.7,
        });
        var chooseFileRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        var chooseBtn = new Button { Content = "Choose a file…" };
        chooseBtn.Click += OnChooseFileClicked;
        chooseFileRow.Children.Add(chooseBtn);
        chooseFileRow.Children.Add(_chosenFileLabel);
        _filePanel.Children.Add(chooseFileRow);
        _filePanel.Visibility = Visibility.Collapsed;
        main.Children.Add(_filePanel);

        // 3. Google Sheet Panel
        _sheetPanel.Children.Add(new TextBlock
        {
            Text = "Paste the sheet’s address, straight out of your browser’s address bar.",
            FontSize = 12,
            Opacity = 0.7,
        });
        _sheetPanel.Children.Add(_sheetUrlBox);
        _sheetUrlBox.TextChanged += (_, _) => ResetParsed();
        _sheetPanel.Children.Add(new TextBlock
        {
            Text = "Reading a Google Sheet sends the link to Google over the internet. It is the only thing Plantoir’s assistant does that leaves this PC — the other two ways above stay here.",
            FontSize = 12,
            Opacity = 0.7,
            TextWrapping = TextWrapping.Wrap,
        });
        _sheetPanel.Children.Add(new TextBlock
        {
            Text = "The sheet has to be shared: in the sheet, Share ▸ General access ▸ “Anyone with the link”.",
            FontSize = 11,
            Opacity = 0.6,
            TextWrapping = TextWrapping.Wrap,
        });
        _sheetPanel.Visibility = Visibility.Collapsed;
        main.Children.Add(_sheetPanel);

        // Source Field
        var sourceLabel = new TextBlock
        {
            Text = "Where these came from (for your notes):",
            FontSize = 12,
            Opacity = 0.8,
        };
        main.Children.Add(sourceLabel);
        main.Children.Add(_sourceBox);

        // Ordering Question
        _orderingPanel.Children.Add(_orderingPrompt);
        var orderingButtons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        _dayFirstBtn.Click += (_, _) => AnswerOrdering(ColumnOrdering.DayThenMonth);
        _monthFirstBtn.Click += (_, _) => AnswerOrdering(ColumnOrdering.MonthThenDay);
        orderingButtons.Children.Add(_dayFirstBtn);
        orderingButtons.Children.Add(_monthFirstBtn);
        _orderingPanel.Children.Add(orderingButtons);
        main.Children.Add(_orderingPanel);

        // Status / Feedback
        main.Children.Add(_statusBlock);

        Content = main;
    }

    private void OnRouteChanged()
    {
        int index = _routePicker.SelectedIndex;
        _typedPanel.Visibility = index == 0 ? Visibility.Visible : Visibility.Collapsed;
        _filePanel.Visibility = index == 1 ? Visibility.Visible : Visibility.Collapsed;
        _sheetPanel.Visibility = index == 2 ? Visibility.Visible : Visibility.Collapsed;

        if (index == 0 && string.IsNullOrWhiteSpace(_sourceBox.Text))
            _sourceBox.Text = "pasted by hand";
        else if (index == 1 && !string.IsNullOrWhiteSpace(_pickedFilePath))
            _sourceBox.Text = Path.GetFileName(_pickedFilePath);
        else if (index == 2 && string.IsNullOrWhiteSpace(_sourceBox.Text))
            _sourceBox.Text = "Google Sheet";

        ResetParsed();
    }

    private void ResetParsed()
    {
        _parsedDates = null;
        _pendingQuestion = null;
        _chosenOrdering = null;
        _orderingPanel.Visibility = Visibility.Collapsed;
        _statusBlock.Text = "";
    }

    private async void OnChooseFileClicked(object sender, RoutedEventArgs e)
    {
        var picker = new Windows.Storage.Pickers.FileOpenPicker();
        if (_hwnd != IntPtr.Zero)
        {
            WinRT.Interop.InitializeWithWindow.Initialize(picker, _hwnd);
        }
        picker.FileTypeFilter.Add(".csv");
        picker.FileTypeFilter.Add(".ics");
        picker.FileTypeFilter.Add(".txt");
        picker.FileTypeFilter.Add(".xlsx");
        picker.FileTypeFilter.Add("*");

        var file = await picker.PickSingleFileAsync();
        if (file is not null)
        {
            _pickedFilePath = file.Path;
            _chosenFileLabel.Text = file.Name;
            _sourceBox.Text = file.Name;
            ResetParsed();
        }
    }

    private async void OnSecondaryButtonClick(ContentDialog sender, ContentDialogButtonClickEventArgs args)
    {
        var deferral = args.GetDeferral();
        try
        {
            args.Cancel = true; // keep dialog open
            await ReadDatesAsync();
        }
        finally
        {
            deferral.Complete();
        }
    }

    private async void OnPrimaryButtonClick(ContentDialog sender, ContentDialogButtonClickEventArgs args)
    {
        var deferral = args.GetDeferral();
        try
        {
            if (_parsedDates is null || _parsedDates.Count == 0)
            {
                bool ok = await ReadDatesAsync();
                if (!ok || _parsedDates is null || _parsedDates.Count == 0)
                {
                    args.Cancel = true;
                    return;
                }
            }

            string source = string.IsNullOrWhiteSpace(_sourceBox.Text) ? "the teacher" : _sourceBox.Text.Trim();
            var today = DateOnly.FromDateTime(DateTime.Now);

            bool wrote = TimetableMemory.Write(_workspacePath, _course.Code, _sectionNumber, _parsedDates, source, today);
            if (wrote)
            {
                SavedDates = _parsedDates;
                SavedSource = source;
            }
            else
            {
                _statusBlock.Text = "Could not save timetable to disk.";
                _statusBlock.Foreground = (Brush)Application.Current.Resources["SystemFillColorCautionBrush"];
                args.Cancel = true;
            }
        }
        finally
        {
            deferral.Complete();
        }
    }

    private async Task<bool> ReadDatesAsync()
    {
        _statusBlock.Text = "";
        _orderingPanel.Visibility = Visibility.Collapsed;
        _pendingQuestion = null;

        try
        {
            int route = _routePicker.SelectedIndex;
            ScheduleOutcome outcome;

            if (route == 0)
            {
                string text = _typedBox.Text.Trim();
                if (string.IsNullOrEmpty(text))
                {
                    _statusBlock.Text = "Please type or paste some dates first.";
                    _statusBlock.Foreground = (Brush)Application.Current.Resources["SystemFillColorCautionBrush"];
                    return false;
                }
                outcome = SectionScheduleSource.ReadTypedText(text, _chosenOrdering);
            }
            else if (route == 1)
            {
                if (string.IsNullOrEmpty(_pickedFilePath) || !File.Exists(_pickedFilePath))
                {
                    _statusBlock.Text = "Please choose a file first.";
                    _statusBlock.Foreground = (Brush)Application.Current.Resources["SystemFillColorCautionBrush"];
                    return false;
                }
                outcome = SectionScheduleSource.ReadFromFile(_pickedFilePath, _chosenOrdering);
            }
            else
            {
                string url = _sheetUrlBox.Text.Trim();
                if (string.IsNullOrEmpty(url))
                {
                    _statusBlock.Text = "Please enter a Google Sheet address.";
                    _statusBlock.Foreground = (Brush)Application.Current.Resources["SystemFillColorCautionBrush"];
                    return false;
                }

                var csvUri = SectionScheduleSource.CsvUrlForGoogleSheetLink(url);
                using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };
                string csv = await http.GetStringAsync(csvUri);
                var lines = csv.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None);
                outcome = SectionScheduleSource.Read(lines, "Google Sheet", "Google Sheet", _chosenOrdering);
            }

            if (outcome is ScheduleOutcome.Question q)
            {
                _pendingQuestion = q.OrderingQuestion;
                _orderingPrompt.Text = q.OrderingQuestion.Prompt;
                _dayFirstBtn.Content = $"Day first ({q.OrderingQuestion.DayFirstShort})";
                _monthFirstBtn.Content = $"Month first ({q.OrderingQuestion.MonthFirstShort})";
                _orderingPanel.Visibility = Visibility.Visible;
                return false;
            }

            if (outcome is ScheduleOutcome.Dates d)
            {
                _parsedDates = d.Reading.Dates;
                if (_parsedDates.Count == 0)
                {
                    _statusBlock.Text = "No dates were found in that input.";
                    _statusBlock.Foreground = (Brush)Application.Current.Resources["SystemFillColorCautionBrush"];
                    return false;
                }

                _statusBlock.Text = $"Found {_parsedDates.Count} class {(_parsedDates.Count == 1 ? "date" : "dates")} ({_parsedDates[0]:yyyy-MM-dd} to {_parsedDates[^1]:yyyy-MM-dd}).";
                _statusBlock.Foreground = (Brush)Application.Current.Resources["TextFillColorPrimaryBrush"];
                return true;
            }

            return false;
        }
        catch (AssistRefusal refusal)
        {
            _statusBlock.Text = refusal.Message;
            _statusBlock.Foreground = (Brush)Application.Current.Resources["SystemFillColorCautionBrush"];
            return false;
        }
        catch (Exception ex)
        {
            _statusBlock.Text = $"Could not read dates: {ex.Message}";
            _statusBlock.Foreground = (Brush)Application.Current.Resources["SystemFillColorCautionBrush"];
            return false;
        }
    }

    private async void AnswerOrdering(ColumnOrdering ordering)
    {
        _chosenOrdering = ordering;
        _orderingPanel.Visibility = Visibility.Collapsed;
        await ReadDatesAsync();
    }
}

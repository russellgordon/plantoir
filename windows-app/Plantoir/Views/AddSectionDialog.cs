using System;
using System.Linq;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Plantoir.Core.Models;

namespace Plantoir.Views;

/// <summary>
/// "Add a Section to CODE": a native NumberBox with an inline +/− spinner,
/// live orange validation in a reserved slot (the sheet never jumps), and
/// an Add button enabled only when the entry names an addable section.
/// A failed add keeps the dialog open — the whole point is a chance to
/// correct and try again.
/// </summary>
public sealed class AddSectionDialog : ContentDialog
{
    public int? AddedNumber { get; private set; }

    private readonly Course _course;
    private readonly NumberBox _numberBox = new()
    {
        Width = 140,
        Minimum = 1,
        SmallChange = 1,
        SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Inline,
        ValidationMode = NumberBoxValidationMode.InvalidInputOverwritten,
    };
    private readonly TextBlock _warningSlot = new()
    {
        FontSize = 12,
        TextWrapping = TextWrapping.Wrap,
        MinHeight = 26,
    };

    public AddSectionDialog(Course course)
    {
        _course = course;
        Title = $"Add a Section to {course.Code}";
        PrimaryButtonText = "Add Section";
        CloseButtonText = "Cancel";
        DefaultButton = ContentDialogButton.Primary;
        PrimaryButtonClick += OnAdd;

        var existing = course.SectionNumbers;
        string existingSentence = existing.Count switch
        {
            0 => $"{course.Code} has no sections yet.",
            1 => $"{course.Code} already has section {existing[0]}.",
            _ => $"{course.Code} already has sections {JoinWithAnd(existing)}.",
        };

        _numberBox.Value = SectionAdder.SuggestedNumber(existing);
        _numberBox.ValueChanged += (_, _) => RefreshValidation();

        var numberRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        numberRow.Children.Add(new TextBlock { Text = "Section number:", VerticalAlignment = VerticalAlignment.Center });
        numberRow.Children.Add(_numberBox);

        var panel = new StackPanel { Spacing = 12, MinWidth = 300 };
        panel.Children.Add(FormBuilders.DialogExplanation(existingSentence));
        panel.Children.Add(numberRow);
        panel.Children.Add(_warningSlot);
        Content = panel;
        RefreshValidation();
    }

    /// <summary>NaN (empty box) reads as 0, which the validator rejects with a clear message.</summary>
    private int CurrentValue => double.IsNaN(_numberBox.Value) ? 0 : (int)_numberBox.Value;

    private void RefreshValidation()
    {
        var existing = _course.SectionNumbers;
        string entry = CurrentValue.ToString();
        string? problem = SectionAdder.EntryProblem(entry, existing, _course.Code);
        _warningSlot.Text = problem ?? " ";
        _warningSlot.Foreground = (Brush)Application.Current.Resources["SystemFillColorCautionBrush"];
        DialogButtons.EnablePrimary(this, SectionAdder.EntryIsAddable(entry, existing));
    }

    private void OnAdd(ContentDialog sender, ContentDialogButtonClickEventArgs args)
    {
        int number = CurrentValue;
        if (number < 1) { args.Cancel = true; return; }
        try
        {
            SectionAdder.AddSection(number, _course);
            AddedNumber = number;
        }
        catch (SectionAdder.SectionAddException error)
        {
            _warningSlot.Text = error.Message;
            args.Cancel = true;   // stay open: a chance to correct
        }
    }

    private static string JoinWithAnd(System.Collections.Generic.IReadOnlyList<int> numbers)
    {
        if (numbers.Count == 1) return numbers[0].ToString();
        return string.Join(", ", numbers.Take(numbers.Count - 1)) + " and " + numbers[^1];
    }
}

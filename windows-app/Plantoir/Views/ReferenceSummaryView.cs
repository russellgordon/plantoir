using System;
using System.Linq;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Plantoir.Core.Models;

namespace Plantoir.Views;

/// <summary>
/// What a reference course's row opens INSTEAD of the Course Settings form
/// (#241, <c>referenceCourses.interface.theReadOnlySummary</c>): the code a
/// teacher reads and the name; the school year, with the one action a frozen
/// course still offers; the sections; the FOLDER name, the one place a folder
/// name is the fact; and the calm sentences. No fields, no Save, and no
/// control that can never become available. The form asked a never-deployed
/// course to choose a deploy folder and let every other setting be saved —
/// including the deploying settings whose emptiness is what makes an older
/// Plantoir refuse it.
/// </summary>
public sealed class ReferenceSummaryView : UserControl
{
    public string CourseCode { get; }

    public ReferenceSummaryView(MainWindow window, Course course)
    {
        CourseCode = course.Code;
        string shown = ReferenceCourse.ShownCode(course);
        int? year = SchoolYear.Read(course.Configuration.StoredReferenceSchoolYear, DateOnly.FromDateTime(DateTime.Now));
        var setYear = new Button { Content = ReferenceCourse.SetSchoolYearMenuItem };
        setYear.SetValue(Microsoft.UI.Xaml.Automation.AutomationProperties.AutomationIdProperty, "referenceSetSchoolYear");
        setYear.Click += (_, _) => _ = window.SidebarPane.SetSchoolYear(course);

        TextBlock Line(string text, double opacity = 1) =>
            new() { Text = text, TextWrapping = TextWrapping.Wrap, Opacity = opacity };

        var panel = new StackPanel { Spacing = 12, Padding = new Thickness(24), MaxWidth = 640, HorizontalAlignment = HorizontalAlignment.Left };
        panel.Children.Add(new TextBlock { Text = shown, Style = (Style)Application.Current.Resources["TitleTextBlockStyle"] });
        if (course.Configuration.CourseName.Length > 0) panel.Children.Add(Line(course.Configuration.CourseName));
        panel.Children.Add(new StackPanel
        {
            Orientation = Orientation.Horizontal, Spacing = 12,
            Children = { Line("School year: " + SchoolYear.Name(year, SchoolYear.OtherGroupName)), setYear },
        });
        panel.Children.Add(Line(course.SectionNumbers.Count == 1
            ? "Section " + course.SectionNumbers[0]
            : "Sections " + string.Join(", ", course.SectionNumbers)));
        panel.Children.Add(Line("Folder: " + course.Code, 0.75));
        panel.Children.Add(Line(ReferenceCourse.NeverDeployed(shown)));
        panel.Children.Add(Line(ReferenceCourse.PagesAreLocked));
        // On the ScrollViewer, not on this UserControl: a UserControl has no
        // automation peer, so an id set on it never reaches UI Automation and
        // "referenceSummary" could not be found (measured, bundle 11).
        var scroller = new ScrollViewer { Content = panel };
        scroller.SetValue(Microsoft.UI.Xaml.Automation.AutomationProperties.AutomationIdProperty, "referenceSummary");
        Content = scroller;
    }
}

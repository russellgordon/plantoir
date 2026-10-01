using Newtonsoft.Json.Linq;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// What a reference course's interface WITHHOLDS (#241,
/// <c>referenceCourses.interface.whatIsWithheld</c>), asserted on the code
/// paths behind the buttons as well as the buttons: a withheld button with a
/// live code path is a door left open for the next caller.
/// </summary>
public class ReferenceInterfaceTests
{
    private static string Source(params string[] path) =>
        File.ReadAllText(Path.Combine(new[] { ContractLoader.RepositoryRoot, "windows-app" }.Concat(path).ToArray()));

    private static string Between(string text, string start, string end)
    {
        int from = text.IndexOf(start, StringComparison.Ordinal);
        Assert.True(from >= 0, start);
        int to = text.IndexOf(end, from + start.Length, StringComparison.Ordinal);
        // Comments say what is withheld; only code is asserted on.
        return string.Join(Environment.NewLine, text[from..(to < 0 ? text.Length : to)].Split(Environment.NewLine[^1])
            .Where(line => !line.TrimStart().StartsWith("//", StringComparison.Ordinal)));
    }

    [Fact]
    public void TheReferenceMenusOfferNothingThatChangesTheCourse()
    {
        string sidebar = Source("Plantoir", "Views", "SidebarPane.Reference.cs");
        string courseMenu = Between(sidebar, "private MenuFlyout ReferenceCourseMenu(", "private MenuFlyout ReferenceSectionMenu(");
        string sectionMenu = Between(sidebar, "private MenuFlyout ReferenceSectionMenu(", "private MenuFlyoutItem ReferenceObsidianItem(");
        foreach (string withheld in new[] { "Rename", "Add Section", "KeepACopyMenuItem", "Revise", "Schedule Deploy", "Restore Section" })
        {
            Assert.DoesNotContain(withheld, courseMenu);
            Assert.DoesNotContain(withheld, sectionMenu);
        }
        Assert.Contains("Cancel Scheduled Deploy", sectionMenu);   // gate by direction
        Assert.Contains("SetSchoolYearMenuItem", courseMenu);
    }

    [Fact]
    public void SiteHealthRepairsNothingOnAReferenceCourse()
    {
        var course = new Course("ICS3U-2025", Path.GetTempPath(),
            CourseConfiguration.FromDictionary(JObject.Parse("""{"course_code":"ICS3U","kept_for_reference":true}""")));
        var findings = new[] { new SiteHealthFinding("mediaFolderMissing", "The Media folder is not there.", "", true, "ICS3U-2025", 1) };
        Assert.Null(SiteHealthRepair.OutcomeOfRepairing(findings, course));
        Assert.Contains("repairIsOffered: !ReferenceCourse.IsKeptForReference(_course)",
            Source("Plantoir", "Views", "SectionDetailView.xaml.cs"));
    }

    [Fact]
    public void EveryRenameRouteAsksTheSameQuestion()
    {
        Assert.Contains("!ReferenceCourse.IsKeptForReference(course) ? course : null", Source("Plantoir", "MainWindow.xaml.cs"));
        string dialog = Between(Source("Plantoir", "Views", "SidebarPane.xaml.cs"), "public async Task OpenRenameCourseDialog(", "string? askedIn");
        Assert.Contains("ReferenceCourse.IsKeptForReference(course)", dialog);
    }

    [Fact]
    public void TheSettingsFormIsReplacedByTheSummary()
    {
        string window = Source("Plantoir", "MainWindow.xaml.cs");
        string routing = Between(window[window.IndexOf("public void ShowDetailForSelection", StringComparison.Ordinal)..],
            "case SidebarSelection.CourseItem(", "case SidebarSelection.ArchivedEntry(");
        Assert.True(routing.IndexOf("ReferenceSummaryView", StringComparison.Ordinal) < routing.IndexOf("new CourseSettingsView", StringComparison.Ordinal));
    }
}

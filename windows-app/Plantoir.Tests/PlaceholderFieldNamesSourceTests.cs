namespace Plantoir.Tests;

/// <summary>
/// #1020, the Windows half of the mac's #1012: every box that showed only a
/// placeholder has a name of its own, in the mac's words, and the placeholder
/// stays as the hint. A placeholder goes when the teacher types, so it is not a
/// name a screen reader can rely on (the mac's <c>PlaceholderFieldNamesTests</c>;
/// Apple's VoiceOver guidance: "Provide alternative labels for all key interface
/// elements"). A box cannot be built outside a WinUI window here, so this pins
/// the source; <c>PlaceholderFieldNamesUiTests</c> reads the names that UI
/// Automation gives for the boxes a test can reach without starting a task or
/// the assistant.
/// </summary>
public class PlaceholderFieldNamesSourceTests
{
    private static string View(string file) => File.ReadAllText(Path.Combine(
        ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "Views", file)).Replace("\r\n", "\n");

    /// <summary>The text from <paramref name="from"/> to the next blank line.</summary>
    private static string Paragraph(string source, string from)
    {
        int start = source.IndexOf(from, StringComparison.Ordinal);
        Assert.True(start >= 0, $"the source no longer holds: {from}");
        int end = source.IndexOf("\n\n", start, StringComparison.Ordinal);
        return end < 0 ? source[start..] : source[start..end];
    }

    [Fact]
    public void TheAssistantsBoxIsAskAboutThisSection()
    {
        string box = Paragraph(View("AssistWindow.xaml"), "<TextBox x:Name=\"Input\"");
        Assert.Contains("AutomationProperties.Name=\"Ask about this section\"", box);
    }

    [Fact]
    public void TheConsolesAnswerBoxIsYourAnswer()
    {
        string box = Paragraph(View("TaskProgressView.xaml"), "<TextBox x:Name=\"ConsoleInput\"");
        Assert.Contains("AutomationProperties.Name=\"Your answer\"", box);
    }

    [Fact]
    public void ThePlainQuestionsAnswerBoxIsYourAnswer()
    {
        string source = View("TaskProgressView.xaml.cs");
        Assert.Contains("AutomationProperties.SetName(answerBox, \"Your answer\");", source);
    }

    /// <summary>The mac names the credential field by the label printed above it ("Netlify token").</summary>
    [Fact]
    public void TheCredentialFieldIsNamedByItsPrintedLabel()
    {
        string source = View("TaskProgressView.xaml.cs");
        Assert.Contains("fieldColumn.Children.Add(new TextBlock { Text = req.FieldLabel });", source);
        Assert.Contains("AutomationProperties.SetName(inputControl, req.FieldLabel);", source);
    }

    [Fact]
    public void ClassDatesBoxesAreNamedAsTheMacs()
    {
        string source = View("SectionScheduleDialog.cs");
        Assert.Contains("public const string ClassDatesName = \"Class dates\";", source);
        Assert.Contains("public const string GoogleSheetAddressName = \"Google Sheet address\";", source);
        Assert.Contains("public const string WhereTheseCameFromName = \"Where these came from\";", source);
        Assert.Contains("AutomationProperties.SetName(_typedBox, ClassDatesName);", source);
        Assert.Contains("AutomationProperties.SetName(_sheetUrlBox, GoogleSheetAddressName);", source);
        Assert.Contains("AutomationProperties.SetName(_sourceBox, WhereTheseCameFromName);", source);
    }

    [Fact]
    public void TheSidebarsBoxesAreCourseCodeAndFilter()
    {
        Assert.Contains("AutomationProperties.SetName(codeBox, \"Course code\");", View("SidebarPane.xaml.cs"));
        string filter = Paragraph(View("SidebarPane.xaml"), "<TextBox x:Name=\"FilterBox\"");
        Assert.Contains("AutomationProperties.Name=\"Filter\"", filter);
    }

    [Fact]
    public void TheListEditorsBoxesAreNewNameAndNewFolderOrFileName()
    {
        Assert.Contains("AutomationProperties.SetName(field, hidesMarkdownExtension ? \"New file name\" : \"New folder name\");",
                        View("FormBuilders.cs"));
        Assert.Contains("AutomationProperties.SetName(field, \"New name\");", View("CourseSettingsView.xaml.cs"));
    }

    [Fact]
    public void BothFooterBoxesAreFooter()
    {
        Assert.Contains("AutomationProperties.SetName(footerBox, \"Footer\");", View("CourseSettingsView.xaml.cs"));
        Assert.Contains("AutomationProperties.SetName(footerBox, \"Footer\");", View("NewCourseDialog.cs"));
    }

    [Fact]
    public void BothDeployFolderBoxesAreFolder()
    {
        string source = View("PublishingChoiceView.cs");
        Assert.Contains("AutomationProperties.SetName(_pathBox, \"Folder\");", source);
        Assert.Contains("AutomationProperties.SetName(folderBox, \"Folder\");", source);
    }
}

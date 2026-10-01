using System.Text.RegularExpressions;

namespace Plantoir.Tests;

/// <summary>
/// #191: each of the four window-level accelerators with no ScopeOwner asks
/// <c>DialogGate.Holds</c> before doing anything, so none of them acts under
/// a modal dialog (F2 would otherwise raise a second ContentDialog that WinUI
/// refuses and the app swallows — a key that silently does nothing). A source
/// scan, because the handlers live in the WinUI project this suite cannot
/// load; <c>Plantoir.UiTests.AcceleratorUnderDialogUiTests</c> presses the key.
/// </summary>
public class AcceleratorDialogGateTests
{
    [Theory]
    [InlineData("OpenWorkingFolderAccelerator")]
    [InlineData("NewWindowAccelerator")]
    [InlineData("ReloadCoursesAccelerator")]
    [InlineData("RenameCourseAccelerator")]
    public void TheAcceleratorDoesNothingWhileADialogIsUp(string handler)
    {
        string source = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "MainWindow.xaml.cs"));
        var body = Regex.Match(source,
            $@"private void {handler}\(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args\)\s*\{{\s*(?<first>[^\r\n]*)");
        Assert.True(body.Success, $"{handler} was not found in MainWindow.xaml.cs.");
        // Holds = IsOpen, plus the test-run record that makes #191's measurement.
        Assert.Contains("DialogGate.Holds(", body.Groups["first"].Value);
    }
}

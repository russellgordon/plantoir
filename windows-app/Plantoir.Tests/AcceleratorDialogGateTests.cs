using System.Text.RegularExpressions;

namespace Plantoir.Tests;

/// <summary>
/// #191: each of the four window-level keys — on menu items since #488 — asks
/// <c>DialogGate.Holds</c> before doing anything, so none of them acts under
/// a modal dialog (F2 would otherwise raise a second ContentDialog that WinUI
/// refuses and the app swallows — a key that silently does nothing). A source
/// scan, because the items live in the WinUI project this suite cannot
/// load; <c>Plantoir.UiTests.AcceleratorUnderDialogUiTests</c> presses the key.
/// </summary>
public class AcceleratorDialogGateTests
{
    private static string Menus => File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "MainWindow.Menus.cs"));

    /// <summary>
    /// Since #488 the four keys #191 guarded are on MENU ITEMS, and every item's
    /// key and click go through <c>MainWindow.Invoke</c>, whose first act is
    /// <c>DialogGate.Holds</c> for a key (or <c>IsOpen</c> for a click).
    /// </summary>
    [Theory]
    [InlineData("Ctrl+O")]
    [InlineData("Ctrl+N")]
    [InlineData("Ctrl+Shift+R")]
    [InlineData("F2")]
    [InlineData("F1")]   // Help ▸ Plantoir Help (#491)
    public void TheKeyIsOnAMenuItemWhoseRunAsksTheDialogGateFirst(string key)
    {
        Assert.Contains($", \"{key}\")", Menus);   // Key(…, "<key>") on an Add(…) line
        var invoke = Regex.Match(Menus, @"private void Invoke\(Item\? item, Action\? run, string\? keyName\)\s*\{(?<body>.*?)if \(held\) return;", RegexOptions.Singleline);
        Assert.True(invoke.Success, "MainWindow.Invoke was not found in MainWindow.Menus.cs.");
        Assert.Contains("DialogGate.Holds(root, keyName)", invoke.Groups["body"].Value);
        Assert.Contains("window.Invoke(item, run, name);", Menus);   // every accelerator goes through it
    }

    [Fact]
    public void NoKeyIsLeftOnTheWindowsRoot()
    {
        string xaml = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "MainWindow.xaml"));
        Assert.DoesNotContain("KeyboardAccelerator ", xaml);
    }
}

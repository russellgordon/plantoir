namespace Plantoir.Tests;

/// <summary>
/// #269 (mac #266) is visual, so its behaviour is driven by
/// <c>ListTablesUiTests</c> (opt-in, unproven while the desktop was locked).
/// This pins the two rules a reviewer could "tidy" away without a window to
/// see it: a DISABLED list ignores Delete (the mac's keys were not stopped by
/// <c>.disabled</c>), and − and Delete share ONE removal path, so a blocked
/// row explains itself and records <c>removal blocked</c> either way.
/// </summary>
public class ListTablesSourceTests
{
    private static string FormBuilders() => File.ReadAllText(Path.Combine(
        ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "Views", "FormBuilders.cs"));

    [Fact]
    public void ADisabledListIgnoresDeleteAndMinus()
    {
        string source = FormBuilders();
        Assert.Contains("if (args.Key != Windows.System.VirtualKey.Delete || !list.IsEnabled) return;", source);
        Assert.Contains("if (!list.IsEnabled || Selected() is not { } item) return;", source);
    }

    [Fact]
    public void MinusAndDeleteShareOneRemovalPath()
    {
        string source = FormBuilders();
        Assert.Contains("removeButton.Click += async (_, _) => await RemoveSelected(removeButton);", source);
        Assert.Contains("await RemoveSelected(removeButton);\n        };", source.Replace("\r\n", "\n"));
        Assert.Contains("onRemovalBlocked?.Invoke(item, now.Reason);", source);
    }
}

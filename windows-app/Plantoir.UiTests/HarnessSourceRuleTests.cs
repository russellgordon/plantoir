using System.Text.RegularExpressions;

namespace Plantoir.UiTests;

/// <summary>
/// #638, pinned WITHOUT a desktop (plain facts, like
/// <see cref="AssertAbsentRuleTests"/>): no UI test sends a key DOWN with no
/// key up. FlaUI's down-only call leaves the key held at the operating-system
/// level for the rest of the run; <c>Keyboard.Type</c> sends both, and
/// <c>using (Keyboard.Pressing(...))</c> sends the up on dispose.
///
/// <para>One method is allowed it, by name: <c>PageTablesUiTests.HeldSpace</c>
/// imitates a held key's auto-repeat (several downs, then ONE up in a
/// <c>finally</c>), which neither safe form can send. The call is spelled in
/// pieces here so this file does not trip its own rule.</para>
/// </summary>
public class HarnessSourceRuleTests
{
    private static readonly string DownOnly = "Keyboard." + "Press(";

    /// <summary>(file, method) pairs allowed the down-only call, each with a key-up in a finally.</summary>
    private static readonly (string File, string Method)[] Allowed = { ("PageTablesUiTests.cs", "HeldSpace") };

    private static string SourceFolder()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && dir.Name != "windows-app") dir = dir.Parent;
        if (dir is null) throw new InvalidOperationException("Could not locate windows-app/ from " + AppContext.BaseDirectory);
        return Path.Combine(dir.FullName, "Plantoir.UiTests");
    }

    /// <summary>The name of the method a position in a C# file is inside: the
    /// last method-like declaration before it. Good enough for this folder's
    /// shape, where every helper is a plain method.</summary>
    internal static string EnclosingMethod(string source, int position)
    {
        var declarations = Regex.Matches(source[..position],
            @"^\s*(?:(?:public|private|internal|protected|static|async|override)\s+)+[\w<>\[\],.? ]+?\s+(\w+)\s*\(",
            RegexOptions.Multiline);
        return declarations.Count == 0 ? "" : declarations[^1].Groups[1].Value;
    }

    [Fact]
    public void NoTestSendsAKeyDownWithNoKeyUp()
    {
        var found = new List<string>();
        foreach (string file in Directory.EnumerateFiles(SourceFolder(), "*.cs"))
        {
            string name = Path.GetFileName(file);
            string source = File.ReadAllText(file);
            for (int at = source.IndexOf(DownOnly, StringComparison.Ordinal); at >= 0;
                 at = source.IndexOf(DownOnly, at + 1, StringComparison.Ordinal))
            {
                string method = EnclosingMethod(source, at);
                if (Allowed.Contains((name, method))) continue;
                int line = source[..at].Count(c => c == '\n') + 1;
                found.Add($"{name}:{line} (in {method})");
            }
        }
        Assert.True(found.Count == 0,
            "These send a key DOWN and never UP, which leaves it held for the rest of the run (#638); " +
            "use Keyboard.Type, or using (Keyboard.Pressing(...)): " + string.Join(", ", found));
    }

    [Fact]
    public void TheAllowedMethodStillReleasesItsKey()
    {
        foreach (var (file, method) in Allowed)
        {
            string source = File.ReadAllText(Path.Combine(SourceFolder(), file));
            int start = source.IndexOf($" {method}(", StringComparison.Ordinal);
            Assert.True(start >= 0, $"{file} no longer has {method}; take it off the allowed list");
            int next = source.IndexOf("\n    private ", start + 1, StringComparison.Ordinal);
            string body = next < 0 ? source[start..] : source[start..next];
            Assert.Contains("finally { Keyboard.Release(", body);
        }
    }

    [Fact]
    public void TheHeldKeyMessageNamesTheTestsAndTheFix()
    {
        string message = HeldKeys.FailureMessage(new[] { "PlanTableUiTests.Tab: TAB" });
        Assert.Contains("PlanTableUiTests.Tab: TAB", message);
        Assert.Contains("Keyboard.Type", message);
        Assert.Contains("remote-desktop", message);
    }
}

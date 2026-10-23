using System.Text.RegularExpressions;

namespace Plantoir.UiTests;

/// <summary>
/// #638, pinned WITHOUT a desktop (plain facts, like
/// <see cref="AssertAbsentRuleTests"/>): no UI test sends a key DOWN with no
/// key up. FlaUI's down-only call leaves the key held at the operating-system
/// level for the rest of the run; <c>Keyboard.Type</c> sends both, and
/// <c>using (Keyboard.Pressing(...))</c> sends the up on dispose.
///
/// <para>One method is allowed the down-only call, by name:
/// <c>PageTablesUiTests.HeldSpace</c> imitates a held key's auto-repeat
/// (several downs, then ONE up in a <c>finally</c>), which neither safe form
/// can send. The patterns are spelled in pieces here so this file does not
/// trip its own rule.</para>
/// </summary>
public class HarnessSourceRuleTests
{
    // Spaced either way: "Keyboard.Press (" is the same call.
    private static readonly Regex DownOnly = new(@"Keyboard\s*\.\s*Press" + @"\s*\(");
    private static readonly Regex Holding = new(@"Keyboard\s*\.\s*Pressing" + @"\s*\(");

    /// <summary>(file, method) pairs allowed the down-only call, each with a key-up in a finally.</summary>
    private static readonly (string File, string Method)[] Allowed = { ("PageTablesUiTests.cs", "HeldSpace") };

    private static string SourceFolder()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && dir.Name != "windows-app") dir = dir.Parent;
        if (dir is null) throw new InvalidOperationException("Could not locate windows-app/ from " + AppContext.BaseDirectory);
        return Path.Combine(dir.FullName, "Plantoir.UiTests");
    }

    private static IEnumerable<(string Name, string Source)> Sources() =>
        Directory.EnumerateFiles(SourceFolder(), "*.cs").Select(file => (Path.GetFileName(file), File.ReadAllText(file)));

    private static int LineOf(string source, int position) => source[..position].Count(c => c == '\n') + 1;

    /// <summary>Whether a position sits on a line that is a comment (a doc
    /// comment naming the safe form is not code).</summary>
    private static bool InAComment(string source, int position)
    {
        string lineSoFar = source[(source.LastIndexOf('\n', position) + 1)..position];
        return lineSoFar.TrimStart().StartsWith("//", StringComparison.Ordinal);
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
        foreach (var (name, source) in Sources())
            foreach (Match match in DownOnly.Matches(source))
            {
                if (InAComment(source, match.Index)) continue;
                string method = EnclosingMethod(source, match.Index);
                if (Allowed.Contains((name, method))) continue;
                found.Add($"{name}:{LineOf(source, match.Index)} (in {method})");
            }
        Assert.True(found.Count == 0,
            "These send a key DOWN and never UP, which leaves it held for the rest of the run (#638); " +
            "use Keyboard.Type, or using (Keyboard.Pressing(...)): " + string.Join(", ", found));
    }

    /// <summary>
    /// A held key's release is the DISPOSE of what <c>Keyboard.Pressing</c>
    /// returns, so a call whose result is thrown away holds the key until
    /// something else lets it go. PlanTable's Shift+Tab did exactly that until
    /// #638 (released by hand on the next line, so a failing step between
    /// would have left Shift down). Every such call heads a <c>using</c>.
    /// </summary>
    [Fact]
    public void EveryHeldKeyIsHeldByAUsing()
    {
        var found = new List<string>();
        foreach (var (name, source) in Sources())
            foreach (Match match in Holding.Matches(source))
            {
                if (InAComment(source, match.Index)) continue;
                // The line so far ends "using (" or "using var x = ": the call
                // heads a using. (A string naming the safe form ends the same way.)
                string lineSoFar = source[(source.LastIndexOf('\n', match.Index) + 1)..match.Index];
                if (Regex.IsMatch(lineSoFar, @"\busing\s*\(\s*$|\busing\s+var\s+\w+\s*=\s*$")) continue;
                found.Add($"{name}:{LineOf(source, match.Index)}");
            }
        Assert.True(found.Count == 0,
            "Keyboard.Pressing returns what releases the key; these throw it away (#638): " + string.Join(", ", found));
    }

    /// <summary>Every key a test names is one <see cref="HeldKeys"/> watches, or one left down would go unseen.</summary>
    [Fact]
    public void EveryKeyATestNamesIsWatched()
    {
        // Compared by value: ENTER and RETURN, ALT and MENU name one key each.
        var watched = HeldKeys.Watched.Select(key => (int)key).ToHashSet();
        var missing = new SortedSet<string>();
        foreach (var (_, source) in Sources())
            foreach (Match match in Regex.Matches(source, @"VirtualKeyShort\.([A-Z_0-9]+)"))
                if (Enum.TryParse<FlaUI.Core.WindowsAPI.VirtualKeyShort>(match.Groups[1].Value, out var key)
                    && !watched.Contains((int)key))
                    missing.Add(match.Groups[1].Value);
        Assert.True(missing.Count == 0, "HeldKeys.Watched does not watch: " + string.Join(", ", missing));
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

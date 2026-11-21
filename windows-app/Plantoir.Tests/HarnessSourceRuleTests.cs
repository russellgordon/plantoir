using System.Text.RegularExpressions;

namespace Plantoir.Tests;

/// <summary>
/// #638, pinned WITHOUT a desktop: no UI test sends a key DOWN with no key
/// up. FlaUI's down-only call leaves the key held at the operating-system
/// level for the rest of the run; <c>Keyboard.Type</c> sends both, and
/// <c>using (Keyboard.Pressing(...))</c> sends the up on dispose.
///
/// <para><b>Why it lives here, not in Plantoir.UiTests (#1035).</b> These read
/// the UI test project's SOURCES and need nothing else, but in that project
/// the merge gate, which runs this unit project only, never ran them, and two
/// breaks sat on <c>dev</c> unseen. They read the sources from here, and the
/// watched keys from <c>HeldKeys.cs</c>'s own <c>Watched</c> list, so there
/// is still one copy of each.</para>
///
/// <para>One method is allowed the down-only call, by name:
/// <c>HeldKeys.HoldWithRepeats</c> imitates a held key's auto-repeat (several
/// downs, then ONE up in a <c>finally</c>), which neither safe form can send.
/// The patterns are spelled in pieces here so this file reads the same way a
/// UI test source would.</para>
/// </summary>
public class HarnessSourceRuleTests
{
    // Spaced either way: "Keyboard.Press (" is the same call.
    private static readonly Regex DownOnly = new(@"Keyboard\s*\.\s*Press" + @"\s*\(");
    private static readonly Regex Holding = new(@"Keyboard\s*\.\s*Pressing" + @"\s*\(");
    private static readonly Regex KeyName = new(@"VirtualKeyShort\.([A-Z_0-9]+)");

    /// <summary>(file, method) pairs allowed the down-only call, each with a key-up in a finally.</summary>
    private static readonly (string File, string Method)[] Allowed = { ("HeldKeys.cs", "HoldWithRepeats") };

    private static string SourceFolder() => Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir.UiTests");

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

    /// <summary>The keys <c>HeldKeys.Watched</c> lists, read from its source.</summary>
    internal static HashSet<string> WatchedKeys()
    {
        string source = File.ReadAllText(Path.Combine(SourceFolder(), "HeldKeys.cs"));
        var list = Regex.Match(source, @"VirtualKeyShort\[\]\s+Watched\s*=\s*\{(.*?)\};", RegexOptions.Singleline);
        Assert.True(list.Success, "HeldKeys.cs no longer declares its Watched list as an array; this rule reads it");
        var watched = new HashSet<string>();
        foreach (Match key in KeyName.Matches(list.Groups[1].Value)) watched.Add(key.Groups[1].Value);
        Assert.NotEmpty(watched);
        return watched;
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
            "use Keyboard.Type, using (Keyboard.Pressing(...)), or HeldKeys.HoldWithRepeats for a held key's repeats: " +
            string.Join(", ", found));
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
                // The line so far ends "using (", "using (var x = ",
                // "using var x = " or "using IDisposable x = ": the call heads a
                // using. (A string naming the safe form ends the same way.)
                string lineSoFar = source[(source.LastIndexOf('\n', match.Index) + 1)..match.Index];
                if (Regex.IsMatch(lineSoFar, @"\busing\s*\(\s*(\w+\s+\w+\s*=\s*)?$|\busing\s+\w+\s+\w+\s*=\s*$")) continue;
                found.Add($"{name}:{LineOf(source, match.Index)}");
            }
        Assert.True(found.Count == 0,
            "Keyboard.Pressing returns what releases the key; these throw it away (#638): " + string.Join(", ", found));
    }

    /// <summary>
    /// Every key a test names is one <c>HeldKeys</c> watches, or one left down
    /// would go unseen. Compared by NAME, because FlaUI's key list cannot be
    /// loaded by this project (it is Windows-only and this project is not):
    /// a test spells a key the way <c>Watched</c> does (RETURN, not its
    /// other name ENTER), and a second name for a watched key fails here
    /// rather than slipping past.
    /// </summary>
    [Fact]
    public void EveryKeyATestNamesIsWatched()
    {
        var watched = WatchedKeys();
        var missing = new SortedSet<string>();
        foreach (var (name, source) in Sources())
            foreach (Match match in KeyName.Matches(source))
                if (!InAComment(source, match.Index) && !watched.Contains(match.Groups[1].Value))
                    missing.Add($"{match.Groups[1].Value} ({name}:{LineOf(source, match.Index)})");
        Assert.True(missing.Count == 0,
            "HeldKeys.Watched does not watch these keys a test names (add the key there, spelled the same way): " +
            string.Join(", ", missing));
    }

    [Fact]
    public void TheAllowedMethodStillReleasesItsKey()
    {
        foreach (var (file, method) in Allowed)
        {
            string source = File.ReadAllText(Path.Combine(SourceFolder(), file));
            int start = source.IndexOf($" {method}(", StringComparison.Ordinal);
            Assert.True(start >= 0, $"{file} no longer has {method}; take it off the allowed list");
            int next = source.IndexOf("\n    p", start + 1, StringComparison.Ordinal);
            string body = next < 0 ? source[start..] : source[start..next];
            Assert.Contains("finally { Keyboard.Release(", body);
        }
    }

    /// <summary>The rule reads the real list: a key it surely watches is in it.</summary>
    [Fact]
    public void TheWatchedListIsReadFromHeldKeys()
    {
        var watched = WatchedKeys();
        Assert.Contains("ESCAPE", watched);
        Assert.Contains("SHIFT", watched);
    }
}

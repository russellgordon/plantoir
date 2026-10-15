using System.Globalization;
using System.Text.RegularExpressions;

namespace Plantoir.Tests;

/// <summary>
/// Nothing a teacher reads is smaller than 12 effective pixels (#491 item 9;
/// the mac's "nothing below 10 pt"). Why 12 and not a conversion of the mac's
/// number: 12 is Fluent's Caption, the smallest size in Windows' own type ramp,
/// and the size the app's captions already use. Points on the mac are logical
/// pixels, so the mac's 10 pt is about 10–11 epx here — a floor below Windows'
/// own smallest style would have permitted text Windows never draws (decided
/// on batch 3's plan review, M4). Glyphs in a <c>FontIcon</c> are icons, not
/// text, and are exempt.
/// </summary>
/// <remarks>
/// Reads every <c>.cs</c> and <c>.xaml</c> under <c>Plantoir/</c>, including XAML
/// held in C# strings (the wizard's "Example content" badge is a DataTemplate
/// in a raw string, and was 10): an attribute <c>FontSize="N"</c> belongs to
/// the nearest <c>&lt;Tag</c> before it, an assignment <c>FontSize = N</c> to the
/// nearest <c>new Type {</c> whose braces are still open.
/// </remarks>
public class FontSizeFloorScanTests
{
    private const double Floor = 12;

    private static string AppFolder => Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir");

    [Fact]
    public void NoTextIsSmallerThanTheFloor()
    {
        var attribute = new Regex(@"\bFontSize=""(?<n>[0-9]+(?:\.[0-9]+)?)""");
        var assignment = new Regex(@"\bFontSize\s*=\s*(?<n>[0-9]+(?:\.[0-9]+)?)\b");
        var creation = new Regex(@"\bnew\s+(?<type>[A-Za-z_][\w.]*)\s*(?:\(\s*\))?\s*\{");
        var tag = new Regex(@"<(?<type>[A-Za-z_][\w:.]*)");
        var offenders = new List<string>();
        int seen = 0;

        foreach (string file in Directory.EnumerateFiles(AppFolder, "*.*", SearchOption.AllDirectories)
                     .Where(f => f.EndsWith(".cs", StringComparison.Ordinal) || f.EndsWith(".xaml", StringComparison.Ordinal))
                     .Where(f => !f.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")
                                 && !f.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}")))
        {
            string source = File.ReadAllText(file);
            string name = Path.GetRelativePath(AppFolder, file);

            void Check(Match match, string owner)
            {
                seen++;
                double size = double.Parse(match.Groups["n"].Value, CultureInfo.InvariantCulture);
                if (size >= Floor || owner.EndsWith("FontIcon", StringComparison.Ordinal)) return;
                int line = source[..match.Index].Count(c => c == '\n') + 1;
                offenders.Add($"{name}:{line}: FontSize {size} on {owner}");
            }

            foreach (Match match in attribute.Matches(source))
            {
                var owner = tag.Matches(source[..match.Index]).LastOrDefault();
                Check(match, owner?.Groups["type"].Value ?? "?");
            }
            foreach (Match match in assignment.Matches(source))
            {
                // The innermost object initialiser still open at the match.
                string before = source[..match.Index];
                string owner = "?";
                foreach (Match made in creation.Matches(before).Reverse())
                {
                    string inside = before[(made.Index + made.Length)..];
                    if (inside.Count(c => c == '{') >= inside.Count(c => c == '}'))
                    {
                        owner = made.Groups["type"].Value;
                        break;
                    }
                }
                Check(match, owner);
            }
        }

        Assert.True(seen > 50, $"only {seen} font sizes were found — the scan is not reading the app");
        Assert.True(offenders.Count == 0,
            $"Text below {Floor} epx (Fluent's Caption, Windows' smallest style):\n" + string.Join("\n", offenders));
    }
}

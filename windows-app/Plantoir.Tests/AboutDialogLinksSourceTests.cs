using System.Text.RegularExpressions;

namespace Plantoir.Tests;

/// <summary>
/// #993 (D46), the Windows half: the About panel follows the mac's About
/// window as Russell ruled (option A of
/// <c>vm-tools/reference/993-about-window-design.md</c>). Every link is a
/// <c>HyperlinkButton</c> of its own, which UI Automation exposes as one
/// Hyperlink element with its own words and Tab reaches; the sponsor sentence
/// is plain text with its two links beneath it; the credits are label-and-value
/// rows. The mac reads the same six links through the accessibility tree
/// (<c>AboutWindowLinksTests</c>); a dialog cannot be built outside a WinUI
/// window here, so this pins the source, and what a screen reader hears is for
/// the UI harness or a live read.
/// </summary>
public class AboutDialogLinksSourceTests
{
    private static string AboutDialog() => File.ReadAllText(Path.Combine(
        ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "Views", "AboutDialog.cs")).Replace("\r\n", "\n");

    [Fact]
    public void NoLinkIsInsideASentence()
    {
        string source = AboutDialog();
        // A Hyperlink (not a HyperlinkButton) is an inline run inside a
        // TextBlock's sentence; the old panel built its links that way.
        Assert.False(Regex.IsMatch(source, @"new Hyperlink(?!Button)"), "a link is built inside a sentence (new Hyperlink)");
        Assert.DoesNotContain("Inlines.Add", source);
    }

    [Fact]
    public void EveryLinkIsAHyperlinkButtonOfItsOwnWithItsOwnWords()
    {
        string source = AboutDialog();
        // Each link's address too, the mac's (AboutWindowLinksTests, #1012):
        // the 993b review found the first pattern took any address at all, so
        // a link pointed elsewhere passed (#1020).
        var expected = new (string Address, string Words, string Id)[]
        {
            ("https://plantoir.app", "\"https://plantoir.app\"", "aboutWebsiteLink"),
            ("mailto:support@plantoir.app", "\"support@plantoir.app\"", "aboutEmailLink"),
            ("https://quartz.jzhao.xyz", "QuartzName", "aboutQuartzLink"),
            ("https://github.com/sponsors/jackyzha0", "\"Sponsor Jacky Zhao on GitHub\"", "aboutSponsorLink"),
            ("https://phosphoricons.com", "\"Phosphor Icons\"", "aboutIconCreditLink"),
            ("https://www.russellgordon.ca", "\"Russell Gordon\"", "aboutDesignCreditLink"),
        };
        foreach (var (address, words, id) in expected)
        {
            string call = @"Link\(""" + Regex.Escape(address) + @""", " + Regex.Escape(words) + @", """ + id + @"""";
            Assert.True(Regex.IsMatch(source, call), $"no link of its own reads {words} ({id}) and goes to {address}");
        }
        // Six links and no seventh: every Link( call names one of the six.
        Assert.Equal(6, Regex.Matches(source, ", \"about[A-Za-z]+Link\"").Count);
    }

    [Fact]
    public void TheCreditsAreLabelAndValueRows()
    {
        string source = AboutDialog();
        Assert.Contains("CreditRow(0, \"Icon\", iconCredit);", source);
        Assert.Contains("CreditRow(1, \"Design\", Link(", source);
        Assert.Contains("CreditRow(2, \"Made with\", new TextBlock { Text = \"Claude\"", source);
        Assert.Contains("Text = \"(MIT)\"", source);
    }

    [Fact]
    public void TheSponsorSentenceIsWholeAndPlain()
    {
        string source = AboutDialog();
        Assert.Contains("Text = \"Plantoir is a friendly wrapper around \" + QuartzName + \", which Jacky Zhao builds and gives away for free. If you end up using Plantoir regularly, please consider sponsoring him on GitHub — it is his work that makes all of this possible.\"", source);
    }
}

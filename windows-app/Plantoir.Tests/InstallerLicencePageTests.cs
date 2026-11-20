using System.Text;
using System.Text.RegularExpressions;
using Plantoir.Core.Assist;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #1010 (Russell's rulings of 2026-11-19, option A): the Windows installer
/// shows Inno Setup's Licence Agreement page, first in the wizard, with
/// neither choice made when it opens and Next disabled until "I accept the
/// agreement" is chosen; its words say "Licence"; the text it shows carries
/// the repository's own <c>LICENSE</c> word for word, scoped to Plantoir's own
/// code, and the terms for Microsoft's vcruntime140.dll; and the third-party
/// notice it names is installed beside the app.
/// </summary>
/// <remarks>
/// These read SOURCE TEXT with comments taken out (<see
/// cref="InstallerRunningWorkTests.WithoutComments"/>), so a setting that is
/// commented out goes red. What the page LOOKS like, and that a /VERYSILENT
/// update shows no page, is proven by building the installer and running it
/// (documentation/12-windows-app.md, "The Licence Agreement page"); the
/// first-install rehearsal's driver chooses "I accept the agreement" by name.
/// </remarks>
public sealed class InstallerLicencePageTests
{
    // MARK: - Where the files are

    private static string RepoRoot => ContractLoader.RepositoryRoot;
    private static string WindowsApp => Path.Combine(RepoRoot, "windows-app");

    private static string Installer =>
        InstallerRunningWorkTests.WithoutComments(File.ReadAllText(Path.Combine(WindowsApp, "installer.iss")));

    private static string LicencePageText => File.ReadAllText(Path.Combine(WindowsApp, "installer-licence.txt"));

    /// <summary>The lines of one <c>[Section]</c> of the script, comments already gone, blank lines dropped.</summary>
    private static List<string> SectionLines(string script, string section)
    {
        var lines = new List<string>();
        bool inside = false;
        foreach (string line in script.Replace("\r\n", "\n").Split('\n'))
        {
            string trimmed = line.Trim();
            if (Regex.IsMatch(trimmed, @"^\[[A-Za-z]+\]$"))
            {
                inside = trimmed.Equals($"[{section}]", StringComparison.OrdinalIgnoreCase);
                continue;
            }
            if (inside && trimmed.Length > 0) lines.Add(trimmed);
        }
        return lines;
    }

    /// <summary>
    /// The paragraphs of a text, each with its line breaks joined into single
    /// spaces: the repository's <c>LICENSE</c> is wrapped at 80 columns, as a
    /// licence file usually is, and the page's text is not (Inno wraps it to
    /// the box), so the same words are compared, not the same line breaks.
    /// </summary>
    private static List<string> Paragraphs(string text)
    {
        var paragraphs = new List<string>();
        foreach (string block in Regex.Split(text.Replace("\r\n", "\n").Trim(), @"\n\s*\n"))
        {
            string joined = Regex.Replace(block.Trim(), @"\s*\n\s*", " ");
            if (joined.Length > 0) paragraphs.Add(joined);
        }
        return paragraphs;
    }

    // MARK: - The page is shown, first, with neither choice made

    [Fact]
    public void TheInstallerShowsTheLicencePage()
    {
        Assert.Contains("LicenseFile=installer-licence.txt", SectionLines(Installer, "Setup"));
        Assert.True(File.Exists(Path.Combine(WindowsApp, "installer-licence.txt")));
        // Option A, not B: an agreement to accept, not a page to read and pass.
        foreach (string line in SectionLines(Installer, "Setup"))
        {
            Assert.False(line.StartsWith("InfoBeforeFile", StringComparison.OrdinalIgnoreCase), line);
            // Inno's welcome page would come before it; the page is first.
            Assert.NotEqual("DisableWelcomePage=no", line);
        }
    }

    [Fact]
    public void ThePageOpensWithNeitherChoiceMade()
    {
        string code = Installer[Installer.IndexOf("[Code]", StringComparison.Ordinal)..];
        var initialize = Regex.Match(code, @"(?ms)^procedure InitializeWizard;\s*\nbegin\n(.*?)^end;");
        Assert.True(initialize.Success, "installer.iss has no InitializeWizard outside comments");
        string body = initialize.Groups[1].Value;
        Assert.Contains("WizardForm.LicenseNotAcceptedRadio.Checked := False;", body);
        // Nothing anywhere chooses "I accept" for the teacher, or turns Next on for the page.
        Assert.DoesNotContain("LicenseAcceptedRadio.Checked := True", code);
        Assert.DoesNotContain("NextButton.Enabled := True", code);
        // The include defines no InitializeWizard of its own to override this one.
        string include = File.ReadAllText(Path.Combine(WindowsApp, "installer-running-work.iss"));
        Assert.DoesNotContain("InitializeWizard", InstallerRunningWorkTests.WithoutComments(include, startsInCode: true));
        // And no ShouldSkipPage brings the page into a silent install or skips it in a visible one.
        Assert.DoesNotContain("ShouldSkipPage", code);
    }

    // MARK: - The page's words say "Licence"

    /// <summary>
    /// Every message Inno's License Agreement page shows (Default.isl, the
    /// "License Agreement" wizard page section: the title, the sentence under
    /// it, the sentence above the text, and the two choices), each set in
    /// <c>[Messages]</c> and none spelled "License".
    /// </summary>
    [Fact]
    public void EveryMessageOnThePageIsOursAndSaysLicence()
    {
        var expected = new Dictionary<string, string>
        {
            ["WizardLicense"] = "Licence Agreement",
            ["LicenseLabel"] = "Please read the following important information before continuing.",
            ["LicenseLabel3"] = "Please read the following Licence Agreement. You must accept the terms of this agreement before continuing with the installation.",
            ["LicenseAccepted"] = "I &accept the agreement",
            ["LicenseNotAccepted"] = "I &do not accept the agreement",
        };
        var set = new Dictionary<string, string>();
        foreach (string line in SectionLines(Installer, "Messages"))
        {
            int equals = line.IndexOf('=');
            Assert.True(equals > 0, $"[Messages] line without a value: {line}");
            string key = line[..equals].Trim();
            Assert.False(set.ContainsKey(key), $"[Messages] sets {key} twice");
            set[key] = line[(equals + 1)..];
        }
        foreach (var (key, words) in expected)
        {
            Assert.True(set.ContainsKey(key), $"[Messages] does not set {key}, so Inno's own words would show");
            Assert.Equal(words, set[key]);
        }
        foreach (var (key, words) in set)
            Assert.False(words.Contains("License", StringComparison.Ordinal), $"{key} says \"License\": {words}");
    }

    // MARK: - The page's text

    [Fact]
    public void TheRepositoryHasAnMitLicenceInPlantoirsName()
    {
        var licence = Paragraphs(File.ReadAllText(Path.Combine(RepoRoot, "LICENSE")));
        Assert.Equal("MIT License", licence[0]);
        // The year and name About shows (AboutDialog.cs; the Mac's AboutView.swift).
        Assert.Equal("Copyright 2026 Russell Gordon", licence[1]);
        Assert.StartsWith("Permission is hereby granted, free of charge,", licence[2]);
        Assert.StartsWith("The above copyright notice and this permission notice shall be included", licence[3]);
        Assert.StartsWith("THE SOFTWARE IS PROVIDED \"AS IS\"", licence[4]);
        Assert.Equal(5, licence.Count);
        string readme = File.ReadAllText(Path.Combine(RepoRoot, "README.md"));
        Assert.Contains("[`LICENSE`](LICENSE)", readme);
    }

    /// <summary>
    /// The page carries the repository's <c>LICENSE</c> word for word: its
    /// copyright line, then (after the line scoping it to Plantoir's own code)
    /// its three paragraphs, in order, with nothing between them.
    /// </summary>
    [Fact]
    public void ThePageCarriesTheLicenceFileWordForWord()
    {
        var licence = Paragraphs(File.ReadAllText(Path.Combine(RepoRoot, "LICENSE")));
        var page = Paragraphs(LicencePageText);
        Assert.Equal("Plantoir", page[0]);
        Assert.Equal(licence[1], page[1]);
        Assert.Equal("Plantoir's own code is released under the MIT License:", page[2]);
        Assert.Equal(licence[2], page[3]);
        Assert.Equal(licence[3], page[4]);
        Assert.Equal(licence[4], page[5]);
    }

    [Fact]
    public void TheMicrosoftTermsSayTheMitLicenceDoesNotApplyToTheirFile()
    {
        var page = Paragraphs(LicencePageText);
        int heading = page.IndexOf("Microsoft Visual C++ runtime");
        Assert.True(heading > 0, "the page has no \"Microsoft Visual C++ runtime\" heading");
        string terms = page[heading + 1];
        Assert.StartsWith("Plantoir includes vcruntime140.dll", terms);
        Assert.Contains("The MIT License above does not apply to it.", terms);
        // The drafted limits, as ruled (Russell, 2026-11-19, ruling 2).
        Assert.Contains("You may use it only as part of Plantoir.", terms);
        Assert.Contains("reverse engineer, decompile or disassemble it", terms);
        Assert.Contains("\"as is\", without warranty of any kind", terms);
        Assert.Equal(heading + 2, page.Count);
        Assert.DoesNotContain("DRAFT", LicencePageText, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void ThePageNamesTheNoticeTheInstallerCopies()
    {
        var page = Paragraphs(LicencePageText);
        Assert.Contains("Software by other people", page);
        Assert.Contains("THIRD_PARTY_LICENSES.txt in the folder Plantoir is installed in", LicencePageText);
        Assert.Contains(@"Source: ""..\THIRD_PARTY_LICENSES.md""; DestDir: ""{app}""; DestName: ""THIRD_PARTY_LICENSES.txt""; Flags: ignoreversion",
                        SectionLines(Installer, "Files"));
        Assert.True(File.Exists(Path.Combine(RepoRoot, "THIRD_PARTY_LICENSES.md")));
    }

    /// <summary>
    /// Rule 1: the page is read by a teacher, so it never names the machinery:
    /// rule 1's own words, with those the update's wording is checked against
    /// (contracts/shared-rules.json, the Windows update wording's
    /// machineryCheck), since this page belongs to the installer too.
    /// </summary>
    [Fact]
    public void ThePageNeverNamesTheMachinery()
    {
        string[] banned = { "toolchain", "script", "docker", "container", "Sparkle", "feed", "appcast", "launchd", "lease", "process" };
        foreach (string word in banned)
            Assert.False(Regex.IsMatch(LicencePageText, $@"\b{Regex.Escape(word)}\b", RegexOptions.IgnoreCase),
                         $"installer-licence.txt says \"{word}\"");
    }

    /// <summary>
    /// Inno reads a .txt licence file as UTF-8 or UTF-16LE. Strict UTF-8, so a
    /// stray byte from another encoding fails here rather than showing as a
    /// wrong letter on the page.
    /// </summary>
    [Fact]
    public void ThePageTextIsUtf8()
    {
        byte[] bytes = File.ReadAllBytes(Path.Combine(WindowsApp, "installer-licence.txt"));
        var strict = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true);
        string text = strict.GetString(bytes);
        Assert.Contains("Copyright 2026 Russell Gordon", text);
    }
}

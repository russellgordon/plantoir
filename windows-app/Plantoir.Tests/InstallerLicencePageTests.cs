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

    private static string Notice => File.ReadAllText(Path.Combine(RepoRoot, "THIRD_PARTY_LICENSES.md"));

    /// <summary>The heading of the notice's section that carries the terms for Microsoft's file.</summary>
    private const string NoticeTermsHeading = "## Terms for the Microsoft Visual C++ runtime file, which only the Windows app carries";

    /// <summary>The page's paragraph of terms for vcruntime140.dll: the one after its "Microsoft Visual C++ runtime" heading.</summary>
    private static string PageTerms()
    {
        var page = Paragraphs(LicencePageText);
        int heading = page.IndexOf("Microsoft Visual C++ runtime");
        Assert.True(heading > 0 && heading + 1 < page.Count, "the page has no \"Microsoft Visual C++ runtime\" heading with terms after it");
        return page[heading + 1];
    }

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

    /// <summary>
    /// Pascal ignores spacing and the case of its words, so the settings are
    /// matched that way: <c>Checked:=True</c> and <c>checked := true</c> are
    /// the same line to Inno and to these tests.
    /// </summary>
    private static bool Sets(string code, string property, string value) =>
        Regex.IsMatch(code, $@"\b{Regex.Escape(property).Replace(@"\.", @"\s*\.\s*")}\s*:=\s*{value}\s*;", RegexOptions.IgnoreCase);

    private static string Code => Installer[Installer.IndexOf("[Code]", StringComparison.Ordinal)..];

    private static string InitializeWizardBody()
    {
        var initialize = Regex.Match(Code, @"(?msi)^\s*procedure\s+InitializeWizard\s*;\s*\nbegin\s*\n(.*?)^\s*end;");
        Assert.True(initialize.Success, "installer.iss has no InitializeWizard outside comments");
        return initialize.Groups[1].Value;
    }

    [Fact]
    public void ThePageOpensWithNeitherChoiceMade()
    {
        string code = Code;
        string body = InitializeWizardBody();
        Assert.True(Sets(body, "WizardForm.LicenseNotAcceptedRadio.Checked", "False"), "InitializeWizard does not clear \"I do not accept the agreement\"");
        // Nothing anywhere chooses "I accept" for the teacher, or turns Next on for the page.
        Assert.False(Sets(code, "LicenseAcceptedRadio.Checked", "True"), "installer.iss chooses \"I accept the agreement\"");
        Assert.False(Sets(code, "NextButton.Enabled", "True"), "installer.iss turns Next on");
        // The include defines no InitializeWizard of its own to override this one.
        string include = File.ReadAllText(Path.Combine(WindowsApp, "installer-running-work.iss"));
        Assert.DoesNotContain("InitializeWizard", InstallerRunningWorkTests.WithoutComments(include, startsInCode: true), StringComparison.OrdinalIgnoreCase);
        // And no ShouldSkipPage brings the page into a silent install or skips it in a visible one.
        Assert.DoesNotContain("ShouldSkipPage", code, StringComparison.OrdinalIgnoreCase);
    }

    [Theory]
    [InlineData("WizardForm.LicenseNotAcceptedRadio.Checked := False;", true)]
    [InlineData("WizardForm.LicenseNotAcceptedRadio.Checked:=False;", true)]
    [InlineData("  wizardform.licensenotacceptedradio.checked  :=  false ;", true)]
    [InlineData("WizardForm.LicenseNotAcceptedRadio.Checked := True;", false)]
    [InlineData("WizardForm.LicenseAcceptedRadio.Checked := False;", false)]
    public void TheSettingIsReadWhateverItsSpacing(string line, bool readsAsClearingTheRefusal)
    {
        Assert.Equal(readsAsClearingTheRefusal, Sets(line, "WizardForm.LicenseNotAcceptedRadio.Checked", "False"));
    }

    /// <summary>
    /// The #1010 review: Delphi's radio button sets its Tab stop to match
    /// Checked, so clearing both choices took the pair out of the Tab order
    /// (measured on the Windows VM: Tab went only between the text and
    /// Cancel). The pair gets back one Tab stop, on the safe choice: Windows
    /// chooses a radio button when the keyboard moves the focus onto it, so a
    /// stop on "I accept the agreement" would accept by Tab alone. The keys,
    /// measured, are in documentation/12-windows-app.md, "The Licence
    /// Agreement page in the installer (#1010)".
    /// </summary>
    [Fact]
    public void TabReachesTheChoicesOnTheSafeOne()
    {
        string body = InitializeWizardBody();
        Assert.True(Sets(body, "WizardForm.LicenseNotAcceptedRadio.TabStop", "True"), "InitializeWizard does not give \"I do not accept the agreement\" its Tab stop");
        Assert.False(Sets(Code, "LicenseAcceptedRadio.TabStop", "True"), "a Tab stop on \"I accept the agreement\" would accept by Tab alone");
        Assert.False(Sets(Code, "LicenseNotAcceptedRadio.TabStop", "False"), "installer.iss takes the pair's Tab stop away");
        // The Tab stop comes after both are cleared: clearing a choice takes its Tab stop away again.
        int stop = Regex.Match(body, @"(?i)LicenseNotAcceptedRadio\s*\.\s*TabStop").Index;
        foreach (Match cleared in Regex.Matches(body, @"(?i)License(Not)?AcceptedRadio\s*\.\s*Checked"))
            Assert.True(cleared.Index < stop, "a choice is cleared after the Tab stop is set, which takes the stop away");
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
        // Read the same in the notice, where no MIT text comes above it (the second #1010 review).
        Assert.Contains("The MIT License that covers Plantoir's own code does not apply to it.", terms);
        Assert.DoesNotContain("above", terms, StringComparison.OrdinalIgnoreCase);
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
    /// Russell's ruling 6 (2026-11-19): the portable <c>Plantoir-win-x64.zip</c>
    /// carries <c>LICENSE</c> and <c>THIRD_PARTY_LICENSES.txt</c> beside the
    /// app, the notice under the name the installer gives it. They are added
    /// to the zip once it is made, not put in the publish folder, which the
    /// installer takes whole. The zip's name is a frozen asset name
    /// (RELEASING.md) and is held here too.
    /// </summary>
    [Fact]
    public void ThePortableZipCarriesTheLicencesBesideTheApp()
    {
        string publish = InstallerRunningWorkTests.PowerShellWithoutComments(File.ReadAllText(Path.Combine(WindowsApp, "publish.ps1")));
        Assert.Contains(@"$zip = ""dist\Plantoir-win-x64.zip""", publish);
        Assert.Contains(@"Copy-Item ""..\LICENSE"" ""$zipLicences\LICENSE""", publish);
        Assert.Contains(@"Copy-Item ""..\THIRD_PARTY_LICENSES.md"" ""$zipLicences\THIRD_PARTY_LICENSES.txt""", publish);
        string added = @"Compress-Archive -Path ""$zipLicences\LICENSE"", ""$zipLicences\THIRD_PARTY_LICENSES.txt"" -Update -DestinationPath $zip";
        Assert.Contains(added, publish);
        // In that order: the zip is made, then the two files go in, before the drive is unmapped.
        int made = publish.IndexOf(@"Compress-Archive -Path ""$substDrive\*"" -DestinationPath $zip", StringComparison.Ordinal);
        int licences = publish.IndexOf(added, StringComparison.Ordinal);
        int unmapped = publish.IndexOf("} finally {", Math.Max(made, 0), StringComparison.Ordinal);
        Assert.True(made >= 0, "publish.ps1 no longer makes the zip from the publish folder");
        Assert.True(made < licences && licences < unmapped, "the licences are not added to the zip after it is made");
        Assert.True(File.Exists(Path.Combine(RepoRoot, "LICENSE")));
        Assert.True(File.Exists(Path.Combine(RepoRoot, "THIRD_PARTY_LICENSES.md")));
        // Ruling 6: the zip's notice carries the Microsoft terms. The notice
        // the zip gets is THIRD_PARTY_LICENSES.md, copied as it is (above), so
        // the terms must be in that file, word for word as on the page; the
        // zip itself carries no Licence Agreement page (the second review).
        Assert.Contains(PageTerms(), Paragraphs(Notice));
    }

    /// <summary>
    /// The second #1010 review (MEDIUM): the end-user terms for
    /// vcruntime140.dll were on the installer's page only, so a copy of the
    /// file reached through the portable zip, or read later in the installed
    /// folder, travelled without them. They are in the notice now, under a
    /// heading that says only the Windows app carries the file (the notice
    /// is also read on GitHub, by Mac users too), in the same words as the
    /// page: one text, held equal here. The notice reaches {app} through the
    /// installer's [Files] line and the zip through publish.ps1 (the tests
    /// above), both copying the file unchanged.
    /// </summary>
    [Fact]
    public void TheNoticeCarriesTheMicrosoftTermsInThePagesWords()
    {
        var notice = Paragraphs(Notice);
        int heading = notice.IndexOf(NoticeTermsHeading);
        Assert.True(heading >= 0, $"THIRD_PARTY_LICENSES.md has no \"{NoticeTermsHeading}\" section");
        var section = new List<string>();
        for (int i = heading + 1; i < notice.Count && !notice[i].StartsWith("## ", StringComparison.Ordinal); i++)
            section.Add(notice[i]);
        var terms = new List<string>();
        foreach (string paragraph in section)
            if (paragraph.StartsWith("Plantoir includes vcruntime140.dll", StringComparison.Ordinal)) terms.Add(paragraph);
        Assert.Single(terms);
        Assert.Equal(PageTerms(), terms[0]);
        // Said where a Mac reader of the notice meets it, not only in the heading.
        Assert.Contains(section, paragraph => paragraph.Contains("The Mac app does not carry", StringComparison.Ordinal));
        // Nowhere else in the notice, so there is one copy of the words to keep equal.
        int copies = 0;
        foreach (string paragraph in notice)
            if (paragraph.Contains("You may use it only as part of Plantoir.", StringComparison.Ordinal)) copies++;
        Assert.Equal(1, copies);
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

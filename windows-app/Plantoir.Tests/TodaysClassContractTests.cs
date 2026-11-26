using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// <c>class-planning.json</c> → <c>todaysClassOnTheFrontPage</c> (#406, mac
/// #397): every case through this app's REAL readers on real files, as
/// <c>howTheCasesRun</c> says; the seven sentences; the Not Today record; and
/// the rule that only the section window's Preview button asks.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class TodaysClassContractTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("todays-class").FullName;
    private readonly string _trail;

    public TodaysClassContractTests()
    {
        _trail = Path.Combine(_folder, "trail.txt");
        ActivityTrail.SetCustomLogPathForTesting(_trail);
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(null);
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private static JsonNode Rule => ContractLoader.LoadJson("class-planning.json")["todaysClassOnTheFrontPage"]!;

    private (AssistWorkspace Workspace, string Index, int Section) LayOut(JsonNode c, string name)
    {
        string root = Path.Combine(_folder, name.GetHashCode().ToString("x8"));
        Directory.CreateDirectory(root);
        File.WriteAllText(Path.Combine(root, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(root, "deploy.ps1"), "# marker");
        int section = c["section"]?.GetValue<int>() ?? 1;
        string course = Path.Combine(root, "courses", "ICS3U");
        var config = new JsonObject
        {
            ["course_code"] = "ICS3U", ["course_name"] = "Test", ["num_sections"] = 1,
            ["section_numbers"] = new JsonArray(section),
            ["shared_folders"] = new JsonArray(), ["shared_files"] = new JsonArray(),
            ["per_section_folders"] = new JsonArray("All Classes"), ["per_section_files"] = new JsonArray(),
        };
        if (c["unitWord"] is { } word) config["unit_word"] = word.ToString();
        if (c["classPageScheme"] is { } scheme) config["class_page_scheme"] = scheme.ToString();
        if (c["frontPageHeading"] is { } heading) config["front_page_heading"] = heading.ToString();
        if (c["noun"] is { } noun) config["class_noun"] = noun.ToString();
        Directory.CreateDirectory(course);
        File.WriteAllText(Path.Combine(course, "course_config.json"), config.ToJsonString());

        foreach (var k in c["classes"]!.AsArray())
        {
            string folder = k!["folder"]?.ToString() ?? "All Classes";
            string dir = Path.Combine(course, $"section{section}", folder);
            Directory.CreateDirectory(dir);
            var publish = k["publish"]!;
            string publishLine = publish.GetValueKind() == System.Text.Json.JsonValueKind.String
                ? "publish: \"true"                    // "unreadable": the unclosed quote
                : $"publish: {(publish.GetValue<bool>() ? "true" : "false")}";
            string created = k["created"] is { } date ? $"created: {date}\n" : "";
            File.WriteAllText(Path.Combine(dir, k["title"] + ".md"),
                $"---\ntitle: {k["title"]}\n{publishLine}\n{created}---\n", new UTF8Encoding(false));
        }
        string index = Path.Combine(course, $"section{section}", "index.md");
        File.WriteAllText(index, c["indexText"]!.ToString(), new UTF8Encoding(false));
        if (c["declined"] is JsonObject declined)
        {
            Directory.CreateDirectory(Path.Combine(course, ".publish_state"));
            File.WriteAllText(Path.Combine(course, ".publish_state", $"section{section}.front-page-not-today.json"),
                new JsonObject { ["version"] = "1", ["day"] = declined["day"]!.ToString(), ["class"] = declined["class"]!.ToString() }.ToJsonString());
        }
        return (new AssistWorkspace(root, new FakeLauncher()), index, section);
    }

    [Fact]
    public void EveryCaseIsAskedAndAnsweredAsTheContractSays()
    {
        var cases = Rule["cases"]!.AsArray();
        Assert.True(cases.Count >= 42, $"todaysClassOnTheFrontPage.cases lost cases: {cases.Count}");
        var failures = new List<string>();
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            var (workspace, index, section) = LayOut(c, name);
            var today = DateOnly.Parse(c["today"]!.ToString());
            var offer = workspace.TodaysClassOffer("ICS3U", section, today);
            var expect = c["expectAsk"];
            if (expect is null)
            {
                if (offer is not null) failures.Add($"{name}: asked about {offer.Show}, expected no question");
                continue;
            }
            if (offer is null) { failures.Add($"{name}: not asked, expected {expect["show"]} for {expect["shows"]}"); continue; }
            if (offer.Show != expect["show"]!.ToString() || offer.Shows != expect["shows"]!.ToString())
            {
                failures.Add($"{name}: offered {offer.Show} for {offer.Shows}, expected {expect["show"]} for {expect["shows"]}");
                continue;
            }
            if (c["expectAfterYes"] is not JsonObject after) continue;
            var outcome = workspace.ShowTodaysClass("ICS3U", section, today, offer);
            string written = File.ReadAllText(index);
            if (outcome is not TodaysClassOnTheFrontPage.Outcome.Written) failures.Add($"{name}: Yes gave {outcome}");
            if (Body(written) != after["body"]!.ToString())
                failures.Add($"{name}: body\n  expected {System.Text.Json.JsonSerializer.Serialize(after["body"]!.ToString())}\n  got      {System.Text.Json.JsonSerializer.Serialize(Body(written))}");
            if (CreatedDay(written) != after["createdDay"]!.ToString())
                failures.Add($"{name}: created {CreatedDay(written)}, expected {after["createdDay"]}");
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }

    [Fact]
    public void NotTodayIsRememberedForThatDayAndClassAndSaid()
    {
        var c = Rule["cases"]!.AsArray().First(k => k!["name"]!.ToString().StartsWith("the ordinary morning"))!;
        var (workspace, _, section) = LayOut(c, "not today");
        var today = DateOnly.Parse(c["today"]!.ToString());
        var offer = workspace.TodaysClassOffer("ICS3U", section, today)!;
        workspace.DeclineTodaysClass("ICS3U", section, today, offer);
        Assert.Null(workspace.TodaysClassOffer("ICS3U", section, today));
        Assert.NotNull(workspace.TodaysClassOffer("ICS3U", section, today.AddDays(1)) ?? offer);   // another day is a new question (no class then: nothing)
        Assert.Contains("left the front page as it was — Not Today: Unit 2, Day 5 offered, it showed Unit 2, Day 4", File.ReadAllText(_trail));
    }

    [Fact]
    public void AnAnswerAfterTheClassChangedWritesNothing()
    {
        var c = Rule["cases"]!.AsArray().First(k => k!["name"]!.ToString().StartsWith("the ordinary morning"))!;
        var (workspace, index, section) = LayOut(c, "changed");
        var today = DateOnly.Parse(c["today"]!.ToString());
        var offer = workspace.TodaysClassOffer("ICS3U", section, today)!;
        string before = File.ReadAllText(index);
        // After midnight: decided again for the day ASKED, still Yes-able —
        // but answered as if for tomorrow, no class is today's, nothing written.
        Assert.IsType<TodaysClassOnTheFrontPage.Outcome.NoLongerOffered>(
                     workspace.ShowTodaysClass("ICS3U", section, today.AddDays(3), offer));
        Assert.Equal(before, File.ReadAllText(index));
    }

    [Fact]
    public void TheSentencesAreTheContracts()
    {
        var w = Rule["wording"]!;
        Assert.Equal(w["question"]!.ToString().Replace("{class}", "X"), TodaysClassOnTheFrontPage.Question("X"));
        Assert.Equal(w["because"]!.ToString().Replace("{noun}", "meeting").Replace("{shown}", "Y"),
                     TodaysClassOnTheFrontPage.Because(ClassNoun.Meeting, "Y"));
        Assert.Equal(w["show"]!.ToString(), TodaysClassOnTheFrontPage.Show);
        Assert.Equal(w["notToday"]!.ToString(), TodaysClassOnTheFrontPage.NotToday);
        Assert.Equal(w["notChangedTitle"]!.ToString(), TodaysClassOnTheFrontPage.NotChangedTitle);
        Assert.Equal(w["noLongerOffered"]!.ToString().Replace("{noun}", "class"), TodaysClassOnTheFrontPage.NoLongerOffered(ClassNoun.Class));
        Assert.Equal(w["couldNotSave"]!.ToString().Replace("{shown}", "Y"), TodaysClassOnTheFrontPage.CouldNotSave("Y"));

        // The kept-file alert (#899 W7b2-9, Russell's ruling of 2026-11-25 (a)).
        Assert.Equal(w["keptTitle"]!.ToString().Replace("{class}", "X"), TodaysClassOnTheFrontPage.KeptTitle("X"));
        Assert.Equal(w["kept"]!.ToString().Replace("{kept}", "K"), TodaysClassOnTheFrontPage.KeptSentence("K"));
        Assert.Equal(w["keptGone"]!.ToString().Replace("{kept}", "K"), TodaysClassOnTheFrontPage.KeptGoneSentence("K"));
        // showKept is the one key Windows says in its own words: the button
        // opens the folder, never the file (keptOnWindows.showKept), the path
        // bar's open action.
        var onWindows = Rule["keptOnWindows"]!;
        Assert.Equal(onWindows["showKept"]!.ToString(), TodaysClassOnTheFrontPage.OpenKeptFolder);
        Assert.Equal(onWindows["hiddenItems"]!.ToString(), TodaysClassOnTheFrontPage.HiddenItems);
        var pathBarOpen = ContractLoader.LoadJson("shared-rules.json")["workingFolderPathBar"]!["actions"]!.AsArray()
            .First(action => action!["action"]!.ToString() == "open")!;
        Assert.Equal(pathBarOpen["windowsLabel"]!.ToString(), TodaysClassOnTheFrontPage.OpenKeptFolder);

        // Every key the contract has is compared above or held by name in
        // NamedGapLedger: a key added on the mac turns this red rather than
        // passing unseen. A held key fails the day it is said here.
        var saidHere = new[] { "question", "because", "show", "notToday", "notChangedTitle", "noLongerOffered", "couldNotSave",
                               "keptTitle", "kept", "showKept", "keptGone" };
        var keys = w.AsObject().Select(pair => pair.Key).ToList();
        var held = NamedGapLedger.GapsIn(NamedGapLedger.TodaysClassWording, keys, saidHere);
        foreach (string key in keys)
            Assert.True(saidHere.Contains(key) || held.Contains(key), $"todaysClassOnTheFrontPage.wording.{key} is neither said here nor held");
    }

    /// <summary>
    /// The kept-file alert's message (#899 W7b2-9): one <c>kept</c> sentence
    /// per kept name, then the sentence that says how to see hidden items,
    /// since the file stays hidden on Windows (Russell's ruling of 2026-11-25 (a)).
    /// </summary>
    [Fact]
    public void TheKeptAlertNamesTheFileThenSaysHowToSeeHiddenItems()
    {
        var w = Rule["wording"]!;
        string name = ".index.md.plantoir-undo-0123-orig";
        string expected = w["kept"]!.ToString().Replace("{kept}", name) + " " + Rule["keptOnWindows"]!["hiddenItems"]!.ToString();
        Assert.Equal(expected, TodaysClassOnTheFrontPage.KeptMessage([name]));
    }

    /// <summary>
    /// The kept-file alert's make-up, read without a screen (W7b2-9 review 1,
    /// MEDIUM 1): titled with the class the page NOW shows (<c>Show</c>, never
    /// <c>Shows</c>), the message, Open Folder as the action, and OK as the
    /// closing button and the default, so Enter and Escape are both OK.
    /// </summary>
    [Fact]
    public void TheKeptAlertIsTitledWithTheClassNowShownWithOkTheDefaultAndTheClose()
    {
        var w = Rule["wording"]!;
        var offer = new TodaysClassOnTheFrontPage.Offering("Unit 2, Day 5", "Unit 2, Day 4", Path.Combine(_folder, "Unit 2, Day 5.md"));
        string kept = Path.Combine(_folder, ".index.md.plantoir-undo-1-apply-orig");

        var alert = TodaysClassOnTheFrontPage.KeptAlertFor(offer, new TodaysClassOnTheFrontPage.Outcome.ShownWithWhatItHeldKept([kept]));

        Assert.Equal(new TodaysClassOnTheFrontPage.AlertDescription(
                         w["keptTitle"]!.ToString().Replace("{class}", "Unit 2, Day 5"),
                         TodaysClassOnTheFrontPage.KeptMessage([".index.md.plantoir-undo-1-apply-orig"]),
                         Rule["keptOnWindows"]!["showKept"]!.ToString(),
                         "OK",
                         TodaysClassOnTheFrontPage.AlertButton.Close),
                     alert.Shows);
        Assert.Equal([kept], alert.KeptOriginals);
    }

    /// <summary>The <c>keptGone</c> alert: its sentences alone, with OK as the closing button and the default, and no action.</summary>
    [Fact]
    public void TheGoneAlertSaysItsSentenceWithOkAlone()
    {
        string sentence = Rule["wording"]!["keptGone"]!.ToString().Replace("{kept}", "K");
        Assert.Equal(new TodaysClassOnTheFrontPage.AlertDescription(null, sentence, null, "OK", TodaysClassOnTheFrontPage.AlertButton.Close),
                     TodaysClassOnTheFrontPage.GoneAlert(sentence));
    }

    /// <summary>
    /// The section window only renders the description (read from source:
    /// the WinUI app cannot be loaded here). Each line that maps a field to
    /// the dialog, or wires the press, is pinned whole, and each appears once.
    /// </summary>
    [Fact]
    public void TheSectionWindowOnlyRendersTheKeptAlertsDescription()
    {
        string view = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "Views", "SectionDetailView.xaml.cs"))
                          .Replace("\r\n", "\n");   // a Windows checkout has CRLF
        string[] lines =
        [
            "                var alert = TodaysClassOnTheFrontPage.KeptAlertFor(offer, kept);\n",
            "                await alert.PressedAsync(await ShowAlertAsync(alert.Shows), ShowAlertAsync, FolderActions.OpenFolder);\n",
            "            Title = alert.Title,\n",
            "            Content = new TextBlock { Text = alert.Message, TextWrapping = TextWrapping.Wrap },\n",
            "            CloseButtonText = alert.CloseButton,\n",
            "            DefaultButton = alert.Default == TodaysClassOnTheFrontPage.AlertButton.Action ? ContentDialogButton.Primary : ContentDialogButton.Close,\n",
            "        if (alert.ActionButton is { } action) dialog.PrimaryButtonText = action;\n",
            "            ContentDialogResult.Primary => TodaysClassOnTheFrontPage.AlertButton.Action,\n",
            "            ContentDialogResult.None => TodaysClassOnTheFrontPage.AlertButton.Close,\n",
            "            _ => null,\n",
        ];
        foreach (string line in lines)
        {
            int first = view.IndexOf(line, StringComparison.Ordinal);
            Assert.True(first >= 0, "missing: " + line.Trim());
            if (line.Contains("alert", StringComparison.Ordinal))
                Assert.True(view.IndexOf(line, first + 1, StringComparison.Ordinal) < 0, "said twice: " + line.Trim());
        }
        Assert.DoesNotContain("ShowInFileExplorer", view[view.IndexOf("KeptAlertFor(", StringComparison.Ordinal)..view.IndexOf("ShowAlertAsync(TodaysClassOnTheFrontPage.AlertDescription", StringComparison.Ordinal)]);
    }

    /// <summary>
    /// No sentence of the kept-file alert says a word <c>plainWordsCheck</c>
    /// rules out (the mac's T3 list), checked FILLED; the one exception is a
    /// name the contract lists in <c>plainWordsExceptions</c> (W7b2-9 review 1, LOW 1).
    /// </summary>
    [Fact]
    public void NoKeptAlertSentenceSaysATechnicalWord()
    {
        string[] words = ["transclude", "transcludes", "transcluded", "transclusion", "transclusions",
                          "embed", "embeds", "embedded", "index", "file", "frontmatter", "link"];
        string plain = Rule["plainWordsCheck"]!.ToString();
        foreach (string word in new[] { "transclude", "embed", "index", "file", "frontmatter", "link" })
            Assert.Contains($"“{word}”", plain);
        var exceptions = new List<string>();
        foreach (JsonNode? exception in Rule["plainWordsExceptions"]!.AsArray()) exceptions.Add(exception!["name"]!.ToString());
        Assert.Equal(["File Explorer"], exceptions);

        string[] sentences =
        [
            TodaysClassOnTheFrontPage.KeptTitle("Unit 2, Day 5"),
            TodaysClassOnTheFrontPage.KeptMessage(["KEPT"]),
            TodaysClassOnTheFrontPage.OpenKeptFolder,
            TodaysClassOnTheFrontPage.KeptGoneSentence("KEPT"),
        ];
        foreach (string sentence in sentences)
        {
            string checkedText = sentence;
            foreach (string name in exceptions) checkedText = checkedText.Replace(name, " ", StringComparison.Ordinal);
            var said = new HashSet<string>();
            foreach (string piece in System.Text.RegularExpressions.Regex.Split(checkedText.ToLowerInvariant(), "[^\\p{L}]+"))
                if (piece.Length > 0) said.Add(piece);
            foreach (string word in words)
                Assert.False(said.Contains(word), $"“{sentence}” says “{word}”");
        }
    }

    /// <summary>
    /// Asked from the section window's Preview button and NOTHING else: no
    /// file but the section window and the workspace wrapper names the offer.
    /// The mac pins the same with a source test on <c>startPreview()</c>.
    /// </summary>
    [Fact]
    public void OnlyThePreviewButtonAsks()
    {
        string repo = ContractLoader.RepositoryRoot;
        var callers = Directory.GetFiles(Path.Combine(repo, "windows-app"), "*.cs", SearchOption.AllDirectories)
            .Where(f => !f.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}")
                        && !f.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")
                        && !f.Contains("Plantoir.Tests") && !f.Contains("Plantoir.UiTests"))
            .Where(f => File.ReadAllText(f).Contains("TodaysClassOffer(", StringComparison.Ordinal))
            .Select(Path.GetFileName)
            .OrderBy(n => n)
            .ToList();
        Assert.Equal(new[] { "AssistWorkspace.cs", "SectionDetailView.xaml.cs" }, callers);
    }

    private static string Body(string page)
    {
        if (!page.StartsWith("---", StringComparison.Ordinal)) return page;
        int end = page.IndexOf("\n---", 3, StringComparison.Ordinal);
        int after = page.IndexOf('\n', end + 1);
        return after < 0 ? "" : page[(after + 1)..];
    }

    private static string? CreatedDay(string page)
    {
        foreach (string raw in page.Split('\n').Skip(1))
        {
            string line = raw.TrimEnd('\r');
            if (line.Trim() == "---") break;
            if (line.StartsWith("created:", StringComparison.Ordinal))
            {
                string value = line["created:".Length..].Trim().Trim('"', '\'');
                return value.Length >= 10 ? value[..10] : value;
            }
        }
        return null;
    }
}

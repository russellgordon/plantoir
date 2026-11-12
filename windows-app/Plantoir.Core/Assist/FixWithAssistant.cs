using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Assist;

/// <summary>
/// Fix with Claude… and Fix with Codex… on a section's Problems tab (#736,
/// the mac's #717 part two): the problems a teacher ticked, handed to an
/// outside assistant they already have through the SAME two doors as Revise
/// With ▸ (<see cref="ClaudeCodeLauncher"/>, <see cref="CodexLauncher"/>),
/// with an opening message that lists them in place of the plain greeting.
/// </summary>
/// <remarks>
/// <para>Every word here is <c>contracts/app-rules.json</c> →
/// <c>outsideAgents.fixWith</c>, as constants pinned key by key by
/// <c>FixWithAssistantContractTests</c>, which also runs its
/// <c>buttonCases</c> and <c>greetingCases</c>. The mac's counterpart is
/// <c>FixWithAssistant.swift</c>, ported function for function.</para>
///
/// <para><b>Characters are the mac's</b> (<c>fixWith.charactersAre</c>):
/// Swift counts grapheme clusters, so every bound here counts text elements
/// (<see cref="StringInfo"/>), not <see cref="string.Length"/> — an emoji is
/// one character to a teacher and two or more UTF-16 units. The whole
/// command line's UTF-16 length is a SECOND bound, which the door supplies
/// (<c>fits</c>): when it bites first, rows go from the end, said with
/// <see cref="More"/>, exactly as the character bound does.</para>
/// </remarks>
public static class FixWithAssistant
{
    /// <summary>Which door a button opens.</summary>
    public enum Assistant { Claude, Codex }

    /// <summary>The rows a press would hand over, and what it leaves out.</summary>
    public sealed record Handover(IReadOnlyList<SectionProblemRow> Rows, int Unticked, int FixedInTheSource)
    {
        /// <summary>Whether the buttons can be pressed.</summary>
        public bool HasRows => Rows.Count > 0;
    }

    /// <summary>The message, and how many of the handed rows it names.</summary>
    public sealed record Greeting(string Text, int RowsNamed, int RowsNotNamed);

    /// <summary>Whether each button shows, and whether they can be pressed (they are enabled together).</summary>
    public sealed record ButtonState(bool ClaudeShown, bool CodexShown, bool Enabled);

    // ---- The contract's words and bounds (fixWith) --------------------------

    public const string ClaudeButtonTitle = "Fix with Claude…";
    public const string CodexButtonTitle = "Fix with Codex…";

    /// <summary>
    /// What a button that cannot be pressed says to assistive technology
    /// (<c>fixWith.notEnabledHelp</c>, proposed from Windows with #736): a
    /// greyed button alone tells a Narrator user nothing.
    /// </summary>
    public const string NotEnabledHelp = "Tick a problem this section still has to hand it over.";
    public const int MostRowsInThePrompt = 10;
    public const int GreetingMaxCharacters = 6500;
    public const int PagePlaceMaxCharacters = 300;
    public const int CourseNameMaxCharacters = 80;

    /// <summary>cmd's command line, in UTF-16 units (<c>fixWith.charactersAre</c>).</summary>
    public const int CommandLineMaxUtf16 = 8191;

    public static readonly IReadOnlyList<(string From, string To)> ReplaceInTheMessage = new[]
    {
        ("\"", "'"),
        (";", ","),
    };

    public static readonly IReadOnlySet<string> DeployOnlyKinds = new HashSet<string>(StringComparer.Ordinal)
    {
        "filesTooLargeForCloudflare",
    };

    public static readonly IReadOnlyDictionary<string, string> SkillForKind = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        ["figuresCouldNotBeDrawn"] = "plantoir-math-graphs",
        ["geogebraSketchesNotReady"] = "plantoir-math-graphs",
        ["swiftCouldNotBePrepared"] = "plantoir-runnable-code",
        ["runnableCodeShownAsPlainCode"] = "plantoir-runnable-code",
        ["quizzesNotReady"] = "plantoir-quizzes",
        ["quizzesReadDifferently"] = "plantoir-quizzes",
        ["printPdfNotFound"] = "plantoir-printing",
    };

    public const string OtherwiseSkill = "plantoir-page-authoring";

    // The message's pieces (fixWith.fixGreeting), with the contract's own
    // {placeholders} so the pin compares them as written.
    public const string OpeningOne =
        "I'm a teacher working on {course} in Plantoir. The last {occasion} of Section {section} found a problem on its website that I'd like your help to fix: ";
    public const string OpeningSeveral =
        "I'm a teacher working on {course} in Plantoir. The last {occasion} of Section {section} found problems on its website that I'd like your help to fix: ";
    public const string RowWithAPage = "{number}) {prompt} (page: {file}{shared}, skill: {skill})";
    public const string RowWithoutAPage = "{number}) {prompt} (skill: {skill})";
    public const string SharedPage = ", a page shared by every section";
    public const string RowSeparator = " · ";
    public const string More = " · and {count} more on the Problems tab";
    public const string AfterTheRows =
        ". Use the plantoir tools for anything to do with this course, and the skill named for each problem, which knows what this site can show. ";
    public const string PlanFirst =
        " Before changing anything, show me in plain words what you will change, using the matching plan tool where there is one, and wait for me to agree. ";
    public const string ClosingPreview = "When you are done, preview Section {section} so its Problems tab clears.";
    public const string ClosingDeploy = "When you are done, deploy Section {section} to Cloudflare again so its Problems tab clears.";
    public const string ClosingBoth =
        "When you are done, preview Section {section} and then deploy it to Cloudflare again so its Problems tab clears.";

    // ---- Which rows, which buttons --------------------------------------------

    /// <summary>
    /// The rows a press hands over: ticked (a row nobody unticked is ticked,
    /// sectionProblems ruling 6), and not fixed in the source — another
    /// section's later build shows the page right, so this one needs only a
    /// build, and an assistant asked to fix it might change something that is
    /// not broken looking for the fault.
    /// </summary>
    public static Handover HandoverOf(IEnumerable<SectionProblemRow> rows, Func<string, bool> isTicked,
                                      Func<SectionProblemRow, SectionProblemsRules.RowState> stateOf)
    {
        var handed = new List<SectionProblemRow>();
        int unticked = 0, fixedInTheSource = 0;
        foreach (var row in rows)
        {
            if (!isTicked(row.Id)) { unticked++; continue; }
            if (stateOf(row) == SectionProblemsRules.RowState.FixedInTheSource) { fixedInTheSource++; continue; }
            handed.Add(row);
        }
        return new Handover(handed, unticked, fixedInTheSource);
    }

    /// <summary>The same, for a record and the other sections' records, which decide "fixed in the source".</summary>
    public static Handover HandoverOf(SectionProblemsRecord record, IReadOnlyList<SectionProblemsRecord> others,
                                      Func<string, bool> isTicked) =>
        HandoverOf(record.Rows, isTicked, row => SectionProblemsRules.State(row, record, others));

    /// <summary>
    /// <c>fixWith.buttonCases</c>: a button shows while its assistant is
    /// installed (hidden, never greyed, <c>hiddenWhenNotInstalled</c>) and
    /// never on a course kept for reference; both are enabled while a row is
    /// handed over.
    /// </summary>
    public static ButtonState Buttons(bool claudeInstalled, bool codexInstalled, bool keptForReference, Handover handover) =>
        new(claudeInstalled && !keptForReference, codexInstalled && !keptForReference, handover.HasRows);

    // ---- The message -------------------------------------------------------------

    /// <summary>The skill named for a kind.</summary>
    public static string SkillFor(string kind) => SkillForKind.TryGetValue(kind, out var skill) ? skill : OtherwiseSkill;

    /// <summary>Whether a page is the course's own rather than one section's: a section's pages live under <c>section&lt;N&gt;/</c>.</summary>
    public static bool IsSharedByEverySection(string page)
    {
        if (page.Length == 0) return false;
        if (!page.StartsWith("section", StringComparison.Ordinal)) return true;
        bool sawADigit = false;
        foreach (char character in page["section".Length..])
        {
            if (character == '/') return !sawADigit;
            if (character is >= '0' and <= '9') { sawADigit = true; continue; }
            return true;
        }
        return true;
    }

    /// <summary>Where a page is, from the working folder the session opens in, its place cut at <see cref="PagePlaceMaxCharacters"/>.</summary>
    public static string FileOf(string page, string courseCode) =>
        $"courses/{courseCode}/{Cut(page, PagePlaceMaxCharacters)}.md";

    /// <summary>The closing: a preview clears most problems, only a deploy clears Cloudflare's refusal, and a mix says both.</summary>
    public static string ClosingFor(IEnumerable<SectionProblemRow> rows)
    {
        bool preview = false, deploy = false;
        foreach (var row in rows)
        {
            if (DeployOnlyKinds.Contains(row.Kind)) deploy = true;
            else preview = true;
        }
        return deploy && preview ? ClosingBoth : deploy ? ClosingDeploy : ClosingPreview;
    }

    /// <summary>One numbered row. A prompt's own closing full stop is dropped, so the row never reads ". (".</summary>
    public static string RowText(SectionProblemRow row, int number, string courseCode)
    {
        string prompt = row.Prompt;
        if (prompt.Length == 0) prompt = row.Item.Length == 0 ? row.Sentence : row.Item;
        if (prompt.EndsWith('.')) prompt = prompt[..^1];
        if (row.Page.Length == 0)
            return Fill(RowWithoutAPage, new() { ["{number}"] = number.ToString(CultureInfo.InvariantCulture), ["{prompt}"] = prompt, ["{skill}"] = SkillFor(row.Kind) });
        return Fill(RowWithAPage, new()
        {
            ["{number}"] = number.ToString(CultureInfo.InvariantCulture),
            ["{prompt}"] = prompt,
            ["{file}"] = FileOf(row.Page, courseCode),
            ["{shared}"] = IsSharedByEverySection(row.Page) ? SharedPage : "",
            ["{skill}"] = SkillFor(row.Kind),
        });
    }

    /// <summary>
    /// The opening message for <paramref name="rows"/>, or null when there are
    /// none. Rows are named in order until <see cref="MostRowsInThePrompt"/>
    /// are, or until the next would take the message past
    /// <see cref="GreetingMaxCharacters"/>, or past what <paramref name="fits"/>
    /// allows (the door's whole command line, in UTF-16 units); the first is
    /// always named and the rest are "and N more on the Problems tab".
    /// </summary>
    public static Greeting? GreetingFor(IReadOnlyList<SectionProblemRow> rows, string courseCode, string courseName,
                                        int sectionNumber, string occasion, Func<string, bool>? fits = null)
    {
        if (rows.Count == 0) return null;
        var greeting = Compose(rows, courseCode, courseName, sectionNumber, occasion, MostRowsInThePrompt);
        while (fits is not null && !fits(greeting.Text) && greeting.RowsNamed > 1)
        {
            var fewer = Compose(rows, courseCode, courseName, sectionNumber, occasion, greeting.RowsNamed - 1);
            if (fewer.RowsNamed >= greeting.RowsNamed) break;
            greeting = fewer;
        }
        return greeting;
    }

    private static Greeting Compose(IReadOnlyList<SectionProblemRow> rows, string courseCode, string courseName,
                                    int sectionNumber, string occasion, int mostNamed)
    {
        string courseNamed = courseCode;
        string name = Cut(courseName.Trim(), CourseNameMaxCharacters);
        if (name.Length > 0 && name != courseCode) courseNamed += $" ({name})";
        string section = sectionNumber.ToString(CultureInfo.InvariantCulture);
        string opening = Fill(rows.Count == 1 ? OpeningOne : OpeningSeveral, new()
        {
            ["{course}"] = courseNamed,
            ["{occasion}"] = occasion == "deploy" ? "deploy" : "preview",
            ["{section}"] = section,
        });
        string ending = AfterTheRows + ClaudeCodeLauncher.HowITeachSentence + PlanFirst
                        + Fill(ClosingFor(rows), new() { ["{section}"] = section });

        var named = new List<string>();
        int length = Characters(opening) + Characters(ending);
        foreach (var row in rows)
        {
            if (named.Count == mostNamed) break;
            string text = RowText(row, named.Count + 1, courseCode);
            int separator = named.Count == 0 ? 0 : Characters(RowSeparator);
            int remainingAfterThis = rows.Count - named.Count - 1;
            int more = remainingAfterThis > 0 ? Characters(MoreText(remainingAfterThis)) : 0;
            if (named.Count > 0 && length + separator + Characters(text) + more > GreetingMaxCharacters) break;
            named.Add(text);
            length += separator + Characters(text);
        }

        var message = new StringBuilder(opening).Append(string.Join(RowSeparator, named));
        int notNamed = rows.Count - named.Count;
        if (notNamed > 0) message.Append(MoreText(notNamed));
        message.Append(ending);
        return new Greeting(Replaced(message.ToString()), named.Count, notNamed);
    }

    /// <summary><c>fixWith.replaceInTheMessage</c>, over the whole message: each replacement keeps the length.</summary>
    public static string Replaced(string message)
    {
        foreach (var (from, to) in ReplaceInTheMessage) message = message.Replace(from, to, StringComparison.Ordinal);
        return message;
    }

    private static string MoreText(int count) => Fill(More, new() { ["{count}"] = count.ToString(CultureInfo.InvariantCulture) });

    // ---- The trail ---------------------------------------------------------------

    /// <summary>
    /// The trail's line (<c>activityTrail.mustRecord</c> → "asked an assistant
    /// to fix problems"), after the course and section the trail adds: which
    /// assistant, how many rows went and of what KINDS, how many the message
    /// names and how many were left out — never a page, which is the
    /// teacher's own name, and never a row's words.
    /// </summary>
    public static string TrailLine(Assistant assistant, Handover handover, Greeting greeting)
    {
        var kinds = new List<string>();
        foreach (var row in handover.Rows)
            if (!kinds.Contains(row.Kind)) kinds.Add(row.Kind);
        int count = handover.Rows.Count;
        string problems = count == 1 ? "1 problem" : $"{count} problems";
        return $"asked {NameOf(assistant)} to fix {problems} ({string.Join(", ", kinds)}); "
               + $"named in the message: {greeting.RowsNamed}; left out: {handover.Unticked} unticked, "
               + $"{handover.FixedInTheSource} fixed in the source";
    }

    /// <summary>Writes that line, for a door that opened.</summary>
    public static void NoteOnTheTrail(Assistant assistant, Handover handover, Greeting greeting, string courseCode, int sectionNumber) =>
        ActivityTrail.Note(ActivityTrail.Event.AskedAnAssistantToFixProblems, TrailLine(assistant, handover, greeting),
                           courseCode, sectionNumber);

    /// <summary>The product's name, as the trail line says it.</summary>
    public static string NameOf(Assistant assistant) => assistant == Assistant.Claude ? "Claude" : "Codex";

    /// <summary>A button's title (<c>fixWith.buttons[].title</c>).</summary>
    public static string TitleOf(Assistant assistant) => assistant == Assistant.Claude ? ClaudeButtonTitle : CodexButtonTitle;

    // ---- Text ------------------------------------------------------------------------

    /// <summary>
    /// Each <c>{key}</c> in <paramref name="template"/> replaced by its value in
    /// ONE pass: a value is never searched again, so a row whose own words
    /// carry <c>{section}</c> (TeX has braces everywhere) goes over as written.
    /// </summary>
    public static string Fill(string template, Dictionary<string, string> values)
    {
        var text = new StringBuilder();
        int at = 0;
        while (at < template.Length)
        {
            int open = template.IndexOf('{', at);
            if (open < 0) break;
            text.Append(template, at, open - at);
            int close = template.IndexOf('}', open);
            if (close < 0) { text.Append(template, open, template.Length - open); return text.ToString(); }
            string key = template[open..(close + 1)];
            text.Append(values.TryGetValue(key, out var value) ? value : key);
            at = close + 1;
        }
        if (at < template.Length) text.Append(template, at, template.Length - at);
        return text.ToString();
    }

    /// <summary>Characters as Swift counts them: grapheme clusters, here text elements.</summary>
    public static int Characters(string text) => new StringInfo(text).LengthInTextElements;

    /// <summary>Cut to at most <paramref name="most"/> characters, the last of them an ellipsis.</summary>
    internal static string CutToCharacters(string text, int most) => Cut(text, most);

    private static string Cut(string text, int most)
    {
        var info = new StringInfo(text);
        return info.LengthInTextElements <= most ? text : info.SubstringByTextElements(0, most - 1) + "…";
    }
}

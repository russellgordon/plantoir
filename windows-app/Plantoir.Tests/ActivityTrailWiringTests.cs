using System.Text.RegularExpressions;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// Pins that the activity trail is WIRED, not merely declared — the Windows
/// twin of the mac's <c>ActivityTrailWiringTests.testEveryEventIsReferencedSomewhereInProductCode</c>
/// (<c>documentation/12-windows-app.md</c> → "Two testing rules that cost time
/// to learn").
///
/// <para>This side found the gap first (2026-08-19): three events sat in
/// <see cref="ActivityTrail.Event"/>, the contract test compared the enum with
/// <c>shared-rules.json</c> → <c>activityTrail.mustRecord</c> and passed, and
/// nothing ever CALLED them. A list-against-list pin cannot see that; a source
/// scan can. Its honest limit: it proves a call site EXISTS, not that it is
/// reached.</para>
///
/// <para>An event the contract names that this app has not DECLARED is not this
/// test's business — <c>ContractTests.SharedRules_ActivityTrailEvents_Exist</c>
/// fails for it, or <see cref="NamedGapLedger"/> holds it open by name. So
/// together the two say: every event the contract asks of Windows is either
/// declared AND referenced by product code, or ledgered against the issue that
/// owes it.</para>
/// </summary>
public class ActivityTrailWiringTests
{
    /// <summary>
    /// Events recorded through a helper that writes the line itself rather
    /// than through <c>Note(Event.X, …)</c>, each with the helper that is its
    /// call site. The helper must itself be called from product code.
    /// </summary>
    private static readonly Dictionary<ActivityTrail.Event, string> RecordedThroughAHelper = new()
    {
        // NotePrompt writes "asked a question" plus the redacted sentence on
        // its own marked line; it is the "assistant asked" event's writer.
        [ActivityTrail.Event.AssistantAsked] = "ActivityTrail.NotePrompt(",
    };

    private static string ProductSourceRoot
    {
        get
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            for (int i = 0; i < 10 && dir is not null; i++, dir = dir.Parent)
            {
                string candidate = Path.Combine(dir.FullName, "windows-app", "Plantoir.Core");
                if (Directory.Exists(candidate)) return Path.Combine(dir.FullName, "windows-app");
            }
            throw new DirectoryNotFoundException("Could not find windows-app/ above the test assembly.");
        }
    }

    /// <summary>Every product .cs file: Plantoir.Core, Plantoir, Plantoir.Mcp, PtyDriver — never a test project, never build output.</summary>
    private static List<string> ProductFiles() =>
        Directory.EnumerateFiles(ProductSourceRoot, "*.cs", SearchOption.AllDirectories)
            .Where(path => !path.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}")
                           && !path.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")
                           && !path.Contains("Plantoir.Tests")
                           && !path.Contains("Plantoir.UiTests"))
            .ToList();

    /// <summary>
    /// Product source with every comment and string literal taken out, so a
    /// name mentioned in a comment, a doc line or a string is not mistaken for
    /// a call (bundle 1 review: <c>_ = "ActivityTrail.Event.X";</c> kept the
    /// first version of this scan green).
    /// </summary>
    /// <remarks>
    /// One FILE at a time, in one left-to-right pass, so a <c>//</c> comment or
    /// a string is recognised before anything inside it can open a block
    /// comment. The scan this replaced (#580) stripped <c>/* … */</c> across
    /// every file joined together BEFORE <c>//</c> lines, so <c>support/**</c>
    /// in a <c>///</c> line swallowed the files after it and the test blamed
    /// four events in other files. A <c>/*</c> that never closes now fails the
    /// test naming its file.
    /// </remarks>
    private static string Code(IEnumerable<string> files)
    {
        var all = new System.Text.StringBuilder();
        foreach (string file in files)
        {
            all.Append(Stripped(File.ReadAllText(file), file)).Append('\n');
        }
        return all.ToString();
    }

    /// <summary>One file's source with its comments and string and character literals taken out.</summary>
    internal static string Stripped(string source, string file)
    {
        var code = new System.Text.StringBuilder(source.Length);
        int i = 0;
        int n = source.Length;
        while (i < n)
        {
            char c = source[i];
            char next = i + 1 < n ? source[i + 1] : '\0';
            if (c == '/' && next == '/')
            {
                while (i < n && source[i] != '\n') i++;
                continue;
            }
            if (c == '/' && next == '*')
            {
                int close = source.IndexOf("*/", i + 2, StringComparison.Ordinal);
                if (close < 0)
                    throw new Xunit.Sdk.XunitException(
                        $"{file}: a /* at offset {i} never closes, so the trail-wiring scan cannot read what follows it.");
                code.Append(' ');
                i = close + 2;
                continue;
            }
            // String prefixes: $, @, $@, @$, and $$… for raw strings.
            int start = i;
            bool verbatim = false;
            while (i < n && (source[i] == '$' || source[i] == '@'))
            {
                if (source[i] == '@') verbatim = true;
                i++;
            }
            if (i < n && source[i] == '"')
            {
                int quotes = 0;
                while (i + quotes < n && source[i + quotes] == '"') quotes++;
                if (quotes >= 3)
                {
                    // A raw string literal: closed by the same run of quotes.
                    string fence = new string('"', quotes);
                    int close = source.IndexOf(fence, i + quotes, StringComparison.Ordinal);
                    i = close < 0 ? n : close + quotes;
                    code.Append("\"\"");
                    continue;
                }
                i++;
                while (i < n)
                {
                    if (verbatim)
                    {
                        if (source[i] == '"' && i + 1 < n && source[i + 1] == '"') { i += 2; continue; }
                        if (source[i] == '"') break;
                    }
                    else
                    {
                        if (source[i] == '\\') { i += 2; continue; }
                        if (source[i] == '"' || source[i] == '\n') break;
                    }
                    i++;
                }
                i++;
                code.Append("\"\"");
                continue;
            }
            if (i > start)
            {
                // A $ or @ that did not start a string (@this, an identifier).
                code.Append(source, start, i - start);
                continue;
            }
            if (c == '\'')
            {
                var literal = Regex.Match(source.Substring(i, Math.Min(8, n - i)), @"^'(?:\\.[^']*|[^'\\\n])'");
                if (literal.Success)
                {
                    code.Append("' '");
                    i += literal.Length;
                    continue;
                }
            }
            code.Append(c);
            i++;
        }
        return code.ToString();
    }

    [Fact]
    public void TheScanReadsAStarStarInACommentAsAComment()
    {
        string stripped = Stripped(
            "/// copies <c>support/**</c> from it\nNote(Event.A, \"x\");\n// a \"quote\nNote(Event.B, '\\'', \"//y\", @\"a\"\"b\", \"\"\"\nraw /* \n\"\"\");\n/* gone */ Note(Event.C);\n",
            "sample.cs");
        Assert.Contains("Note(Event.A", stripped);
        Assert.Contains("Note(Event.B", stripped);
        Assert.Contains("Note(Event.C", stripped);
        Assert.DoesNotContain("gone", stripped);
        Assert.DoesNotContain("raw", stripped);
        var unclosed = Assert.Throws<Xunit.Sdk.XunitException>(() => Stripped("a /* b", "late.cs"));
        Assert.Contains("late.cs", unclosed.Message);
    }

    /// <summary>
    /// The shapes that record an event: the event as <c>Note(</c>'s first
    /// argument (qualified or not, on the same line or the next), or the value
    /// a switch arm hands on to a <c>Note</c> call (<c>=&gt; ActivityTrail.Event.X</c>,
    /// how <c>ScheduledPublishOutcome</c> picks its event). <c>KeyFor</c>'s
    /// arms have the event on the LEFT of <c>=&gt;</c> and so do not count.
    /// </summary>
    private static bool IsRecorded(string code, ActivityTrail.Event ev)
    {
        string name = @"(?:Plantoir\.Core\.Scripting\.)?(?:ActivityTrail\.)?Event\." + ev + @"\b";
        return Regex.IsMatch(code, @"\bNote\(\s*" + name)
            || Regex.IsMatch(code, @"=>\s*" + name + @"\s*[,;}]");
    }

    [Fact]
    public void EveryDeclaredEventIsReferencedSomewhereInProductCode()
    {
        var files = ProductFiles();
        Assert.True(files.Count > 100,
            $"Only {files.Count} product source files were found under {ProductSourceRoot}; the scan below would pass vacuously.");
        string code = Code(files);

        var unreferenced = Enum.GetValues<ActivityTrail.Event>()
            .Where(ev => !(RecordedThroughAHelper.TryGetValue(ev, out var helper)
                ? Regex.IsMatch(code, Regex.Escape(helper))
                : IsRecorded(code, ev)))
            .Select(ev => $"{ev} (\"{ActivityTrail.KeyFor(ev)}\")")
            .ToList();

        Assert.True(unreferenced.Count == 0,
            "These trail events are declared but nothing in the app refers to them, so nothing can ever record " +
            "them: " + string.Join(", ", unreferenced) + ". Wire a call site (ActivityTrail.Note(ActivityTrail.Event.X, …)) " +
            "as part of the feature, or remove the event — and if the contract still names it, ledger it in " +
            "NamedGapLedger against the issue that owes it rather than declaring it empty.");
    }

    [Fact]
    public void EveryHelperNamedHereStillWritesItsEvent()
    {
        string source = File.ReadAllText(Path.Combine(ProductSourceRoot, "Plantoir.Core", "Scripting", "ActivityTrail.cs"));
        foreach (var (ev, helper) in RecordedThroughAHelper)
        {
            string name = helper[(helper.IndexOf('.') + 1)..].TrimEnd('(');
            Assert.True(source.Contains($"public static void {name}(", StringComparison.Ordinal),
                $"RecordedThroughAHelper says {helper} records {ev}, and ActivityTrail no longer has it.");
        }
    }
}

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
    private static string Code(IEnumerable<string> files)
    {
        string all = string.Join("\n", files.Select(File.ReadAllText));
        all = Regex.Replace(all, @"/\*.*?\*/", " ", RegexOptions.Singleline);
        all = Regex.Replace(all, @"@""(?:""""|[^""])*""", "\"\"");
        all = Regex.Replace(all, @"""(?:\\.|[^""\\\n])*""", "\"\"");
        all = Regex.Replace(all, @"'(?:\\.|[^'\\\n])'", "' '");
        all = Regex.Replace(all, @"//[^\n]*", "");
        return all;
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

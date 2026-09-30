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
    /// The lines that could be a call: not a comment, not the enum's
    /// <c>KeyFor</c> arm (<c>Event.X =&gt; "…"</c>), which is declaration.
    /// </summary>
    private static List<string> CallableLines(IEnumerable<string> files) =>
        files.SelectMany(File.ReadAllLines)
            .Select(line => line.Trim())
            .Where(line => !line.StartsWith("//"))
            .Where(line => !Regex.IsMatch(line, @"^Event\.\w+\s*=>"))
            .ToList();

    [Fact]
    public void EveryDeclaredEventIsReferencedSomewhereInProductCode()
    {
        var files = ProductFiles();
        Assert.True(files.Count > 100,
            $"Only {files.Count} product source files were found under {ProductSourceRoot}; the scan below would pass vacuously.");
        var lines = CallableLines(files);

        var unreferenced = Enum.GetValues<ActivityTrail.Event>()
            .Where(ev => !(RecordedThroughAHelper.TryGetValue(ev, out var helper)
                ? lines.Any(line => line.Contains(helper, StringComparison.Ordinal))
                : lines.Any(line => Regex.IsMatch(line, @"\bEvent\." + ev + @"\b"))))
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

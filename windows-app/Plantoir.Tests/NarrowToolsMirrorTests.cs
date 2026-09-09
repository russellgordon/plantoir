using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Plantoir.Core.Assist;

namespace Plantoir.Tests;

/// <summary>
/// The routing measurements are run through <c>research/ai-assist/narrow-tools.py</c>,
/// which hand-copies two things out of <see cref="AssistAgent"/>: the set of
/// tools the local model is shown, and the example course code that is
/// rewritten to the teacher's own. This pins that copy.
///
/// <para><b>Why it exists.</b> The copy had already drifted, and the drift was
/// invisible. The Python was committed on 2026-08-14 holding FIFTEEN names,
/// which was right at the time; <c>ForTheLocalModel</c> dropped to THIRTEEN on
/// 2026-08-17 (4089c752) — out went four <c>plan_</c> tools, in came
/// <c>read_remembered_timetable</c> and <c>add_next_class</c> — and the Python
/// was not followed through. So any routing score taken through it AFTER that
/// date was a score for a surface the app does not ship, and — worse for the
/// change that found this on 2026-09-08 — blind to the two tools that were
/// being measured. <c>routing-suite.py</c>'s own docstring calls that worse
/// than no score, because it reads as evidence. The three results files
/// measured in the 2026-08-14 to 17 window are sound and are named in the
/// Python's own docstring, so nobody discards them on the strength of this.</para>
///
/// <para>Nothing in a research script can fail on its own: those files are run
/// by hand, months apart, by whoever is measuring. So the guard has to live in
/// a suite that runs on every commit, and this is it.</para>
///
/// <para><b>What is deliberately NOT pinned.</b> <c>Briefly()</c> is private
/// and its Python twin is checked by eye. Pinning it would mean exposing it or
/// duplicating its rules here, and the failure it would catch — a differently
/// trimmed description — changes the measurement's absolute score without
/// hiding a tool, which is the milder of the two mistakes.</para>
/// </summary>
public class NarrowToolsMirrorTests
{
    private static string RepoRoot
    {
        get
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            for (int i = 0; i < 8 && dir is not null; i++, dir = dir.Parent)
            {
                if (File.Exists(Path.Combine(dir.FullName, "Dockerfile")))
                    return dir.FullName;
            }
            throw new DirectoryNotFoundException("Could not find repository root containing Dockerfile.");
        }
    }

    private static string NarrowToolsSource =>
        File.ReadAllText(Path.Combine(RepoRoot, "research", "ai-assist", "narrow-tools.py"));

    [Fact]
    public void TheMeasurementScriptShowsTheModelExactlyTheToolsTheAppDoes()
    {
        var mirrored = NamesIn(NarrowToolsSource, "FOR_THE_LOCAL_MODEL");

        var missing = AssistAgent.ForTheLocalModel.Except(mirrored, StringComparer.Ordinal).Order().ToList();
        var extra = mirrored.Except(AssistAgent.ForTheLocalModel, StringComparer.Ordinal).Order().ToList();

        Assert.True(missing.Count == 0 && extra.Count == 0,
            "research/ai-assist/narrow-tools.py no longer mirrors AssistAgent.ForTheLocalModel, so any "
            + "routing score measured through it is a score for a surface the app does not ship.\n"
            + $"  the app shows {AssistAgent.ForTheLocalModel.Count} tools, the script keeps {mirrored.Count}\n"
            + (missing.Count > 0 ? $"  shipped but NOT measured: {string.Join(", ", missing)}\n" : "")
            + (extra.Count > 0 ? $"  measured but NOT shipped: {string.Join(", ", extra)}\n" : "")
            + "Update FOR_THE_LOCAL_MODEL in that file, and re-run any measurement that predates the change.");
    }

    [Fact]
    public void TheMeasurementScriptRewritesTheSameExampleCourseTheAppDoes()
    {
        var declared = Regex.Match(NarrowToolsSource, "EXAMPLE_COURSE\\s*=\\s*\"([^\"]+)\"");
        Assert.True(declared.Success, "narrow-tools.py no longer declares EXAMPLE_COURSE.");
        string mirrored = declared.Groups[1].Value;

        // Fed through the real narrowing, the script's example course must be
        // the token that actually gets replaced. If AssistAgent.ExampleCourse
        // changes, this stops being true and the script starts measuring a
        // surface naming a course the teacher does not have.
        string name = AssistAgent.ForTheLocalModel.Order().First();
        var tools = new JsonArray
        {
            new JsonObject
            {
                ["type"] = "function",
                ["function"] = new JsonObject
                {
                    ["name"] = name,
                    ["description"] = $"TEACHERS SAY: \"do the thing\". Works on {mirrored} only. Ignored.",
                    ["parameters"] = new JsonObject
                    {
                        ["type"] = "object",
                        ["properties"] = new JsonObject
                        {
                            ["course"] = new JsonObject
                            {
                                ["type"] = "string",
                                ["description"] = $"The course code, for example {mirrored}.",
                            },
                        },
                    },
                },
            },
        };

        var narrowed = AssistAgent.NarrowToLocal(tools, "ZZZ9Z");
        string described = narrowed[0]!["function"]!["description"]!.GetValue<string>();
        string argument = narrowed[0]!["function"]!["parameters"]!["properties"]!["course"]!["description"]!
            .GetValue<string>();

        Assert.False(described.Contains(mirrored, StringComparison.Ordinal),
            $"narrow-tools.py rewrites \"{mirrored}\" but AssistAgent leaves it in the description, so the "
            + "measured surface names a course no teacher has.");
        Assert.False(argument.Contains(mirrored, StringComparison.Ordinal),
            $"narrow-tools.py rewrites \"{mirrored}\" in argument descriptions but AssistAgent does not.");
    }

    /// <summary>
    /// Every quoted string inside the named Python set literal, comments
    /// stripped first. The set is commented per group, and a future comment
    /// quoting a phrasing — <c># kept for "publish tomorrow's class"</c> —
    /// would otherwise be read as a tool name and fail this test while
    /// blaming something else entirely.
    /// </summary>
    private static HashSet<string> NamesIn(string source, string setName)
    {
        int start = source.IndexOf(setName + " = {", StringComparison.Ordinal);
        Assert.True(start >= 0, $"narrow-tools.py no longer declares {setName}.");
        int open = source.IndexOf('{', start);
        int close = source.IndexOf('}', open);
        Assert.True(close > open, $"{setName} in narrow-tools.py is not a closed set literal.");

        string body = Regex.Replace(source[open..close], "#[^\n]*", "");

        var found = new HashSet<string>(StringComparer.Ordinal);
        foreach (Match quoted in Regex.Matches(body, "\"([^\"]+)\""))
            found.Add(quoted.Groups[1].Value);
        return found;
    }
}

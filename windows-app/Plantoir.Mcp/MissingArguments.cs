using System.Reflection;
using System.Text.Json;
using ModelContextProtocol.Server;
using Plantoir.Core.Assist;

namespace Plantoir.Mcp;

/// <summary>
/// A tool call that leaves out <c>section</c> (or, for the <c>add_classes</c>
/// pair, <c>unit</c> or <c>howMany</c>) is answered truthfully, BEFORE the
/// tool is dispatched (#885, the mac's #865). Without this the MCP SDK
/// (ModelContextProtocol 2.2.0) refuses the call while binding, and the
/// assistant reads only "An error occurred invoking '&lt;tool&gt;'.": nothing
/// planned or deployed, but nothing said about what was missing either.
/// </summary>
/// <remarks>
/// <para><b>What it says</b>, as the mac's <c>AssistToolRunner.locate</c> and
/// <c>addClassesQuestion</c> do: the course first (its own refusal from
/// <see cref="AssistWorkspace.Course"/>, <c>noCourseNamed</c> included), then
/// a course with ONE section is answered for it (the section is supplied), a
/// course with none says <c>noSectionNamedAndNoSections</c>, and any other says
/// <c>noSectionNamed</c> with its sections; then, for <c>add_classes</c> and
/// <c>plan_add_classes</c> only, <c>addClassesNeedsAUnit</c> and
/// <c>addClassesNeedsACount</c>. Another tool that requires <c>unit</c> keeps
/// the SDK's answer. A call that names its section is untouched, a section
/// that is not there included (it keeps <see cref="AssistWorkspace.Section"/>'s
/// sentence).</para>
/// <para><b>Nothing a model is shown moves.</b> No schema, description or
/// tool list is touched: <c>section</c> stays a required <c>int</c> (an
/// <c>int?</c> would change <c>tools/list</c>, which the built-in assistant's
/// window reads too, and the generated <c>toolSchemas</c>). The window's own
/// assistant never meets these answers: <c>AssistAgent.BoundToThisWindow</c>
/// writes its course and section into every call whose tool declares them,
/// and its 13 local tools do not include the <c>add_classes</c> pair.</para>
/// <para><b>Which tools</b> is read off each tool's own parameters by
/// reflection (a parameter with no default is required), never a list, so a
/// tool added later is covered.</para>
/// </remarks>
public static class MissingArguments
{
    /// <summary>The arguments this filter looks for.</summary>
    private static readonly string[] Watched = { "course", "section", "unit", "howMany" };

    /// <summary>The two tools whose missing <c>unit</c> or <c>howMany</c> is asked about.</summary>
    public static readonly IReadOnlySet<string> AddClassesTools =
        new HashSet<string>(StringComparer.Ordinal) { "add_classes", "plan_add_classes" };

    private static readonly Lazy<IReadOnlyDictionary<string, IReadOnlySet<string>>> Served = new(() => RequiredBy(typeof(PlantoirTools)));

    /// <summary>For each tool <paramref name="toolType"/> serves, which of course, section, unit and howMany it REQUIRES.</summary>
    public static IReadOnlyDictionary<string, IReadOnlySet<string>> RequiredBy(Type toolType)
    {
        var required = new Dictionary<string, IReadOnlySet<string>>(StringComparer.Ordinal);
        foreach (var method in toolType.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static))
        {
            if (method.GetCustomAttribute<McpServerToolAttribute>() is not { Name: { } name }) continue;
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (var parameter in method.GetParameters())
                if (parameter.Name is { } p && Watched.Contains(p) && !parameter.HasDefaultValue) names.Add(p);
            required[name] = names;
        }
        return required;
    }

    /// <summary>What the filter does with one call.</summary>
    /// <param name="Refusal">The sentence to answer with, the tool not run; null to run it.</param>
    /// <param name="Arguments">The arguments to run it with: the call's own, or with the one section supplied.</param>
    public sealed record Outcome(string? Refusal, Dictionary<string, JsonElement>? Arguments);

    /// <summary>
    /// The answer for <paramref name="tool"/> called with <paramref name="arguments"/>,
    /// read against <paramref name="workspace"/>; <paramref name="required"/>
    /// defaults to what this server's tools require.
    /// </summary>
    public static Outcome For(string tool, Dictionary<string, JsonElement>? arguments, AssistWorkspace workspace,
                              IReadOnlyDictionary<string, IReadOnlySet<string>>? required = null)
    {
        var pass = new Outcome(null, arguments);
        if (!(required ?? Served.Value).TryGetValue(tool, out var needs)) return pass;
        bool noSection = needs.Contains("section") && Missing(arguments, "section");
        bool asks = AddClassesTools.Contains(tool);
        bool noUnit = asks && needs.Contains("unit") && Missing(arguments, "unit");
        // A count of 0 or less is asked about too, as the mac's
        // addClassesQuestion asks (no contract case covers it).
        bool noCount = asks && needs.Contains("howMany") && (Missing(arguments, "howMany") || NotACount(arguments!["howMany"]));
        if (!noSection && !noUnit && !noCount) return pass;
        if (!needs.Contains("course")) return pass;

        Plantoir.Core.Models.Course course;
        try
        {
            string code = arguments is not null && arguments.TryGetValue("course", out var value)
                          && value.ValueKind == JsonValueKind.String ? value.GetString() ?? "" : "";
            course = workspace.Course(code);
        }
        catch (AssistRefusal refusal) { return new Outcome(refusal.Message, arguments); }

        var supplied = arguments;
        if (noSection)
        {
            var numbers = course.SectionNumbers.OrderBy(n => n).ToList();
            if (numbers.Count == 0) return new Outcome(AssistWording.NoSectionNamedAndNoSections(course.Code), arguments);
            if (numbers.Count > 1) return new Outcome(AssistWording.NoSectionNamed(course.Code, SectionsPhrase(numbers)), arguments);
            supplied = arguments is null ? new() : new Dictionary<string, JsonElement>(arguments);
            supplied["section"] = JsonSerializer.SerializeToElement(numbers[0]);
        }
        if (noUnit) return new Outcome(AssistWording.AddClassesNeedsAUnit, supplied);
        if (noCount) return new Outcome(AssistWording.AddClassesNeedsACount, supplied);
        return new Outcome(null, supplied);
    }

    /// <summary>
    /// Everything the server's call-tool filter asks before a tool runs, in
    /// the mac's order (its two gates in <c>AssistToolRunner.run</c>, then
    /// <c>locate</c> inside the tool): the one section SUPPLIED first, so the
    /// gates and <c>AfterCall</c> read the section the tool will run with;
    /// then <see cref="ReferenceWriteGate"/> (nothing writes to a course kept
    /// for reference, and a settings file that cannot be read keeps its
    /// fail-safe sentence); then <see cref="OutsideChangeGate"/> (an outside
    /// change while the course is being built is held back, #436); and only
    /// then <see cref="For"/>'s own refusal. Until the batch review's M1 the
    /// refusal came first, and a reference course was asked to choose a
    /// section that would then be refused anyway.
    /// </summary>
    public static Outcome InFrontOfTheTool(string tool, Dictionary<string, JsonElement>? arguments, AssistWorkspace workspace)
    {
        var missing = For(tool, arguments, workspace);
        var runWith = missing.Arguments;
        string? refusal = ReferenceWriteGate.Refusal(tool, runWith, workspace)
                          ?? OutsideChangeGate.Refusal(tool, runWith, workspace)
                          ?? missing.Refusal;
        return new Outcome(refusal, runWith);
    }

    /// <summary>"Sections 1 and 2", "Sections 1, 2 and 3" (the mac's form; a lone section is never said, it is supplied).</summary>
    public static string SectionsPhrase(IReadOnlyList<int> numbers)
    {
        var text = new System.Text.StringBuilder(numbers.Count == 1 ? "Section " : "Sections ");
        for (int i = 0; i < numbers.Count; i++)
        {
            if (i > 0) text.Append(i == numbers.Count - 1 ? " and " : ", ");
            text.Append(numbers[i].ToString(System.Globalization.CultureInfo.InvariantCulture));
        }
        return text.ToString();
    }

    /// <summary>A number of 0 or less, as a JSON number or a string of digits; anything else is left to the SDK.</summary>
    private static bool NotACount(JsonElement value) =>
        value.ValueKind == JsonValueKind.Number ? value.TryGetDouble(out double n) && n <= 0
        : value.ValueKind == JsonValueKind.String && int.TryParse(value.GetString(), out int m) && m <= 0;

    private static bool Missing(Dictionary<string, JsonElement>? arguments, string key) =>
        arguments is null || !arguments.TryGetValue(key, out var value)
        || value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined;
}

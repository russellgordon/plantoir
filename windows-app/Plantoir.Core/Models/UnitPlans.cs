using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Plantoir.Core.Assist;

namespace Plantoir.Core.Models;

/// <summary>
/// A course's unit plans (#790, the mac's #707): what the
/// <c>plantoir-unit-planning</c> skill writes into
/// <c>courses/&lt;CODE&gt;/.internal/planning/</c>, as far as the app needs to
/// know about it: which units have a plan, so a Revise door's greeting can
/// name them and the course page's Planning tab can offer them.
/// </summary>
/// <remarks>
/// <para>The app never writes a plan. Each unit's folder holds a small
/// <c>plan.json</c> (<c>contracts/shared-rules.json</c> →
/// <c>unitPlanning.planFile</c>), read here against its rules and walked by
/// <c>UnitPlansTests</c> through <c>unitPlanning.planFileCases</c>; the
/// greeting's sentence is <c>app-rules.json</c> →
/// <c>outsideAgents.greetingUnitPlans</c>, walked through both doors by
/// <c>greetingUnitPlansCases</c>. Ported function for function from the mac's
/// <c>UnitPlans.swift</c>.</para>
///
/// <para><b>Reading never throws.</b> A plan file that cannot be read, or that
/// breaks a rule, is left out and COUNTED, so the trail can say so: an opening
/// message is no place to report a broken file, and a door that refused to
/// open over one would be worse.</para>
///
/// <para><b>A unit folder that is a link (a junction or a symbolic link) is not
/// read</b>, as on the mac, whose directory listing reports a symbolic link as
/// not a folder. A link there is either a mistake or points somewhere the plan
/// does not own. A link is <see cref="FileSystemInfo.LinkTarget"/> not null,
/// never the reparse-point attribute alone: a OneDrive placeholder carries that
/// attribute and is not a link.</para>
/// </remarks>
public static class UnitPlans
{
    /// <summary>The folder under a course, <c>unitPlanning.folder</c> after <c>courses/&lt;CODE&gt;/</c>.</summary>
    public static readonly string FolderPath = Path.Combine(".internal", "planning");

    /// <summary><c>unitPlanning.planFile.name</c>.</summary>
    public const string PlanFileName = "plan.json";

    /// <summary><c>unitPlanning.slugRules.pattern</c>.</summary>
    public const string SlugPattern = "^[a-z][a-z0-9-]{0,39}$";

    /// <summary><c>unitPlanning.neverSlugs</c>: folder names that are never a unit, the stylesheets' own first.</summary>
    public static readonly IReadOnlyList<string> NeverSlugs = new[] { "assets", "build", "dist", "node_modules", "out", "__pycache__" };

    /// <summary><c>outsideAgents.greetingUnitPlans.unitNameMaxCharacters</c>, counted as <c>fixWith.charactersAre</c> says.</summary>
    public const int UnitNameMaxCharacters = 60;

    /// <summary><c>outsideAgents.greetingUnitPlans.mostUnitsNamed</c>.</summary>
    public const int MostUnitsNamed = 6;

    // The sentences, verbatim from outsideAgents.greetingUnitPlans. Since #708
    // `one` and `some` point at the course's Planning tab. They are
    // instructions to the assistant, in the teacher's voice, asking it to SAY
    // one sentence in its first reply (707 plan review M3).

    public const string NoneSentence =
        "In your first reply, also tell me in one sentence that you can help me plan a unit for this course, "
        + "from a calendar across my sections to a plan page with lesson cards and assessment drafts, "
        + "and that I start by asking you to plan one.";

    public const string OneSentence =
        "In your first reply, also remind me in one sentence that this course has a unit plan for {units}, "
        + "which I can see on the course's Planning tab in Plantoir, and do not describe what is in it.";

    public const string SomeSentence =
        "In your first reply, also remind me in one sentence that this course has unit plans for {units}, "
        + "which I can see on the course's Planning tab in Plantoir, and do not describe what is in them.";

    /// <summary><c>greetingUnitPlans.more</c>, after the last unit named.</summary>
    public const string MoreClause = ", and {n} more";

    // greetingUnitPlans.trail.
    public const string TrailSeparator = " · ";
    public const string TrailNone = "told about unit planning";
    public const string TrailOne = "reminded of 1 unit plan";
    public const string TrailSeveral = "reminded of {n} unit plans";
    public const string TrailUnreadable = "{n} plan.json could not be read";

    private static readonly Regex Slug = new(SlugPattern, RegexOptions.CultureInvariant);

    /// <summary>One unit's plan, as its <c>plan.json</c> describes it.</summary>
    public sealed record Plan(string Slug, string Unit, string Title, DateOnly? FirstClass, DateOnly? LastClass,
                              IReadOnlyList<string> Sections);

    /// <summary>The plans of one course, sorted, and how many plan files were left out.</summary>
    public sealed record Reading(IReadOnlyList<Plan> Plans, int Unreadable);

    // ---- Reading -------------------------------------------------------------

    /// <summary>The planning folder of a course folder.</summary>
    public static string PlanningFolder(string courseDirectory) => Path.Combine(courseDirectory, FolderPath);

    /// <summary>
    /// The plans in a course folder, in the order the greeting names them
    /// (<see cref="SortedForTheGreeting"/>), and how many plan files were left
    /// out because they could not be read or broke a rule. Never throws.
    /// </summary>
    public static Reading Read(string courseDirectory)
    {
        var plans = new List<Plan>();
        int unreadable = 0;
        IEnumerable<string> folders;
        try
        {
            string planning = PlanningFolder(courseDirectory);
            if (!Directory.Exists(planning)) return new Reading(plans, 0);
            folders = Directory.GetDirectories(planning);
        }
        catch { return new Reading(plans, 0); }

        foreach (string folder in folders)
        {
            string slug = Path.GetFileName(folder);
            if (!IsUnitSlug(slug)) continue;
            try
            {
                if (new DirectoryInfo(folder).LinkTarget is not null) continue;
                string planFile = Path.Combine(folder, PlanFileName);
                if (!File.Exists(planFile)) continue;
                Plan? plan = PlanFrom(slug, File.ReadAllBytes(planFile));
                if (plan is null) { unreadable++; continue; }
                plans.Add(plan);
            }
            catch { unreadable++; }
        }
        return new Reading(SortedForTheGreeting(plans), unreadable);
    }

    /// <summary>
    /// What a Revise door on this course should be told, or null when it is
    /// told nothing: a course kept for reference has no door at all. With more
    /// plans than the greeting names they are put in <see cref="NamedFirst"/>
    /// order for <paramref name="today"/>, so the ones named are the ones that
    /// matter now (707a review M2).
    /// </summary>
    public static Reading? ToMention(string courseDirectory, bool isKeptForReference, DateOnly today)
    {
        if (isKeptForReference) return null;
        var reading = Read(courseDirectory);
        if (reading.Plans.Count <= MostUnitsNamed) return reading;
        return reading with { Plans = NamedFirst(reading.Plans, today) };
    }

    /// <summary>A folder name the skill may give a unit, and the app reads as one (<c>slugRules</c>, <c>neverSlugs</c>).</summary>
    /// <remarks>.NET's <c>$</c> also matches before a final line break, which the mac's does not, so one is refused here by hand.</remarks>
    public static bool IsUnitSlug(string name) =>
        !NeverSlugs.Contains(name, StringComparer.Ordinal) && !name.EndsWith('\n') && Slug.IsMatch(name);

    /// <summary>
    /// One plan file read against <c>unitPlanning.planFile</c>, or null when it
    /// breaks a rule: not a JSON object; <c>unit</c> or <c>title</c> present but
    /// not text, or both empty once on one line; a date present but not a real
    /// <c>yyyy-mm-dd</c> day; <c>sections</c> present but not a list of text.
    /// Unknown keys are ignored, so a later release can add one.
    /// </summary>
    public static Plan? PlanFrom(string slug, byte[] json)
    {
        try
        {
            // A UTF-8 byte order mark, which Windows editors write, is skipped
            // as the mac's JSONSerialization skips it: JsonDocument refuses one
            // (measured: a plan saved with it read as unreadable).
            ReadOnlyMemory<byte> bytes = json;
            if (json.Length >= 3 && json[0] == 0xEF && json[1] == 0xBB && json[2] == 0xBF) bytes = bytes[3..];
            using var document = JsonDocument.Parse(bytes);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return null;
            if (!OptionalText(root, "unit", out string unit) || !OptionalText(root, "title", out string title)) return null;
            unit = OneLine(unit);
            title = OneLine(title);
            if (unit.Length == 0 && title.Length == 0) return null;
            if (!OptionalDay(root, "firstClass", out DateOnly? firstClass)
                || !OptionalDay(root, "lastClass", out DateOnly? lastClass)
                || !OptionalDay(root, "updated", out _)) return null;
            var sections = new List<string>();
            if (root.TryGetProperty("sections", out var listed) && listed.ValueKind != JsonValueKind.Null)
            {
                if (listed.ValueKind != JsonValueKind.Array) return null;
                foreach (var item in listed.EnumerateArray())
                {
                    if (item.ValueKind != JsonValueKind.String) return null;
                    sections.Add(item.GetString()!);
                }
            }
            return new Plan(slug, unit, title, firstClass, lastClass, sections);
        }
        // InvalidOperationException too (790a review M1): JsonDocument accepts
        // an escaped lone surrogate ("\ud800") and a raw byte that is not
        // UTF-8 inside a string, and GetString throws on them. Such a file is
        // a plan that cannot be read, like any other broken one.
        catch (Exception e) when (e is JsonException or InvalidOperationException) { return null; }
    }

    /// <summary>The same, from the file's text.</summary>
    public static Plan? PlanFrom(string slug, string json) => PlanFrom(slug, Encoding.UTF8.GetBytes(json));

    /// <summary>
    /// A plan's <c>unit</c> or <c>title</c> on one line
    /// (<c>greetingUnitPlans.nameForm</c>): every run of white space, as
    /// <see cref="char.IsWhiteSpace(string, int)"/> reads Unicode's White_Space
    /// property, becomes one space, and the ends are trimmed, so the greeting
    /// and the trail stay one line (707a review M1; the <c>cmd /k</c> door
    /// cannot carry a line break). The mac runs its course-name cleaner
    /// (<c>OneLineText.cleaned</c>, #780) first; on Windows that cleaner is
    /// #821's and is the first step to add here when it lands.
    /// </summary>
    public static string OneLine(string text)
    {
        var result = new StringBuilder(text.Length);
        bool lastWasSpace = false;
        for (int i = 0; i < text.Length; i++)
        {
            if (char.IsWhiteSpace(text, i))
            {
                if (!lastWasSpace) result.Append(' ');
                lastWasSpace = true;
            }
            else
            {
                result.Append(text[i]);
                lastWasSpace = false;
            }
        }
        return result.ToString().Trim(' ');
    }

    // ---- Which unit is current -----------------------------------------------

    /// <summary>
    /// Whether <paramref name="plan"/> covers <paramref name="today"/>: its
    /// first class on or before today and its last class on or after, both days
    /// included. A plan with only one of its two dates is read as starting and
    /// ending on that day; a plan with neither covers no day. ONE rule for the
    /// greeting's order (<see cref="NamedFirst"/>) and for the entry the
    /// Planning tab starts on (<see cref="PlanningTab.StartingChoice"/>), so the
    /// two cannot disagree about which unit is current (#820 item 1).
    /// </summary>
    public static bool Covers(Plan plan, DateOnly today)
    {
        if ((plan.FirstClass ?? plan.LastClass) is not { } start || (plan.LastClass ?? plan.FirstClass) is not { } end) return false;
        return start <= today && today <= end;
    }

    /// <summary>
    /// The order for a course with more plans than the greeting names
    /// (<c>greetingUnitPlans.order</c>): the plans covering today first (by
    /// first class), then the upcoming ones soonest first, then the past ones
    /// most recent first (by last class), then the undated; a tie by folder name.
    /// </summary>
    public static IReadOnlyList<Plan> NamedFirst(IEnumerable<Plan> plans, DateOnly today)
    {
        var current = new List<Plan>();
        var upcoming = new List<Plan>();
        var past = new List<Plan>();
        var undated = new List<Plan>();
        foreach (var plan in plans)
        {
            if ((plan.FirstClass ?? plan.LastClass) is not { } start || (plan.LastClass ?? plan.FirstClass) is not { } end)
                undated.Add(plan);
            else if (Covers(plan, today)) current.Add(plan);
            else if (end < today) past.Add(plan);
            else if (today < start) upcoming.Add(plan);
        }
        var ordered = new List<Plan>(SortedForTheGreeting(current));
        ordered.AddRange(SortedForTheGreeting(upcoming));
        ordered.AddRange(past
            .OrderByDescending(p => (p.LastClass ?? p.FirstClass)!.Value)
            .ThenBy(p => p.Slug, StringComparer.Ordinal));
        ordered.AddRange(SortedForTheGreeting(undated));
        return ordered;
    }

    /// <summary>Dated plans first, by their first class; then the undated; a tie by folder name, ordinal.</summary>
    public static IReadOnlyList<Plan> SortedForTheGreeting(IEnumerable<Plan> plans) =>
        plans.OrderBy(p => p.FirstClass is null ? 1 : 0)
             .ThenBy(p => p.FirstClass ?? DateOnly.MinValue)
             .ThenBy(p => p.Slug, StringComparer.Ordinal)
             .ToList();

    // ---- The greeting's sentence and the trail -------------------------------

    /// <summary>
    /// "Unit 3: Chemical Reactions", or whichever half is there
    /// (<c>greetingUnitPlans.nameForm</c>), cut at
    /// <see cref="UnitNameMaxCharacters"/> text elements with the last an
    /// ellipsis, so the greeting has a bound whatever a plan is called. The
    /// Planning tab's popup labels its entries with this too.
    /// </summary>
    public static string NameInTheGreeting(Plan plan)
    {
        string name = plan.Unit.Length > 0 && plan.Title.Length > 0 ? plan.Unit + ": " + plan.Title
                    : plan.Unit.Length > 0 ? plan.Unit : plan.Title;
        return FixWithAssistant.CutToCharacters(name, UnitNameMaxCharacters);
    }

    /// <summary>
    /// "A", "A and B", "A, B and C"; past <see cref="MostUnitsNamed"/>, the
    /// first six and ", and N more" (<c>joinedAs</c>). A door whose command
    /// line the names would push past cmd's limit asks for fewer
    /// (<paramref name="mostNamed"/>, 790a review M2), and the rest are counted
    /// into the same <c>more</c> clause, as <c>fixWith.charactersAre</c> says.
    /// </summary>
    public static string UnitsInTheGreeting(IReadOnlyList<Plan> plans, int mostNamed = MostUnitsNamed)
    {
        var names = plans.Take(Math.Clamp(mostNamed, 1, MostUnitsNamed)).Select(NameInTheGreeting).ToList();
        int left = plans.Count - names.Count;
        if (left > 0) return string.Join(", ", names) + MoreClause.Replace("{n}", left.ToString(CultureInfo.InvariantCulture));
        if (names.Count <= 1) return string.Concat(names);
        return string.Join(", ", names.Take(names.Count - 1)) + " and " + names[^1];
    }

    /// <summary>The sentence the greeting ends with: <c>none</c>, <c>one</c> or <c>some</c>.</summary>
    public static string GreetingSentence(IReadOnlyList<Plan> plans, int mostNamed = MostUnitsNamed)
    {
        if (plans.Count == 0) return NoneSentence;
        return (plans.Count == 1 ? OneSentence : SomeSentence).Replace("{units}", UnitsInTheGreeting(plans, mostNamed));
    }

    /// <summary>
    /// What a Revise door's "assistant opened" line gains
    /// (<c>greetingUnitPlans.trail</c>): which sentence was said, and how many
    /// plan files were left out. Counts only, never a plan's name.
    /// </summary>
    public static string TrailClause(Reading reading)
    {
        string clause = TrailSeparator + (reading.Plans.Count switch
        {
            0 => TrailNone,
            1 => TrailOne,
            int n => TrailSeveral.Replace("{n}", n.ToString(CultureInfo.InvariantCulture)),
        });
        if (reading.Unreadable > 0)
            clause += TrailSeparator + TrailUnreadable.Replace("{n}", reading.Unreadable.ToString(CultureInfo.InvariantCulture));
        return clause;
    }

    // ---- The rules for one key -----------------------------------------------

    /// <summary>A key that, when present and not null, must be text. Absent or null reads as empty text.</summary>
    private static bool OptionalText(JsonElement root, string key, out string text)
    {
        text = "";
        if (!root.TryGetProperty(key, out var value) || value.ValueKind == JsonValueKind.Null) return true;
        if (value.ValueKind != JsonValueKind.String) return false;
        text = value.GetString()!;
        return true;
    }

    /// <summary>A key that, when present and not null, must be a real day written exactly yyyy-mm-dd.</summary>
    private static bool OptionalDay(JsonElement root, string key, out DateOnly? day)
    {
        day = null;
        if (!root.TryGetProperty(key, out var value) || value.ValueKind == JsonValueKind.Null) return true;
        if (value.ValueKind != JsonValueKind.String) return false;
        string text = value.GetString()!;
        if (!DateOnly.TryParseExact(text, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var read)) return false;
        if (read.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) != text) return false;
        day = read;
        return true;
    }
}

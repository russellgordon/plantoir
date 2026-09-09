using System.Reflection;
using System.Text.RegularExpressions;
using System.Text.Json.Nodes;
using ModelContextProtocol.Server;
using Plantoir.Core.Assist;
using Plantoir.Mcp;

namespace Plantoir.Tests;

/// <summary>
/// The assistant's SURFACE — the tools each client is shown, and what a
/// teacher is told about which assistant they are running.
///
/// <para>Adding a tool is a routing change, and more choices is the classic
/// way a router degrades, so the shape of this surface is a product decision
/// rather than an implementation detail. `assist-cases.json` →
/// <c>toolSchemas</c> carries the definitions as each client really sends
/// them, and nothing on this side read them (documentation/10-local-ai-assistant.md).</para>
///
/// <para><b>The descriptions are deliberately NOT asserted, and that is the
/// interesting part.</b> This app has no local tool definitions of its own:
/// <c>AssistAgent.NarrowToLocal</c> takes the MCP server's schemas, keeps
/// thirteen by name and rewrites every description through <c>Briefly()</c>,
/// which strips all but the routing phrasings — a measured decision, not a
/// stylistic one. Asserting the mac's wording here would be red on all
/// thirteen, and "fixing" it would change the text the local model routes on,
/// which needs the routing suite re-run rather than a test edited. So what is
/// pinned is the part that is shared by construction: WHICH tools, and what
/// each one's arguments are.</para>
/// </summary>
public class AssistSurfaceContractTests
{
    /// <summary>
    /// Every tool this app's MCP server declares, by name, with its parameters
    /// read off the real method signature.
    ///
    /// <para>Reflection over <see cref="PlantoirTools"/> rather than starting
    /// the server and asking it: driving <c>plantoir-mcp</c> over stdio works
    /// and leaves a process holding <c>Plantoir.Core.dll</c> open if anything
    /// goes wrong, which then fails the NEXT build with a file-lock error that
    /// reads as "the app is open" when the app is not open at all.</para>
    /// </summary>
    private static Dictionary<string, MethodInfo> ServedTools()
    {
        var tools = new Dictionary<string, MethodInfo>(StringComparer.Ordinal);
        foreach (var method in typeof(PlantoirTools).GetMethods(BindingFlags.Public | BindingFlags.Instance))
        {
            var attribute = method.GetCustomAttribute<McpServerToolAttribute>();
            if (attribute is null) continue;
            // The SDK falls back to the method name when the attribute gives
            // none; matching that means a tool declared without a Name is
            // COUNTED rather than silently skipped, which would otherwise read
            // as the contract and the server agreeing.
            tools[attribute.Name ?? method.Name] = method;
        }
        return tools;
    }

    /// <summary>The JSON schema type a parameter of this CLR type is sent as.</summary>
    private static string SchemaType(Type type)
    {
        var underlying = Nullable.GetUnderlyingType(type) ?? type;
        if (underlying == typeof(string)) return "string";
        if (underlying == typeof(bool)) return "boolean";
        if (underlying == typeof(int) || underlying == typeof(long)) return "integer";
        if (underlying == typeof(double) || underlying == typeof(float)) return "number";
        if (underlying.IsArray || (underlying.IsGenericType
            && typeof(System.Collections.IEnumerable).IsAssignableFrom(underlying))) return "array";
        return "object";
    }

    /// <summary>
    /// The parameters the server really puts in a tool's schema.
    ///
    /// <para>Three approximations, none of which can pass silently: the SDK
    /// also binds any parameter whose type is a registered service, so a future
    /// injected argument would be counted here as required and fail loudly
    /// rather than quietly; a nullable array goes on the wire as
    /// <c>["array","null"]</c> and is called <c>array</c> here; and a tool
    /// declared with no <c>Name</c> is matched by its method name above.</para>
    /// </summary>
    private static (List<string> Required, Dictionary<string, string> Types) Parameters(MethodInfo method)
    {
        var required = new List<string>();
        var types = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var parameter in method.GetParameters())
        {
            // The server injects these; they are not part of the tool's schema,
            // and no model is ever shown them. IProgress<T> is the one that is
            // easy to miss — it lives in System, not in the MCP namespace, so a
            // namespace filter alone lets it through and every long-running
            // tool then reads as taking an undocumented argument.
            if (parameter.ParameterType == typeof(CancellationToken)) continue;
            if (parameter.ParameterType.IsGenericType
                && parameter.ParameterType.GetGenericTypeDefinition() == typeof(IProgress<>)) continue;
            if (parameter.ParameterType.Namespace?.StartsWith("ModelContextProtocol", StringComparison.Ordinal) == true)
                continue;

            types[parameter.Name!] = SchemaType(parameter.ParameterType);
            if (!parameter.HasDefaultValue) required.Add(parameter.Name!);
        }
        return (required, types);
    }

    private static (List<string> Required, Dictionary<string, string> Types) Expected(JsonNode tool)
    {
        var function = tool["function"]!;
        var required = new List<string>();
        if (function["parameters"]?["required"] is JsonArray names)
            foreach (var name in names) required.Add(name!.ToString());

        var types = new Dictionary<string, string>(StringComparer.Ordinal);
        if (function["parameters"]?["properties"] is JsonObject properties)
            foreach (var (name, schema) in properties)
                types[name] = schema?["type"]?.ToString() ?? "object";

        return (required, types);
    }

    /// <summary>
    /// The parameters whose TYPE differs between the two apps by design, and
    /// nothing else.
    ///
    /// <para>The mac's client speaks a schema with strings, integers and
    /// booleans and <b>no arrays</b>, so a list of page titles reaches it as
    /// one semicolon-separated string — semicolons rather than commas because
    /// "Unit 2, Day 3" is the name nearly every class page in these courses
    /// has, and a comma-separated list would cut it in half. This app's server
    /// has arrays and uses them. The reason is written down in
    /// <c>mac-app/…/AssistToolSurface.swift</c>, which calls it one of "two
    /// deliberate departures from the Windows schema".</para>
    ///
    /// <para><b>That it is written down in a Swift comment is the problem.</b>
    /// <c>toolSchemas</c> is a GENERATED key, so the departure cannot be
    /// recorded beside the schemas it applies to, and this list is now its
    /// second home — the very thing `contracts/` exists to prevent. Asked for
    /// in issue #83: have the generator emit the departures alongside the
    /// schemas, and this reads them instead of restating them.</para>
    ///
    /// <para>Asserted as an exact set rather than an allow-list, so a NEW
    /// departure fails, and so does a departure that has been resolved and not
    /// deleted from here.</para>
    /// </summary>
    private static void AssertOnlyTheDeparturesWeHaveAgreed(
        List<string> differing, List<string> onlyHere, IEnumerable<string> onThisSurface)
    {
        var tools = onThisSurface.ToHashSet(StringComparer.Ordinal);

        // The arguments this server takes that the contract does not describe.
        //
        // `preview` is the SECOND of the two departures AssistToolSurface.swift
        // names: on the mac every change rebuilds, which is what the assistant's
        // system prompt promises a teacher, so there is no flag; here a batch of
        // edits can be made with the preview suppressed and rebuilt once at the
        // end. The rest are arguments the mac's surface simply does not offer.
        //
        // Held to an exact set for the same reason as the type departures: a
        // NEW one is a routing difference nobody chose, and a resolved one that
        // stays listed makes this list a record of what once differed. The
        // plan_ twins take no `preview` — they change nothing, so there is
        // nothing to rebuild — which this list said they did until the check
        // itself said otherwise.
        var agreedExtras = new[]
        {
            "publish_class_on.preview",
            "publish_pages.preview", "publish_pages.includeLinked",
            "unpublish_pages.preview", "unpublish_pages.includeLinked",
            "plan_publish_pages.includeLinked",
            "plan_unpublish_pages.includeLinked",
            "add_next_class.unit", "add_next_class.days",
            "plan_add_next_class.unit", "plan_add_next_class.days",
            "read_remembered_timetable.scope", "read_remembered_timetable.revise",
            "re_date_classes.timetable", "re_date_classes.block", "re_date_classes.pages",
            "re_date_classes.meetings", "re_date_classes.firstDay", "re_date_classes.startYear",
            "plan_re_date_classes.timetable", "plan_re_date_classes.block",
            "plan_re_date_classes.pages", "plan_re_date_classes.meetings",
            "plan_re_date_classes.firstDay", "plan_re_date_classes.startYear",

            // The rollover's website question. `website` itself IS in the
            // contract and so is not listed here; these three are ours alone,
            // for a reason that is a platform fact rather than a preference.
            //
            // Plantoir's own assistant window reaches these tools THROUGH this
            // MCP server over JSON-RPC (Plantoir/Services/McpClient.cs), and
            // an argument the tool does not DECLARE is DROPPED by the SDK's
            // binder rather than refused — measured against
            // ModelContextProtocol 2.2.0 by sending a made-up key: the call
            // completed, IsError false, the key gone. So an undeclared
            // `rollover` would make the rollover phrasing run as an ordinary
            // re-date with nothing anywhere reporting a fault, which is why
            // TheCardsArgumentsReachTheToolThatReadsThem asserts arrival and
            // not merely presence on the schema. On the mac the card and the
            // tool runner share a process, so no binder stands between them
            // and `rollover` is deliberately absent from its published schema
            // — the same aim, reached differently because the two apps are
            // built differently.
            //
            // `plan_re_date_classes` needs both for the same reason once
            // removed: plan mode is ON by default, so the card's arguments
            // reach the TWIN first, and a twin that cannot see them proposes an
            // ordinary re-date and the answer is lost.
            //
            // Costs no routing accuracy: re_date_classes and its twin are not
            // in AssistAgent.ForTheLocalModel, so no local model reads either
            // schema.
            "re_date_classes.rollover",
            "plan_re_date_classes.website", "plan_re_date_classes.rollover",
        }.Where(e => tools.Contains(e[..e.IndexOf('.')])).ToList();

        var unagreedExtras = onlyHere.Except(agreedExtras).OrderBy(e => e, StringComparer.Ordinal).ToList();
        Assert.True(unagreedExtras.Count == 0,
            "This server takes tool arguments the contract does not describe, and nobody has " +
            "agreed them: " + string.Join("; ", unagreedExtras) + ". An argument the mac's model " +
            "is not shown is a routing difference as surely as an extra tool is. Either add it to " +
            "the contract, or record it here with its reason.");

        var goneExtras = agreedExtras.Except(onlyHere).OrderBy(e => e, StringComparer.Ordinal).ToList();
        Assert.True(goneExtras.Count == 0,
            "These are recorded as arguments this server alone takes, and it no longer does — or " +
            "the contract now describes them: " + string.Join("; ", goneExtras) + ". Delete them " +
            "from the list.");

        // Scoped to the surface being checked: the plan_ twins are MCP-only, so
        // on the local surface they are not departures, they are simply absent.
        var agreed = new[]
        {
            "publish_pages.pages (contract string, here array)",
            "plan_publish_pages.pages (contract string, here array)",
            "unpublish_pages.pages (contract string, here array)",
            "plan_unpublish_pages.pages (contract string, here array)",
        }.Where(d => tools.Contains(d[..d.IndexOf('.')])).ToList();

        var unexpected = differing.Except(agreed).OrderBy(d => d, StringComparer.Ordinal).ToList();
        Assert.True(unexpected.Count == 0,
            "Tool arguments differ between the two apps in ways nobody has agreed: " +
            string.Join("; ", unexpected) + ". A client that sends the documented shape gets a " +
            "refusal the teacher reads as \"the assistant could not do that\", with nothing " +
            "saying why. Either make them agree, or record the departure here with its reason.");

        var resolved = agreed.Except(differing).OrderBy(d => d, StringComparer.Ordinal).ToList();
        Assert.True(resolved.Count == 0,
            "These are recorded as deliberate departures and the two apps now agree about them: " +
            string.Join("; ", resolved) + ". Delete them from this list, so it keeps meaning " +
            "\"everything that differs\" rather than \"everything that once did\".");
    }

    // ---- What each client is shown ---------------------------------------

    /// <summary>
    /// The thirteen the on-device model sees are these thirteen — no more, and
    /// in particular no fewer.
    ///
    /// <para>Already pinned by name against <c>tools.local</c>. Asserted again
    /// from <c>toolSchemas</c> because the two lists are separate halves of the
    /// contract and a tool added to one and not the other is a contract that
    /// disagrees with itself.</para>
    /// </summary>
    [Fact]
    public void TheLocalModelIsShownExactlyTheToolsTheSchemasName()
    {
        var doc = ContractLoader.LoadJson("assist-cases.json");
        var named = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var tool in doc["toolSchemas"]!["local"]!.AsArray())
            named.Add(tool!["function"]!["name"]!.ToString());

        Assert.Equal(named, AssistAgent.ForTheLocalModel);
    }

    /// <summary>
    /// Every tool the contract's local surface names is one this app's server
    /// actually serves, with the same required arguments and the same types.
    ///
    /// <para>The arguments are where a mismatch bites silently: a model that
    /// sends <c>section</c> as a string to a server expecting an integer gets a
    /// refusal the teacher reads as "the assistant could not do that", with
    /// nothing anywhere saying why.</para>
    /// </summary>
    [Fact]
    public void EveryLocalToolTakesTheArgumentsTheContractGivesIt()
    {
        var served = ServedTools();
        var doc = ContractLoader.LoadJson("assist-cases.json");
        var tools = doc["toolSchemas"]!["local"]!.AsArray();
        Assert.NotEmpty(tools);

        var differing = new List<string>();
        var onlyHere = new List<string>();

        foreach (var tool in tools)
        {
            string name = tool!["function"]!["name"]!.ToString();
            Assert.True(served.TryGetValue(name, out var method),
                $"The contract shows the local model a tool called \"{name}\" and this app's " +
                "server does not serve it. The local surface is narrowed FROM the server's own " +
                "list, so a tool missing there is a tool the model is told about and cannot call.");

            var (required, types) = Parameters(method!);
            var (expectedRequired, expectedTypes) = Expected(tool);

            // Named, because a bare Assert.Equal here reports two lists of
            // argument names and not which of the tools they belong to — and
            // the loop stops at the first failure, so the reader has no other
            // clue either.
            Assert.True(
                expectedRequired.OrderBy(p => p, StringComparer.Ordinal)
                    .SequenceEqual(required.OrderBy(p => p, StringComparer.Ordinal)),
                $"\"{name}\" must require exactly the arguments the contract says it does. " +
                $"Contract: [{string.Join(", ", expectedRequired.OrderBy(p => p, StringComparer.Ordinal))}]; " +
                $"here: [{string.Join(", ", required.OrderBy(p => p, StringComparer.Ordinal))}].");

            foreach (var (parameter, type) in expectedTypes)
            {
                Assert.True(types.TryGetValue(parameter, out string? actual),
                    $"\"{name}\" is documented as taking \"{parameter}\" and does not.");
                if (type != actual) differing.Add($"{name}.{parameter} (contract {type}, here {actual})");
            }

            // The other direction, which the first version of this test did not
            // ask: an argument this server takes and the contract does not
            // describe is one the model here is offered and the mac's is not.
            // On a router, an extra argument is a routing difference exactly as
            // an extra tool is.
            foreach (string parameter in types.Keys)
                if (!expectedTypes.ContainsKey(parameter)) onlyHere.Add($"{name}.{parameter}");
        }

        AssertOnlyTheDeparturesWeHaveAgreed(differing, onlyHere,
            tools.Select(t => t!["function"]!["name"]!.ToString()));
    }

    /// <summary>
    /// The contract's MCP surface is a SUBSET of what this app serves, not an
    /// equality — and the difference is a known one, not drift.
    ///
    /// <para>The contract carries the mac's 25; <c>plantoir-mcp.exe</c> serves
    /// 37. So the same question asked of Claude Code gets a different toolbox
    /// depending on the machine, which is written up in documentation/10-local-ai-assistant.md and is
    /// the mac's to decide. What must hold either way is that every tool the
    /// contract DOES describe behaves the same here.</para>
    ///
    /// <para>A subset check cannot notice an addition, which is exactly how the
    /// drift went unseen — so the count is asserted too, and a change in it
    /// fails here saying which tools moved.</para>
    /// </summary>
    [Fact]
    public void EveryToolTheContractsMcpSurfaceNamesIsServedTheSameWayHere()
    {
        var served = ServedTools();
        var doc = ContractLoader.LoadJson("assist-cases.json");
        var tools = doc["toolSchemas"]!["mcp"]!.AsArray();
        Assert.NotEmpty(tools);

        var differing = new List<string>();
        var onlyHere = new List<string>();
        var missing = new List<string>();
        foreach (var tool in tools)
        {
            string name = tool!["function"]!["name"]!.ToString();
            if (!served.TryGetValue(name, out var method)) { missing.Add(name); continue; }

            var (required, types) = Parameters(method);
            var (expectedRequired, expectedTypes) = Expected(tool);

            // Named, because a bare Assert.Equal here reports two lists of
            // argument names and not which of the tools they belong to — and
            // the loop stops at the first failure, so the reader has no other
            // clue either.
            Assert.True(
                expectedRequired.OrderBy(p => p, StringComparer.Ordinal)
                    .SequenceEqual(required.OrderBy(p => p, StringComparer.Ordinal)),
                $"\"{name}\" must require exactly the arguments the contract says it does. " +
                $"Contract: [{string.Join(", ", expectedRequired.OrderBy(p => p, StringComparer.Ordinal))}]; " +
                $"here: [{string.Join(", ", required.OrderBy(p => p, StringComparer.Ordinal))}].");

            foreach (var (parameter, type) in expectedTypes)
            {
                Assert.True(types.TryGetValue(parameter, out string? actual),
                    $"\"{name}\" is documented as taking \"{parameter}\" and does not.");
                if (type != actual) differing.Add($"{name}.{parameter} (contract {type}, here {actual})");
            }

            // The other direction, which the first version of this test did not
            // ask: an argument this server takes and the contract does not
            // describe is one the model here is offered and the mac's is not.
            // On a router, an extra argument is a routing difference exactly as
            // an extra tool is.
            foreach (string parameter in types.Keys)
                if (!expectedTypes.ContainsKey(parameter)) onlyHere.Add($"{name}.{parameter}");
        }

        Assert.True(missing.Count == 0,
            "The contract describes MCP tools this app does not serve: " +
            string.Join(", ", missing) + ". A client told about a tool that is not there gets a " +
            "failure it cannot explain to the teacher.");

        AssertOnlyTheDeparturesWeHaveAgreed(differing, onlyHere,
            tools.Select(t => t!["function"]!["name"]!.ToString()));
    }

    /// <summary>
    /// Every argument a card phrasing sets is an argument the tool it routes to
    /// actually DECLARES.
    ///
    /// <para><b>Presence on the schema is not the property that matters —
    /// arrival is.</b> Plantoir's own assistant window sends
    /// <c>AssistCardCommand.ToJsonObject</c> to this server over JSON-RPC, and
    /// the SDK's binder DROPS a key the method does not declare rather than
    /// refusing it: measured against ModelContextProtocol 2.2.0 by sending a
    /// made-up argument, the call completed with <c>IsError = false</c> and the
    /// key simply gone. So a phrasing whose argument the tool has forgotten to
    /// take runs as though the teacher had said the plainer sentence, with
    /// nothing anywhere reporting a fault. "Roll this section over to a new
    /// year" would quietly become an ordinary re-date, and the section would go
    /// on publishing over last year's website — the defect this whole feature
    /// exists to fix.</para>
    ///
    /// <para>Across every phrasing rather than one case, because the failure is
    /// silent and so is invisible to any test that does not go looking.</para>
    /// </summary>
    [Fact]
    public void TheCardsArgumentsReachTheToolThatReadsThem()
    {
        var served = ServedTools();
        var doc = ContractLoader.LoadJson("assist-cases.json");
        var missing = new List<string>();
        var stillDropped = new HashSet<string>(StringComparer.Ordinal);

        foreach (var phrasing in doc["cardPhrasings"]!["matches"]!.AsArray())
        {
            string typed = phrasing!["phrasing"]!.ToString();
            var matched = AssistCardCommand.Matching(typed);
            if (matched is null) continue;   // the phrasing itself is another test's business
            if (!served.TryGetValue(matched.ToolName, out var method)) continue;

            var takes = method.GetParameters()
                .Select(p => p.Name!)
                .ToHashSet(StringComparer.Ordinal);

            foreach (string key in matched.ToJsonObject("ICS3U", 1).Select(pair => pair.Key))
            {
                if (takes.Contains(key)) continue;
                string pair = $"{matched.ToolName}.{key}";
                if (KnownToBeDropped.ContainsKey(pair)) { stillDropped.Add(pair); continue; }
                missing.Add($"“{typed}” sets \"{key}\" and {matched.ToolName} does not take it");
            }
        }

        Assert.True(missing.Count == 0,
            "These card arguments are dropped on the way to the tool, silently: " +
            string.Join("; ", missing) + ". The request then runs as though the teacher had said " +
            "something simpler, and nothing reports a fault.");

        // The other direction, so the list cannot rot: a pair recorded as
        // broken and no longer broken has been FIXED, and leaving it here would
        // turn this into a record of what once went wrong.
        var mended = KnownToBeDropped.Keys.Except(stillDropped).OrderBy(p => p, StringComparer.Ordinal);
        Assert.True(!mended.Any(),
            "These are recorded as arguments the binder drops and they now arrive: " +
            string.Join(", ", mended) + ". Delete them from KnownToBeDropped, and close the issue " +
            "the entry names.");
    }

    /// <summary>
    /// Card arguments the tool does not declare, each with the reason it is
    /// listed rather than fixed.
    /// </summary>
    /// <remarks>
    /// <para>Listed rather than tolerated: the test above fails on anything NOT
    /// here, and fails again when something here is mended and not deleted, so
    /// this is a short-lived record rather than a licence.</para>
    /// </remarks>
    private static readonly Dictionary<string, string> KnownToBeDropped = new(StringComparer.Ordinal)
    {
        // HARMLESS, and correct as it stands. The undo history is per
        // conversation, so the tool needs neither — the card sends course and
        // section to every tool it can reach, and these two are simply surplus.
        ["undo_last_change.course"] = "the undo history is per conversation, so the argument is surplus",
        ["undo_last_change.section"] = "the undo history is per conversation, so the argument is surplus",

        // A REAL DEFECT, filed as issue #116 and deliberately not fixed inside
        // the rollover work that found it. The eight publish_class_on phrasings
        // send `when` (a relative day) and the tool takes `date` (an absolute
        // one), which is required — so "publish tomorrow's class", the
        // commonest request in the product and one of the shelf's suggested
        // prompts, fails in the app with "That tool couldn't be run". Confirmed
        // against the real server over stdio, not reasoned about. The fix has a
        // wording decision in it (does "monday" include today when today is
        // Monday?), which is why it is its own piece of work.
        ["publish_class_on.when"] = "issue #116 — the card's relative day never becomes the tool's date",
    };

    /// <summary>
    /// How far this app's MCP surface has drifted ahead of the contract's,
    /// asserted as a NUMBER so that drifting further fails.
    ///
    /// <para>The subset test above passes whatever this app adds — which is how
    /// twelve extra tools accumulated without either suite noticing. Pinning
    /// the count turns the next addition into a decision: either it belongs in
    /// the contract, or the number and the reason change together.</para>
    /// </summary>
    [Fact]
    public void TheExtraToolsThisServerOffersAreTheOnesWeKnowAbout()
    {
        var served = ServedTools().Keys.ToHashSet(StringComparer.Ordinal);
        var doc = ContractLoader.LoadJson("assist-cases.json");
        var described = new HashSet<string>(StringComparer.Ordinal);
        foreach (var tool in doc["toolSchemas"]!["mcp"]!.AsArray())
            described.Add(tool!["function"]!["name"]!.ToString());

        // Named, not counted. A count stays at twelve when one tool is added
        // and another adopted into the contract, and it cannot tell the reader
        // WHICH — so the two things that should happen next would get the same
        // message.
        //
        // Twelve as of 2026-09-06; FIVE since 2026-09-08, when the mac built
        // seven of them (`add_classes`, `back_up_course`, `explain_publishing`,
        // `list_courses`, `make_room_for_classes`, `plan_add_classes`,
        // `plan_make_room_for_classes`) and the contract began describing them.
        // Deleting an adopted name from this list is the whole of what the
        // "adopted" assertion below asks for, and the list shrinking is the gap
        // closing rather than anything being lost.
        var knownExtras = new[]
        {
            "list_recent_changes", "plan_sync_page_dates", "read_timetable",
            "roll_over_section", "sync_page_dates",
        };

        var extra = served.Except(described).OrderBy(n => n, StringComparer.Ordinal).ToList();

        var unrecorded = extra.Except(knownExtras).OrderBy(n => n, StringComparer.Ordinal).ToList();
        Assert.True(unrecorded.Count == 0,
            "This server offers tools the contract does not describe and nobody has recorded: " +
            string.Join(", ", unrecorded) + ". Add each to assist-cases.json → toolSchemas.mcp " +
            "so both apps serve it, or list it here and open a `mac` issue saying why it is this " +
            "platform's alone. A subset check cannot notice an addition, which is how twelve of " +
            "these accumulated without either suite saying so.");

        var adopted = knownExtras.Except(extra).OrderBy(n => n, StringComparer.Ordinal).ToList();
        Assert.True(adopted.Count == 0,
            "The contract now describes tools this list still records as this platform's alone: " +
            string.Join(", ", adopted) + ". That is the gap closing — delete them from the " +
            "list, which is the whole of what is owed here.");
    }

    /// <summary>
    /// The <c>TEACHERS SAY:</c> clause of every shared tool matches the
    /// contract's, character for character.
    ///
    /// <para><b>Why this exists.</b> The phrasings are measured artifacts —
    /// <c>AssistToolSurface</c>'s own comment says they "are what took routing
    /// from 69% to 91%" — and <c>AssistAgent.Briefly()</c> puts the clause
    /// FIRST in what the local model reads, so a missing or edited one is a
    /// routing change nobody chose. Until 2026-09-08 this side was missing the
    /// clause ENTIRELY on seven tools and no test could see it: the rest of
    /// this class deliberately asserts names and argument types and never
    /// descriptions, because <c>NarrowToLocal</c> rewrites every description
    /// through <c>Briefly()</c> and asserting the mac's full wording would be
    /// red on all thirteen.</para>
    ///
    /// <para>The clause is the part that can be pinned, and pinning only the
    /// clause is deliberate: the descriptions' BODIES differ between the two
    /// servers on purpose — this one writes for Claude Code — so asserting
    /// those would be asserting a difference both sides chose.</para>
    ///
    /// <para>Added because the branch that closed the gap wrote up "a hand
    /// copy of a shipping list needs something that runs on every commit" as
    /// its own lesson, and had applied it to a research script and not to the
    /// twenty phrasings that were the point of the work.</para>
    /// </summary>
    [Fact]
    public void TheTriggerPhrasingsAreTheContractsOwn()
    {
        var served = ServedTools();
        var doc = ContractLoader.LoadJson("assist-cases.json");

        // check_section: this server offers a fourth phrasing, "what would
        // students see in this section right now?", written here 2026-08-17
        // and never adopted on the mac. It is the mac's to take up, and is a
        // GitHub issue on the `mac` label rather than a difference to erase.
        var agreedDepartures = new HashSet<string>(StringComparer.Ordinal) { "check_section" };

        var missing = new List<string>();
        var differing = new List<string>();
        var resolved = new List<string>();
        int compared = 0;

        foreach (var tool in doc["toolSchemas"]!["mcp"]!.AsArray())
        {
            string name = tool!["function"]!["name"]!.ToString();
            if (!served.TryGetValue(name, out var method)) continue;

            string? wanted = TriggerClause(tool["function"]!["description"]?.ToString());
            if (wanted is null) continue;

            string? here = TriggerClause(
                method.GetCustomAttribute<System.ComponentModel.DescriptionAttribute>()?.Description);

            if (agreedDepartures.Contains(name))
            {
                if (here == wanted) resolved.Add(name);
                continue;
            }

            compared++;
            if (here is null) missing.Add(name);
            else if (here != wanted)
                differing.Add($"{name} — contract has [{wanted}] and this server has [{here}]");
        }

        Assert.True(compared > 0,
            "No shared tool carried a TEACHERS SAY: clause, so this test compared nothing. "
            + "Either the contract stopped writing them or the surface stopped overlapping.");

        Assert.True(missing.Count == 0,
            "These shared tools carry a TEACHERS SAY: clause in the contract and none here: "
            + string.Join(", ", missing.Order(StringComparer.Ordinal))
            + ". The phrasings are measured, not decorative — Briefly() puts them FIRST in what "
            + "the local model reads, so a missing clause is a routing change nobody chose. "
            + "Copy the contract's clause WHOLE; see research/ai-assist/teachers-say-results.txt "
            + "for what the last set was worth.");

        Assert.True(differing.Count == 0,
            "These shared tools' TEACHERS SAY: clauses differ from the contract's: "
            + string.Join("; ", differing.Order(StringComparer.Ordinal))
            + ". Copy the contract's, or — if this side is deliberately ahead — add the tool to "
            + "agreedDepartures above and open a `mac` issue so the mac adopts it.");

        Assert.True(resolved.Count == 0,
            "These tools are listed as agreed departures and no longer differ: "
            + string.Join(", ", resolved.Order(StringComparer.Ordinal))
            + ". That is the gap closing — remove them from agreedDepartures, which is the whole "
            + "of what is owed here.");
    }

    /// <summary>
    /// The leading <c>TEACHERS SAY: "…", "…".</c> of a description, or null.
    /// MIRRORS the first half of <c>AssistAgent.Briefly()</c>, which splits on
    /// the first occurrence of quote-full-stop-space.
    /// </summary>
    private static string? TriggerClause(string? description)
    {
        if (description is null) return null;
        if (!description.StartsWith("TEACHERS SAY:", StringComparison.Ordinal)) return null;
        int end = description.IndexOf("\". ", StringComparison.Ordinal);
        return end > 0 ? description[..(end + 2)] : null;
    }

    // ---- Which assistant a teacher is offered ----------------------------

    /// <summary>
    /// A model is comfortable on a machine when it needs at most a share of
    /// physical memory that the contract fixes — a third, today.
    ///
    /// <para>Driven from the contract rather than typed, because the number
    /// is the line the automatic ladder has always been held to, and a test
    /// that hard-codes it cannot notice the ladder and the comfort rule
    /// drifting apart.</para>
    /// </summary>
    [Fact]
    public void ComfortIsTheShareOfMemoryTheContractNames()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        int denominator = doc["assistantModelChoice"]!["comfortFraction"]!["denominator"]!.GetValue<int>();
        Assert.True(denominator > 0);

        foreach (var tier in new[] { AssistModelTier.Small, AssistModelTier.Large })
        {
            long resident = tier.ResidentBytes();

            // Exactly enough is comfortable; a byte less is not. Asserting both
            // sides of the line is what makes this a test of the fraction
            // rather than of one machine that happens to be large.
            Assert.True(new AssistHardwareBudget(resident * denominator).IsComfortable(tier));
            Assert.False(new AssistHardwareBudget(resident * denominator - 1).IsComfortable(tier));
        }
    }

    /// <summary>
    /// The automatic choice never cautions, BY CONSTRUCTION: a caution names a
    /// tier the teacher picked, and the automatic choice names none.
    ///
    /// <para>Worth saying plainly, because the contract's own
    /// <c>comfortFraction.why</c> gives a different reason — "the line the
    /// automatic ladder has always been held to, which is why the automatic
    /// choice can never produce a caution" — and that reason does not hold at
    /// the bottom of the ladder here. On a 4 GB machine the ladder picks the
    /// small assistant, which needs 1.75 GB, and a third of 4 GB is less than
    /// that. The absence of a caution is right either way — a teacher who
    /// chose nothing has nothing to be cautioned about — but the reason is the
    /// construction, not the arithmetic. Recorded for the mac.</para>
    /// </summary>
    [Fact]
    public void TheAutomaticChoiceNeverCautions()
    {
        foreach (long gigabytes in new long[] { 4, 8, 16, 32, 64, 128 })
        {
            var budget = new AssistHardwareBudget(gigabytes * 1024 * 1024 * 1024);
            Assert.Null(AssistModelChoice.Caution(AssistModelChoice.Automatic, budget));
        }

        // A NAMED choice DOES caution on a tight machine, so the loop above is
        // not passing because cautions never happen at all.
        Assert.NotNull(AssistModelChoice.Caution(
            AssistModelChoice.Larger, new AssistHardwareBudget(4L * 1024 * 1024 * 1024)));
        Assert.Null(AssistModelChoice.Caution(
            AssistModelChoice.Larger, new AssistHardwareBudget(64L * 1024 * 1024 * 1024)));
    }

    /// <summary>
    /// What a teacher is told about a choice names BOTH costs: the download,
    /// which is what runs out on a small laptop, and the memory it holds while
    /// working, which is what makes the machine feel slow while a class is
    /// being prepared and appears as a number nowhere else.
    ///
    /// <para>Neither is guessable from the other — on the mac the larger
    /// download is 2.2x the smaller but 2.9x the memory, because most of the
    /// difference is the conversation being held rather than the file being
    /// read.</para>
    /// </summary>
    [Fact]
    public void TheGuidanceNamesBothWhatIsDownloadedAndWhatIsHeld()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var guidance = doc["assistantModelChoice"]!["guidance"]!;

        foreach (var tier in new[] { AssistModelTier.Small, AssistModelTier.Large })
        {
            string said = tier.SizeGuidance();

            if (guidance["mustNameDownloadSize"]!.GetValue<bool>())
                Assert.Contains(tier.DownloadDescription(), said, StringComparison.Ordinal);

            if (guidance["mustNameMemoryWhileWorking"]!.GetValue<bool>())
                Assert.Contains(tier.MemoryDescription(), said, StringComparison.Ordinal);
        }
    }

    // ---- What must be true of the model choice itself ---------------------

    /// <summary>
    /// <c>modelTiers.requirements</c> — five rules about the local assistant
    /// that hold on both platforms. Three can be executed; two are about how
    /// the work is done rather than about what the code does, and say so here
    /// rather than being quietly dropped.
    ///
    /// <para>A sixth requirement added on the mac fails this test by name,
    /// which is the point: the numbers in that section are explicitly NOT
    /// shared, but the shape is.</para>
    /// </summary>
    [Fact]
    public void EveryRequirementOfTheLocalAssistantIsAnsweredOrSaidToBeUnexecutable()
    {
        var doc = ContractLoader.LoadJson("app-rules.json");
        var unanswered = new HashSet<string>(StringComparer.Ordinal);
        foreach (var rule in doc["modelTiers"]!["requirements"]!.AsArray())
            unanswered.Add(rule!["rule"]!.ToString());
        Assert.NotEmpty(unanswered);

        void Answer(string rule)
        {
            Assert.True(unanswered.Remove(rule),
                $"No requirement in the contract reads \"{rule}\" any more.");
        }

        // Two rungs, no more.
        Assert.Equal(2, Enum.GetValues<AssistModelTier>().Length);
        Answer("Two rungs, no more");

        // The rung is CHOSEN from the hardware, never asked. A small machine
        // and a large one must reach different answers with nothing asked of
        // the teacher in between.
        Assert.Equal(AssistModelTier.Small,
            new AssistHardwareBudget(8L * 1024 * 1024 * 1024).Tier);
        Assert.Equal(AssistModelTier.Large,
            new AssistHardwareBudget(64L * 1024 * 1024 * 1024).Tier);
        Answer("The rung is CHOSEN from the hardware, never asked");

        // The teacher never learns the model's name.
        var names = doc["modelTiers"]!["requirements"]!.AsArray()
            .First(r => r!["rule"]!.ToString() == "The teacher never learns the model's name")!["names"]!;
        Assert.Equal(names["small"]!.ToString(), AssistModelTier.Small.DisplayName());
        Assert.Equal(names["large"]!.ToString(), AssistModelTier.Large.DisplayName());
        Answer("The teacher never learns the model's name");

        // The model runs on the HOST, with hardware acceleration — never inside
        // the container that builds the site. Both halves ARE executable, and
        // the first version of this test wrongly called them unexecutable: the
        // server launched is the bundled llama-server.exe rather than wsl.exe or
        // a container runtime, and LocalModelTests pins the GPU offload flag it
        // is given. A change routing the server through WSL would otherwise
        // have left this green.
        string? server = LocalModel.FindServer();
        if (server is not null)
        {
            // A bundled executable beside the app, not a shell into a VM.
            Assert.EndsWith("llama-server.exe", server, StringComparison.OrdinalIgnoreCase);
            foreach (string elsewhere in new[] { "wsl", "docker", "colima" })
                Assert.DoesNotContain(elsewhere, server, StringComparison.OrdinalIgnoreCase);
        }

        // And the arguments carry the GPU offload, which is the "with hardware
        // acceleration" half. Asserted here rather than only in
        // LocalModelTests because that is where this requirement is claimed.
        Assert.Contains("--n-gpu-layers",
            LocalModel.BuildArguments("model.gguf", 8080, threads: 4, useGpu: true));
        Answer("The model runs on the HOST, with hardware acceleration");

        // The one that genuinely cannot be executed, named rather than dropped.
        // A polarity veto is a rule about how a MODEL is chosen: it governs the
        // routing suite in research/ai-assist/, which is measured by hand and
        // states its own conditions. A test that pretended otherwise would be
        // the green-for-the-wrong-reason this whole item exists to remove.
        Assert.True(unanswered.Remove("A model that inverts polarity is VETOED, whatever it scores"),
            "The polarity veto is recorded here as the one requirement no test can execute, and " +
            "the contract no longer states it in those words.");

        Assert.True(unanswered.Count == 0,
            "contracts/app-rules.json requires things of the local assistant that no test here " +
            "answers: " + string.Join("; ", unanswered.OrderBy(r => r, StringComparer.Ordinal)) +
            ". The numbers in that section are not shared; the shape is.");
    }

    // ---- Walking back through what was typed ------------------------------

    /// <summary>
    /// The two cases where Up and Down must do their ORDINARY job instead of
    /// walking the prompt history. A key that silently does nothing reads as a
    /// dropped keystroke.
    ///
    /// <para>The two cases live in two places, which is why they are checked
    /// two ways. "Nowhere further to walk" is <see cref="AssistPromptHistory"/>
    /// answering null, and null is the signal the key was not consumed.
    /// "More than one line" is the composer's own guard, in the interface
    /// project this suite cannot reference, so it is read from the source the
    /// same way the wizard's answers are.</para>
    /// </summary>
    [Fact]
    public void TheArrowsAreLetThroughInBothCasesTheContractNames()
    {
        var doc = ContractLoader.LoadJson("assist-cases.json");
        var cases = doc["promptHistory"]!["passThroughWhen"]!["cases"]!.AsArray();

        var unanswered = new HashSet<string>(StringComparer.Ordinal);
        foreach (var entry in cases) unanswered.Add(entry!["when"]!.ToString());
        Assert.NotEmpty(unanswered);

        // Nowhere further to walk, in both directions.
        var history = new AssistPromptHistory();
        history.Remember("publish tomorrow's class");
        history.Remember("hide the quiz");

        // Down with no walk under way: nothing to come back to.
        Assert.Null(history.Later());

        // Up to the oldest entry, and then one more.
        Assert.Equal("hide the quiz", history.Earlier(""));
        Assert.Equal("publish tomorrow's class", history.Earlier(""));
        Assert.Null(history.Earlier(""));

        // An empty history has nowhere to walk from the start, which is the
        // same case on a teacher's first ever conversation.
        Assert.Null(new AssistPromptHistory().Earlier(""));
        Assert.True(unanswered.Remove("there is nowhere further to walk"));

        // More than one line: the composer must not swallow the key, because
        // the arrows have to move the caret between those lines.
        //
        // Anchored to EACH arrow's own block, with comments stripped first.
        // Bare containment stayed green with the guard deleted from Down and
        // left on Up, and green again with it moved into a comment — which is
        // the shape of source-reading test that reports a rule nobody follows.
        string composer = File.ReadAllText(Path.Combine(
            RepoRoot, "windows-app", "Plantoir", "Views", "AssistWindow.xaml.cs"));
        string code = Regex.Replace(composer, @"//[^\n]*", "");

        foreach (string arrow in new[] { "Up", "Down" })
        {
            Assert.Matches(
                new Regex(@"VirtualKey\." + arrow + @"\)\s*\{\s*if \(Input\.Text\.Contains\('\\n'\)\) return;",
                          RegexOptions.Singleline),
                code);
        }
        Assert.True(unanswered.Remove("the box holds more than one line"));

        Assert.True(unanswered.Count == 0,
            "contracts/assist-cases.json names cases where the arrow keys must be passed on " +
            "that no test here answers: " + string.Join("; ", unanswered) + ".");
    }

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
}

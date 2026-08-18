using System.Text.Json.Nodes;
using Plantoir.Core.Assist;

namespace Plantoir.Tests;

/// <summary>
/// The conversation loop, tested against the promise card.
///
/// AssistAgent.ExampleRequests tells a teacher eleven things this assistant
/// is good at. Routing — whether the MODEL picks the right tool for each
/// phrasing — is measured separately, against the real model, by
/// research/ai-assist/trimmed-surface-suite.py. What these tests pin is
/// everything AFTER routing: given the model's choice, the loop must do
/// exactly what the card promises — build and deploy through the app's own
/// windows, stop-edit-offer around page changes, gate deploys behind a
/// button, and never show the teacher the model's routing residue.
///
/// Every failure mode here was hit live first, one teacher-afternoon each.
/// </summary>
public class AssistAgentTests
{
    // ---- The fakes -------------------------------------------------------

    /// <summary>A model that answers from a script and records what it was asked.</summary>
    private sealed class ScriptedModel : IChatModel
    {
        private readonly Queue<JsonObject?> _replies = new();
        public readonly List<JsonArray> Asked = new();

        public ScriptedModel Then(JsonObject? reply)
        {
            _replies.Enqueue(reply);
            return this;
        }

        public ScriptedModel ThenSays(string content) => Then(new JsonObject { ["content"] = content });

        public ScriptedModel ThenCalls(string tool, string argumentsJson = "{}", string? alsoSays = null)
        {
            var reply = new JsonObject
            {
                ["tool_calls"] = new JsonArray(new JsonObject
                {
                    ["id"] = $"call-{_replies.Count}",
                    ["function"] = new JsonObject { ["name"] = tool, ["arguments"] = argumentsJson },
                }),
            };
            if (alsoSays is not null) reply["content"] = alsoSays;
            return Then(reply);
        }

        public Task<JsonObject?> Ask(JsonArray messages, JsonArray tools, CancellationToken cancellation)
        {
            Asked.Add((JsonArray)messages.DeepClone());
            return Task.FromResult(_replies.Count > 0 ? _replies.Dequeue() : null);
        }
    }

    /// <summary>A tool server that records calls and answers with a canned line.</summary>
    private sealed class RecordingTools : IToolServer
    {
        public readonly List<(string Name, JsonObject Arguments)> Calls = new();
        public string Result = "Done.";

        /// <summary>
        /// What a plan_ twin says it WOULD do — or null when the twin
        /// REFUSES, which comes back as an ordinary answer rather than a
        /// proposal.
        /// </summary>
        public string? PlanResult = "This would change one page.";

        /// <summary>The teacher's one-line half, when a test is about the split.</summary>
        public string? Summary;
        public string[] Narration = Array.Empty<string>();

        public Task<AssistToolAnswer> CallTool(string name, JsonObject arguments,
                                               Action<string>? progress = null,
                                               CancellationToken cancellation = default)
        {
            Calls.Add((name, (JsonObject)arguments.DeepClone()));
            foreach (string line in Narration) progress?.Invoke(line);

            // A plan_ twin answers with a PLAN, marked as one, the way the
            // real server does. Without the mark the loop would read it as a
            // refusal — which is the behaviour a refusal is supposed to get.
            if (name.StartsWith("plan_", StringComparison.Ordinal) && PlanResult is { } proposal)
                return Task.FromResult(new AssistToolAnswer(proposal, proposal, IsPlan: true));

            return Task.FromResult(Summary is null
                ? AssistToolAnswer.Same(Result)
                : new AssistToolAnswer(Summary, Result));
        }
    }

    /// <summary>An agent wired the way AssistWindow wires it, with everything recorded.</summary>
    private sealed class Rig
    {
        public readonly ScriptedModel Model = new();
        public readonly RecordingTools Tools = new();
        public readonly List<string> AppActions = new();
        public bool PreviewShowing;

        /// <summary>
        /// Whether the assistant shows what it is about to do and waits. TRUE
        /// by default, because that is what a teacher who has changed nothing
        /// in Settings gets.
        /// </summary>
        public bool Confirming = true;

        public readonly AssistAgent Agent;

        public Rig()
        {
            Agent = new AssistAgent(Model, Tools, new JsonArray(), "VVH2O", 1)
            {
                ShowPreviewInApp = () => AppActions.Add("show preview"),
                StopPreviewInApp = () => AppActions.Add("stop preview"),
                StartDeployInApp = () => AppActions.Add("deploy"),
                PreviewIsShowing = () => PreviewShowing,
                OnToolProgress = line => AppActions.Add("narrate: " + line),
                ConfirmationMode = () => Confirming,
            };
        }

        public List<AssistAgent.Line> Say(string text) =>
            Agent.Say(text, CancellationToken.None).GetAwaiter().GetResult();

        public List<AssistAgent.Line> Approve() =>
            Agent.Approve(CancellationToken.None).GetAwaiter().GetResult();

        public List<AssistAgent.Line> Decline() =>
            Agent.Decline(CancellationToken.None).GetAwaiter().GetResult();
    }

    // ---- Publishing a class ---------------------------------------------

    [Fact]
    public void PublishingAClassIsACommandNotARoutingQuestion()
    {
        // "Publish Unit 2, Day 3, and everything it links to" — the card's
        // own wording. Measured, the model sent it to the publish-by-DATE
        // tool three trials out of three, so the shape is matched in code:
        // exact tool, exact arguments, server's build declined, restart
        // offered, and the model never consulted.
        var rig = new Rig { Confirming = false };
        rig.Tools.Result = "Published “Unit 2, Day 3”.";

        var lines = rig.Say("Publish Unit 2, Day 3, and everything it links to");

        Assert.Empty(rig.Model.Asked);
        var call = Assert.Single(rig.Tools.Calls);
        Assert.Equal("publish_pages", call.Name);
        Assert.True(call.Arguments["includeLinked"]!.GetValue<bool>());
        Assert.Equal("Unit 2, Day 3", call.Arguments["pages"]![0]!.GetValue<string>());
        Assert.False(call.Arguments["preview"]!.GetValue<bool>());
        Assert.Contains(lines, l => l.Text.Contains("Published “Unit 2, Day 3”"));
        Assert.False(lines[^1].NeedsApproval);
    }

    /// <summary>
    /// Skipping the MODEL is not skipping the TEACHER. A fixed phrasing is
    /// matched in code because the router gets it wrong, which is no reason
    /// to stop saying what it would do first.
    /// </summary>
    [Fact]
    public void AFixedPhrasingStillShowsItsPlanWhenConfirmationIsOn()
    {
        var rig = new Rig();                    // confirming, as a teacher gets it
        rig.Tools.PlanResult = "Publish “Unit 2, Day 3” and the 4 pages it links to.";
        rig.Tools.Result = "Published 5 pages.";

        var lines = rig.Say("Publish Unit 2, Day 3, and everything it links to");

        Assert.Empty(rig.Model.Asked);
        Assert.Equal("plan_publish_pages", Assert.Single(rig.Tools.Calls).Name);
        Assert.Contains(lines, l => l.Text == "Publish “Unit 2, Day 3” and the 4 pages it links to.");
        Assert.Equal(AssistWording.PlanQuestion, lines[^1].Text);
        Assert.True(lines[^1].NeedsApproval);
        Assert.True(rig.Agent.IsAwaitingApproval);

        // The model is not asked a second time: the arguments it chose are
        // carried through, so what runs on Go is what was described.
        var done = rig.Approve();
        var real = rig.Tools.Calls[^1];
        Assert.Equal("publish_pages", real.Name);
        Assert.Equal("Unit 2, Day 3", real.Arguments["pages"]![0]!.GetValue<string>());
        Assert.Contains(done, l => l.Text == "Published 5 pages.");
    }

    /// <summary>
    /// A plan twin can REFUSE — no such page, no such section — and a refusal
    /// is an answer, not a proposal. Two buttons under it invite a teacher to
    /// approve an explanation of why nothing can be done.
    /// </summary>
    [Fact]
    public void APlanThatRefusedGetsNoButtons()
    {
        const string refusal = "There’s no page called “Unit 9, Day 9” in VVH2O Section 1.";
        var rig = new Rig();
        rig.Tools.PlanResult = null;                 // the twin refuses
        rig.Tools.Result = refusal;
        rig.Model.ThenCalls("publish_pages",
            """{"course": "VVH2O", "section": 1, "pages": ["Unit 9, Day 9"]}""");

        var lines = rig.Say("Put up Unit 9, Day 9");

        Assert.Equal("plan_publish_pages", Assert.Single(rig.Tools.Calls).Name);
        Assert.Contains(lines, l => l.Text == refusal);
        Assert.False(rig.Agent.IsAwaitingApproval);
        Assert.DoesNotContain(lines, l => l.NeedsApproval);
    }

    [Fact]
    public void PublishingTomorrowsClassCarriesTheDateTheModelWasGiven()
    {
        // "Publish tomorrow's class, but not the linked pages" only works because
        // the dateline rides on the user turn — without it, every trial fabricated 2023-09-15.
        var rig = new Rig { Confirming = false };
        rig.Model.ThenCalls("publish_class_on",
            """{"course": "VVH2O", "section": 1, "date": "2026-08-15"}""");

        rig.Say("Publish tomorrow's class, but not the linked pages");

        string userTurn = rig.Model.Asked[0][^1]!["content"]!.GetValue<string>();
        Assert.StartsWith("Publish tomorrow's class, but not the linked pages (Today is ", userTurn);
        Assert.Contains(DateTime.Now.ToString("yyyy-MM-dd"), userTurn);
        Assert.Equal("publish_class_on", Assert.Single(rig.Tools.Calls).Name);
    }

    [Fact]
    public void PublishTomorrowCarriesItsArgument()
    {
        var command = AssistCardCommand.Matching("Publish tomorrow's class");
        Assert.NotNull(command);
        Assert.Equal("publish_class_on", command.ToolName);
        Assert.Equal("tomorrow", command.Arguments["when"]);
    }

    // ---- Taking something back down -------------------------------------

    [Fact]
    public void UnpublishingStopsTheShowingPreviewAndEdits()
    {
        // The stop-edit flow, in the order a person would do it.
        var rig = new Rig { PreviewShowing = true, Confirming = false };
        rig.Tools.Result = "Unpublished “Unit 2, Day 3”.";

        var lines = rig.Say("Unpublish Unit 2, Day 3");

        Assert.Empty(rig.Model.Asked);                        // the card's shape is a command
        Assert.Equal("stop preview", rig.AppActions[0]);      // before the edit
        Assert.False(Assert.Single(rig.Tools.Calls).Arguments["preview"]!.GetValue<bool>());
        Assert.False(rig.Agent.IsAwaitingApproval);
        Assert.Contains(lines, l => l.Text.Contains("Unpublished “Unit 2, Day 3”"));
    }

    [Fact]
    public void AnEditWithNoPreviewShowingStopsNothing()
    {
        var rig = new Rig { PreviewShowing = false, Confirming = false };

        var lines = rig.Say("Unpublish Unit 2, Day 3");

        Assert.DoesNotContain("stop preview", rig.AppActions);
        Assert.False(rig.Agent.IsAwaitingApproval);
    }

    // ---- Looking before you leap ----------------------------------------

    [Fact]
    public void PlanQuestionsAnswerWithThePlansOwnSentence()
    {
        // "What would publishing Unit 3, Day 1 change?" — the plan tool's
        // result is written to be read aloud, so it IS the answer: no model
        // round to summarise it (measured, the model routed this to the
        // wrong plan tool three trials out of three), and no button.
        var rig = new Rig();
        rig.Tools.PlanResult = "Would publish “Unit 3, Day 1” and the 3 pages it links to.";

        var lines = rig.Say("What would publishing Unit 3, Day 1 change?");

        Assert.Empty(rig.Model.Asked);
        var call = Assert.Single(rig.Tools.Calls);
        Assert.Equal("plan_publish_pages", call.Name);
        Assert.Equal("Unit 3, Day 1", call.Arguments["pages"]![0]!.GetValue<string>());
        Assert.False(rig.Agent.IsAwaitingApproval);
        Assert.Contains(lines, l => l.Text.Contains("Would publish “Unit 3, Day 1”"));
    }

    [Fact]
    public void AskingWhatStudentsSeeIsAFreeLookup()
    {
        var rig = new Rig();
        rig.Tools.Result = "Students can see 34 pages; nothing is broken.";

        var lines = rig.Say("What would students see in this section right now?");

        Assert.Empty(rig.Model.Asked);
        Assert.Equal("check_section", Assert.Single(rig.Tools.Calls).Name);
        Assert.False(rig.Agent.IsAwaitingApproval);
        Assert.Contains(lines, l => l.Text.Contains("34 pages"));
    }

    // ---- Afterwards ------------------------------------------------------

    [Fact]
    public void RebuildThePreviewNeverConsultsTheModelOrTheServer()
    {
        // The commonest command is a command: measured, the model sent
        // "Preview the site" to check_section three trials out of four even
        // with the cue in place, so plain string matching answers it.
        var rig = new Rig();

        var lines = rig.Say("Rebuild the preview");

        Assert.Empty(rig.Model.Asked);
        Assert.Empty(rig.Tools.Calls);
        Assert.Equal(new[] { "show preview" }, rig.AppActions);
        Assert.Contains("main window", Assert.Single(lines).Text);
    }

    [Theory]
    [InlineData("Preview the site")]
    [InlineData("preview the site please")]
    [InlineData("Can you show me the preview?")]
    [InlineData("Start the preview.")]
    public void PlainPreviewCommandsAreInstantWhateverTheCourtesyWords(string phrasing)
    {
        var rig = new Rig();
        rig.Say(phrasing);
        Assert.Empty(rig.Model.Asked);
        Assert.Equal(new[] { "show preview" }, rig.AppActions);
    }

    [Fact]
    public void ARoutedRebuildPreviewPressesTheAppsButtonNotTheServers()
    {
        // Longer phrasings still reach the model; when IT picks
        // rebuild_preview, the tool is intercepted — the server must never
        // build behind the chat, and the turn ends without an echo round.
        var rig = new Rig();
        rig.Model.ThenCalls("rebuild_preview", """{"course": "VVH2O", "section": 1}""");

        var lines = rig.Say("The preview looks stale — could you rebuild it for me?");

        Assert.Empty(rig.Tools.Calls);
        Assert.Contains("show preview", rig.AppActions);
        Assert.Single(rig.Model.Asked);
        Assert.Contains(lines, l => l.Text.Contains(AssistWording.PreviewIsRebuilding("VVH2O", "1")));
    }

    [Fact]
    public void UndoIsACommandAndReversesChange()
    {
        // Bare "Undo that" was DECLINED by the model three trials out of
        // three — without conversation context it saw nothing to undo. It
        // means exactly one thing, so it is matched in code.
        var rig = new Rig();
        rig.Tools.Result = "Took back the last change.";

        var lines = rig.Say("Undo that");

        Assert.Empty(rig.Model.Asked);
        Assert.Equal("undo_last_change", Assert.Single(rig.Tools.Calls).Name);
        Assert.Contains(lines, l => l.Text.Contains("Took back the last change."));
        Assert.False(lines[^1].NeedsApproval);
    }

    // ---- Putting it in front of students ---------------------------------

    [Fact]
    public void DeployingWaitsForTheButtonAndThenDrivesTheMainWindow()
    {
        // The one gate left, reached as a command — measured, "Deploy this
        // section now" never once routed to the deploy tool. Nothing must
        // happen until the teacher presses the button; then the deploy runs
        // through the main window's own flow, never the server's.
        var rig = new Rig();

        var lines = rig.Say("Deploy this section now");

        Assert.Empty(rig.Model.Asked);
        Assert.True(rig.Agent.IsAwaitingApproval);
        Assert.Empty(rig.AppActions);
        Assert.Empty(rig.Tools.Calls);
        Assert.True(lines[^1].NeedsApproval);
        Assert.Equal(AssistWording.DeployApproval, lines[^2].Text);
        Assert.Equal(AssistWording.DeployQuestion, lines[^1].Text);

        var answer = rig.Approve();
        Assert.Equal(new[] { "deploy" }, rig.AppActions);
        Assert.Empty(rig.Tools.Calls);
        Assert.Contains(answer, l => l.Text.Contains(AssistWording.Deployed("VVH2O", "1")));
    }

    [Fact]
    public void DecliningADeployRunsNothing()
    {
        var rig = new Rig();

        rig.Say("Deploy this section now");
        var answer = rig.Decline();

        Assert.Empty(rig.AppActions);
        Assert.Empty(rig.Tools.Calls);
        Assert.Equal(AssistWording.DeployWasCancelled, Assert.Single(answer).Text);
    }

    [Fact]
    public void SchedulingADeployIsApprovedAtSchedulingTime()
    {
        // "Deploy tomorrow's class at 6:30 AM" — matched in code (measured,
        // the model answered it with a publish tool three trials out of
        // three), the time parsed, and the yes collected NOW, because the
        // firing at 6:30 asks nobody. The tool itself runs on the server:
        // scheduling has to outlive the window.
        var rig = new Rig();
        rig.Tools.Result = "This computer will deploy VVH2O section 1 at 06:30.";

        var asked = rig.Say("Deploy tomorrow's class at 6:30 AM");
        Assert.Empty(rig.Model.Asked);
        Assert.True(asked[^1].NeedsApproval);
        Assert.Empty(rig.Tools.Calls);

        var answer = rig.Approve();
        var call = Assert.Single(rig.Tools.Calls);
        Assert.Equal("schedule_deploy", call.Name);
        Assert.Equal($"{DateTime.Now.AddDays(1):yyyy-MM-dd} 06:30", call.Arguments["when"]!.GetValue<string>());
        Assert.Contains(answer, l => l.Text.Contains("06:30"));
    }

    [Fact]
    public void CancellingAScheduledDeployNeedsNoButton()
    {
        // Cancelling takes something AWAY from students' path, so it runs
        // freely — a gate here would only slow down changing your mind.
        var rig = new Rig();
        rig.Model.ThenCalls("cancel_scheduled_deploy", """{"course": "VVH2O", "section": 1}""");
        rig.Model.ThenSays("Cancelled — nothing will deploy.");
        rig.Tools.Result = "The scheduled deploy is cancelled.";

        var lines = rig.Say("Cancel that scheduled deploy");

        Assert.False(rig.Agent.IsAwaitingApproval);
        Assert.Equal("cancel_scheduled_deploy", Assert.Single(rig.Tools.Calls).Name);
        Assert.Contains(lines, l => l.Text.Contains("cancelled", StringComparison.OrdinalIgnoreCase));
    }

    [Theory]
    [InlineData("Publish tomorrow's class, but not the linked pages")]
    [InlineData("Publish the Safety Contract page")]
    [InlineData("I published Unit 4, Day 1 by mistake — unpublish it")]
    [InlineData("What would publishing tomorrow's class change?")]
    [InlineData("Deploy tomorrow's class when the bell goes")]
    public void AnythingConversationalStillGoesToTheModel(string phrasing)
    {
        // The command layer handles the card's fixed shapes and nothing
        // more. Dated titles, freeform titles, sentences with a story in
        // them — those are what the model is for.
        var rig = new Rig();
        rig.Model.ThenSays("Let me look into that.");

        rig.Say(phrasing);

        Assert.NotEmpty(rig.Model.Asked);
    }

    // ---- The transcript never shows the machinery ------------------------

    [Fact]
    public void ContentRidingWithAToolCallIsNotShown()
    {
        // The model parrots the request back beside its tool call —
        // "Unpublishing Unit 4, Day 5 (Today is 2026-08-14, a Friday.)",
        // dateline and all, shown to the teacher who had just typed it.
        // A conversational phrasing, because the card's own shape is a
        // command that never reaches the model.
        // Confirmation off, because what is under test is the parrot rather
        // than the gate.
        var rig = new Rig { Confirming = false };
        rig.Model.ThenCalls("unpublish_pages", """{"course": "VVH2O", "section": 1}""",
            alsoSays: "Unpublishing Unit 4, Day 5 (Today is 2026-08-14, a Friday.)");
        rig.Tools.Result = "Unpublished “Unit 4, Day 5”.";

        var lines = rig.Say("Take Unit 4, Day 5 down for me, would you?");

        Assert.DoesNotContain(lines, l => l.Text.Contains("Unpublishing Unit 4, Day 5"));
        Assert.Contains(lines, l => l.Text.Contains("Unpublished “Unit 4, Day 5”."));
    }

    [Fact]
    public void TheDatelineNeverAppearsInWhatTheTeacherReads()
    {
        var rig = new Rig();
        string today = DateTime.Now.ToString("yyyy-MM-dd");
        rig.Model.ThenSays($"Tomorrow is the day after (Today is {today}, a {DateTime.Now.DayOfWeek}.) — nothing to do.");

        var lines = rig.Say("What day is it?");

        Assert.DoesNotContain(lines, l => l.Text.Contains("(Today is"));
        Assert.Contains(lines, l => l.Text.Contains("nothing to do"));
    }

    [Fact]
    public void ToolNarrationReachesTheWindowLineByLine()
    {
        var rig = new Rig();
        rig.Model.ThenCalls("unpublish_pages", """{"course": "VVH2O", "section": 1}""");
        rig.Tools.Narration = new[] { "Backing up VVH2O first…", "Editing “Unit 2, Day 3”…", "Changed 1 page." };

        rig.Say("Unpublish Unit 2, Day 3");

        Assert.Contains("narrate: Backing up VVH2O first…", rig.AppActions);
        Assert.Contains("narrate: Editing “Unit 2, Day 3”…", rig.AppActions);
    }

    // ---- The loop cannot run away ----------------------------------------

    [Fact]
    public void AModelThatLoopsIsStoppedAfterSixSteps()
    {
        var rig = new Rig();
        for (int step = 0; step < 10; step++)
            rig.Model.ThenCalls("list_pages", """{"course": "VVH2O", "section": 1}""");

        var lines = rig.Say("Do something odd");

        Assert.Equal(6, rig.Tools.Calls.Count);
        Assert.Contains("without finishing", lines[^1].Text);
    }

    [Fact]
    public void ASilentModelIsReportedNotWaitedOn()
    {
        var rig = new Rig();   // no scripted replies: Ask returns null

        var lines = rig.Say("Publish tomorrow's class, but not the linked pages");

        Assert.Contains("didn’t answer", Assert.Single(lines).Text);
    }

    // ---- The promise card and the surface stay in step -------------------

    [Fact]
    public void EveryToolThePromisesNeedSurvivesTheNarrowing()
    {
        // The card's eleven tasks need these tools on the local surface. A
        // trim that dropped one would break a promise silently — deploying
        // was once trimmed out for speed after being asked for by name.
        string[] needed =
        {
            "publish_pages", "publish_class_on", "unpublish_pages",
            "check_section", "rebuild_preview",
            "undo_last_change", "deploy_section", "schedule_deploy",
            "cancel_scheduled_deploy",
        };
        var serverTools = new JsonArray();
        foreach (string name in needed.Append("hide_class").Append("roll_over_course"))
            serverTools.Add(new JsonObject
            {
                ["function"] = new JsonObject
                {
                    ["name"] = name,
                    ["description"] = "TEACHERS SAY: \"words\". Does the thing, for example ICS3U. And more detail.",
                    ["parameters"] = new JsonObject
                    {
                        ["properties"] = new JsonObject
                        {
                            ["course"] = new JsonObject { ["description"] = "The course code, for example ICS3U." },
                        },
                    },
                },
            });

        var narrowed = AssistAgent.NarrowToLocal(serverTools, "VVH2O");

        var keptNames = narrowed.Select(t => t!["function"]!["name"]!.GetValue<string>()).ToList();
        foreach (string name in needed) Assert.Contains(name, keptNames);
        // And nothing that fell off the card sneaks along to slow the prompt.
        Assert.DoesNotContain("roll_over_course", keptNames);
    }

    [Fact]
    public void TheNarrowedSchemasNameTheRealCourseNotTheExample()
    {
        // With no course named, the model copied "for example ICS3U" nine
        // trials out of nine. The only example it cannot copy wrongly is the
        // right answer.
        var serverTools = new JsonArray(new JsonObject
        {
            ["function"] = new JsonObject
            {
                ["name"] = "publish_pages",
                ["description"] = "TEACHERS SAY: \"put it up\". Publishes, for example ICS3U. More prose. Even more.",
                ["parameters"] = new JsonObject
                {
                    ["properties"] = new JsonObject
                    {
                        ["course"] = new JsonObject { ["description"] = "The course code, for example ICS3U." },
                    },
                },
            },
        });

        var narrowed = AssistAgent.NarrowToLocal(serverTools, "VVH2O");

        string wholeSurface = narrowed.ToJsonString();
        Assert.DoesNotContain("ICS3U", wholeSurface);
        Assert.Contains("VVH2O", wholeSurface);
        // And the description is trimmed to cues plus one sentence.
        string description = narrowed[0]!["function"]!["description"]!.GetValue<string>();
        Assert.Contains("TEACHERS SAY", description);
        Assert.DoesNotContain("More prose", description);
    }

    [Fact]
    public void ThePromiseCardStillPromisesWhatTheseTestsCover()
    {
        // If the card's wording of the eleven tasks changes, this fails and
        // whoever changed it is pointed here, to keep card and tests in step.
        string[] promised =
        {
            "Publish Unit 2, Day 3, and everything it links to",
            "Publish tomorrow's class",
            "Unpublish Unit 2, Day 3",
            "I published Unit 4, Day 1 by mistake — unpublish it",
            "What would publishing Unit 3, Day 1 change?",
            "What would students see in this section right now?",
            "Rebuild the preview",
            "Undo that",
            "Deploy this section now",
            "Deploy tomorrow's class at 6:30 AM",
            "Cancel that scheduled deploy",
        };
        foreach (string promise in promised)
            Assert.Contains(promise, AssistAgent.ExampleRequests);
    }
}

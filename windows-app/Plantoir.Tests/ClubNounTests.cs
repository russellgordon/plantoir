using System.Text.Json.Nodes;
using ModelContextProtocol.Protocol;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Mcp;

namespace Plantoir.Tests;

/// <summary>
/// "meeting" in a club (#274, mac #267): the TEACHER's card says meeting, the
/// MODEL's copy never does. The mac's
/// <c>ClubNounTests.testTheNounNeverReachesWhatTheModelReads</c> flips
/// <c>class_noun</c> on one club and requires every plan's model copy to be
/// byte-identical; this is the same test over plantoir-mcp's tools, reading
/// the TEXT content (what the model and Claude Code read) apart from the
/// <c>_meta</c> teacher summary (what the window shows).
/// </summary>
public sealed class ClubNounTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("club-noun").FullName;

    /// <summary>The workspace the last <see cref="Club"/> made.</summary>
    private AssistWorkspace? _workspace;

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private PlantoirTools Club(string? noun)
    {
        var classes = new JsonArray(
            new JsonObject { ["title"] = "Week 1", ["date"] = "2025-09-18" },
            new JsonObject { ["title"] = "Week 2", ["date"] = "2025-09-25" },
            new JsonObject { ["title"] = "Week 3", ["date"] = "2025-10-02" });
        var dates = Enumerable.Range(0, 10).Select(week => new DateOnly(2025, 9, 18).AddDays(7 * week)).ToList();
        foreach (var entry in Directory.EnumerateFileSystemEntries(_folder))
        {
            if (Directory.Exists(entry)) Directory.Delete(entry, true); else File.Delete(entry);
        }
        var workspace = ClassPlanningContractTests.ScratchCourse(_folder, new ClassPageNaming("Week", ClassPageScheme.Numbered),
                                                                 classes, dates);
        string config = Path.Combine(_folder, "courses", "ICS3U", "course_config.json");
        string text = File.ReadAllText(config);
        text = noun is null
            ? text.Replace("\"class_noun\": \"meeting\"", "\"class_noun_unused\": \"x\"")
            : text.Replace("\"class_noun\": \"meeting\"", $"\"class_noun\": \"{noun}\"");
        File.WriteAllText(config, text);
        _workspace = workspace;
        return new PlantoirTools(workspace);
    }

    private static string ModelCopy(CallToolResult result) =>
        string.Join("\n", result.Content.OfType<TextContentBlock>().Select(block => block.Text));

    private static string TeacherCopy(CallToolResult result) =>
        result.Meta?[AssistToolAnswer.TeacherSummaryKey]?.GetValue<string>() ?? ModelCopy(result);

    /// <summary>
    /// Week 1 linking to Week 2, both hidden or both visible, written over the
    /// scratch club AFTER <see cref="Club"/> made it — kept out of
    /// <see cref="Club"/> itself so the other plans run on the plain fixture
    /// (#556). A hidden Week 2 is a linked class a publish LEAVES ALONE; a
    /// visible one is a linked class an unpublish KEEPS, "a class of its own".
    /// </summary>
    private PlantoirTools Linked(PlantoirTools tools, bool visible)
    {
        string classes = Path.Combine(_folder, "courses", "ICS3U", "section1", "All Classes");
        string publish = visible ? "true" : "false";
        File.WriteAllText(Path.Combine(classes, "Week 1.md"),
            $"---\ntitle: Week 1\npublish: {publish}\ncreated: 2025-09-18T07:00:00.000-0400\n---\n\nToday: [[Week 2]]\n");
        File.WriteAllText(Path.Combine(classes, "Week 2.md"),
            $"---\ntitle: Week 2\npublish: {publish}\ncreated: 2025-09-25T07:00:00.000-0400\n---\n\nWeek 2\n");
        return tools;
    }

    private IEnumerable<(string What, Func<PlantoirTools, CallToolResult> Call)> Plans() => new (string, Func<PlantoirTools, CallToolResult>)[]
    {
        ("make room", tools => tools.PlanMakeRoomForClasses("ICS3U", 1, 1, 2)),
        ("next page", tools => tools.PlanAddNextClass("ICS3U", 1)),
        ("duplicate", tools => tools.PlanAddNextClass("ICS3U", 1, duplicate: "Week 1")),
        ("add pages", tools => tools.PlanAddClasses("ICS3U", 1, 1, 2)),
        ("start of year", tools => tools.PlanPrepareForStartOfYear("ICS3U", 1)),
        // #556: the three publish plans, each over a linked class.
        ("publish pages", tools => Linked(tools, visible: false).PlanPublishPages("ICS3U", 1, new[] { "Week 1" })),
        ("unpublish pages", tools => Linked(tools, visible: true).PlanUnpublishPages("ICS3U", 1, new[] { "Week 1" })),
        ("publish the class on", tools => Linked(tools, visible: false).PlanPublishClassOn("ICS3U", 1, "2025-09-18")),
        ("nothing changes, a name unknown",
         tools => Linked(tools, visible: true).PlanPublishPages("ICS3U", 1, new[] { "Week 2", "Week 99" })),
        // ...and the write itself with preview=false, which answers the same way and writes nothing.
        ("publish, nothing changes, no preview",
         tools => Linked(tools, visible: true).PublishPages("ICS3U", 1, pages: new[] { "Week 2", "Week 99" }, preview: false)
                      .GetAwaiter().GetResult()),
    };

    [Fact]
    public void TheNounNeverReachesWhatTheModelReads()
    {
        foreach (var (what, call) in Plans())
        {
            string asAClass = ModelCopy(call(Club(null)));
            var meeting = call(Club("meeting"));
            Assert.Equal(asAClass, ModelCopy(meeting));
            Assert.DoesNotContain("meeting", ModelCopy(meeting), StringComparison.OrdinalIgnoreCase);
        }
    }

    [Fact]
    public void AClubsTeacherReadsMeeting()
    {
        var tools = Club("meeting");
        Assert.Contains(AssistWording.WouldMakeRoomForAMeeting(1, "Week 2", "ICS3U", "1"),
                        TeacherCopy(tools.PlanMakeRoomForClasses("ICS3U", 1, 1, 2)));
        Assert.Contains(AssistWording.WouldAddPagesForAMeeting(1, "ICS3U", "1"),
                        TeacherCopy(tools.PlanAddNextClass("ICS3U", 1)));
        Assert.Contains(AssistWording.MakingRoomCannotBeUndoneForAMeeting,
                        TeacherCopy(tools.PlanAddNextClass("ICS3U", 1, duplicate: "Week 1")));

        // #530: the make-room card, too, in the meeting form; the model's copy
        // keeps the class form (TheNounNeverReachesWhatTheModelReads).
        var makeRoom = tools.PlanMakeRoomForClasses("ICS3U", 1, 1, 2);
        Assert.Contains(AssistWording.MakingRoomCannotBeUndoneForAMeeting, TeacherCopy(makeRoom));
        Assert.DoesNotContain(AssistWording.MakingRoomCannotBeUndone, TeacherCopy(makeRoom));
        Assert.Contains(AssistWording.MakingRoomCannotBeUndone, ModelCopy(makeRoom));
    }

    /// <summary>
    /// #556 (the mac's #267): a club's publish and unpublish cards say
    /// "meeting" for a linked class left alone and for the reason one is kept,
    /// as the Section menu's table under them already did (#548); the model's
    /// copy keeps the class forms (<see cref="TheNounNeverReachesWhatTheModelReads"/>
    /// holds it byte for byte). The kept line is the contract's sentence with
    /// no folder because only one page in the section is called Week 2.
    /// </summary>
    [Fact]
    public void AClubsPublishCardSaysMeetingForLinkedClasses()
    {
        var leftAlone = new[] { "Week 2" };
        foreach (var publishing in new[]
                 {
                     Linked(Club("meeting"), visible: false).PlanPublishPages("ICS3U", 1, new[] { "Week 1" }),
                     Linked(Club("meeting"), visible: false).PlanPublishClassOn("ICS3U", 1, "2025-09-18"),
                 })
        {
            Assert.Contains(AssistWording.LinkedClassWasLeftAloneForAMeeting(leftAlone), TeacherCopy(publishing));
            Assert.DoesNotContain(AssistWording.LinkedClassWasLeftAlone(leftAlone), TeacherCopy(publishing));
            Assert.Contains(AssistWording.LinkedClassWasLeftAlone(leftAlone), ModelCopy(publishing));
            Assert.True(publishing.Meta?[AssistToolAnswer.IsPlanKey]?.GetValue<bool>());
        }

        var hiding = Linked(Club("meeting"), visible: true).PlanUnpublishPages("ICS3U", 1, new[] { "Week 1" });
        Assert.Contains(AssistWording.LinkedClassStaysVisibleForAMeeting("Week 2"), TeacherCopy(hiding));
        Assert.DoesNotContain(AssistWording.LinkedClassStaysVisible("Week 2"), TeacherCopy(hiding));
        Assert.Contains(AssistWording.LinkedClassStaysVisible("Week 2"), ModelCopy(hiding));

        // Nothing would change and a name fits no page: an ANSWER, not a plan,
        // with the teacher's copy beside the model's (the mac nouns this card too).
        var unknown = Linked(Club("meeting"), visible: true).PlanPublishPages("ICS3U", 1, new[] { "Week 2", "Week 99" });
        Assert.Null(unknown.Meta?[AssistToolAnswer.IsPlanKey]);
        Assert.Contains(PublishPlan.NoPageIsCalledLine(new[] { "Week 99" }), TeacherCopy(unknown));
        Assert.NotNull(unknown.Meta?[AssistToolAnswer.TeacherSummaryKey]);
        var unknownWrite = Linked(Club("meeting"), visible: true)
            .PublishPages("ICS3U", 1, pages: new[] { "Week 2", "Week 99" }, preview: false).GetAwaiter().GetResult();
        Assert.Contains(PublishPlan.NoPageIsCalledLine(new[] { "Week 99" }), TeacherCopy(unknownWrite));
        Assert.NotNull(unknownWrite.Meta?[AssistToolAnswer.TeacherSummaryKey]);

        // A course that is not a club reads the class form on its card too.
        var asAClass = Linked(Club(null), visible: false).PlanPublishPages("ICS3U", 1, new[] { "Week 1" });
        Assert.Contains(AssistWording.LinkedClassWasLeftAlone(leftAlone), TeacherCopy(asAClass));
    }

    /// <summary>
    /// A club's shelf (#274): every card is matched IN CODE in a Week club —
    /// the cancel card too since #466 (the mac's #449) — in either noun — so the shelf promises
    /// nothing a model was never measured on — and no card names a unit or a
    /// page title the model would have to route.
    /// </summary>
    [Theory]
    [InlineData(ClassNoun.Meeting)]
    [InlineData(ClassNoun.Class)]
    public void AClubsShelfOffersOnlyWhatIsMatchedInCode(ClassNoun noun)
    {
        var groups = AssistPromptShelf.GroupsFor(new ClassPageNaming("Week", ClassPageScheme.Numbered), noun);
        foreach (string card in groups.SelectMany(g => g.Phrasings))
        {
            Assert.True(AssistCardCommand.Matching(card, "Week") is not null, $"“{card}” on a club's shelf is not matched in code.");
            Assert.DoesNotContain("Unit", card);
        }
        Assert.Same(AssistPromptShelf.Groups, AssistPromptShelf.GroupsFor(ClassPageNaming.Standard, ClassNoun.Class));
    }

    /// <summary>
    /// make_room_for_classes AFTER Go (review M, ruling 1): the model's copy is
    /// identical on a class course and a club and says no "meeting"; the club's
    /// teacher reads MadeRoomForAMeeting.
    /// </summary>
    [Fact]
    public void MakingRoomAfterGoSaysMeetingOnlyToTheTeacher()
    {
        var asAClass = Club(null).MakeRoomForClasses("ICS3U", 1, 1, 2);
        string classModel = ModelCopy(asAClass).Replace(System.Text.RegularExpressions.Regex.Match(ModelCopy(asAClass), @"[^ ]*\.zip").Value, "");
        var meeting = Club("meeting").MakeRoomForClasses("ICS3U", 1, 1, 2);
        string meetingModel = ModelCopy(meeting).Replace(System.Text.RegularExpressions.Regex.Match(ModelCopy(meeting), @"[^ ]*\.zip").Value, "");
        Assert.Equal(classModel, meetingModel);
        Assert.DoesNotContain("meeting", meetingModel, StringComparison.OrdinalIgnoreCase);
        Assert.Contains(AssistWording.MadeRoomForAMeeting(1, "Week 2"), TeacherCopy(meeting));
    }

    /// <summary>A refusal is one string for both audiences, in the ordinary wording.</summary>
    [Fact]
    public void ARefusalKeepsTheOrdinaryWording()
    {
        var refused = Club("meeting").PlanAddNextClass("ICS3U", 1, "next");
        Assert.Equal(NextClassPlanner.NoUnitsInANumberedCourse("ICS3U", "Week"), ModelCopy(refused));
        Assert.Null(refused.Meta?[AssistToolAnswer.TeacherSummaryKey]);
    }

    // ---- The menus' items in a club (#1027) --------------------------------------------

    private static JsonNode ItemTitles => SubjectMenusContractTests.Rule["layout"]!["itemTitles"]!;

    private static readonly System.Text.RegularExpressions.Regex SaysClass = new(@"\b[Cc]lass(es)?\b");

    /// <summary>
    /// Russell's ruling on #1027: in a club the Meetings menu's items say
    /// meeting. Every item of Section ▸ and Classes ▸ the contract lists has its
    /// <c>title</c> in a course and its <c>titleForAMeeting</c> in a club (the
    /// menu bar and a section row's menu both read <see cref="SubjectMenuLayout.TitleHere"/>);
    /// every other item says neither and has one title, so the list is
    /// complete. The mac's <c>testEveryItemTitleSaysMeetingInAClub</c>.
    /// MUST FAIL with a club title put back to its class words.
    /// </summary>
    [Fact]
    public void EveryItemTitleSaysMeetingInAClub()
    {
        var listed = ItemTitles["items"]!.AsObject();
        Assert.Equal(5, listed.Count);
        foreach (var menu in Enum.GetValues<SubjectMenuLayout.Menu>())
            foreach (var group in SubjectMenuLayout.Groups(menu))
                foreach (var entry in group)
                {
                    if (entry is not SubjectMenuLayout.Entry.OfItem(var item)) continue;
                    string? asAClass = SubjectMenuLayout.TitleHere(item, ClassNoun.Class);
                    string? asAMeeting = SubjectMenuLayout.TitleHere(item, ClassNoun.Meeting);
                    if (listed[SubjectMenuRules.ContractName(item)] is { } titles)
                    {
                        Assert.Equal(titles["title"]!.ToString(), asAClass);
                        Assert.Equal(titles["titleForAMeeting"]!.ToString(), asAMeeting);
                    }
                    else
                    {
                        Assert.Equal(asAClass, asAMeeting);
                        Assert.Null(SubjectMenuLayout.TitleSayingTheNoun(item, ClassNoun.Meeting));
                    }
                    Assert.DoesNotMatch(SaysClass, asAMeeting ?? "");
                }
        foreach (var (name, _) in listed)
            Assert.Contains(Enum.GetValues<SubjectMenuRules.Item>(), item => SubjectMenuRules.ContractName(item) == name
                                                                    && SubjectMenuLayout.MenuContaining(item) is not null);
    }

    /// <summary>The trail's "ran from a menu" path names the item as the club's menu bar draws it (<c>ranFromAMenuCases</c>). MUST FAIL with the path read in the ordinary noun.</summary>
    [Fact]
    public void TheRanFromAMenuPathSaysMeetingInAClub()
    {
        var cases = ItemTitles["ranFromAMenuCases"]!.AsArray();
        Assert.True(cases.Count >= 4);
        foreach (var c in cases)
        {
            var item = Enum.GetValues<SubjectMenuRules.Item>().Single(i => SubjectMenuRules.ContractName(i) == c!["item"]!.ToString());
            var noun = ClassPageSchemes.NounReading(c!["noun"]!.ToString());
            Assert.Equal(c["path"]!.ToString(), Plantoir.Core.Models.SubjectMenuLayout.Path(item, SubjectMenuLayout.TitleHere(item, noun)!, noun));
        }
    }

    /// <summary>
    /// Every club sentence that names one of the items names it as the club's
    /// menu bar does: where the ordinary twin says "Classes ▸ Class Dates…", the
    /// club's says "Meetings ▸ Meeting Dates…". Walks every <c>…ForAMeeting</c>
    /// and <c>…FromTheMeetingsMenu</c> key of the contract's wording.
    /// </summary>
    [Fact]
    public void EveryClubSentenceNamesTheItemAsTheClubsMenuBarDoes()
    {
        var wording = ContractLoader.LoadJson("assist-wording.json")["wording"]!.AsObject();
        int namesAnItem = 0;
        foreach (var (key, value) in wording)
        {
            string? ordinaryKey = key.EndsWith("ForAMeeting", StringComparison.Ordinal) ? key[..^"ForAMeeting".Length]
                : key.EndsWith("FromTheMeetingsMenu", StringComparison.Ordinal) ? key[..^"FromTheMeetingsMenu".Length] + "FromTheMenu"
                : null;
            if (ordinaryKey is null) continue;
            string club = value!.ToString();
            string ordinary = wording[ordinaryKey]!.ToString();
            foreach (var (name, _) in ItemTitles["items"]!.AsObject())
            {
                var item = Enum.GetValues<SubjectMenuRules.Item>().Single(i => SubjectMenuRules.ContractName(i) == name);
                string ordinaryPath = SubjectMenuLayout.Path(item, SubjectMenuLayout.TitleHere(item, ClassNoun.Class)!, ClassNoun.Class);
                if (!ordinary.Contains(ordinaryPath)) continue;
                namesAnItem++;
                Assert.Contains(SubjectMenuLayout.Path(item, SubjectMenuLayout.TitleHere(item, ClassNoun.Meeting)!, ClassNoun.Meeting), club);
            }
        }
        Assert.True(namesAnItem >= 2, $"{namesAnItem} club sentences name an item");
        Assert.Equal(wording["menuNeedsClassDatesFirstForAMeeting"]!.ToString(), AddClassWords.NeedsClassDatesFirst(ClassNoun.Meeting));
    }

    /// <summary>
    /// Undo Last Change's nothing-to-undo from the menu on a club's section
    /// names the Section or Meetings menu: the window sends the section's
    /// course in the call's <c>_meta</c> (#1027). MUST FAIL with the sentence
    /// read in the ordinary noun.
    /// </summary>
    /// <summary>
    /// #1027's review, low 5: the window's <c>_meta</c> keys are read as text
    /// or not at all. A number or an object under either key reads as absent
    /// (the Section menu, the class form) rather than throwing before the call
    /// begins. MUST FAIL with <c>GetValue&lt;string&gt;</c> put back.
    /// </summary>
    [Fact]
    public void AMetaValueThatIsNotTextReadsAsAbsent()
    {
        var meta = new JsonObject
        {
            [AssistWorkspace.CourseMetaKey] = 42,
            [AssistWorkspace.MenuMetaKey] = new JsonObject { ["menu"] = "Classes" },
        };
        Assert.Null(AssistWorkspace.MetaText(meta, AssistWorkspace.CourseMetaKey));
        Assert.Null(AssistWorkspace.MetaText(meta, AssistWorkspace.MenuMetaKey));
        Assert.Null(AssistWorkspace.MetaText(null, AssistWorkspace.CourseMetaKey));
        Assert.Null(AssistWorkspace.MetaText(new JsonObject(), AssistWorkspace.CourseMetaKey));
        Assert.Equal("ICS3U", AssistWorkspace.MetaText(new JsonObject { [AssistWorkspace.CourseMetaKey] = "ICS3U" }, AssistWorkspace.CourseMetaKey));
    }

    [Fact]
    public void NothingToUndoOnAClubsSectionNamesTheMeetingsMenu()
    {
        Club("meeting");
        var workspace = _workspace!;
        workspace.MenuCourseOfTheCall = "ICS3U";
        Assert.Equal(AssistWording.NothingToUndoFromTheMenu(ClassNoun.Meeting), workspace.NothingToUndoFromTheMenu());
        Assert.Contains("the Section or Meetings menu", workspace.NothingToUndoFromTheMenu());
        workspace.MenuCourseOfTheCall = null;
        Assert.Equal(AssistWording.NothingToUndoFromTheMenu(ClassNoun.Class), workspace.NothingToUndoFromTheMenu());
    }

    /// <summary>
    /// #1027's review, MEDIUM 1: Meetings ▸ Meeting Dates… opens the Class
    /// Dates dialog, and in a club what it says itself is the contract's
    /// <c>…ForAMeeting</c> twin: the purpose line, the status once the dates
    /// are read, the refusal of a date too far from today and the refusal of
    /// a half-read column. What the model reads stays the class form. MUST
    /// FAIL with any of them said in the ordinary noun.
    /// </summary>
    [Fact]
    public void TheClassDatesDialogSaysMeetingInAClub()
    {
        Club("meeting");
        var wording = ContractLoader.LoadJson("assist-wording.json")["wording"]!.AsObject();
        string Said(string key) => wording[key]!.ToString().Replace("{course}", "ICS3U").Replace("{section}", "1");
        string folder = Path.Combine(_folder, "courses", "ICS3U");
        var club = new Course("ICS3U", folder, CourseConfiguration.Load(Path.Combine(folder, "course_config.json")));
        Assert.Equal(ClassNoun.Meeting, club.Configuration.ClassNoun);

        Assert.Equal(Said("classDatesPurposeForAMeeting"), ClassDatesDialogWords.Purpose(club));
        Assert.Equal(Said("classDatesTooFarFromTodayForAMeeting"),
                     ClassDatesDialogWords.CannotBeADate(new[] { new DateOnly(2569, 9, 8) }, club, 1));

        var tuesdays = Enumerable.Range(0, 12).Select(week => new DateOnly(2026, 9, 8).AddDays(7 * week)).ToList();
        Assert.Equal(Said("classDatesToRememberForAMeeting").Replace("2026-12-15 (Tuesday)", "2026-11-24 (Tuesday)"),
                     ClassDatesDialogWords.Found(tuesdays, club, 1));

        const string Typed = "2026-09-08\nbanana\n2026-09-10";
        var asTheDialogReads = Assert.Throws<AssistRefusal>(() => SectionScheduleSource.ReadTypedText(Typed, null, club.Configuration.ClassNoun));
        Assert.Equal(Said("classDatesHalfReadForAMeeting").Replace("2026-13-01", "“banana”").Replace("the pasted dates", "what you pasted"),
                     asTheDialogReads.Message);
        var asTheModelReads = Assert.Throws<AssistRefusal>(() => SectionScheduleSource.ReadTypedText(Typed));
        Assert.Equal(Said("classDatesHalfRead").Replace("2026-13-01", "“banana”").Replace("the pasted dates", "what you pasted"),
                     asTheModelReads.Message);
    }

    // ---- #1027 round 3 (review 2).

    /// <summary>
    /// Every key of the contract whose words say class has a club twin
    /// (<c>…ForAMeeting</c>, or <c>…FromTheMeetingsMenu</c> for a
    /// <c>…FromTheMenu</c> key) or is on <c>staysClass</c> with its reason, and
    /// nothing stale is on that list. MUST FAIL with any twin taken out.
    /// </summary>
    [Fact]
    public void EveryClassSentenceInTheContractHasAClubFormOrAReason()
    {
        var file = ContractLoader.LoadJson("assist-wording.json");
        var wording = file["wording"]!.AsObject();
        var staysClass = file["staysClass"]!.AsObject();
        var withoutAClubForm = new List<string>();
        int saidInClass = 0;
        foreach (var (key, value) in wording)
        {
            if (key.EndsWith("ForAMeeting") || key.EndsWith("FromTheMeetingsMenu")) continue;
            if (value is not JsonValue || !SaysClass.IsMatch(value.ToString())) continue;
            saidInClass++;
            bool hasATwin = wording.ContainsKey(key + "ForAMeeting")
                || (key.EndsWith("FromTheMenu") && wording.ContainsKey(key[..^"FromTheMenu".Length] + "FromTheMeetingsMenu"));
            if (!hasATwin && !staysClass.ContainsKey(key)) withoutAClubForm.Add(key);
        }
        Assert.True(saidInClass > 50, $"only {saidInClass} class sentences read");
        Assert.True(withoutAClubForm.Count == 0, "say class with no club form and no reason: " + string.Join(", ", withoutAClubForm));
        foreach (var (key, reason) in staysClass)
        {
            Assert.True(wording.ContainsKey(key), $"staysClass names no key {key}");
            Assert.True(SaysClass.IsMatch(wording[key]!.ToString()), $"{key} no longer says class");
            Assert.False(wording.ContainsKey(key + "ForAMeeting"), $"{key} has a twin, so it is not an exception");
            Assert.False(string.IsNullOrWhiteSpace(reason!.ToString()), key);
        }
    }

    /// <summary>Review 2, MEDIUM 1: Add Meeting…'s trail counts say meeting (<c>itemTitles.countsCases</c>), and so do Deploy's hide counts.</summary>
    [Fact]
    public void TheRanFromAMenuCountsSayMeetingInAClub()
    {
        var cases = ContractLoader.LoadJson("shared-rules.json")["subjectMenus"]!["layout"]!["itemTitles"]!["countsCases"]!.AsArray();
        Assert.Equal(5, cases.Count);
        foreach (var testCase in cases)
        {
            var way = Enum.Parse<SubjectMenuRules.AddClassWay>(testCase!["way"]!.ToString(), ignoreCase: true);
            var noun = testCase["noun"]!.ToString() == "meeting" ? ClassNoun.Meeting : ClassNoun.Class;
            Assert.Equal(testCase["counts"]!.ToString(), SectionVerbs.AddClassCounts(way, noun));
        }
        Assert.Equal("1 meeting dated later, unticked at Deploy", ClassesDatedLater.UntickedAtDeployCounts(1, ClassNoun.Meeting));
        Assert.Equal("3 classes dated later, unticked at Deploy", ClassesDatedLater.UntickedAtDeployCounts(3));
    }

    /// <summary>
    /// Review 2, MEDIUM 2: a make-room plan that runs out of dates says meeting
    /// days on a club's card and in the refusal the teacher reads; the model
    /// reads the class form. MUST FAIL with the problem typed in the class noun only.
    /// </summary>
    [Fact]
    public void APlanShortOfDatesSaysMeetingToAClubsTeacher()
    {
        var tools = Club("meeting");
        var plan = tools.PlanMakeRoomForClasses("ICS3U", 1, 1, 2, 40);
        string card = TeacherCopy(plan);
        Assert.Contains("meeting day", card);
        Assert.DoesNotContain("class day", card);
        Assert.DoesNotContain("class date", card);
        Assert.Contains("class day", ModelCopy(plan));

        var write = tools.MakeRoomForClasses("ICS3U", 1, 1, 2, 40);
        Assert.Contains("meeting date", TeacherCopy(write));
        Assert.False(SaysClass.IsMatch(TeacherCopy(write)), TeacherCopy(write));
        Assert.Contains("class date", ModelCopy(write));
    }

    /// <summary>Review 2, lows 3 and 5: the assistant's dates card lines say meeting in a club; the too-far refusal names every such date.</summary>
    [Fact]
    public void TheDatesCardLinesSayMeetingAndTheRefusalNamesEveryDate()
    {
        Club("meeting");
        var wording = ContractLoader.LoadJson("assist-wording.json")["wording"]!.AsObject();
        string folder = Path.Combine(_folder, "courses", "ICS3U");
        var club = new Course("ICS3U", folder, CourseConfiguration.Load(Path.Combine(folder, "course_config.json")));
        Assert.Equal("Could not open the meeting dates dialog.", ClassDatesDialogWords.CouldNotOpen(club));
        Assert.Equal("No meeting dates were recorded.", ClassDatesDialogWords.NoneRecorded(club));
        Assert.Equal(wording["datesNotGivenYetForAMeeting"]!.ToString(), ClassDatesDialogWords.NotGivenYet(club));
        Assert.Equal(wording["rememberedTheClassDatesForAMeeting"]!.ToString().Replace("{course}", "ICS3U").Replace("{section}", "1"),
                     ClassDatesDialogWords.Remembered(12, club, 1));

        var today = new DateOnly(2026, 11, 20);
        var typed = new[] { new DateOnly(2026, 9, 8), new DateOnly(2569, 9, 8), new DateOnly(2570, 1, 5), new DateOnly(2569, 9, 8) };
        var refused = TimetableMemory.EveryUnbelievable(typed, today);
        Assert.Equal(new[] { new DateOnly(2569, 9, 8), new DateOnly(2570, 1, 5) }, refused);
        string said = ClassDatesDialogWords.CannotBeADate(refused, club, 1);
        Assert.StartsWith("2569-09-08 and 2570-01-05 are too far from today to be meeting dates", said);
        Assert.Contains("those dates corrected", said);
    }

    /// <summary>
    /// #1027 round 4: the planners' refusals were typed in code with the class
    /// word. Each is now a contract key with its twin: the teacher reads the
    /// club's, the model the class form (#267). MUST FAIL with any of them
    /// thrown without the course's noun.
    /// </summary>
    [Fact]
    public void ThePlannersRefusalsSayMeetingToAClubsTeacher()
    {
        var wording = ContractLoader.LoadJson("assist-wording.json")["wording"]!.AsObject();
        var tools = Club("meeting");
        var none = tools.PlanMakeRoomForClasses("ICS3U", 1, 1, 2, 0);
        Assert.Equal(wording["askForAtLeastOneClassForAMeeting"]!.ToString(), TeacherCopy(none));
        Assert.Equal(wording["askForAtLeastOneClass"]!.ToString(), ModelCopy(none));

        File.Delete(Path.Combine(_folder, "courses", "ICS3U", ".internal", "timetable", "section1.json"));
        var noDates = tools.PlanMakeRoomForClasses("ICS3U", 1, 1, 2, 1);
        Assert.Equal(AssistWording.CannotMoveClassesWithoutDatesForAMeeting("ICS3U", 1), TeacherCopy(noDates));
        Assert.Equal(AssistWording.CannotMoveClassesWithoutDates("ICS3U", 1), ModelCopy(noDates));
    }

    /// <summary>
    /// The guard's other half: every club twin says meeting and never class, so
    /// a twin typed by copying the class form fails here. MUST FAIL with a
    /// <c>…ForAMeeting</c> key that still says class.
    /// </summary>
    [Fact]
    public void EveryClubTwinSaysMeetingAndNeverClass()
    {
        var wording = ContractLoader.LoadJson("assist-wording.json")["wording"]!.AsObject();
        var twinsSayingClass = new List<string>();
        int twinsRead = 0;
        foreach (var (key, value) in wording)
        {
            if (!key.EndsWith("ForAMeeting") && !key.EndsWith("FromTheMeetingsMenu")) continue;
            if (value is not JsonValue) continue;
            twinsRead++;
            if (SaysClass.IsMatch(value.ToString())) twinsSayingClass.Add(key);
        }
        Assert.True(twinsRead > 50, $"only {twinsRead} twins read");
        Assert.True(twinsSayingClass.Count == 0, "a club twin says class: " + string.Join(", ", twinsSayingClass));
    }
}

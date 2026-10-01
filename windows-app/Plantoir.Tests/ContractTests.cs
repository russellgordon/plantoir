using System.Reflection;
using System.Text.Json.Nodes;
using Plantoir.Core;
using Plantoir.Core.Assist;
using Plantoir.Core.Catalogs;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

public class ContractTests
{
    /// <summary>
    /// <c>assist-wording.json</c> → <c>wording</c> is THE list (#157): every key
    /// is walked by reflection, in both directions, rather than named here one
    /// line at a time. A key the mac adds with no member here goes red naming
    /// itself; a member here with no key goes red too, unless it is one of the
    /// sentences this app says and the mac says differently
    /// (<see cref="WindowsOnlyWording"/>). A key this app does not carry yet is
    /// held open BY NAME in <see cref="NamedGapLedger"/> against the issue that
    /// owns it, and the ledger fails the day it starts existing.
    ///
    /// <para>What is compared. A key is resolved to a public static member of
    /// the same name (first letter upper-cased) on <c>AssistWording</c>, then on
    /// <c>ClassChangeWording</c>, where the duplicate-and-copy sentences live. A
    /// constant is compared with the file WHOLE. A method cannot be compared
    /// generically — its example values live in the file, not in its
    /// signature — so the methods keep their hand-written calls below, with the
    /// placeholder convention of the generator ("{course}", "{section}", 2).</para>
    /// </summary>
    [Fact]
    public void AssistWording_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("assist-wording.json");
        var wording = doc["wording"]!.AsObject();

        // ---- The methods, by hand: their example values come from the file.
        Assert.Equal(wording["deployed"]!.ToString(), AssistWording.Deployed("{course}", "{section}"));
        Assert.Equal(wording["couldNotBuildBeforeDeploying"]!.ToString(), AssistWording.CouldNotBuildBeforeDeploying("{course}", "{section}"));
        Assert.Equal(wording["deployDidNotFinish"]!.ToString(), AssistWording.DeployDidNotFinish("{course}", "{section}"));
        Assert.Equal(wording["sectionIsBusy"]!.ToString(), AssistWording.SectionIsBusy("{course}", "{section}"));
        Assert.Equal(wording["courseIsBusy"]!.ToString(), AssistWording.CourseIsBusy("{course}"));
        Assert.Equal(wording["courseIsBeingBuiltElsewhere"]!.ToString(), AssistWording.CourseIsBeingBuiltElsewhere("{course}"));
        Assert.Equal(wording["deployWentOutTo"]!.ToString(), AssistWording.DeployWentOutTo("{destinations}"));

        Assert.Equal(wording["previewIsRebuilding"]!.ToString(), AssistWording.PreviewIsRebuilding("{course}", "{section}"));
        Assert.Equal(wording["builtWithNoWindowOpen"]!.ToString(), AssistWording.BuiltWithNoWindowOpen("{course}", "{section}"));
        Assert.Equal(wording["rebuiltForACallerWithNoWindow"]!.ToString(), AssistWording.RebuiltForACallerWithNoWindow("{course}", "{section}"));
        Assert.Equal(wording["previewDidNotBuild"]!.ToString(), AssistWording.PreviewDidNotBuild("{course}", "{section}"));

        Assert.Equal(wording["undid"]!.ToString(), AssistWording.Undid("{change}"));
        Assert.Equal(wording["undidPartly"]!.ToString(), AssistWording.UndidPartly("{change}", 2));
        Assert.Equal(wording["couldNotUndo"]!.ToString(), AssistWording.CouldNotUndo("{change}", 2));

        // Both said straight to a teacher now that "back up this course" and
        // "what does publishing mean?" are fixed phrasings, matched in code.
        Assert.Equal(wording["backedUpCourse"]!.ToString(),
                     AssistWording.BackedUpCourse("{course}", "{course}_backup_2026-09-08_190000.zip"));
        Assert.Equal(wording["publishingAlreadyExplained"]!.ToString(),
                     AssistWording.PublishingAlreadyExplained("{course}", "{section}"));

        // The two with a value in them carry the generator's own example.
        Assert.Equal(wording["rolloverStartedANewWebsite"]!.ToString(),
                     AssistWording.RolloverStartedANewWebsite(
                         ".netlify_sites/section1.previous-2026-09-08_071500.json"));
        Assert.Equal(wording["rolloverCouldNotStartANewWebsite"]!.ToString(),
                     AssistWording.RolloverCouldNotStartANewWebsite(".netlify_sites/section1.json"));

        // The class-planning sentences hoisted on 2026-09-30, with the
        // generator's own examples.
        Assert.Equal(wording["madeRoom"]!.ToString(), AssistWording.MadeRoom(1, "Unit 3, Day 4"));
        Assert.Equal(wording["movedToLaterDays"]!.ToString(), AssistWording.MovedToLaterDays(3));
        Assert.Equal(wording["movesAndBecomesADraft"]!.ToString(), AssistWording.MovesAndBecomesADraft("{page}", "2026-12-15"));
        Assert.Equal(wording["publishedTheClassOn"]!.ToString(), AssistWording.PublishedTheClassOn("2026-09-14"));
        Assert.Equal(wording["reDatingOntoTheDatesOnFile"]!.ToString(), AssistWording.ReDatingOntoTheDatesOnFile("{course}", "{section}"));
        Assert.Equal(wording["theNextWouldFallOn"]!.ToString(), AssistWording.TheNextWouldFallOn("2026-09-14", "Monday"));

        // #352 (mac #197) and #203 / #342 (mac #173 / #201): methods, so the
        // value walk below cannot see them; rendered here with the
        // contract's own placeholders and literal titles.
        Assert.Equal(wording["everyPageIsNotAPageToPublish"]!.ToString(), AssistWording.EveryPageIsNotAPageToPublish("{example}"));
        Assert.Equal(wording["everyPageIsNotAPageToHide"]!.ToString(), AssistWording.EveryPageIsNotAPageToHide("{example}"));
        Assert.Equal(wording["noPageCalled"]!.ToString(), AssistWording.NoPageCalled("{course}", "{section}", "{page}"));
        Assert.Equal(wording["noPagesCalled"]!.ToString(), AssistWording.NoPagesCalled("{course}", "{section}", "{pages}"));
        Assert.Equal(wording["linkedClassWasLeftAlone"]!.ToString(), AssistWording.LinkedClassWasLeftAlone(new[] { "Unit 2, Day 4" }));
        Assert.Equal(wording["linkedClassesWereLeftAlone"]!.ToString(),
                     AssistWording.LinkedClassesWereLeftAlone(new[] { "Unit 2, Day 4", "Unit 2, Day 5" }));
        Assert.Equal(wording["linkedClassStaysVisible"]!.ToString(), AssistWording.LinkedClassStaysVisible("Unit 2, Day 4"));
        // #305 (mac #167): the links answer.
        Assert.Equal(wording["pageLinksTo"]!.ToString(), AssistWording.PageLinksTo("{page}"));
        Assert.Equal(wording["pageLinksToNothing"]!.ToString(), AssistWording.PageLinksToNothing("{page}"));
        Assert.Equal(wording["morePagesThanOneAreCalled"]!.ToString(), AssistWording.MorePagesThanOneAreCalled("{course}", "{section}", "{page}"));
        Assert.Equal(wording["pageCouldNotBeRead"]!.ToString(), AssistWording.PageCouldNotBeRead("{page}"));

        // #281/#288: rendered by running this app's own functions on the
        // inputs the generator used, so the keys test the code path rather
        // than a template.
        Assert.Equal(wording["morningOrEvening"]!.ToString(),
                     AssistWording.MorningOrEvening(AssistCardCommand.MorningOrEvening("deploy at 6:30")!));
        Assert.Equal(wording["sayTheTimeAs"]!.ToString(),
                     AssistWording.SayTheTimeAs(AssistCardCommand.TimeToSayAs("deploy at 6.30 pm")!));
        Assert.Equal(wording["sayTheTimeAsWithoutTheComma"]!.ToString(),
                     AssistWording.SayTheTimeAs(AssistCardCommand.TimeToSayAs("deploy at 6:30 pm,")!));

        // #180: a call the model made for another course.
        Assert.Equal(wording["askedAboutAnotherCourse"]!.ToString(),
                     AssistWording.AskedAboutAnotherCourse("{course}", "{otherCourse}"));
        Assert.Equal(wording["askedAboutACourseThatIsNotHere"]!.ToString(),
                     AssistWording.AskedAboutACourseThatIsNotHere("{course}", "{otherCourse}"));

        // #274 (mac #267): the class/meeting pairs, each rendered with the
        // generator's own example values. The meeting form is the TEACHER's
        // copy only — ClubNounTests pins that it never reaches the model.
        void Pair(string key, string forAClass, string forAMeeting)
        {
            Assert.Equal(wording[key]!.ToString(), forAClass);
            Assert.Equal(wording[key + "ForAMeeting"]!.ToString(), forAMeeting);
        }
        Pair("addedTheNextPage", AssistWording.AddedTheNextPage, AssistWording.AddedTheNextPageForAMeeting);
        Pair("allScheduledDatesHaveConcluded",
             AssistWording.AllScheduledDatesHaveConcluded(12, "{course}", "{section}", "Tuesday", "2026-12-15"),
             AssistWording.AllScheduledDatesHaveConcludedForAMeeting(12, "{course}", "{section}", "Tuesday", "2026-12-15"));
        Pair("datesForTheNextPage", AssistWording.DatesForTheNextPage, AssistWording.DatesForTheNextPageForAMeeting);
        Pair("datesNotGivenYet", AssistWording.DatesNotGivenYet, AssistWording.DatesNotGivenYetForAMeeting);
        Pair("datesToDuplicate", AssistWording.DatesToDuplicate, AssistWording.DatesToDuplicateForAMeeting);
        Pair("datesToFindADaysPage", AssistWording.DatesToFindADaysPage, AssistWording.DatesToFindADaysPageForAMeeting);
        Pair("datesToReDate", AssistWording.DatesToReDate, AssistWording.DatesToReDateForAMeeting);
        Pair("datesToReplace", AssistWording.DatesToReplace("{course}", "{section}"),
             AssistWording.DatesToReplaceForAMeeting("{course}", "{section}"));
        Pair("everyDateIsSpokenFor", AssistWording.EveryDateIsSpokenFor, AssistWording.EveryDateIsSpokenForForAMeeting);
        Assert.Equal(wording["linkedClassStaysVisibleForAMeeting"]!.ToString(), AssistWording.LinkedClassStaysVisibleForAMeeting("Week 4"));
        Assert.Equal(wording["linkedClassWasLeftAloneForAMeeting"]!.ToString(), AssistWording.LinkedClassWasLeftAloneForAMeeting(new[] { "Week 4" }));
        Assert.Equal(wording["linkedClassesWereLeftAloneForAMeeting"]!.ToString(),
                     AssistWording.LinkedClassesWereLeftAloneForAMeeting(new[] { "Week 4", "Week 5" }));
        Assert.Equal(wording["madeRoomForAMeeting"]!.ToString(), AssistWording.MadeRoomForAMeeting(1, "Week 5"));
        Pair("makingRoomCannotBeUndone", AssistWording.MakingRoomCannotBeUndone, AssistWording.MakingRoomCannotBeUndoneForAMeeting);
        Pair("mayIAskForYourDates", AssistWording.MayIAskForYourDates, AssistWording.MayIAskForYourDatesForAMeeting);
        Pair("movedToLaterDays", AssistWording.MovedToLaterDays(3), AssistWording.MovedToLaterDaysForAMeeting(3));
        Pair("movesAndBecomesADraft", AssistWording.MovesAndBecomesADraft("{page}", "2026-12-15"),
             AssistWording.MovesAndBecomesADraftForAMeeting("{page}", "2026-12-15"));
        Pair("movesToTheFirstDay", AssistWording.MovesToTheFirstDay("{page}", "2026-09-08"),
             AssistWording.MovesToTheFirstDayForAMeeting("{page}", "2026-09-08"));
        Pair("otherClassesWouldMoveAndLinksFollow", ClassChangeWording.OtherClassesWouldMoveAndLinksFollow(2),
             ClassChangeWording.OtherClassesWouldMoveAndLinksFollowForAMeeting(2));
        Pair("otherClassesWouldMoveKeepingTheirNames", ClassChangeWording.OtherClassesWouldMoveKeepingTheirNames(2),
             ClassChangeWording.OtherClassesWouldMoveKeepingTheirNamesForAMeeting(2));
        Pair("pagesAcrossTheDates", AssistWording.PagesAcrossTheDates("{course}", "{section}", 4, 12, 8),
             AssistWording.PagesAcrossTheDatesForAMeeting("{course}", "{section}", 4, 12, 8));
        Pair("pagesRunFrom", AssistWording.PagesRunFrom(12, "2026-09-08", "Tuesday", "2026-12-15", "Tuesday"),
             AssistWording.PagesRunFromForAMeeting(12, "2026-09-08", "Tuesday", "2026-12-15", "Tuesday"));
        Pair("pagesWithNoDayOfTheirOwn", AssistWording.PagesWithNoDayOfTheirOwn(2, "2026-12-15"),
             AssistWording.PagesWithNoDayOfTheirOwnForAMeeting(2, "2026-12-15"));
        Pair("publishedTheClassOn", AssistWording.PublishedTheClassOn("2026-09-14"), AssistWording.PublishedTheClassOnForAMeeting("2026-09-14"));
        Pair("reDated", AssistWording.ReDated(12, 5), AssistWording.ReDatedForAMeeting(12, 5));
        Pair("reDatedOnlyPagesTheyUse", AssistWording.ReDatedOnlyPagesTheyUse(3), AssistWording.ReDatedOnlyPagesTheyUseForAMeeting(3));
        Pair("reDatingOntoTheDatesOnFile", AssistWording.ReDatingOntoTheDatesOnFile("{course}", "{section}"),
             AssistWording.ReDatingOntoTheDatesOnFileForAMeeting("{course}", "{section}"));
        Pair("sharingTheLastDay", AssistWording.SharingTheLastDay, AssistWording.SharingTheLastDayForAMeeting);
        Pair("spareDatesAfterThese", AssistWording.SpareDatesAfterThese(3, "timetable.xlsx, block H"),
             AssistWording.SpareDatesAfterTheseForAMeeting(3, "timetable.xlsx, block H"));
        Pair("theNextWouldFallOn", AssistWording.TheNextWouldFallOn("2026-09-14", "Monday"),
             AssistWording.TheNextWouldFallOnForAMeeting("2026-09-14", "Monday"));
        Pair("theSemesterBegins", AssistWording.TheSemesterBegins("Tuesday", "2026-09-08", 3),
             AssistWording.TheSemesterBeginsForAMeeting("Tuesday", "2026-09-08", 3));
        Pair("wouldAddPages", AssistWording.WouldAddPages(1, "Unit 4", "{course}", "{section}"),
             AssistWording.WouldAddPagesForAMeeting(1, "{course}", "{section}"));
        Pair("wouldMakeRoom", AssistWording.WouldMakeRoom(2, "Unit 3, Day 4", "{course}", "{section}"),
             AssistWording.WouldMakeRoomForAMeeting(2, "Week 5", "{course}", "{section}"));
        Pair("yourNextUpcoming", AssistWording.YourNextUpcoming(3, "{course}", "{section}"),
             AssistWording.YourNextUpcomingForAMeeting(3, "{course}", "{section}"));

        // #241: a course kept for reference.
        Assert.Equal(wording["askedAboutAReferenceCourse"]!.ToString(),
                     AssistWording.AskedAboutAReferenceCourse("{course}", "{otherCourse}"));
        Assert.Equal(wording["deployRefusedForAReferenceCourse"]!.ToString(),
                     AssistWording.DeployRefusedForAReferenceCourse("{course}"));

        // ---- The walk: the file is the list.
        var keys = wording.Select(pair => pair.Key).ToList();
        var here = keys.Where(key => WordingMember(key) is not null).ToList();
        var deferred = NamedGapLedger.GapsIn(NamedGapLedger.AssistWordingKeys, keys, here);

        var unresolved = keys
            .Where(key => WordingMember(key) is null && !deferred.Contains(key))
            .ToList();
        Assert.True(unresolved.Count == 0,
            "assist-wording.json names sentences with no member of the same name on AssistWording or " +
            "ClassChangeWording, and no NamedGapLedger entry holding them open: " +
            string.Join(", ", unresolved) + ". Add the member (the mac owns the words; copy them), or " +
            "ledger the key by name against the open issue that owns it.");

        // ---- The other direction: a member of AssistWording with no key.
        var keySet = keys.ToHashSet(StringComparer.Ordinal);
        var members = typeof(AssistWording)
            .GetMembers(BindingFlags.Public | BindingFlags.Static | BindingFlags.DeclaredOnly)
            .Where(member => member is FieldInfo or MethodInfo { IsSpecialName: false })
            .Select(member => member.Name)
            .Distinct()
            .ToList();
        foreach (var (name, why) in WindowsOnlyWording)
        {
            Assert.True(members.Contains(name),
                $"WindowsOnlyWording names {name}, which AssistWording no longer has: delete the entry ({why}).");
            Assert.False(keySet.Contains(char.ToLowerInvariant(name[0]) + name[1..]),
                $"WindowsOnlyWording names {name}, and assist-wording.json now carries it as a key: delete " +
                "the entry so the walk compares it.");
        }
        var keyless = members
            .Where(name => !keySet.Contains(char.ToLowerInvariant(name[0]) + name[1..]))
            .Where(name => !WindowsOnlyWording.ContainsKey(name))
            .ToList();
        Assert.True(keyless.Count == 0,
            "AssistWording carries sentences assist-wording.json does not name: " + string.Join(", ", keyless) +
            ". The mac owns the sentence (CLAUDE.md rule 2): propose the key on a `mac` issue, or say here " +
            "why the two apps word it differently.");

        // ---- Values last, so a sentence that differs cannot hide a missing key.
        var differs = here
            .Select(key => (key, member: WordingMember(key)))
            .Where(entry => entry.member is FieldInfo { FieldType: var type } && type == typeof(string))
            .Where(entry => (string?)((FieldInfo)entry.member!).GetValue(null) != wording[entry.key]!.ToString())
            .Select(entry => $"{entry.key}: contract \"{wording[entry.key]}\", here \"{((FieldInfo)entry.member!).GetValue(null)}\"")
            .ToList();
        Assert.True(differs.Count == 0,
            "These sentences differ from assist-wording.json:\n" + string.Join("\n", differs));
    }

    /// <summary>
    /// Sentences AssistWording carries that the contract deliberately does not,
    /// each with its reason. Mend-checked both ways by the test above.
    /// </summary>
    private static readonly Dictionary<string, string> WindowsOnlyWording = new(StringComparer.Ordinal)
    {
        ["DeployedToMultipleDestinations"] =
            "this app's own sentence for a deploy to more than one destination; the mac says " +
            "wording.deployed; the multi-destination sentences are the same on both apps but not generated into the contract",
        ["DeployPartiallySucceeded"] =
            "this app's own sentence for a deploy that reached some destinations; the mac's shape is " +
            "the same sentence (not generated into the contract); wording.deployWentOutTo follows #391's needs-an-answer sentence",
        ["DeployToMultipleDestinationsDidNotFinish"] =
            "this app's own sentence for a deploy that reached none of several destinations; owed on #400",
    };

    /// <summary>The public static member a wording key names, or null.</summary>
    private static MemberInfo? WordingMember(string key)
    {
        string name = char.ToUpperInvariant(key[0]) + key[1..];
        return new[] { typeof(AssistWording), typeof(ClassChangeWording) }
            .Select(home => home.GetMember(name, BindingFlags.Public | BindingFlags.Static).FirstOrDefault())
            .FirstOrDefault(member => member is not null);
    }

    [Fact]
    public void FileFormats_PageVisibilityReadingCases()
    {
        var doc = ContractLoader.LoadJson("file-formats.json");
        var cases = doc["pageVisibility"]!["readingCases"]!.AsArray();

        foreach (var c in cases)
        {
            string pageText = c!["page"]!.ToString();
            bool expectedVisible = c["expectVisible"]!.GetValue<bool>();
            int section = c["section"]?.GetValue<int>() ?? 1;

            string fullFrontmatter = $"---\n{pageText}\n---\n# Content";

            bool actualVisible = !PageFrontmatter.IsDraft(fullFrontmatter, section);

            Assert.True(actualVisible == expectedVisible,
                $"Case '{pageText}' (section {section}) expected visible={expectedVisible} but got {actualVisible}");
        }
    }

    [Fact]
    public void CourseManagement_GradeLabels_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("course-management.json");
        var cases = doc["gradeLabels"]!["cases"]!.AsArray();

        foreach (var c in cases)
        {
            if (c is null) continue;
            string code = c["code"]!.ToString();
            string expectedLabel = c["expect"]!.ToString();
            string actual = SectionAdder.GradeLabel(code);
            Assert.Equal(expectedLabel, actual);
        }
    }

    [Fact]
    public void CourseManagement_CourseCode_Normalized_And_Problems_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("course-management.json");
        var normalizedCases = doc["courseCode"]!["normalized"]!.AsArray();

        foreach (var c in normalizedCases)
        {
            string typed = c!["typed"]!.ToString();
            string expected = c["expect"]!.ToString();
            Assert.Equal(expected, CourseCodeValidator.Normalize(typed));
        }

        var problemCases = doc["courseCode"]!["problems"]!.AsArray();
        foreach (var c in problemCases)
        {
            string typed = c!["typed"]!.ToString();
            var existing = c["existing"]!.AsArray().Select(e => e!.ToString()).ToList();
            string? currentCode = c["currentCode"]?.ToString();
            string? expectProblem = c["expectProblem"]?.ToString();
            string? expectShort = c["expectShort"]?.ToString();

            var (problem, shortProblem) = CourseCodeValidator.Validate(typed, existing, currentCode);
            Assert.Equal(expectProblem, problem);
            Assert.Equal(expectShort, shortProblem);
        }
    }

    [Fact]
    public void CourseManagement_ClubDetection_MatchesContract()
    {
        string onFile = ContractLoader.GetSupportPath("ontario_secondary_courses.json");
        string bcFile = ContractLoader.GetSupportPath("british_columbia_secondary_courses.json");
        var catalog = CourseNameCatalog.Load(onFile, bcFile);

        var doc = ContractLoader.LoadJson("course-management.json");
        var cases = doc["courseCode"]!["clubDetection"]!["cases"]!.AsArray();

        foreach (var c in cases)
        {
            string code = c!["code"]!.ToString();
            bool expectClub = c["expectClub"]!.GetValue<bool>();
            Assert.Equal(expectClub, ClubCodeRule.IsClub(code, catalog));
        }
    }

    [Fact]
    public void CourseManagement_DefaultCourseName_MatchesContract()
    {
        string onFile = ContractLoader.GetSupportPath("ontario_secondary_courses.json");
        string bcFile = ContractLoader.GetSupportPath("british_columbia_secondary_courses.json");
        var catalog = CourseNameCatalog.Load(onFile, bcFile);

        var doc = ContractLoader.LoadJson("course-management.json");
        var cases = doc["defaultCourseName"]!["cases"]!.AsArray();

        foreach (var c in cases)
        {
            string code = c!["code"]!.ToString();
            string? expect = c["expect"]?.ToString();
            string? actual = catalog.DefaultName(code);
            Assert.Equal(expect, actual);
        }
    }

    [Fact]
    public void CourseManagement_SectionNumbers_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("course-management.json");
        var sectionNumbers = doc["sectionNumbers"]!.AsObject();

        // suggested
        var suggested = sectionNumbers["suggested"]!.AsArray();
        foreach (var s in suggested)
        {
            var existing = s!["existing"]!.AsArray().Select(x => x!.GetValue<int>()).ToList();
            int expect = s["expect"]!.GetValue<int>();
            Assert.Equal(expect, SectionAdder.SuggestedNumber(existing));
        }

        // addable
        var addable = sectionNumbers["addable"]!.AsArray();
        foreach (var a in addable)
        {
            string entry = a!["entry"]!.ToString();
            var existing = a["existing"]!.AsArray().Select(x => x!.GetValue<int>()).ToList();
            bool expect = a["expect"]!.GetValue<bool>();
            Assert.Equal(expect, SectionAdder.EntryIsAddable(entry, existing));
        }

        // entryProblems
        var entryProblems = sectionNumbers["entryProblems"]!.AsArray();
        foreach (var ep in entryProblems)
        {
            string entry = ep!["entry"]!.ToString();
            var existing = ep["existing"]!.AsArray().Select(x => x!.GetValue<int>()).ToList();
            string? expect = ep["expectProblem"]?.ToString();
            Assert.Equal(expect, SectionAdder.EntryProblem(entry, existing, "ICS3U"));
        }
    }

    [Fact]
    public void CourseManagement_ZipNames_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("course-management.json");
        var zipNames = doc["zipNames"]!.AsObject();
        string courseCode = zipNames["courseCode"]!.ToString();
        var cases = zipNames["cases"]!.AsArray();

        foreach (var c in cases)
        {
            string kind = c!["kind"]!.ToString();
            string name = c["name"]!.ToString();
            string filePath = $@"C:\folder\_backups\{courseCode}\{name}";

            var backup = BackupItem.From(filePath, courseCode);
            var archive = ArchivedItem.From(filePath, courseCode);

            switch (kind)
            {
                case "backup":
                    Assert.NotNull(backup);
                    Assert.Null(archive);
                    string expectedMaker = c["maker"]?.ToString() ?? "teacher";
                    if (expectedMaker == "teacher")
                    {
                        Assert.IsType<BackupMaker.Teacher>(backup!.Maker);
                    }
                    else if (expectedMaker == "assistant")
                    {
                        Assert.IsType<BackupMaker.Assistant>(backup!.Maker);
                        int expectedSection = c["section"]!.GetValue<int>();
                        Assert.Equal(expectedSection, ((BackupMaker.Assistant)backup.Maker).SectionNumber);
                    }
                    break;
                case "archive":
                    Assert.NotNull(archive);
                    Assert.Null(backup);
                    if (c["section"] is JsonNode secNode)
                    {
                        Assert.Equal(secNode.GetValue<int>(), archive!.SectionNumber);
                    }
                    else
                    {
                        Assert.Null(archive!.SectionNumber);
                    }
                    break;
                case "neither":
                    Assert.Null(backup);
                    Assert.Null(archive);
                    break;
            }
        }
    }

    [Fact]
    public void SharedRules_FollowingLinks_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var following = doc["followingLinks"]!.AsObject();

        Assert.True(following["publishing"]!["takesLinkedPages"]!.GetValue<bool>());
        Assert.True(following["publishing"]!["transitive"]!.GetValue<bool>());
        Assert.True(following["publishing"]!["disclosedInThePlan"]!.GetValue<bool>());

        Assert.True(following["unpublishing"]!["takesALinkedPageOnlyWhenNothingElseNeedsIt"]!.GetValue<bool>());
        Assert.True(following["unpublishing"]!["aReferrerCountsOnlyWhenVisible"]!.GetValue<bool>());

        var exclusions = following["neverTakenDownByFollowingLinks"]!.AsArray();
        Assert.Equal(3, exclusions.Count);
    }

    [Fact]
    public void SharedRules_ActivityTrailEvents_Exist()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var events = doc["activityTrail"]!["mustRecord"]!.AsArray();

        // `appliesOn` names the platforms an event belongs to; an entry
        // without it belongs to both. Honouring it is not a loosening: the
        // assertion below is still equality, so an event this app records
        // and the contract does not still fails. Without it, "built site
        // moved out of the working folder" (appliesOn: mac) held this test
        // red on Windows no matter what was implemented here, and a test
        // that cannot go green stops being read.
        var contractKeys = events
            .Where(e => e!["appliesOn"] is null
                        || e!["appliesOn"]!.AsArray().Any(p => p!.ToString() == "windows"))
            .Select(e => e!["event"]!.ToString())
            .ToHashSet();

        var codeKeys = Enum.GetValues<ActivityTrail.Event>()
            .Select(ActivityTrail.KeyFor)
            .ToHashSet();

        // `appliesOn` above is for a difference that is permanent and
        // deliberate. This is the other case: an event Windows OWES and has
        // not built yet, named in the ledger with the issue and the milestone
        // that own it. Everything not in the ledger is still compared for
        // equality, and the ledger itself fails if the event starts existing
        // here or stops being in the contract. See NamedGapLedger for why this
        // is not written into the contract as `appliesOn`.
        var deferred = NamedGapLedger.GapsIn(
            NamedGapLedger.ActivityTrailEvents, contractKeys, codeKeys);

        Assert.Equal(contractKeys.Except(deferred).ToHashSet(), codeKeys);
    }

    [Fact]
    public void AppRules_PreviewPorts_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("app-rules.json");
        var previewPorts = doc["previewPorts"]!;
        int wsOffset = previewPorts["websocketOffset"]!.GetValue<int>();
        Assert.Equal(1000, wsOffset);
    }

    [Fact]
    public void SharedRules_WorkingFolderPathBar_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var bar = doc["workingFolderPathBar"]!;
        var actions = bar["actions"]!.AsArray();

        var revealAction = actions.FirstOrDefault(a => a?["action"]?.ToString() == "reveal");
        Assert.NotNull(revealAction);
        Assert.Equal("Show in File Explorer", revealAction["windowsLabel"]?.ToString());

        var openAction = actions.FirstOrDefault(a => a?["action"]?.ToString() == "open");
        Assert.NotNull(openAction);
        Assert.Equal("Open Folder", openAction["windowsLabel"]?.ToString());

        // The ancestor crumbs were hand-typed here until 2026-09-06 and are
        // now DATA: shared-rules.json → workingFolderPathBar.ancestorPaths
        // gained `windowsCases`, and SharedRuleContractTests runs them. A copy
        // kept here as well would be the thing contracts/ exists to end.
    }

    [Fact]
    public void AppRules_CredentialPrompts_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("app-rules.json");
        var cases = doc["credentialPrompts"]!["cases"]!.AsArray();

        foreach (var c in cases)
        {
            if (c is null) continue;
            string prompt = c["prompt"]!.ToString();
            string expectRequest = c["expectRequest"]!.ToString();

            var match = CredentialRequests.MatchPrompt(prompt);
            string actualName = match?.Name ?? "";
            Assert.Equal(expectRequest, actualName);
        }
    }

    [Fact]
    public void AppRules_CredentialRequests_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("app-rules.json");
        var requests = doc["credentialRequests"]!["requests"]!.AsArray();

        var codeRequests = new Dictionary<string, CredentialRequest>
        {
            ["netlifyToken"] = CredentialRequests.NetlifyToken,
            ["cloudflareToken"] = CredentialRequests.CloudflareToken,
            ["cloudflareAccountID"] = CredentialRequests.CloudflareAccountID,
            ["cloudflareAccountIDHelp"] = CredentialRequests.CloudflareAccountIDHelp,
            ["teacherSurname"] = CredentialRequests.TeacherSurname,
            ["siteName"] = CredentialRequests.SiteName,
            ["siteNameConflict"] = CredentialRequests.SiteNameConflict,
        };

        foreach (var req in requests)
        {
            if (req is null) continue;
            string name = req["name"]!.ToString();
            Assert.True(codeRequests.TryGetValue(name, out var codeReq), $"Missing request definition for {name}");

            Assert.Equal(req["title"]!.ToString(), codeReq!.Title);
            // The explanation is the LONGEST thing a teacher reads in one of
            // these dialogs and was the one field this sweep did not check —
            // found 2026-09-07 while writing the hand-driven procedure for the
            // new-site dialog, which told the checker not to eyeball it
            // "because the contract pins it". It did not. It does now.
            Assert.Equal(req["explanation"]!.ToString(), codeReq.Explanation);
            Assert.Equal(req["fieldLabel"]!.ToString(), codeReq.FieldLabel);
            Assert.Equal(req["isSecret"]!.GetValue<bool>(), codeReq.IsSecret);
            Assert.Equal(req["linkAddress"]!.ToString(), codeReq.LinkAddress);
            Assert.Equal(req["linkTitle"]!.ToString(), codeReq.LinkTitle);

            var expectSteps = req["steps"]!.AsArray().Select(s => s!.ToString()).ToList();
            Assert.Equal(expectSteps, codeReq.Steps);
        }
    }

    [Fact]
    public void SharedRules_CurriculumRules_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var rules = doc["curriculumRules"]!;

        // expectationWording
        var wordingCases = rules["expectationWording"]!["cases"]!.AsArray();
        foreach (var c in wordingCases)
        {
            if (c is null) continue;
            string body = c["body"]!.ToString();
            string expect = c["expect"]!.ToString();
            string actual = CurriculumRules.ExpectationWording(body);
            Assert.Equal(expect, actual);
        }

        // isCurriculumPage
        var pageCases = rules["isCurriculumPage"]!["cases"]!.AsArray();
        foreach (var c in pageCases)
        {
            if (c is null) continue;
            string path = c["path"]!.ToString();
            bool expect = c["expect"]!.GetValue<bool>();
            bool actual = CurriculumRules.IsCurriculumPage(path);
            Assert.Equal(expect, actual);
        }

        // isExpectationCode
        var codeCases = rules["isExpectationCode"]!["cases"]!.AsArray();
        foreach (var c in codeCases)
        {
            if (c is null) continue;
            string code = c["code"]!.ToString();
            bool expect = c["expect"]!.GetValue<bool>();
            bool actual = CurriculumRules.IsExpectationCode(code);
            Assert.Equal(expect, actual);
        }
    }

    [Fact]
    public void SharedRules_AssistantModelChoice_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var modelChoice = doc["assistantModelChoice"]!;

        Assert.Equal("automatic", modelChoice["defaultChoice"]!.ToString());

        var choices = modelChoice["choices"]!.AsArray();
        var choiceKeys = choices.Select(c => c!["key"]!.ToString()).ToList();
        Assert.Equal(new[] { "automatic", "smaller", "larger" }, choiceKeys);

        foreach (var c in choices)
        {
            string key = c!["key"]!.ToString();
            string expectLabel = c["label"]!.ToString();
            Assert.Equal(expectLabel, AssistModelChoice.Label(key));
        }

        // Automatic choice resolves at point of use based on budget
        var budget8Gb = new AssistHardwareBudget(8L * 1024 * 1024 * 1024);
        var budget16Gb = new AssistHardwareBudget(16L * 1024 * 1024 * 1024);

        Assert.Equal(AssistModelTier.Small, AssistModelChoice.Resolved(AssistModelChoice.Automatic, budget8Gb));
        Assert.Equal(AssistModelTier.Large, AssistModelChoice.Resolved(AssistModelChoice.Automatic, budget16Gb));

        // Automatic never produces a caution
        Assert.Null(AssistModelChoice.Caution(AssistModelChoice.Automatic, budget8Gb));
        Assert.Null(AssistModelChoice.Caution(AssistModelChoice.Automatic, budget16Gb));

        // Hand-picked larger choice on 8 GB machine produces caution naming memory numbers
        string? caution = AssistModelChoice.Caution(AssistModelChoice.Larger, budget8Gb);
        Assert.NotNull(caution);
        Assert.Contains("8 GB", caution);
        Assert.Contains(AssistModelTier.Large.DisplayName(), caution);
        Assert.Contains(AssistModelTier.Large.MemoryDescription(), caution);
    }

    [Fact]
    public void SharedRules_AssistantModelChoice_NamesNoModel()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var jargonList = doc["assistantModelChoice"]!["namesNoModel"]!["jargon"]!
            .AsArray()
            .Select(j => j!.ToString().ToLowerInvariant())
            .ToList();

        var budget = new AssistHardwareBudget(8L * 1024 * 1024 * 1024);

        var allStrings = new List<string>
        {
            AssistModelTier.Small.DisplayName(),
            AssistModelTier.Large.DisplayName(),
            AssistModelTier.Small.ChoiceLabel(),
            AssistModelTier.Large.ChoiceLabel(),
            AssistModelTier.Small.SizeGuidance(),
            AssistModelTier.Large.SizeGuidance(),
            AssistModelChoice.Label(AssistModelChoice.Automatic),
            AssistModelChoice.Detail(AssistModelChoice.Automatic, budget),
            AssistModelChoice.Detail(AssistModelChoice.Smaller, budget),
            AssistModelChoice.Detail(AssistModelChoice.Larger, budget),
            AssistModelChoice.Caution(AssistModelChoice.Larger, budget) ?? "",
        };

        foreach (string text in allStrings)
        {
            string lower = text.ToLowerInvariant();
            foreach (string jargon in jargonList)
            {
                Assert.False(
                    lower.Contains(jargon),
                    $"User-facing string '{text}' contains forbidden model jargon '{jargon}'");
            }
        }
    }

    /// <summary>Every tool name <c>plantoir-mcp</c> declares.</summary>
    private static readonly HashSet<string> PlantoirToolNames = typeof(Plantoir.Mcp.PlantoirTools)
        .GetMethods(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance)
        .Select(method => method
            .GetCustomAttribute<ModelContextProtocol.Server.McpServerToolAttribute>())
        .Where(attribute => attribute is not null)
        .Select(attribute => attribute!.Name!)
        .ToHashSet(StringComparer.OrdinalIgnoreCase);

    [Fact]
    public void AssistCases_Tools_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("assist-cases.json");
        var tools = doc["tools"]!.AsObject();

        var localTools = tools["local"]!.AsArray().Select(t => t!.ToString()).ToHashSet(StringComparer.OrdinalIgnoreCase);
        Assert.Equal(localTools, AssistAgent.ForTheLocalModel);

        var needsApproval = tools["needsApproval"]!.AsArray().Select(t => t!.ToString()).ToHashSet(StringComparer.OrdinalIgnoreCase);
        Assert.Equal(needsApproval, AssistAgent.DeploysToStudents);

        // The tools the CONTRACT says the mac shows an MCP client and not its
        // local model. It went from three to ten on 2026-09-08, when the mac
        // built the six this app had had all along plus their plan twins — see
        // issue #70. What changed for Windows was not the tools, which were
        // already served, but the FIXED PHRASINGS that reach them.
        // MCP-only means the local MODEL is not SHOWN a tool. Asserted about
        // THIS app rather than by retyping the contract's list: an inline copy
        // goes red only when the contract moves, and the fix is always to
        // retype it — which is the pattern issue #146 called out and CLAUDE.md
        // means by "deserialise, don't retype".
        //
        // The two halves are the whole meaning of the word. Nothing MCP-only
        // may be in the local surface, which is what protects the measured
        // routing accuracy of the thirteen; and every one of them must still
        // be reachable, because MCP-only says nothing about whether a teacher
        // may ask for it — six of these ten are reached by a fixed phrasing,
        // matched in code, that no model ever sees (issue #70).
        var mcpOnly = tools["mcpOnly"]!.AsArray().Select(t => t!.ToString()).ToHashSet(StringComparer.OrdinalIgnoreCase);
        Assert.NotEmpty(mcpOnly);

        foreach (string tool in mcpOnly)
        {
            Assert.False(AssistAgent.ForTheLocalModel.Contains(tool),
                $"{tool} is MCP-only in the contract and this app shows it to the local model, " +
                "which spends routing accuracy the measurement was taken against.");

            Assert.True(PlantoirToolNames.Contains(tool),
                $"{tool} is MCP-only in the contract and this server does not offer it at all, " +
                "so nothing here can reach it — by a fixed phrasing or otherwise.");
        }
    }

    /// <summary>
    /// Every write the LOCAL MODEL can reach and that has a plan_ twin must
    /// be in <see cref="AssistAgent.PlanTwins"/>, or the confirmation setting
    /// silently does nothing for it — a teacher who asked to be shown what
    /// would happen is shown nothing, and only for some requests.
    ///
    /// Deliberately scoped to the local surface: the contract lists twins for
    /// writes the local model is never offered, and this loop cannot check
    /// what it does not route.
    ///
    /// <para><b>It is a floor, not a ceiling, and the difference matters.</b>
    /// "The local model is never offered it" does NOT mean nothing reaches it
    /// — a FIXED PHRASING reaches a tool no model is shown, and then wants the
    /// same gate. <c>re_date_classes</c> has been in
    /// <see cref="AssistAgent.PlanTwins"/> for exactly that reason, and
    /// <c>make_room_for_classes</c> joined it on 2026-09-09 (issue #70). So
    /// the loop below skips what it cannot judge; the check underneath it,
    /// that nothing is gated behind a twin the CONTRACT does not know, is what
    /// keeps the additions honest.</para>
    /// </summary>
    [Fact]
    public void PlanTwins_CoverEveryLocalWriteThatHasOne()
    {
        var tools = ContractLoader.LoadJson("assist-cases.json")!["tools"]!.AsObject();
        var local = tools["local"]!.AsArray().Select(t => t!.ToString()).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var twins = tools["planTwins"]!.AsObject();

        foreach (var (write, twin) in twins)
        {
            if (!local.Contains(write)) continue;

            // Deploying waits on its own button whatever the setting says, so
            // its twin is never the thing a teacher is shown.
            if (AssistAgent.NeedsApproval(write)) continue;

            Assert.True(AssistAgent.PlanTwins.ContainsKey(write),
                $"{write} is a local write with a plan twin, but the confirmation gate does not know it");
            Assert.Equal(twin!.ToString(), AssistAgent.PlanTwins[write]);
        }

        // And nothing is gated behind a twin that is not in the contract.
        foreach (var (write, twin) in AssistAgent.PlanTwins)
            Assert.Equal(twin, twins[write]!.ToString());
    }

    [Fact]
    public void AssistantConfirmation_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var conf = doc["assistantConfirmation"]!.AsObject();

        bool defaultsToOn = conf["defaultsToOn"]!.GetValue<bool>();
        Assert.True(defaultsToOn);

        int plansBeforeMention = conf["mentionedAfter"]!["plansAccepted"]!.GetValue<int>();
        Assert.Equal(15, plansBeforeMention);

        // NeedsApproval only applies to DeploysToStudents (deploy_section, schedule_deploy)
        Assert.True(AssistAgent.NeedsApproval("deploy_section"));
        Assert.True(AssistAgent.NeedsApproval("schedule_deploy"));
        Assert.False(AssistAgent.NeedsApproval("publish_pages"));
        Assert.False(AssistAgent.NeedsApproval("list_pages"));
        Assert.False(AssistAgent.NeedsApproval("cancel_scheduled_deploy"));
    }

    [Fact]
    public void AppRules_DeployArguments_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("app-rules.json");
        var cases = doc["deployArguments"]!["cases"]!.AsArray();

        foreach (var c in cases)
        {
            if (c is null) continue;
            string name = c["name"]!.ToString();
            string course = c["course"]!.ToString();
            int section = c["section"]!.GetValue<int>();
            string cloudflareAccountID = c["cloudflareAccountID"]?.ToString() ?? "";
            var configJson = c["configuration"]!.ToJsonString();
            var config = CourseConfiguration.FromBytes(System.Text.Encoding.UTF8.GetBytes(configJson));

            // A case carrying `unattended` is the SCHEDULED deploy's shape, and
            // nothing else passes it — the Deploy button, the assistant and an
            // MCP client all leave it off, because a question they raise
            // becomes a dialog somebody is there to answer. Read rather than
            // assumed: a case added on the mac with this key set arrives here
            // as a real assertion instead of being silently ignored, which is
            // what happened while this app appended the flag in its own
            // scheduled wrapper instead.
            bool unattended = c["unattended"]?.GetValue<bool>() ?? false;

            var actual = DeployCommand.Arguments(course, section, config, cloudflareAccountID, unattended);
            var expected = c["expectArguments"]!.AsArray().Select(x => x!.ToString()).ToList();

            Assert.Equal(expected, actual);
        }
    }

    [Fact]
    public void AppRules_ConfigurationRules_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("app-rules.json");
        var rules = doc["configurationRules"]!.AsObject();

        foreach (var c in rules["cloudflareAccountID"]!.AsArray())
        {
            if (c is null) continue;
            string input = c["input"]!.ToString();
            string? expect = c["expectProblem"]?.ToString();
            Assert.Equal(expect, CourseConfiguration.CloudflareAccountProblem(input));
        }

        foreach (var c in rules["customDomain"]!.AsArray())
        {
            if (c is null) continue;
            string input = c["input"]!.ToString();
            string expect = c["expectNormalized"]!.ToString();
            Assert.Equal(expect, CourseConfiguration.NormalizedCustomDomain(input));
        }

        string tempDir = Directory.CreateTempSubdirectory("contract-deployfolder").FullName;
        try
        {
            string realFile = Path.Combine(tempDir, "not-a-folder.txt");
            File.WriteAllText(realFile, "x");
            string missing = Path.Combine(tempDir, "nope");

            foreach (var c in rules["deployFolder"]!.AsArray())
            {
                if (c is null) continue;
                string input = c["input"]!.ToString()
                    .Replace("@MISSING@", missing)
                    .Replace("@FILE@", realFile)
                    .Replace("@FOLDER@", tempDir);
                string? expect = c["expectProblem"]?.ToString();
                Assert.Equal(expect, CourseConfiguration.DeployFolderProblem(input));
            }
        }
        finally
        {
            try { Directory.Delete(tempDir, recursive: true); } catch { }
        }
    }

    [Fact]
    public void AppRules_FailureExplanations_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("app-rules.json");
        var cases = doc["failureExplanations"]!["cases"]!.AsArray();

        // Every case is played and every mismatch reported, rather than
        // stopping at the first: this list grows from the mac, and a red that
        // names only its first case hides which issues own the rest.
        var mismatches = cases
            .Where(c => c is not null)
            .Select((c, index) => (index, expect: c!["expect"]?.ToString(), actual: FailureExplainer.Explanation(c["output"]!.ToString())))
            .Where(result => result.expect != result.actual)
            .Select(result => $"case {result.index}: expected \"{result.expect ?? "null"}\", got \"{result.actual ?? "null"}\"")
            .ToList();
        Assert.True(mismatches.Count == 0,
            "app-rules.json → failureExplanations: " + mismatches.Count + " of " + cases.Count +
            " cases explained differently here:\n" + string.Join("\n", mismatches));
    }

    [Fact]
    public void AppRules_LauncherFlags_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("app-rules.json");
        var section = doc["launcherFlags"]!.AsObject();

        string repoRoot = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", ".."));
        string previewScript = File.ReadAllText(Path.Combine(repoRoot, "preview.ps1"));
        string setupScript = File.ReadAllText(Path.Combine(repoRoot, "setup.ps1"));
        string deployScript = File.ReadAllText(Path.Combine(repoRoot, "deploy.ps1"));

        var previewFlags = section["preview"]!.AsArray().Select(x => x!["flag"]!.ToString().Split(' ')[0]).ToList();
        foreach (var flag in previewFlags)
        {
            Assert.Contains(flag, previewScript, StringComparison.OrdinalIgnoreCase);
        }

        var setupFlags = section["setup"]!.AsArray().Select(x => x!["flag"]!.ToString().Split(' ')[0]).ToList();
        foreach (var flag in setupFlags)
        {
            Assert.Contains(flag, setupScript, StringComparison.OrdinalIgnoreCase);
        }

        var deployFlags = new[] { "--target", "--account", "--to-folder" };
        foreach (var flag in deployFlags)
        {
            Assert.Contains(flag, deployScript, StringComparison.OrdinalIgnoreCase);
        }
    }

    [Fact]
    public void SharedRules_PageNaming_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var cases = doc["pageNaming"]!["cases"]!.AsArray();

        foreach (var c in cases)
        {
            if (c is null) continue;
            string file = c["file"]!.ToString();
            string? frontmatterTitle = c["frontmatterTitle"]?.ToString();
            string expected = c["shown"]!.ToString();

            string pageText = frontmatterTitle is not null
                ? $"---\ntitle: {frontmatterTitle}\n---\nBody"
                : "Body without frontmatter";

            string actual = PagePaths.DisplayTitle(file, pageText);
            Assert.Equal(expected, actual);
        }
    }

    [Fact]
    public void SharedRules_SidebarFilter_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var section = doc["sidebarFilter"]!.AsObject();

        var coursesData = section["courses"]!.AsArray();
        var courses = coursesData.Select(cd =>
        {
            string code = cd!["code"]!.ToString();
            string name = cd["name"]!.ToString();
            var config = CourseConfiguration.FromBytes(System.Text.Encoding.UTF8.GetBytes($$"""{"course_code": "{{code}}", "course_name": "{{name}}", "section_numbers": [1]}"""));
            return new Course(code, Path.Combine("C:\\test\\courses", code), config);
        }).ToList();

        var cases = section["cases"]!.AsArray();
        foreach (var c in cases)
        {
            if (c is null) continue;
            string filter = c["filter"]!.ToString();
            var expect = c["expect"]!.AsArray().Select(x => x!.ToString()).ToList();

            var matches = Workspace.Filter(courses, filter).Select(x => x.Code).ToList();
            Assert.Equal(expect, matches);
        }
    }

    [Fact]
    public void SharedRules_TranscriptStripping_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var cases = doc["transcriptStripping"]!["cases"]!.AsArray();

        foreach (var c in cases)
        {
            if (c is null) continue;
            string input = c["input"]!.ToString();
            string expect = c["expect"]!.ToString();

            string actual = TranscriptBuilder.StripControlSequences(input);
            Assert.Equal(expect, actual);
        }
    }

    [Fact]
    public void SharedRules_ScheduledDeployRefusals_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var cases = doc["scheduledDeployRefusals"]!["cases"]!.AsArray();

        var now = new DateTime(2026, 8, 18, 12, 0, 0);

        foreach (var c in cases)
        {
            if (c is null) continue;
            string name = c["name"]!.ToString();
            string? expectRefusal = c["expectRefusal"]?.ToString();
            var given = c["given"]!.AsObject();

            bool isPast = given["whenIsInThePast"]?.GetValue<bool>() ?? false;
            DateTime when = isPast ? now.AddHours(-1) : now.AddHours(2);

            string target = given["target"]?.ToString() ?? "netlify";
            string folderPath = given["folderProblem"]?.GetValue<bool>() == true ? "" : "C:\\Sites\\valid";
            string cloudflareAccountID = given["cloudflareAccountID"]?.ToString() ?? "0123456789abcdef0123456789abcdef";
            bool hasDeployed = given["hasDeployedBefore"]?.GetValue<bool>() ?? true;

            // An ADDITIONAL destination — present only on the cases entry
            // 305 added. additionalTargetHasDeployedBefore defaults to true
            // so the "never deployed" case fires only when a scenario asks
            // for it explicitly.
            string? additionalTarget = given["additionalTarget"]?.ToString();
            string additionalFolderPath = given["additionalFolderProblem"]?.GetValue<bool>() == true ? "" : "C:\\Sites\\additional";
            bool additionalHasDeployed = given["additionalTargetHasDeployedBefore"]?.GetValue<bool>() ?? true;

            string tempDir = Directory.CreateTempSubdirectory("contract-sched-deploy").FullName;
            try
            {
                string additionalTargetsJson = additionalTarget is null
                    ? "[]"
                    : $$"""[{"type": "{{additionalTarget}}", "path": "{{additionalFolderPath.Replace("\\", "\\\\")}}"}]""";
                var config = CourseConfiguration.FromBytes(System.Text.Encoding.UTF8.GetBytes($$"""
                {
                    "course_code": "ICS3U",
                    "course_name": "Computer Science",
                    "section_numbers": [1],
                    "deploy_target": "{{target}}",
                    "deploy_folder_path": "{{folderPath.Replace("\\", "\\\\")}}",
                    "additional_deploy_targets": {{additionalTargetsJson}}
                }
                """));
                var course = new Course("ICS3U", tempDir, config);

                if (hasDeployed)
                {
                    if (target == "cloudflare_pages")
                    {
                        Directory.CreateDirectory(Path.Combine(tempDir, ".cloudflare_sites"));
                        File.WriteAllText(Path.Combine(tempDir, ".cloudflare_sites", "section1.json"), "{}");
                    }
                    else if (target == "netlify" || target == "local_folder")
                    {
                        Directory.CreateDirectory(Path.Combine(tempDir, ".netlify_sites"));
                        File.WriteAllText(Path.Combine(tempDir, ".netlify_sites", "section1.json"), "{}");
                    }
                }
                if (additionalTarget is not null && additionalHasDeployed)
                {
                    string folderName = additionalTarget == "cloudflare_pages" ? ".cloudflare_sites" : ".netlify_sites";
                    Directory.CreateDirectory(Path.Combine(tempDir, folderName));
                    File.WriteAllText(Path.Combine(tempDir, folderName, "section1.json"), "{}");
                }

                string? problem = ScheduledDeploy.Problem(course, 1, when, now, cloudflareAccountID);

                if (expectRefusal is null)
                {
                    Assert.Null(problem);
                }
                else
                {
                    Assert.NotNull(problem);
                    switch (expectRefusal)
                    {
                        case "hasAlreadyPassed":
                            Assert.Contains("has already passed", problem);
                            break;
                        case "deployFolderNeedsAttention":
                            Assert.Contains("needs attention first", problem);
                            break;
                        case "cloudflareAccountMissing":
                            Assert.Contains("Cloudflare Pages, which needs your Account ID", problem);
                            break;
                        case "neverDeployed":
                        case "additionalDestinationNeverDeployed":
                            // Compared WHOLE (#344 / mac #322): both contain
                            // "has never been deployed to", so a substring
                            // cannot tell the primary's from an additional's.
                            string rendered = ContractLoader.LoadJson("shared-rules.json")!
                                ["scheduledDeployRefusals"]!["wording"]![expectRefusal]!.ToString()
                                .Replace("{course}", "ICS3U").Replace("{section}", "1")
                                .Replace("{destination}", c["destinationNamed"]!.ToString());
                            Assert.Equal(rendered, problem);
                            break;
                        case "additionalDeployFolderNeedsAttention":
                            Assert.Contains("also deploys to a folder", problem);
                            Assert.Contains("needs attention first", problem);
                            break;
                        case "additionalCloudflareAccountMissing":
                            Assert.Contains("also deploys to Cloudflare Pages, which needs your Account ID", problem);
                            break;
                        default:
                            Assert.Fail($"Unknown refusal case: {expectRefusal}");
                            break;
                    }
                }
            }
            finally
            {
                try { Directory.Delete(tempDir, recursive: true); } catch { }
            }
        }
    }

    [Fact]
    public void FileFormats_CourseConfigKeys_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("file-formats.json");
        var keys = doc["courseConfigKeys"]!["keys"]!.AsArray().Select(k => k!["key"]!.ToString()).ToList();

        string repoRoot = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", ".."));
        string source = File.ReadAllText(Path.Combine(repoRoot, "windows-app", "Plantoir.Core", "Models", "CourseConfiguration.cs"));

        // A key this app does not carry yet is held open by name against the
        // issue that owns it (NamedGapLedger, the parity burn-down list), and
        // the ledger fails the day the key appears in CourseConfiguration.cs.
        var here = keys.Where(key => source.Contains($"\"{key}\"")).ToList();
        var deferred = NamedGapLedger.GapsIn(NamedGapLedger.CourseConfigKeys, keys, here);

        var missing = keys.Where(key => !here.Contains(key) && !deferred.Contains(key)).ToList();
        Assert.True(missing.Count == 0,
            "file-formats.json → courseConfigKeys names keys CourseConfiguration.cs does not: " +
            string.Join(", ", missing));
    }

    private sealed class ScriptedModel : IChatModel
    {
        public Task<ModelReply?> Ask(JsonArray messages, JsonArray tools, CancellationToken cancellation) =>
            Task.FromResult<ModelReply?>(null);
    }

    private sealed class DummyTools : IToolServer
    {
        public Task<AssistToolAnswer> CallTool(string name, JsonObject arguments, Action<string>? progress = null, CancellationToken cancellation = default) =>
            Task.FromResult(AssistToolAnswer.Same("OK"));
    }
}




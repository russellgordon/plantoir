using System.Text.Json.Nodes;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Catalogs;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// "This is a club" (#274, mac #267) and its panel words (#390, mac #368):
/// <c>shared-rules.json</c> → <c>wizard.clubToggle</c>, deserialised rather than
/// retyped. The dialog itself is a view; these pin the Core seams it calls —
/// <see cref="ClubFill"/>, <see cref="WizardWording"/>, <see cref="ClubSettingsRows"/>
/// and the <c>course created</c> line.
/// </summary>
public class ClubWizardTests
{
    private static JsonNode ClubToggle => ContractLoader.LoadJson("shared-rules.json")["wizard"]!["clubToggle"]!;
    private static JsonNode Wizard => ContractLoader.LoadJson("shared-rules.json")["wizard"]!;

    private static List<string> Strings(JsonNode? node) => node!.AsArray().Select(x => x!.ToString()).ToList();

    [Fact]
    public void TheFillCasesAreFollowed()
    {
        var cases = ClubToggle["cases"]!.AsArray();
        Assert.True(cases.Count >= 4, $"clubToggle.cases lost cases: {cases.Count}");
        foreach (var c in cases)
        {
            var given = c!["given"]!;
            var expect = c["expect"]!;
            var filled = ClubFill.Applying(c["isClub"]!.GetValue<bool>(), new ClubFillFields(
                Strings(given["sharedFolders"]), Strings(given["perSectionFolders"]), given["classFolder"]!.ToString(),
                given["unitWord"]!.ToString(), given["frontPageHeading"]!.ToString(),
                ClassPageSchemes.NounReading(given["noun"]!.ToString())), c["usesLCSTerminology"]!.GetValue<bool>());

            string name = c["name"]!.ToString();
            Assert.True(Strings(expect["sharedFolders"]).SequenceEqual(filled.SharedFolders), $"{name}: sharedFolders");
            Assert.True(Strings(expect["perSectionFolders"]).SequenceEqual(filled.PerSectionFolders), $"{name}: perSectionFolders");
            Assert.Equal(expect["classFolder"]!.ToString(), filled.ClassFolder);
            Assert.Equal(expect["unitWord"]!.ToString(), filled.UnitWord);
            Assert.Equal(expect["frontPageHeading"]!.ToString(), filled.FrontPageHeading);
            Assert.Equal(ClassPageSchemes.NounReading(expect["noun"]!.ToString()), filled.Noun);
        }
    }

    [Fact]
    public void TheVocabulariesAndCurriculumFoldersAreTheContracts()
    {
        foreach (var (key, vocabulary) in new[] { ("club", ClubVocabulary.Club), ("course", ClubVocabulary.Course) })
        {
            var words = ClubToggle[key]!;
            Assert.Equal(words["classFolder"]!.ToString(), vocabulary.ClassFolder);
            Assert.Equal(words["unitWord"]!.ToString(), vocabulary.UnitWord);
            Assert.Equal(words["frontPageHeading"]!.ToString(), vocabulary.FrontPageHeading);
            Assert.Equal(ClassPageSchemes.NounReading(words["noun"]!.ToString()), vocabulary.Noun);
        }
        Assert.Equal(Strings(ClubToggle["curriculumFolders"]), ClubFill.CurriculumFolders);
    }

    /// <summary>#390: every word that follows the box, from both sides of the contract.</summary>
    [Fact]
    public void ThePanelsWordsFollowTheToggle()
    {
        void Same(JsonNode side, WizardWording.PanelWords words, string createKey, string graded)
        {
            Assert.Equal(side[createKey]!.ToString(), words.CreateButton);
            Assert.Equal(side["namingHeading"]!.ToString(), words.NamingHeading);
            Assert.Equal(side["namingCaption"]!.ToString(), words.NamingCaption);
            Assert.Equal(side["creatingTitle"]!.ToString(), words.CreatingTitle);
            Assert.Equal(side["codeLabel"]!.ToString(), words.CodeLabel);
            Assert.Equal(side["nameLabel"]!.ToString(), words.NameLabel);
            Assert.Equal(side["sectionMarkerCaption"]!.ToString(), words.SectionMarkerCaption);
            Assert.Equal(side["gradeCaption"]!.ToString(), words.GradeCaption);
            Assert.Equal(side["structureCaption"]!.ToString(), words.StructureCaption);
            Assert.Equal(graded, words.GradedFolderCaption);
            Assert.Equal(side["defaultSiteName"]!.ToString(), words.DefaultSiteName);
        }
        string courseGraded = ContractLoader.LoadJson("shared-rules.json")["gradedFolders"]!["wording"]!["caption"]!.ToString();
        Same(Wizard, WizardWording.Panel(isClub: false), "createCourseButton", courseGraded);
        Same(ClubToggle, WizardWording.Panel(isClub: true), "createButton", ClubToggle["gradedFolderCaption"]!.ToString());
        Assert.NotEqual(WizardWording.Panel(true).CreateButton, WizardWording.Panel(false).CreateButton);
    }

    [Fact]
    public void TheToggleAndRowWordsAreTheContracts()
    {
        Assert.Equal(ClubToggle["label"]!.ToString(), WizardWording.ClubToggleLabel);
        Assert.Equal(ClubToggle["caption"]!.ToString(), WizardWording.ClubToggleCaption);
        Assert.Equal(ClubToggle["startingContentNote"]!.ToString(), WizardWording.ClubStartingContentNote);
        var rows = ClubToggle["rows"]!;
        Assert.Equal(rows["classFolder"]!.ToString(), WizardWording.ClubClassFolderRow);
        Assert.Equal(rows["frontPageHeading"]!.ToString(), WizardWording.ClubFrontPageHeadingRow);
        Assert.Equal(rows["pageWord"]!.ToString(), WizardWording.ClubPageWordRow);
        Assert.Equal(rows["noun"]!.ToString(), WizardWording.ClubNounRow);
        Assert.Equal(rows["pageWordCaption"]!.ToString().Replace("{word}", "Week"), WizardWording.ClubPageWordCaption("Week"));
    }

    /// <summary>
    /// #387 item 3 / #274 item 6: a locked row is drawn only when its key is
    /// RECORDED (<c>settingsRows.shownWhen</c>, 8 cases), never a derived default.
    /// </summary>
    [Fact]
    public void TheLockedRowsAreShownOnlyWhenRecorded()
    {
        var settings = ClubToggle["settingsRows"]!;
        Assert.Equal(settings["pageNaming"]!.ToString(), ClubSettingsRows.PageNamingLabel);
        Assert.Equal(settings["frontPageHeading"]!.ToString(), ClubSettingsRows.FrontPageHeadingLabel);
        Assert.Equal(settings["noun"]!.ToString(), ClubSettingsRows.NounLabel);
        Assert.Equal(settings["lockedCaption"]!.ToString(), ClubSettingsRows.LockedCaption);

        var cases = settings["shownWhenCases"]!.AsArray();
        Assert.Equal(8, cases.Count);
        foreach (var c in cases)
        {
            var configuration = CourseConfiguration.FromDictionary(JObject.Parse(c!["given"]!.ToJsonString()));
            var rows = ClubSettingsRows.Shown(configuration);
            string name = c["name"]!.ToString();
            Assert.True(Strings(c["expect"]).SequenceEqual(rows.Select(r => r.Key)),
                $"{name}: expected [{string.Join(", ", Strings(c["expect"]))}], drew [{string.Join(", ", rows.Select(r => r.Key))}]");
            if (c["values"] is JsonObject values)
                foreach (var (key, value) in values)
                    Assert.Equal(value!.ToString(), rows.Single(r => r.Key == key).Value);
        }
    }

    [Fact]
    public void AClubSaysItIsAClubInItsOwnWords()
    {
        Assert.Equal("created CODING as a club, with pages named “Week 1” in “All Meetings”",
                     NewCourseCreator.ClubLine("CODING", new ClassPageNaming("Week", ClassPageScheme.Numbered), "All Meetings"));
        var keys = ClubFill.ClubKeys("Most Recent Meeting", ClassNoun.Meeting);
        Assert.Equal("numbered", keys["class_page_scheme"]);
        Assert.Equal("Most Recent Meeting", keys["front_page_heading"]);
        Assert.Equal("meeting", keys["class_noun"]);
    }

    /// <summary>A club takes no ready-made pages, no skeleton and no curriculum, whatever the toggles held.</summary>
    [Fact]
    public void AClubIsGivenNoStartingContent()
    {
        var choices = new NewCourseAnswers.Choices("ADA1O", true, true, true, WizardStructure.Defaults(false));
        var club = NewCourseAnswers.ForAClub(choices, isClub: true);
        Assert.False(club.Prepopulate);
        Assert.False(club.StartsFromSkeleton);
        Assert.False(club.IncludeCurriculum);
        Assert.Same(choices, NewCourseAnswers.ForAClub(choices, isClub: false));
    }
}

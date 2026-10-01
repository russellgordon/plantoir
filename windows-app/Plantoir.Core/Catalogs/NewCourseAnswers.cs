using Newtonsoft.Json.Linq;
using Plantoir.Core.Models;

namespace Plantoir.Core.Catalogs;

/// <summary>
/// The part of a new course's <c>course_config.json</c> that the Starting
/// Content answers decide: the five structure lists, the sidebar, the three
/// starting-point keys (<c>prepopulate_example_content</c>,
/// <c>use_skeleton</c>, <c>include_curriculum_pages</c>) and the marks pool.
///
/// <para>Hoisted out of <c>NewCourseDialog.BuildConfiguration</c> for GitHub
/// issue #250, so the file the wizard writes can be pinned by a test at all —
/// the view cannot be reached from <c>Plantoir.Tests</c>. The goldens in
/// <c>Plantoir.Tests/Goldens/</c> were captured from this function with the
/// rule as it stood BEFORE #250 changed it, and a teacher who TAKES the
/// example content must still get those bytes: that is the thing the fix
/// must not move.</para>
/// </summary>
public static class NewCourseAnswers
{
    /// <summary>The teacher's Starting Content and structure answers, as the wizard holds them.</summary>
    public sealed record Choices(
        string Code,
        bool Prepopulate,
        bool StartsFromSkeleton,
        bool IncludeCurriculum,
        WizardStructure.Lists Lists);

    /// <summary>
    /// A club takes no ready-made pages, no skeleton and no curriculum pages
    /// (#274, mac #267): all three answered "no", whatever the toggles held —
    /// so a club typed with a payload code keeps the wizard's own marks pool.
    /// </summary>
    public static Choices ForAClub(Choices choices, bool isClub) =>
        isClub ? choices with { Prepopulate = false, StartsFromSkeleton = false, IncludeCurriculum = false } : choices;

    /// <summary>The keys written, and the lists as they stand after the last-moment adoption.</summary>
    public sealed record Result(JObject Keys, WizardStructure.Lists Lists);

    /// <summary>
    /// True when the teacher is TAKING the ready-made pages — which needs
    /// both that they exist for the code and that the toggle is on. The
    /// question #250 is about: "does example content exist?" was asked where
    /// this one belongs.
    /// </summary>
    public static bool TakesExampleContent(string exampleContentRoot, string code, bool prepopulate) =>
        prepopulate && ExampleContentCatalog.HasContent(exampleContentRoot, code);

    public static Result Decide(string exampleContentRoot, string skeletonsRoot, Choices choices)
    {
        string code = choices.Code;
        var lists = choices.Lists;
        bool taking = TakesExampleContent(exampleContentRoot, code, choices.Prepopulate);

        // Adopt once more, here, whether or not the code box's TextChanged
        // ever ran — it does not for a programmatic Text on an untemplated
        // box. A config that disagreed with the pages about to be installed
        // would leave empty folders beside them. The guard is
        // StructureToAdopt's own, so a list the teacher edited is still theirs.
        if (choices.StartsFromSkeleton
            && SkeletonCatalog.StructureToAdopt(exampleContentRoot, skeletonsRoot, code, taking, lists.SharedFolders,
                                                WizardDefaults.SharedFolders, WizardDefaults.LcsSharedFolders) is { } lateAdopted)
        {
            lists = WizardStructure.Adopting(lateAdopted);
        }

        bool usesSkeleton = SkeletonCatalog.HasSkeleton(exampleContentRoot, skeletonsRoot, code, taking)
                            && choices.StartsFromSkeleton;

        // The skeleton decides its own sidebar, whatever the teacher has
        // since done to the folder list.
        var skeletonInUse = usesSkeleton ? SkeletonCatalog.GetFamily(skeletonsRoot, code) : null;
        List<string> hidden;
        List<string> expandable;
        if (skeletonInUse is not null)
        {
            var plan = SkeletonCatalog.Sidebar(skeletonInUse, lists.SharedFolders, lists.SharedFiles,
                lists.PerSectionFolders, lists.PerSectionFiles);
            hidden = plan.Hidden.ToList();
            expandable = plan.Expandable.ToList();
        }
        else
        {
            var allItems = lists.SharedFolders.Concat(lists.SharedFiles)
                .Concat(lists.PerSectionFolders).Concat(lists.PerSectionFiles).ToHashSet();
            hidden = WizardDefaults.HiddenItems
                .Where(i => allItems.Contains(i)
                            || string.Equals(i, "Media", StringComparison.OrdinalIgnoreCase))
                .ToList();
            var expandableSource = lists.SharedFolders.Concat(lists.PerSectionFolders).ToHashSet();
            expandable = WizardDefaults.ExpandableItems.Where(expandableSource.Contains).ToList();
        }

        var keys = new JObject
        {
            ["shared_folders"] = new JArray(lists.SharedFolders),
            ["shared_files"] = new JArray(lists.SharedFiles),
            ["per_section_folders"] = new JArray(lists.PerSectionFolders),
            ["per_section_files"] = new JArray(lists.PerSectionFiles),
            ["hidden"] = new JArray(hidden),
            ["expandable"] = new JArray(expandable),
            ["prepopulate_example_content"] = taking,
            // The same capabilityExists && teacherSaidYes shape —
            // contracts/file-formats.json -> wizardAnswerKeys.
            ["use_skeleton"] = usesSkeleton,
            ["include_curriculum_pages"] = CourseConfiguration.CurriculumPagesOffered(
                exampleContentRoot, skeletonsRoot, code, taking, choices.StartsFromSkeleton)
                && choices.IncludeCurriculum,
        };

        // The marks pool is written for EVERY new course (#317): a course the
        // teacher shaped gets the pool the teacher chose, reconciled exactly
        // against its folders; a course taking ready-made pages gets the
        // MANIFEST's pool. An unreadable manifest leaves the key absent.
        if (!taking)
        {
            keys["graded_folders"] = new JArray(
                GradedFolderRule.Reconciled(WizardStructure.EffectiveGradedFolders(lists),
                    lists.SharedFolders.Concat(lists.PerSectionFolders)));
        }
        else if (ExampleContentCatalog.MarksPool(exampleContentRoot, code) is { } manifestPool)
        {
            keys["graded_folders"] = new JArray(manifestPool);
        }

        return new Result(keys, lists);
    }
}

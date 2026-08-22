using System.Text;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// A course can publish to more than one destination now (redundancy
/// against one host having a bad day) — see WINDOWS-HANDOFF.md entry 304.
/// Mirrors the mac's AdditionalDeployTargetsTests.swift.
/// </summary>
public class AdditionalDeployTargetsTests
{
    private static CourseConfiguration FromJson(string json) =>
        CourseConfiguration.FromBytes(Encoding.UTF8.GetBytes(json));

    [Fact]
    public void ACourseThatNeverOptsInHasNoAdditionalTargets()
    {
        var config = FromJson("""{"course_code":"ICS3U"}""");
        Assert.Empty(config.AdditionalDeployTargets);
    }

    [Fact]
    public void WritingAnEmptyAdditionalTargetsListOmitsTheKeyEntirely()
    {
        var config = FromJson("""{"course_code":"ICS3U"}""");
        config.AdditionalDeployTargets = new List<CourseConfiguration.AdditionalDeployTarget>();
        string written = Encoding.UTF8.GetString(config.SerializedBytes());
        Assert.DoesNotContain("additional_deploy_targets", written);
    }

    [Fact]
    public void ACourseWithNoAdditionalTargetsWritesTheSameFileAsBefore()
    {
        var untouched = FromJson("""{"course_code":"ICS3U","deploy_target":"netlify"}""");
        var touched = FromJson("""{"course_code":"ICS3U","deploy_target":"netlify"}""");
        // Reading the empty list and writing it right back must not add the key.
        touched.AdditionalDeployTargets = touched.AdditionalDeployTargets;
        Assert.Equal(untouched.SerializedBytes(), touched.SerializedBytes());
    }

    [Fact]
    public void AdditionalTargetsRoundTripThroughDisk()
    {
        var config = FromJson("""{"course_code":"ICS3U","deploy_target":"netlify"}""");
        config.AdditionalDeployTargets = new List<CourseConfiguration.AdditionalDeployTarget>
        {
            new("cloudflare_pages", ""),
            new("local_folder", @"C:\Sites\backup"),
        };
        var reloaded = CourseConfiguration.FromBytes(config.SerializedBytes());
        var targets = reloaded.AdditionalDeployTargets;
        Assert.Equal(2, targets.Count);
        Assert.Contains(targets, t => t.Type == "cloudflare_pages" && t.Path == "");
        Assert.Contains(targets, t => t.Type == "local_folder" && t.Path == @"C:\Sites\backup");
    }

    [Fact]
    public void TurningATargetOnThenOffLeavesNoTraceOfItsOldPath()
    {
        var config = FromJson("""{"course_code":"ICS3U","deploy_target":"netlify"}""");
        config.AdditionalDeployTargets = CourseConfiguration.SettingAdditionalDeployTarget(
            config.AdditionalDeployTargets, enabled: true, type: "local_folder");
        config.AdditionalDeployTargets = CourseConfiguration.SettingAdditionalDeployTargetPath(
            config.AdditionalDeployTargets, @"C:\Sites\old", "local_folder");
        Assert.Equal(@"C:\Sites\old", CourseConfiguration.AdditionalDeployTargetPath(config.AdditionalDeployTargets, "local_folder"));

        config.AdditionalDeployTargets = CourseConfiguration.SettingAdditionalDeployTarget(
            config.AdditionalDeployTargets, enabled: false, type: "local_folder");
        config.AdditionalDeployTargets = CourseConfiguration.SettingAdditionalDeployTarget(
            config.AdditionalDeployTargets, enabled: true, type: "local_folder");

        Assert.Equal("", CourseConfiguration.AdditionalDeployTargetPath(config.AdditionalDeployTargets, "local_folder"));
    }

    [Fact]
    public void AvailableAdditionalTypesExcludesWhicheverIsPrimary()
    {
        Assert.Equal(new[] { "cloudflare_pages", "local_folder" },
            CourseConfiguration.AvailableAdditionalDeployTargetTypes("netlify"));
        Assert.Equal(new[] { "netlify", "local_folder" },
            CourseConfiguration.AvailableAdditionalDeployTargetTypes("cloudflare_pages"));
    }

    [Fact]
    public void SwitchingThePrimaryOntoAConfiguredAdditionalTargetDropsItFromTheAdditionalList()
    {
        var config = FromJson("""{"course_code":"ICS3U","deploy_target":"netlify"}""");
        config.AdditionalDeployTargets = CourseConfiguration.SettingAdditionalDeployTarget(
            config.AdditionalDeployTargets, enabled: true, type: "cloudflare_pages");
        Assert.True(CourseConfiguration.HasAdditionalDeployTarget(config.AdditionalDeployTargets, "cloudflare_pages"));

        config.DeployTarget = "cloudflare_pages";

        Assert.False(CourseConfiguration.HasAdditionalDeployTarget(config.AdditionalDeployTargets, "cloudflare_pages"));
    }

    [Fact]
    public void PruningAdditionalTargetsDropsOnlyTheMatchingType()
    {
        var targets = new List<CourseConfiguration.AdditionalDeployTarget>
        {
            new("cloudflare_pages", ""),
            new("local_folder", @"C:\Sites"),
        };
        var pruned = CourseConfiguration.PruningAdditionalTargets(targets, "cloudflare_pages");
        Assert.Single(pruned);
        Assert.Equal("local_folder", pruned[0].Type);
    }

    [Fact]
    public void PruningAdditionalTargetsIsANoOpWhenTheTypeIsntListed()
    {
        var targets = new List<CourseConfiguration.AdditionalDeployTarget> { new("local_folder", @"C:\Sites") };
        var pruned = CourseConfiguration.PruningAdditionalTargets(targets, "cloudflare_pages");
        Assert.Equal(targets, pruned);
    }

    [Fact]
    public void AllThreeSlotsCanBeFilledAtOnce()
    {
        var config = FromJson("""{"course_code":"ICS3U","deploy_target":"netlify"}""");
        config.AdditionalDeployTargets = CourseConfiguration.SettingAdditionalDeployTarget(
            config.AdditionalDeployTargets, enabled: true, type: "cloudflare_pages");
        config.AdditionalDeployTargets = CourseConfiguration.SettingAdditionalDeployTarget(
            config.AdditionalDeployTargets, enabled: true, type: "local_folder");

        Assert.Equal(2, config.AdditionalDeployTargets.Count);
        Assert.Equal(3, config.AllDeployDestinations.Count);
        Assert.Equal("netlify", config.AllDeployDestinations[0].Type);
    }

    [Fact]
    public void AtMostOneEntryPerType_SettingTwiceReplacesRatherThanDuplicates()
    {
        var config = FromJson("""{"course_code":"ICS3U","deploy_target":"netlify"}""");
        config.AdditionalDeployTargets = CourseConfiguration.SettingAdditionalDeployTarget(
            config.AdditionalDeployTargets, enabled: true, type: "local_folder");
        config.AdditionalDeployTargets = CourseConfiguration.SettingAdditionalDeployTargetPath(
            config.AdditionalDeployTargets, @"C:\Sites\a", "local_folder");
        config.AdditionalDeployTargets = CourseConfiguration.SettingAdditionalDeployTarget(
            config.AdditionalDeployTargets, enabled: true, type: "local_folder");

        Assert.Single(config.AdditionalDeployTargets);
    }
}

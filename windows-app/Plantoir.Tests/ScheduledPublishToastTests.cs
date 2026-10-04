using System.Text.Json.Nodes;
using Plantoir.Core.Assist;

namespace Plantoir.Tests;

/// <summary>
/// #324 (mac #306): what a click on the scheduled-publish toast does, played
/// from <c>shared-rules.json → scheduledPublishStopped.notification.onClick</c>,
/// and the toast's launch arguments.
/// </summary>
public class ScheduledPublishToastTests
{
    [Fact]
    public void EveryClickCaseIsDecidedAsTheContractSays()
    {
        var onClick = ContractLoader.LoadJson("shared-rules.json")["scheduledPublishStopped"]!["notification"]!["onClick"]!;
        int played = 0;
        foreach (var c in onClick["cases"]!.AsArray())
        {
            var appliesOn = c!["appliesOn"]?.AsArray().Select(x => x!.ToString()).ToList();
            if (appliesOn is not null && !appliesOn.Contains("windows")) continue;   // the mac's launch-time "wait" and out-of-reach rows
            played++;
            var windows = c["windows"]!.AsArray().Select(w => new ScheduledPublishToast.OpenWindow(
                w!["folder"]!.ToString() switch
                {
                    "this" => ScheduledPublishToast.WindowFolder.This,
                    "other" => ScheduledPublishToast.WindowFolder.Other,
                    _ => ScheduledPublishToast.WindowFolder.None,
                },
                w["busy"]?.GetValue<bool>() ?? false)).ToList();
            var decision = ScheduledPublishToast.Decide(
                c["carries"]!.GetValue<bool>(),
                c["folderExists"]?.GetValue<bool>() ?? true,
                c["sectionInFolder"]?.GetValue<bool>() ?? true,
                windows);
            var expect = c["expect"]!;
            string name = c["name"]!.ToString();
            Assert.True(expect["action"]!.ToString() == decision.Action switch
            {
                ScheduledPublishToast.Action.UseWindow => "useWindow",
                ScheduledPublishToast.Action.AdoptInto => "adoptInto",
                ScheduledPublishToast.Action.OpenNewWindow => "openNewWindow",
                _ => "bringForwardOnly",
            }, $"{name}: action {decision.Action}");
            if (expect["window"] is JsonNode window) Assert.True(window.GetValue<int>() == decision.Window, $"{name}: window {decision.Window}");
            if (expect["selectsTheSection"] is JsonNode selects) Assert.True(selects.GetValue<bool>() == decision.SelectsTheSection, $"{name}: selects");
            if (expect["opensAWindow"] is JsonNode opens) Assert.True(opens.GetValue<bool>() == decision.OpensAWindow, $"{name}: opens");
            Assert.True(c["trailSays"]!.ToString() == decision.TrailSays, $"{name}: trail says \"{decision.TrailSays}\"");
        }
        Assert.True(played >= 12, $"Only {played} click cases were played.");
    }

    [Fact]
    public void TheLaunchArgumentsCarryCourseSectionAndFolder()
    {
        var target = new ScheduledPublishToast.Target("ICS3U", 2, @"C:\Users\t\My Teaching & Things");
        string args = ScheduledPublishToast.Format(target);
        Assert.Equal(target, ScheduledPublishToast.Parse(args));
        Assert.StartsWith("section=ICS3U/2&", args);
    }

    [Fact]
    public void AToastThatNamesNoSectionParsesAsNothing()
    {
        Assert.Null(ScheduledPublishToast.Parse(""));
        Assert.Null(ScheduledPublishToast.Parse("folder=C%3A%5Cx"));
        Assert.Null(ScheduledPublishToast.Parse("section=ICS3U/0&folder=C%3A%5Cx"));
        Assert.Null(ScheduledPublishToast.Parse("section=ICS3U&folder=C%3A%5Cx"));
    }
}

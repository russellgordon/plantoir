using System;
using System.IO;
using System.Linq;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #357 (mac #335): every act that sends a site somewhere or sets a deploy
/// reads the SAVED settings — <c>shared-rules.json → actsUseTheSavedSettings</c>
/// (8 cases) — and #272's saved-settings sentences are the contract's.
/// The window's in-memory copy is the case's <c>saved</c> plus
/// <c>unsavedInWindow</c>; the act reads through <see cref="SavedSettings.Read"/>.
/// </summary>
public class ActsUseTheSavedSettingsTests : IDisposable
{
    private readonly string _root = Directory.CreateTempSubdirectory("saved-settings-").FullName;
    public void Dispose() { try { Directory.Delete(_root, true); } catch { } }

    [Fact]
    public void EveryCaseActsOnTheSavedSettings()
    {
        var cases = ContractLoader.LoadJson("shared-rules.json")["actsUseTheSavedSettings"]!["cases"]!.AsArray();
        Assert.True(cases.Count >= 7);
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            string courseDir = Path.Combine(_root, Guid.NewGuid().ToString("N"), "ICS3U");
            Directory.CreateDirectory(Path.Combine(courseDir, "section1"));
            string folder = Path.Combine(_root, "site-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(folder);
            string Filled(string json) => json.Replace("{folder}", folder.Replace("\\", "\\\\"));

            var saved = JObject.Parse(Filled(c["saved"]!.ToJsonString()));
            saved["course_code"] = "ICS3U"; saved["section_numbers"] = new JArray(1);
            string configPath = Path.Combine(courseDir, "course_config.json");
            File.WriteAllText(configPath, saved.ToString());
            var window = new Course("ICS3U", courseDir, CourseConfiguration.Load(configPath));
            foreach (var pair in JObject.Parse(Filled(c["unsavedInWindow"]!.ToJsonString())))
                window.Configuration.Values[pair.Key] = pair.Value!.DeepClone();
            if (c["savedFileIsNotJSON"]?.GetValue<bool>() == true) File.WriteAllText(configPath, "not { json");

            var readAtTheAct = SavedSettings.Read(window);
            var expect = c["expect"]!;
            if (expect["refusal"]?.ToString() == "settingsCouldNotBeReadToDeploy")
            {
                Assert.True(readAtTheAct is null, name);   // refused; the window's copy is never used instead
                continue;
            }
            Assert.True(readAtTheAct is not null, name);
            foreach (var type in (c["savedDeployedBefore"]?.AsArray() ?? new System.Text.Json.Nodes.JsonArray()).Select(t => t!.ToString()))
                if (DeployCommand.FirstDeployMarkerPath(1, readAtTheAct!, type) is { } marker)
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(marker)!);
                    File.WriteAllText(marker, "site");
                }

            if (expect["destinations"] is { } destinations)
                Assert.True(destinations.AsArray().Select(d => d!.ToString())
                    .SequenceEqual(readAtTheAct!.Configuration.AllDeployDestinations.Select(d => d.Type)), name);
            if (expect["schedulable"] is { } schedulable)
                Assert.True((ScheduledDeploy.Problem(readAtTheAct!, 1, DateTime.Now.AddDays(1), DateTime.Now) is null) ==
                            schedulable.GetValue<bool>(), name);
            // A notice exactly when the window holds something unsaved.
            bool noticeExpected = expect["notice"] is not null;
            Assert.True(window.Configuration.HasUnsavedChanges == noticeExpected, name);
        }
    }

    [Fact]
    public void TheSentencesAreTheContracts()
    {
        var names = ContractLoader.LoadJson("shared-rules.json")["specialNames"]!;
        string Message(string key) => names[key]!["message"]!.ToString();
        Assert.Equal(Message("settingsCouldNotBeReadToDeploy").Replace("{course}", "ICS3U"), SavedSettings.CouldNotBeReadToDeploy("ICS3U"));
        Assert.Equal(Message("deployUsesSavedSettings"), SavedSettings.DeployUsesSavedSettings);
        Assert.Equal(Message("schedulingUsesSavedSettings"), SavedSettings.SchedulingUsesSavedSettings);
        Assert.Equal(Message("previewUsesSavedSettings"), SavedSettings.PreviewUsesSavedSettings);
        Assert.Equal(Message("settingsSavedWhilePreviewing"), SavedSettings.SavedWhilePreviewing);
        Assert.Equal(Message("settingsSavedWhilePublishing"), SavedSettings.SavedWhilePublishing);
        Assert.Equal(Message("settingsPreviewAgainNothingOpen"), SavedSettings.PreviewAgainNothingOpen);
    }

    [Fact]
    public void TheTrailLineNamesKindsNeverPaths()
    {
        string dir = Path.Combine(_root, "ICS3U"); Directory.CreateDirectory(dir);
        string path = Path.Combine(dir, "course_config.json");
        File.WriteAllText(path, """{"deploy_target":"netlify"}""");
        var saved = new Course("ICS3U", dir, CourseConfiguration.Load(path));
        var window = new Course("ICS3U", dir, CourseConfiguration.Load(path));
        window.Configuration.Values["deploy_target"] = "local_folder";
        window.Configuration.Values["deploy_folder_path"] = @"C:\Users\pat\secret site";
        string line = SavedSettings.DeployUsedTheSavedSettingsLine("deployed from the section window", saved, window);
        Assert.Contains("netlify", line);
        Assert.Contains("different kind", line);
        Assert.DoesNotContain("secret", line);
    }
}

using Newtonsoft.Json.Linq;

namespace Plantoir.Core.Models;

/// <summary>
/// What enables Save in Course Settings (#387, mac #364 #373;
/// <c>shared-rules.json</c> → <c>savingSettings.whatEnablesSave</c>).
/// </summary>
/// <remarks>
/// <para><b>The rule.</b> Save is enabled exactly when the window's copy differs
/// from what it last read or wrote (every top-level key) and no problem holds
/// it back; Revert exactly when the copy differs. A destination problem holds
/// Save back ONLY when the unsaved edit MOVES where the course publishes — the
/// primary target, its folder, or any additional destination, compared with
/// what was last read or written.</para>
///
/// <para><b>Why the old shape was the likeliest real #373 here too.</b> This
/// app's Save was <c>dirty &amp;&amp; _publishingChoice.Problem is null</c>:
/// a local-folder course whose folder is missing on THIS PC, or a Cloudflare
/// course with no Account ID on this PC, could not save a colour scheme, and
/// nothing near Save said why. A destination already broken in the file is not
/// made worse by saving a colour scheme, so it no longer blocks one; it stays
/// reported under Deploying, where it always was.</para>
/// </remarks>
public static class SettingsSaveState
{
    /// <summary><c>courseSettingsWording.saveHeldBack</c>, with <c>{reason}</c> the problem's own sentence.</summary>
    public const string SaveHeldBackTemplate = "Save is held back until Deploying is fixed: {reason}";

    public static string SaveHeldBack(string reason) => SaveHeldBackTemplate.Replace("{reason}", reason);

    /// <summary>The trail's names for the three checks — never the path or the ID.</summary>
    public const string DeployFolderCheck = "deploy folder";
    public const string CloudflareAccountCheck = "cloudflare account id";
    public const string AdditionalDestinationCheck = "additional destination";

    /// <param name="SaveEnabled">Save can be pressed.</param>
    /// <param name="RevertEnabled">Revert can be pressed.</param>
    /// <param name="Check">Which check holds Save back, or null.</param>
    /// <param name="Reason">The problem's own sentence, or null.</param>
    public sealed record State(bool SaveEnabled, bool RevertEnabled, string? Check, string? Reason)
    {
        public bool HeldBack => Check is not null;

        /// <summary>The sentence beside Save, or null when nothing is held back.</summary>
        public string? Sentence => Reason is null ? null : SaveHeldBack(Reason);
    }

    /// <summary>Decide the buttons for this copy of a course's settings.</summary>
    /// <param name="cloudflareAccountId">The Account ID kept on THIS PC.</param>
    public static State Decide(CourseConfiguration configuration, string cloudflareAccountId)
    {
        bool dirty = configuration.HasUnsavedChanges;
        if (!dirty) return new State(false, false, null, null);

        var (check, reason) = MovesTheDestination(configuration)
            ? Problem(configuration, cloudflareAccountId)
            : (null, null);
        return new State(check is null, true, check, reason);
    }

    /// <summary>Whether the unsaved edit changes where the course publishes.</summary>
    public static bool MovesTheDestination(CourseConfiguration configuration)
    {
        var saved = configuration.LastReadOrWritten();
        if (saved is null) return true;
        foreach (string key in new[] { "deploy_target", "deploy_folder_path", "additional_deploy_targets" })
            if (!JToken.DeepEquals(Normalised(configuration.Values[key]), Normalised(saved[key])))
                return true;
        return false;
    }

    /// <summary>The first destination problem and which check found it, or (null, null).</summary>
    public static (string? Check, string? Reason) Problem(CourseConfiguration configuration, string cloudflareAccountId)
    {
        string? primary = configuration.DeployTarget switch
        {
            "local_folder" => CourseConfiguration.DeployFolderProblem(configuration.DeployFolderPath),
            "cloudflare_pages" => CourseConfiguration.CloudflareAccountProblem(cloudflareAccountId),
            _ => null,
        };
        if (primary is not null)
            return (configuration.DeployTarget == "local_folder" ? DeployFolderCheck : CloudflareAccountCheck, primary);
        foreach (var target in configuration.AdditionalDeployTargets)
        {
            string? problem = target.Type switch
            {
                "local_folder" => CourseConfiguration.DeployFolderProblem(target.Path),
                "cloudflare_pages" => CourseConfiguration.CloudflareAccountProblem(cloudflareAccountId),
                _ => null,
            };
            if (problem is not null) return (AdditionalDestinationCheck, problem);
        }
        return (null, null);
    }

    // A missing key and an empty string or list say the same thing about where a course publishes.
    private static JToken? Normalised(JToken? token) => token switch
    {
        null => null,
        JValue { Type: JTokenType.Null } => null,
        JValue { Type: JTokenType.String } value when ((string?)value ?? "").Length == 0 => null,
        JArray { Count: 0 } => null,
        _ => token,
    };
}

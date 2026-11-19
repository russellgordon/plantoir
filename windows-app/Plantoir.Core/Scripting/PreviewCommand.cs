using System;
using System.Collections.Generic;
using System.IO;

namespace Plantoir.Core.Scripting;

/// <summary>
/// The ONE place the app writes a <c>preview.ps1 --build-only</c> line (#828,
/// mac #729's <c>buildArguments(forADeploy:)</c>).
/// </summary>
/// <remarks>
/// <para><b>Why one builder, and why <c>forADeploy</c> has no default.</b>
/// Since #729 the launchers count a deploy's build leg
/// (<c>--build-only --for-deploy</c>) as a deploy, and any other
/// <c>--build-only</c> of the section as a build
/// (<c>contracts/shared-rules.json</c> → <c>deployWhileItsSectionDeploys</c>;
/// <c>app-rules.json</c> → <c>launcherFlags.preview</c> → <c>--for-deploy</c>).
/// A deploy's build leg that forgot the flag would be told "already being
/// built" by the wrong name; a rebuild that carried it would refuse every
/// preview while it runs, with a false sentence. So every call site must
/// CHOOSE, and <c>PreviewCommandTests</c> fails on a <c>"--build-only"</c>
/// literal anywhere else in the app.</para>
///
/// <para><b>Why the folder is asked (#828 plan review, M4).</b>
/// <c>plantoir-mcp</c> never refreshes a working folder's launchers (only the
/// window's <c>ToolchainReadiness.Ensure</c> does), and <c>preview.ps1</c>
/// refuses an option it does not know (<c>Unknown option</c>, exit 1). A
/// deploy_section on a folder not yet opened in an updated app would then
/// fail at its build leg where it worked the day before. So the flag is added
/// only when the folder's own <c>preview.ps1</c> carries it. Leaving it out of
/// an older launcher loses nothing: that launcher's guard cannot count the
/// flag anyway. The Windows twin of the contract's knownLimits item about two
/// copies of Plantoir of different ages; refreshing the launchers from the
/// server instead was rejected, because it would write the folder from a
/// second process while the window may be running <c>Ensure</c> on it.</para>
/// </remarks>
public static class PreviewCommand
{
    /// <summary>The flag a deploy's own build leg carries (#729).</summary>
    public const string ForDeployFlag = "--for-deploy";

    /// <summary>
    /// <c>COURSE SECTION --build-only [--non-interactive] [--for-deploy]</c>,
    /// the arguments after the script's name.
    /// </summary>
    /// <param name="workingFolder">The folder whose <c>preview.ps1</c> will run; read only to learn whether it takes <c>--for-deploy</c>.</param>
    /// <param name="forADeploy">True ONLY for a deploy's build leg (the window's Deploy, an assistant's deploy). Never for a rebuild of the preview, nor the scheduled wrapper's build (which counts as 'later' already).</param>
    /// <param name="nonInteractive">Adds <c>--non-interactive</c> (#391): nobody can answer a question.</param>
    public static string[] BuildOnlyArguments(string workingFolder, string course, int section, bool forADeploy, bool nonInteractive)
    {
        var arguments = new List<string> { course, section.ToString(), "--build-only" };
        if (nonInteractive) arguments.Add("--non-interactive");
        if (forADeploy && LauncherTakesForDeploy(workingFolder)) arguments.Add(ForDeployFlag);
        return arguments.ToArray();
    }

    /// <summary>
    /// Whether the folder's <c>preview.ps1</c> accepts <c>--for-deploy</c>: its
    /// flag parser names it as a case (<c>'--for-deploy'</c>). A folder with no
    /// launcher, or one that cannot be read, answers false, so nothing is
    /// passed that could be refused as unknown.
    /// </summary>
    public static bool LauncherTakesForDeploy(string workingFolder)
    {
        try
        {
            string launcher = Path.Combine(workingFolder, "preview.ps1");
            if (!File.Exists(launcher)) return false;
            using var stream = new FileStream(launcher, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            using var reader = new StreamReader(stream);
            return reader.ReadToEnd().Contains("'" + ForDeployFlag + "'", StringComparison.Ordinal);
        }
        catch
        {
            return false;
        }
    }
}

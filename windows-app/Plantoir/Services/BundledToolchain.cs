using System;
using System.IO;
using Plantoir.Core.Models;

namespace Plantoir.Services;

/// <summary>Where the app's bundled toolchain recipe lives, and the refresh entry point.</summary>
public static class BundledToolchain
{
    /// <summary>The recipe copied beside the executable at build time.</summary>
    public static string Root => Path.Combine(AppContext.BaseDirectory, "Toolchain");

    public static string SupportPath(string relative) =>
        Path.Combine(Root, "support", relative.Replace('/', Path.DirectorySeparatorChar));

    /// <summary>
    /// Whenever the app works in a folder: refresh stale launchers (only ones
    /// that already exist) HERE, synchronously — six small files, milliseconds
    /// — and START the mirror of the recipe into .toolchain in the background,
    /// returning at once (#473). The copy runs once per folder per process;
    /// <see cref="ToolchainReadiness"/> owns that rule, joins a second window
    /// to the copy already running, and says when the folder is ready. A copy
    /// that failed is started again only when <paramref name="retryAFailedCopy"/>.
    /// The copy's start and finish are logged to startup.log ("tools copy
    /// started" / "tools copy finished") by the app's own subscription.
    /// </summary>
    public static void RefreshWorkspace(string workspacePath, bool retryAFailedCopy = false)
    {
        App.LogDiagnostic($"BundledToolchain.RefreshWorkspace starting for '{workspacePath}'");
        try
        {
            App.LogDiagnostic("BundledToolchain.RefreshWorkspace: calling RefreshLaunchers");
            ToolchainMirror.RefreshLaunchers(workspacePath, Root);
            App.LogDiagnostic("BundledToolchain.RefreshWorkspace: handing the tools copy to the background");
            _ = ToolchainReadiness.Ensure(workspacePath, Root, retryAFailedCopy);
            App.LogDiagnostic($"BundledToolchain.RefreshWorkspace: done (tools copy {ToolchainReadiness.StateOf(workspacePath)})");
        }
        catch (Exception ex)
        {
            App.LogDiagnostic($"BundledToolchain.RefreshWorkspace EXCEPTION: {ex}");
        }
    }

}

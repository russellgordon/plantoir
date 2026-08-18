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
    /// that already exist) and mirror the recipe into .toolchain.
    /// </summary>
    public static void RefreshWorkspace(string workspacePath)
    {
        App.LogDiagnostic($"BundledToolchain.RefreshWorkspace starting for '{workspacePath}'");
        try
        {
            App.LogDiagnostic("BundledToolchain.RefreshWorkspace: calling RefreshLaunchers");
            ToolchainMirror.RefreshLaunchers(workspacePath, Root);
            App.LogDiagnostic("BundledToolchain.RefreshWorkspace: calling RefreshToolchain");
            ToolchainMirror.RefreshToolchain(workspacePath, Root);
            App.LogDiagnostic("BundledToolchain.RefreshWorkspace: done");
        }
        catch (Exception ex)
        {
            App.LogDiagnostic($"BundledToolchain.RefreshWorkspace EXCEPTION: {ex}");
        }
    }

}

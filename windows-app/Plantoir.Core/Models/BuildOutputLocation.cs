using System;
using System.IO;

namespace Plantoir.Core.Models;

/// <summary>
/// Where a section's BUILT WEBSITE is kept — which on Windows is not inside the
/// working folder.
///
/// <para>A built site is DERIVED: every file in it comes from the teacher's
/// notes and can be made again. Nothing outside Plantoir knows that, so a
/// cloud-synced folder uploads every build against the teacher's quota, a
/// backup copies it, and a folder handed to a colleague carries it. Windows
/// moved builds out to <c>%LOCALAPPDATA%\Plantoir\builds\{folder id}</c> in
/// GUI-IMPROVEMENTS row 290, and keeps its flat layout — the mac's symlink is
/// a mac answer to a mac problem (a container that mounts only
/// <c>courses/</c>) and is deliberately not copied. See
/// <c>shared-rules.json</c> → <c>buildOutputLocation</c>.</para>
///
/// <para><b>This type exists because nothing in the app knew that path.</b>
/// Only the launchers and the Python did, so <see cref="BuildFreshness"/> went
/// on reading <c>&lt;course&gt;\.merged_output\…</c> — the pre-row-290
/// location — long after Windows stopped writing there, and nothing could
/// clear a course's build when the course was archived.</para>
///
/// <para><b>Every method except <see cref="BuildsRootFor"/> takes the ROOT
/// rather than the working folder</b>, so a caller computes it once and a TEST
/// can hand over a temporary directory. Deriving the root inside each method
/// would have every test writing into the real
/// <c>%LOCALAPPDATA%\Plantoir\builds</c> — the same mistake that put 263
/// lines about a fixture course into a teacher's real activity trail.</para>
/// </summary>
public static class BuildOutputLocation
{
    /// <summary>
    /// The builds root for a working folder:
    /// <c>%LOCALAPPDATA%\Plantoir\builds\{folder id}</c>.
    ///
    /// <para>The id comes from <see cref="FolderContainers.FolderIdentifier"/>
    /// rather than from a second hash of its own — the launcher computes the
    /// same value as <c>$WORKDIR_ID</c>, and two derivations are how they
    /// would come apart.</para>
    ///
    /// <para><c>PLANTOIR_BUILD_ROOT</c> is honoured when set, which the
    /// contract's <c>windowsLocation</c> describes. In practice that is a TEST
    /// HOOK rather than a runtime path: the app never sets it, and the
    /// launchers overwrite it unconditionally in <c>Enter-NativeRuntime</c>.
    /// Said plainly so the next reader does not conclude the app is the one
    /// setting it.</para>
    /// </summary>
    public static string BuildsRootFor(string workingFolderPath)
    {
        string? overridden = Environment.GetEnvironmentVariable("PLANTOIR_BUILD_ROOT");
        if (!string.IsNullOrWhiteSpace(overridden)) return overridden!;

        return AppDataRoot.Combine("builds", FolderContainers.FolderIdentifier(workingFolderPath));
    }

    /// <summary>
    /// Where a course's built sites are kept:
    /// <c>…\builds\{id}\{COURSE}</c>.
    /// </summary>
    public static string ForCourse(string buildsRoot, string courseCode) =>
        Path.Combine(buildsRoot, courseCode);

    /// <summary>
    /// One section's built site: <c>…\builds\{id}\{COURSE}\section{N}</c>.
    /// </summary>
    public static string ForSection(string buildsRoot, string courseCode, int sectionNumber) =>
        Path.Combine(ForCourse(buildsRoot, courseCode), "section" + sectionNumber);

    /// <summary>
    /// The page a freshness check reads:
    /// <c>…\section{N}\public\index.html</c>.
    /// </summary>
    public static string BuiltIndexFor(string buildsRoot, string courseCode, int sectionNumber) =>
        Path.Combine(ForSection(buildsRoot, courseCode, sectionNumber), "public", "index.html");

    /// <summary>
    /// The BUILD WORKSPACE for a course — <c>…\builds\{id}\work\{COURSE}</c>,
    /// where the Quartz project and its <c>node_modules</c> live and what a
    /// preview actually serves from.
    ///
    /// <para>Separate from <see cref="ForCourse"/> and easy to forget: clearing
    /// a course's built site without clearing its workspace leaves the half
    /// that a preview serves and that <c>preview.ps1 --stop</c> hunts by
    /// path.</para>
    /// </summary>
    public static string WorkspaceForCourse(string buildsRoot, string courseCode) =>
        Path.Combine(buildsRoot, "work", courseCode);

    /// <summary>One section's build workspace.</summary>
    public static string WorkspaceForSection(string buildsRoot, string courseCode, int sectionNumber) =>
        Path.Combine(WorkspaceForCourse(buildsRoot, courseCode), "section" + sectionNumber);

    /// <summary>
    /// Throw away a course's built site AND its build workspace.
    ///
    /// <para><b>Why anything deletes a build at all.</b> A built site outlives
    /// the content it was made from. Archive a course and restore it later —
    /// or restore a backup over it — and the notes that come back can be OLDER
    /// than the site standing outside, so a freshness check comparing dates
    /// says "already up to date" and the next publish puts last month's pages
    /// online. The mac has the same rule and reaches it a different way: there
    /// a build with no symlink pointing at it is cleared rather than reused.
    /// Windows has no link, so the clearing has to be explicit at each of the
    /// moments a course's content is replaced.</para>
    ///
    /// <para>Nothing here is a teacher's own work: everything under the builds
    /// root is derived, and the site markers (<c>.netlify_sites</c>,
    /// <c>.cloudflare_sites</c>) and publish stamps (<c>.publish_state</c>)
    /// live under the COURSE folder, not here. The cost of being wrong is one
    /// rebuild.</para>
    ///
    /// <para>Best-effort by design: a locked file — a preview still serving, a
    /// virus scanner mid-read — must not turn "archive this course" into an
    /// error. A build that survives is stale rather than dangerous, because
    /// whatever left it locked is still running and will be rebuilt over.</para>
    /// </summary>
    public static void DiscardBuildsFor(string buildsRoot, string courseCode)
    {
        if (WouldCollideWithEveryCourse(courseCode)) return;
        Discard(ForCourse(buildsRoot, courseCode));
        Discard(WorkspaceForCourse(buildsRoot, courseCode));
    }

    /// <summary>
    /// Throw away ONE section's built site and workspace, leaving the course's
    /// other sections alone.
    /// </summary>
    public static void DiscardBuildsFor(string buildsRoot, string courseCode, int sectionNumber)
    {
        if (WouldCollideWithEveryCourse(courseCode)) return;
        Discard(ForSection(buildsRoot, courseCode, sectionNumber));
        Discard(WorkspaceForSection(buildsRoot, courseCode, sectionNumber));
    }

    /// <summary>
    /// The one course code that must never be discarded by name.
    ///
    /// <para><c>builds\{id}\work</c> holds EVERY course's build workspace, so
    /// a course code of "work" makes <see cref="ForCourse"/> resolve to that
    /// shared directory — and deleting it would pull the ground from under
    /// every other course's preview. Windows filesystems are
    /// case-insensitive, so "Work" and "WORK" are the same collision.</para>
    ///
    /// <para>The layout collision itself is older than this file and lives in
    /// the Python too (<c>toolchain_paths.merged_output_root</c> uses the
    /// course directory's name), but nothing DELETED by that path until now.
    /// Refusing here is the cheap half; the naming is recorded for the mac in
    /// MAC-HANDOFF.</para>
    /// </summary>
    private const string WorkspaceDirectoryName = "work";

    private static bool WouldCollideWithEveryCourse(string courseCode) =>
        courseCode.Equals(WorkspaceDirectoryName, StringComparison.OrdinalIgnoreCase);

    private static void Discard(string directory)
    {
        try
        {
            if (Directory.Exists(directory)) CourseRestorer.DeleteTree(directory);
        }
        catch
        {
            // Best-effort, deliberately. See the note above.
        }
    }
}

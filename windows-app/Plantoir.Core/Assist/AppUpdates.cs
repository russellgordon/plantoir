using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// Plantoir on Windows finding and installing its own updates (#337, the
/// mac's #204) — the parts that are RULES, so they are played from
/// <c>shared-rules.json → appUpdates</c> rather than eyeballed. The engine
/// that fetches the feed and downloads the installer (NetSparkleUpdater, per
/// design A in documentation/11) is NOT wired yet: no release and no feed
/// exist, and its API was not verified against a restored package. What is
/// here is everything that decides WHETHER an install may happen and what the
/// teacher is told.
/// </summary>
public static class AppUpdates
{
    /// <summary><c>appUpdates.feed.windows</c>. One key and one feed per platform.</summary>
    public const string Feed = "https://plantoir.app/updates/windows.xml";

    /// <summary>
    /// THE one place the engine reads its feed from, and EMPTY until a release
    /// sets it to <see cref="Feed"/> (with <see cref="PublicKey"/>): no feed,
    /// no key and no release exist yet, so nothing is checked. Set by the
    /// release flow, never by a setting a teacher can reach (the contract
    /// rejects a user-settable feed).
    /// </summary>
    public const string ConfiguredFeed = "";

    /// <summary>The Ed25519 public key (base64) the feed and download must be signed with. Empty until the key exists.</summary>
    public const string PublicKey = "";

    /// <summary>A development build has no feed at all (decision 5): nothing is constructed, no menu item shows.</summary>
    public static string? FeedFor(bool developmentBuild) => developmentBuild ? null : Feed;

    public const int CheckEverySeconds = 86400;

    // ---- What is under way (appUpdates.cases, mayNotInstallWhile) -----------

    public sealed record OtherCopy(int Pid, string Kind, string? Course = null, int? Section = null);

    public sealed record LeaseFact(int Pid, string Kind, string Course);

    public sealed record Snapshot(
        IReadOnlyList<(string Course, int Section)> Publishes,
        IReadOnlyList<(string Course, int Section)> PreviewBuilds,
        int PreviewsOpen,
        IReadOnlyList<OtherCopy> OtherCopies,
        IReadOnlyList<LeaseFact> Leases);

    public enum Named { Nothing, TheQuitQuestionsWords, ScheduledWork, ScheduledWorkUnnamed, ElsewhereWork }

    public sealed record Hold(Named NamedAs, string? Course = null, int? Section = null)
    {
        public bool Held => NamedAs != Named.Nothing;
    }

    /// <summary>
    /// Whether an install must wait, and how the work is named: this app's own
    /// publish first (it reaches the class website), then a scheduled publish of
    /// this install (named, or unnamed for a job set before v1.2.0), then a
    /// preview this app is BUILDING, then another program's build or publish.
    /// An open preview, an assistant that is only connected, and an assist or
    /// import lease do not hold it.
    /// </summary>
    public static Hold Evaluate(Snapshot s)
    {
        if (s.Publishes.Count > 0) return new Hold(Named.TheQuitQuestionsWords);
        if (s.OtherCopies.FirstOrDefault(c => c.Kind == "scheduledPublish") is { } scheduled)
            return scheduled.Course is null
                ? new Hold(Named.ScheduledWorkUnnamed)
                : new Hold(Named.ScheduledWork, scheduled.Course, scheduled.Section);
        if (s.PreviewBuilds.Count > 0) return new Hold(Named.TheQuitQuestionsWords);
        var scheduledPids = s.OtherCopies.Where(c => c.Kind == "scheduledPublish").Select(c => c.Pid).ToHashSet();
        if (s.Leases.FirstOrDefault(l => !scheduledPids.Contains(l.Pid) && l.Kind is WorkLease.Building or WorkLease.Publishing) is { } other)
            return new Hold(Named.ElsewhereWork, other.Course);
        return new Hold(Named.Nothing);
    }

    /// <summary>
    /// The Windows gate ON TOP of <see cref="Evaluate"/> (bundle-8 ruling 2):
    /// the installer replaces plantoir-mcp.exe, so ANY running outside-assistant
    /// server holds the install — one may be publishing in a folder this app
    /// has never opened, which no lease in a known folder would show. The mac
    /// has no such case (its server IS the app). Asked again at the moment of
    /// install, never only when the update was offered.
    /// </summary>
    public static Hold EvaluateForInstall(Snapshot s, IReadOnlyList<int> assistantServersRunning)
    {
        var hold = Evaluate(s);
        if (hold.Held) return hold;
        return assistantServersRunning.Count > 0 ? new Hold(Named.ElsewhereWork) : hold;
    }

    // ---- At quit (appUpdates.atQuit) -----------------------------------------

    public enum Prepared { None, ReadyToInstall, HeldForWork, PostponedAtInstall }

    public enum AtQuit { NothingToDo, InstallsAsItQuits, SetAside }

    /// <summary>A quit is never refused (decision 7); with work under way the prepared update is set aside.</summary>
    public static AtQuit DecideAtQuit(Prepared prepared, bool workUnderWay) => prepared switch
    {
        Prepared.None => AtQuit.NothingToDo,
        Prepared.PostponedAtInstall => AtQuit.InstallsAsItQuits,
        _ => workUnderWay ? AtQuit.SetAside : AtQuit.InstallsAsItQuits,
    };

    // ---- The installer ---------------------------------------------------------

    /// <summary>
    /// What the downloaded <c>PlantoirSetup.exe</c> is started with. Silent and
    /// per-user. <c>/PLANTOIRUPDATE=1</c> makes installer.iss SKIP its taskkill
    /// of plantoir-mcp and llama-server (ruling 2: the app already refused to
    /// install while either could be working). <c>/RELAUNCH=1</c> is set ONLY
    /// by the in-app Install path (ruling 1): installer.iss's [Run] entry is
    /// <c>skipifsilent</c>, so without it a silent install never reopens, and
    /// "Plantoir will close and open again by itself" would be false. The
    /// at-quit install never passes it. <c>/NOCLOSEAPPLICATIONS</c> (ruling 8):
    /// Restart Manager must not close plantoir-mcp or a scheduled run on the
    /// update path; the app quits itself first.
    /// </summary>
    public static string InstallerArguments(bool relaunch, string? returnTo = null) =>
        "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOCLOSEAPPLICATIONS /PLANTOIRUPDATE=1" + (relaunch ? " /RELAUNCH=1" : "") +
        (string.IsNullOrEmpty(returnTo) ? "" : $" \"/RETURNTO={returnTo}\"");

    /// <summary>
    /// What installer.iss starts Plantoir with when it REFUSES an update
    /// (ruling 12): a plantoir-mcp started between the app's last check and
    /// setup, so the teacher is not left with Plantoir simply gone.
    /// </summary>
    public const string UpdateNotInstalledArgument = "--update-not-installed";

    /// <summary>The `update held while work is under way` line for that launch, or null when it is an ordinary one.</summary>
    public static string? NotInstalledLine(IEnumerable<string> arguments) =>
        arguments.Any(a => string.Equals(a, UpdateNotInstalledArgument, StringComparison.OrdinalIgnoreCase))
            ? $"the new version was not installed: {UpdateWording.AssistantElsewhereWork} had started; it will be offered again"
            : null;

    /// <summary>
    /// Whether this copy may update itself (ruling 3). Only a copy under
    /// <c>%LOCALAPPDATA%\Programs</c> is updated: a silent per-user update of
    /// an all-users copy in Program Files would put a SECOND copy beside it, so
    /// that one shows the contract's needsAdministrator sentences instead.
    /// Since 2026-10-01 installer.iss installs per-user ONLY (it no longer
    /// offers an all-users install), so every copy it makes updates itself; the
    /// refusal stays for an all-users copy an older installer made.
    /// </summary>
    public static bool IsPerUserInstall(string executableDirectory, string localAppData)
    {
        string root = Path.GetFullPath(Path.Combine(localAppData, "Programs")).TrimEnd('\\', '/') + Path.DirectorySeparatorChar;
        string dir = Path.GetFullPath(executableDirectory).TrimEnd('\\', '/') + Path.DirectorySeparatorChar;
        return dir.StartsWith(root, StringComparison.OrdinalIgnoreCase);
    }

    // ---- "app updated" (activityTrail) ----------------------------------------

    /// <summary>
    /// The trail line at the first launch whose version differs from the last
    /// launch's, or null. Covers a copy installed by hand too, which is why it
    /// is owed from the day it is read, updater or not.
    /// </summary>
    public static string? AppUpdatedLine(string? lastLaunched, string running, bool byItsOwnUpdater) =>
        string.IsNullOrWhiteSpace(lastLaunched) || lastLaunched == running
            ? null
            : $"updated from {lastLaunched} to {running}, " +
              (byItsOwnUpdater ? "by its own updater" : "by hand (a new copy installed some other way)");
}

/// <summary>
/// What the teacher reads about updates (rule 1: no machinery words). The
/// contract's <c>appUpdates.wording</c>, plus the Windows-only sentences in
/// <c>appUpdates.windowsWording</c>: Windows draws its own offer dialog where
/// the mac shows Sparkle's, so it needs words the mac does not have.
/// </summary>
public static class UpdateWording
{
    public const string MenuItem = "Check for Updates…";
    public const string HeldTitle = "Plantoir will finish updating once it is done {work}.";
    public const string ScheduledWork = "publishing Section {section} of {course} on its schedule";
    public const string ScheduledWorkUnnamed = "publishing on its schedule";
    /// <summary>The contract's words, which name a Mac.</summary>
    public const string ElsewhereWorkContract = "waiting for {course} to finish building somewhere else on this Mac";
    /// <summary>What Windows says until the contract carries a {machine} placeholder (proposed to the mac): windowsWording.elsewhereWorkOnWindows.</summary>
    public const string ElsewhereWorkOnWindows = "waiting for {course} to finish building somewhere else on this PC";
    public static string ElsewhereWork(string course) => ElsewhereWorkOnWindows.Replace("{course}", course);
    public const string HeldExplanation =
        "The new version is ready. Plantoir will close and open again by itself as soon as that is finished. If you quit Plantoir before then, the update is set aside and offered again later.";
    public const string HeldExplanationOnceInstalling =
        "The new version is ready. Plantoir will close and open again by itself as soon as that is finished. If you quit Plantoir before then, it finishes updating as it quits.";
    public const string OkButton = "OK";
    public const string NeedsAdministratorTitle = "Plantoir could not install the new version.";
    public const string NeedsAdministratorExplanation =
        "Installing it on this Mac needs an administrator’s name and password, and none was given. To try again, choose Check for Updates… in the Plantoir menu. If you do not have an administrator’s password, whoever looks after this Mac can install it for you.";

    // Windows-only (appUpdates.windowsWording), proposed to the mac in the bundle-8 draft.
    public const string OfferTitle = "A new version of Plantoir is ready: {version}.";
    public const string OfferInstall = "Install and Reopen";
    public const string OfferLater = "Not Now";
    public const string OfferSkip = "Skip This Version";
    public const string UpToDate = "Plantoir is up to date.";
    public const string CouldNotCheck = "Plantoir could not find out whether a new version is ready. It will try again tomorrow.";
    public const string AssistantElsewhereWork = "helping an assistant in another app";
    public const string NeedsAdministratorExplanationOnWindows =
        "Plantoir was installed for everyone who uses this PC, so a new version needs an administrator to install it. Whoever looks after this PC can download it from plantoir.app.";

    /// <summary>The {work} phrase for a hold.</summary>
    public static string Work(AppUpdates.Hold hold, string theQuitQuestionsWords) => hold.NamedAs switch
    {
        AppUpdates.Named.TheQuitQuestionsWords => theQuitQuestionsWords,
        AppUpdates.Named.ScheduledWork => ScheduledWork.Replace("{section}", hold.Section?.ToString() ?? "").Replace("{course}", hold.Course ?? ""),
        AppUpdates.Named.ScheduledWorkUnnamed => ScheduledWorkUnnamed,
        AppUpdates.Named.ElsewhereWork when hold.Course is { } course => ElsewhereWork(course),
        AppUpdates.Named.ElsewhereWork => AssistantElsewhereWork,
        _ => "",
    };
}

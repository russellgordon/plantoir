using System;
using System.Net.Http;
using System.Net.Sockets;

namespace Plantoir.Core.Models;

/// <summary>
/// What the wait for a preview does next — the Windows half of the mac's
/// <c>PreviewReachability</c> (#233 / mac #225, #278 / mac #235). A pure
/// function of what has been seen, so the view's loop only acts on it and the
/// rules can be tested without a window.
///
/// <para>Contract: <c>app-rules.json → previewPorts.whenThePreviewNeverAppears</c>.
/// Three rules, in this order:</para>
/// <list type="number">
/// <item>A run the teacher stopped, or one that has ended, is simply left —
/// no alert and no trail line about a preview they ended themselves
/// (<c>whenNoAddressWasAnnounced.evenAfterTheTeacherPressedStop: false</c>).</item>
/// <item>Once the builder has said <c>Started a Quartz server</c> with no
/// address announced, the wait gives up AT ONCE: the launcher announces
/// before it builds and output is read in order, so a missing address is
/// final, not late. Nothing is guessed — the old code started from the port
/// INSIDE the builder, wrong for every folder after the first.</item>
/// <item>The QUIET is bounded, not the run: 45 s with no output, counted from
/// that server line and restarted by every piece of output after it. A first
/// build legitimately takes minutes, so the run itself is never bounded.</item>
/// </list>
/// </summary>
public static class PreviewReachability
{
    /// <summary>Quartz's own line, printed natively on Windows too.</summary>
    public const string ServerStartedLine = "Started a Quartz server";

    /// <summary><c>whenThePreviewNeverAppears.secondsOfSilenceAllowed</c>.</summary>
    public const int SecondsOfSilenceAllowed = 45;

    public enum Verdict
    {
        /// <summary>This PC was asked and answered that nothing was listening there.</summary>
        TheSiteNeverAnswered,
        /// <summary>No answer could be had — or no address was ever announced.</summary>
        PlantoirCouldNotTell,
    }

    public enum Step { KeepWaiting, TryTheAddress, GiveUpNoAddress, GiveUpSilence, LeaveIt }

    /// <summary>The next step for one tick of the wait.</summary>
    /// <param name="runIsOver">The run has ended, or the teacher pressed Stop.</param>
    /// <param name="serverStartedAt">When "Started a Quartz server" was first seen; null before.</param>
    /// <param name="lastOutputAt">When the latest piece of output arrived.</param>
    public static Step NextStep(bool runIsOver, Uri? announcedAddress, DateTime? serverStartedAt,
                                DateTime lastOutputAt, DateTime now)
    {
        if (runIsOver) return Step.LeaveIt;
        if (serverStartedAt is not { } started)
            return announcedAddress is null ? Step.KeepWaiting : Step.TryTheAddress;
        if (announcedAddress is null) return Step.GiveUpNoAddress;
        DateTime quietSince = lastOutputAt > started ? lastOutputAt : started;
        return (now - quietSince).TotalSeconds >= SecondsOfSilenceAllowed ? Step.GiveUpSilence : Step.TryTheAddress;
    }

    /// <summary>
    /// What the LAST attempt to open the address says about why it never
    /// answered. Only a refusal from this PC is an answer ("nothing is
    /// serving it"); a timeout, or anything else, is not — and "I asked and
    /// the answer was no" must never be reported for "I could not find out".
    /// On Windows the site is served on the PC itself, so there is no builder
    /// to ask and no counterpart to the mac's first verdict.
    /// </summary>
    public static Verdict VerdictFrom(Exception? lastAttempt) =>
        lastAttempt is HttpRequestException { InnerException: SocketException { SocketErrorCode: SocketError.ConnectionRefused } }
            ? Verdict.TheSiteNeverAnswered
            : Verdict.PlantoirCouldNotTell;

    /// <summary><c>whenThePreviewNeverAppears.alertTitle</c>.</summary>
    public const string AlertTitle = "Your Preview Did Not Appear";

    /// <summary>
    /// <c>cases[1].sentence</c> as the contract writes it, <c>{machine}</c> and
    /// all (<c>specialNames.platformWording.machine.usedIn</c>, #438).
    /// </summary>
    public const string TheSiteNeverAnsweredContract =
        "Your website did not come up, so Plantoir stopped waiting for it.\n\n" +
        "Nothing has been lost. Press Preview to try again — and if it happens again, restarting your {machine} usually puts it right.";

    /// <summary>
    /// The contract's sentence for a verdict, its <c>{machine}</c> said as
    /// <see cref="MachineWord.Name"/>.
    /// </summary>
    public static string Sentence(Verdict verdict) => verdict switch
    {
        Verdict.TheSiteNeverAnswered => MachineWord.Fill(TheSiteNeverAnsweredContract),
        _ =>
            "Plantoir could not get your website to appear, and could not tell why.\n\n" +
            "Nothing has been lost. Press Preview to try again — and if it happens again, choose “Report a Problem…” " +
            "from the Help menu so somebody can see what happened.",
    };

    /// <summary>The trail line for <c>preview did not appear</c>, without the place (the Note adds it).</summary>
    public static string TrailLine(Step why, Verdict verdict, int quietSeconds) => why == Step.GiveUpNoAddress
        ? "preview did not appear — its website started and no address for it was ever announced, so there was nothing to open"
        : $"preview did not appear — said nothing for {quietSeconds} s after its server started; " +
          (verdict == Verdict.TheSiteNeverAnswered
              ? "nothing was serving it on this PC"
              : "Plantoir could not tell why");
}

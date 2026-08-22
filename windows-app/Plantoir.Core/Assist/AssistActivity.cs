using System;
using System.Collections.Generic;

namespace Plantoir.Core.Assist;

/// <summary>
/// Which assistant windows are open right now, across the whole app.
///
/// Mirrors the mac's `AssistActivity`, with one difference the mac does not
/// have to make: the mac enforces one assistant window at a time, so it only
/// ever needs a single active session. Windows does not (yet) have that
/// limit — see WINDOWS-HANDOFF.md — so this tracks a SET of open sessions
/// rather than one. What both sides need this for is narrower than the
/// bigger "one at a time" feature: knowing whether ANY assistant window is
/// open, so Settings can refuse to delete a model file out from under a
/// running `llama-server.exe`.
///
/// The bug this exists to stop: a teacher downloads a model, opens the
/// assistant (which spawns a server that has the file open), goes back to
/// Settings and removes that same model. Whether the delete succeeds while
/// the server still has the file open is Windows' own file-sharing rules to
/// decide, not something this app controls — but even where it "works" for
/// the reply already in flight, the model file is gone for the NEXT prompt,
/// a server restart, or a second window. Settings should not offer the
/// button at all while that risk exists.
/// </summary>
public static class AssistActivity
{
    /// <summary>The section an assistant window is open for.</summary>
    public readonly record struct Session(string FolderPath, string CourseCode, int SectionNumber);

    private static readonly object Gate = new();
    private static readonly HashSet<Session> Open = new();

    /// <summary>Raised whenever a window opens or closes, so a settings
    /// dialog already on screen can redraw without polling.</summary>
    public static event Action? Changed;

    /// <summary>
    /// Records that an assistant window has opened for one section.
    ///
    /// Claimed as the window opens, not once the engine is ready — a teacher
    /// three minutes into a download still has the assistant open as far as
    /// removing its model is concerned.
    /// </summary>
    public static void Begin(string folderPath, string courseCode, int sectionNumber)
    {
        lock (Gate) Open.Add(new Session(folderPath, courseCode, sectionNumber));
        Changed?.Invoke();
    }

    /// <summary>
    /// Records that an assistant window has closed. Safe to call even if
    /// <see cref="Begin"/> was never reached for this session — released
    /// unconditionally, because leaving a stale claim behind locks Settings
    /// out of removing anything until the app restarts, which is worse than
    /// this running once too often.
    /// </summary>
    public static void End(string folderPath, string courseCode, int sectionNumber)
    {
        lock (Gate) Open.Remove(new Session(folderPath, courseCode, sectionNumber));
        Changed?.Invoke();
    }

    /// <summary>Whether any assistant window is open anywhere in the app.</summary>
    public static bool AnyOpen
    {
        get { lock (Gate) return Open.Count > 0; }
    }

    /// <summary>
    /// One open session, to name in a message to the teacher — the first
    /// found when several windows are open. Naming every open window would
    /// be a paragraph; naming one is still enough to say what to close.
    /// </summary>
    public static Session? Active
    {
        get
        {
            lock (Gate)
            {
                foreach (var session in Open) return session;
                return null;
            }
        }
    }

    /// <summary>Forget everything, for tests — process-wide state that
    /// outlives a test answers the next test's questions.</summary>
    public static void Reset()
    {
        lock (Gate) Open.Clear();
        Changed?.Invoke();
    }
}

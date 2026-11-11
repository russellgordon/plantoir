namespace Plantoir.Core.Scripting;

/// <summary>
/// One asker per question (#728). A section's deploy runner is shared by every
/// view of the section in every window (<see cref="SectionRuns"/>), so a
/// question the deploy asks — a publishing credential, say — would otherwise
/// be put up in each of them, each sending its own answer to the one prompt.
/// The first view to claim the runner asks; a view taken off screen with its
/// dialog up (a window closing, or the assistant changing the selection) hides
/// the dialog and HANDS THE QUESTION ON — the next live view asks it — rather
/// than cancelling it; and a dialog that closes after its view has left sends
/// nothing, whichever button it reports.
/// </summary>
/// <remarks>
/// The mac shows the question in every window and lets the binding close the
/// others when one is answered (<c>documentation/09-mac-app.md</c>). Windows'
/// ContentDialog is not bound to the runner, so it needs this instead.
/// Interface thread in practice; locked anyway.
/// </remarks>
public static class QuestionAskers
{
    /// <summary>What a closing question dialog does with the runner.</summary>
    public enum Answer { Send, Cancel, Nothing }

    private static readonly Dictionary<ScriptRunner, object> s_asking = new();
    private static readonly object s_gate = new();

    /// <summary>A question was left unanswered by the view asking it: another view may ask it.</summary>
    public static event Action<ScriptRunner>? LeftUnanswered;

    /// <summary>True when <paramref name="asker"/> is now the one asking <paramref name="runner"/>'s question.</summary>
    public static bool TryClaim(ScriptRunner runner, object asker)
    {
        lock (s_gate)
        {
            if (s_asking.TryGetValue(runner, out var holder)) return ReferenceEquals(holder, asker);
            s_asking[runner] = asker;
            return true;
        }
    }

    /// <summary>The asker is done with the question (answered or cancelled). Only its own claim is let go.</summary>
    public static void Release(ScriptRunner runner, object asker)
    {
        lock (s_gate)
            if (s_asking.TryGetValue(runner, out var holder) && ReferenceEquals(holder, asker))
                s_asking.Remove(runner);
    }

    /// <summary>The asker left with the question up: let it go and tell the other views.</summary>
    public static void HandOn(ScriptRunner runner, object asker)
    {
        bool released;
        lock (s_gate)
        {
            released = s_asking.TryGetValue(runner, out var holder) && ReferenceEquals(holder, asker);
            if (released) s_asking.Remove(runner);
        }
        if (released) LeftUnanswered?.Invoke(runner);
    }

    /// <summary>
    /// What a dialog that has just closed does: nothing once its view has
    /// left (the question was handed on, and another view may be answering
    /// it) or once the runner no longer waits; otherwise send on the main
    /// button and cancel on any other.
    /// </summary>
    public static Answer WhatToDo(bool pressedTheMainButton, bool askerHasLeft, bool runnerStillWaits) =>
        askerHasLeft || !runnerStillWaits ? Answer.Nothing
        : pressedTheMainButton ? Answer.Send
        : Answer.Cancel;

    /// <summary>For tests only.</summary>
    internal static void Reset()
    {
        lock (s_gate) s_asking.Clear();
        LeftUnanswered = null;
    }
}

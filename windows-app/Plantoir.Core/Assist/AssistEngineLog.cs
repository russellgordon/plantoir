using System;
using System.Collections.Generic;
using System.Linq;

namespace Plantoir.Core.Assist;

/// <summary>
/// Which of the local engine's own log lines are worth putting on the
/// activity trail, and how much of it a single conversation may spend.
///
/// Ported from the mac's <c>AssistSession</c> — same filter, same cap, same
/// reasoning — but kept as pure functions here rather than folded into
/// <see cref="LocalModel"/> or the assistant window, so the one thing that
/// actually needs pinning (what counts as trouble, and how much survives)
/// can be tested without a running <c>llama-server</c>. See
/// <c>contracts/shared-rules.json</c> → <c>activityTrail.mustRecord</c> →
/// "assistant engine said" for why this exists at all: until it did, a
/// report from a teacher whose assistant was misbehaving carried nothing the
/// engine itself had said, because both its streams went to the null device.
/// </summary>
public static class AssistEngineLog
{
    /// <summary>
    /// The most of the engine's own chatter one conversation may put on the
    /// trail.
    ///
    /// The trail is deliberately coarse — a record of what the TEACHER did —
    /// and its failure mode is the one line that mattered ending up on page
    /// forty. A cap is what keeps a chatty engine from being that page forty.
    /// Twelve is enough for a model that will not load (the reason is in the
    /// last handful of lines) and nowhere near enough to bury a morning's work.
    /// </summary>
    public const int MostEngineLinesOnTheTrail = 12;

    /// <summary>
    /// Which of the engine's lines go on the trail, already shortened.
    ///
    /// <paramref name="keepingEverything"/> is for the one case where the
    /// ordinary filter is wrong: an engine that never became ready. There,
    /// every line is the diagnosis — including the perfectly ordinary ones
    /// it got through before it stopped.
    ///
    /// Separated from the writing so what is worth keeping, and how much,
    /// can be checked against real engine output without an engine.
    /// </summary>
    public static IReadOnlyList<string> LinesWorthRecording(
        IEnumerable<string> lines,
        bool keepingEverything,
        int alreadyRecorded,
        int cap = MostEngineLinesOnTheTrail)
    {
        var worthKeeping = new List<string>();
        foreach (var line in lines)
        {
            if (keepingEverything || ReadsLikeATrouble(line))
            {
                worthKeeping.Add(line);
            }
        }

        // The LAST few, not the first: when an engine gives up, the reason
        // is at the bottom of what it wrote.
        int roomLeft = Math.Max(0, cap - alreadyRecorded);
        int startIndex = Math.Max(0, worthKeeping.Count - roomLeft);
        return worthKeeping.Skip(startIndex).Select(line => Shortened(line)).ToList();
    }

    /// <summary>
    /// Whether a line the engine wrote is worth a teacher's trail.
    ///
    /// Measured against a real engine rather than guessed (llama.cpp build
    /// b10435). Its lines carry a severity letter as their second
    /// whitespace-separated field — <c>0.46.018.667 E srv send_error: …</c>
    /// — so <c>E</c> is the signal to key off. Warnings deliberately are
    /// NOT: a perfectly healthy start prints several of them (a CORS block
    /// that cannot matter on a loopback-only server, and a token-type quirk
    /// in the weights) — recording those would spend the whole budget on
    /// noise before the teacher had asked anything.
    ///
    /// The word test beside it is the belt to that braces: the severity
    /// field is this build's format and a future build could drop it, while
    /// a line naming an error or an exception says so in any format. It is
    /// what catches a warning line that is genuinely worth having, e.g.
    /// <c>W srv operator(): got exception: …</c>.
    /// </summary>
    public static bool ReadsLikeATrouble(string line)
    {
        var firstTwoFields = line
            .Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Take(2)
            .ToArray();
        if (firstTwoFields.Length == 2 && firstTwoFields[1] == "E")
        {
            return true;
        }

        var lowered = line.ToLowerInvariant();
        foreach (var word in new[] { "error", "exception", "failed", "failure" })
        {
            if (lowered.Contains(word))
            {
                return true;
            }
        }
        return false;
    }

    /// <summary>One line, cut to something a trail can hold.</summary>
    public static string Shortened(string line, int longest = 200)
    {
        if (line.Length <= longest)
        {
            return line;
        }
        return line.Substring(0, longest) + "…";
    }
}

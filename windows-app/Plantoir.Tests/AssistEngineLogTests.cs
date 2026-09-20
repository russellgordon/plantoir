using System.Collections.Generic;
using System.Linq;
using Plantoir.Core.Assist;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// Pins which of the local engine's own log lines reach the activity trail,
/// and how much of it a single conversation may spend. Ported from mac's
/// <c>AssistEngineLogTests.swift</c> — same filter, same cap, checked against
/// the same real-engine output.
/// </summary>
public class AssistEngineLogTests
{
    /// <summary>
    /// What llama.cpp prints when everything is fine, taken verbatim from a
    /// real run (build b10435, Qwen2.5-1.5B, 2026-08-20) — mirrors mac's
    /// fixture exactly, so the filter is checked against the same evidence
    /// on both platforms.
    /// </summary>
    private static readonly string[] HealthyStart =
    {
        "0.07.299.773 I cmn  common_param: common_params_print_info: verbosity = 3 (adjust with the `-lv N` CLI arg)",
        "0.07.300.122 W srv  llama_server: -----------------",
        "0.07.300.127 W srv  llama_server: CORS is set to allow all origins ('*') and no API key is set",
        "0.07.300.127 W srv  llama_server: this can be a security risk (cross-origin attacks)",
        "0.07.300.127 W srv  llama_server: more info: https://github.com/ggml-org/llama.cpp/pull/25655",
        "0.07.488.084 W load: control-looking token: 128247 '</s>' was not control-type; this is probably a bug in the model. its type will be overridden",
        "0.07.953.283 I cmn          init: llama threadpool init, n_threads = 4",
        "0.07.986.963 I srv    load_model: initializing, n_slots = 1, n_ctx_slot = 8192, kv_unified = 'false'",
        "0.07.990.066 I srv  llama_server: model loaded",
        "0.07.990.069 I srv  llama_server: listening on http://127.0.0.1:8791",
        "0.18.295.148 I slot print_timing: id  0 | task 0 | prompt eval time =      58.58 ms /    33 tokens",
        "0.18.295.176 I slot      release: id  0 | task 0 | stop processing: n_tokens = 34, truncated = 0",
    };

    [Fact]
    public void TheFilterKeepsTheTroubleAndDropsAHealthyStart()
    {
        var trouble = new[]
        {
            "0.46.018.667 E srv    send_error: task id = 3, error: request (20030 tokens) exceeds the available context size (8192 tokens), try increasing it",
            "0.45.886.270 W srv    operator(): got exception: {\"error\":{\"code\":500,\"message\":\"[json.exception.parse_error.101] parse error at line 1, column 10\"}}",
        };
        foreach (var line in trouble)
        {
            Assert.True(AssistEngineLog.ReadsLikeATrouble(line), $"This is exactly the line a report is for: {line}");
        }

        foreach (var line in HealthyStart)
        {
            Assert.False(AssistEngineLog.ReadsLikeATrouble(line), $"A healthy start must leave the trail alone: {line}");
        }
    }

    [Fact]
    public void ALongLineIsCutAndAShortOneIsNot()
    {
        const string @short = "0.07.990.066 I srv  llama_server: model loaded";
        Assert.Equal(@short, AssistEngineLog.Shortened(@short));

        var @long = new string('x', 500);
        var cut = AssistEngineLog.Shortened(@long);
        Assert.Equal(201, cut.Length);
        Assert.EndsWith("…", cut);
    }

    [Fact]
    public void AHealthyStartPutsNothingOnTheTrail()
    {
        var recorded = AssistEngineLog.LinesWorthRecording(HealthyStart, keepingEverything: false, alreadyRecorded: 0);
        Assert.Empty(recorded);
    }

    [Fact]
    public void AnEngineThatNeverStartedGivesUpItsWholeTail()
    {
        var recorded = AssistEngineLog.LinesWorthRecording(HealthyStart, keepingEverything: true, alreadyRecorded: 0);
        Assert.Equal(HealthyStart.Length, recorded.Count);
        Assert.Equal(HealthyStart.Last(), recorded.Last());
    }

    [Fact]
    public void TheCapHoldsAcrossSeparateLooks()
    {
        var trouble = Enumerable.Range(0, 40)
            .Select(i => $"0.46.0{i} E srv    send_error: task id = {i}, error: something went wrong")
            .ToList();

        var first = AssistEngineLog.LinesWorthRecording(trouble, keepingEverything: false, alreadyRecorded: 0);
        Assert.Equal(AssistEngineLog.MostEngineLinesOnTheTrail, first.Count);
        Assert.Equal(trouble.Last(), first.Last());

        var second = AssistEngineLog.LinesWorthRecording(
            trouble, keepingEverything: false, alreadyRecorded: AssistEngineLog.MostEngineLinesOnTheTrail);
        Assert.Empty(second);

        var partway = AssistEngineLog.LinesWorthRecording(
            trouble, keepingEverything: false, alreadyRecorded: AssistEngineLog.MostEngineLinesOnTheTrail - 3);
        Assert.Equal(3, partway.Count);
    }

    [Fact]
    public void OneTroubleLineAmongAHealthyStartIsWhatIsKept()
    {
        const string overflow = "0.46.018.667 E srv    send_error: task id = 3, error: request (20030 tokens) exceeds the available context size (8192 tokens), try increasing it";
        var mixed = new List<string>(HealthyStart)
        {
            overflow,
            "0.46.018.670 I slot      release: id  0 | task 3 | stop processing: n_tokens = 34, truncated = 0",
        };

        var recorded = AssistEngineLog.LinesWorthRecording(mixed, keepingEverything: false, alreadyRecorded: 0);
        Assert.Equal(new[] { overflow }, recorded);
    }
}

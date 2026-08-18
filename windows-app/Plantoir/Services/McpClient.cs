using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;

namespace Plantoir.Services;

/// <summary>
/// Speaks MCP to Plantoir's own server, over stdio, from inside the app.
///
/// The built-in assistant drives **the same `plantoir-mcp` that Claude Code
/// drives** rather than a second copy of the tool definitions. That matters
/// more than it saves: the tool descriptions are where the safety rules live —
/// publish and hide as separate verbs, plan before write, nothing destructive,
/// the course lock — and two copies of those would drift, quietly, in the
/// direction of whichever one somebody edited last.
///
/// It also means the built-in assistant inherits the lease protocol and the
/// course lock for free, and that a teacher gets the same answers whichever
/// assistant they use.
/// </summary>
public sealed class McpClient : Plantoir.Core.Assist.IToolServer, IAsyncDisposable
{
    private readonly Process _server;
    private readonly StreamWriter _to;
    private readonly StreamReader _from;
    private int _nextId = 1;

    private McpClient(Process server)
    {
        _server = server;
        _to = server.StandardInput;
        _from = server.StandardOutput;
    }

    /// <summary>
    /// Start the server for one course and complete the MCP handshake.
    /// Returns null when the server could not be started at all.
    /// </summary>
    public static async Task<McpClient?> Start(string serverPath, string workspacePath, string courseCode,
                                               CancellationToken cancellation = default)
    {
        var info = new ProcessStartInfo
        {
            FileName = serverPath,
            WorkingDirectory = workspacePath,
            CreateNoWindow = true,
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        foreach (string argument in new[] { "--folder", workspacePath, "--course", courseCode })
            info.ArgumentList.Add(argument);

        Process? server;
        try { server = Process.Start(info); }
        catch { return null; }
        if (server is null) return null;

        // stderr carries the server's own logging. Drained so a full pipe can
        // never block it mid-answer.
        server.ErrorDataReceived += (_, _) => { };
        server.BeginErrorReadLine();

        var client = new McpClient(server);
        try
        {
            await client.Call("initialize", new JsonObject
            {
                ["protocolVersion"] = "2025-06-18",
                ["capabilities"] = new JsonObject(),
                ["clientInfo"] = new JsonObject { ["name"] = "plantoir", ["version"] = "1.0" },
            }, cancellation);
            await client.Notify("notifications/initialized");
            return client;
        }
        catch
        {
            await client.DisposeAsync();
            return null;
        }
    }

    /// <summary>The tools the server offers, as the model needs to see them.</summary>
    public async Task<JsonArray> Tools(CancellationToken cancellation = default)
    {
        var result = await Call("tools/list", new JsonObject(), cancellation);
        var tools = new JsonArray();
        if (result?["tools"] is not JsonArray listed) return tools;

        foreach (var tool in listed)
        {
            if (tool is not JsonObject entry) continue;
            tools.Add(new JsonObject
            {
                ["type"] = "function",
                // The server's own annotations, carried through unchanged for
                // any client logic that wants them. The model never sees them:
                // llama.cpp parses tools into {name, description, parameters}
                // and drops the rest. (The approval gate read readOnlyHint
                // from here once; it gates only deploys now, by name.)
                ["annotations"] = entry["annotations"]?.DeepClone(),
                ["function"] = new JsonObject
                {
                    ["name"] = entry["name"]?.DeepClone(),
                    ["description"] = entry["description"]?.DeepClone(),
                    ["parameters"] = entry["inputSchema"]?.DeepClone(),
                },
            });
        }
        return tools;
    }

    /// <summary>
    /// Run a tool and return what it said, in its two halves.
    ///
    /// The server answers a refusal as ordinary text rather than an error, so
    /// the model reads the reason and can correct itself — the same behaviour
    /// Claude Code gets.
    ///
    /// The TEXT is the model's half, unchanged, which is why Claude Code is
    /// unaffected by any of this. The teacher's one-line half rides in the
    /// result's <c>_meta</c>; a tool that says the same thing to both sends
    /// none, and the fall-back below is what that absence means.
    /// </summary>
    public async Task<Plantoir.Core.Assist.AssistToolAnswer> CallTool(
        string name, JsonObject arguments,
        Action<string>? progress = null,
        CancellationToken cancellation = default)
    {
        JsonNode? result;
        try
        {
            result = await Call("tools/call",
                new JsonObject { ["name"] = name, ["arguments"] = arguments }, cancellation, progress);
        }
        catch (Exception error)
        {
            return Plantoir.Core.Assist.AssistToolAnswer.Same($"That tool couldn’t be run: {error.Message}");
        }

        if (result?["content"] is not JsonArray content)
            return Plantoir.Core.Assist.AssistToolAnswer.Same("");
        var text = new System.Text.StringBuilder();
        foreach (var block in content)
            if (block?["text"]?.GetValue<string>() is { } piece) text.AppendLine(piece);
        string detail = text.ToString().TrimEnd();

        var meta = result["_meta"];
        bool isPlan = meta?[Plantoir.Core.Assist.AssistToolAnswer.IsPlanKey]?.GetValue<bool>() == true;
        string? summary = meta?[Plantoir.Core.Assist.AssistToolAnswer.TeacherSummaryKey]?.GetValue<string>();

        return string.IsNullOrWhiteSpace(summary)
            ? Plantoir.Core.Assist.AssistToolAnswer.Same(detail) with { IsPlan = isPlan }
            : new Plantoir.Core.Assist.AssistToolAnswer(summary, detail, isPlan);
    }

    // ---- JSON-RPC --------------------------------------------------------

    private async Task<JsonNode?> Call(string method, JsonObject parameters, CancellationToken cancellation,
                                       Action<string>? onProgress = null)
    {
        int id = _nextId++;

        // The server only narrates when asked. Sending a progress token is the
        // asking; without one the SDK hands each tool a no-op IProgress and
        // every milestone line the toolchain writes is thrown away — which is
        // how a rebuild that recreates its container and re-installs the
        // toolchain came to look exactly like a hang, for minutes, in front of
        // a teacher who had just been told the assistant was working.
        if (onProgress is not null)
            parameters["_meta"] = new JsonObject { ["progressToken"] = id };

        var request = new JsonObject
        {
            ["jsonrpc"] = "2.0",
            ["id"] = id,
            ["method"] = method,
            ["params"] = parameters,
        };
        await _to.WriteLineAsync(request.ToJsonString());
        await _to.FlushAsync();

        // Notifications arrive on the same stream. Progress for THIS request
        // is passed along; everything else is skipped until the answer turns up.
        while (true)
        {
            string? line = await _from.ReadLineAsync(cancellation);
            if (line is null) throw new IOException("The Plantoir tools stopped responding.");
            if (line.Trim().Length == 0) continue;

            JsonNode? message;
            try { message = JsonNode.Parse(line); } catch { continue; }

            if (onProgress is not null &&
                message?["method"]?.GetValue<string>() == "notifications/progress" &&
                message["params"]?["progressToken"] is JsonValue token &&
                token.TryGetValue(out int tokenId) && tokenId == id &&
                message["params"]?["message"]?.GetValue<string>() is { Length: > 0 } note)
            {
                onProgress(note);
                continue;
            }

            if (message?["id"]?.GetValue<int>() != id) continue;

            if (message["error"] is { } failure)
                throw new IOException(failure["message"]?.GetValue<string>() ?? "The tool failed.");
            return message["result"];
        }
    }

    private async Task Notify(string method)
    {
        var message = new JsonObject
        {
            ["jsonrpc"] = "2.0",
            ["method"] = method,
            ["params"] = new JsonObject(),
        };
        await _to.WriteLineAsync(message.ToJsonString());
        await _to.FlushAsync();
    }

    /// <summary>Closing stdin is how an MCP server is asked to stop.</summary>
    public async ValueTask DisposeAsync()
    {
        try { _to.Close(); } catch { }
        try
        {
            if (!_server.WaitForExit(3000)) _server.Kill(entireProcessTree: true);
        }
        catch { }
        try { _server.Dispose(); } catch { }
        await Task.CompletedTask;
    }
}

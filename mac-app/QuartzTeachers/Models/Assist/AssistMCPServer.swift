import Foundation

/// Serves the assistant's tools over stdio as an MCP server, so Claude Code
/// drives exactly what the built-in assistant drives.
///
/// **One tool surface, two clients.** The safety rules — coarse tools,
/// publish and unpublish as separate verbs, nothing destructive — live in
/// `AssistToolSurface` and `AssistToolRunner`. Serving a SECOND surface here,
/// or reimplementing the tools for this client, would let the two drift; the
/// day they drift is the day one of them is missing a rule.
///
/// This client is offered MORE of that one surface, not a different one. The
/// local model's list is kept as short as the job allows, because a small model
/// routes worse the more it is shown; Claude Code is not that model, so it also
/// gets the
/// tools it alone is offered: three that ask for a judgement about meaning —
/// reading a course's curriculum
/// expectations and pointing a page at the ones that fit. Same definitions,
/// same runner, same rules; `runner.mcpDefinitions` is simply the longer list.
///
/// **Why this is inside the app rather than a separate binary.** The tools
/// are written against the app's own model layer, so a standalone executable
/// would need that layer extracted into a shared framework — a large refactor
/// whose only benefit is a second binary to sign, notarise and keep in step.
/// Instead the app answers a flag:
///
/// ```
/// /Applications/Plantoir.app/Contents/MacOS/Plantoir --mcp-stdio <working-folder>
/// ```
///
/// It ships with the app automatically, cannot be forgotten by a packaging
/// script the way Windows' `plantoir-mcp.exe` was, and is signed with the app
/// because it IS the app.
@MainActor
enum AssistMCPServer {

    // MARK: - Types

    /// The flag that turns the app into a server.
    static let flag: String = "--mcp-stdio"

    // MARK: - Functions

    /// The working folder given on the command line, when the flag is present.
    ///
    /// Returns nil for an ordinary launch, which is the overwhelmingly common
    /// case and must stay cheap: this runs before the first window.
    static func requestedWorkingFolder(from arguments: [String]) -> URL? {
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }
        let next: Int = arguments.index(after: index)
        guard next < arguments.count else {
            return nil
        }
        let path: String = arguments[next]
        if path.isEmpty || path.hasPrefix("-") {
            return nil
        }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    /// Read requests from stdin, write replies to stdout, until stdin closes.
    ///
    /// Never returns — MCP servers live until their client goes away, and the
    /// caller uses this to replace the app's ordinary startup.
    static func serve(workingFolder: URL) -> Never {
        let workspace: WorkspaceModel = WorkspaceModel()
        workspace.adoptRestoredPath(workingFolder.path)
        let runner: AssistToolRunner = AssistToolRunner(workspace: workspace)

        DispatchQueue.global(qos: .userInitiated).async {
            while let line = readLine(strippingNewline: true) {
                if line.isEmpty {
                    continue
                }
                guard let data = line.data(using: .utf8) else {
                    continue
                }
                Task { @MainActor in
                    guard let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        return
                    }
                    if let reply = await handle(request: request, runner: runner) {
                        write(reply)
                    }
                }
            }
            Task { @MainActor in
                exit(0)
            }
        }

        dispatchMain()
    }

    /// One request, answered. Returns nil for a notification, which by the
    /// JSON-RPC contract is not replied to at all.
    private static func handle(request: [String: Any], runner: AssistToolRunner) async -> [String: Any]? {
        let method: String = (request["method"] as? String) ?? ""
        let identifier: Any? = request["id"]

        // Notifications carry no id and take no answer. Replying to one is a
        // protocol error, not a harmless extra.
        if identifier == nil {
            return nil
        }

        switch method {
        case "initialize":
            return success(id: identifier, result: [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [:] as [String: Any]],
                "serverInfo": ["name": "plantoir", "version": "1.0"],
            ])

        case "tools/list":
            var tools: [[String: Any]] = []
            for definition in runner.mcpDefinitions {
                tools.append([
                    "name": definition.name,
                    "description": definition.description,
                    "inputSchema": definition.parametersJSON,
                    // The approval gate reads this rather than a list of its
                    // own, on both clients.
                    "annotations": [
                        "readOnlyHint": definition.readOnly,
                        "destructiveHint": false,
                    ],
                ])
            }
            return success(id: identifier, result: ["tools": tools])

        case "tools/call":
            let parameters: [String: Any] = (request["params"] as? [String: Any]) ?? [:]
            let name: String = (parameters["name"] as? String) ?? ""
            let arguments: [String: Any] = (parameters["arguments"] as? [String: Any]) ?? [:]
            guard runner.definition(named: name) != nil else {
                return failure(id: identifier, code: -32602, message: "There is no tool called \(name).")
            }

            let encoded: Data = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
            let call: AssistToolCall = AssistToolCall(
                id: UUID().uuidString,
                type: "function",
                function: AssistToolCall.Function(
                    name: name,
                    arguments: String(data: encoded, encoding: .utf8) ?? "{}"
                )
            )

            let outcome: AssistToolOutcome = await runner.run(call: call)
            return success(id: identifier, result: [
                "content": [["type": "text", "text": outcome.detail]],
            ])

        default:
            return failure(id: identifier, code: -32601, message: "Unknown method \(method).")
        }
    }

    // MARK: - JSON-RPC plumbing

    private static func success(id: Any?, result: [String: Any]) -> [String: Any] {
        var reply: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id {
            reply["id"] = id
        }
        return reply
    }

    private static func failure(id: Any?, code: Int, message: String) -> [String: Any] {
        var reply: [String: Any] = ["jsonrpc": "2.0", "error": ["code": code, "message": message]]
        if let id {
            reply["id"] = id
        }
        return reply
    }

    private static func write(_ reply: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: reply),
              var text = String(data: data, encoding: .utf8) else {
            return
        }
        text.append("\n")
        FileHandle.standardOutput.write(Data(text.utf8))
    }
}

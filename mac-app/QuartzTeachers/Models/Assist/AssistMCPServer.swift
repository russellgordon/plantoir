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

    /// True in the process `serve` is running in — so a trail line written
    /// by code the app and the server share can say which of the two wrote it.
    static var isServing: Bool = false

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
        isServing = true
        let workspace: WorkspaceModel = WorkspaceModel()
        workspace.adoptRestoredPath(workingFolder.path)
        let runner: AssistToolRunner = AssistToolRunner(workspace: workspace, surface: .mcp)

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
                await AssistMCPServer.stopOwnWorkBeforeLeaving()
                exit(0)
            }
        }

        dispatchMain()
    }

    /// The client has gone: stop what THIS process started, and only then
    /// take its leases down (#156).
    ///
    /// Leaving at once (`exit(0)` as soon as stdin closed, which is what this
    /// did) took the `build` lease down with the process while the launcher it
    /// had started carried on — a child on a pseudo-terminal is reparented
    /// rather than killed when its parent goes (measured for the quit path),
    /// so the build went on writing into the section's folder with nothing on
    /// disk saying so, and the window was then free to start a second one:
    /// the fault the lease exists to prevent.
    ///
    /// In order: no new launcher may start (a deploy's next leg would
    /// otherwise begin the moment its build is stopped); the leases stop
    /// following the records, so that the runs ending their own records as
    /// they are stopped cannot take the leases down early; every launcher
    /// this process has in flight is stopped and WAITED for — each resumes
    /// when its own process has actually exited, a real dependency rather
    /// than a guessed delay; then each section it was building is stopped
    /// inside the website builder as well (`PreviewStopper`, whose own wait
    /// is bounded); and only then are the leases removed.
    ///
    /// A client that KILLS the server rather than closing its input skips all
    /// of this. The lease is then left behind with a pid that is gone, which
    /// every reader ignores — but the reparented launcher may still be
    /// building. That is a known limit, shared with Windows' `plantoir-mcp`.
    static func stopOwnWorkBeforeLeaving(
        stopInsideTheBuilder: (_ courseCode: String, _ sectionNumber: Int, _ folder: URL) async -> Void
            = AssistMCPServer.stopSectionInsideTheBuilder
    ) async {
        var sections: [CourseActivity.PreviewBuildRecord] = []
        for build in CourseActivity.activePreviewBuilds {
            sections.append(build)
        }
        for publish in CourseActivity.activePublishes {
            let asBuild: CourseActivity.PreviewBuildRecord = CourseActivity.PreviewBuildRecord(
                folderPath: publish.folderPath,
                courseCode: publish.courseCode,
                sectionNumber: publish.sectionNumber
            )
            if !sections.contains(asBuild) {
                sections.append(asBuild)
            }
        }

        ScriptRunner.refusesNewRuns = true
        WorkLeaseRegistry.isLeaving = true

        var inFlight: [ScriptRunner] = []
        for runner in ScriptRunner.runsInFlight {
            inFlight.append(runner)
        }
        for runner in inFlight {
            runner.stopByUser()
        }
        for runner in inFlight {
            await runner.waitUntilFinished()
        }

        for section in sections {
            await stopInsideTheBuilder(
                section.courseCode, section.sectionNumber, URL(fileURLWithPath: section.folderPath)
            )
        }

        WorkLeaseRegistry.releaseEverything()
    }

    /// The real stop for one section inside the website builder.
    static func stopSectionInsideTheBuilder(_ courseCode: String, _ sectionNumber: Int, _ folder: URL) async {
        await PreviewStopper.stopSectionProcessesAndWait(
            courseCode: courseCode, sectionNumber: sectionNumber, workspaceURL: folder
        )
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
            var result: [String: Any] = [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [:] as [String: Any]],
                "serverInfo": ["name": "plantoir", "version": "1.0"],
            ]
            // Told BEFORE it can try, rather than refused after. MCP
            // 2024-11-05 carries an `instructions` field and clients surface
            // it as server guidance; it is MCP-only by construction, so it
            // costs the local model's thirteen-tool surface nothing.
            //
            // **Not the only channel**, deliberately: whether a given client
            // reads this could not be measured here, so `list_courses` and
            // the launcher greetings carry the same facts. If one of the
            // three is ignored, nothing is lost.
            if let instructions = AssistMCPServer.instructions(for: runner) {
                result["instructions"] = instructions
            }
            return success(id: identifier, result: result)

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

            // Straight to the runner, with no `settlingTheClassDay` first —
            // which is what the assistant WINDOW does before a plan and an act
            // share one arguments object. Here they are two requests with
            // nothing in between, so each resolves its own words against the
            // clock as it is asked. The runner reads that clock afresh, so a
            // server left open for days is not answering with the day it
            // started on.
            let outcome: AssistToolOutcome = await runner.run(call: call)
            return success(id: identifier, result: [
                "content": [["type": "text", "text": outcome.detail]],
            ])

        default:
            return failure(id: identifier, code: -32601, message: "Unknown method \(method).")
        }
    }

    /// What a session is told about this working folder before it does
    /// anything — or nil when there is nothing to say.
    ///
    /// Only reference courses are described. Everything else a session needs
    /// it can ask for, and a briefing that restates the obvious is one that
    /// gets skimmed.
    static func instructions(for runner: AssistToolRunner) -> String? {
        let described: [String] = runner.referenceCourseBriefingLines()
        if described.isEmpty {
            return nil
        }
        var lines: [String] = []
        lines.append(
            "Some courses in this folder are kept for reference: they are read-only sources, "
            + "and Plantoir never deploys them."
        )
        lines.append("")
        for line in described {
            lines.append(line)
        }
        lines.append("")
        lines.append(
            "Address one by the name on the left. Reading them works as it does anywhere else; "
            + "anything that would change or deploy one is refused."
        )
        return lines.joined(separator: "\n")
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

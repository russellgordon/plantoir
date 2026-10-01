import Foundation

/// One turn's worth of conversation, in the shape llama.cpp's OpenAI-compatible
/// endpoint expects.
struct AssistMessage: Codable, Equatable, Sendable {

    // MARK: - Stored properties

    let role: String
    let content: String?
    let toolCalls: [AssistToolCall]?
    let toolCallID: String?
    let name: String?

    // MARK: - Initializer

    init(role: String,
         content: String?,
         toolCalls: [AssistToolCall]? = nil,
         toolCallID: String? = nil,
         name: String? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
        case name
    }

    // MARK: - Functions

    static func system(_ text: String) -> AssistMessage {
        return AssistMessage(role: "system", content: text)
    }

    static func user(_ text: String) -> AssistMessage {
        return AssistMessage(role: "user", content: text)
    }

    static func toolResult(callID: String, name: String, text: String) -> AssistMessage {
        return AssistMessage(role: "tool", content: text, toolCallID: callID, name: name)
    }
}

/// A tool the model asked to run.
struct AssistToolCall: Codable, Equatable, Sendable, Identifiable {

    // MARK: - Types

    struct Function: Codable, Equatable, Sendable {
        let name: String
        /// JSON, as a string — that is how the endpoint sends it.
        let arguments: String
    }

    // MARK: - Stored properties

    let id: String
    let type: String
    let function: Function

    // MARK: - Computed properties

    /// The arguments, decoded. An empty dictionary when the model sent
    /// something that is not an object, which it occasionally does.
    var argumentValues: [String: Any] {
        guard let data = function.arguments.data(using: .utf8) else {
            return [:]
        }
        let parsed: Any? = try? JSONSerialization.jsonObject(with: data)
        return (parsed as? [String: Any]) ?? [:]
    }

    /// Whether the arguments are readable at all.
    ///
    /// `argumentValues` answers `[:]` for two different things — a tool that
    /// takes no arguments, and a generation that stopped in the middle of
    /// writing some — and every caller was treating them as the same. They
    /// are not: the first is an answer and the second is a fragment. An empty
    /// string and `{}` are readable, because `undo_last_change` genuinely
    /// takes nothing; a non-empty string that is not a JSON object is not.
    var argumentsAreReadable: Bool {
        let written: String = function.arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        if written.isEmpty {
            return true
        }
        guard let data = written.data(using: .utf8) else {
            return false
        }
        let parsed: Any? = try? JSONSerialization.jsonObject(with: data)
        return (parsed as? [String: Any]) != nil
    }

    /// Whether the model wrote NO arguments at all: nothing, whitespace, or an
    /// object with no keys in it. Not the same as unreadable — half-written
    /// JSON is a fragment, and this is an answer that says nothing.
    var wroteNoArguments: Bool {
        let written: String = function.arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        if written.isEmpty {
            return true
        }
        if !argumentsAreReadable {
            return false
        }
        return argumentValues.isEmpty
    }

    // MARK: - Functions

    /// The arguments a section window supplies itself, whatever the model
    /// wrote: the window binds its own course and section onto every call
    /// whose schema declares them (`AssistAgent.boundToThisSection`).
    static let argumentsTheWindowSupplies: [String] = ["course", "section"]

    /// Whether the arguments are readable FOR THIS TOOL — the gate a finished
    /// answer must pass before anything runs in a section window (issue #198).
    ///
    /// `argumentsAreReadable` answers yes for an empty string and for `{}`,
    /// deliberately, because `undo_last_change` takes nothing and llama.cpp
    /// sends `""` for it. But the same yes let a finished reply that named
    /// `publish_pages` and wrote nothing reach the tool, where — bound to the
    /// window's section, with no pages and no dates — it answered with a
    /// sentence reading as a complaint about the teacher's request, when the
    /// teacher had named pages and the model had dropped them.
    ///
    /// So a call that wrote nothing is readable only when the WINDOW can
    /// supply everything the tool needs — and it needs more than the window
    /// can supply when:
    /// - its schema REQUIRES an argument other than course and section (a
    ///   date, a page, a time), or
    /// - it CHANGES pages (`readOnly` false) and its schema declares any
    ///   argument other than course and section — which pages, which dates,
    ///   which unit. A write told only its section has nothing to act on.
    ///
    /// Everything else RUNS on an empty call, because the window supplies the
    /// rest: undo (no arguments at all), rebuild, deploy (still behind its
    /// button), check, add the next class, and a read like `list_pages` whose
    /// extra argument only narrows it. REJECTED on review: refusing every
    /// tool with a `required` list (`required` is exactly course and section
    /// for nine of the thirteen local tools, so it refused "rebuild the
    /// preview" when the model wrote nothing, although the window supplies
    /// everything that tool takes); and refusing every empty call (breaks
    /// undo, the tool a card reaches most).
    func argumentsAreReadable(
        forToolRequiring required: [String],
        declaring properties: [String],
        readOnly: Bool
    ) -> Bool {
        if !argumentsAreReadable {
            return false
        }
        if !wroteNoArguments {
            return true
        }
        return !AssistToolCall.needsMoreThanTheWindowSupplies(
            required: required, properties: properties, readOnly: readOnly
        )
    }

    /// Whether a tool needs an argument a section window cannot supply for it
    /// — see `argumentsAreReadable(forToolRequiring:declaring:readOnly:)`.
    static func needsMoreThanTheWindowSupplies(
        required: [String],
        properties: [String],
        readOnly: Bool
    ) -> Bool {
        for name in required where !argumentsTheWindowSupplies.contains(name) {
            return true
        }
        if readOnly {
            return false
        }
        for name in properties where !argumentsTheWindowSupplies.contains(name) {
            return true
        }
        return false
    }
}

/// Talks to the local `llama-server`.
///
/// Deliberately the OpenAI shape rather than anything bespoke: it is what
/// llama.cpp speaks, what the Windows suite measures against, and what a
/// teacher's own assistant would speak if they ever pointed one at the MCP
/// server instead.
struct AssistModelClient: Sendable {

    // MARK: - Stored properties

    let baseURL: URL

    /// The most the model may write in one reply.
    ///
    /// **Not a tuning knob — a bound on how long a teacher waits.** Without
    /// one, a reply is bounded only by the context. Measured on this Mac with
    /// the smaller assistant (M4 Pro, llama.cpp b10435 on Metal,
    /// Qwen2.5-1.5B Q4_K_M at a context of 8,192): the ordinary request
    /// "Publish tomorrow's class for VVH2O section 1, and make sure every page
    /// it links to is published rather than left as a draft" produced 5,435
    /// tokens of a page list that went on until the context was full, took
    /// **42 seconds**, three trials in three — and what arrived was unusable.
    /// 2,757 prompt + 5,435 written = 8,192 exactly, so the only thing
    /// bounding it was the context. On the larger assistant the same shape
    /// would run about 216 seconds at that tier's measured 63.2 tokens a
    /// second, past this client's own 180-second timeout, so it would fail
    /// rather than answer.
    ///
    /// **512, which is the number Windows already sends** (`LocalModel.Ask`),
    /// so the two apps cannot drift on a value neither interface shows. It is
    /// roomy: measured against this model's own tokenizer, an ordinary tool
    /// call is 16 to 60 tokens, twenty page titles is 203, twenty-four long
    /// real-world titles is 384, and fifty-eight short titles is 545. So the
    /// only legitimate shape it cuts is an explicit list of about fifty-five
    /// or more class pages — and `publish_pages` already takes `onOrAfter` and
    /// `before`, which asks for any number of classes in about sixty tokens.
    ///
    /// **The one shape that does NOT fit**, measured rather than assumed: the
    /// two-lap one, where `list_pages` hands back up to
    /// `AssistToolRunner.mostPagesListed` entries as relative PATHS and the
    /// next turn is asked to publish all of them. Sixty real paths are **975
    /// tokens**, so such a call crosses this cap at about the thirty-first
    /// (the twenty-sixth for a section's longest paths). Asked exactly that
    /// way, though, the smaller assistant answered `"pages": "all"` in 35
    /// tokens, three trials of three, and the cap never fired — one model, one
    /// phrasing, worth that much and no more. (Re-measured 2026-09-26 for
    /// #197: on six example payloads it wrote "all" in none of 108 cells, and
    /// ran every one to the cap instead; and `"pages": "all"`, which was
    /// answered "Nothing needed changing.", is refused in code since then —
    /// `AssistToolRunner.pagePlan`.) A teacher who does meet it is
    /// told `AssistWording.answerWasCutOff`, whose advice is followable in
    /// precisely this case. Sizing the cap to the worst imaginable call is a
    /// cap that never fires, which is what this issue was about.
    ///
    /// The rule is in `contracts/app-rules.json` → `modelTiers.requirements`
    /// so that neither app can move it alone.
    static let mostTokensPerReply: Int = 512

    // MARK: - Functions

    /// Ask the model for its next move.
    ///
    /// `temperature` is 0: this is a router, and a router that answers
    /// differently to the same request twice is a router a teacher cannot
    /// learn to trust.
    func respond(messages: [AssistMessage],
                 tools: [AssistToolDefinition]) async throws -> AssistMessage {
        return try await reply(messages: messages, tools: tools).message
    }

    /// The same request, with what the engine reported about the work it did.
    ///
    /// The completion-token count is here for one reason, and it is the
    /// reason the thinking flags shipped wrong for days: llama.cpp parses a
    /// `<think>` block OUT of the content before the app ever sees it, so an
    /// answer with thinking turned back on looks perfectly clean and is
    /// merely slow. The count is the honest check — 44 tokens with thinking
    /// off against 512 with it on, for the same question — and in a released
    /// app the problem report is the only place it can be seen.
    func reply(messages: [AssistMessage],
               tools: [AssistToolDefinition]) async throws -> AssistReply {
        let body: [String: Any] = try requestBody(messages: messages, tools: tools)

        var request: URLRequest = URLRequest(url: baseURL.appendingPathComponent("v1/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        // Generous: a cold prefix read on the large model is about twelve
        // seconds, and a slow disk can add to that on the very first call.
        request.timeoutInterval = 180

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code: Int = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AssistModelError.badResponse(status: code, body: String(data: data, encoding: .utf8) ?? "")
        }

        return try decodeReply(from: data)
    }

    // MARK: - Encoding

    /// Everything the server is asked for, in one place a test can read.
    ///
    /// Separated from `reply` for exactly the reason
    /// `AssistServerHost.serverArguments` is separated from `start()`: a field
    /// that only exists inside the function that makes the request cannot be
    /// checked without making one, and the cap is a field that must never
    /// quietly go missing.
    func requestBody(messages: [AssistMessage],
                     tools: [AssistToolDefinition]) throws -> [String: Any] {
        var body: [String: Any] = [
            "messages": try encodeMessages(messages),
            "temperature": 0,
            "stream": false,
            "max_tokens": AssistModelClient.mostTokensPerReply,
        ]
        if !tools.isEmpty {
            body["tools"] = try encodeTools(tools)
            body["tool_choice"] = "auto"
        }
        return body
    }

    private func encodeMessages(_ messages: [AssistMessage]) throws -> [[String: Any]] {
        var encoded: [[String: Any]] = []
        for message in messages {
            var item: [String: Any] = ["role": message.role]
            item["content"] = message.content ?? ""
            if let toolCallID = message.toolCallID {
                item["tool_call_id"] = toolCallID
            }
            if let name = message.name {
                item["name"] = name
            }
            if let calls = message.toolCalls {
                var encodedCalls: [[String: Any]] = []
                for call in calls {
                    encodedCalls.append([
                        "id": call.id,
                        "type": call.type,
                        "function": ["name": call.function.name, "arguments": call.function.arguments],
                    ])
                }
                item["tool_calls"] = encodedCalls
            }
            encoded.append(item)
        }
        return encoded
    }

    private func encodeTools(_ tools: [AssistToolDefinition]) throws -> [[String: Any]] {
        var encoded: [[String: Any]] = []
        for tool in tools {
            encoded.append([
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": tool.parametersJSON,
                ],
            ])
        }
        return encoded
    }

    // MARK: - Decoding

    private func decodeReply(from data: Data) throws -> AssistReply {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            throw AssistModelError.unreadableReply
        }

        // WHY the turn stopped, which is a different question from what it
        // said. "length" means the engine cut the model off part way: what it
        // was about to write next is unknowable, so nothing it had begun can
        // be acted on. See `AssistAgent.think`.
        let stoppedBecause: String = (first["finish_reason"] as? String) ?? ""

        let content: String? = message["content"] as? String
        var calls: [AssistToolCall] = []
        if let rawCalls = message["tool_calls"] as? [[String: Any]] {
            for raw in rawCalls {
                guard let function = raw["function"] as? [String: Any],
                      let name = function["name"] as? String else {
                    continue
                }
                // Some builds send arguments as an object rather than the
                // string the schema promises; both are accepted because a
                // dropped tool call reads to a teacher as the assistant
                // ignoring them.
                var arguments: String = ""
                if let text = function["arguments"] as? String {
                    arguments = text
                } else if let object = function["arguments"] {
                    if let encoded = try? JSONSerialization.data(withJSONObject: object),
                       let text = String(data: encoded, encoding: .utf8) {
                        arguments = text
                    }
                }
                let id: String = (raw["id"] as? String) ?? UUID().uuidString
                calls.append(AssistToolCall(
                    id: id,
                    type: "function",
                    function: AssistToolCall.Function(name: name, arguments: arguments)
                ))
            }
        }

        let usage: [String: Any]? = root["usage"] as? [String: Any]
        return AssistReply(
            message: AssistMessage(
                role: "assistant",
                content: content,
                toolCalls: calls.isEmpty ? nil : calls
            ),
            completionTokens: usage?["completion_tokens"] as? Int,
            wasCutOff: stoppedBecause == "length"
        )
    }
}

/// A reply, with what the engine said it cost to produce.
struct AssistReply: Sendable {

    // MARK: - Stored properties

    let message: AssistMessage

    /// How many tokens the model wrote, when the engine reported it.
    let completionTokens: Int?

    /// Whether the engine stopped the model part way rather than the model
    /// finishing what it was saying.
    ///
    /// Named for what happened rather than for the field it is read from:
    /// everything that reads this does one thing with it — refuse to act —
    /// and `finishReason == "length"` at a call site is a fact about a wire
    /// format in the middle of a sentence about a teacher's turn.
    /// No default, on purpose: there is one place a reply is built, and a
    /// reply built without saying whether it finished is the bug this whole
    /// piece exists to stop.
    let wasCutOff: Bool
}

/// What can go wrong talking to the engine.
enum AssistModelError: LocalizedError, Equatable {
    case badResponse(status: Int, body: String)
    case unreadableReply

    var errorDescription: String? {
        switch self {
        case .badResponse(let status, _):
            return "The assistant's engine answered with an error (\(status))."
        case .unreadableReply:
            return "The assistant's engine sent a reply Plantoir could not read."
        }
    }
}

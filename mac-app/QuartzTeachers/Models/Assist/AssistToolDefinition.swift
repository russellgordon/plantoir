import Foundation

/// One tool, as the model sees it.
///
/// The surface is deliberately COARSE. The finding the Windows work rests on,
/// and it held up under everything since: *the model is a router, not a
/// planner — every unit of reasoning moved out of the model and into ordinary
/// code is a unit of reliability bought back.* Given `resolve_links`,
/// `set_publish` and `publish_section` separately and asked to publish
/// tomorrow's class **and everything it links to**, the model chose
/// `publish_section` 8 times out of 8, skipping the link resolution — perfectly
/// consistent, and wrong. Given one `publish_class_on` that resolves links
/// itself, it was right 8 out of 8.
nonisolated struct AssistToolDefinition: Sendable, Equatable {

    // MARK: - Stored properties

    /// The name the model calls.
    let name: String

    /// What it does, in the shape the model routes best on.
    let description: String

    /// JSON Schema for the arguments.
    let parameters: [String: AssistSchemaProperty]

    /// Which arguments must be present.
    let required: [String]

    /// Whether running this changes anything.
    let readOnly: Bool

    /// Whether this waits for the teacher to press a button.
    ///
    /// Declared BY THE TOOL, not by a list the gate keeps somewhere else. A
    /// list is a second place to remember, and the day someone adds a tool
    /// and forgets the list is the day a write runs unapproved.
    ///
    /// Only deploying sets this. Publishing and unpublishing are backed up
    /// and `undo_last_change` takes them back, so they happen when asked — a
    /// gate in front of every write teaches a teacher to click through gates,
    /// which is worse than having no gate at all. Deploying is the one act
    /// that puts something in front of students immediately and that Plantoir
    /// cannot undo for them.
    let needsApproval: Bool

    // MARK: - Computed properties

    /// What this tool's `plan_` twin WOULD be called.
    ///
    /// The name only — whether such a tool exists is the surface's business,
    /// and the caller must check. Not every write has a twin: four of them
    /// are their own reversal and there is nothing to plan.
    ///
    /// - `rebuild_preview` changes no page at all.
    /// - `undo_last_change` IS the undo; asking a teacher to approve a plan
    ///   to undo something is a joke at their expense.
    /// - `deploy_section` waits on its own button already, always.
    /// - `cancel_scheduled_deploy` calls off an alarm, and re-setting it is
    ///   the whole remedy.
    ///
    /// One irregular pair: `schedule_deploy`'s twin reads
    /// `plan_scheduled_deploy` rather than `plan_schedule_deploy`, because
    /// the plan describes a scheduled deploy rather than the act of
    /// scheduling. The exception lives here so callers never encode it.
    var planTwinName: String? {
        if readOnly {
            return nil
        }
        if name == "schedule_deploy" {
            return "plan_scheduled_deploy"
        }
        return "plan_" + name
    }

    /// The parameters as a JSON Schema object.
    var parametersJSON: [String: Any] {
        var properties: [String: Any] = [:]
        for (key, property) in parameters {
            properties[key] = property.json
        }
        var schema: [String: Any] = [
            "type": "object",
            "properties": properties,
        ]
        if !required.isEmpty {
            schema["required"] = required
        }
        return schema
    }

    // MARK: - Functions

    /// The same tool with every mention of the placeholder course replaced by
    /// the real one.
    ///
    /// Measured on the Windows side and worth inheriting rather than
    /// rediscovering: with `for example ICS3U` left in the schema examples, a
    /// request that named no course copied `ICS3U` out of the examples **9
    /// times out of 9**. The model reads examples as suggestions.
    func namingTheRealCourse(_ course: String) -> AssistToolDefinition {
        var rewritten: [String: AssistSchemaProperty] = [:]
        for (key, property) in parameters {
            rewritten[key] = property.replacing(placeholder: "ICS3U", with: course)
        }
        return AssistToolDefinition(
            name: name,
            description: description.replacingOccurrences(of: "ICS3U", with: course),
            parameters: rewritten,
            required: required,
            readOnly: readOnly,
            needsApproval: needsApproval
        )
    }
}

/// One argument in a tool's schema.
nonisolated struct AssistSchemaProperty: Sendable, Equatable {

    // MARK: - Types

    enum Kind: Sendable, Equatable {
        case string
        case integer
        case boolean

        /// A string that carries a LIST, and the separator it is split on.
        ///
        /// Renders as `"type": "string"`, so the schema a client is sent is
        /// byte-identical to `.string`: this is NOT a routing change and owes
        /// no re-measurement. What it buys is that the generator can say WHICH
        /// string parameters are list-shaped from the DECLARATION rather than
        /// by matching English in their descriptions — and the descriptions
        /// are measured artifacts that must not be reworded casually, so a
        /// generator reading them would be a generator whose output depends on
        /// prose nobody may touch.
        case separatedList(separator: String)

        /// The `type` a client is sent.
        var jsonType: String {
            switch self {
            case .string, .separatedList:
                return "string"
            case .integer:
                return "integer"
            case .boolean:
                return "boolean"
            }
        }

        /// The separator, for a list-shaped string. `nil` for everything else.
        var listSeparator: String? {
            switch self {
            case .separatedList(let separator):
                return separator
            case .string, .integer, .boolean:
                return nil
            }
        }
    }

    // MARK: - Stored properties

    let kind: Kind
    let description: String

    // MARK: - Computed properties

    var json: [String: Any] {
        return ["type": kind.jsonType, "description": description]
    }

    // MARK: - Functions

    func replacing(placeholder: String, with replacement: String) -> AssistSchemaProperty {
        return AssistSchemaProperty(
            kind: kind,
            description: description.replacingOccurrences(of: placeholder, with: replacement)
        )
    }
}

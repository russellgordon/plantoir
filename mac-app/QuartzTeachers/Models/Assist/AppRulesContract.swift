import Foundation

/// `contracts/app-rules.json` — the rules BOTH apps must agree on that have
/// nothing to do with the assistant.
///
/// The assistant contract came first and answered the obvious question: what
/// does it say, and what must happen. This answers the less obvious one, and
/// the failures it prevents are quieter. Three kinds of rule are in here:
///
/// * **The milestones.** Both apps watch the SAME script output and turn it
///   into a progress bar, by matching a marker string. A marker that drifts on
///   one side does not crash it — the bar simply stops moving, or jumps, and
///   nothing in either app can tell. That is a shared-toolchain fact, and it
///   belongs in a file both sides read rather than in two lists nobody
///   compares.
/// * **The launcher arguments.** Given a course's configuration, what is
///   `deploy.sh` asked to do? This is the one that has already gone wrong: the
///   assistant path built its own arguments, never passed `--target
///   cloudflare`, and a Cloudflare course quietly deployed to Netlify. No
///   error anywhere — the site simply appeared on the wrong host.
/// * **The validation.** What a teacher is told about a Cloudflare Account ID,
///   a publishing folder, or a custom domain they typed with `https://` on the
///   front. Both apps ask the same questions and should give the same answers.
///
/// Generated and hand-written halves, split by top-level key exactly as in the
/// assistant contract: `milestones` is a readout of `TaskMilestones` and is
/// overwritten; `deployArguments`, `configurationRules` and `previewPorts` are
/// authored expectations and are preserved. The difference matters — a readout
/// cannot catch a regression in the thing it reads, so anything that must FAIL
/// when the code changes is written by hand.
@MainActor
enum AppRulesContract {

    // MARK: - Stored properties

    static let fileName: String = "app-rules.json"

    /// The top-level keys this writes. Everything else is authored.
    static let generatedKeys: [String] = ["credentialRequests", "milestones"]

    // MARK: - Functions

    /// The generated half, by top-level key.
    static func generated() -> [String: Any] {
        return [
            "credentialRequests": credentialRequests(),
            "milestones": milestones(),
        ]
    }

    /// Everything a teacher is shown when a launcher stops to ask for a
    /// Netlify or Cloudflare credential.
    ///
    /// A readout rather than an authored list, for the same reason the
    /// assistant's sentences are: this is the WORDING, and the point of
    /// carrying it in the contract is that the other app can show the same
    /// sentences instead of inventing its own. What must FAIL when the code
    /// changes is the recognition — which prompt produces which request —
    /// and that is authored, in `credentialPrompts`.
    private static func credentialRequests() -> [String: Any] {
        var written: [String: Any] = [
            "note": "What a teacher reads when a first publish stops to ask for a Netlify or Cloudflare "
                  + "credential. The launcher's own prompt is one line — \"Paste Netlify token:\" — which "
                  + "names something most teachers have never heard of and does not say where to get "
                  + "one, so both apps answer it with a dialog: what the credential is for, the steps "
                  + "that produce one, and the page to make it on as a LINK. The link is never opened "
                  + "for them; see credentialPrompts.whyNoBrowserOpens.",
        ]
        var requests: [[String: Any]] = []
        for request in CredentialRequest.all {
            requests.append([
                "name": request.name,
                "title": request.title,
                "explanation": request.explanation,
                "steps": request.steps,
                "linkTitle": request.linkTitle,
                "linkAddress": request.linkAddress?.absoluteString ?? "",
                "fieldLabel": request.fieldLabel,
                "isSecret": request.isSecret,
            ])
        }
        written["requests"] = requests
        return written
    }

    /// Every milestone list, as label and marker.
    ///
    /// The LABEL is what a teacher reads; the MARKER is the text in the
    /// script's output that means this step has been reached. The marker is
    /// the load-bearing half: it is matched against output produced by shared
    /// Python, so it is a fact about the toolchain rather than about either
    /// app, and both apps must match the same strings.
    private static func milestones() -> [String: Any] {
        // Read from TaskMilestones.allLists, never a copy of it. This was a
        // private array naming eight of the nine until 2026-09-08, so
        // `exampleCourse` reached no readout and the two shared-python markers
        // only it carries were classified by nobody.
        var written: [String: Any] = [
            "note": "label is what a teacher reads; marker is the text in the shared scripts' output that "
                  + "means the step has been reached. The marker is the load-bearing half — it is matched "
                  + "against output produced by shared Python, so both apps must match these strings "
                  + "exactly. A drifted marker does not crash anything: the progress bar simply stops "
                  + "moving, and neither app can tell.",
        ]
        for (name, list) in TaskMilestones.allLists {
            var steps: [[String: String]] = []
            for milestone in list {
                steps.append(["label": milestone.label, "marker": milestone.marker])
            }
            written[name] = steps
        }
        return written
    }

    /// Write the file, keeping every authored key exactly as it was.
    static func write(into directory: URL) -> String {
        let url: URL = directory.appendingPathComponent(fileName)
        var rules: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            rules = existing
        }
        for (key, value) in generated() {
            rules[key] = value
        }
        rules["generated"] = [
            "note": "Written by `Plantoir --write-contracts` from the app's own types and overwritten: "
                  + generatedKeys.joined(separator: ", ")
                  + ". The rest is hand-written expectation and is preserved.",
            "keys": generatedKeys,
        ]
        if rules["note"] == nil {
            rules["note"] = "What both apps must agree on outside the assistant. See contracts/README.md."
        }
        do {
            try AssistContract.encode(rules).write(to: url)
        } catch {
            return "Could not write the app rules: \(error.localizedDescription)"
        }
        return "Wrote \(url.path)"
    }
}

import AppKit
import SwiftUI

/// The deploy destination(s) — Netlify, Cloudflare Pages, or a folder on
/// this Mac — used by both Course Settings and the new-course wizard, so
/// the two offer exactly the same behaviour and wording.
///
/// One is always the PRIMARY (the picker at the top); a teacher may also
/// switch on any of the other known types as ADDITIONAL destinations, for
/// redundancy against one host having a bad day. Deploying sends your website to
/// every configured destination in one action — this view only decides
/// which destinations are configured, not how deploying uses them.
struct PublishingChoiceView: View {

    // MARK: - Stored properties

    @Binding var deployTarget: String
    @Binding var deployFolderPath: String

    /// The teacher's Cloudflare Account ID. It lives in app settings, not
    /// in this course's settings — it identifies the person, not the class
    /// — so it is entered once and every Cloudflare course uses it,
    /// whether Cloudflare is the primary destination or an additional one.
    /// SHOWN here, never edited: it is edited in Plantoir ▸ Settings ▸
    /// Deploying since the HIG sweep (#457), so changing it can no longer
    /// look like a change to this one course.
    let cloudflareAccountID: String

    /// Every OTHER destination this course also publishes to, beyond the
    /// primary above — see `CourseConfiguration.additionalDeployTargets`.
    @Binding var additionalDeployTargets: [CourseConfiguration.AdditionalDeployTarget]

    /// True in the new-course window only: there a missing Account ID is a
    /// warning rather than a refusal (#668), so the orange sentence gets
    /// `PublishingDestinations.accountIDCanWait` under it. Course Settings
    /// leaves it false, because saving a changed destination there still
    /// needs the ID (`SaveEnablement`).
    var accountIDMayWait: Bool = false

    // MARK: - Computed properties

    /// The additional destinations' types, in the order they were added.
    var additionalTypes: [String] {
        var result: [String] = []
        for target in additionalDeployTargets {
            result.append(target.type)
        }
        return result
    }

    /// Whether Netlify's note is shown (#668) — wherever Netlify is
    /// configured, primary or additional.
    var showsNetlifyNote: Bool {
        return PublishingDestinations.showsNetlifyNote(primary: deployTarget, additional: additionalTypes)
    }

    /// What is wrong with the chosen folder, or nil when nothing is.
    /// Checks the PRIMARY folder only — an additional folder target's
    /// problem is shown inline beside its own field instead.
    var folderProblem: String? {
        if deployTarget != "local_folder" {
            return nil
        }
        return CourseConfiguration.deployFolderProblem(forPath: deployFolderPath)
    }

    /// True when Cloudflare is configured as an ADDITIONAL destination.
    /// Never true at the same time as `deployTarget == "cloudflare_pages"`
    /// — the picker's own `onChange` below keeps the two from disagreeing.
    var hasAdditionalCloudflare: Bool {
        for target in additionalDeployTargets where target.type == "cloudflare_pages" {
            return true
        }
        return false
    }

    /// True when a local folder is configured as an ADDITIONAL destination.
    var hasAdditionalLocalFolder: Bool {
        for target in additionalDeployTargets where target.type == "local_folder" {
            return true
        }
        return false
    }

    /// What is wrong with the Cloudflare Account ID, or nil when nothing
    /// is. The same ID serves Cloudflare whether it is primary or
    /// additional — the two are mutually exclusive, so this applies to
    /// whichever one is actually configured.
    var accountProblem: String? {
        if deployTarget != "cloudflare_pages" && !hasAdditionalCloudflare {
            return nil
        }
        return CourseConfiguration.cloudflareAccountProblem(forID: cloudflareAccountID)
    }

    /// The other destination types this course could ALSO publish to —
    /// every known type except whichever one is currently primary.
    var availableAdditionalDeployTargetTypes: [String] {
        var result: [String] = []
        for type in CourseConfiguration.knownDeployTargetTypes where type != deployTarget {
            result.append(type)
        }
        return result
    }

    /// A live folder-path editor for the additional local-folder target.
    var additionalFolderPathBinding: Binding<String> {
        return Binding(
            get: {
                for target in additionalDeployTargets where target.type == "local_folder" {
                    return target.path
                }
                return ""
            },
            set: { newPath in
                var targets: [CourseConfiguration.AdditionalDeployTarget] = []
                for target in additionalDeployTargets {
                    if target.type == "local_folder" {
                        targets.append(CourseConfiguration.AdditionalDeployTarget(type: "local_folder", path: newPath))
                    } else {
                        targets.append(target)
                    }
                }
                additionalDeployTargets = targets
            }
        )
    }

    /// What is wrong with the additional local-folder target's path, or
    /// nil when nothing is (or it isn't configured).
    var additionalFolderProblem: String? {
        if !hasAdditionalLocalFolder {
            return nil
        }
        return CourseConfiguration.deployFolderProblem(forPath: additionalFolderPathBinding.wrappedValue)
    }

    /// Anything that must be put right before this course can be saved.
    var problem: String? {
        if let folderProblem {
            return folderProblem
        }
        if let accountProblem {
            return accountProblem
        }
        return additionalFolderProblem
    }

    // MARK: - Body

    var body: some View {
        Picker("Deploy to", selection: $deployTarget) {
            ForEach(CourseConfiguration.knownDeployTargetTypes, id: \.self) { type in
                Text(PublishingChoiceView.label(forDeployTargetType: type)).tag(type)
            }
        }
        .accessibilityIdentifier("deployTargetPicker")
        .onChange(of: deployTarget) { _, newValue in
            // Keeps the WIZARD's plain @State consistent live on screen —
            // it has no CourseConfiguration to route through until the
            // course is actually created, so this view enforces the same
            // rule `CourseConfiguration.deployTarget`'s setter enforces
            // for Course Settings, which binds straight to the model.
            additionalDeployTargets = CourseConfiguration.pruningAdditionalTargets(
                additionalDeployTargets, ofType: newValue
            )
        }

        if deployTarget == "cloudflare_pages" {
            CloudflareDetailFields(
                cloudflareAccountID: cloudflareAccountID,
                accountProblem: accountProblem,
                accountIDMayWait: accountIDMayWait
            )
        }

        // Netlify as the primary: the note sits under the picker. As an
        // additional destination it sits under that toggle instead.
        if deployTarget == "netlify" && showsNetlifyNote {
            NetlifyNote()
        }

        if deployTarget == "local_folder" {
            LocalFolderDetailFields(
                path: $deployFolderPath,
                problem: folderProblem,
                chooseIdentifier: "deployFolderChooseButton",
                fieldIdentifier: "deployFolderField",
                problemIdentifier: "deployFolderProblem"
            )
        }

        if !availableAdditionalDeployTargetTypes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Also deploy to, for redundancy")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ExampleCaption("Deploying sends your website to every destination switched on here, one after another. If one host is down or having trouble, the others still go out. Most teachers leave this off — it is here for anyone who wants a second copy live.")

                ForEach(availableAdditionalDeployTargetTypes, id: \.self) { type in
                    additionalTargetRow(forType: type)
                }
            }
        }
    }

    /// One row of the additional-targets list: its toggle, and — only
    /// while switched on — the same detail fields the primary destination
    /// would show for that type.
    @ViewBuilder
    func additionalTargetRow(forType type: String) -> some View {
        Toggle(
            PublishingChoiceView.label(forDeployTargetType: type),
            isOn: toggleBinding(forType: type)
        )
        .accessibilityIdentifier("additionalDeployTargetToggle-\(type)")

        if type == "cloudflare_pages" && hasAdditionalCloudflare {
            CloudflareDetailFields(
                cloudflareAccountID: cloudflareAccountID,
                accountProblem: accountProblem,
                accountIDMayWait: accountIDMayWait
            )
            .padding(.leading, 20)
        }

        if type == "netlify" && deployTarget != "netlify" && showsNetlifyNote {
            NetlifyNote()
                .padding(.leading, 20)
        }

        if type == "local_folder" && hasAdditionalLocalFolder {
            LocalFolderDetailFields(
                path: additionalFolderPathBinding,
                problem: additionalFolderProblem,
                chooseIdentifier: "additionalDeployFolderChooseButton",
                fieldIdentifier: "additionalDeployFolderField",
                problemIdentifier: "additionalDeployFolderProblem"
            )
            .padding(.leading, 20)
        }
    }

    // MARK: - Functions

    /// The label a teacher sees for a destination type — shared by the
    /// primary picker and the additional-targets list, so the two never
    /// describe the same destination in different words.
    static func label(forDeployTargetType type: String) -> String {
        switch type {
        case "netlify":
            return "Netlify"
        case "cloudflare_pages":
            return "Cloudflare Pages"
        case "local_folder":
            return "A folder on this Mac"
        default:
            return type
        }
    }

    /// A live on/off switch for one additional-target type, backed by the
    /// array binding above.
    func toggleBinding(forType type: String) -> Binding<Bool> {
        return Binding(
            get: {
                for target in additionalDeployTargets where target.type == type {
                    return true
                }
                return false
            },
            set: { isOn in
                var targets: [CourseConfiguration.AdditionalDeployTarget] = []
                for target in additionalDeployTargets where target.type != type {
                    targets.append(target)
                }
                if isOn {
                    targets.append(CourseConfiguration.AdditionalDeployTarget(type: type, path: ""))
                }
                additionalDeployTargets = targets
            }
        )
    }
}

/// The Cloudflare Account ID as this Mac has it, read-only, with Open
/// Settings… beside it; its validation message; and the fixed 25 MB caption
/// — shared between the primary destination's detail block and an
/// additional Cloudflare target's, which are never both on screen at once
/// (a type is either primary or additional, never both), and with the
/// new-course wizard.
///
/// **Read-only since the HIG sweep (#457, Russell 2026-10-08).** The field,
/// "Where do I find this?" and its instructions moved to Plantoir ▸ Settings
/// ▸ Deploying (`DeployingSettingsView`), because the ID is the teacher's,
/// not the course's: editing it here changed it for every course. With no
/// ID the sentence is the same as before
/// (`CourseConfiguration.cloudflareAccountProblem`, pinned in the contract),
/// beside the button that fixes it — but since #668 the new-course window no
/// longer refuses Create over a MISSING ID (Cloudflare is the default, and a
/// first-time teacher has none): it says `accountIDCanWait` under it, and the
/// first deploy refuses instead. `AppSettings` is observable, so a change
/// made in the Settings window shows here, and re-validates, at once.
private struct CloudflareDetailFields: View {

    // MARK: - Stored properties

    /// The fixed fact about this destination, shown whether or not
    /// anything is wrong.
    static let sizeNote: String =
        "One thing to know: Cloudflare won’t accept any single file larger than 25 MB. Documents, images, and slide decks are almost always comfortably under that — a long video usually isn’t. Most teachers embed video from YouTube or Vimeo rather than uploading it, which avoids the limit entirely."

    let cloudflareAccountID: String
    let accountProblem: String?

    /// See `PublishingChoiceView.accountIDMayWait`.
    let accountIDMayWait: Bool

    @Environment(\.openSettings) var openSettings

    // MARK: - Computed properties

    /// The ID, or "Not set yet" in its place.
    var shownID: String {
        let trimmed: String = cloudflareAccountID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Not set yet"
        }
        return trimmed
    }

    /// Whether the new-course window's "it can wait" sentence belongs under
    /// the ID's problem: only there, and only for a MISSING ID (#668).
    var saysTheIDCanWait: Bool {
        return accountProblem != nil && accountIDMayWait && PublishingDestinations.accountIDIsMissing(cloudflareAccountID)
    }

    /// ONE block of text (#668 review, L5 and L4): the ID's problem in
    /// orange, then — in the new-course window, for a missing ID — the
    /// sentence that says it can wait, in grey, right after the sentence it
    /// qualifies, and then the 25 MB fact in orange.
    var notice: Text {
        var built: Text = Text("")
        if let accountProblem {
            built = Text(accountProblem + " ").foregroundStyle(.orange)
            if saysTheIDCanWait {
                built = built + Text(PublishingDestinations.accountIDCanWait + " ").foregroundStyle(.secondary)
            }
        }
        return built + Text(CloudflareDetailFields.sizeNote).foregroundStyle(.orange)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Why it is offered first (#668), said plainly and without
            // figures.
            ExampleCaption(PublishingDestinations.cloudflareCaption)
                .accessibilityIdentifier("cloudflareCaption")
            // Said FIRST, where the row is read from: the value below is
            // shown, not edited, and this is where it is edited.
            Text("Kept in Plantoir ▸ Settings ▸ Deploying, for every course that deploys to Cloudflare Pages.")
                .font(.caption)
                .foregroundStyle(.secondary)
            // The value and its button together on the trailing side, the
            // way the unit word's row draws "Unit" beside Rename… — so "Not
            // set yet" sits where a value sits.
            LabeledContent("Cloudflare Account ID") {
                HStack {
                    Text(shownID)
                        .foregroundStyle(cloudflareAccountID.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("cloudflareAccountValue")
                    Button("Open Settings…") {
                        SettingsPane.select(.deploying)
                        openSettings()
                    }
                    .accessibilityIdentifier("cloudflareAccountOpenSettings")
                }
            }

            // What is wrong with the ID this Mac has, and the 25 MB fact,
            // in ONE block when both apply (#668 review, L5; `notice`): with
            // Cloudflare the default, a new teacher with no ID would
            // otherwise meet two orange warnings on their first course. Not
            // commentary: in Course Settings the ID's sentence is why a
            // changed destination will not save; in the new-course window a
            // MISSING ID is a warning and says so right after it, while one that
            // cannot be an ID still refuses Create
            // (`PublishingDestinations.wizardCreateRefusal`).
            //
            // The 25 MB sentence is not a warning that comes and goes: a
            // fact about this destination that never hides. It is the one
            // real functional difference between the destinations, so a
            // teacher should meet it while choosing rather than when a
            // deploy fails halfway through an upload.
            notice
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(accountProblem == nil ? "cloudflareSizeNote" : "cloudflareAccountProblem")
        }
    }
}

/// What a teacher is told about Netlify's free plan wherever Netlify is
/// chosen (#668): the allowance, that deploys use it up, and that running
/// out pauses every site on the account. No figures — the hosts change them.
private struct NetlifyNote: View {

    // MARK: - Body

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(PublishingDestinations.netlifyNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("netlifyNote")
    }
}

/// The folder path field, its Choose… button, and its own validation
/// message — shared between the primary destination's detail block and
/// an additional local-folder target's.
private struct LocalFolderDetailFields: View {

    // MARK: - Stored properties

    @Binding var path: String
    let problem: String?
    let chooseIdentifier: String
    let fieldIdentifier: String
    let problemIdentifier: String

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Folder", text: $path)
                    .borderedTextField()
                    .accessibilityIdentifier(fieldIdentifier)
                Button("Choose…") {
                    chooseDeployFolder()
                }
                .accessibilityIdentifier(chooseIdentifier)
            }
            if let problem {
                // The same orange every other inline warning wears.
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier(problemIdentifier)
            } else {
                ExampleCaption("Each section deploys into its own subfolder here — section1, section2 — and only changed files are copied. Upload the folder to your web host however you prefer (e.g. over SFTP). Netlify isn’t involved.")
            }
        }
    }

    // MARK: - Functions

    /// The standard folder chooser, writing straight into the setting.
    func chooseDeployFolder() {
        let panel: NSOpenPanel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose the folder this course's sections deploy into."
        if panel.runModal() == .OK, let chosen = panel.url {
            path = chosen.path
        }
    }
}

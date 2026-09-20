import AppKit
import SwiftUI

/// The deploy destination(s) — Netlify, Cloudflare Pages, or a folder on
/// this Mac — used by both Course Settings and the new-course wizard, so
/// the two offer exactly the same behaviour and wording.
///
/// One is always the PRIMARY (the picker at the top); a teacher may also
/// switch on any of the other known types as ADDITIONAL destinations, for
/// redundancy against one host having a bad day. Deploying publishes to
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
    @Binding var cloudflareAccountID: String

    /// Every OTHER destination this course also publishes to, beyond the
    /// primary above — see `CourseConfiguration.additionalDeployTargets`.
    @Binding var additionalDeployTargets: [CourseConfiguration.AdditionalDeployTarget]

    /// True while the "Where do I find this?" instructions are open.
    @State var isShowingAccountHelp: Bool = false

    // MARK: - Computed properties

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
                cloudflareAccountID: $cloudflareAccountID,
                isShowingAccountHelp: $isShowingAccountHelp,
                accountProblem: accountProblem
            )
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
                Text("Also publish to, for redundancy")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ExampleCaption("Deploying publishes to every destination switched on here, one after another. If one host is down or having trouble, the others still go out. Most teachers leave this off — it is here for anyone who wants a second copy live.")

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
                cloudflareAccountID: $cloudflareAccountID,
                isShowingAccountHelp: $isShowingAccountHelp,
                accountProblem: accountProblem
            )
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

/// The Cloudflare Account ID field, its help button, its own validation
/// message, and the fixed 25 MB caption — shared between the primary
/// destination's detail block and an additional Cloudflare target's,
/// which are never both on screen at once (a type is either primary or
/// additional, never both).
private struct CloudflareDetailFields: View {

    // MARK: - Stored properties

    @Binding var cloudflareAccountID: String
    @Binding var isShowingAccountHelp: Bool
    let accountProblem: String?

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Cloudflare Account ID", text: $cloudflareAccountID)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("cloudflareAccountField")

            // The grey caption that used to sit here repeated the
            // dashboard directions in four lines of small text under a
            // field that wants one code, whether or not anybody had a
            // question. It is a dialog now, on request. The Safari mark
            // matches the dialogs, so a link that leaves the app looks
            // the same everywhere.
            Button {
                showAccountHelp()
            } label: {
                Label("Where do I find this?", systemImage: "safari")
            }
            .buttonStyle(.link)
            .accessibilityIdentifier("cloudflareAccountHelpButton")

            // What is WRONG with what was typed. Not commentary: this
            // is why the course will not save.
            if let accountProblem {
                Text(accountProblem)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("cloudflareAccountProblem")
            }

            // Not a warning that comes and goes: a fact about this
            // destination that never hides. It is the one real
            // functional difference between the destinations, so a
            // teacher should meet it while choosing rather than when
            // a deploy fails halfway through an upload.
            Text("One thing to know: Cloudflare won’t accept any single file larger than 25 MB. Documents, images, and slide decks are almost always comfortably under that — a long video usually isn’t. Most teachers embed video from YouTube or Vimeo rather than uploading it, which avoids the limit entirely.")
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("cloudflareSizeNote")
        }
        // The same dialog the launcher shows when it has to ask for an
        // Account ID mid-publish, opened here on purpose instead. What
        // is typed into it lands in the field above, so a teacher who
        // has just fetched the code does not have to close this and
        // find the field again.
        .sheet(isPresented: $isShowingAccountHelp) {
            CredentialRequestSheet(
                request: CredentialRequest.cloudflareAccountIDHelp,
                initialAnswer: cloudflareAccountID,
                confirmTitle: "Use this ID",
                onSend: { typed in
                    cloudflareAccountID = typed
                    isShowingAccountHelp = false
                },
                onCancel: {
                    isShowingAccountHelp = false
                }
            )
        }
    }

    // MARK: - Functions

    /// Opens the instructions for finding an Account ID.
    ///
    /// Recorded on the trail: a teacher who had to go looking for this is
    /// the same teacher whose first publish is about to fail on it, and the
    /// line says which credential they were looking for. What they type is
    /// never recorded.
    func showAccountHelp() {
        ActivityTrail.note(.askedForACredential, "opened the instructions for finding a Cloudflare Account ID")
        isShowingAccountHelp = true
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
                    .textFieldStyle(.roundedBorder)
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

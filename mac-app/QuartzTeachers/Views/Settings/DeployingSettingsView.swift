import SwiftUI

/// Plantoir ▸ Settings ▸ Deploying: the Cloudflare Account ID, the one
/// deploying answer that belongs to the teacher rather than to a course
/// (#457 item 4, the HIG sweep — Russell, 2026-10-08: it moves to Settings).
///
/// **Why here.** The ID identifies the PERSON, not the class: one account
/// serves every course that deploys to Cloudflare Pages, and the value was
/// always stored app-wide (`AppSettings.cloudflareAccountID`). But it was
/// EDITED inside one course's settings, so changing it in one course
/// silently changed it for every other — a setting in the wrong place. A
/// course's Deploying section, and the new-course wizard, now show it
/// read-only with an Open Settings… button (`CloudflareDetailFields`).
///
/// No data moved: the stored key is the one it always was, so nothing was
/// migrated (the plan's "first non-empty course value wins" found no
/// per-course value to read on either platform).
struct DeployingSettingsView: View {

    // MARK: - Stored properties

    /// True while the "Where do I find this?" instructions are open.
    @State var isShowingAccountHelp: Bool = false

    /// The ID as it was when the pane last wrote its trail line, so leaving
    /// the pane writes one line for a change and nothing for a visit.
    @State var accountIDWhenNoted: String = ""

    // MARK: - Computed properties

    var body: some View {
        @Bindable var settings = AppSettings.shared
        Form {
            Section {
                LabeledContent("Cloudflare Account ID") {
                    TextField("", text: $settings.cloudflareAccountID, prompt: Text("32 letters and digits"))
                        .borderedTextField()
                        .accessibilityIdentifier("cloudflareAccountField")
                        .onSubmit {
                            noteTheChange()
                        }
                }
                Button {
                    showAccountHelp()
                } label: {
                    Label("Where do I find this?", systemImage: "safari")
                }
                .buttonStyle(.link)
                .accessibilityIdentifier("cloudflareAccountHelpButton")

                // What is wrong with what was typed. Nothing is said about
                // an EMPTY ID here: a teacher who never deploys to
                // Cloudflare has no reason to fill it in, and the course
                // that needs one says so itself.
                if let problem = DeployingSettingsView.problem(with: settings.cloudflareAccountID) {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("cloudflareAccountProblem")
                }
            } header: {
                Text("Cloudflare Pages")
            } footer: {
                Text("Every course that deploys to Cloudflare Pages uses this one account. Each course chooses where it deploys in its own settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isShowingAccountHelp) {
            CredentialRequestSheet(
                request: CredentialRequest.cloudflareAccountIDHelp,
                initialAnswer: settings.cloudflareAccountID,
                confirmTitle: "Use This ID",
                onSend: { typed in
                    settings.cloudflareAccountID = typed
                    isShowingAccountHelp = false
                    noteTheChange()
                },
                onCancel: {
                    isShowingAccountHelp = false
                }
            )
        }
        .onAppear {
            accountIDWhenNoted = AppSettings.shared.cloudflareAccountID
        }
        .onDisappear {
            noteTheChange()
        }
        // `.contain` BEFORE the identifier (#353): without it SwiftUI puts
        // the container's identifier on every element inside it.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deployingSettings")
    }

    // MARK: - Functions

    /// The problem with a typed ID, or nil — nil for an empty one, which is
    /// not wrong on this pane (see the body).
    static func problem(with accountID: String) -> String? {
        if accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        return CourseConfiguration.cloudflareAccountProblem(forID: accountID)
    }

    /// The trail line for a change made on this pane, or nil when nothing
    /// changed. NEVER the ID itself: only whether one is now set, cleared,
    /// or not yet a valid ID (`activityTrail.mustRecord` → "Cloudflare
    /// account ID changed in Settings").
    static func trailLine(before: String, after: String) -> String? {
        let was: String = before.trimmingCharacters(in: .whitespacesAndNewlines)
        let now: String = after.trimmingCharacters(in: .whitespacesAndNewlines)
        if was == now {
            return nil
        }
        if now.isEmpty {
            return "Settings ▸ Deploying — the Cloudflare Account ID was cleared"
        }
        if CourseConfiguration.cloudflareAccountProblem(forID: now) != nil {
            return "Settings ▸ Deploying — the Cloudflare Account ID was changed, and is not a valid ID yet"
        }
        return "Settings ▸ Deploying — the Cloudflare Account ID was changed"
    }

    /// Writes the trail line if the ID changed since the last one.
    func noteTheChange() {
        let now: String = AppSettings.shared.cloudflareAccountID
        if let line = DeployingSettingsView.trailLine(before: accountIDWhenNoted, after: now) {
            ActivityTrail.note(.cloudflareAccountIDChangedInSettings, line)
        }
        accountIDWhenNoted = now
    }

    /// Opens the instructions for finding an Account ID — recorded, as it
    /// was in a course's settings: a teacher who had to go looking is the
    /// teacher whose first deploy is about to need it. What they type is
    /// never recorded.
    func showAccountHelp() {
        ActivityTrail.note(.askedForACredential, "opened the instructions for finding a Cloudflare Account ID")
        isShowingAccountHelp = true
    }
}

/// Which pane Plantoir ▸ Settings shows, remembered, so a course's Open
/// Settings… button can ask for Deploying before the window opens.
enum SettingsPane: String {

    case assistant
    case deploying

    // MARK: - Stored properties

    static let storageKey: String = "settingsPane"

    // MARK: - Functions

    /// Asks the Settings window to show this pane the next time it is drawn
    /// — and at once, if it is already open (it reads the same key).
    static func select(_ pane: SettingsPane) {
        PlantoirDefaults.shared.set(pane.rawValue, forKey: SettingsPane.storageKey)
    }
}

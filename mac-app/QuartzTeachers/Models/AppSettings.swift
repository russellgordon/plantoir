import Foundation
import Observation

/// Settings that belong to the TEACHER rather than to any one course.
///
/// The Cloudflare Account ID is the first of these. It identifies the
/// person, not the class — a teacher deploying four courses to Cloudflare
/// has one account for all of them — so storing it in `course_config.json`
/// would ask the same question once per course and then leave four copies
/// to drift apart. That is the same reasoning that puts the API token in
/// the Keychain rather than in the course folder.
///
/// The store is injectable so that tests never write into the teacher's
/// real preferences, following `WorkspaceModel` and `WindowFolderMemory`.
@Observable
class AppSettings {

    // MARK: - Stored properties

    /// The app's own settings, used by every window.
    @MainActor static let shared: AppSettings = AppSettings()

    /// Where these are remembered. Injected so a test can never write into
    /// the real preferences.
    @ObservationIgnored private let defaults: UserDefaults

    /// The key holding the Cloudflare Account ID.
    static let cloudflareAccountIDKey: String = "cloudflareAccountID"

    /// The teacher's Cloudflare Account ID, entered once and used by every
    /// course that deploys to Cloudflare Pages. Empty until they give it.
    var cloudflareAccountID: String {
        didSet {
            if canRemember {
                defaults.set(cloudflareAccountID, forKey: AppSettings.cloudflareAccountIDKey)
            }
        }
    }

    /// The key holding which assistant the teacher has asked for.
    static let assistantModelChoiceKey: String = "assistantModelChoice"

    /// Which assistant this teacher has asked Plantoir to run.
    ///
    /// App-wide rather than per-course for the same reason as the Cloudflare
    /// Account ID: it describes the MACHINE and the person at it, not the
    /// class. One Mac has one amount of memory and one disk however many
    /// courses are on it, and four copies of this answer would be four
    /// answers to drift apart.
    ///
    /// Stored as the raw value so an unreadable or retired setting falls back
    /// to `automatic` rather than refusing to launch.
    var assistantModelChoice: AssistModelChoice {
        didSet {
            if canRemember {
                defaults.set(assistantModelChoice.rawValue, forKey: AppSettings.assistantModelChoiceKey)
            }
        }
    }

    /// The key holding whether the assistant asks before it changes anything.
    static let assistantAsksBeforeChangingKey: String = "assistantAsksBeforeChanging"

    /// The key this replaced, kept only to read an answer given before the
    /// setting existed. Inverted sense: it recorded being turned OFF.
    static let retiredPlanModeOffKey: String = "AssistPlanModeTurnedOff"

    /// Whether the assistant describes what it is about to do and waits for a
    /// button, before anything that changes the built website.
    ///
    /// **On by default, and that is the important half.** The local model is a
    /// router, and routers are wrong sometimes; plan mode turns a misroute
    /// from a thing that happens into a thing a teacher declines. Turning it
    /// off is an invitation, not a default — offered because a gate in front
    /// of every action teaches people to click through gates, and a teacher
    /// who has pressed Go on forty correct plans is not reading the
    /// forty-first.
    var assistantAsksBeforeChanging: Bool {
        didSet {
            if canRemember {
                defaults.set(
                    assistantAsksBeforeChanging,
                    forKey: AppSettings.assistantAsksBeforeChangingKey
                )
            }
        }
    }

    /// How many plans this teacher has said yes to, across every conversation
    /// and every course.
    static let plansAcceptedKey: String = "assistantPlansAccepted"

    /// Whether the assistant has already pointed at the setting.
    static let toldAboutTheSettingKey: String = "assistantToldAboutConfirmationSetting"

    /// Plans accepted, app-wide and for good.
    ///
    /// **App-wide, not per conversation.** The old count reset with every
    /// window, so a teacher who works in short bursts — the usual way of using
    /// this — could accept a hundred plans across twenty conversations and
    /// never be told the setting existed, because they never hit five in one
    /// sitting. What the number is evidence of is how much of the assistant's
    /// work this person has read and agreed with, and that does not reset
    /// because a window closed.
    var plansAccepted: Int {
        didSet {
            if canRemember {
                defaults.set(plansAccepted, forKey: AppSettings.plansAcceptedKey)
            }
        }
    }

    /// Whether the assistant has mentioned the setting. **Once, ever.**
    ///
    /// A suggestion declined is an answer. Asking again is how a helpful
    /// mention becomes nagging, and it is the same reasoning that stops the
    /// assistant offering to deploy: say the thing once, then let them get on.
    var hasBeenToldAboutTheSetting: Bool {
        didSet {
            if canRemember {
                defaults.set(hasBeenToldAboutTheSetting, forKey: AppSettings.toldAboutTheSettingKey)
            }
        }
    }

    // MARK: - Computed properties

    /// False while the hosted tests drive the real app, so a test run
    /// cannot leave a fixture value behind in the teacher's preferences.
    private var canRemember: Bool {
        if WorkspaceModel.isRunningTests && defaults === PlantoirDefaults.shared {
            return false
        }
        return true
    }

    // MARK: - Initializer

    init(defaults: UserDefaults = PlantoirDefaults.shared) {
        self.defaults = defaults
        self.cloudflareAccountID = defaults.string(forKey: AppSettings.cloudflareAccountIDKey) ?? ""
        let storedChoice: String = defaults.string(forKey: AppSettings.assistantModelChoiceKey) ?? ""
        self.assistantModelChoice = AssistModelChoice(rawValue: storedChoice) ?? .automatic

        self.plansAccepted = defaults.integer(forKey: AppSettings.plansAcceptedKey)
        self.hasBeenToldAboutTheSetting = defaults.bool(forKey: AppSettings.toldAboutTheSettingKey)

        // On unless the teacher has said otherwise — including through the
        // retired key, which recorded the same answer the other way round.
        if defaults.object(forKey: AppSettings.assistantAsksBeforeChangingKey) != nil {
            self.assistantAsksBeforeChanging = defaults.bool(
                forKey: AppSettings.assistantAsksBeforeChangingKey
            )
        } else {
            self.assistantAsksBeforeChanging = !defaults.bool(
                forKey: AppSettings.retiredPlanModeOffKey
            )
        }
    }
}

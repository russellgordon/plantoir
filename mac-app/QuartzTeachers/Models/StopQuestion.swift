import Foundation

/// The two questions asked before a running task is stopped (#988,
/// Russell's rulings of 2026-11-19): "Stop the deploy?" for a section's
/// deploy and "Stop this share?" for a share of unit plans. A preview stops
/// at once and has no question.
///
/// Each question has a "Don't ask again" box and its own setting, so
/// silencing one never silences the other (the #731 lesson: one box that
/// quietly turned off a different question). The box counts only when the
/// teacher goes on to stop; Cancel remembers nothing. The way back is
/// Plantoir ▸ Settings ▸ Deploying ▸ Stopping (`StopQuestionSettingsSection`).
///
/// Alerts, https://developer.apple.com/design/human-interface-guidelines/alerts:
/// "macOS alerts can add a suppression checkbox"; "Configure repeating
/// alerts to let people suppress subsequent occurrences of the same alert."
/// The design: `vm-tools/reference/988-stop-questions-design.md`.
enum StopQuestion {

    /// "Stop the deploy?", asked when a section's running deploy is stopped.
    case deploy

    /// "Stop this share?", asked when a running share of unit plans is stopped.
    case share

    /// Where a change to a question's setting was made, for its trail line.
    enum ChangedFrom {

        /// The question's own "Don't ask again" box, ticked with the stop.
        case dontAskAgain

        /// Plantoir ▸ Settings ▸ Deploying ▸ Stopping.
        case settings
    }

    // MARK: - Computed properties

    /// The question's title.
    var title: String {
        switch self {
        case .deploy:
            return DeployStopWording.title
        case .share:
            return ShareStopWording.title
        }
    }

    /// The question's informative text.
    var message: String {
        switch self {
        case .deploy:
            return DeployStopWording.message
        case .share:
            return ShareStopWording.message
        }
    }

    /// The button that stops the task: plain, the default, with Return.
    var stopButton: String {
        switch self {
        case .deploy:
            return DeployStopWording.stopButton
        case .share:
            return ShareStopWording.stopButton
        }
    }

    /// The button that backs out, with Escape and Command-Period.
    var cancelButton: String {
        switch self {
        case .deploy:
            return DeployStopWording.cancelButton
        case .share:
            return ShareStopWording.cancelButton
        }
    }

    /// The stopping button's accessibility identifier.
    var stopButtonIdentifier: String {
        switch self {
        case .deploy:
            return "stopDeployButton"
        case .share:
            return "stopShareButton"
        }
    }

    /// The Cancel button's accessibility identifier.
    var cancelButtonIdentifier: String {
        switch self {
        case .deploy:
            return "cancelStopDeployButton"
        case .share:
            return "cancelStopShareButton"
        }
    }

    /// The label of this question's row in Settings ▸ Deploying.
    var settingLabel: String {
        switch self {
        case .deploy:
            return StopQuestionSettingsWording.asksBeforeStoppingADeploy
        case .share:
            return StopQuestionSettingsWording.asksBeforeStoppingAShare
        }
    }

    /// The Settings row's accessibility identifier.
    var settingIdentifier: String {
        switch self {
        case .deploy:
            return "asksBeforeStoppingADeployToggle"
        case .share:
            return "asksBeforeStoppingAShareToggle"
        }
    }

    // MARK: - Functions

    /// Whether this question is asked before the task stops.
    func isAsked(in settings: AppSettings) -> Bool {
        switch self {
        case .deploy:
            return settings.asksBeforeStoppingADeploy
        case .share:
            return settings.asksBeforeStoppingAShare
        }
    }

    /// Turns this question on or off, and writes one trail line when that
    /// changes anything. The Settings row and the question's box are the
    /// same setting.
    func setAsked(_ asked: Bool, in settings: AppSettings, from place: ChangedFrom) {
        if isAsked(in: settings) == asked {
            return
        }
        switch self {
        case .deploy:
            settings.asksBeforeStoppingADeploy = asked
        case .share:
            settings.asksBeforeStoppingAShare = asked
        }
        ActivityTrail.note(.stopQuestionSettingChanged, StopQuestion.trailLine(for: self, asked: asked, from: place))
    }

    /// The teacher chose the stopping button. A ticked "Don't ask again"
    /// turns this question off; an unticked one changes nothing. Cancel
    /// never calls this, so backing out remembers nothing (ruling 3).
    func stopWasChosen(dontAskAgainTicked: Bool, in settings: AppSettings) {
        if dontAskAgainTicked {
            setAsked(false, in: settings, from: .dontAskAgain)
        }
    }

    /// The trail line for a change to one question's setting
    /// (`activityTrail.mustRecord` → "stop question setting changed").
    static func trailLine(for question: StopQuestion, asked: Bool, from place: ChangedFrom) -> String {
        let onOrOff: String = asked ? "on" : "off"
        switch place {
        case .settings:
            return "Settings ▸ Deploying — " + question.settingLabel + " " + onOrOff
        case .dontAskAgain:
            return question.settingLabel + " " + onOrOff + ", from Don't ask again in “" + question.title + "”"
        }
    }
}

/// What a teacher reads when stopping a running share of unit plans (#988,
/// Russell's rulings of 2026-11-19). Mac only for now, as the deploy's is.
nonisolated enum ShareStopWording {

    // MARK: - Stored properties

    /// The question's title. Not "Stop Sharing", which already names taking
    /// shared plans down in the Planning tab.
    static let title: String = "Stop this share?"

    /// True today: a stopped share may leave part of an upload. Becomes "The
    /// unit plans stay as they were before this share began." when #992's
    /// all-or-nothing share lands (ruling 1; a comment on #992 says so).
    static let message: String = "The unit plans may be left partly shared until you share them again."

    /// Stops the share: the default button, with Return.
    static let stopButton: String = "Stop Share"

    /// Backs out and lets the share go on, with Escape and Command-Period.
    static let cancelButton: String = "Cancel"
}

/// The box on both questions and the Stopping section of Settings ▸
/// Deploying (#988, rulings 2 to 4).
nonisolated enum StopQuestionSettingsWording {

    // MARK: - Stored properties

    /// The box on each question: the app's one existing box says exactly
    /// this (#495), and it is AppKit's own default in contracted form.
    static let dontAskAgain: String = "Don't ask again"

    /// The section's header in Settings ▸ Deploying.
    static let sectionHeader: String = "Stopping"

    /// The deploy question's row.
    static let asksBeforeStoppingADeploy: String = "Ask before stopping a deploy"

    /// The share question's row.
    static let asksBeforeStoppingAShare: String = "Ask before stopping a share of unit plans"

    /// The section's footer.
    static let footer: String = "When one is off, Cancel stops that task at once, and so do the Escape key and Command-Period."
}

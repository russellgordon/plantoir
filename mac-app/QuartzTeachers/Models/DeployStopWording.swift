import Foundation

/// What a teacher reads when stopping a running deploy (#988, Russell's
/// rulings of 2026-11-19): a preview stops at once, a deploy asks first,
/// whether Cancel was clicked or Escape or Command-Period pressed. Stop
/// Deploy is plain and the default; the other button is Cancel.
///
/// Alerts, https://developer.apple.com/design/human-interface-guidelines/alerts:
/// a title that is a complete sentence takes sentence case and its ending
/// punctuation; informative text only "if it adds value", in complete
/// sentences; button titles of one or two words that describe the result,
/// in title case. Mac only for now: the Windows app is brought to match in
/// stage 3 of the HIG review (#979).
nonisolated enum DeployStopWording {

    // MARK: - Stored properties

    /// The question's title.
    static let title: String = "Stop the deploy?"

    /// Why it asks: what stopping part way can do.
    static let message: String = "The website may be left partly updated until you deploy again."

    /// Stops the deploy: the default button, with Return.
    static let stopButton: String = "Stop Deploy"

    /// Backs out and lets the deploy go on, with Escape and Command-Period.
    /// Alerts: "Always use 'Cancel' to title a button that cancels the
    /// alert's action."
    static let cancelButton: String = "Cancel"
}

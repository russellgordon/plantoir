import Foundation

/// The one reload a preview gets when it was shown before its build landed
/// (#998).
///
/// The preview's wait gives the build two minutes to write the site, then
/// shows whatever the server is serving, which may be the build before. It
/// used to reload 900 milliseconds later, a guess: a build still landing at
/// that moment was missed, and the teacher kept the old page until they
/// pressed Reload. This waits for what the reload is for instead: the
/// section's built front page changing from what it was before the run
/// (`SectionDetailView.builtIndexWrittenAt`, the same reading phase 2 of the
/// wait uses). The page is reloaded once, when that happens, and not at all
/// if the run ends, is stopped or is replaced first.
///
/// The file is written by the builder, which runs outside the app and says
/// nothing when it has written it, so it is read again at each `pause`:
/// a paced reading of something that cannot announce itself, never a wait
/// for something to settle.
enum PreviewLateBuild {

    // MARK: - Functions

    /// True once the build has landed (reload now); false when the run
    /// stopped being the one this was about, or `limit` passed, first.
    ///
    /// - Parameters:
    ///   - siteAsItWas: when the built front page was written before the run
    ///     started, or nil when it had never been built.
    ///   - whenWritten: reads when it was last written, now.
    ///   - theRunIsStillTheOne: whether the run the page was shown for is
    ///     still going and still the window's run.
    ///   - limit: how long the reading may go on.
    ///   - now: the clock, so a test can run it without waiting.
    ///   - pause: what to do between readings.
    static func waitForTheBuildToLand(
        siteAsItWas: Date?,
        whenWritten: () -> Date?,
        theRunIsStillTheOne: () -> Bool,
        limit: TimeInterval,
        now: () -> Date = { Date() },
        pause: () async -> Void
    ) async -> Bool {
        let began: Date = now()
        while true {
            if !theRunIsStillTheOne() || Task.isCancelled {
                return false
            }
            if let written = whenWritten(), written != siteAsItWas {
                return true
            }
            if now().timeIntervalSince(began) >= limit {
                return false
            }
            await pause()
        }
    }
}

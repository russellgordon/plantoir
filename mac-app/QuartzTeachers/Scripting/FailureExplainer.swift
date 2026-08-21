import Foundation

/// Turns a failed task's raw output into a sentence a teacher can act on.
///
/// The output of a failure is written for whoever wrote the tools: API
/// error codes, hostnames, stack traces. This reads it and, where it
/// recognises the trouble, says what happened and what to do about it.
/// When it recognises nothing it says nothing, and the app shows the
/// full output instead — an honest fallback beats a confident guess.
struct FailureExplainer {

    // MARK: - Functions

    /// A plain-language reason for the failure, or nil when the output
    /// shows nothing recognisable.
    static func explanation(in output: String) -> String? {
        if let reason = vaultLinkExplanation(in: output) {
            return reason
        }
        if let reason = rateLimitExplanation(in: output) {
            return reason
        }
        if let reason = accountExplanation(in: output) {
            return reason
        }
        if let reason = connectionExplanation(in: output) {
            return reason
        }
        if let reason = missingBuildExplanation(in: output) {
            return reason
        }
        return nil
    }

    /// A link (junction or symlink) inside the TEACHER's own course folder
    /// that Windows refuses to traverse.
    ///
    /// This output can never appear on macOS — it is a Windows error, from a
    /// Windows filesystem — and the mapping is here anyway so that the two
    /// apps' explainers stay the same list of troubles rather than growing a
    /// platform switch for a handful of lines. See the contract's note on the
    /// case; the alternative, a `platform` field on every case, was rejected.
    ///
    /// The trouble itself is the teacher's to fix: the toolchain creates no
    /// links of its own on Windows any more, so a link inside a course folder
    /// is one they made — commonly the Obsidian trick of sharing a single
    /// Media folder across several vaults. Left unexplained, the raw OSError
    /// reads as Plantoir crashing.
    static func vaultLinkExplanation(in output: String) -> String? {
        if output.contains("untrusted mount point") {
            return "Part of this course folder is a link to another folder, and Windows won't let "
                 + "the website builder follow it. Replace the link with the real folder (the "
                 + "details above name which one), then try again."
        }
        return nil
    }

    /// Netlify limits how often sites can be created and deployed.
    static func rateLimitExplanation(in output: String) -> String? {
        let mentionsLimit: Bool = output.contains("429") || output.lowercased().contains("rate limit")
        if !mentionsLimit {
            return nil
        }
        let wait: String = waitDescription(in: output)
        return "Netlify is limiting how often websites can be deployed right now. Try deploying again \(wait)."
    }

    /// "Window resets at: … (in ~59s)." tells us how long the wait is.
    static func waitDescription(in output: String) -> String {
        guard let seconds = secondsUntilReset(in: output) else {
            return "in a few minutes"
        }
        if seconds <= 90 {
            return "in about a minute"
        }
        var minutes: Int = seconds / 60
        if seconds % 60 > 0 {
            minutes += 1
        }
        return "in about \(minutes) minutes"
    }

    /// Reads the seconds out of "(in ~59s)".
    static func secondsUntilReset(in output: String) -> Int? {
        let marker: String = "(in ~"
        guard let markerRange = output.range(of: marker) else {
            return nil
        }
        var digits: String = ""
        for character in output[markerRange.upperBound...] {
            if character.isNumber {
                digits.append(character)
            } else {
                break
            }
        }
        return Int(digits)
    }

    /// The Netlify account is not connected, or no longer accepted.
    static func accountExplanation(in output: String) -> String? {
        if output.contains("Netlify token missing") {
            return "Your Netlify account isn't connected yet. Add your Netlify access token, then deploy again."
        }
        let wasRefused: Bool = output.contains("Netlify API error 401") || output.contains("Netlify API error 403")
        if wasRefused {
            return "Netlify didn't accept your access token — it may have expired or been removed. Create a new one on Netlify, then deploy again."
        }
        return nil
    }

    /// The computer could not reach the internet.
    static func connectionExplanation(in output: String) -> String? {
        let signs: [String] = [
            "Could not resolve host",
            "nodename nor servname",
            "Temporary failure in name resolution",
            "Network is unreachable",
            "The Internet connection appears to be offline"
        ]
        for sign in signs {
            if output.contains(sign) {
                return "Your computer couldn't reach the internet. Check your connection, then try again."
            }
        }
        return nil
    }

    /// Publishing was asked for before anything had been built.
    static func missingBuildExplanation(in output: String) -> String? {
        if output.contains("Built site not found") {
            return "This website hasn't been built yet. Preview it once, then deploy."
        }
        return nil
    }
}

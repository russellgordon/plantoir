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
        if let reason = keptForReferenceExplanation(in: output) {
            return reason
        }
        if let reason = sectionIsBeingDeployedExplanation(in: output) {
            return reason
        }
        if let refusal = sectionDeployRefusal(in: output) {
            return refusal.sentence
        }
        if let reason = vaultLinkExplanation(in: output) {
            return reason
        }
        if let reason = folderCopyDidNotFinishExplanation(in: output) {
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
        if let reason = unreadableFrontPageExplanation(in: output) {
            return reason
        }
        if let reason = missingFrontPageExplanation(in: output) {
            return reason
        }
        if let reason = missingBuildExplanation(in: output) {
            return reason
        }
        if let reason = workspaceCouldNotBeMadeExplanation(in: output) {
            return reason
        }
        return nil
    }

    /// What a teacher reads when a publish to a folder could not copy every
    /// page. Contract data: `app-rules.json` → `failureExplanations`.
    ///
    /// It names no single cause on purpose: the same "finished in part" comes
    /// from a folder that will not take a file AND from a page on this side
    /// that cannot be read (measured in review: one unreadable page, 312 of
    /// 313 copied), so blaming the folder would be a confident wrong guess.
    static let folderCopyDidNotFinish: String =
        "Plantoir could not copy every page into your publishing folder, so it is not up to date. "
        + "Try publishing again; if the same thing happens, one of your pages may not open "
        + "or the folder may not be taking new files."

    /// A publish to a folder stopped part way (GitHub issue #227).
    ///
    /// `deploy.sh` now reads the copy's own exit status instead of throwing
    /// it away, and fails — rather than saying "Published" — when the copy
    /// did not finish, INCLUDING when it finished in part: a page left behind
    /// may be one the teacher took down. Its line names the copy's error
    /// number, which means nothing to a teacher, so the line is matched here
    /// and replaced with a sentence they can act on.
    ///
    /// Asked before the connection check on purpose: the copy's own error
    /// lines can carry words that check matches, and this output is about a
    /// folder on this Mac, not the internet.
    static func folderCopyDidNotFinishExplanation(in output: String) -> String? {
        if output.contains("could be copied into the publishing folder") {
            return folderCopyDidNotFinish
        }
        return nil
    }

    /// The words `preview.sh` refuses a preview with while that same section
    /// is being deployed (GitHub #381) — `shared-rules.json` →
    /// `previewWhileItsSectionDeploys.sentences.launcher`, whose first line
    /// always carries them.
    static let sectionIsBeingDeployedMarker: String = "is being deployed right now, so it cannot be previewed"

    /// preview.sh refused because a deploy of the same section was running —
    /// one typed at a command line, or a deploy set for later, which the
    /// window's own check cannot see. LIFTED, as the kept-for-reference
    /// refusal is: the launcher's line already is the sentence a teacher can
    /// act on, and a second wording of one refusal is how one rule comes to
    /// be said two ways. Pinned by `failureExplanationCases` in the contract.
    static func sectionIsBeingDeployedExplanation(in output: String) -> String? {
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.contains(sectionIsBeingDeployedMarker) else {
                continue
            }
            var sentence: String = String(line).trimmingCharacters(in: .whitespaces)
            while let first = sentence.first, first == "❌" || first == " " {
                sentence.removeFirst()
            }
            return sentence.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// What `deploy.sh`, or `preview.sh --build-only`, refused with while
    /// the same section was still being deployed (GitHub #439) —
    /// `shared-rules.json` → `deployWhileItsSectionDeploys`.
    struct SectionDeployRefusal: Equatable {

        // MARK: - Stored properties

        /// True when what was in the way is a deploy that was set for later
        /// (its run's script still working, including a run ended by setting
        /// the section again); false when it was another `deploy.sh` for the
        /// section, such as one typed in Terminal.
        let byALaterDeploy: Bool

        /// The launcher's first line with the cross taken off: the sentence
        /// the window shows.
        let sentence: String
    }

    /// The words the launchers' #439 refusal always carries, one pair per
    /// leg. `sentences.launcher` in the contract is the source; the test
    /// pins these to it.
    static let sectionDeployRefusalMarkers: [String] = [
        "so it cannot be deployed again until that has finished.",
        "so it cannot be built until that has finished."
    ]

    /// The part of the first line that says the deploy set for later was
    /// the reason, rather than another deploy of the section.
    static let laterDeployMarker: String = "is still being deployed by a deploy that was set for later"

    /// The launcher refused a deploy, or its build leg, because that same
    /// section was still being deployed. LIFTED, as #381's refusal is: the
    /// launcher's line already is the sentence a teacher can act on.
    /// Pinned by `deployWhileItsSectionDeploys.failureExplanationCases`.
    static func sectionDeployRefusal(in output: String) -> SectionDeployRefusal? {
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            var carriesAMarker: Bool = false
            for marker in sectionDeployRefusalMarkers {
                if line.contains(marker) {
                    carriesAMarker = true
                }
            }
            if !carriesAMarker {
                continue
            }
            var sentence: String = String(line).trimmingCharacters(in: .whitespaces)
            while let first = sentence.first, first == "❌" || first == " " {
                sentence.removeFirst()
            }
            sentence = sentence.trimmingCharacters(in: .whitespaces)
            return SectionDeployRefusal(
                byALaterDeploy: sentence.contains(laterDeployMarker),
                sentence: sentence
            )
        }
        return nil
    }

    /// The launcher refused because the course is kept for reference.
    ///
    /// **Asked FIRST, and it exists for one caller in particular.** A deploy
    /// the teacher set to happen on its own runs with the app closed; when it
    /// fails, the app shows `ScheduledPublishOutcome`'s generic "did not
    /// finish", and the real reason stays in a log nobody opens. This is what
    /// lifts the refusal out of that log and into the sentence they read.
    ///
    /// The launcher's output already IS a sentence a teacher can act on —
    /// that is what makes a new exit code unnecessary. So this lifts the line
    /// out rather than writing a second explanation of the same rule, which is
    /// how one rule ends up said two ways.
    static func keptForReferenceExplanation(in output: String) -> String? {
        // The launcher's OTHER reference refusal, which is TWO printed lines
        // — the headline and the reason — and reaches the teacher joined.
        //
        // It matters for exactly the population the one below does, and more
        // so: the app reads a course with an odd marker value as ORDINARY, so
        // a teacher can set it to deploy on its own, and only the launcher
        // refuses. Without this, half six comes and the app says "did not
        // finish".
        if let cannotTell = cannotTellExplanation(in: output) {
            return cannotTell
        }
        let marker: String = "is kept for reference, so it is never deployed"
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.contains(marker) else {
                continue
            }
            var sentence: String = String(line).trimmingCharacters(in: .whitespaces)
            // The launchers put a cross in front of every refusal.
            while let first = sentence.first, first == "❌" || first == " " {
                sentence.removeFirst()
            }
            return sentence.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// "Plantoir cannot tell whether … is kept for reference — …", as the two
    /// lines the launchers print, rejoined into the one sentence a teacher
    /// reads.
    ///
    /// Matched on the headline, which is a keyed string both launchers carry
    /// and `scripts/test_reference_course.py` compares them against — so the
    /// three copies cannot drift into three explanations of one rule.
    static func cannotTellExplanation(in output: String) -> String? {
        let headline: String = "cannot tell whether"
        let lines: [Substring] = output.split(separator: "\n", omittingEmptySubsequences: false)
        var index: Int = 0
        while index < lines.count {
            let line: String = String(lines[index]).trimmingCharacters(in: .whitespaces)
            if !line.contains(headline) {
                index += 1
                continue
            }
            var sentence: String = line
            while let first = sentence.first, first == "❌" || first == " " {
                sentence.removeFirst()
            }
            // The reason is the next line. Joined with a space, because the
            // launcher breaks it for the width of a Terminal and the app has
            // no such width.
            if index + 1 < lines.count {
                let reason: String = String(lines[index + 1]).trimmingCharacters(in: .whitespaces)
                if !reason.isEmpty {
                    sentence += " " + reason
                }
            }
            return sentence.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// The workspace a section is built in could not be made, because a folder
    /// it needs could not be handed over.
    ///
    /// Asked LAST, so it can never shadow one of the specific troubles above.
    ///
    /// Matched on `bind source path does not exist` and nothing wider. The
    /// tempting substring was `Error response from daemon`, which would put
    /// this in front of a teacher whose disk was full or whose engine had
    /// restarted mid-run — a confident wrong guess, which this file exists
    /// not to make.
    ///
    /// The commonest cause is a working folder the builder cannot reach at
    /// all: only the home folder is available to it, so an external drive, a
    /// second volume or /Users/Shared cannot be handed over. Measured
    /// 2026-09-19 with paths the virtual machine had never been given, three
    /// of three: refused. That was NOT refused before — the older form
    /// created the folder out of sight and built against an empty one,
    /// reporting success and producing nothing — which is why the sentence
    /// can name the rule now: something finally enforces it.
    ///
    /// Two rarer causes share this output and are deliberately not named: a
    /// folder that moved between the launcher's own check and the moment the
    /// workspace is made, and a builds folder that could not be created. The
    /// launchers print the same sentence themselves, for a teacher at the
    /// command line and for a publish launchd ran overnight. Until
    /// 2026-09-19 a colon in the folder's name beat all of them — GitHub
    /// issue #221.
    static func workspaceCouldNotBeMadeExplanation(in output: String) -> String? {
        if output.contains("bind source path does not exist") {
            return "Plantoir could not get this folder ready for building. "
                 + "Check that it is inside your home folder — on your Desktop or in "
                 + "Documents, for example — and not on an external drive or in a "
                 + "shared location, then try again."
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

    /// The build ran, succeeded at everything it could, and still produced no
    /// website, because the section has no front page.
    ///
    /// Asked BEFORE `missingBuildExplanation`, and the order is the whole
    /// point. A publish runs the build and then the deploy on one transcript,
    /// so when a front page is missing the output carries both lines — and
    /// "hasn't been built yet" is the wrong one to say to somebody who just
    /// watched it build. The build's own reason is the specific one, so it
    /// wins.
    static func missingFrontPageExplanation(in output: String) -> String? {
        if output.contains("no front page, so no website was produced") {
            return "This section has no front page, so there is no website to publish. "
                 + "Put the front page back, then publish again."
        }
        return nil
    }

    /// The build produced no website because the front page's SETTINGS could
    /// not be read, so the build hid it (#246).
    ///
    /// Not the missing front page: the page is there, and "Put the front page
    /// back" would send a teacher to restore a page they can see — with a
    /// repair that would find it and say it was already put right. Asked
    /// BEFORE `missingBuildExplanation` for the same reason as the missing
    /// front page is: a publish's transcript carries the deploy's "Built site
    /// not found" after it, and the build's reason is the specific one.
    ///
    /// The line the build's reader stopped near travels in the output as
    /// "near line N", and is passed on when it is there — the build can tell
    /// for most shapes, not all (`documentation/05-build-pipeline.md`).
    static func unreadableFrontPageExplanation(in output: String) -> String? {
        let sign: String = "the settings at the top of its front page could not be read"
        guard let signRange = output.range(of: sign) else {
            return nil
        }
        let headline: String = "The settings at the top of this section's front page could not be read, "
            + "so there is no website to publish. "
        if let line = lineNumber(after: "(near line ", in: output[signRange.upperBound...]) {
            return headline + "Open the front page in Obsidian, fix its settings near line \(line), "
                + "then publish again."
        }
        return headline + "Open the front page in Obsidian, fix its settings, then publish again."
    }

    /// The whole number written straight after `marker` on the same line of
    /// `text`, or nil when there is none.
    private static func lineNumber(after marker: String, in text: Substring) -> Int? {
        guard let markerRange = text.range(of: marker) else {
            return nil
        }
        let before: Substring = text[..<markerRange.lowerBound]
        if before.contains("\n") {
            return nil
        }
        var digits: String = ""
        for character in text[markerRange.upperBound...] {
            if character.isASCII && character.isNumber {
                digits.append(character)
            } else {
                break
            }
        }
        return Int(digits)
    }
}

import Foundation

/// Words the New Course wizard shows a teacher. Authored in
/// `contracts/shared-rules.json` → `wizard`.
///
/// Why a sentence earns a constant here, and why the keys are authored
/// rather than generated, is in the contract's own `wizard` block — not
/// repeated here.
enum WizardWording {

    // MARK: - Stored properties

    /// The club choice (#267), beside the course code. Authored in
    /// `contracts/shared-rules.json` → `wizard.clubToggle`.
    nonisolated static let clubToggleLabel: String = "This is a club"

    nonisolated static let clubToggleCaption: String =
        "A club meets rather than holds classes: its pages are numbered one after "
        + "another, it has no curriculum, and it starts with a page for its first "
        + "meeting. The words below can be changed now, but not once the course is made."

    /// Under Starting Content for a club, in place of every toggle there.
    nonisolated static let clubStartingContentNote: String =
        "A club starts with empty folders and one page for its first meeting — no "
        + "ready-made pages, no subject skeleton and no curriculum coverage page. "
        + "The coverage page can be turned on later in Course Settings."

    /// The four rows a club's words are chosen in.
    nonisolated static let clubClassFolderLabel: String = "Folder for meeting pages"
    nonisolated static let clubFrontPageHeadingLabel: String = "Front page heading"
    nonisolated static let clubPageWordLabel: String = "Pages are named"
    nonisolated static let clubNounLabel: String = "The assistant calls a page a"

    /// The caption under a club's page word: its own shape, never
    /// "Week 1, Day 1".
    nonisolated static func clubPageWordCaption(word: String) -> String {
        return "Pages will be named “\(word) 1”, “\(word) 2” and so on."
    }

    /// Course Settings' three LOCKED rows (#267): the words a course was
    /// made with, shown and not changeable (Russell, 2026-09-24: not
    /// switchable after the wizard).
    nonisolated static let settingsPageNamingLabel: String = "Class pages are named"
    nonisolated static let settingsFrontPageHeadingLabel: String = "Front page heading"
    nonisolated static let settingsNounLabel: String = "The assistant calls a page a"
    nonisolated static let settingsLockedCaption: String =
        "Chosen when the course was made. An existing course keeps these; they cannot be changed here."

    /// The heading row when the course recorded none (every course made
    /// before #267): its front page keeps whatever heading it has, and this
    /// row does not guess which.
    nonisolated static let settingsFrontPageHeadingNotSet: String =
        "Not recorded — the front page keeps the heading it already has"

    /// The heading row's value: the recorded heading, or the sentence above.
    nonisolated static func settingsFrontPageHeadingValue(_ recorded: String?) -> String {
        guard let recorded else {
            return settingsFrontPageHeadingNotSet
        }
        return recorded
    }

    /// How a scheme is shown in its locked row: the course's own first page.
    nonisolated static func settingsPageNamingValue(_ naming: ClassPageNaming) -> String {
        return "“" + naming.title(unit: 1, day: 1) + "”"
    }

    /// The affirmative button on the wizard's last step.
    nonisolated static let createCourseButton: String = "Create Course"

    /// Shown under Starting Content when the new course will begin with
    /// nothing in it — no ready-made pages exist for the code and no
    /// skeleton either, OR the teacher has turned the skeleton down. Both
    /// are the same situation for a teacher, so both are told the same
    /// thing rather than a second sentence being invented for the second
    /// one. Windows says it in both places too (`NoExampleContentNote()`).
    nonisolated static let noExampleContentNote: String =
        "Example content isn’t available for this course code yet, so the "
        + "course will start with empty folders ready for your own pages."

    /// Shown under Starting Content when a course code that DOES have
    /// ready-made pages will start with nothing: the teacher turned the
    /// example content down and then turned the skeleton down too.
    ///
    /// A second sentence rather than a reword of `noExampleContentNote`,
    /// whose first clause — "Example content isn't available for this
    /// course code yet" — is plainly false to somebody who has just
    /// declined it. Leaving that sentence exactly as it is also leaves the
    /// ~1,900 codes with no payload reading what they have always read.
    nonisolated static let noStartingContentNote: String =
        "This course will start with empty folders ready for your own pages."

    /// Shown in place of the structure editor while the example content is
    /// choosing this course's folders and files.
    ///
    /// Its second sentence had to move with issue #248: turning
    /// pre-populating off used to leave the school-neutral factory lists on
    /// screen, and now leaves the SUBJECT's, which is a different offer.
    /// Pinned here rather than left as a literal in the view for the reason
    /// the contract gives — it is a sentence a teacher reads, and the two
    /// apps had no way to notice the other rewording it.
    nonisolated static let structureFromExampleNote: String =
        "The example content chooses the folders and files for this course, "
        + "so every page lands where its links expect it. Turn off "
        + "pre-populating to start from the subject’s own structure instead, "
        + "and change it however you like."

    /// The skeleton toggle's own label, for a subject the app can name.
    /// `{subject}` is the family's label lowercased except for its proper
    /// nouns, and `{article}` is "a" or "an" for it by sound — the rule is
    /// `contracts/shared-rules.json` → `wizard.skeletonToggleLabelSubject`
    /// (#336, which found "Start from a english skeleton" on screen).
    nonisolated static let skeletonToggleLabelTemplate: String =
        "Start from {article} {subject} skeleton"

    /// Words that keep their capitals when a family's label is lowercased
    /// for the toggle. Pinned against the contract's `properNouns`.
    nonisolated static let skeletonToggleProperNouns: [String] = [
        "English", "French", "First Nations", "Métis", "Inuit", "Indigenous"
    ]

    /// Starts of words spelled with a vowel but said with a consonant
    /// ("a unit", "a European", "a one-page") — checked before the others.
    /// Pinned against the contract's `article.consonantSoundVowelStarts`,
    /// and the same list as `article_for` in `generate_skeletons.py`.
    nonisolated static let consonantSoundVowelStarts: [String] = [
        "uni", "use", "usu", "uti", "ubi", "ura", "eu", "one", "once", "ewe"
    ]

    /// Starts of words spelled with a consonant but said with a vowel
    /// ("an hour"). Pinned against `article.vowelSoundConsonantStarts`.
    nonisolated static let vowelSoundConsonantStarts: [String] = [
        "hour", "honest", "honour", "honor", "heir"
    ]

    /// The same label for the GENERAL family — club codes, custom codes,
    /// and any prefix the map does not carry (MCMPR11, the one British
    /// Columbia code with ready-made pages, is among them).
    ///
    /// Its own sentence because the general family's label is "This
    /// Course", written for the skeleton's own pages, and the template
    /// renders it as "Start from a this course skeleton" — which has been
    /// on screen for club codes since the toggle existed and reads as a
    /// typo. Windows renders the identical string.
    nonisolated static let skeletonToggleLabelForAGeneralSkeleton: String =
        "Start from a general course skeleton"

    /// The caption under the skeleton toggle for a code with NO ready-made
    /// pages of its own.
    nonisolated static let skeletonToggleCaption: String =
        "There is no ready-made course for this code, but there is a starting "
        + "point shaped for the subject: folders that suit it, four units of "
        + "class pages to rename, a page explaining what the site can do, and "
        + "placeholders saying what belongs where."

    /// The caption under the skeleton toggle for a code that HAS ready-made
    /// pages which the teacher has just turned down — where the sentence
    /// above opens with something untrue.
    nonisolated static let skeletonToggleCaptionWhenExampleContentIsDeclined: String =
        "There is also a starting point shaped for the subject: folders that "
        + "suit it, four units of class pages to rename, a page explaining "
        + "what the site can do, and placeholders saying what belongs where."

    // MARK: - Functions

    /// What the skeleton toggle says for one family.
    nonisolated static func skeletonToggleLabel(forFamilyNamed familyName: String,
                                                label: String) -> String {
        if familyName == SkeletonCatalog.generalFamilyName {
            return skeletonToggleLabelForAGeneralSkeleton
        }
        let subject: String = skeletonToggleSubject(forLabel: label)
        let firstWord: String = subject.components(separatedBy: " ").first ?? subject
        return skeletonToggleLabelTemplate
            .replacingOccurrences(of: "{article}", with: article(for: firstWord))
            .replacingOccurrences(of: "{subject}", with: subject)
    }

    /// A family's label as it reads mid-sentence: lowercased, with each
    /// proper noun put back the way `skeletonToggleProperNouns` writes it.
    nonisolated static func skeletonToggleSubject(forLabel label: String) -> String {
        var subject: String = label.lowercased()
        for properNoun in skeletonToggleProperNouns {
            let pattern: String = "\\b" + NSRegularExpression.escapedPattern(for: properNoun) + "\\b"
            guard let expression = try? NSRegularExpression(
                pattern: pattern, options: [.caseInsensitive]
            ) else {
                continue
            }
            let wholeSubject: NSRange = NSRange(subject.startIndex..., in: subject)
            subject = expression.stringByReplacingMatches(
                in: subject,
                options: [],
                range: wholeSubject,
                withTemplate: NSRegularExpression.escapedTemplate(for: properNoun)
            )
        }
        return subject
    }

    /// "a" or "an" for the word that follows it, by its first SOUND rather
    /// than its first letter.
    nonisolated static func article(for word: String) -> String {
        let lowered: String = word.lowercased()
        for start in consonantSoundVowelStarts {
            if lowered.hasPrefix(start) {
                return "a"
            }
        }
        for start in vowelSoundConsonantStarts {
            if lowered.hasPrefix(start) {
                return "an"
            }
        }
        let vowels: [String] = ["a", "e", "i", "o", "u"]
        for vowel in vowels {
            if lowered.hasPrefix(vowel) {
                return "an"
            }
        }
        return "a"
    }
}

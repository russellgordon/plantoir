import Foundation

/// One thing taken out of a report, named so it can be talked about.
nonisolated struct RedactionRule {

    // MARK: - Stored properties

    /// What this rule is for, in the words the contract uses.
    let name: String

    /// The pattern it looks for.
    let pattern: String

    /// What it leaves behind. `$1` keeps a captured label in place, so a
    /// line still says WHAT was taken out.
    let replacement: String
}

/// Takes out of a line anything that names the teacher, or that would let
/// somebody else act as them, on the way IN to a problem report.
///
/// **Redaction happens as the file is written, never as it is sent.** A
/// report that is only safe when it leaves by the right button is one that
/// leaks the first time somebody opens the folder it sits in. Writing it
/// safe also means the file on disk can be handed over as it stands — which
/// is what lets a teacher open the thing and see for themselves what they
/// are sending, rather than being asked to trust a promise about it.
///
/// The rules are deliberately blunt. Removing a build hash by mistake costs
/// a moment of puzzlement; a token that survives costs the teacher their
/// account. Where the two are in tension this leans towards removing too
/// much — with exactly one exception, in `removingLongSecrets`, and the
/// reason it is worth having is written there.
///
/// There is no way to switch this off for a development build. A redactor
/// that is off while it is being worked on is a redactor nobody has run.
nonisolated enum LogRedactor {

    // MARK: - Stored properties

    /// What replaces a credential.
    ///
    /// One phrase for each kind, rather than a blank: a teacher reading
    /// their own report can see that something was taken out and what sort
    /// of thing it was, and a report can be searched for the phrase.
    static let removedToken: String = "[removed: token]"
    static let removedEmail: String = "[removed: email address]"
    static let removedAccount: String = "[removed: account id]"

    /// What replaces the account name in a path. The rest of the path
    /// survives — `/Users/person/Documents/Teaching` still says everything
    /// worth knowing about where the folder sits.
    static let removedPersonPath: String = "person"

    /// A run of exactly this many token characters is treated as a
    /// credential. Cloudflare API tokens are 40 characters.
    static let secretLength: Int = 40

    /// The rules that are pattern matches, applied in this order. The
    /// labelled ones come first so that a value with a label round it is
    /// removed WITH its label kept, rather than being swept up namelessly
    /// by the length rule that runs afterwards.
    static let patternRules: [RedactionRule] = [
        RedactionRule(
            name: "macHomeFolder",
            pattern: #"/Users/[^/\s"':]+"#,
            replacement: "/Users/" + removedPersonPath
        ),
        RedactionRule(
            name: "windowsHomeFolder",
            pattern: #"([A-Za-z]:\\Users\\)[^\\\s"':]+"#,
            replacement: "$1" + removedPersonPath
        ),
        // A username and password written into an address (#709): before
        // the email rule, which would otherwise take the password and the
        // host for an address and leave the username behind.
        RedactionRule(
            name: "urlUserinfo",
            pattern: #"(?i)(https?://)[^/\s:@]+:[^/\s@]+@"#,
            replacement: "$1" + removedToken + "@"
        ),
        RedactionRule(
            name: "emailAddress",
            pattern: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#,
            replacement: removedEmail
        ),
        RedactionRule(
            name: "labelledSecret",
            pattern: #"(?i)\b(\w*(?:token|secret|password|api[_\-]?key)\s*[=:]\s*)\S+"#,
            replacement: "$1" + removedToken
        ),
        RedactionRule(
            name: "bearerHeader",
            pattern: #"(?i)\bBearer\s+\S+"#,
            replacement: "Bearer " + removedToken
        ),
        // A Basic Authorization header (#709): the base64 of a unit plan's
        // username and password. Anchored on the header's own name, so
        // "Basic French" in a course title is left alone (review L4).
        RedactionRule(
            name: "basicAuthHeader",
            pattern: #"(?i)(\bAuthorization:\s*Basic\s+)\S+"#,
            replacement: "$1" + removedToken
        ),
        RedactionRule(
            name: "netlifyToken",
            pattern: #"\bnfp_[A-Za-z0-9]{8,}"#,
            replacement: removedToken
        ),
        RedactionRule(
            name: "accountFlag",
            pattern: #"(?i)(--account[=\s]\s*)[A-Za-z0-9]{16,}"#,
            replacement: "$1" + removedAccount
        ),
        RedactionRule(
            name: "accountIdentifier",
            pattern: #"(?i)(account\s*id\s*[:=]?\s*)[A-Za-z0-9]{16,}"#,
            replacement: "$1" + removedAccount
        ),
        // The ID inside a Cloudflare API path (#773, proposed from Windows
        // with #739). A failing wrangler call names the resource it asked
        // for, and every Pages resource is /accounts/<id>/pages/…, so the ID
        // arrives with no label and no flag beside it. The two rules above
        // do not see it, and at 32 characters the long-secret rule does not
        // either.
        RedactionRule(
            name: "accountPath",
            pattern: #"(?i)(/accounts/)[A-Za-z0-9]{16,}"#,
            replacement: "$1" + removedAccount
        ),
    ]

    // MARK: - Functions

    /// The text as it may be written to a report.
    static func redacting(_ text: String) -> String {
        var result: String = text
        for rule in patternRules {
            result = applying(rule, to: result)
        }
        result = removingLongSecrets(from: result)
        return result
    }

    /// Applies one pattern rule.
    ///
    /// A pattern that will not compile is a mistake in this file rather
    /// than in the text, and the safe thing to do with text that could not
    /// be cleaned is to leave the rule out rather than to write the text
    /// out uncleaned — but every rule here is covered by a contract case,
    /// so a broken pattern fails a test long before it reaches a teacher.
    static func applying(_ rule: RedactionRule, to text: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: rule.pattern) else {
            return text
        }
        let whole: NSRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.stringByReplacingMatches(
            in: text,
            options: [],
            range: whole,
            withTemplate: rule.replacement
        )
    }

    /// Removes any run of exactly 40 token characters — the shape of a
    /// Cloudflare API token, wherever it turns up and whatever is or is not
    /// written beside it.
    ///
    /// **The one exception**: a 40-character run that is entirely lowercase
    /// hexadecimal is left alone, because that is a git commit or a SHA-1
    /// digest, and those are worth reading in a report about a build. A real
    /// token being all-hex by chance is a 1-in-10^24 event, so this gives up
    /// nothing to keep something useful.
    ///
    /// Written as a scan rather than as a pattern because the rule is about
    /// a run's LENGTH being exact — neither 39 nor 41 — and a pattern that
    /// says that needs look-behind and look-ahead on both sides, which is
    /// three times as long as this and cannot be read at a glance.
    static func removingLongSecrets(from text: String) -> String {
        var result: String = ""
        var run: String = ""
        for character in text {
            if isTokenCharacter(character) {
                run.append(character)
                continue
            }
            result += settled(run: run)
            run = ""
            result.append(character)
        }
        result += settled(run: run)
        return result
    }

    /// One completed run of token characters, as it should appear.
    static func settled(run: String) -> String {
        if run.count != secretLength {
            return run
        }
        if isAllLowercaseHexadecimal(run) {
            return run
        }
        return removedToken
    }

    /// The characters a token is made of: letters, digits, underscore, dash.
    static func isTokenCharacter(_ character: Character) -> Bool {
        if character.isLetter && character.isASCII {
            return true
        }
        if character.isNumber && character.isASCII {
            return true
        }
        return character == "_" || character == "-"
    }

    /// True for a run that is only 0-9 and a-f — a digest, not a token.
    static func isAllLowercaseHexadecimal(_ run: String) -> Bool {
        for character in run {
            let isDigit: Bool = character >= "0" && character <= "9"
            let isHexLetter: Bool = character >= "a" && character <= "f"
            if !isDigit && !isHexLetter {
                return false
            }
        }
        return true
    }
}

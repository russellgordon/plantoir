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

    /// **Redacting twice changes nothing (#780).** The rules that take
    /// whatever follows a label (`labelledSecret`, `bearerHeader`, and since
    /// #853 `basicAuthHeader` and `userFlag`) do not take a value that is
    /// already a placeholder, `(?!\[removed: )`; `userFlag` refuses only a
    /// placeholder that stands alone, and reads one inside a value. Before
    /// that, a line redacted at its call site and again by the trail writer
    /// (`ScriptRunner`'s "started …" line is one) read
    /// `token=[removed: token] token]`; the trail writer now redacts twice
    /// on purpose whenever a line held a control character.
    /// `problemReportRedaction.redactedAgainCases`.
    ///
    /// The rules that are pattern matches, applied in this order, which is
    /// part of the contract (`problemReportRedaction.ruleOrder`). A rule
    /// that reads one narrow shape runs before a rule that takes whatever
    /// follows a label, and the email rule runs after every rule whose value
    /// can hold an address. In another order some lines lose only part of a
    /// secret (#853 rounds 2 and 3, measured): with `labelledSecret` before
    /// the home-folder rules, `password=/Users/First Last/x` keeps `Last`,
    /// and with `emailAddress` first, `https://name:password@host` keeps
    /// its username. `ruleOrder.cases` holds lines like these, and each
    /// suite checks that they come out right in this order and differently
    /// in the one other order each case names. The labelled rules still run
    /// before the length rule, which runs last, so that a value with a
    /// label round it is removed WITH its label kept.
    ///
    /// Every rule is linear in the length of the line (#853 round 2): a
    /// trail line of 100,000 characters took more than 90 seconds in the
    /// email rule alone before, and the app's write waits for it.
    /// `ProblemReportTests.testNoRuleTakesLongerThanLinearTime`.
    static let patternRules: [RedactionRule] = [
        // A username and password written into an address (#709): before
        // the email rule, which would otherwise take the password and the
        // host for an address and leave the username behind.
        //
        // Any scheme, not only http and https (#853: `ftp://` left its
        // username behind). The password may hold a raw `/` and, unless it
        // starts with a digit, single spaces. The digit exception is a
        // port: `http://localhost:8081 ready; write to someone@school…`
        // would otherwise lose everything up to the address (measured on an
        // invented trail). A password that starts with a digit is still
        // taken whole up to the `@` when it holds no space. A further word
        // of a password holds no colon, so one address cannot run on into
        // the next. The username holds no `[`, `]`, `?` or `#`, which no
        // username may: so `http://[::1]:8081` and `obsidian://open?vault=…`
        // are not read as a username and a password.
        RedactionRule(
            name: "urlUserinfo",
            pattern: #"(?i)(?<![a-z0-9+.\-])([a-z][a-z0-9+.\-]*://)[^/\s:@\[\]?#]+:(?:(?=\d)[^\s@]+|(?!\d)[^\s@]+(?: [^\s:@]+)*)@"#,
            replacement: "$1" + removedToken + "@"
        ),
        // An account folder whose name holds a space (#876): school-issued
        // accounts are often "First Last", and the rule used to stop at the
        // space and leave the second word of the name behind. Several words
        // are taken when they run on to a separator, a quote, a colon or the
        // end of the line; otherwise only the first, as before, so
        // `/Users/name to /Users/name/Archive` keeps its " to ". Read
        // without regard to case, since neither file system minds
        // (`/users/`, `c:\users\`); the prefix is kept as it was written.
        //
        // An apostrophe followed by a letter is part of the name, so
        // `O'Brien` goes whole; any other quote ends it, so
        // `HOME='/Users/First Last'` keeps its closing quote. A word that
        // would start another rule's match is never taken as a further
        // word of the name: a label word followed by `=` or `:` (`token:`,
        // `password=` and the rest), or `Bearer`, `Authorization` or
        // `Account` not followed by a letter. So `/Users/name token: abc`
        // keeps its label for `labelledSecret`, where taking it would have
        // left `abc` behind, and a surname that only holds a label word
        // (`Secretan`, `Tokenfield`, `Accountly`) is taken with the name
        // (#853 round 3; before, it was left on the line).
        // A carriage return ends the name as the end of a line does,
        // because .NET's `$` does not match before one.
        //
        // The Windows rule reads a doubled backslash too, the way Python
        // prints a Windows path in a dict or an exception (`C:\\Users\\…`).
        RedactionRule(
            name: "macHomeFolder",
            pattern: #"(?im)(/Users/)(?:(?:[^/\s"':]|'(?=\p{L}))+(?: (?!-|[^/\s"':]*(?:token|secret|password|api[_\-]?key)\s*[=:]|[^/\s"':]*(?:bearer|authorization|account)(?![a-z]))(?:[^/\s"':]|'(?=\p{L}))+)*(?=[/"'\r]|:(?:\s|$)|$)|(?:[^/\s"':]|'(?=\p{L}))+)"#,
            replacement: "$1" + removedPersonPath
        ),
        RedactionRule(
            name: "windowsHomeFolder",
            pattern: #"(?im)([A-Z]:\\{1,2}Users\\{1,2})(?:(?:[^\\\s"':]|'(?=\p{L}))+(?: (?!-|[^\\\s"':]*(?:token|secret|password|api[_\-]?key)\s*[=:]|[^\\\s"':]*(?:bearer|authorization|account)(?![a-z]))(?:[^\\\s"':]|'(?=\p{L}))+)*(?=[\\/"'\r]|:(?:\s|$)|$)|(?:[^\\\s"':]|'(?=\p{L}))+)"#,
            replacement: "$1" + removedPersonPath
        ),
        // A Basic Authorization header (#709): the base64 of a unit plan's
        // username and password. Anchored on the header's own name, so
        // "Basic French" in a course title is left alone (review L4).
        //
        // The header's name and value may each sit in quotes, and the name
        // may be followed by `=` (#853): a JSON dump of request headers,
        // `"Authorization": "Basic …"`, and a Python one,
        // `'Authorization': 'Basic …'`, both went through whole. A value
        // that is already a placeholder is left alone, as in the two label
        // rules: before that, redacting twice wrote
        // `Basic [removed: token] token]`.
        //
        // None of the three label rules (this one, `bearerHeader` and
        // `labelledSecret`) takes another rule's label as its value: a
        // value that is `Bearer` and a word, an `Authorization` header, a
        // `token:` label with a space and a value after it, or an account
        // flag or label with its identifier, or with the placeholder that
        // took the identifier (#853 rounds 2 and 3). The rule that owns
        // that label takes what follows it instead, in either order, and
        // redacting again changes nothing. Before, `token: Bearer abc…`
        // wrote out the token, and `password: --account <id>` became
        // `password: [removed: token] [removed: account id]` on a second
        // pass.
        //
        // `Basic` is different, because `basicAuthHeader` owns it only
        // after `Authorization`. So `labelledSecret` takes `Basic` and the
        // word after it together (`password: Basic abc…`, #853 round 3;
        // before, nobody took it). It reads `Basic` atomically, `(?>…)`, so
        // a second pass over `password: Basic [removed: token]` cannot give
        // up the `Basic` and take it as the value. The two header rules
        // still refuse `Basic` and a word, which leaves the contrived
        // `Bearer Basic abc…` to nobody (documentation 09 names it).
        RedactionRule(
            name: "basicAuthHeader",
            pattern: #"(?i)(\bAuthorization["']?\s*[:=]\s*["']?\s*Basic\s+)(?!\[removed: )(?!Bearer\s+\S|Basic\s+\S|["']?Authorization["']?\s*[:=]|\w*(?:token|secret|password|api[_\-]?key)\s*[=:]\s+\S|--account[=\s]\s*(?:[A-Za-z0-9]{16}|\[removed: account id\])|account\s*id\s*[:=]?\s*(?:[A-Za-z0-9]{16}|\[removed: account id\]))\S+"#,
            replacement: "$1" + removedToken
        ),
        RedactionRule(
            name: "bearerHeader",
            pattern: #"(?i)\bBearer\s+(?!\[removed: )(?!Bearer\s+\S|Basic\s+\S|["']?Authorization["']?\s*[:=]|\w*(?:token|secret|password|api[_\-]?key)\s*[=:]\s+\S|--account[=\s]\s*(?:[A-Za-z0-9]{16}|\[removed: account id\])|account\s*id\s*[:=]?\s*(?:[A-Za-z0-9]{16}|\[removed: account id\]))\S+"#,
            replacement: "Bearer " + removedToken
        ),
        RedactionRule(
            name: "labelledSecret",
            pattern: #"(?i)\b(\w*(?:token|secret|password|api[_\-]?key)\s*[=:]\s*)(?!\[removed: )(?!Bearer\s+\S|["']?Authorization["']?\s*[:=]|\w*(?:token|secret|password|api[_\-]?key)\s*[=:]\s+\S|--account[=\s]\s*(?:[A-Za-z0-9]{16}|\[removed: account id\])|account\s*id\s*[:=]?\s*(?:[A-Za-z0-9]{16}|\[removed: account id\]))(?>(?:Basic\s+)?)(?!\[removed: )\S+"#,
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
        // A username and password handed to a command line's `-u` or
        // `--user` (#853), the way curl takes them. Only a value holding a
        // colon goes: a bare `-u name` holds no password (curl asks for
        // it), and `git push -u origin …` holds no colon. A quoted value is
        // taken to its closing quote, spaces and all. The flag is kept, so
        // the line still says a user was given. `-u` may close a run of
        // short flags (`-su`), and it is not read inside a word or after a
        // second dash. Before the email rule, since a school login is
        // usually an address and that rule left the password behind it.
        // Only spaces and tabs may sit between the flag and its value, so
        // a flag at the end of one line never takes the next.
        //
        // A placeholder inside the value is read as part of it, so a
        // username another rule took first (`-u [removed: token]:pass`)
        // still loses its password. The flag is read atomically, `(?>…)`, up
        // to its first `u`, so a long run of letters after a dash is read
        // once rather than once for every `u` in it.
        RedactionRule(
            name: "userFlag",
            pattern: #"(?<![\w\-])((?>-[A-Za-z]*?u)[ \t]*|--user(?:=|[ \t]+))(?!\[removed: [a-z ]+\](?:\s|$))(?:'[^':\n]*:[^'\n]*'|"[^":\n]*:[^"\n]*"|(?:\[removed: [a-z ]+\]|[^\s:'"])+:(?:\[removed: [a-z ]+\]|\S)+)"#,
            replacement: "$1" + removedToken
        ),
        // A match starts only where a run of address characters starts, so
        // a long run with no `@` in it is read once rather than once from
        // every character (#853 round 2: 100,000 of them took more than 90
        // seconds). Every address it took before, it still takes whole.
        // An address whose name another rule already took
        // (`[removed: token]@school…`) still loses its domain, except after
        // `://`, where that is `urlUserinfo`'s own work and the host stays.
        RedactionRule(
            name: "emailAddress",
            pattern: #"(?:(?<!://)\[removed: (?:token|account id)\]|(?<![A-Za-z0-9._%+\-])[A-Za-z0-9._%+\-]+)@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#,
            replacement: removedEmail
        ),
    ]

    // MARK: - Functions

    /// The text as it may be written to a report.
    static func redacting(_ text: String) -> String {
        return redacting(text, applyingInOrder: patternRules)
    }

    /// The text with these pattern rules applied in this order, then the
    /// 40-character run. The app always passes `patternRules`; a test
    /// passes the same rules in another order, to show that a
    /// `problemReportRedaction.ruleOrder` case depends on the order.
    static func redacting(_ text: String, applyingInOrder rules: [RedactionRule]) -> String {
        var result: String = text
        for rule in rules {
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

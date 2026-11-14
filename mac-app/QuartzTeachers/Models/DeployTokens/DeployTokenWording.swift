import Foundation

/// Every sentence Plantoir ▸ Settings ▸ Deploying says about the teacher's
/// deploy tokens, and the warning a section's Deploy screen shows (#696).
///
/// One place, pinned key by key to `contracts/shared-rules.json` →
/// `deployTokens.words` by `DeployTokenTests`, so Windows says the same words.
/// "Token" is the hosts' own word for what the teacher pasted, and the word
/// the deploy's own sheet already uses; nothing here names where it is kept.
nonisolated enum DeployTokenWording {

    // MARK: - Stored properties

    nonisolated static let sectionHeaderNetlify: String = "Netlify"
    nonisolated static let statusChecking: String = "Checking the token…"
    nonisolated static let statusConnected: String = "Connected to {service}."
    nonisolated static let statusConnectedEndsOn: String = "Connected to {service}. The token ends on {date}."
    nonisolated static let statusConnectedEndsSoon: String =
        "Connected to {service}. The token ends on {date}, less than 30 days from now. Make a new one before then."
    nonisolated static let statusNotConnected: String = "Not connected. The next deploy to {service} asks for a token."
    nonisolated static let statusRefused: String =
        "{service} no longer accepts the saved token. Change it before the next deploy."
    nonisolated static let statusExpired: String = "The saved token has expired. Change it before the next deploy."
    nonisolated static let statusDisabled: String =
        "{service} says the saved token is turned off. Change it before the next deploy."
    nonisolated static let statusCannotUseAccount: String =
        "The saved token cannot deploy to the Cloudflare account above. Check its permission and its account, or change it."
    nonisolated static let statusUnheard: String = "Plantoir could not reach {service} to check the token. It is still saved."
    nonisolated static let statusNoWorkingFolder: String = "Open a working folder to check the token."
    nonisolated static let changeButton: String = "Change Token…"
    nonisolated static let removeButton: String = "Remove Token"
    nonisolated static let checkAgainButton: String = "Check Again"
    nonisolated static let removeTitle: String = "Remove the {service} token?"
    nonisolated static let removeMessage: String =
        "Deploys to {service} stop until a new token is saved, and a deploy set for later will not run. The next deploy you press asks for one."
    nonisolated static let removeConfirm: String = "Remove"
    nonisolated static let changeTitle: String = "Change the {service} Token"
    nonisolated static let changeConfirm: String = "Check and Save"
    nonisolated static let checkingNewToken: String = "Checking the new token with {service}…"
    nonisolated static let problemTokenEmpty: String = "Paste the token first."
    nonisolated static let problemTokenHasSpaces: String =
        "What was pasted has a space or a line break inside it. Copy the token again, and paste only the token itself."
    nonisolated static let problemTokenNotPlainText: String =
        "What was pasted has a character no token has, such as a curly quote. Copy the token again from {service}'s page."
    nonisolated static let problemTokenRefused: String = "{service} did not accept that token. Nothing was changed."
    nonisolated static let problemTokenRefusedCloudflare: String =
        "Cloudflare did not accept that token. Check that it has the 'Cloudflare Pages - Edit' permission, then try again."
    nonisolated static let problemTokenExpired: String = "That token has already expired. Nothing was changed."
    nonisolated static let problemTokenDisabled: String = "{service} says that token is turned off. Nothing was changed."
    nonisolated static let problemTokenCannotUseAccount: String =
        "That token cannot deploy to the Cloudflare account in Settings. Check that it has the 'Cloudflare Pages - Edit' permission and names that account."
    nonisolated static let problemUnheard: String =
        "Plantoir could not reach {service} to check that token, so nothing was changed. Check that this computer is online, then try again."
    nonisolated static let problemSitesNotChecked: String =
        "Plantoir could not check that token against your class websites, so nothing was changed. Check that this computer is online, then try again."
    nonisolated static let problemCouldNotSave: String =
        "{service} accepted that token, but it could not be saved on this Mac. Nothing was changed."
    nonisolated static let unreachableTitle: String = "That token cannot reach {count} of your class websites"
    nonisolated static let unreachableTitleOne: String = "That token cannot reach one of your class websites"
    nonisolated static let unreachableMessage: String =
        "Deployed with your old token: {sections}. A deploy with this one would make a new website at a new address, so students' links would stop working. The token may belong to another {service} account."
    nonisolated static let keepOldToken: String = "Keep My Old Token"
    nonisolated static let useNewToken: String = "Use the New Token"
    nonisolated static let placeSection: String = "{course} section {section}"
    nonisolated static let deployScreenEndsSoon: String =
        "The Cloudflare token ends on {date}. Make a new one and change it in Plantoir ▸ Settings ▸ Deploying before then."
    nonisolated static let deployScreenEnded: String =
        "The Cloudflare token ended on {date}, so deploys to Cloudflare will stop. Change it in Plantoir ▸ Settings ▸ Deploying."
    nonisolated static let openSettingsButton: String = "Open Settings…"

    // MARK: - Computed properties

    /// Every sentence by its contract key, for the test that pins them.
    nonisolated static var everyKey: [String: String] {
        return [
            "sectionHeaderNetlify": sectionHeaderNetlify,
            "statusChecking": statusChecking,
            "statusConnected": statusConnected,
            "statusConnectedEndsOn": statusConnectedEndsOn,
            "statusConnectedEndsSoon": statusConnectedEndsSoon,
            "statusNotConnected": statusNotConnected,
            "statusRefused": statusRefused,
            "statusExpired": statusExpired,
            "statusDisabled": statusDisabled,
            "statusCannotUseAccount": statusCannotUseAccount,
            "statusUnheard": statusUnheard,
            "statusNoWorkingFolder": statusNoWorkingFolder,
            "changeButton": changeButton,
            "removeButton": removeButton,
            "checkAgainButton": checkAgainButton,
            "removeTitle": removeTitle,
            "removeMessage": removeMessage,
            "removeConfirm": removeConfirm,
            "changeTitle": changeTitle,
            "changeConfirm": changeConfirm,
            "checkingNewToken": checkingNewToken,
            "problemTokenEmpty": problemTokenEmpty,
            "problemTokenHasSpaces": problemTokenHasSpaces,
            "problemTokenNotPlainText": problemTokenNotPlainText,
            "problemTokenRefused": problemTokenRefused,
            "problemTokenRefusedCloudflare": problemTokenRefusedCloudflare,
            "problemTokenExpired": problemTokenExpired,
            "problemTokenDisabled": problemTokenDisabled,
            "problemTokenCannotUseAccount": problemTokenCannotUseAccount,
            "problemUnheard": problemUnheard,
            "problemSitesNotChecked": problemSitesNotChecked,
            "problemCouldNotSave": problemCouldNotSave,
            "unreachableTitle": unreachableTitle,
            "unreachableTitleOne": unreachableTitleOne,
            "unreachableMessage": unreachableMessage,
            "keepOldToken": keepOldToken,
            "useNewToken": useNewToken,
            "placeSection": placeSection,
            "deployScreenEndsSoon": deployScreenEndsSoon,
            "deployScreenEnded": deployScreenEnded,
            "openSettingsButton": openSettingsButton,
        ]
    }

    // MARK: - Functions

    /// A sentence with its placeholders filled in.
    nonisolated static func filled(_ sentence: String, _ values: [String: String]) -> String {
        var result: String = sentence
        for (key, value) in values {
            result = result.replacingOccurrences(of: "{" + key + "}", with: value)
        }
        return result
    }

    /// The date a teacher reads, in the Mac's own way of writing dates.
    nonisolated static func shownDate(_ date: Date, in timeZone: TimeZone, locale: Locale = Locale.current) -> String {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// The status line under a destination's heading for a check's answer.
    nonisolated static func statusLine(
        for answer: DeployTokenAnswer,
        destination: DeployTokenDestination,
        now: Date,
        timeZone: TimeZone,
        locale: Locale = Locale.current
    ) -> String {
        let service: String = destination.serviceName
        switch answer.answer {
        case "notSaved":
            return filled(statusNotConnected, ["service": service])
        case "unheard":
            return filled(statusUnheard, ["service": service])
        case "refused":
            if answer.problem == "tokenExpired" {
                return statusExpired
            }
            if answer.problem == "tokenDisabled" {
                return filled(statusDisabled, ["service": service])
            }
            if answer.problem == "tokenCannotUseAccount" {
                return statusCannotUseAccount
            }
            return filled(statusRefused, ["service": service])
        case "accepted":
            let reading: DeployTokenEndDate.Reading = DeployTokenEndDate.reading(
                endsOn: answer.endsOn, now: now, timeZone: timeZone
            )
            guard let endDate = reading.endDate else {
                return filled(statusConnected, ["service": service])
            }
            let date: String = shownDate(endDate, in: timeZone, locale: locale)
            switch reading.state {
            case .endsSoon, .ended:
                return filled(statusConnectedEndsSoon, ["service": service, "date": date])
            case .ends, .none:
                return filled(statusConnectedEndsOn, ["service": service, "date": date])
            }
        default:
            return filled(statusUnheard, ["service": service])
        }
    }

    /// What the Change Token sheet says under the field when a save did not
    /// keep the new token, or nil when there is nothing to say (it was saved,
    /// or the answer is the list of class websites, which has its own
    /// question).
    nonisolated static func sheetProblem(for answer: DeployTokenAnswer, destination: DeployTokenDestination) -> String? {
        if answer.saved {
            return nil
        }
        let service: String = destination.serviceName
        switch answer.problem {
        case "tokenEmpty":
            return problemTokenEmpty
        case "tokenHasSpaces":
            return problemTokenHasSpaces
        case "tokenNotPlainText":
            return filled(problemTokenNotPlainText, ["service": service])
        case "tokenRefused":
            if destination == .cloudflare {
                return problemTokenRefusedCloudflare
            }
            return filled(problemTokenRefused, ["service": service])
        case "tokenExpired":
            return problemTokenExpired
        case "tokenDisabled":
            return filled(problemTokenDisabled, ["service": service])
        case "tokenCannotUseAccount":
            return problemTokenCannotUseAccount
        case "sitesNotChecked":
            return problemSitesNotChecked
        case "couldNotSave":
            return filled(problemCouldNotSave, ["service": service])
        case "tokenCannotReachSites":
            return nil
        default:
            return filled(problemUnheard, ["service": service])
        }
    }

    /// "ICS3U section 2" for the launcher's "ICS3U/2"; a place in any other
    /// shape is shown as it came.
    nonisolated static func place(_ courseAndSection: String) -> String {
        let parts: [Substring] = courseAndSection.split(separator: "/")
        if parts.count != 2 {
            return courseAndSection
        }
        return filled(placeSection, ["course": String(parts[0]), "section": String(parts[1])])
    }

    /// The question's title when a new token cannot reach some websites.
    nonisolated static func unreachableQuestionTitle(count: Int) -> String {
        if count == 1 {
            return unreachableTitleOne
        }
        return filled(unreachableTitle, ["count": String(count)])
    }

    /// The question's message, naming every website by course and section.
    nonisolated static func unreachableQuestionMessage(places: [String], destination: DeployTokenDestination) -> String {
        var named: [String] = []
        for courseAndSection in places {
            named.append(place(courseAndSection))
        }
        let list: String = ListFormatter.localizedString(byJoining: named)
        return filled(unreachableMessage, ["sections": list, "service": destination.serviceName])
    }

    /// The warning a section's Deploy screen shows, or nil when there is
    /// none: only for a Cloudflare token whose remembered end date is under
    /// 30 days away or past (`deployTokens.endDate.rule`).
    nonisolated static func deployScreenWarning(
        rememberedEndsOn: String,
        now: Date,
        timeZone: TimeZone,
        locale: Locale = Locale.current
    ) -> String? {
        let reading: DeployTokenEndDate.Reading = DeployTokenEndDate.reading(
            endsOn: rememberedEndsOn, now: now, timeZone: timeZone
        )
        guard let endDate = reading.endDate else {
            return nil
        }
        let date: String = shownDate(endDate, in: timeZone, locale: locale)
        switch reading.state {
        case .endsSoon:
            return filled(deployScreenEndsSoon, ["date": date])
        case .ended:
            return filled(deployScreenEnded, ["date": date])
        case .ends, .none:
            return nil
        }
    }
}

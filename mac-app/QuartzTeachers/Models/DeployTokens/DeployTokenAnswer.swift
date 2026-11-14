import Foundation

/// Which host a deploy token is for (#696). GitHub Pages joins with #669.
nonisolated enum DeployTokenDestination: String, CaseIterable, Equatable {

    case netlify
    case cloudflare

    // MARK: - Computed properties

    /// The host's name as a teacher reads it, in the sentences.
    nonisolated var serviceName: String {
        switch self {
        case .netlify:
            return "Netlify"
        case .cloudflare:
            return "Cloudflare"
        }
    }

    /// What the launcher's `--target` is given.
    nonisolated var launcherTarget: String {
        return rawValue
    }

    /// The steps the Change Token sheet shows: the deploy's own, one source.
    @MainActor var credentialRequest: CredentialRequest {
        switch self {
        case .netlify:
            return CredentialRequest.netlifyToken
        case .cloudflare:
            return CredentialRequest.cloudflareToken
        }
    }
}

/// What `deploy.sh --token …` answered: one line of JSON in the shape
/// `contracts/shared-rules.json` → `deployTokens.answerShape` names.
nonisolated struct DeployTokenAnswer: Equatable, Decodable {

    // MARK: - Stored properties

    var saved: Bool
    var answer: String
    var endsOn: String?
    var problem: String?
    var unreachable: [String]

    // MARK: - Functions

    /// The answer in a launcher's output, or nil when there is none: the last
    /// line that is a JSON object of the right shape. Anything else the
    /// launcher printed (a refusal of an argument, say) is ignored here and
    /// shown as "could not be checked".
    nonisolated static func parse(_ output: String) -> DeployTokenAnswer? {
        var found: DeployTokenAnswer? = nil
        for line in output.split(separator: "\n") {
            let trimmed: String = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.hasPrefix("{") {
                continue
            }
            guard let data = trimmed.data(using: .utf8) else {
                continue
            }
            if let decoded = try? JSONDecoder().decode(DeployTokenAnswer.self, from: data) {
                found = decoded
            }
        }
        return found
    }
}

/// When a token ends, read the way `deployTokens.endDate.rule` says: the
/// instant the service gave, shown as that instant's date in the Mac's time
/// zone, with a warning when it is under 30 days away (#696, first ruling).
nonisolated enum DeployTokenEndDate {

    // MARK: - Stored properties

    /// Under this many days away is a warning; exactly this many is not.
    nonisolated static let warningDays: Int = 30

    enum State: String, Equatable {
        case none
        case ends
        case endsSoon
        case ended
    }

    struct Reading: Equatable {
        var state: State
        var endDate: Date?
        /// The end date's calendar date in the time zone, as yyyy-MM-dd.
        var localDate: String?
        /// Whole calendar days from today to the end date; nil when there is
        /// no end date or it has passed.
        var daysLeft: Int?
    }

    // MARK: - Functions

    /// The instant an end date names, or nil when it is not an ISO 8601
    /// date and time with seconds and a zone (`endDate.reading.rule`).
    nonisolated static func instant(from text: String?) -> Date? {
        guard let text, !text.isEmpty else {
            return nil
        }
        let plain: ISO8601DateFormatter = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) {
            return date
        }
        let fractional: ISO8601DateFormatter = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }

    /// The reading of an end date at a moment, in a time zone.
    nonisolated static func reading(endsOn: String?, now: Date, timeZone: TimeZone) -> Reading {
        guard let endDate = instant(from: endsOn) else {
            return Reading(state: .none, endDate: nil, localDate: nil, daysLeft: nil)
        }
        var calendar: Calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts: DateComponents = calendar.dateComponents([.year, .month, .day], from: endDate)
        let localDate: String = String(
            format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0
        )
        if endDate <= now {
            return Reading(state: .ended, endDate: endDate, localDate: localDate, daysLeft: nil)
        }
        let today: Date = calendar.startOfDay(for: now)
        let lastDay: Date = calendar.startOfDay(for: endDate)
        let days: Int = calendar.dateComponents([.day], from: today, to: lastDay).day ?? 0
        let state: State = days < warningDays ? .endsSoon : .ends
        return Reading(state: state, endDate: endDate, localDate: localDate, daysLeft: days)
    }
}

/// The end date a deploy to Cloudflare said its token has, read from
/// `deploy.sh`'s `PLANTOIR_TOKEN_ENDS:` line (`deployTokens.endDate.marker`)
/// and kept so the section's Deploy screen can warn without asking
/// Cloudflare each time it opens (review MUST 2).
nonisolated enum DeployTokenEndReport {

    // MARK: - Stored properties

    nonisolated static let markerPrefix: String = "PLANTOIR_TOKEN_ENDS:"

    // MARK: - Functions

    /// The last report in a stretch of output: `.some(nil)` for a token with
    /// no end date, `.some(date)` for one, and nil when the output says
    /// nothing in the marker's exact shape.
    nonisolated static func endsOn(in text: String) -> String?? {
        var found: String?? = nil
        for line in text.split(separator: "\n") {
            guard let prefixRange = line.range(of: markerPrefix) else {
                continue
            }
            var words: [String] = []
            for word in line[prefixRange.upperBound...].split(separator: " ", omittingEmptySubsequences: true) {
                words.append(String(word).trimmingCharacters(in: .whitespacesAndNewlines))
            }
            guard words.count == 2, words[0] == DeployTokenDestination.cloudflare.launcherTarget else {
                continue
            }
            if words[1] == "none" {
                found = .some(nil)
                continue
            }
            if DeployTokenEndDate.instant(from: words[1]) != nil {
                found = .some(words[1])
            }
        }
        return found
    }

    /// Keeps what a stretch of a deploy's output said, if it said anything.
    nonisolated static func remember(from text: String) {
        guard let said = endsOn(in: text) else {
            return
        }
        let kept: String = said ?? ""
        Task { @MainActor in
            AppSettings.shared.cloudflareTokenEndsOn = kept
        }
    }
}

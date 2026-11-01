import Foundation

/// Where a NEW course deploys, and what a teacher is told while choosing
/// (GitHub #668). Every rule and sentence here is pinned by
/// `contracts/app-rules.json` → `publishingDestinations`, so the Windows app
/// shows the same words and makes the same choice.
///
/// Netlify moved new accounts to a fixed monthly allowance shared by every
/// site on the account, which deploys use up; when it runs out, every site
/// on the account is paused until the next month. So a course made in the
/// new-course window starts on Cloudflare Pages. A course whose file names
/// NO destination still deploys to Netlify — see `whenTheKeyIsAbsent` and
/// `CourseConfiguration.deployTarget` — because every course made before the
/// other destinations existed relies on that.
///
/// The sentences carry no figures (the hosts change them; the dated figures
/// are in documentation/07-deployment.md), say DEPLOY for what spends the
/// allowance (publishing marks a page and costs nothing), and make no claim
/// about Cloudflare's limits on deploys.
enum PublishingDestinations {

    // MARK: - Stored properties

    /// What the new-course window writes as `deploy_target` unless the
    /// teacher picks something else.
    nonisolated static let newCourseDefault: String = "cloudflare_pages"

    /// What a `course_config.json` with no `deploy_target` deploys to. Not
    /// the same as `newCourseDefault`, on purpose: `whyTheyDiffer` in the
    /// contract.
    nonisolated static let whenTheKeyIsAbsent: String = "netlify"

    /// The new-course window's caption over its Deploying section.
    nonisolated static let wizardCaption: String =
        "Cloudflare Pages is the usual choice — change it any time in Course Settings"

    /// Under Cloudflare Pages wherever it is chosen, primary or additional.
    nonisolated static let cloudflareCaption: String =
        "Recommended. Free, with no limit on visitors."

    /// Under Netlify wherever it is chosen, primary or additional, in the
    /// new-course window and in Course Settings.
    nonisolated static let netlifyNote: String =
        "A note about Netlify’s free plan: Netlify accounts made since September 2025 get a fixed monthly allowance, and every deploy of every section uses part of it. When the allowance runs out, Netlify pauses every site on the account until the next month. Cloudflare Pages’ free plan has no limit on visitors, which is why Plantoir suggests it. If your Netlify account is older than that, or you deploy only now and then, Netlify works well."

    /// The shorter form, in the Schedule a deploy sheet of a course that
    /// deploys to Netlify — a deploy that happens on its own is the easiest
    /// one to forget the cost of.
    nonisolated static let netlifyScheduleNote: String =
        "This course deploys to Netlify. On Netlify’s free plan every deploy uses part of a monthly allowance, and when it runs out Netlify pauses every site on the account until the next month."

    /// Under the orange "Paste your Cloudflare Account ID." in the
    /// new-course window, which no longer refuses Create for a missing ID.
    nonisolated static let accountIDCanWait: String =
        "You can create the course without it and preview it as usual. It is needed before the first deploy."

    // MARK: - Functions

    /// Whether the Netlify note belongs on screen for these destinations.
    /// An empty primary is a course whose file names none, which deploys to
    /// Netlify.
    static func showsNetlifyNote(primary: String, additional: [String]) -> Bool {
        if primary.isEmpty || primary == "netlify" {
            return true
        }
        for type in additional where type == "netlify" {
            return true
        }
        return false
    }

    /// Whether the Cloudflare caption belongs on screen: wherever Cloudflare
    /// Pages is configured, primary or additional.
    static func showsCloudflareCaption(primary: String, additional: [String]) -> Bool {
        if primary == "cloudflare_pages" {
            return true
        }
        for type in additional where type == "cloudflare_pages" {
            return true
        }
        return false
    }

    /// Why the new-course window refuses Create over the Cloudflare Account
    /// ID, or nil when it does not. An EMPTY ID no longer refuses (#668): it
    /// is a warning, and the first deploy is where it is asked for
    /// (`MultiDestinationDeployRunner.refusalReason`). An ID that cannot be
    /// one still refuses, because something is saved and it is wrong.
    static func wizardCreateRefusal(forAccountID rawID: String) -> String? {
        if accountIDIsMissing(rawID) {
            return nil
        }
        return CourseConfiguration.cloudflareAccountProblem(forID: rawID)
    }

    /// Whether the "Cannot Deploy Yet" alert offers Open Settings… beside
    /// OK (#668): when what it says is the Account ID's problem, which is
    /// put right in Plantoir ▸ Settings ▸ Deploying. A folder's refusal is
    /// put right in the course's own settings, so it does not.
    static func deployRefusalOpensSettings(refusal: String, cloudflareAccountID: String) -> Bool {
        guard let problem = CourseConfiguration.cloudflareAccountProblem(forID: cloudflareAccountID) else {
            return false
        }
        return refusal.hasPrefix(problem)
    }

    /// True when the ID is empty once trimmed — the case the new-course
    /// window lets wait, and says so with `accountIDCanWait`.
    static func accountIDIsMissing(_ rawID: String) -> Bool {
        return rawID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

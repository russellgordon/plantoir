import Foundation

/// The sentences a scheduled deploy is refused with when a destination has
/// never been deployed to, one per shape (GitHub #322).
///
/// Both are pinned by `contracts/shared-rules.json` →
/// `scheduledDeployRefusals.wording` and compared WHOLE, rendered from the
/// contract's template: the two share "has never been deployed to", so a
/// substring check cannot tell them apart.
///
/// The primary's sentence names its destination since #322. Russell read the
/// old one — "has never been deployed, so deploying it asks what to call the
/// website" — as "it thinks I am deploying to Netlify" and had to guess; the
/// assistant WAS deploying to Netlify, from a copy of the settings taken
/// before he changed them to a folder. Naming the destination lets a teacher
/// who expected somewhere else see the disagreement at once.
enum ScheduledDeployWording {

    // MARK: - Functions

    /// The course's PRIMARY destination has never been deployed to, so the
    /// first deploy there would ask what to call the website.
    static func neverDeployed(course: String, section: Int, destination: String) -> String {
        return "\(course) Section \(section) has never been deployed to \(destination), "
            + "so deploying it there asks what to call the website. "
            + "Nobody would be there to answer that at the scheduled time, and it would wait. "
            + "Deploy it to \(destination) once from Plantoir, and after that it can be scheduled."
    }

    /// An ADDITIONAL destination has never been deployed to. Unchanged from
    /// before #322; moved here so the contract pins it too.
    static func additionalDestinationNeverDeployed(course: String, section: Int, destination: String) -> String {
        return "\(course) Section \(section) has never been deployed to \(destination), "
            + "so deploying it there asks what to call that site. "
            + "Nobody would be there to answer that at the scheduled time, and it would wait. "
            + "Deploy it there once from Plantoir, and after that it can be scheduled."
    }
}

/// Why a scheduled deploy cannot go ahead the way a course is set: one case
/// per `scheduledDeployRefusals` key, and the reference-course refusal
/// (GitHub #323).
///
/// The same checks are asked at three moments — when the deploy is SET (the
/// sheet and the assistants), when it RUNS (`ScheduledDeploy.readAtTheRun`),
/// and after a Save in Course Settings — and each moment says it differently,
/// because advice that is true at one is false at another: "after that it can
/// be scheduled" is wrong for a deploy that is already scheduled, and "it
/// would wait" is wrong at the run, which did not wait (the #323 plan
/// review's M3). So a refusal carries two things:
///
/// - `sentence(course:section:)` — the schedule sheet's whole sentence,
///   byte for byte what `ScheduledDeploy.problem()` has always returned
///   (pinned by `scheduledDeployRefusals.cases`);
/// - `reasonClause` — a short clause true at any moment, with no remedy and
///   no path in it, which the run's stand-down, the Save's sentence and the
///   trail all put inside sentences of their own.
nonisolated enum ScheduledDeployRefusal: Equatable, Sendable {

    // MARK: - Cases

    case keptForReference
    case deployFolderNeedsAttention(problem: String)
    case cloudflareAccountMissing(problem: String)
    case additionalDeployFolderNeedsAttention(problem: String)
    case additionalCloudflareAccountMissing(problem: String)
    case neverDeployed(destination: String)
    case additionalDestinationNeverDeployed(destination: String)

    // MARK: - Computed properties

    /// The key this refusal has in `contracts/shared-rules.json` →
    /// `scheduledDeployRefusals.cases[].expectRefusal`. The reference-course
    /// refusal is not one of those: its sentence is
    /// `AssistWording.deployRefusedForAReferenceCourse`, in assist-wording.json.
    var contractKey: String {
        switch self {
        case .keptForReference:
            return "keptForReference"
        case .deployFolderNeedsAttention:
            return "deployFolderNeedsAttention"
        case .cloudflareAccountMissing:
            return "cloudflareAccountMissing"
        case .additionalDeployFolderNeedsAttention:
            return "additionalDeployFolderNeedsAttention"
        case .additionalCloudflareAccountMissing:
            return "additionalCloudflareAccountMissing"
        case .neverDeployed:
            return "neverDeployed"
        case .additionalDestinationNeverDeployed:
            return "additionalDestinationNeverDeployed"
        }
    }

    /// Why, in a clause true at ANY moment: no remedy, no "schedule this
    /// again", no path. Pinned by `scheduledDeployCancellation.theDestination`
    /// → `reasonClauses`. Written into a stand-down's record, the Save's
    /// sentence and the trail.
    var reasonClause: String {
        switch self {
        case .keptForReference:
            return "it is a course kept for reference, which is never deployed"
        case .deployFolderNeedsAttention:
            return "the folder it deploys to needs attention in this course’s settings, under Deploying"
        case .cloudflareAccountMissing:
            return "it deploys to Cloudflare Pages, which needs your Account ID, and no Account ID that works is set"
        case .additionalDeployFolderNeedsAttention:
            return "a folder it also deploys to needs attention in this course’s settings, under Deploying"
        case .additionalCloudflareAccountMissing:
            return "it also deploys to Cloudflare Pages, which needs your Account ID, and no Account ID that works is set"
        case .neverDeployed(let destination):
            return "it has never been deployed to \(destination), and the first deploy there asks what to call the website"
        case .additionalDestinationNeverDeployed(let destination):
            return "it has never been deployed to \(destination), and the first deploy there asks what to call that site"
        }
    }

    // MARK: - Functions

    /// The schedule sheet's sentence — unchanged by #323, and still what
    /// `ScheduledDeploy.problem()` returns.
    @MainActor
    func sentence(course: Course, section: Int) -> String {
        switch self {
        case .keptForReference:
            return AssistWording.deployRefusedForAReferenceCourse(course: course.displayCode)
        case .deployFolderNeedsAttention(let problem):
            return "\(course.code) deploys to a folder, and that folder needs attention first: \(problem)"
        case .cloudflareAccountMissing(let problem):
            return "\(course.code) deploys to Cloudflare Pages, which needs your Account ID. \(problem) Add it in this course’s settings, under Deploying, then schedule this again."
        case .additionalDeployFolderNeedsAttention(let problem):
            return "\(course.code) also deploys to a folder, and that folder needs attention first: \(problem)"
        case .additionalCloudflareAccountMissing(let problem):
            return "\(course.code) also deploys to Cloudflare Pages, which needs your Account ID. \(problem) Add it in this course’s settings, under Deploying, then schedule this again."
        case .neverDeployed(let destination):
            return ScheduledDeployWording.neverDeployed(course: course.code, section: section, destination: destination)
        case .additionalDestinationNeverDeployed(let destination):
            return ScheduledDeployWording.additionalDestinationNeverDeployed(
                course: course.code, section: section, destination: destination
            )
        }
    }
}

extension ScheduledDeployWording {

    // MARK: - Stored properties

    /// The reason a run stood down when the course's settings could not be
    /// read at the moment it fired (#323). A clause, like every
    /// `reasonClause`: it goes inside `couldNotRunAsSetNow`'s sentence.
    /// Pinned by `scheduledDeployCancellation.theDestination.wording`.
    nonisolated static let settingsCouldNotBeRead: String =
        "its settings could not be read when the time came, so there was no telling where to deploy it"

    /// The reason a run stood down when it read the settings but could not
    /// get the deploy ready (#323 review, M2) — never "could not read".
    nonisolated static let wrapperCouldNotBeWritten: String =
        "Plantoir could not get the deploy ready on this computer when the time came"
}

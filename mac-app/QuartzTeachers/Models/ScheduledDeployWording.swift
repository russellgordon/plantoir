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

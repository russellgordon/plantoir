import Foundation

/// What `deploy.sh` is asked to do for one section, at one destination.
///
/// One place decides this, because several now ask: the Deploy button, the
/// assistant, and the launchd agent a scheduled deploy leaves behind.
/// Building the arguments separately in each would let a scheduled
/// Cloudflare deploy quietly go to Netlify — the failure would appear once,
/// overnight, on a live class site.
///
/// A course can publish to more than one destination now (redundancy
/// against one host having a bad day) — see
/// `CourseConfiguration.allDeployDestinations`. The functions here that
/// take a single `destination:` are the ones a multi-destination deploy
/// calls once per leg; the ones that take a whole `configuration:` are
/// thin wrappers over those, kept so every existing caller and every
/// existing test — all written against "this course's ONE destination" —
/// keeps working unchanged, reading `deployTarget` as that one destination.
enum DeployCommand {

    // MARK: - Stored properties

    /// The launcher in the teacher's working folder.
    static let scriptName: String = "deploy.sh"

    // MARK: - Functions

    /// The arguments for one section's deploy, to one destination.
    ///
    /// Netlify passes no target flag at all: it is `deploy.sh`'s default,
    /// and every course written before Cloudflare existed relies on that.
    static func arguments(
        courseCode: String,
        sectionNumber: Int,
        destination: CourseConfiguration.DeployDestination,
        cloudflareAccountID: String
    ) -> [String] {
        var arguments: [String] = [courseCode, String(sectionNumber)]
        if destination.type == "local_folder" {
            arguments.append("--to-folder")
            arguments.append(destination.path)
            return arguments
        }
        if destination.type == "cloudflare_pages" {
            arguments.append("--target")
            arguments.append("cloudflare")
            // The launcher can discover the account from some tokens and
            // remembers it afterwards, but a token scoped only to Pages
            // cannot list its own account — so the app hands over what the
            // teacher gave it rather than leaving a console prompt that
            // nothing here can answer.
            let identifier: String = cloudflareAccountID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !identifier.isEmpty {
                arguments.append("--account")
                arguments.append(identifier)
            }
        }
        return arguments
    }

    /// The arguments for one section's deploy, to this course's PRIMARY
    /// destination only — a thin wrapper over the destination-aware
    /// function above, kept for every caller that still means "the one
    /// place this course deploys."
    static func arguments(
        courseCode: String,
        sectionNumber: Int,
        configuration: CourseConfiguration,
        cloudflareAccountID: String
    ) -> [String] {
        return arguments(
            courseCode: courseCode,
            sectionNumber: sectionNumber,
            destination: CourseConfiguration.DeployDestination(
                type: configuration.deployTarget, path: configuration.deployFolderPath
            ),
            cloudflareAccountID: cloudflareAccountID
        )
    }

    /// Where a destination deploys to, in the teacher's words.
    static func destinationDescription(for destination: CourseConfiguration.DeployDestination) -> String {
        if destination.type == "local_folder" {
            return destination.path
        }
        if destination.type == "cloudflare_pages" {
            return "Cloudflare Pages"
        }
        return "Netlify"
    }

    /// Where this course's PRIMARY destination deploys to, in the
    /// teacher's words.
    static func destinationDescription(for configuration: CourseConfiguration) -> String {
        return destinationDescription(for: CourseConfiguration.DeployDestination(
            type: configuration.deployTarget, path: configuration.deployFolderPath
        ))
    }

    /// The marker file `deploy.py` writes the first time a section goes out
    /// to a given destination TYPE, or nil for a destination that keeps
    /// none.
    ///
    /// It is the honest answer to "has this section ever been deployed
    /// HERE?" — `deploy.py` reads it to reuse the site rather than asking
    /// what to call a new one. A folder deploy asks nothing, so it has no
    /// marker. Marker files are keyed purely by destination TYPE
    /// (`.netlify_sites/`, `.cloudflare_sites/`), never by whether that
    /// type happens to be this course's primary or an additional target —
    /// `deploy.py` itself has never known the difference, so an additional
    /// Cloudflare target reuses the identical marker path a primary
    /// Cloudflare target would.
    static func firstDeployMarkerURL(
        forSection sectionNumber: Int,
        in course: Course,
        destinationType: String
    ) -> URL? {
        if destinationType == "local_folder" {
            return nil
        }
        let folderName: String = destinationType == "cloudflare_pages" ? ".cloudflare_sites" : ".netlify_sites"
        return course.directoryURL
            .appendingPathComponent(folderName)
            .appendingPathComponent("section\(sectionNumber).json")
    }

    /// The marker file for this course's PRIMARY destination — a thin
    /// wrapper over the destination-aware function above.
    static func firstDeployMarkerURL(
        forSection sectionNumber: Int,
        in course: Course
    ) -> URL? {
        return firstDeployMarkerURL(
            forSection: sectionNumber, in: course, destinationType: course.configuration.deployTarget
        )
    }

    /// True when this section has been deployed to the given destination
    /// TYPE at least once, so a deploy to it asks the teacher nothing.
    static func hasDeployedBefore(section sectionNumber: Int, in course: Course, destinationType: String) -> Bool {
        guard let markerURL = firstDeployMarkerURL(forSection: sectionNumber, in: course, destinationType: destinationType) else {
            return true
        }
        return FileManager.default.fileExists(atPath: markerURL.path)
    }

    /// True when this section has been deployed to its PRIMARY destination
    /// at least once — a thin wrapper over the destination-aware function
    /// above.
    static func hasDeployedBefore(section sectionNumber: Int, in course: Course) -> Bool {
        return hasDeployedBefore(section: sectionNumber, in: course, destinationType: course.configuration.deployTarget)
    }
}

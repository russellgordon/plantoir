import XCTest
@testable import QuartzTeachers

/// A section's custom domain: stored per section AND per destination
/// TYPE, cleaned on entry, and worn by that destination's own live-site
/// link in place of the address it would otherwise be assigned.
final class CustomDomainTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    func testTheDomainIsStoredPerSectionAndPerDestinationAndSurvivesARoundTrip() throws {
        let folderURL: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("domain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let configJSON: [String: Any] = ["course_code": "ICS3U", "section_numbers": [1, 2]]
        let configURL: URL = folderURL.appendingPathComponent("course_config.json")
        try JSONSerialization.data(withJSONObject: configJSON).write(to: configURL)

        let configuration: CourseConfiguration = try CourseConfiguration(contentsOf: configURL)
        XCTAssertEqual(configuration.customDomain(forSection: 1, destinationType: "netlify"), "", "No domain until one is set")

        configuration.setCustomDomain("ics3u.school.ca", forSection: 1, destinationType: "netlify")
        try configuration.write(to: configURL)

        let reloaded: CourseConfiguration = try CourseConfiguration(contentsOf: configURL)
        XCTAssertEqual(reloaded.customDomain(forSection: 1, destinationType: "netlify"), "ics3u.school.ca")
        XCTAssertEqual(reloaded.customDomain(forSection: 2, destinationType: "netlify"), "", "Each section has its own domain")
    }

    /// The actual bug this per-destination shape exists to fix: a domain
    /// meant for Netlify must never be readable — and so never applied —
    /// for the Cloudflare Pages leg of the same section.
    @MainActor
    func testDomainsAreIsolatedPerDestinationType() throws {
        let folderURL: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("domain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let configJSON: [String: Any] = ["course_code": "ICS3U", "section_numbers": [1], "deploy_target": "netlify"]
        let configURL: URL = folderURL.appendingPathComponent("course_config.json")
        try JSONSerialization.data(withJSONObject: configJSON).write(to: configURL)
        let configuration: CourseConfiguration = try CourseConfiguration(contentsOf: configURL)

        configuration.setCustomDomain("ics3u-netlify.school.ca", forSection: 1, destinationType: "netlify")
        XCTAssertEqual(configuration.customDomain(forSection: 1, destinationType: "netlify"), "ics3u-netlify.school.ca")
        XCTAssertEqual(
            configuration.customDomain(forSection: 1, destinationType: "cloudflare_pages"), "",
            "A Netlify domain must never leak onto the Cloudflare Pages destination's own link"
        )

        configuration.setCustomDomain("ics3u.school.ca", forSection: 1, destinationType: "cloudflare_pages")
        XCTAssertEqual(configuration.customDomain(forSection: 1, destinationType: "netlify"), "ics3u-netlify.school.ca", "Setting the second type must not disturb the first")
        XCTAssertEqual(configuration.customDomain(forSection: 1, destinationType: "cloudflare_pages"), "ics3u.school.ca")
    }

    /// `custom_domains.sections.sectionN` used to be a bare string, written
    /// before a course could have more than one destination — read as the
    /// PRIMARY destination's own domain, since that was the only
    /// destination that could have set it.
    @MainActor
    func testAnOldBareStringIsReadAsThePrimaryDestinationsDomain() throws {
        let folderURL: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("domain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let configJSON: [String: Any] = [
            "course_code": "ICS3U", "section_numbers": [1],
            "deploy_target": "netlify",
            "custom_domains": ["sections": ["section1": "ics3u.school.ca"]],
        ]
        let configURL: URL = folderURL.appendingPathComponent("course_config.json")
        try JSONSerialization.data(withJSONObject: configJSON).write(to: configURL)
        let configuration: CourseConfiguration = try CourseConfiguration(contentsOf: configURL)

        XCTAssertEqual(configuration.customDomain(forSection: 1, destinationType: "netlify"), "ics3u.school.ca")
        XCTAssertEqual(
            configuration.customDomain(forSection: 1, destinationType: "cloudflare_pages"), "",
            "An old bare-string domain belongs to the primary destination only, never any other type"
        )
    }

    /// Setting a domain for a SECOND destination must not silently discard
    /// an old bare-string domain that was already there for the primary —
    /// it is migrated into the new per-type shape instead.
    @MainActor
    func testSettingASecondDestinationsDomainMigratesAnOldStringRatherThanDiscardingIt() throws {
        let folderURL: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("domain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let configJSON: [String: Any] = [
            "course_code": "ICS3U", "section_numbers": [1],
            "deploy_target": "netlify",
            "custom_domains": ["sections": ["section1": "ics3u-netlify.school.ca"]],
        ]
        let configURL: URL = folderURL.appendingPathComponent("course_config.json")
        try JSONSerialization.data(withJSONObject: configJSON).write(to: configURL)
        let configuration: CourseConfiguration = try CourseConfiguration(contentsOf: configURL)

        configuration.setCustomDomain("ics3u-cloudflare.school.ca", forSection: 1, destinationType: "cloudflare_pages")

        XCTAssertEqual(
            configuration.customDomain(forSection: 1, destinationType: "netlify"), "ics3u-netlify.school.ca",
            "The old string's domain must survive, now addressable by the primary's own type"
        )
        XCTAssertEqual(configuration.customDomain(forSection: 1, destinationType: "cloudflare_pages"), "ics3u-cloudflare.school.ca")
    }

    @MainActor
    func testAPastedAddressIsReducedToJustTheDomain() {
        XCTAssertEqual(CourseConfiguration.normalizedCustomDomain("https://ics3u.school.ca/"), "ics3u.school.ca")
        XCTAssertEqual(CourseConfiguration.normalizedCustomDomain("http://ics3u.school.ca/some/page"), "ics3u.school.ca")
        XCTAssertEqual(CourseConfiguration.normalizedCustomDomain("  ics3u.school.ca  "), "ics3u.school.ca")
        XCTAssertEqual(CourseConfiguration.normalizedCustomDomain("ics3u.school.ca"), "ics3u.school.ca")
        XCTAssertEqual(CourseConfiguration.normalizedCustomDomain(""), "")
    }

    @MainActor
    func testTheLiveSiteLinkWearsTheCustomDomain() throws {
        let netlifyURL: URL = try XCTUnwrap(URL(string: "https://seedbed-example-course.netlify.app"))

        let dressed: URL = ScriptRunner.applyingCustomDomain("ics3u.school.ca", to: netlifyURL)
        XCTAssertEqual(dressed.absoluteString, "https://ics3u.school.ca")

        // A path on the site survives the swap.
        let deepURL: URL = try XCTUnwrap(URL(string: "https://seedbed-example-course.netlify.app/Curriculum"))
        XCTAssertEqual(ScriptRunner.applyingCustomDomain("ics3u.school.ca", to: deepURL).absoluteString,
                       "https://ics3u.school.ca/Curriculum")

        // No domain set: the address passes through untouched.
        XCTAssertEqual(ScriptRunner.applyingCustomDomain(nil, to: netlifyURL), netlifyURL)
        XCTAssertEqual(ScriptRunner.applyingCustomDomain("", to: netlifyURL), netlifyURL)

        // A plain-http address is promoted to https on the teacher's domain.
        let httpURL: URL = try XCTUnwrap(URL(string: "http://seedbed-example-course.netlify.app"))
        XCTAssertEqual(ScriptRunner.applyingCustomDomain("ics3u.school.ca", to: httpURL).absoluteString,
                       "https://ics3u.school.ca")
    }

    /// The runner end to end: a deploy transcript announcing a Netlify
    /// address shows the teacher's domain when one is set.
    @MainActor
    func testARunnersPublishedLinkUsesTheDomain() {
        let runner: ScriptRunner = ScriptRunner()
        runner.transcript.append(rawText: "Site URL: https://seedbed-example-course.netlify.app\r\n")

        XCTAssertEqual(runner.publishedSiteURL?.absoluteString, "https://seedbed-example-course.netlify.app",
                       "Without a custom domain the Netlify address shows")

        runner.customDomainForLinks = "ics3u.school.ca"
        XCTAssertEqual(runner.publishedSiteURL?.absoluteString, "https://ics3u.school.ca")
    }
}

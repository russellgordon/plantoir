import XCTest
@testable import QuartzTeachers

/// The "Advanced" custom-domain field's own wording — one field per
/// destination that can have a domain, labelled by service name only once
/// there is more than one to tell apart.
final class SectionSettingsViewTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    func testASingleDestinationCourseKeepsThePlainLabel() {
        let label: String = SectionSettingsView.customDomainFieldLabel(
            destination: CourseConfiguration.DeployDestination(type: "netlify", path: ""),
            destinationCount: 1
        )
        XCTAssertEqual(label, "Custom domain", "The overwhelming majority of courses see the field they always have")
    }

    @MainActor
    func testAMultiDestinationCourseNamesWhichServiceEachFieldIsFor() {
        let netlifyLabel: String = SectionSettingsView.customDomainFieldLabel(
            destination: CourseConfiguration.DeployDestination(type: "netlify", path: ""),
            destinationCount: 2
        )
        XCTAssertEqual(netlifyLabel, "Netlify custom domain")

        let cloudflareLabel: String = SectionSettingsView.customDomainFieldLabel(
            destination: CourseConfiguration.DeployDestination(type: "cloudflare_pages", path: ""),
            destinationCount: 2
        )
        XCTAssertEqual(cloudflareLabel, "Cloudflare Pages custom domain")
    }

    @MainActor
    func testTheCaptionNamesTheActualServiceEvenForASingleDestination() {
        // Regression: the OLD caption said "Netlify address"
        // unconditionally, even for a course whose one destination was
        // Cloudflare Pages — a wrong host name shown to every such teacher.
        XCTAssertTrue(
            SectionSettingsView.customDomainCaption(forDestinationType: "cloudflare_pages").contains("Cloudflare Pages address"),
            "A Cloudflare-only course must not be told to leave the field empty to use \"the Netlify address\""
        )
        XCTAssertFalse(SectionSettingsView.customDomainCaption(forDestinationType: "cloudflare_pages").contains("Netlify"))
    }

    @MainActor
    func testTheCaptionNamesNetlifyForANetlifyDestination() {
        let caption: String = SectionSettingsView.customDomainCaption(forDestinationType: "netlify")
        XCTAssertTrue(caption.contains("Netlify address"))
        XCTAssertFalse(caption.contains("Cloudflare"))
    }
}

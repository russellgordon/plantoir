import XCTest
@testable import QuartzTeachers

/// Runs `contracts/toolchain.json` against the real `Dockerfile` and `patches/`.
///
/// **Why an app test guards the image.** Neither app can change these — the
/// launchers build the image from the recipe and tag it by a hash of the whole
/// context — but both apps DEPEND on them, and the reasons are invisible from
/// the version numbers. `wrangler@4.80.0` looks like something to bump; it is
/// pinned below 4.100 because 4.100 needs Node 22 while the image ships Node 20,
/// which is what Quartz v4.5.0 is known-good against. Raising either for a good
/// local reason breaks every teacher's site build, and the person doing it will
/// be reading the Dockerfile, not this contract — so the test names the reason
/// in its failure.
final class ToolchainContractTests: XCTestCase {

    // MARK: - The pins

    func testTheDockerfileStillCarriesThePinnedVersions() throws {
        let recipe: String = try ToolchainContractTests.read("Dockerfile")
        for pin in try ToolchainContractTests.array("pins") {
            let name: String = try XCTUnwrap(pin["pin"] as? String)
            let value: String = try XCTUnwrap(pin["value"] as? String)
            let why: String = (pin["why"] as? String) ?? ""

            // A pin that says where to look for itself needs no case here, so
            // the next one costs a contract entry rather than a code change
            // on two platforms.
            if let expected = pin["dockerfileContains"] as? String {
                XCTAssertTrue(recipe.contains(expected), "\(name): \(why)")
                continue
            }

            switch name {
            case "baseImage":
                XCTAssertTrue(recipe.contains("FROM \(value)"), "\(name): \(why)")
            case "node":
                XCTAssertTrue(recipe.contains("setup_\(value).x"), "\(name): \(why)")
            case "wrangler":
                XCTAssertTrue(recipe.contains("wrangler@\(value)"), "\(name): \(why)")
            case "quartz":
                XCTAssertTrue(recipe.contains("--branch \(value)"), "\(name): \(why)")
            default:
                XCTFail("The contract names a pin this test does not know how to check: \(name)")
            }
        }
    }

    /// The pin with a rule attached rather than just a number.
    func testWranglerStaysBelowTheVersionThatNeedsNode22() throws {
        var pinned: String = ""
        var ceiling: String = ""
        for pin in try ToolchainContractTests.array("pins") where pin["pin"] as? String == "wrangler" {
            pinned = try XCTUnwrap(pin["value"] as? String)
            ceiling = try XCTUnwrap(pin["mustStayBelow"] as? String)
        }

        let pinnedParts: [Int] = ToolchainContractTests.numbers(in: pinned)
        let ceilingParts: [Int] = ToolchainContractTests.numbers(in: ceiling)
        XCTAssertEqual(pinnedParts.first, ceilingParts.first, "A different major version needs a rethink")
        XCTAssertLessThan(
            pinnedParts[1], ceilingParts[1],
            "wrangler \(pinned) is at or past \(ceiling), which requires Node 22 — and this image ships "
            + "Node 20 because that is what Quartz v4.5.0 is known-good against. Revalidate Quartz on a "
            + "newer Node BEFORE raising this."
        )
    }

    // MARK: - The patches

    /// Every patch the contract describes exists, and is still copied over the
    /// file it claims to replace.
    ///
    /// A patch that stops being copied does not fail anything: the image
    /// builds, the site builds, and stock Quartz behaviour quietly returns —
    /// which for `publish.ts` means publishing pages a teacher hid.
    func testEveryPatchIsRealAndStillApplied() throws {
        let recipe: String = try ToolchainContractTests.read("Dockerfile")
        let patchesDirectory: URL = ToolchainContractTests.repositoryRoot()
            .appendingPathComponent("patches")

        var described: Set<String> = []
        for patch in try ToolchainContractTests.array("patches") {
            let file: String = try XCTUnwrap(patch["file"] as? String)
            let replaces: String = try XCTUnwrap(patch["replaces"] as? String)
            described.insert(file)

            XCTAssertTrue(
                FileManager.default.fileExists(atPath: patchesDirectory.appendingPathComponent(file).path),
                "contracts/toolchain.json describes patches/\(file), which is not there."
            )
            XCTAssertTrue(
                recipe.contains("COPY patches/\(file)") && recipe.contains(replaces),
                "patches/\(file) is no longer copied over \(replaces). "
                + "\((patch["cannotBeDropped"] as? String) ?? "")"
            )
        }

        // And nothing has been added to patches/ without being described —
        // an undescribed patch is a behaviour the other platform cannot know
        // it depends on.
        for file in try FileManager.default.contentsOfDirectory(atPath: patchesDirectory.path)
        where !file.hasPrefix(".") {
            XCTAssertTrue(
                described.contains(file),
                "patches/\(file) exists and contracts/toolchain.json does not describe it. Say what it "
                + "changes and why it cannot be dropped."
            )
        }
    }

    /// The one whose absence is silent AND consequential.
    func testThePublishFilterStillDefaultsToVisible() throws {
        let filter: String = try ToolchainContractTests.read("patches/publish.ts")
        XCTAssertTrue(filter.contains("frontmatter?.publish"), "It must read the teacher's own word")
        XCTAssertTrue(
            filter.contains("!(flag === false || flag === \"false\")"),
            "A page is published UNLESS it says publish: false. Flipping this default hides every page "
            + "written before the flag existed — 60 of 225 in the example course, curriculum included."
        )
    }

    // MARK: - Private

    private static func numbers(in version: String) -> [Int] {
        var parts: [Int] = []
        for piece in version.split(separator: ".") {
            parts.append(Int(piece) ?? 0)
        }
        while parts.count < 3 {
            parts.append(0)
        }
        return parts
    }

    private static func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private static func read(_ relativePath: String) throws -> String {
        return try String(
            contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8
        )
    }

    private static func array(_ key: String) throws -> [[String: Any]] {
        let url: URL = repositoryRoot().appendingPathComponent("contracts/toolchain.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        return try XCTUnwrap(all[key] as? [[String: Any]], "No \(key) in toolchain.json")
    }
}

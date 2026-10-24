import XCTest
@testable import QuartzTeachers

/// Runs `contracts/toolchain.json` against the real `Dockerfile` and `patches/`.
///
/// **Why an app test guards the image.** Neither app can change these — the
/// launchers build the image from the recipe and tag it by a hash of the whole
/// context — but both apps DEPEND on them, and the reasons are invisible from
/// the version numbers. `wrangler@4.80.0` looks like something to bump; it is
/// pinned below 4.87 because 4.87.0 is the first wrangler whose engines need
/// Node 22, and while the image runs Node 22 since #640, the pin is shared with
/// Windows, whose runtime stays on Node 20 until its own issue lands. The other
/// direction matters too: the image's Node must satisfy wrangler's own engines,
/// or publishing to Cloudflare breaks with every site build still green.
/// Raising either for a good local reason can break every teacher's site build
/// or publish, and the person doing it will be reading the Dockerfile, not this
/// contract — so the test names the reason in its failure.
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
                // The two fields must say the same thing, or a pin could be
                // raised in `value` and still pass because the line it
                // watches for never mentioned the version.
                XCTAssertTrue(
                    expected.contains(value),
                    "\(name): the contract watches the Dockerfile for \"\(expected)\", which does "
                    + "not carry the pinned version \(value). \(why)"
                )
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
    func testWranglerStaysBelowTheVersionWindowsNode20CannotRun() throws {
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
            "wrangler \(pinned) is at or past \(ceiling), whose engines require Node 22. The image runs "
            + "Node 22 (#640), but the pin is shared with Windows, whose runtime still ships Node 20. Move "
            + "Windows' runtime to Node 22 BEFORE raising this, and retire mustStayBelow on both platforms then."
        )
    }

    /// The other direction: the image's Node must satisfy wrangler's own
    /// `engines.node`, which the contract records as `nodeEngine` and verify.sh
    /// reads back out of the image. A Node pin lowered below it, or a wrangler
    /// raised past it, breaks publishing to Cloudflare while every site build
    /// stays green.
    func testTheImagesNodeSatisfiesWranglersEngines() throws {
        var nodeVersion: String = ""
        var engine: String = ""
        for pin in try ToolchainContractTests.array("pins") {
            let name: String = (pin["pin"] as? String) ?? ""
            if name == "node" {
                nodeVersion = try XCTUnwrap(pin["value"] as? String)
            }
            if name == "wrangler" {
                engine = try XCTUnwrap(
                    pin["nodeEngine"] as? String,
                    "The wrangler pin must say which Node its engines need (nodeEngine), as wrangler's "
                    + "own package.json does."
                )
            }
        }

        // Only the one shape wrangler has ever used is understood. Anything
        // else fails loudly rather than being compared wrongly.
        XCTAssertTrue(
            engine.hasPrefix(">="),
            "wrangler's nodeEngine is \"\(engine)\"; this test understands only \">=X.Y.Z\"."
        )
        let floor: [Int] = ToolchainContractTests.numbers(in: String(engine.dropFirst(2)))
        let node: [Int] = ToolchainContractTests.numbers(in: nodeVersion)

        var nodeIsAtLeastTheFloor: Bool = true
        for position in 0..<3 {
            if node[position] > floor[position] {
                break
            }
            if node[position] < floor[position] {
                nodeIsAtLeastTheFloor = false
                break
            }
        }
        XCTAssertTrue(
            nodeIsAtLeastTheFloor,
            "The image runs Node \(nodeVersion), but wrangler's engines need \(engine): publishing to "
            + "Cloudflare would break. Raise Node, or keep wrangler at a version whose engines it satisfies."
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

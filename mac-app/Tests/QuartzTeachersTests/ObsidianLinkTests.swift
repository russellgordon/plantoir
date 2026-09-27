import XCTest
@testable import QuartzTeachers

/// The obsidian:// link that opens a course or section folder as a vault.
final class ObsidianLinkTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    func testTheLinkCarriesTheFullPathEncoded() throws {
        let folder: URL = URL(fileURLWithPath: "/Users/teacher/Desktop/Class Websites/courses/ICS3U/section2")
        let link: URL = try XCTUnwrap(FolderActions.obsidianURL(forFolder: folder))

        XCTAssertEqual(link.scheme, "obsidian")
        XCTAssertEqual(link.host, "open")
        XCTAssertEqual(link.absoluteString,
                       "obsidian://open?path=/Users/teacher/Desktop/Class%20Websites/courses/ICS3U/section2",
                       "Spaces in the path must be percent-encoded or Obsidian gets a broken path")

        // And the path survives the round trip exactly.
        let components: URLComponents = try XCTUnwrap(URLComponents(url: link, resolvingAgainstBaseURL: false))
        var pathValue: String?
        for item in components.queryItems ?? [] {
            if item.name == "path" {
                pathValue = item.value
            }
        }
        XCTAssertEqual(pathValue, folder.path)
    }

    /// Obsidian opens files, not folders: a section is represented by its
    /// landing page, and a section without one falls back to the vault.
    @MainActor
    func testASectionOpensAtItsLandingPage() throws {
        let vault: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("vault-\(UUID().uuidString)")
        let section: URL = vault.appendingPathComponent("section6")
        try FileManager.default.createDirectory(at: section, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        // No landing page yet: fall back to the vault, never the bare
        // folder — handing Obsidian a folder gets "File not found".
        XCTAssertEqual(FolderActions.obsidianTarget(forFolder: section, vaultURL: vault), vault)

        try "---\ntitle: Section 6\n---".write(to: section.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)
        XCTAssertEqual(FolderActions.obsidianTarget(forFolder: section, vaultURL: vault),
                       section.appendingPathComponent("index.md"))

        // The vault's own folder passes through: a path that IS a vault
        // opens that vault.
        XCTAssertEqual(FolderActions.obsidianTarget(forFolder: vault, vaultURL: vault), vault)
    }

    /// Auto-reveal is flipped on in the saved layout without disturbing
    /// anything else in it.
    @MainActor
    func testAutoRevealIsEnabledAndTheRestOfTheLayoutSurvives() throws {
        let layout: [String: Any] = [
            "main": ["id": "m1", "type": "split"],
            "left": [
                "type": "split",
                "children": [
                    [
                        "type": "tabs",
                        "children": [
                            [
                                "type": "leaf",
                                "state": [
                                    "type": "file-explorer",
                                    "state": ["sortOrder": "alphabetical", "autoReveal": false],
                                    "icon": "lucide-folder-closed",
                                ],
                            ],
                            [
                                "type": "leaf",
                                "state": ["type": "search", "state": ["query": "keep me"]],
                            ],
                        ],
                    ],
                ],
            ],
            "active": "m1",
        ]

        let improved: [String: Any] = try XCTUnwrap(FolderActions.layoutEnablingAutoReveal(layout) as? [String: Any])

        let left: [String: Any] = try XCTUnwrap(improved["left"] as? [String: Any])
        let tabs: [String: Any] = try XCTUnwrap((left["children"] as? [Any])?.first as? [String: Any])
        let leaves: [Any] = try XCTUnwrap(tabs["children"] as? [Any])
        let explorer: [String: Any] = try XCTUnwrap(leaves[0] as? [String: Any])
        let explorerState: [String: Any] = try XCTUnwrap(explorer["state"] as? [String: Any])
        let innerState: [String: Any] = try XCTUnwrap(explorerState["state"] as? [String: Any])
        XCTAssertEqual(innerState["autoReveal"] as? Bool, true)
        XCTAssertEqual(innerState["sortOrder"] as? String, "alphabetical", "The teacher's sort order survives")

        let search: [String: Any] = try XCTUnwrap(leaves[1] as? [String: Any])
        let searchState: [String: Any] = try XCTUnwrap(search["state"] as? [String: Any])
        let searchInner: [String: Any] = try XCTUnwrap(searchState["state"] as? [String: Any])
        XCTAssertEqual(searchInner["query"] as? String, "keep me", "Other leaves are untouched")
        XCTAssertEqual(improved["active"] as? String, "m1")
    }

    /// The registry Obsidian keeps: a folder counts as "in a vault" when a
    /// registered vault IS the folder or contains it.
    @MainActor
    func testRecognizingAFolderInsideARegisteredVault() throws {
        let registry: [String: Any] = [
            "vaults": [
                "abc123": ["path": "/Users/teacher/Desktop/Class Websites/courses/ICS3U", "ts": 1],
            ],
        ]
        let data: Data = try JSONSerialization.data(withJSONObject: registry)

        XCTAssertTrue(FolderActions.folderIsInRegisteredVault(
            "/Users/teacher/Desktop/Class Websites/courses/ICS3U", registryData: data))
        XCTAssertTrue(FolderActions.folderIsInRegisteredVault(
            "/Users/teacher/Desktop/Class Websites/courses/ICS3U/section2", registryData: data))
        XCTAssertFalse(FolderActions.folderIsInRegisteredVault(
            "/Users/teacher/Desktop/Class Websites/courses/ICS3UOTHER", registryData: data),
            "A sibling folder whose name merely starts the same is NOT inside the vault")
        XCTAssertFalse(FolderActions.folderIsInRegisteredVault(
            "/Users/teacher/Desktop/temp/courses/EXC2O", registryData: data))
        XCTAssertFalse(FolderActions.folderIsInRegisteredVault(
            "/Users/teacher/anything", registryData: nil),
            "No registry at all means nothing is registered")
    }

    /// Registering adds one vault and loses none of the teacher's own.
    @MainActor
    func testRegisteringAVaultPreservesTheExistingOnes() throws {
        let registry: [String: Any] = [
            "vaults": [
                "abc123": ["path": "/Users/teacher/Existing Vault", "ts": 1, "open": true],
            ],
        ]
        let before: Data = try JSONSerialization.data(withJSONObject: registry)
        let after: Data = try XCTUnwrap(FolderActions.registryData(
            afterRegisteringVaultAt: "/Users/teacher/Desktop/temp/courses/EXC2O",
            in: before,
            identifier: "def456",
            timestamp: 99
        ))

        let decoded: [String: Any] = try XCTUnwrap(JSONSerialization.jsonObject(with: after) as? [String: Any])
        let vaults: [String: Any] = try XCTUnwrap(decoded["vaults"] as? [String: Any])
        XCTAssertEqual(vaults.count, 2, "The existing vault survives")
        let added: [String: Any] = try XCTUnwrap(vaults["def456"] as? [String: Any])
        XCTAssertEqual(added["path"] as? String, "/Users/teacher/Desktop/temp/courses/EXC2O")
        XCTAssertEqual(added["ts"] as? Int, 99)
        let kept: [String: Any] = try XCTUnwrap(vaults["abc123"] as? [String: Any])
        XCTAssertEqual(kept["open"] as? Bool, true, "Even keys we do not use are preserved")
    }

    /// A Mac where Obsidian has never written a registry still works: the
    /// registry is built from nothing.
    @MainActor
    func testRegisteringIntoAnEmptyRegistry() throws {
        let after: Data = try XCTUnwrap(FolderActions.registryData(
            afterRegisteringVaultAt: "/Users/teacher/courses/SNC1W",
            in: nil,
            identifier: "aaa111",
            timestamp: 5
        ))
        let decoded: [String: Any] = try XCTUnwrap(JSONSerialization.jsonObject(with: after) as? [String: Any])
        let vaults: [String: Any] = try XCTUnwrap(decoded["vaults"] as? [String: Any])
        XCTAssertEqual(vaults.count, 1)
    }

    // MARK: - Which vaults are open, and what a rename does to them

    /// Obsidian marks the vault it opens and does NOT unmark it on quit, so
    /// the mark answers "opened last", never "open now". Measured on a real
    /// machine: a vault carried `"open": true` for hours while Obsidian was
    /// closed. Anything that acts on the mark has to check that Obsidian is
    /// running as well, and `openVaultPathsNow` is where that pairing lives.
    @MainActor
    func testTheOpenMarkIsReadFromTheRegistryAndSorted() throws {
        let registry: [String: Any] = [
            "vaults": [
                "aaa": ["path": "/Users/t/Desktop/courses/ICS3U", "ts": 1, "open": true],
                "bbb": ["path": "/Users/t/Desktop/courses/MPM2D", "ts": 2],
                "ccc": ["path": "/Users/t/Notes", "ts": 3, "open": true],
            ],
        ]
        let data: Data = try JSONSerialization.data(withJSONObject: registry)

        XCTAssertEqual(
            FolderActions.openVaultPaths(registryData: data),
            ["/Users/t/Desktop/courses/ICS3U", "/Users/t/Notes"],
            "Only the marked ones, in a settled order so reopening is predictable"
        )
        XCTAssertEqual(FolderActions.openVaultPaths(registryData: nil), [])
        XCTAssertEqual(FolderActions.openVaultPaths(registryData: Data("not json".utf8)), [])
    }

    /// The pairing itself: with Obsidian closed the answer is nothing at
    /// all, whatever the registry still says.
    @MainActor
    func testNothingIsOpenWhileObsidianIsNotRunning() {
        if FolderActions.obsidianIsRunning {
            // Nothing to prove on a machine that is using Obsidian right now.
            return
        }
        XCTAssertTrue(
            FolderActions.openVaultPathsNow.isEmpty,
            "A stale mark in the registry must not be read as an open vault"
        )
    }

    /// The mark also survives a vault being CLOSED while Obsidian keeps
    /// running — measured with every vault closed and Obsidian still up: no
    /// windows on screen, and one vault still marked open. So the marks are
    /// trusted only while Obsidian actually has a window.
    ///
    /// Conditional on the machine's state, and it asserts for real in exactly
    /// the state that was reported broken: Obsidian running, nothing open.
    @MainActor
    func testNothingIsOpenWhileObsidianHasNoWindowsOnScreen() {
        if !FolderActions.obsidianIsRunning {
            return
        }
        if FolderActions.obsidianWindowCount() > 0 {
            return
        }
        XCTAssertTrue(
            FolderActions.openVaultPathsNow.isEmpty,
            "A mark left behind by a CLOSED vault must not read as a vault that is open"
        )
    }

    /// Only a vault whose OWN root moves is stranded. A vault that contains
    /// the course — a teacher who opened the whole `courses` folder as one
    /// vault — is fine, because Obsidian follows a rename inside a vault
    /// perfectly well; it is the root moving out from under the watcher that
    /// breaks it.
    @MainActor
    func testWhichOpenVaultsARenameWouldStrand() {
        let course: String = "/Users/t/Desktop/courses/ICS3U"

        XCTAssertTrue(FolderActions.openVaultWouldBeStranded(
            byMoving: course, openVaultPaths: [course]
        ), "the course folder IS the vault")

        XCTAssertTrue(FolderActions.openVaultWouldBeStranded(
            byMoving: course, openVaultPaths: ["/Users/t/Desktop/courses/ICS3U/section1"]
        ), "a vault inside the course moves with it")

        XCTAssertFalse(FolderActions.openVaultWouldBeStranded(
            byMoving: course, openVaultPaths: ["/Users/t/Desktop/courses"]
        ), "a vault CONTAINING the course keeps its own root, and Obsidian follows the rename")

        XCTAssertFalse(FolderActions.openVaultWouldBeStranded(
            byMoving: course, openVaultPaths: ["/Users/t/Desktop/courses/ICS3U2"]
        ), "a longer name that merely starts the same way is a different course")

        XCTAssertFalse(FolderActions.openVaultWouldBeStranded(byMoving: course, openVaultPaths: []))
    }

    @MainActor
    func testAPathFollowsTheFolderThatMoved() {
        let old: String = "/Users/t/courses/ICS3U"
        let new: String = "/Users/t/courses/ICS4U"

        XCTAssertEqual(FolderActions.path(old, movedFrom: old, to: new), new)
        XCTAssertEqual(
            FolderActions.path(old + "/section1", movedFrom: old, to: new), new + "/section1"
        )
        XCTAssertEqual(
            FolderActions.path("/Users/t/courses/ICS3U2", movedFrom: old, to: new),
            "/Users/t/courses/ICS3U2",
            "a name that merely starts the same way is left alone"
        )
        XCTAssertEqual(FolderActions.path("/Users/t/Notes", movedFrom: old, to: new), "/Users/t/Notes")
    }

    /// The registry entry is REPOINTED rather than replaced: same
    /// identifier, same number of vaults, no dead entry left behind
    /// pointing at a folder that no longer exists.
    @MainActor
    func testRepointingAVaultKeepsItsEntryAndLeavesTheOthersAlone() throws {
        let old: String = "/Users/t/courses/ICS3U"
        let new: String = "/Users/t/courses/ICS4U"
        let registry: [String: Any] = [
            "vaults": [
                "aaa": ["path": old, "ts": 1, "open": true],
                "bbb": ["path": "/Users/t/Notes", "ts": 2],
            ],
            "openSchemes": ["something": true],
        ]
        let data: Data = try JSONSerialization.data(withJSONObject: registry)

        let moved: Data = try XCTUnwrap(
            FolderActions.registryData(afterMovingVaultsUnder: old, to: new, in: data)
        )
        let result: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: moved) as? [String: Any]
        )
        let vaults: [String: Any] = try XCTUnwrap(result["vaults"] as? [String: Any])

        XCTAssertEqual(vaults.count, 2, "no entry added, none removed")
        let renamed: [String: Any] = try XCTUnwrap(vaults["aaa"] as? [String: Any])
        XCTAssertEqual(renamed["path"] as? String, new)
        XCTAssertEqual(renamed["ts"] as? Int, 1, "everything else about the entry survives")
        XCTAssertEqual(renamed["open"] as? Bool, true)
        let untouched: [String: Any] = try XCTUnwrap(vaults["bbb"] as? [String: Any])
        XCTAssertEqual(untouched["path"] as? String, "/Users/t/Notes")
        XCTAssertNotNil(result["openSchemes"], "the rest of the registry is not ours to drop")

        XCTAssertNil(FolderActions.registryData(afterMovingVaultsUnder: old, to: new, in: nil))
    }

    /// The question names what will happen, and counts.
    @MainActor
    func testTheQuestionAsksAboutOneVaultOrSeveral() {
        XCTAssertTrue(
            CourseRenamer.obsidianQuestion(openVaultCount: 1).hasSuffix("and open it again."),
            CourseRenamer.obsidianQuestion(openVaultCount: 1)
        )
        XCTAssertTrue(
            CourseRenamer.obsidianQuestion(openVaultCount: 3).hasSuffix("and open your vaults again."),
            CourseRenamer.obsidianQuestion(openVaultCount: 3)
        )
    }

    /// A PAGE is its own target (#329): routed through `obsidianTarget`, which
    /// is for folders, it would look for `<page>/index.md`, find none, and
    /// open the vault instead of the How I Teach page.
    @MainActor
    func testAPageOpensAsItself() throws {
        let vault: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let page: URL = vault.appendingPathComponent("How I Teach.md")
        try "---\npublish: false\n---\n".write(to: page, atomically: true, encoding: .utf8)

        let target: URL = FolderActions.pageTarget(page, vaultURL: vault)
        XCTAssertEqual(target, page)
        let link: URL = try XCTUnwrap(FolderActions.obsidianURL(forFolder: target))
        XCTAssertTrue(link.absoluteString.hasSuffix("/How%20I%20Teach.md"), link.absoluteString)
    }
}


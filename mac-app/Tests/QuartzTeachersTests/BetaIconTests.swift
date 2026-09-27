import XCTest

/// `Plantoir-Beta.icon` — the icon the Debug build wears so it can be told
/// apart from the released app in the Dock — is GENERATED from
/// `Plantoir.icon` by `mac-app/make-beta-icon.py`. These tests fail when the
/// real icon has been edited and the script not re-run, so the development
/// copy never quietly shows an older plant than the one teachers get.
final class BetaIconTests: XCTestCase {

    // MARK: - Computed properties

    /// The mac-app folder, found from this file's own location.
    var macAppFolder: URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    var realIcon: URL {
        return macAppFolder.appendingPathComponent("Plantoir.icon")
    }

    var betaIcon: URL {
        return macAppFolder.appendingPathComponent("Plantoir-Beta.icon")
    }

    // MARK: - Functions

    /// Every drawing in the real icon is carried, byte for byte, by the Beta one.
    func testEveryDrawingIsCopiedUnchanged() throws {
        let realAssets: URL = realIcon.appendingPathComponent("Assets")
        let assetNames: [String] = try FileManager.default.contentsOfDirectory(atPath: realAssets.path)
        XCTAssertFalse(assetNames.isEmpty, "Plantoir.icon/Assets is empty")

        for assetName in assetNames {
            let realData: Data = try Data(contentsOf: realAssets.appendingPathComponent(assetName))
            let betaFile: URL = betaIcon.appendingPathComponent("Assets").appendingPathComponent(assetName)
            let betaData: Data? = try? Data(contentsOf: betaFile)
            XCTAssertEqual(
                betaData,
                realData,
                "\(assetName) differs between Plantoir.icon and Plantoir-Beta.icon — run python3 mac-app/make-beta-icon.py"
            )
        }
    }

    /// The Beta icon's document is the real one with the ribbon group added
    /// in front, and nothing else changed.
    func testDocumentIsTheRealOneWithTheRibbonInFront() throws {
        let realDocument: NSDictionary = try readDocument(of: realIcon)
        let betaDocument: NSMutableDictionary = try XCTUnwrap(readDocument(of: betaIcon).mutableCopy() as? NSMutableDictionary)

        let betaGroups: NSMutableArray = try XCTUnwrap((betaDocument["groups"] as? NSArray)?.mutableCopy() as? NSMutableArray)
        let frontGroup: NSDictionary = try XCTUnwrap(betaGroups.firstObject as? NSDictionary)
        let frontLayers: NSArray = try XCTUnwrap(frontGroup["layers"] as? NSArray)
        let ribbonLayer: NSDictionary = try XCTUnwrap(frontLayers.firstObject as? NSDictionary)
        XCTAssertEqual(ribbonLayer["image-name"] as? String, "beta-ribbon.svg")

        betaGroups.removeObject(at: 0)
        betaDocument["groups"] = betaGroups
        XCTAssertEqual(
            betaDocument,
            realDocument,
            "Plantoir.icon/icon.json has changed since Plantoir-Beta.icon was made — run python3 mac-app/make-beta-icon.py"
        )
    }

    func readDocument(of icon: URL) throws -> NSDictionary {
        let data: Data = try Data(contentsOf: icon.appendingPathComponent("icon.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }
}

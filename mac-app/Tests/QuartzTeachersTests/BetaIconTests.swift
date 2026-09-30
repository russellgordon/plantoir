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

    /// Which configuration wears which icon, read off `project.yml` in the
    /// style of `AppUpdatesStartTests`. The dangerous drift is not the art but
    /// this: `Plantoir-Beta` moved into the base settings, or the Release
    /// exclusion dropped, ships the ribbon to teachers and no other test
    /// notices. So: the base names `Plantoir`, Debug alone names
    /// `Plantoir-Beta`, and Release names nothing else and excludes the bundle.
    func testOnlyDebugNamesTheBetaIcon() throws {
        let projectFile: URL = macAppFolder.appendingPathComponent("project.yml")
        let text: String = try String(contentsOf: projectFile, encoding: .utf8)
        let lines: [String] = splitIntoLines(text)
        let iconKey: String = "ASSETCATALOG_COMPILER_APPICON_NAME"

        let debugLines: [String] = try XCTUnwrap(block(named: "Debug:", in: lines), "No Debug: block in project.yml")
        let releaseLines: [String] = try XCTUnwrap(block(named: "Release:", in: lines), "No Release: block in project.yml")

        XCTAssertEqual(value(of: iconKey, in: debugLines), "Plantoir-Beta", "Debug must wear the Beta icon")
        let releaseIcon: String? = value(of: iconKey, in: releaseLines)
        XCTAssertTrue(releaseIcon == nil || releaseIcon == "Plantoir", "Release names \(releaseIcon ?? "")")
        XCTAssertEqual(
            value(of: "EXCLUDED_SOURCE_FILE_NAMES", in: releaseLines),
            "Plantoir-Beta.icon",
            "Release must leave the Beta icon out of the bundle altogether"
        )

        // Every other line naming the icon is a base setting, and names the real one.
        var otherIconNames: [String] = []
        for line in lines {
            if debugLines.contains(line) {
                continue
            }
            if let named = value(of: iconKey, in: [line]) {
                otherIconNames.append(named)
            }
        }
        XCTAssertEqual(otherIconNames, ["Plantoir"], "The base setting must be the real icon, and only Debug may differ")
    }

    func splitIntoLines(_ text: String) -> [String] {
        var lines: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            lines.append(String(line))
        }
        return lines
    }

    /// The lines indented under the first line reading `header`, up to the
    /// next line indented no deeper than it. Comments and blank lines are skipped.
    func block(named header: String, in lines: [String]) -> [String]? {
        var headerIndent: Int? = nil
        var result: [String] = []
        for line in lines {
            let trimmed: String = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            let indent: Int = line.count - line.drop(while: { (character: Character) -> Bool in character == " " }).count
            if let opened = headerIndent {
                if indent <= opened {
                    return result
                }
                result.append(line)
            } else if trimmed == header {
                headerIndent = indent
            }
        }
        if headerIndent == nil {
            return nil
        }
        return result
    }

    /// The unquoted value of `key: value` on the first of `lines` that sets it.
    func value(of key: String, in lines: [String]) -> String? {
        for line in lines {
            let trimmed: String = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(key + ":") {
                let rest: String = String(trimmed.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
                return rest.replacingOccurrences(of: "\"", with: "")
            }
        }
        return nil
    }

    func readDocument(of icon: URL) throws -> NSDictionary {
        let data: Data = try Data(contentsOf: icon.appendingPathComponent("icon.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }
}

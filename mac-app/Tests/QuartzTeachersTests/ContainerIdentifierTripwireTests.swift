import XCTest

/// Every container whose identifier must NOT swallow its children's carries
/// `.accessibilityElement(children: .contain)` immediately BEFORE that
/// identifier (#366, the rule of #353).
///
/// SwiftUI applies an identifier on a stack to every element inside it, so a
/// button's own identifier never reaches the accessibility tree: the
/// start-of-year sheet's Cancel and Go both read back as "startOfYearSheet",
/// and no test could find Go. `.contain` fixes it only when it comes FIRST —
/// placed after the identifier it compiles and changes nothing, which is the
/// mistake this test exists for. The tree itself cannot be read in process
/// (#353, measured: it does not reach hosted SwiftUI), so this reads the
/// source; the opt-in `ContainerIdentifiersUITests` reads the real window.
///
/// The list is NAMED rather than discovered. A scan for "an identifier on a
/// stack" misses a container whose children come from a computed property —
/// the start-of-year sheet's buttons live in `buttons`, which is exactly how
/// #353's own sweep missed it. Add a container here when you give it an
/// identifier and it holds identified controls.
final class ContainerIdentifierTripwireTests: XCTestCase {

    // MARK: - Stored properties

    /// Containers known to hold controls with identifiers of their own.
    static let containersHoldingIdentifiedControls: [String] = [
        "startOfYearSheet",
        "stoppedPublishNotice",
        "credentialSheet",
        "cloudSyncNotice",
        "settingsSaveNotice",
        "copyPageResult",
    ]

    // MARK: - Functions

    private static func productFolder() -> URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("QuartzTeachers")
    }

    /// The source just before `position`, with trailing blank lines and
    /// whole-line `//` comments taken off — what the modifier chain says
    /// immediately before the identifier.
    static func chainBefore(_ position: String.Index, in text: String) -> String {
        let before: String = String(text[text.startIndex..<position])
        var lines: [String] = before.components(separatedBy: "\n")
        // The identifier's own line: whatever precedes `.accessibilityIdentifier(`
        // on it is part of the chain too.
        while let last = lines.last {
            let trimmed: String = last.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("//") {
                lines.removeLast()
            } else {
                break
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// For each use of `.accessibilityIdentifier("<identifier>")` in `text`,
    /// a complaint when the modifier just before it is not `.contain`.
    static func problems(forIdentifier identifier: String, in text: String, fileName: String) -> [String] {
        let marker: String = ".accessibilityIdentifier(\"\(identifier)\")"
        var found: [String] = []
        var searchStart: String.Index = text.startIndex
        while let range = text.range(of: marker, range: searchStart..<text.endIndex) {
            let chain: String = chainBefore(range.lowerBound, in: text)
            if !chain.hasSuffix(".accessibilityElement(children: .contain)") {
                let line: Int = text[text.startIndex..<range.lowerBound].components(separatedBy: "\n").count
                found.append("\(fileName):\(line) \(identifier)")
            }
            searchStart = range.upperBound
        }
        return found
    }

    // MARK: - Tests

    func testEveryNamedContainerKeepsItsChildrensIdentifiers() throws {
        let enumerator: FileManager.DirectoryEnumerator? = FileManager.default.enumerator(
            at: ContainerIdentifierTripwireTests.productFolder(), includingPropertiesForKeys: nil
        )
        var texts: [(name: String, text: String)] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.pathExtension != "swift" {
                continue
            }
            let text: String = try String(contentsOf: fileURL, encoding: .utf8)
            texts.append((name: fileURL.lastPathComponent, text: text))
        }
        XCTAssertGreaterThan(texts.count, 100, "Read too few product files — is the path right?")

        var offenders: [String] = []
        var stale: [String] = []
        for identifier in ContainerIdentifierTripwireTests.containersHoldingIdentifiedControls {
            var uses: Int = 0
            for file in texts {
                uses += file.text.components(separatedBy: ".accessibilityIdentifier(\"\(identifier)\")").count - 1
                let problems: [String] = ContainerIdentifierTripwireTests.problems(
                    forIdentifier: identifier, in: file.text, fileName: file.name
                )
                for problem in problems {
                    offenders.append(problem)
                }
            }
            // A name no product file uses any more is a stale entry: it would
            // pass for ever while checking nothing.
            if uses == 0 {
                stale.append(identifier)
            }
        }
        XCTAssertEqual(
            offenders, [],
            "An identifier on a container swallows its children's (#366, #353). Put "
            + ".accessibilityElement(children: .contain) IMMEDIATELY BEFORE .accessibilityIdentifier(…)."
        )
        XCTAssertEqual(stale, [], "No product file uses these identifiers any more — take them off the list.")
    }

    func testTheScanCatchesContainAfterTheIdentifierAndMissingContain() {
        let sample: String = """
        VStack { Button("Go") {}.accessibilityIdentifier("go") }
            .onAppear {
                load()
            }
            // a comment between is fine
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("good")
        HStack { }
            .accessibilityIdentifier("late")
            .accessibilityElement(children: .contain)
        HStack { }
            .padding()
            .accessibilityIdentifier("missing")
        """
        XCTAssertEqual(ContainerIdentifierTripwireTests.problems(forIdentifier: "good", in: sample, fileName: "S"), [])
        XCTAssertEqual(
            ContainerIdentifierTripwireTests.problems(forIdentifier: "late", in: sample, fileName: "S"), ["S:9 late"]
        )
        XCTAssertEqual(
            ContainerIdentifierTripwireTests.problems(forIdentifier: "missing", in: sample, fileName: "S"),
            ["S:13 missing"]
        )
    }
}

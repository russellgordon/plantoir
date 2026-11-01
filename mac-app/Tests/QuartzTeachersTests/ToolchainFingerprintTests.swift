import XCTest
@testable import QuartzTeachers

/// The mirror compares by fingerprint where it can (GitHub #663, the mac's
/// half of Windows #559): the bundle's manifest, `toolchain.hashes`, and the
/// working folder's index from the last pass.
///
/// The case this exists for: every file in the bundle carries a new time
/// after a rebuild or a full install, and the old mirror read all twelve
/// thousand of them twice to learn that none had changed. These tests build
/// a small bundle of their own (`copyToolchainFiles(into:from:indexFolder:)`)
/// so they can restamp it, take its files away, and make its manifest lie.
@MainActor
final class ToolchainFingerprintTests: XCTestCase {

    // MARK: - Stored properties

    var root: URL = URL(fileURLWithPath: "/")
    var bundle: URL = URL(fileURLWithPath: "/")
    var workingFolder: URL = URL(fileURLWithPath: "/")
    var indexFolder: URL = URL(fileURLWithPath: "/")

    /// The files the small bundle carries, as the manifest names them.
    let bundledFiles: [String] = [
        "Dockerfile",
        "setup.sh",
        "patches/one.patch",
        "scripts/build_site.py",
        "scripts/lib/helpers.py",
        "support/quartz/page.tsx",
        "contracts/app-rules.json",
    ]

    // MARK: - Computed properties

    var indexURL: URL {
        return ToolchainFingerprints.indexURL(forWorkingFolder: workingFolder, in: indexFolder)
    }

    // MARK: - Functions

    override func setUp() {
        super.setUp()
        // The suite's throwaway home (RealHomeTripwireTests): it is reached
        // through the /var symlink, which the mirror's relative paths and
        // `FolderIdentity.canonicalPath` both see through.
        root = RealHome.forFiles
            .appendingPathComponent("plantoir-fingerprint-test-\(UUID().uuidString)")
        bundle = root.appendingPathComponent("Resources")
        workingFolder = root.appendingPathComponent("working folder")
        indexFolder = root.appendingPathComponent("toolchain-index")
        try? FileManager.default.createDirectory(at: workingFolder, withIntermediateDirectories: true)
        for relative in bundledFiles {
            let url: URL = bundle.appendingPathComponent(relative)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? "first version of \(relative)\n".write(to: url, atomically: true, encoding: .utf8)
        }
        let created: URL = root
        let files: [String] = bundledFiles
        let bundleRoot: URL = bundle
        addTeardownBlock {
            // Readable again first, whatever a test did to them.
            for relative in files {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o644], ofItemAtPath: bundleRoot.appendingPathComponent(relative).path
                )
            }
            try? FileManager.default.removeItem(at: created)
        }
    }

    func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// What the build phase does: one line per bundled file, with the
    /// bundle's own length, time and hash.
    func writeManifest() throws {
        var entries: [String: ToolchainFingerprint] = [:]
        for relative in bundledFiles {
            let url: URL = bundle.appendingPathComponent(relative)
            let stamp: ToolchainFingerprints.Stamp = try XCTUnwrap(ToolchainFingerprints.stamp(of: url))
            let hash: String = try XCTUnwrap(ToolchainFingerprints.sha256(of: url))
            entries[relative] = ToolchainFingerprint(length: stamp.length, ticks: stamp.ticks, sha256: hash)
        }
        try ToolchainFingerprints.write(
            entries, to: bundle.appendingPathComponent(ToolchainFingerprints.manifestName)
        )
    }

    /// Every bundled file gets a new time and keeps its bytes — a rebuild,
    /// or a full install that restamped the recipe.
    func restampTheBundle(bySeconds seconds: TimeInterval) throws {
        for relative in bundledFiles {
            let url: URL = bundle.appendingPathComponent(relative)
            let date: Date = try XCTUnwrap(url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            try FileManager.default.setAttributes(
                [.modificationDate: date.addingTimeInterval(seconds)], ofItemAtPath: url.path
            )
        }
    }

    func mirror() -> WorkspaceModel.MirrorOutcome {
        return WorkspaceModel.copyToolchainFiles(into: workingFolder, from: bundle, indexFolder: indexFolder)
    }

    func copyOf(_ relative: String) throws -> String {
        return try String(
            contentsOf: workingFolder.appendingPathComponent(".toolchain").appendingPathComponent(relative),
            encoding: .utf8
        )
    }

    // MARK: - Comparing without reading

    /// MUST-FAIL on the pre-#663 `syncFile`, which read every same-length
    /// file whose time differed: with the bundle's files unreadable, every
    /// one of them failed. Now the manifest and the index answer, and the
    /// bundle's files are never opened.
    func testARestampedBundleIsComparedWithoutReading() throws {
        try writeManifest()
        let filled: WorkspaceModel.MirrorOutcome = mirror()
        XCTAssertEqual(filled.changed, bundledFiles.count)
        XCTAssertEqual(filled.failed, 0)
        XCTAssertEqual(filled.compared, 0, "A folder filled from nothing compared nothing")
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexURL.path), "A pass that failed nothing leaves an index")

        try restampTheBundle(bySeconds: 120)
        try writeManifest()
        for relative in bundledFiles {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o000], ofItemAtPath: bundle.appendingPathComponent(relative).path
            )
        }

        let outcome: WorkspaceModel.MirrorOutcome = mirror()
        XCTAssertEqual(outcome.failed, 0, "No bundled file should have been opened: \(outcome.firstFailure ?? "")")
        XCTAssertEqual(outcome.changed, 0)
        XCTAssertEqual(outcome.readInFull, 0)
        XCTAssertEqual(outcome.compared, bundledFiles.count)

        // The copies took the bundle's new times, so the next pass is the
        // cheap one by length and time.
        let again: WorkspaceModel.MirrorOutcome = mirror()
        XCTAssertEqual(again.failed, 0)
        XCTAssertEqual(again.readInFull, 0)
        XCTAssertEqual(again.compared, bundledFiles.count)
    }

    /// MUST-FAIL with the manifest's trust check removed. The bundle's file
    /// changed — same length, new time — and the manifest still carries the
    /// OLD hash, which is exactly the copy's. A manifest whose time no longer
    /// matches its file is not used, so the file is read and copied; trusting
    /// it would leave last week's script in the working folder.
    func testAStaleManifestDoesNotSkipTheCopy() throws {
        try writeManifest()
        _ = mirror()

        let changedFile: URL = bundle.appendingPathComponent("scripts/build_site.py")
        let before: String = try String(contentsOf: changedFile, encoding: .utf8)
        let after: String = String(repeating: "X", count: before.count)
        try write(after, to: changedFile)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(300)], ofItemAtPath: changedFile.path
        )

        let outcome: WorkspaceModel.MirrorOutcome = mirror()
        XCTAssertEqual(outcome.failed, 0)
        XCTAssertEqual(outcome.changed, 1)
        XCTAssertEqual(try copyOf("scripts/build_site.py"), after)
    }

    /// With no index (a folder this app has not mirrored before, or one whose
    /// index was lost), a trusted manifest still saves half the reading: the
    /// copy alone is hashed. The pass leaves an index, so the next restamp
    /// reads nothing.
    func testOnlyTheManifestIsTrustedReadsTheCopyOnce() throws {
        try writeManifest()
        _ = mirror()
        try FileManager.default.removeItem(at: indexURL)

        try restampTheBundle(bySeconds: 60)
        try writeManifest()
        let outcome: WorkspaceModel.MirrorOutcome = mirror()
        XCTAssertEqual(outcome.failed, 0)
        XCTAssertEqual(outcome.changed, 0)
        XCTAssertEqual(outcome.compared, bundledFiles.count)
        XCTAssertEqual(outcome.readInFull, bundledFiles.count, "Each copy hashed once")
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexURL.path))

        try restampTheBundle(bySeconds: 60)
        try writeManifest()
        let next: WorkspaceModel.MirrorOutcome = mirror()
        XCTAssertEqual(next.readInFull, 0)
        XCTAssertEqual(next.compared, bundledFiles.count)
    }

    /// A bundle with no manifest is compared exactly as before #663: both
    /// files read. The index still learns the copies from the bytes the pass
    /// had in hand, so a later bundle that does carry a manifest reads nothing.
    func testABundleWithNoManifestIsComparedAsBefore() throws {
        _ = mirror()
        try restampTheBundle(bySeconds: 60)

        let outcome: WorkspaceModel.MirrorOutcome = mirror()
        XCTAssertEqual(outcome.failed, 0)
        XCTAssertEqual(outcome.changed, 0)
        XCTAssertEqual(outcome.compared, bundledFiles.count)
        XCTAssertEqual(outcome.readInFull, bundledFiles.count)

        try restampTheBundle(bySeconds: 60)
        try writeManifest()
        let withAManifest: WorkspaceModel.MirrorOutcome = mirror()
        XCTAssertEqual(withAManifest.readInFull, 0)
        XCTAssertEqual(withAManifest.compared, bundledFiles.count)
    }

    /// MUST-FAIL without `keepWhatIsStillKnown`. A Sparkle delta keeps the
    /// old install's time on every file it does not change (measured: 12,865
    /// of 12,891 on 1.8.6 → 1.8.7), so the new build's manifest describes
    /// none of them and the cheap match by length and time compares them.
    /// The index must survive that pass, or the next FULL install — a DMG,
    /// or Sparkle without a delta, which restamps everything — hashes every
    /// copy again.
    func testAFullInstallAfterADeltaReadsNothing() throws {
        try writeManifest()
        _ = mirror()

        // The delta: one file changed (new bytes, new time); the others keep
        // their times; the manifest is the NEW build's, whose times are its
        // own build's and describe none of the files on disk.
        let changedFile: URL = bundle.appendingPathComponent("support/quartz/page.tsx")
        try write("second version, a different length\n", to: changedFile)
        var shifted: [String: ToolchainFingerprint] = [:]
        for relative in bundledFiles {
            let url: URL = bundle.appendingPathComponent(relative)
            let stamp: ToolchainFingerprints.Stamp = try XCTUnwrap(ToolchainFingerprints.stamp(of: url))
            let hash: String = try XCTUnwrap(ToolchainFingerprints.sha256(of: url))
            shifted[relative] = ToolchainFingerprint(
                length: stamp.length, ticks: stamp.ticks + 3_600 * ToolchainFingerprints.ticksPerSecond, sha256: hash
            )
        }
        try ToolchainFingerprints.write(shifted, to: bundle.appendingPathComponent(ToolchainFingerprints.manifestName))
        let afterTheDelta: WorkspaceModel.MirrorOutcome = mirror()
        XCTAssertEqual(afterTheDelta.failed, 0)
        XCTAssertEqual(afterTheDelta.changed, 1)
        XCTAssertEqual(afterTheDelta.readInFull, 0)

        // The full install: every file restamped, a manifest that describes them.
        try restampTheBundle(bySeconds: 600)
        try writeManifest()
        let afterTheFullInstall: WorkspaceModel.MirrorOutcome = mirror()
        XCTAssertEqual(afterTheFullInstall.failed, 0)
        XCTAssertEqual(afterTheFullInstall.changed, 0)
        XCTAssertEqual(afterTheFullInstall.compared, bundledFiles.count)
        XCTAssertEqual(afterTheFullInstall.readInFull, 0, "Every copy is still known to the index")
    }

    /// A copy edited in place — its own time moved, so the index no longer
    /// describes it — is hashed, found different, and copied over.
    func testACopyEditedInPlaceIsPutBack() throws {
        try writeManifest()
        _ = mirror()
        let copy: URL = workingFolder.appendingPathComponent(".toolchain/scripts/lib/helpers.py")
        let original: String = try String(contentsOf: copy, encoding: .utf8)
        try write(String(repeating: "Y", count: original.count), to: copy)

        try restampTheBundle(bySeconds: 60)
        try writeManifest()
        let outcome: WorkspaceModel.MirrorOutcome = mirror()
        XCTAssertEqual(outcome.failed, 0)
        XCTAssertEqual(outcome.changed, 1)
        XCTAssertEqual(outcome.readInFull, 1, "Only the copy whose time moved was read")
        XCTAssertEqual(try copyOf("scripts/lib/helpers.py"), original)
    }

    func testTheIndexIsNotWrittenWhenAPassFailed() throws {
        try writeManifest()
        // A folder where a file belongs: that one copy cannot be written.
        let blocker: URL = workingFolder.appendingPathComponent(".toolchain/scripts/build_site.py/inside")
        try write("in the way", to: blocker)

        let outcome: WorkspaceModel.MirrorOutcome = mirror()
        XCTAssertEqual(outcome.failed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: indexURL.path))
    }

    /// `BuilderWarmUp` calls `copyToolchainFiles` for its own folder, which
    /// is not a working folder (no `preview.sh`). It gets the same pass and
    /// its own index, keyed by its own path.
    func testTheWarmUpsFolderIsComparedByFingerprintToo() throws {
        let place: URL = BuilderWarmUp.folder(inHomeFolder: root)
        try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
        try writeManifest()
        _ = WorkspaceModel.copyToolchainFiles(into: place, from: bundle, indexFolder: indexFolder)
        let placeIndex: URL = ToolchainFingerprints.indexURL(forWorkingFolder: place, in: indexFolder)
        XCTAssertTrue(FileManager.default.fileExists(atPath: placeIndex.path))

        try restampTheBundle(bySeconds: 60)
        try writeManifest()
        let outcome: WorkspaceModel.MirrorOutcome = WorkspaceModel.copyToolchainFiles(
            into: place, from: bundle, indexFolder: indexFolder
        )
        XCTAssertEqual(outcome.failed, 0)
        XCTAssertEqual(outcome.readInFull, 0)
        XCTAssertEqual(outcome.compared, bundledFiles.count)
    }

    func testTheIndexRoundTrips() throws {
        let entries: [String: ToolchainFingerprint] = [
            "scripts/a.py": ToolchainFingerprint(length: 12, ticks: 639_284_101_765_316_255, sha256: String(repeating: "a", count: 64)),
            "Dockerfile": ToolchainFingerprint(length: 0, ticks: 1, sha256: String(repeating: "b", count: 64)),
        ]
        let url: URL = root.appendingPathComponent("round-trip.hashes")
        try ToolchainFingerprints.write(entries, to: url)
        XCTAssertEqual(ToolchainFingerprints.read(url), entries)
        XCTAssertNil(ToolchainFingerprints.read(root.appendingPathComponent("absent.hashes")))
    }

    // MARK: - Pruning the index (#683)

    func modificationDate(of url: URL) throws -> Date {
        let attributes: [FileAttributeKey: Any] = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.modificationDate] as? Date)
    }

    func makeFile(named name: String, in folder: URL, aged age: TimeInterval, now: Date) throws -> URL {
        let url: URL = folder.appendingPathComponent(name)
        try write("index\n", to: url)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path)
        return url
    }

    /// MUST-FAIL without `markUsed` in `copyToolchainFiles`: a pass that
    /// changes nothing does not rewrite the index, so before #683 its time
    /// stayed whatever the last CHANGE left, and a folder opened every day
    /// would look unused after ninety.
    func testAPassMarksAnUnchangedIndexUsed() throws {
        try writeManifest()
        _ = mirror()
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexURL.path), "the first pass wrote no index")
        let longAgo: Date = Date().addingTimeInterval(-100 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: longAgo], ofItemAtPath: indexURL.path)
        let before: String = try String(contentsOf: indexURL, encoding: .utf8)

        let outcome: WorkspaceModel.MirrorOutcome = mirror()

        XCTAssertEqual(outcome.changed, 0, "the state being tested: a pass with nothing to change")
        XCTAssertEqual(try String(contentsOf: indexURL, encoding: .utf8), before, "the index was rewritten, so the test proves nothing")
        XCTAssertLessThan(abs(try modificationDate(of: indexURL).timeIntervalSinceNow), 60,
                          "a folder opened today must read as used today")
    }

    func testAnIndexUnusedForNinetyDaysIsRemovedAndOneUsedWithinThemIsKept() throws {
        let now: Date = Date()
        let day: TimeInterval = 24 * 60 * 60
        let old: URL = try makeFile(named: "aaaaaaaa.hashes", in: indexFolder, aged: 91 * day, now: now)
        let recent: URL = try makeFile(named: "bbbbbbbb.hashes", in: indexFolder, aged: 89 * day, now: now)

        let removed: [String] = ToolchainFingerprints.pruneIndexes(in: indexFolder, now: now)

        XCTAssertEqual(removed, ["aaaaaaaa.hashes"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recent.path), "used within the summer, so kept")
        XCTAssertEqual(ToolchainFingerprints.unusedIndexLifetime, 90 * day)
    }

    func testALeftoverTemporaryIndexIsRemovedAfterADay() throws {
        let now: Date = Date()
        let old: URL = try makeFile(named: "aaaaaaaa.hashes.4242.tmp", in: indexFolder, aged: 2 * 24 * 60 * 60, now: now)
        let writing: URL = try makeFile(named: "bbbbbbbb.hashes.4243.tmp", in: indexFolder, aged: 60, now: now)

        ToolchainFingerprints.pruneIndexes(in: indexFolder, now: now)

        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path), "an interrupted write's leftover stays forever otherwise")
        XCTAssertTrue(FileManager.default.fileExists(atPath: writing.path), "a pass may be writing it now")
    }

    func testNothingButIndexesIsTouched() throws {
        let now: Date = Date()
        let ages: TimeInterval = 400 * 24 * 60 * 60
        let stray: URL = try makeFile(named: "notes.txt", in: indexFolder, aged: ages, now: now)
        let alike: URL = try makeFile(named: "aaaaaaaa.hashes.bak", in: indexFolder, aged: ages, now: now)
        let folder: URL = indexFolder.appendingPathComponent("cccccccc.hashes")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-ages)], ofItemAtPath: folder.path)
        let target: URL = try makeFile(named: "elsewhere.txt", in: root, aged: ages, now: now)
        let link: URL = indexFolder.appendingPathComponent("dddddddd.hashes")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertEqual(ToolchainFingerprints.pruneIndexes(in: indexFolder, now: now), [])
        for kept in [stray, alike, folder, target] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path), "\(kept.lastPathComponent) was removed")
        }
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: link.path), "a link is not one of ours")
    }

    func testAFolderWithNoIndexesIsLeftAlone() {
        let missing: URL = root.appendingPathComponent("never-made")
        XCTAssertEqual(ToolchainFingerprints.pruneIndexes(in: missing, now: Date()), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }

    /// The suite never reaches the real index folder: the default folder the
    /// app prunes is under the suite's throwaway home, and the one caller in
    /// the product is the launch task the suite never runs.
    func testAPruneNeverReachesTheRealIndexFolder() throws {
        // The suite's home is the throwaway one (RealHomeTripwireTests holds
        // that), and the folder the app prunes is under it.
        XCTAssertTrue(RealHome.isRedirected, "the suite is running against the real home")
        XCTAssertTrue(ToolchainFingerprints.indexFolder().path.hasPrefix(RealHome.forFiles.path + "/"),
                      "under the suite the app's index folder must be the throwaway home's")

        let repository: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var callers: [String] = []
        let sources: URL = repository.appendingPathComponent("QuartzTeachers")
        let walker = FileManager.default.enumerator(atPath: sources.path)
        while let relative = walker?.nextObject() as? String {
            if !relative.hasSuffix(".swift") {
                continue
            }
            let text: String = try String(contentsOf: sources.appendingPathComponent(relative), encoding: .utf8)
            if text.contains("ToolchainFingerprints.pruneIndexes(") {
                callers.append(relative)
            }
        }
        XCTAssertEqual(callers, ["App/AppDelegate.swift"], "a new caller of the prune; check it cannot run under the suite")
        let delegate: String = try String(contentsOf: sources.appendingPathComponent("App/AppDelegate.swift"), encoding: .utf8)
        let callRange = try XCTUnwrap(delegate.range(of: "ToolchainFingerprints.pruneIndexes("))
        // The NEAREST guard above the call.
        let guardRange = try XCTUnwrap(delegate.range(
            of: "if !WorkspaceModel.isRunningTests {", options: .backwards,
            range: delegate.startIndex..<callRange.lowerBound
        ))
        XCTAssertLessThan(guardRange.lowerBound, callRange.lowerBound)
        XCTAssertLessThan(delegate.distance(from: guardRange.lowerBound, to: callRange.lowerBound), 800,
                          "the prune has moved away from the launch task the suite never runs")
    }

    // MARK: - The trail line

    func prepareTrail() throws -> URL {
        let trailFolder: URL = root.appendingPathComponent("trail")
        try FileManager.default.createDirectory(at: trailFolder, withIntermediateDirectories: true)
        let previousTrail: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: trailFolder)
        addTeardownBlock {
            MainActor.assumeIsolated {
                ActivityTrail.store = previousTrail
            }
        }
        return trailFolder
    }

    func trailLines() -> [String] {
        var lines: [String] = []
        for line in ActivityTrail.store.activityText(includingPrompts: true).split(separator: "\n") {
            if line.contains("working folder ready") {
                lines.append(String(line))
            }
        }
        return lines
    }

    /// MUST-FAIL on the pre-#663 `apply`, whose line said only how many files
    /// were brought up to date.
    func testTheTrailLineSaysWhatWasCompared() throws {
        _ = try prepareTrail()
        let outcome: WorkspaceModel.MirrorOutcome = WorkspaceModel.MirrorOutcome(
            changed: 14, failed: 0, compared: 12_889, readInFull: 3
        )
        ToolchainReadiness.shared.apply(outcome, to: workingFolder, startedAt: Date())
        let lines: [String] = trailLines()
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines.first?.contains("14 file(s) brought up to date, 12889 compared (3 read in full) in ") ?? false, lines.first ?? "")
    }

    /// MUST-FAIL on the pre-#663 `apply`, which wrote nothing for a pass that
    /// changed nothing — the pass that read twelve thousand files and left no
    /// trace of the time it took.
    func testAPassThatOnlyReadStillLeavesALine() throws {
        _ = try prepareTrail()
        let read: WorkspaceModel.MirrorOutcome = WorkspaceModel.MirrorOutcome(compared: 7, readInFull: 7)
        ToolchainReadiness.shared.apply(read, to: workingFolder, startedAt: Date())
        XCTAssertEqual(trailLines().count, 1)
        XCTAssertTrue(trailLines().first?.contains("0 file(s) brought up to date, 7 compared (7 read in full)") ?? false)

        // The ordinary launch — everything matched by length and time — still
        // leaves nothing.
        let cheap: WorkspaceModel.MirrorOutcome = WorkspaceModel.MirrorOutcome(compared: 7, readInFull: 0)
        ToolchainReadiness.shared.apply(cheap, to: workingFolder, startedAt: Date())
        XCTAssertEqual(trailLines().count, 1)
    }

    func testTheSentenceSaysEachCountOnlyWhenThereIsOne() {
        let filled: String = ToolchainReadiness.trailSentence(
            for: WorkspaceModel.MirrorOutcome(changed: 12_912), seconds: "3.1"
        )
        XCTAssertEqual(filled, "got the working folder ready: 12912 file(s) brought up to date in 3.1 s")

        let compared: String = ToolchainReadiness.trailSentence(
            for: WorkspaceModel.MirrorOutcome(changed: 2, compared: 12_910), seconds: "0.4"
        )
        XCTAssertEqual(compared, "got the working folder ready: 2 file(s) brought up to date, 12910 compared in 0.4 s")

        let failed: String = ToolchainReadiness.trailSentence(
            for: WorkspaceModel.MirrorOutcome(
                changed: 1, failed: 2, firstFailure: ".toolchain/scripts/x.py: denied", compared: 5, readInFull: 1
            ),
            seconds: "0.2"
        )
        XCTAssertEqual(
            failed,
            "could not finish getting the working folder ready: 2 file(s) could not be copied or removed, 1 brought up to date, 5 compared (1 read in full), in 0.2 s — first: .toolchain/scripts/x.py: denied"
        )
    }

    // MARK: - The app's own manifest

    /// Guards against the build phase silently not running: the app this
    /// suite is hosted in carries a manifest with one line per file the
    /// mirror copies, and every line describes the bundled file it names.
    func testTheAppCarriesAManifestThatDescribesItsBundle() throws {
        let resources: URL = try XCTUnwrap(Bundle.main.resourceURL)
        let manifestURL: URL = resources.appendingPathComponent(ToolchainFingerprints.manifestName)
        let manifest: [String: ToolchainFingerprint] = try XCTUnwrap(
            ToolchainFingerprints.read(manifestURL), "The app carries no \(ToolchainFingerprints.manifestName)"
        )

        var mirrored: [String] = []
        for name in ["Dockerfile", "setup.sh", "preview.sh", "deploy.sh", "setup.bat", "preview.bat", "deploy.bat", "setup.ps1", "preview.ps1", "deploy.ps1"] {
            if FileManager.default.fileExists(atPath: resources.appendingPathComponent(name).path) {
                mirrored.append(name)
            }
        }
        for folder in WorkspaceModel.mirroredFolders {
            let folderURL: URL = resources.appendingPathComponent(folder)
            guard let enumerator = FileManager.default.enumerator(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey]) else {
                continue
            }
            for case let fileURL as URL in enumerator {
                let isFile: Bool = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
                if isFile, let relative = WorkspaceModel.relativePath(of: fileURL, under: folderURL) {
                    mirrored.append(folder + "/" + relative)
                }
            }
        }
        XCTAssertGreaterThan(mirrored.count, 1_000)
        XCTAssertEqual(manifest.count, mirrored.count, "One line per mirrored file")

        var undescribed: [String] = []
        for relative in mirrored {
            let stamp: ToolchainFingerprints.Stamp? = ToolchainFingerprints.stamp(of: resources.appendingPathComponent(relative))
            if manifest[relative]?.stillDescribes(stamp) != true {
                undescribed.append(relative)
            }
        }
        XCTAssertEqual(undescribed.count, 0, "First few: \(undescribed.prefix(5))")

        // And the hashes are the files' own, checked on a few.
        for relative in ["Dockerfile", "scripts/build_site.py", "contracts/shared-rules.json"] {
            XCTAssertEqual(
                manifest[relative]?.sha256,
                ToolchainFingerprints.sha256(of: resources.appendingPathComponent(relative)),
                relative
            )
        }
    }
}

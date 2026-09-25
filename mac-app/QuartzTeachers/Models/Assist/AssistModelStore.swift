import Foundation
import Observation

/// Where the local model lives on this Mac, and how it gets here.
///
/// The weights are NOT in the app bundle. A 1–5 GB model inside the app would
/// have to be downloaded by every teacher on every update, signed and
/// notarised each time, and would land on Macs whose teacher never opens the
/// assistant. It is fetched once, into Application Support, and stays there
/// across app updates.
@Observable
final class AssistModelStore {

    // MARK: - Types

    /// What the store is doing, in words a teacher can read.
    enum State: Equatable {
        case missing
        case downloading(fractionComplete: Double, receivedBytes: Int64, totalBytes: Int64)
        case ready
        case failed(reason: String)
    }

    // MARK: - Stored properties

    /// The model this Mac should run.
    let tier: AssistModelTier

    /// Where the store is up to.
    private(set) var state: State = .missing

    /// The download in flight, so it can be cancelled with the window.
    private var task: URLSessionDownloadTask?

    /// Kept alive for the length of a download; its delegate reports progress.
    private var session: URLSession?

    // MARK: - Computed properties

    /// Somewhere else to keep the weights, for tests only.
    ///
    /// The same seam `ActivityTrail.store` has, and for a sharper reason:
    /// these tests DELETE files. Without a way to point the store at a
    /// temporary folder, a test of "removing frees the space" would remove
    /// the weights off the machine it was running on — several gigabytes the
    /// developer then re-downloads, having been given no reason to connect it
    /// to a green test run.
    nonisolated(unsafe) static var directoryOverride: URL?

    /// `~/Library/Application Support/Plantoir/models`.
    ///
    /// **Under the unit suite, the suite's throwaway home instead** (issue
    /// #264), through `RealHome.forFiles`. Three tests used to stat the real
    /// weights here, so a panel sentence they checked depended on what the
    /// Mac running them had downloaded — a suite that answers differently on
    /// a Mac with weights. The app a UI test drives has no XCTest in it and
    /// keeps the real folder, which `AssistantRolloverUITests` needs: it runs
    /// against a real model.
    static var directoryURL: URL {
        if let override = directoryOverride {
            return override
        }
        return RealHome.forFiles
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Plantoir", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
    }

    /// Where this tier's weights sit once downloaded.
    var fileURL: URL {
        return AssistModelStore.directoryURL.appendingPathComponent(tier.fileName)
    }

    /// Is the model already here, and the right size? A truncated download —
    /// a closed lid, a dropped network — leaves a file that exists and is
    /// useless, and llama.cpp's failure on one is not obviously about size.
    var isReady: Bool {
        let path: String = fileURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            return false
        }
        let attributes: [FileAttributeKey: Any]? = try? FileManager.default.attributesOfItem(atPath: path)
        let size: Int64 = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        return size == tier.downloadBytes
    }

    // MARK: - Initializer

    init(tier: AssistModelTier) {
        self.tier = tier
        if isReady {
            state = .ready
        }
    }

    // MARK: - Functions

    /// Fetch the weights, reporting progress. Does nothing when they are
    /// already here.
    func download() {
        if isReady {
            state = .ready
            return
        }
        if case .downloading = state {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: AssistModelStore.directoryURL, withIntermediateDirectories: true
            )
        } catch {
            state = .failed(reason: "Could not make a place for the model: \(error.localizedDescription)")
            return
        }

        // A part-finished file from a previous attempt is never resumed: the
        // ranges would have to match exactly and a wrong guess produces a
        // corrupt model that fails much later, somewhere less obvious.
        try? FileManager.default.removeItem(at: fileURL)

        state = .downloading(fractionComplete: 0, receivedBytes: 0, totalBytes: tier.downloadBytes)
        ActivityTrail.note(
            .assistantModelDownloadStarted,
            "started downloading \(tier.displayName) — \(tier.downloadDescription)"
        )

        let delegate: DownloadDelegate = DownloadDelegate(store: self)
        let configuration: URLSessionConfiguration = .default
        configuration.waitsForConnectivity = true
        let session: URLSession = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        self.session = session

        let task: URLSessionDownloadTask = session.downloadTask(with: tier.downloadURL)
        self.task = task
        task.resume()
    }

    /// Delete the weights to get the space back.
    ///
    /// Deliberately NOT hidden behind "are you sure it is not in use" logic
    /// here: whether it is safe to remove is a question about what windows
    /// are open, which this type cannot see and `AssistModelLibrary` can.
    /// This does the deletion and nothing else, so a test can drive it
    /// without standing an assistant window up.
    ///
    /// Removing the model a teacher is currently set to use is allowed on
    /// purpose — it is not a broken state, it is the state every Mac is in
    /// before the first download, and opening the assistant offers to fetch
    /// it again.
    func remove() {
        cancel()
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            let missing: Bool = (error as NSError).code == NSFileNoSuchFileError
            if !missing {
                state = .failed(reason: "Could not remove it: \(error.localizedDescription)")
                return
            }
        }
        state = .missing
        ActivityTrail.note(
            .assistantModelRemoved,
            "removed \(tier.displayName) — \(tier.downloadDescription) freed"
        )
    }

    /// What this tier takes on disk right now, or nil when it is not here.
    ///
    /// Reads the actual file rather than reporting `downloadBytes`, so a
    /// half-finished download is described by its real size instead of by the
    /// size it was going to be.
    static func bytesOnDisk(for tier: AssistModelTier) -> Int64? {
        let url: URL = AssistModelStore.directoryURL.appendingPathComponent(tier.fileName)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return (attributes[.size] as? NSNumber)?.int64Value
    }

    /// Stop a download in flight — the teacher closed the window.
    func cancel() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        if case .downloading = state {
            state = .missing
            ActivityTrail.note(
                .assistantModelDownloadStopped,
                "stopped downloading \(tier.displayName)"
            )
        }
    }

    /// Called by the delegate as bytes arrive.
    fileprivate func report(received: Int64, expected: Int64) {
        let total: Int64 = expected > 0 ? expected : tier.downloadBytes
        var fraction: Double = 0
        if total > 0 {
            fraction = Double(received) / Double(total)
        }
        state = .downloading(fractionComplete: fraction, receivedBytes: received, totalBytes: total)
    }

    /// Called by the delegate when the body has landed in a temporary file.
    fileprivate func finish(movingFrom temporary: URL) {
        do {
            try? FileManager.default.removeItem(at: fileURL)
            try FileManager.default.moveItem(at: temporary, to: fileURL)
        } catch {
            state = .failed(reason: "Could not save the model: \(error.localizedDescription)")
            return
        }

        // Trust the bytes on disk rather than the fact that the transfer
        // ended: a proxy or a captive portal answers 200 with something that
        // is not a model at all.
        if isReady {
            state = .ready
            ActivityTrail.note(
                .assistantModelDownloaded,
                "finished downloading \(tier.displayName) — \(tier.downloadDescription)"
            )
        } else {
            try? FileManager.default.removeItem(at: fileURL)
            let reason: String = "The download finished but the file is the wrong size. Try again."
            state = .failed(reason: reason)
            ActivityTrail.note(
                .assistantModelDownloadFailed,
                "could not download \(tier.displayName) — \(reason)"
            )
        }
        session?.finishTasksAndInvalidate()
        session = nil
        task = nil
    }

    fileprivate func fail(_ message: String) {
        state = .failed(reason: message)
        ActivityTrail.note(
            .assistantModelDownloadFailed,
            "could not download \(tier.displayName) — \(message)"
        )
        session?.finishTasksAndInvalidate()
        session = nil
        task = nil
    }
}

// MARK: - Download delegate

/// URLSession calls back on its own queue, so every hop into the store is
/// bounced to the main actor where the observable state lives.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    // MARK: - Stored properties

    private let store: AssistModelStore

    // MARK: - Initializer

    init(store: AssistModelStore) {
        self.store = store
    }

    // MARK: - Functions

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let received: Int64 = totalBytesWritten
        let expected: Int64 = totalBytesExpectedToWrite
        Task { @MainActor in
            store.report(received: received, expected: expected)
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The temporary file is deleted the moment this method returns, so it
        // is moved somewhere of our own SYNCHRONOUSLY here, and only then
        // handed to the main actor.
        let holding: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("plantoir-model-\(UUID().uuidString).gguf")
        do {
            try FileManager.default.moveItem(at: location, to: holding)
        } catch {
            let message: String = error.localizedDescription
            Task { @MainActor in
                store.fail("Could not save the model: \(message)")
            }
            return
        }
        Task { @MainActor in
            store.finish(movingFrom: holding)
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let error else {
            return
        }
        let cancelled: Bool = (error as NSError).code == NSURLErrorCancelled
        if cancelled {
            return
        }
        let message: String = error.localizedDescription
        Task { @MainActor in
            store.fail(message)
        }
    }
}

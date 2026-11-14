import Foundation
import Observation

/// Runs `deploy.sh --token …` in a working folder and reads its one line of
/// JSON (#696). The app never reads or writes the token store itself; the
/// launcher does, so both platforms share one behaviour and one set of cases
/// (`contracts/shared-rules.json` → `deployTokens.launcherMode`).
enum DeployTokenLauncher {

    // MARK: - Functions

    /// The launcher's arguments for one action (`launcherMode.arguments`).
    nonisolated static func arguments(
        action: String,
        destination: DeployTokenDestination,
        accountID: String,
        useAnyway: Bool = false
    ) -> [String] {
        var arguments: [String] = ["--token", action, "--target", destination.launcherTarget]
        let account: String = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        if destination == .cloudflare && !account.isEmpty {
            arguments.append("--account")
            arguments.append(account)
        }
        if useAnyway {
            arguments.append("--use-anyway")
        }
        return arguments
    }

    /// The working folder whose launcher is asked: the first open window's,
    /// as long as it has one. Nil when no window has a working folder.
    @MainActor static func workingFolder() -> URL? {
        for model in WorkspaceModel.windowModels {
            guard let folder = model.workspaceURL else {
                continue
            }
            let launcher: URL = folder.appendingPathComponent(DeployCommand.scriptName)
            if FileManager.default.fileExists(atPath: launcher.path) {
                return folder
            }
        }
        return nil
    }

    /// Runs the launcher and returns what it answered, or nil when it could
    /// not be run or answered in some other shape. `input` is written to its
    /// standard input and the pipe closed: a pasted token goes there and
    /// nowhere else, never into the arguments or the environment.
    static func run(workingFolder: URL, arguments: [String], input: String?) async -> DeployTokenAnswer? {
        let launcher: URL = workingFolder.appendingPathComponent(DeployCommand.scriptName)
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [launcher.path] + arguments
        process.environment = HelperPrograms.environment()
        process.currentDirectoryURL = workingFolder
        let output: Pipe = Pipe()
        let given: Pipe = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = given
        // Written into the pipe BEFORE the launcher starts, and the pipe's
        // writing end closed: a token is a few dozen bytes, far under what a
        // pipe holds, and a launcher that exits without reading it can then
        // never make this write fail with a broken pipe.
        if let input, let data = input.data(using: .utf8) {
            given.fileHandleForWriting.write(data)
        }
        try? given.fileHandleForWriting.close()
        let printed: String = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            process.terminationHandler = { _ in
                let data: Data = output.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: "")
            }
        }
        return DeployTokenAnswer.parse(printed)
    }
}

/// One destination's part of Plantoir ▸ Settings ▸ Deploying: what the last
/// check said, and the change and removal (#696).
@MainActor
@Observable
final class DeployTokenPanel {

    // MARK: - Stored properties

    let destination: DeployTokenDestination

    /// What the status line shows.
    enum Status: Equatable {
        case checking
        case answered(DeployTokenAnswer)
        case noWorkingFolder
    }

    var status: Status = .checking

    /// True while the Change Token sheet is open.
    var isShowingChange: Bool = false

    /// What the sheet says under its field after a save that kept nothing.
    var sheetProblem: String? = nil

    /// True while a pasted token is being checked.
    var isSaving: Bool = false

    /// The websites a new token could not reach, while the question about
    /// them is open; empty otherwise.
    var unreachablePlaces: [String] = []

    /// The pasted token, held only while that question is open, so Use the
    /// New Token can hand it over again. Cleared by either answer.
    @ObservationIgnored private var heldPaste: String? = nil

    /// True while Remove Token's question is open.
    var isAskingToRemove: Bool = false

    /// How many websites the question was about, for the trail line written
    /// after Use the New Token.
    @ObservationIgnored private var pendingUnreachableCount: Int = 0

    /// Run instead of the real launcher by a test.
    @ObservationIgnored var runLauncher: (URL, [String], String?) async -> DeployTokenAnswer? = { folder, arguments, input in
        return await DeployTokenLauncher.run(workingFolder: folder, arguments: arguments, input: input)
    }

    /// Where the launcher is; asked each time, so a window opened after the
    /// pane is used.
    @ObservationIgnored var findWorkingFolder: () -> URL? = {
        return DeployTokenLauncher.workingFolder()
    }

    // MARK: - Computed properties

    var isAskingAboutUnreachable: Bool {
        return !unreachablePlaces.isEmpty
    }

    /// Whether a token is saved, as far as the last check knows.
    var hasSavedToken: Bool {
        if case .answered(let answer) = status {
            return answer.saved
        }
        return false
    }

    // MARK: - Initializer

    init(destination: DeployTokenDestination) {
        self.destination = destination
    }

    // MARK: - Functions

    /// The status line for the pane.
    func statusLine(now: Date = Date(), timeZone: TimeZone = TimeZone.current) -> String {
        switch status {
        case .checking:
            return DeployTokenWording.statusChecking
        case .noWorkingFolder:
            return DeployTokenWording.statusNoWorkingFolder
        case .answered(let answer):
            return DeployTokenWording.statusLine(for: answer, destination: destination, now: now, timeZone: timeZone)
        }
    }

    /// Asks the service about the saved token. Never clears it.
    func check() async {
        guard let folder = findWorkingFolder() else {
            status = .noWorkingFolder
            return
        }
        status = .checking
        let arguments: [String] = DeployTokenLauncher.arguments(
            action: "status", destination: destination, accountID: AppSettings.shared.cloudflareAccountID
        )
        let answer: DeployTokenAnswer = await runLauncher(folder, arguments, nil) ?? DeployTokenPanel.notAnswered
        status = .answered(answer)
        rememberTheEndDate(from: answer)
    }

    /// Checks a pasted token and saves it only when the launcher says so.
    func save(pasted: String, useAnyway: Bool = false) async {
        guard let folder = findWorkingFolder() else {
            status = .noWorkingFolder
            sheetProblem = DeployTokenWording.statusNoWorkingFolder
            return
        }
        isSaving = true
        sheetProblem = nil
        let arguments: [String] = DeployTokenLauncher.arguments(
            action: "save", destination: destination,
            accountID: AppSettings.shared.cloudflareAccountID, useAnyway: useAnyway
        )
        let answer: DeployTokenAnswer = await runLauncher(folder, arguments, pasted) ?? DeployTokenPanel.notAnswered
        isSaving = false
        if answer.saved {
            heldPaste = nil
            unreachablePlaces = []
            isShowingChange = false
            status = .answered(answer)
            rememberTheEndDate(from: answer)
            noteChanged(unreachableCount: useAnyway ? pendingUnreachableCount : 0)
            pendingUnreachableCount = 0
            return
        }
        if answer.problem == "tokenCannotReachSites" && !answer.unreachable.isEmpty {
            heldPaste = pasted
            pendingUnreachableCount = answer.unreachable.count
            unreachablePlaces = answer.unreachable
            return
        }
        sheetProblem = DeployTokenWording.sheetProblem(for: answer, destination: destination)
        ActivityTrail.note(
            .deployTokenChangeRefused,
            DeployTokenPanel.trailLine(.refused, destination: destination, problem: answer.problem ?? answer.answer)
        )
    }

    /// Use the New Token: the question closes at once, and the token is
    /// saved without the check against the websites. Returns the work, so a
    /// test can wait for it; the button does not.
    @discardableResult
    func useTheNewTokenAnyway() -> Task<Void, Never>? {
        guard let pasted = heldPaste else {
            unreachablePlaces = []
            return nil
        }
        unreachablePlaces = []
        heldPaste = nil
        return Task { @MainActor in
            await self.save(pasted: pasted, useAnyway: true)
        }
    }

    /// Keep My Old Token: nothing changes, and the sheet closes.
    func keepTheOldToken() {
        let count: Int = unreachablePlaces.count
        heldPaste = nil
        unreachablePlaces = []
        pendingUnreachableCount = 0
        isShowingChange = false
        ActivityTrail.note(
            .deployTokenKeptOld,
            DeployTokenPanel.trailLine(.keptOld, destination: destination, count: count)
        )
    }

    /// Removes the saved token, after the teacher said yes.
    func remove() async {
        guard let folder = findWorkingFolder() else {
            status = .noWorkingFolder
            return
        }
        let arguments: [String] = DeployTokenLauncher.arguments(
            action: "remove", destination: destination, accountID: ""
        )
        let answer: DeployTokenAnswer = await runLauncher(folder, arguments, nil) ?? DeployTokenPanel.notAnswered
        if answer.answer == "notSaved" {
            status = .answered(answer)
            rememberTheEndDate(from: answer)
            ActivityTrail.note(.deployTokenRemoved, DeployTokenPanel.trailLine(.removed, destination: destination))
        } else {
            status = .answered(answer)
        }
    }

    /// Cancel in the sheet: nothing held, nothing said.
    func cancelChange() {
        heldPaste = nil
        unreachablePlaces = []
        sheetProblem = nil
        isShowingChange = false
    }

    /// The end date the Deploy screen warns from, kept when a check read
    /// one for Cloudflare, and cleared when there is no token.
    func rememberTheEndDate(from answer: DeployTokenAnswer) {
        if destination != .cloudflare {
            return
        }
        if answer.answer == "accepted" || answer.answer == "notSaved" {
            AppSettings.shared.cloudflareTokenEndsOn = answer.endsOn ?? ""
        }
    }

    func noteChanged(unreachableCount: Int) {
        if unreachableCount > 0 {
            ActivityTrail.note(
                .deployTokenChanged,
                DeployTokenPanel.trailLine(.changedAnyway, destination: destination, count: unreachableCount)
            )
        } else {
            ActivityTrail.note(.deployTokenChanged, DeployTokenPanel.trailLine(.changed, destination: destination))
        }
    }

    /// What a launcher that could not be run, or answered in another shape,
    /// is read as: could not be checked, nothing saved.
    nonisolated static let notAnswered: DeployTokenAnswer = DeployTokenAnswer(
        saved: false, answer: "unheard", endsOn: nil, problem: nil, unreachable: []
    )

    /// The trail's lines (`deployTokens.trail.lines`).
    enum TrailLine: String {
        case changed
        case changedAnyway
        case removed
        case refused
        case keptOld
    }

    nonisolated static let trailLines: [String: String] = [
        "changed": "Settings ▸ Deploying — changed the {service} token",
        "changedAnyway": "Settings ▸ Deploying — changed the {service} token, though it cannot reach {count} class website(s)",
        "removed": "Settings ▸ Deploying — removed the {service} token",
        "refused": "Settings ▸ Deploying — a new {service} token was not saved: {problem}",
        "keptOld": "Settings ▸ Deploying — kept the old {service} token: the new one cannot reach {count} class website(s)",
    ]

    /// One trail line. Never the token, the account, a site or an address:
    /// only the service, a problem KEY and a count.
    nonisolated static func trailLine(
        _ line: TrailLine,
        destination: DeployTokenDestination,
        problem: String = "",
        count: Int = 0
    ) -> String {
        let sentence: String = trailLines[line.rawValue] ?? ""
        return DeployTokenWording.filled(sentence, [
            "service": destination.serviceName,
            "problem": problem,
            "count": String(count),
        ])
    }
}

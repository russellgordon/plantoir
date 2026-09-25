import Foundation

/// The one answer to "is the process a lease names still doing what the
/// lease says?" — asked by every reader of a lease under
/// `courses/.internal/activity/`.
///
/// A lease is a file named `<NAME>.<kind>.<pid>.lease` holding the process
/// id, the process name, the moment it was taken and — written by the mac —
/// when its owner STARTED. Its whole value is that it survives a crash: a
/// lease whose owner is gone is ignored rather than trusted, so nothing
/// locks up. That makes the liveness question the one that decides whether
/// somebody's work is left alone or taken away, and it is asked here, once,
/// so no reader grows its own copy of it. `contracts/shared-rules.json` →
/// `workLeases.liveness` carries the cases; `contracts/file-formats.json` →
/// `workLease` carries the format.
///
/// **What was measured, on this Mac, as an ordinary user (2026-09-25):**
///
/// - `kill(1, 0)` — launchd, root's — returns -1 with `EPERM`. The process
///   is there; it is simply not ours to signal. Until #245 the import read
///   every answer but 0 as "gone", so a lease held by another account's copy
///   of Plantoir, or by a process running as root, was swept.
/// - `kill(99999, 0)` returns -1 with `ESRCH`: the only answer that means
///   no such process.
/// - `kill(0, 0)` returns 0 — pid 0 means "my own process group" — so a
///   lease naming pid 0 would read as alive for ever. Refused outright.
/// - `proc_name(1, …)` fails with `EPERM` too, so it cannot name another
///   account's process.
/// - `sysctl(CTL_KERN, KERN_PROC, KERN_PROC_PID, pid)` answers for ANY
///   process: pid 1 gave "launchd" and its start time; 99999 gave an empty
///   answer (size 0). So one call gives existence, the zombie state, the
///   name and the start time.
///
/// **Errs toward ALIVE when it cannot tell.** The two directions are not
/// equal: reading a live owner as gone removes somebody's half-made work,
/// while reading a gone owner as alive leaves litter until the next time the
/// folder is opened. Windows' `WorkLease.IsAlive` errs the same way.
///
/// *Rejected: comparing the process NAME alone* (Windows' check). Every copy
/// of Plantoir is called Plantoir, so a lease left by a Plantoir that crashed
/// reads as live whenever another Plantoir has been handed the same number.
/// The start time names the exact process. The name is still checked, first,
/// because Windows' leases carry it and it is free.
/// *Rejected: `flock` on the lease file.* The kernel would release it at
/// death, but nothing else reads a lock — older builds and Windows read names
/// and pids — and working folders live on cloud-synced volumes, where
/// advisory locks are not something to bet a teacher's copy on.
nonisolated enum ProcessLiveness {

    // MARK: - Types

    /// What `kill(pid, 0)` said.
    enum SignalAnswer: String, Equatable {
        /// It returned 0.
        case exists
        /// -1 with `ESRCH`.
        case noSuchProcess
        /// -1 with `EPERM`: it exists and belongs to someone else.
        case notPermitted
        /// Anything else — not an answer this code knows how to read.
        case otherError
    }

    /// What the process table said about a process id.
    enum TableAnswer: Equatable {
        /// There is no process with that id.
        case noSuchProcess
        /// The table could not be asked at all.
        case couldNotAsk
        /// There is one, and this is what it is.
        case found(name: String, isZombie: Bool, startTime: String)
    }

    // MARK: - Stored properties

    /// How many characters of its name the system keeps for a process
    /// (`MAXCOMLEN`). "plantoir-mcp" is 12, so nothing of ours is cut off,
    /// but a longer recorded name is compared on its first sixteen.
    static let namesAreKeptTo: Int = 16

    /// The only program that has ever written an import lease.
    static let importLeaseWriterName: String = "Plantoir"

    // MARK: - Functions

    /// Whether the process a lease names is still the one that took it.
    ///
    /// - Parameters:
    ///   - recordedName: the lease's second line, or nil for a lease that
    ///     does not carry one (the one-line leases the import wrote before
    ///     #245, which an older copy of Plantoir still writes).
    ///   - recordedStart: the lease's fourth line, or nil.
    static func ownerIsAlive(pid: Int32, recordedName: String?, recordedStart: String?) -> Bool {
        if pid <= 0 {
            return false
        }
        let signal: SignalAnswer = ProcessLiveness.askBySignal(pid: pid)
        var table: TableAnswer = .couldNotAsk
        if signal != .noSuchProcess {
            table = ProcessLiveness.askTheProcessTable(pid: pid)
        }
        return ProcessLiveness.decide(
            pid: pid,
            signal: signal,
            table: table,
            recordedName: recordedName,
            recordedStart: recordedStart
        )
    }

    /// The rule itself, with nothing asked of the system — so the contract's
    /// cases can be run against it on any machine, as whatever user.
    ///
    /// In order: a pid of 0 or less is not a process; the signal's "no such
    /// process" is gone and every other signal answer goes on to the table;
    /// the table's "no such process" is gone, and a table that could not be
    /// asked is alive (cannot tell); a zombie is gone — it has finished and
    /// is waiting to be collected, and `kill` still answers 0 for one; a name
    /// that is not the recorded one is a recycled id, and so is a start time
    /// that is not the recorded one.
    static func decide(
        pid: Int32,
        signal: SignalAnswer,
        table: TableAnswer,
        recordedName: String?,
        recordedStart: String?
    ) -> Bool {
        if pid <= 0 {
            return false
        }
        if signal == .noSuchProcess {
            return false
        }

        switch table {
        case .noSuchProcess:
            return false
        case .couldNotAsk:
            return true
        case .found(let name, let isZombie, let startTime):
            if isZombie {
                return false
            }
            if let recordedName = recordedName, !recordedName.isEmpty {
                if !ProcessLiveness.namesMatch(recorded: recordedName, running: name) {
                    return false
                }
            }
            if let recordedStart = recordedStart, !recordedStart.isEmpty {
                if recordedStart != startTime {
                    return false
                }
            }
            return true
        }
    }

    /// The name a lease is judged against: the one it recorded, or — for an
    /// IMPORT lease with no name line — "Plantoir".
    ///
    /// Only Plantoir ever wrote a one-line import lease (the import before
    /// #245, and an older copy of Plantoir today), so the name is known even
    /// when it is not written. Without this a one-line lease left by a crash
    /// was judged on its process id alone, and after a restart that id can
    /// belong to an unrelated process for the whole uptime — which since #245
    /// REFUSES every import of that course, with a sentence that is not true.
    /// Other kinds are left as they are: their writers' names are not ours
    /// to assume.
    static func nameToCompare(recorded: String?, kind: String) -> String? {
        if let recorded = recorded, !recorded.isEmpty {
            return recorded
        }
        if kind == "import" {
            return ProcessLiveness.importLeaseWriterName
        }
        return nil
    }

    /// Whether the name a lease recorded is the name the system reports.
    ///
    /// Case-insensitive (Windows compares that way), and on the first
    /// `namesAreKeptTo` characters, because that is all the system keeps.
    static func namesMatch(recorded: String, running: String) -> Bool {
        let recordedKept: String = String(recorded.prefix(ProcessLiveness.namesAreKeptTo))
        let runningKept: String = String(running.prefix(ProcessLiveness.namesAreKeptTo))
        return recordedKept.lowercased() == runningKept.lowercased()
    }

    /// Asks `kill(pid, 0)`, which sends nothing and says whether the id is in
    /// use.
    static func askBySignal(pid: Int32) -> SignalAnswer {
        let result: Int32 = kill(pid, 0)
        if result == 0 {
            return .exists
        }
        let errorNumber: Int32 = errno
        if errorNumber == ESRCH {
            return .noSuchProcess
        }
        if errorNumber == EPERM {
            return .notPermitted
        }
        return .otherError
    }

    /// Asks the process table about one id — the one question that works for
    /// another account's process as well as our own.
    static func askTheProcessTable(pid: Int32) -> TableAnswer {
        var information: kinfo_proc = kinfo_proc()
        var size: Int = MemoryLayout<kinfo_proc>.stride
        var request: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let result: Int32 = sysctl(&request, UInt32(request.count), &information, &size, nil, 0)
        if result != 0 {
            return .couldNotAsk
        }
        if size == 0 {
            return .noSuchProcess
        }

        var nameBytes: [UInt8] = []
        withUnsafeBytes(of: information.kp_proc.p_comm) { buffer in
            for byte in buffer {
                if byte == 0 {
                    break
                }
                nameBytes.append(byte)
            }
        }
        let name: String = String(decoding: nameBytes, as: UTF8.self)
        let isZombie: Bool = Int32(information.kp_proc.p_stat) == SZOMB
        let started: timeval = information.kp_proc.p_starttime
        let startTime: String = ProcessLiveness.startTimeText(
            seconds: Int(started.tv_sec), microseconds: Int(started.tv_usec)
        )
        return .found(name: name, isZombie: isZombie, startTime: startTime)
    }

    /// When a process started, as a lease writes it — or nil when there is
    /// no such process or the table cannot be asked.
    static func startTime(ofProcess pid: Int32) -> String? {
        let table: TableAnswer = ProcessLiveness.askTheProcessTable(pid: pid)
        switch table {
        case .found(_, _, let startTime):
            return startTime
        case .noSuchProcess, .couldNotAsk:
            return nil
        }
    }

    /// The ONE spelling of a start time — whole seconds since 1970, a dot,
    /// and the microseconds padded to six digits — used both to write a
    /// lease and to compare against one, so a padding difference can never
    /// read as a recycled id.
    static func startTimeText(seconds: Int, microseconds: Int) -> String {
        var fraction: String = String(microseconds)
        while fraction.count < 6 {
            fraction = "0" + fraction
        }
        return "\(seconds).\(fraction)"
    }

    /// The moment a lease was taken, in the shape Windows writes it (.NET's
    /// round-trip "O" form, in UTC): `2026-09-25T13:59:23.8960000Z`.
    ///
    /// No reader parses it; it is there for parity and for a person reading
    /// the folder.
    static func leaseMomentText(_ moment: Date) -> String {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS'Z'"
        return formatter.string(from: moment)
    }

    /// What THIS process writes into a lease: its id, its name, the moment,
    /// and when it started — four lines, each ending in a line feed.
    ///
    /// The first three are Windows' `WorkLease` shape exactly, so its reader
    /// (which reads the first two) understands a mac lease; the fourth is the
    /// mac's addition and is ignored there.
    static func leaseBody(at moment: Date = Date()) -> String {
        let pid: Int32 = getpid()
        let name: String = ProcessInfo.processInfo.processName
        let started: String = ProcessLiveness.startTime(ofProcess: pid) ?? ""
        return "\(pid)\n\(name)\n\(ProcessLiveness.leaseMomentText(moment))\n\(started)\n"
    }

    /// The recorded name and start time in a lease's text, where it has
    /// them. A one-line lease — the import's before #245 — has neither, and
    /// is judged on the process id alone. A carriage return before a line
    /// feed is dropped, so a lease written on Windows reads the same.
    ///
    /// The carriage returns are taken out BEFORE splitting, and that order is
    /// load-bearing: Swift treats "\r\n" as ONE character, so splitting on
    /// "\n" first finds no line breaks at all in a Windows lease (measured —
    /// every line came back as one).
    static func recordedFacts(inLeaseText text: String) -> (name: String?, start: String?) {
        let unixText: String = text.replacingOccurrences(of: "\r\n", with: "\n")
        var lines: [String] = []
        for line in unixText.split(separator: "\n", omittingEmptySubsequences: false) {
            lines.append(String(line).trimmingCharacters(in: .whitespaces))
        }
        var name: String? = nil
        var start: String? = nil
        if lines.count > 1 && !lines[1].isEmpty {
            name = lines[1]
        }
        if lines.count > 3 && !lines[3].isEmpty {
            start = lines[3]
        }
        return (name: name, start: start)
    }
}

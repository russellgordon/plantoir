import Foundation

/// The moment written into the name of an archive or a backup —
/// `ICS3U_2026-08-09_141530.zip` — and read back out of it.
///
/// **Why this is a type of its own rather than a formatter at each end.**
/// Three kinds of zip share `courses/_backups/<CODE>/` and the same stamp:
/// archives (`ArchivedItem`), backups (`BackupItem`) and the setup wizard's
/// automatic copies. One of them is written here and all three are read here,
/// so the spelling is settled in ONE place instead of at each end — a writer
/// and a reader that drift apart is exactly the fault this file was added to
/// fix. The form itself is contract data, shared with the Windows app:
/// [`contracts/course-management.json`](../../../contracts/course-management.json)
/// → `zipNames`.
///
/// **The stamp is Gregorian on every Mac, and that is the whole point.**
/// `DateFormatter` renders `yyyy` in the CURRENT LOCALE'S calendar unless a
/// locale is pinned. Measured on this Mac for 2026-08-09 14:15:30: a Buddhist
/// calendar writes `2569-08-09_141530`, a Japanese one `0008-08-09_141530`
/// (Reiwa 8), an Islamic one `1448-02-26_141530`, an Ethiopic one
/// `2018-12-03_141530`. Every one of those is a name `contracts/` says is not
/// a name Plantoir writes, and a folder carried to another machine stops
/// sorting. So the writer pins `en_US_POSIX`, the way every other kept
/// filename in this app already does.
///
/// `nonisolated` because reading a file name is arithmetic on a string: it
/// has no state of its own and belongs to no actor, and the scans that call
/// it walk a directory rather than a window.
nonisolated enum ArchiveStamp {

    // MARK: - Stored properties

    /// The spelling, matched exactly by the Windows app
    /// (`ArchivedItem.StampFormat`).
    static let format: String = "yyyy-MM-dd_HHmmss"

    /// The earliest moment a Plantoir archive can name.
    ///
    /// Not a guess: the archive feature was written on 2026-08-09, so no zip
    /// of this kind can be older than that. Dated a comfortable year and a
    /// half BEFORE it so that no real name is ever refused, and it still
    /// leaves six years of daylight above the nearest wrong reading — see
    /// `couldHaveBeenStamped(_:)`, which is what that daylight is for.
    private static let earliestPossible: DateComponents = DateComponents(year: 2025, month: 1, day: 1)

    // MARK: - Functions

    /// The name-half of a zip made at `moment`.
    static func text(for moment: Date) -> String {
        return formatter(reading: Locale(identifier: "en_US_POSIX")).string(from: moment)
    }

    /// Reads the "2026-08-09_141530" half of an archive or backup's name.
    ///
    /// **Two spellings are accepted, and the second one is a migration.**
    /// Until 2026-09-10 the writer used no locale, so a Mac whose calendar is
    /// not Gregorian wrote its own calendar into every name it made. Those
    /// zips are still on that teacher's disk, and refusing them would empty
    /// their Archives and Backups lists on the day they updated — their own
    /// history, gone, with the files still sitting there. So the pinned
    /// reading is tried first, and the machine's own calendar second.
    ///
    /// **Which reading is right is decided by whether it could be true, not
    /// by whether it parsed** — the trap that makes this less obvious than it
    /// looks. `2569-08-09_141530` parses perfectly well as the Gregorian year
    /// 2569, so "try the pinned reading, fall back if it fails" would never
    /// fall back at all. `couldHaveBeenStamped(_:)` is what separates them.
    ///
    /// `machineLocale` is passed only by the tests, standing in for a Mac
    /// whose calendar is not Gregorian. Nothing in the app passes it.
    static func moment(from stamp: String, machineLocale: Locale = Locale.current) -> Date? {
        let asPlantoirWritesIt: Date? = formatter(reading: Locale(identifier: "en_US_POSIX")).date(from: stamp)
        if let asPlantoirWritesIt, couldHaveBeenStamped(asPlantoirWritesIt) {
            return asPlantoirWritesIt
        }

        let asThisMacOnceWroteIt: Date? = formatter(reading: machineLocale).date(from: stamp)
        if let asThisMacOnceWroteIt, couldHaveBeenStamped(asThisMacOnceWroteIt) {
            return asThisMacOnceWroteIt
        }

        // Neither reading can be true — a stamp carried from a machine whose
        // calendar this one does not use, or a clock that was wrong. Answer
        // with what this Mac has always answered, so a zip that is listed
        // today is still listed tomorrow, with the same date beside it. A
        // wrong date a teacher can see beats an archive that quietly vanishes
        // from the list while the file sits on disk.
        return asThisMacOnceWroteIt ?? asPlantoirWritesIt
    }

    /// Whether a moment is one Plantoir could have stamped into a name:
    /// after the archive feature existed, and not in the future.
    ///
    /// **This is the whole discriminator, so here is what it is measured
    /// against.** Read as Gregorian, the old spellings land far outside it —
    /// Buddhist 2569 and Hebrew 5786 are in the future, Ethiopic 2018,
    /// Indian 1948, Islamic 1448 and Japanese 0008 are before Plantoir
    /// existed. The closest of them is Ethiopic, seven years and eight months
    /// behind, which is why the floor is set years below the first archive
    /// ever written rather than at the day it was: any floor between the two
    /// works, and one in the middle is wrong in neither direction.
    ///
    /// It also has to stay right as time passes, which is the reason the
    /// pinned reading is tried FIRST. In 2035 an Ethiopic Mac would read a
    /// name written today as 2034 — a moment that is by then perfectly
    /// plausible — but the pinned reading of that same name is 2026, it is
    /// plausible too, and it is settled before the question is asked.
    static func couldHaveBeenStamped(_ moment: Date) -> Bool {
        let gregorian: Calendar = Calendar(identifier: .gregorian)
        guard let earliest = gregorian.date(from: earliestPossible) else {
            return false
        }
        let oneDay: TimeInterval = 24 * 60 * 60
        return moment >= earliest && moment <= Date().addingTimeInterval(oneDay)
    }

    /// A formatter for one calendar's spelling of the stamp.
    ///
    /// The time zone is pinned on BOTH ends deliberately: the stamp says what
    /// the clock on the wall said, so a name written at 14:15 reads back as
    /// 14:15, and a later tidy-up that pins one end and not the other cannot
    /// shift every archive by hours.
    private static func formatter(reading locale: Locale) -> DateFormatter {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = format
        return formatter
    }
}

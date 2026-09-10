import XCTest
@testable import QuartzTeachers

/// The moment written into an archive or backup's name, and read back out.
///
/// **Why a whole file of tests about a filename.** Until 2026-09-10 the
/// writer used a `DateFormatter` with no locale, so it wrote the MACHINE'S
/// calendar into every name: a Buddhist-calendar Mac made
/// `ICS3U_2569-08-09_141530.zip`. Reading was done by the same unpinned
/// formatter, so nothing ever looked wrong on that machine — which is why
/// nobody met it — while the name disagreed with what `contracts/` says
/// Plantoir writes, and a folder carried to any other machine stopped
/// sorting.
///
/// Every case below is machine-independent: `machineLocale` stands in for a
/// Mac whose calendar is not Gregorian, so this file proves on Russell's
/// Mac what it would otherwise only prove on a Thai one.
@MainActor
final class ArchiveStampTests: XCTestCase {

    // MARK: - Stored properties

    /// 2026-08-09 at 14:15:30, local time — the moment every case is about.
    private static let moment: Date = {
        var pieces: DateComponents = DateComponents()
        pieces.year = 2026
        pieces.month = 8
        pieces.day = 9
        pieces.hour = 14
        pieces.minute = 15
        pieces.second = 30
        return Calendar(identifier: .gregorian).date(from: pieces)!
    }()

    // MARK: - Functions

    /// The spelling itself, which is contract data.
    func testTheStampIsGregorianAndPlainDigits() {
        XCTAssertEqual(ArchiveStamp.text(for: ArchiveStampTests.moment), "2026-08-09_141530")
    }

    /// The four calendars macOS offers that a teacher might actually be
    /// running, each writing the same moment its own way — measured, not
    /// guessed. A Mac set to any of them wrote these names before the fix.
    func testANameWrittenInTheMachinesOwnCalendarIsStillRead() {
        let spellings: [(calendar: String, name: String)] = [
            (calendar: "buddhist", name: "2569-08-09_141530"),
            (calendar: "japanese", name: "0008-08-09_141530"),
            (calendar: "islamic-umalqura", name: "1448-02-26_141530"),
            (calendar: "ethiopic", name: "2018-12-03_141530"),
            (calendar: "hebrew", name: "5786-11-26_141530"),
            (calendar: "persian", name: "1405-05-18_141530"),
        ]
        for spelling in spellings {
            let machine: Locale = Locale(identifier: "en_CA@calendar=\(spelling.calendar)")

            // The old name is what that Mac really wrote…
            XCTAssertEqual(
                ArchiveStampTests.spelled(ArchiveStampTests.moment, in: machine), spelling.name,
                "a \(spelling.calendar) Mac wrote this name before the fix"
            )
            // …and the teacher's own history still reads correctly.
            XCTAssertEqual(
                ArchiveStamp.moment(from: spelling.name, machineLocale: machine),
                ArchiveStampTests.moment,
                "\(spelling.calendar): an archive made before the fix must not vanish from the list"
            )
            // The NEW name reads correctly on the same machine, which is the
            // half that is easy to lose: a Buddhist reading of "2026" is the
            // year 1483.
            XCTAssertEqual(
                ArchiveStamp.moment(from: "2026-08-09_141530", machineLocale: machine),
                ArchiveStampTests.moment,
                "\(spelling.calendar): the pinned spelling is read as itself"
            )
        }
    }

    /// The one that decides the shape of `ArchiveStamp.moment(from:)`.
    ///
    /// An Ethiopic Mac's old name for this moment is `2018-12-03_141530`, and
    /// **the Gregorian reading of that is a perfectly ordinary date** — unlike
    /// every other calendar's, which lands in the future or before the app
    /// existed. So "does it parse" cannot choose between the two readings, and
    /// neither can "is it a sensible date": only "could Plantoir have written
    /// it" can, because Plantoir did not exist in 2018.
    func testTheEthiopicNameIsToldApartByWhenPlantoirExisted() {
        let machine: Locale = Locale(identifier: "en_CA@calendar=ethiopic")
        let asGregorian: Date? = ArchiveStampTests.read("2018-12-03_141530", in: Locale(identifier: "en_US_POSIX"))
        XCTAssertNotNil(asGregorian, "2018-12-03 parses cleanly — that is the trap")
        XCTAssertFalse(
            ArchiveStamp.couldHaveBeenStamped(asGregorian!),
            "…but Plantoir could not have stamped it: there were no archives in 2018"
        )
        XCTAssertEqual(ArchiveStamp.moment(from: "2018-12-03_141530", machineLocale: machine), ArchiveStampTests.moment)
    }

    /// A name that could not have been written by Plantoir at all is refused,
    /// so the wizard's automatic zips and stray files stay out of both lists.
    func testSomethingThatIsNotAStampIsRefused() {
        XCTAssertNil(ArchiveStamp.moment(from: "not-a-date"))
        XCTAssertNil(ArchiveStamp.moment(from: ""))
        XCTAssertNil(ArchiveStamp.moment(from: "2026-08-09"))
    }

    /// Nothing that is listed today stops being listed.
    ///
    /// A zip carried here from a Buddhist-calendar Mac reads as the year 2569
    /// on this one, and there is no way to know it was ever anything else —
    /// guessing would mean deciding another machine's calendar on its behalf.
    /// It keeps the answer it has always had, and stays in the list.
    func testAStampNoReadingCanExplainKeepsTheAnswerItAlreadyHad() throws {
        let gregorianMac: Locale = Locale(identifier: "en_CA")
        let read: Date = try XCTUnwrap(ArchiveStamp.moment(from: "2569-08-09_141530", machineLocale: gregorianMac))
        let year: Int = Calendar(identifier: .gregorian).component(.year, from: read)
        XCTAssertEqual(year, 2569, "unchanged from what this Mac has always answered")
        XCTAssertFalse(ArchiveStamp.couldHaveBeenStamped(read))
    }

    /// A moment in the future cannot have been stamped, whatever the name
    /// says — that is what rules out the Buddhist and Hebrew readings.
    func testTheFutureAndThePastBeforePlantoirAreBothRefused() {
        let farFuture: Date = Date().addingTimeInterval(60 * 60 * 24 * 400)
        XCTAssertFalse(ArchiveStamp.couldHaveBeenStamped(farFuture))
        XCTAssertFalse(ArchiveStamp.couldHaveBeenStamped(Date(timeIntervalSince1970: 0)))
        XCTAssertTrue(ArchiveStamp.couldHaveBeenStamped(Date()))
        XCTAssertTrue(
            ArchiveStamp.couldHaveBeenStamped(ArchiveStampTests.moment),
            "the day the archive feature was written is not in the future"
        )
    }

    /// A name written now reads back to the same second, whatever calendar
    /// the Mac reading it is set to.
    func testTodaysNameReadsBackOnAnyMachine() {
        let written: String = ArchiveStamp.text(for: ArchiveStampTests.moment)
        for calendar in ["gregorian", "buddhist", "japanese", "islamic-umalqura", "ethiopic", "hebrew"] {
            XCTAssertEqual(
                ArchiveStamp.moment(from: written, machineLocale: Locale(identifier: "en_CA@calendar=\(calendar)")),
                ArchiveStampTests.moment,
                "read on a \(calendar) Mac"
            )
        }
    }

    /// How a Mac set to `calendar` spelled a moment before the fix — the same
    /// unpinned formatter the writer used to be.
    private static func spelled(_ moment: Date, in machineLocale: Locale) -> String {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = machineLocale
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = ArchiveStamp.format
        return formatter.string(from: moment)
    }

    private static func read(_ stamp: String, in locale: Locale) -> Date? {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = ArchiveStamp.format
        return formatter.date(from: stamp)
    }
}

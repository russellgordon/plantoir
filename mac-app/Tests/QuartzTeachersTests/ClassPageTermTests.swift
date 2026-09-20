import XCTest
@testable import QuartzTeachers

/// What a course calls a unit — and, more to the point, what a course that
/// says something else must NOT be told its pages are.
@MainActor
final class ClassPageTermTests: XCTestCase {

    // MARK: - The default, which every existing course relies on

    /// Absent and empty both mean "Unit". They are deliberately NOT
    /// distinguished the way `graded_folders` distinguishes them: there is no
    /// sensible reading of "the teacher cleared the word", and a course whose
    /// class pages had no name at all could not be built.
    func testAnAbsentOrEmptyWordMeansUnit() {
        XCTAssertEqual(ClassPageTerm.cleaned(nil), "Unit")
        XCTAssertEqual(ClassPageTerm.cleaned(""), "Unit")
        XCTAssertEqual(ClassPageTerm.cleaned("   "), "Unit")
        XCTAssertEqual(ClassPageTerm.term(inConfigurationValues: [:]), "Unit")
    }

    func testAWordIsTrimmed() {
        XCTAssertEqual(ClassPageTerm.cleaned("  Module "), "Module")
        XCTAssertEqual(ClassPageTerm.term(inConfigurationValues: ["unit_word": " Thread "]), "Thread")
    }

    // MARK: - What a word may not be

    /// Both refusals exist because the pages would be WRITTEN and then
    /// recognised by nothing — built successfully, and silently outside every
    /// feature that works on class pages.
    func testAWordWithANumberIsRefused() {
        XCTAssertNotNil(ClassPageTerm.problem(with: "Module2"))
    }

    func testAWordWithACommaIsRefused() {
        XCTAssertNotNil(ClassPageTerm.problem(with: "Module,"))
    }

    func testOrdinaryWordsAreAccepted() {
        XCTAssertNil(ClassPageTerm.problem(with: "Module"))
        XCTAssertNil(ClassPageTerm.problem(with: "Thread"))
        XCTAssertNil(ClassPageTerm.problem(with: "Learning Block"))
        XCTAssertNil(ClassPageTerm.problem(with: ""), "Empty means the default, not a mistake")
    }

    // MARK: - Naming and reading a page

    func testAPageIsNamedInTheCoursesOwnWord() {
        XCTAssertEqual(UnitDay(unit: 2, day: 3, term: "Module").title, "Module 2, Day 3")
        XCTAssertEqual(UnitDay(unit: 2, day: 3).title, "Unit 2, Day 3")
    }

    /// The one that fails silently if it is got wrong: in a Module course, a
    /// page still called "Unit 2, Day 3" is not a class page. Reading it as one
    /// would put two numbering schemes in one section.
    func testTheOtherWordsPagesAreNotClassPages() {
        XCTAssertNil(UnitDay(pageTitle: "Unit 2, Day 3", term: "Module"))
        XCTAssertNotNil(UnitDay(pageTitle: "Module 2, Day 3", term: "Module"))
    }

    /// A word from a teacher's configuration goes into a regular expression,
    /// so it has to be escaped. Unescaped, "Unit (A)" would either match
    /// something else entirely or fail to compile.
    func testARegularExpressionCharacterInTheWordIsTakenLiterally() {
        XCTAssertNotNil(UnitDay(pageTitle: "Unit (A) 2, Day 3", term: "Unit (A)"))
        XCTAssertNil(UnitDay(pageTitle: "Unit A 2, Day 3", term: "Unit (A)"))
    }

    /// A page read out of a course must be writable back into the same course
    /// without being handed the word a second time — which is why `UnitDay`
    /// carries it rather than looking it up.
    func testAPageReadKeepsItsWordWhenWrittenBack() {
        let read: UnitDay? = UnitDay(pageTitle: "Thread 4, Day 2", term: "Thread")
        XCTAssertEqual(read?.title, "Thread 4, Day 2")
        XCTAssertEqual(
            UnitDay(unit: read?.unit ?? 0, day: (read?.day ?? 0) + 1, term: read?.term ?? "").title,
            "Thread 4, Day 3"
        )
    }

    /// The planners all work from `[ClassPageSummary]`, so the word has to
    /// travel on the summary or every one of them would need the course too.
    func testASummaryCarriesTheWordToThePlanners() {
        let summary = ClassPageSummary(
            title: "Module 3, Day 1",
            fileURL: URL(fileURLWithPath: "/tmp/Module 3, Day 1.md"),
            date: nil,
            term: "Module"
        )
        XCTAssertEqual(summary.unitAndDay?.unit, 3)
        XCTAssertEqual(
            NextClassPlanner.nextUnitAndDay(after: [summary], term: "Module").title,
            "Module 3, Day 2"
        )
        XCTAssertEqual(
            NextClassPlanner.firstDayOfANewUnit(after: [summary], term: "Module").title,
            "Module 4, Day 1"
        )
    }

    /// A section with nothing in it yet still has to start in the right word.
    func testAnEmptySectionStartsInTheCoursesWord() {
        XCTAssertEqual(
            NextClassPlanner.nextUnitAndDay(after: [], term: "Thread").title, "Thread 1, Day 1"
        )
    }
}

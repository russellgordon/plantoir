import Foundation
@testable import QuartzTeachers

// Test-only ways to name a page by its WORD alone, meaning the ordinary
// "Unit 2, Day 3" scheme.
//
// The product's `UnitDay`, `ClassPageSummary` and next-class helpers take a
// `ClassPageNaming` with NO default, deliberately (#267): a planner path that
// forgot to say which course's naming it uses would otherwise write
// "Week 1, Day 10" into a club with every test green. Tests written before
// the scheme existed ask about the ordinary scheme, and saying so at every
// one of their call sites would bury what they test. These conveniences live
// in the TEST target only, so the product still cannot reach a default.

extension UnitDay {

    // MARK: - Initializer

    init(unit: Int, day: Int, term: String = ClassPageTerm.standard) {
        self.init(unit: unit, day: day, naming: ClassPageNaming(word: term, scheme: .unitDay))
    }

    init?(pageTitle: String, term: String = ClassPageTerm.standard) {
        self.init(pageTitle: pageTitle, naming: ClassPageNaming(word: term, scheme: .unitDay))
    }
}

@MainActor
extension ClassPageSummary {

    // MARK: - Initializer

    init(title: String, fileURL: URL, date: CalendarDay?, term: String = ClassPageTerm.standard) {
        self.init(
            title: title, fileURL: fileURL, date: date,
            naming: ClassPageNaming(word: term, scheme: .unitDay)
        )
    }
}

@MainActor
extension NextClassPlanner {

    // MARK: - Functions

    static func nextUnitAndDay(
        after pages: [ClassPageSummary], term: String = ClassPageTerm.standard
    ) -> UnitDay {
        return nextUnitAndDay(after: pages, naming: ClassPageNaming(word: term, scheme: .unitDay))
    }

    static func firstDayOfANewUnit(
        after pages: [ClassPageSummary], term: String = ClassPageTerm.standard
    ) -> UnitDay {
        return firstDayOfANewUnit(after: pages, naming: ClassPageNaming(word: term, scheme: .unitDay))
    }
}

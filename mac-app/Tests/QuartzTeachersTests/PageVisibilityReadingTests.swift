import XCTest
@testable import QuartzTeachers

/// The three-way reading of a page's visibility flag.
///
/// `contracts/file-formats.json` → `pageVisibility.readingCases` carries the
/// answers the two apps must agree on, and `FileFormatsContractTests` runs
/// those. This file covers the half the shared list deliberately leaves out:
/// the forms where this app says `cannotTell`, and the corners it handles
/// rather than refusing.
///
/// The shared list cannot carry the `cannotTell` forms, because a case there
/// states what the SITE does and this app's reporting answer is `visible`
/// whatever the site does. Pinning `expectVisible: true` for a form the site
/// HIDES — a value on the line below the key, say — would oblige Windows to be
/// wrong in the same direction rather than merely allow it. So they are pinned
/// here, at the level where the answer is honest: `cannotTell` is its own
/// answer, reporting collapses it to visible, and nothing that writes to a
/// teacher's file is allowed to collapse it at all.
///
/// Everything asserted here about what the BUILD does was measured on
/// 2026-09-18 by running the form through the real image — python-frontmatter
/// 1.3.0 / PyYAML 6.0.3, then gray-matter with js-yaml on `JSON_SCHEMA`, then
/// `patches/publish.ts`'s own expression. `verify.sh` re-runs that measurement
/// for every shared case on every run.
@MainActor
final class PageVisibilityReadingTests: XCTestCase {

    // MARK: - Functions

    /// A frontmatter fragment, as a whole page.
    private func page(_ frontmatter: String) -> String {
        return "---\n" + frontmatter + "\n---\n\nThe lesson.\n"
    }

    private func answer(_ frontmatter: String, section: Int = 1) -> PageVisibilityAnswer {
        return PageVisibilityReader.answer(in: page(frontmatter), forSection: section)
    }

    // MARK: - The forms this app refuses to guess at

    /// Each of these is a page the BUILD has a definite opinion about. This
    /// app does not, and says so rather than picking a side.
    func testTheFormsThisAppWillNotGuessAt() {
        // Measured: the build HIDES every one of these.
        XCTAssertEqual(answer("publish:\n  false"), .cannotTell,
                       "The value is on the next line. The build reads it; a line reader does not.")
        XCTAssertEqual(answer("publish: !!str false"), .cannotTell,
                       "A tag changes what the value IS.")
        XCTAssertEqual(answer("publish: >-\n  false"), .cannotTell,
                       "A folded block scalar: the value is not on this line at all.")
        XCTAssertEqual(answer("publish: |-\n  false"), .cannotTell,
                       "Nor a literal one.")
        XCTAssertEqual(answer("publish: &flag false"), .cannotTell,
                       "An anchor.")
        XCTAssertEqual(answer("flag: &flag false\npublish: *flag"), .cannotTell,
                       "And an alias pointing at one.")
        XCTAssertEqual(answer("publish: \"fal\\u0073e\""), .cannotTell,
                       "An escape inside double quotes: these characters are not the value.")
        XCTAssertEqual(answer("publish: 'fal''se'"), .cannotTell,
                       "`''` is how a single-quoted string spells one quote.")
        XCTAssertEqual(answer("publish: \"false"), .cannotTell,
                       "An unbalanced quote. The build cannot parse this page at all.")

        // Measured: the build PUBLISHES these, but each could run over more
        // than one line, and getting a flow collection wrong is not worth the
        // few teachers who would ever write one.
        XCTAssertEqual(answer("publish: [false]"), .cannotTell,
                       "A flow sequence.")
        XCTAssertEqual(answer("publish: {a: false}"), .cannotTell,
                       "A flow mapping.")

        // Measured: the build stops entirely on these, so there is no site
        // verdict to mirror.
        XCTAssertEqual(answer("title: x\n\tpublish: false"), .cannotTell,
                       "A tab used as indentation is YAML the parser throws on.")
        XCTAssertEqual(
            PageVisibilityReader.answer(in: "---\npublish: false\nBody.\n", forSection: 1),
            .cannotTell,
            "An opening fence with no closing one is not frontmatter this app should read."
        )
    }

    /// A key of one of the four names, indented under something else. It may
    /// be nothing to do with the page, and it may be everything.
    func testAnIndentedKeyIsNotThisPagesFlag() {
        XCTAssertEqual(answer("meta:\n  publish: false"), .cannotTell)
        XCTAssertEqual(answer("something:\n  draft: true"), .cannotTell)
    }

    /// The whole reason `cannotTell` exists as a separate answer.
    func testReportingErrsVisibleAndNeverHidden() {
        let unreadable: String = page("publish: !!str false")
        XCTAssertEqual(
            AssistPageVisibility.statedPublishing(in: unreadable, forSection: 1), true,
            "Reporting collapses cannot-tell to VISIBLE. Calling a page hidden while "
            + "students are reading it is the failure that reports success."
        )
        XCTAssertTrue(AssistPageVisibility.publishes(in: unreadable, forSection: 1))
    }

    /// And the reason no writer is allowed to believe that.
    func testAWriterWritesTheFlagOutRatherThanTrustingTheCollapse() {
        let unreadable: String = "---\npublish: !!str false\n---\nBody.\n"
        let published = AssistPageVisibility.setting(
            published: true, in: unreadable, forSection: 1, isSectionLocal: true
        )
        XCTAssertTrue(published.changed,
                      "Reporting says this page is visible; the writer must not act on that")
        XCTAssertEqual(published.text, "---\npublish: true\n---\nBody.\n")

        let hidden = AssistPageVisibility.setting(
            published: false, in: unreadable, forSection: 1, isSectionLocal: true
        )
        XCTAssertTrue(hidden.changed)
        XCTAssertEqual(hidden.text, "---\npublish: false\n---\nBody.\n")
    }

    /// A page that already SAYS what was asked, however oddly it says it, is
    /// left alone — and that is a CONFIDENT reading, not a collapsed one.
    func testAPageThatAlreadySaysItIsLeftAlone() {
        for value in ["maybe", "on", "true # why", "\"False\"", "y"] {
            let text: String = "---\npublish: \(value)\n---\nBody.\n"
            let result = AssistPageVisibility.setting(
                published: true, in: text, forSection: 1, isSectionLocal: true
            )
            XCTAssertFalse(result.changed, "publish: \(value) already publishes this page")
            XCTAssertEqual(result.text, text)
        }
        for value in ["no", "off", "FALSE", "false # not ready"] {
            let text: String = "---\npublish: \(value)\n---\nBody.\n"
            let result = AssistPageVisibility.setting(
                published: false, in: text, forSection: 1, isSectionLocal: true
            )
            XCTAssertFalse(result.changed, "publish: \(value) already holds this page back")
            XCTAssertEqual(result.text, text)
        }
    }

    // MARK: - The corners this app handles rather than refusing

    func testAPageWithNoFrontmatterSaysNothing() {
        XCTAssertEqual(
            PageVisibilityReader.answer(in: "Just a page.\n", forSection: 1), .saysNothing
        )
        XCTAssertEqual(answer("title: Unit 1, Day 1"), .saysNothing)
    }

    func testABlankLineBeforeTheOpeningFenceIsStillFrontmatter() {
        // Measured: python-frontmatter accepts it, so the build reads the
        // block and hides the page.
        XCTAssertEqual(
            PageVisibilityReader.answer(in: "\n---\npublish: false\n---\nBody.\n", forSection: 1),
            .hidden
        )
    }

    func testAWindowsWrittenFileReadsTheSame() {
        XCTAssertEqual(
            PageVisibilityReader.answer(in: "---\r\npublish: false\r\n---\r\nBody.\r\n", forSection: 1),
            .hidden,
            "A trailing carriage return is not part of the value"
        )
    }

    func testWhitespaceAroundTheValueIsNotPartOfIt() {
        XCTAssertEqual(answer("publish:\tfalse"), .hidden, "A tab after the colon")
        XCTAssertEqual(answer("publish:     false"), .hidden, "Several spaces")
        XCTAssertEqual(answer("publish: false   "), .hidden, "Trailing spaces")
    }

    func testTheLastOfTwoIdenticalKeysWins() {
        XCTAssertEqual(answer("publish: true\npublish: false"), .hidden)
        XCTAssertEqual(answer("publish: false\npublish: true"), .visible)
        XCTAssertEqual(answer("draftSection1: true\ndraftSection1: false"), .visible)
    }

    func testTheFourKeysAreConsultedInTheBuildsOwnOrder() {
        XCTAssertEqual(answer("publishForSection1: false\npublish: true"), .hidden)
        XCTAssertEqual(answer("publish: false\ndraftSection1: false"), .hidden)
        XCTAssertEqual(answer("draftSection1: true\ndraft: false"), .hidden)
        XCTAssertEqual(answer("publishForSection2: false", section: 1), .saysNothing,
                       "A key naming another section is deleted unread by the build")
    }

    func testAKeyThatIsNullPublishesThePage() {
        XCTAssertEqual(answer("publish:"), .visible)
        XCTAssertEqual(answer("publish: ~"), .visible)
        XCTAssertEqual(answer("publish: null"), .visible)
        XCTAssertEqual(answer("publish: NULL"), .visible)
        XCTAssertEqual(answer("publish: #why"), .visible,
                       "A value that is nothing but a comment is null too")
        XCTAssertEqual(answer("publish:\ntitle: x"), .visible,
                       "Nothing after the colon and nothing indented below it")
        XCTAssertEqual(answer("draft:"), .visible)
    }

    func testACommentIsOnlyAComment() {
        XCTAssertEqual(answer("publish: true # why"), .visible)
        XCTAssertEqual(answer("publish: false # why"), .hidden)
        XCTAssertEqual(answer("publish: true#x"), .visible,
                       "No space before the hash, so it is part of the string")
        XCTAssertEqual(answer("publish: false#x"), .visible,
                       "Same rule, and here it changes the answer")
        XCTAssertEqual(answer("publish: \"a # false\""), .visible,
                       "A hash inside quotes is not a comment")
        XCTAssertEqual(answer("publish: \"false\" # why"), .hidden,
                       "And a comment after a quoted value is still a comment")
    }

    func testQuotingChangesTheAnswerBothWays() {
        XCTAssertEqual(answer("publish: \"false\""), .hidden)
        XCTAssertEqual(answer("publish: \"False\""), .visible,
                       "One capital letter apart, because publish.ts compares strings exactly")
        XCTAssertEqual(answer("publish: 'no'"), .visible,
                       "Quoted, `no` never becomes the boolean")
        XCTAssertEqual(answer("draft: \"yes\""), .visible)
        XCTAssertEqual(answer("draft: yes"), .hidden)
        XCTAssertEqual(answer("draft: \"true\""), .hidden)
        XCTAssertEqual(answer("draft: '  true  '"), .hidden,
                       "The build trims a string before comparing it with \"true\"")
    }

    func testTheNineSpellingsAndNothingElse() {
        for spelling in ["true", "True", "TRUE", "yes", "Yes", "YES", "on", "On", "ON"] {
            XCTAssertEqual(answer("publish: " + spelling), .visible, spelling)
            XCTAssertEqual(answer("draft: " + spelling), .hidden, spelling)
        }
        for spelling in ["false", "False", "FALSE", "no", "No", "NO", "off", "Off", "OFF"] {
            XCTAssertEqual(answer("publish: " + spelling), .hidden, spelling)
            XCTAssertEqual(answer("draft: " + spelling), .visible, spelling)
        }
        for spelling in ["tRue", "fAlSe", "nO", "oN", "oFf", "y", "n", "Y", "N", "0", "1", "maybe"] {
            XCTAssertEqual(answer("publish: " + spelling), .visible,
                           "\(spelling) is an ordinary string, and a string that is not \"false\" publishes")
        }
        for spelling in ["TrUe", "\"true\"", "\"True\""] {
            XCTAssertEqual(answer("draft: " + spelling), .hidden,
                           "\(spelling) lowercases to \"true\", which is what the build compares")
        }
        for spelling in ["maybe", "1", "y", "\"yes\""] {
            XCTAssertEqual(answer("draft: " + spelling), .visible, spelling)
        }
    }

    func testAKeySpelledTheOtherLegalWays() {
        XCTAssertEqual(answer("publish : false"), .hidden, "A space before the colon")
        XCTAssertEqual(answer("\"publish\": false"), .hidden, "A quoted key")
        XCTAssertEqual(answer("'publish': false"), .hidden, "Quoted the other way")
        XCTAssertEqual(answer("published: false"), .saysNothing,
                       "`published` is a different key and says nothing about this page")
        XCTAssertEqual(answer("publishForSection11: false", section: 1), .saysNothing,
                       "Nor is section 11 section 1")
    }

    /// Reading does not depend on where the page lives — the build consults
    /// all four keys on every page it copies. This was the mac's own blind
    /// spot until 2026-09-18.
    func testWhereThePageLivesChangesNothingAboutTheRead() {
        XCTAssertEqual(answer("publish: false", section: 2), .hidden,
                       "A plain publish on a course-level page still counts")
        XCTAssertEqual(answer("publishForSection1: false", section: 1), .hidden,
                       "And a per-section key on a page inside a section's folder does too")
    }
}

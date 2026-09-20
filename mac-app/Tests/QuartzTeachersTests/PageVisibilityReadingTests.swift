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
/// The shared list mostly cannot carry the `cannotTell` forms, because a case
/// there states what the SITE does and this app's reporting answer is
/// `visible` whatever the site does. Pinning `expectVisible: true` for a form
/// the site HIDES — a value on the line below an EMPTY key, say — would oblige
/// Windows to be wrong in the same direction rather than merely allow it. So
/// they are pinned here, at the level where the answer is honest: `cannotTell`
/// is its own answer, reporting collapses it to visible, and nothing that
/// writes to a teacher's file is allowed to collapse it at all.
///
/// **With one deliberate exception since 2026-09-19** (issue #176), in the
/// contract note's own words: where the REPORTING answer and the site agree, a
/// shared case obliges nobody to be wrong. The test is not "can the reader
/// read it" but "does the reporting answer match the site" — and for two
/// continuation forms it does, because the site PUBLISHES them. So
/// `publish: false` over an indented `false`, with and without a blank line
/// between, ARE in `readingCases`, and they earn the place because the reader
/// that got them wrong got them wrong CONFIDENTLY, which is what let a
/// writer's already-right gate turn "hide this page" into a no-op. Their
/// polarity siblings (`no`, `off`, `FALSE`, `true`, `maybe` with a value
/// below) are equally honest and add nothing those two do not, so they stay
/// here — see `testAValueBelowACompleteLookingOneIsStillAValueBelow`.
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

    /// More of the same, each measured after the first round of review.
    func testTheFormsTheBuildItselfCannotRead() {
        // Measured: each of these STOPS the build, so there is no site verdict
        // to mirror and this reader must not offer one. Reading them as
        // ordinary strings called them all published.
        XCTAssertEqual(answer("publish: - false"), .cannotTell, "A sequence entry on the key's line")
        XCTAssertEqual(answer("publish: %"), .cannotTell, "A directive indicator")
        XCTAssertEqual(answer("publish: @x"), .cannotTell, "A character YAML reserves")
        XCTAssertEqual(answer("publish: `x"), .cannotTell, "And another")
        XCTAssertEqual(answer("publish: false: true"), .cannotTell, "A mapping where a scalar goes")
    }

    /// A value below the key, over a blank line. Measured: the build reads it
    /// and HIDES the page.
    func testAValueBelowTheKeyIsNotFollowedEvenOverABlankLine() {
        XCTAssertEqual(answer("publish:\n\n  false"), .cannotTell)
        XCTAssertEqual(answer("draft:\n\n  true"), .cannotTell)
        XCTAssertEqual(answer("publishForSection1:\n  false"), .cannotTell)
    }

    /// A colon has to be followed by a space, a tab or the end of the line, or
    /// the line is not a mapping at all.
    func testAColonWithNoSpaceAfterItIsNotAKey() {
        // Measured: a page whose whole frontmatter is `publish:false` reaches
        // Quartz with NO keys and is published; one with another key beside it
        // stops the build. Either way this is not the page's flag, and reading
        // it as one called a live page hidden.
        XCTAssertEqual(answer("publish:false"), .saysNothing)
        XCTAssertEqual(answer("publish:true"), .saysNothing)
        XCTAssertEqual(answer("draft:true"), .saysNothing)
    }

    /// YAML's whitespace is a space and a tab, and the Mac's Option-Space is
    /// neither.
    func testOnlySpacesAndTabsAreWhitespace() {
        // Measured: `publish: false<NBSP>` beside another key is the STRING
        // "false\u{00A0}" and the page is PUBLISHED.
        XCTAssertEqual(answer("publish: false\u{00A0}\ntitle: x"), .visible)
        XCTAssertEqual(answer("publish:\u{00A0}false"), .saysNothing,
                       "A non-breaking space after the colon does not make this a mapping")
        XCTAssertEqual(answer("publish: false\t"), .hidden, "A tab is whitespace, and this is hidden")
    }

    /// python-frontmatter's fence is three dashes OR MORE.
    func testALongerFenceIsStillFrontmatter() {
        // Measured: both of these hide the page. Requiring exactly `---` read
        // them as pages with no frontmatter at all, which is "visible".
        XCTAssertEqual(
            PageVisibilityReader.answer(in: "----\npublish: false\n----\nBody.\n", forSection: 1),
            .hidden
        )
        XCTAssertEqual(
            PageVisibilityReader.answer(in: "---\npublish: false\n----\nBody.\n", forSection: 1),
            .hidden
        )
    }

    /// An indented `# note` is a comment, not a value.
    func testAnIndentedCommentIsNotAValue() {
        // Measured: each of these is what a line reader would say anyway —
        // which is the point, since the value-below rule must not swallow a
        // comment and call a published page unreadable.
        XCTAssertEqual(answer("publish: true\n  # mine"), .visible)
        XCTAssertEqual(answer("publish:\n  # mine"), .visible,
                       "A key with only a comment under it is still a null, which publishes")
        XCTAssertEqual(answer("publish:\n  # mine\n  false"), .cannotTell,
                       "But a real value under the comment is a value this reader will not follow")
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

    /// The writer must rewrite the line the READER read, or the two disagree
    /// about which line the build is looking at.
    func testTheWriterRewritesTheLineTheReaderRead() {
        // A quoted key was invisible to the writer's plain prefix test, so it
        // inserted a SECOND `publish: true` above it — and PyYAML keeps the
        // LAST of two, so the page stayed hidden while the teacher was told it
        // had been published. Measured through the real build.
        // The line is rebuilt in the plain spelling, which is the point: one
        // line changes, and the page really says what the teacher asked for.
        for frontmatter in ["\"publish\": false", "publish : false", "'publish': false"] {
            let before: String = "---\n\(frontmatter)\n---\nBody.\n"
            let published = AssistPageVisibility.setting(
                published: true, in: before, forSection: 1, isSectionLocal: true
            )
            XCTAssertEqual(published.text, "---\npublish: true\n---\nBody.\n", frontmatter)
            XCTAssertEqual(
                PageVisibilityReader.answer(in: published.text, forSection: 1), .visible,
                "\(frontmatter) — inserting a second key above this one left the page hidden"
            )
        }
    }

    /// The writer has to find the same BLOCK the reader found, or it edits a
    /// different page from the one it read.
    ///
    /// Measured: prepending a block of its own leaves the teacher's real
    /// frontmatter behind it as BODY TEXT, printed to their students.
    func testTheWriterEditsTheBlockTheReaderFound() {
        let longerFence: String = "----\npublish: false\n----\nBody.\n"
        let published = AssistPageVisibility.setting(
            published: true, in: longerFence, forSection: 1, isSectionLocal: true
        )
        XCTAssertEqual(published.text, "----\npublish: true\n----\nBody.\n")

        let blankFirst: String = "\n---\npublish: false\n---\nBody.\n"
        let second = AssistPageVisibility.setting(
            published: true, in: blankFirst, forSection: 1, isSectionLocal: true
        )
        XCTAssertEqual(second.text, "\n---\npublish: true\n---\nBody.\n")

        let mismatchedClose: String = "---\npublish: false\n----\nBody.\n"
        let third = AssistPageVisibility.setting(
            published: true, in: mismatchedClose, forSection: 1, isSectionLocal: true
        )
        XCTAssertEqual(third.text, "---\npublish: true\n----\nBody.\n")
    }

    /// And it must rewrite the LAST of two, because that is the one the build
    /// reads.
    func testTheWriterSetsTheLastOfTwoIdenticalKeys() {
        let twice: String = "---\npublish: true\npublish: false\ntitle: x\n---\nBody.\n"
        let published = AssistPageVisibility.setting(
            published: true, in: twice, forSection: 1, isSectionLocal: true
        )
        XCTAssertEqual(published.text, "---\npublish: true\npublish: true\ntitle: x\n---\nBody.\n")
        XCTAssertEqual(
            PageVisibilityReader.answer(in: published.text, forSection: 1), .visible,
            "Setting the FIRST of two would have left this page hidden"
        )

        let legacyTwice: String = "---\ndraft: false\ndraft: true\n---\nBody.\n"
        let hidden = AssistPageVisibility.setting(
            published: false, in: legacyTwice, forSection: 1, isSectionLocal: true
        )
        XCTAssertEqual(hidden.text, "---\npublish: false\n---\nBody.\n",
                       "Migrating takes the last legacy line and removes the earlier ones")
    }

    // MARK: - A value that lives on the lines BELOW its key

    /// A whole page from a frontmatter fragment, written the way a teacher's
    /// file really is — one trailing newline, and body text under the block.
    private func file(_ frontmatter: String) -> String {
        return "---\n" + frontmatter + "\n---\nBody.\n"
    }

    /// A key's value can live on the lines below it, and those lines go
    /// wherever the key's line goes.
    ///
    /// **Leaving them behind is the failure that reports success.** Measured
    /// 2026-09-19 through the real image — python-frontmatter 1.3.0 / PyYAML
    /// 6.0.3 / CPython 3.11.15, then gray-matter with js-yaml on
    /// `JSON_SCHEMA`, then `patches/publish.ts`'s own expression — for every
    /// row below, three times over: the page before the write, the page it
    /// becomes if the key's line is replaced and the lines under it are LEFT,
    /// and the page it becomes when they go with the key.
    ///
    /// * Rows 1, 2, 4, 5, 10, 15: HIDDEN before, **VISIBLE** if the
    ///   continuation is left behind (PyYAML folds the two lines into one
    ///   plain scalar — `"false false"`, a string that is not `"false"`),
    ///   HIDDEN when it is swept. A teacher asking for such a page to be
    ///   hidden was told it had been, and students went on reading it.
    /// * Rows 6, 7, 11, 12, 13, 14, 16: the orphan is a mapping, a column-0
    ///   comment or a column-0 sequence, and the page STOPS BUILDING instead
    ///   — `bad indentation of a mapping entry`, or `end of the stream or a
    ///   document separator is expected`. Swept, every one of them is HIDDEN.
    /// * Rows 15 and 16 are pages the build could not read BEFORE the write
    ///   either; the sweep repairs them.
    ///
    /// The mirror of Windows' `AValuesContinuationLinesGoWithIt`, whose 14
    /// rows are all here. Rows 15 and 16 are the mac's own: row 15 cannot be
    /// a shared contract case, because Windows' `ReplaceValue` keeps the
    /// inline `# why` where this app's whole-line rebuild drops it (both land
    /// HIDDEN, and only the bytes differ).
    func testAValuesContinuationLinesGoWithIt() {
        let rows: [(frontmatter: String, publish: Bool, expected: String)] = [
            ("publish: >-\n  false\ntitle: x", false, "publish: false\ntitle: x"),
            ("publish: |-\n  false\ntitle: x", false, "publish: false\ntitle: x"),
            ("publish: >-\n  false\ntitle: x", true, "publish: true\ntitle: x"),
            ("publish:\n  false\ntitle: x", false, "publish: false\ntitle: x"),
            ("publish:\n\n  false\ntitle: x", false, "publish: false\ntitle: x"),
            ("publish:\n  # n\n  false\ntitle: x", false, "publish: false\ntitle: x"),
            ("publish:\n  a: 1\ntitle: x", false, "publish: false\ntitle: x"),
            ("publish: >-\n  false", false, "publish: false"),
            (
                "publish: true\npublish: >-\n  false\ntitle: x", false,
                "publish: true\npublish: false\ntitle: x"
            ),
            ("draft: >-\n  true\ntitle: x", false, "publish: false\ntitle: x"),
            ("publish:\n# note\n  false\ntitle: x", false, "publish: false\ntitle: x"),
            ("publish:\n- a\ntitle: x", false, "publish: false\ntitle: x"),
            ("publish:\n- a\n- b\ntitle: x", false, "publish: false\ntitle: x"),
            ("draft:\n- a\ntitle: x", false, "publish: false\ntitle: x"),
            ("publish: false # why\n  false\ntitle: x", false, "publish: false\ntitle: x"),
            ("publish: false\n  # note\n  false\ntitle: x", false, "publish: false\ntitle: x"),
        ]

        for row in rows {
            let result = AssistPageVisibility.setting(
                published: row.publish, in: file(row.frontmatter), forSection: 1,
                isSectionLocal: true
            )
            XCTAssertTrue(result.changed, row.frontmatter)
            XCTAssertEqual(result.text, file(row.expected), row.frontmatter)
            XCTAssertEqual(
                PageVisibilityReader.answer(in: result.text, forSection: 1),
                row.publish ? .visible : .hidden,
                "\(row.frontmatter) — the page has to READ the way it was asked to"
            )
        }
    }

    /// A key's line can LOOK complete and still have its value continue below
    /// it — and this is the row that bit, because the old reader answered
    /// `hidden` about it CONFIDENTLY.
    ///
    /// Measured 2026-09-19: every one of these six pages is PUBLISHED by the
    /// site. YAML folds the key's line and the line below into one plain
    /// scalar — `"false false"`, `"no false"`, `"maybe false"` — and a string
    /// that is not `"false"` publishes.
    ///
    /// So the writer's "already right, change nothing" gate believed the
    /// reader, returned before the writer or its continuation sweep ran at
    /// all, and "hide this page" was a NO-OP: the file untouched, the teacher
    /// told it was already hidden, and students still reading it. A sweep in
    /// the writer cannot save a page the writer is never asked to write.
    func testAValueBelowACompleteLookingOneIsStillAValueBelow() {
        for value in ["false", "no", "off", "FALSE", "true", "maybe"] {
            let frontmatter: String = "publish: \(value)\n  false\ntitle: x"
            let pageText: String = file(frontmatter)

            XCTAssertEqual(
                PageVisibilityReader.answer(in: pageText, forSection: 1), .cannotTell,
                "publish: \(value) with a value under it is not a value this app can read"
            )
            XCTAssertTrue(
                AssistPageVisibility.publishes(in: pageText, forSection: 1),
                "Reporting collapses it to visible — and here that is what the site does"
            )

            let hidden = AssistPageVisibility.setting(
                published: false, in: pageText, forSection: 1, isSectionLocal: true
            )
            XCTAssertTrue(
                hidden.changed,
                "publish: \(value) — asking to hide this page must not be a no-op"
            )
            XCTAssertEqual(hidden.text, file("publish: false\ntitle: x"), value)
            XCTAssertEqual(
                PageVisibilityReader.answer(in: hidden.text, forSection: 1), .hidden, value
            )
        }
    }

    /// And a BLANK LINE does not end a value either — the row a reader that
    /// looked only at the next physical line would miss.
    ///
    /// Measured: the fold is `"false\nfalse"`, still a string that is not
    /// `"false"`, so the site PUBLISHES the page.
    func testABlankLineDoesNotEndAValueEither() {
        let pageText: String = file("publish: false\n\n  false\ntitle: x")
        XCTAssertEqual(PageVisibilityReader.answer(in: pageText, forSection: 1), .cannotTell)
        XCTAssertTrue(AssistPageVisibility.publishes(in: pageText, forSection: 1))

        let hidden = AssistPageVisibility.setting(
            published: false, in: pageText, forSection: 1, isSectionLocal: true
        )
        XCTAssertTrue(hidden.changed)
        XCTAssertEqual(hidden.text, file("publish: false\ntitle: x"))
        XCTAssertEqual(PageVisibilityReader.answer(in: hidden.text, forSection: 1), .hidden)
    }

    /// The other side of the same rule, and the guard that stops the sweep
    /// over-reaching: a `# note` with no value under it is the teacher's, and
    /// it stays exactly where they wrote it.
    ///
    /// Measured: PyYAML ignores each of these lines entirely — the page is
    /// published before the write and HIDDEN after it, note and all.
    func testAnIndentedNoteAfterACompleteValueIsLeftAlone() {
        let rows: [(frontmatter: String, expected: String)] = [
            (
                "publish: true\n  # the teacher's note\ntitle: x",
                "publish: false\n  # the teacher's note\ntitle: x"
            ),
            ("publish:\n  # mine\ntitle: x", "publish: false\n  # mine\ntitle: x"),
            (
                "publish: true\n# a note about title\ntitle: x",
                "publish: false\n# a note about title\ntitle: x"
            ),
        ]
        for row in rows {
            let hidden = AssistPageVisibility.setting(
                published: false, in: file(row.frontmatter), forSection: 1, isSectionLocal: true
            )
            XCTAssertTrue(hidden.changed, row.frontmatter)
            XCTAssertEqual(hidden.text, file(row.expected), row.frontmatter)
            XCTAssertEqual(
                PageVisibilityReader.answer(in: hidden.text, forSection: 1), .hidden,
                row.frontmatter
            )
        }
    }

    /// And the second guard: a column-0 sequence is only a key's value when
    /// the key's own value is EMPTY.
    ///
    /// Measured: `publish: true` with `- a` under it does not build either way
    /// — `end of the stream or a document separator is expected` — so there is
    /// nothing to rescue, and sweeping a teacher's list on that guess would be
    /// the larger mistake. The key's line is corrected and nothing else moves.
    func testAColumn0SequenceUnderAKeyThatHasAValueIsNotSwept() {
        let hidden = AssistPageVisibility.setting(
            published: false, in: file("publish: true\n- a\ntitle: x"), forSection: 1,
            isSectionLocal: true
        )
        XCTAssertTrue(hidden.changed)
        XCTAssertEqual(hidden.text, file("publish: false\n- a\ntitle: x"))
        XCTAssertEqual(
            PageVisibilityReader.answer(in: hidden.text, forSection: 1), .hidden,
            "The line the build would read says false — the page's own YAML is what stops it"
        )
    }

    /// A file written on Windows keeps its line endings, including on the
    /// lines the sweep removes.
    ///
    /// Measured: the swept CRLF page is HIDDEN on the site.
    func testSweepingAContinuationOutOfACrlfFileLeavesCrlfBehind() {
        let windowsWritten: String = "---\r\npublish: >-\r\n  false\r\ntitle: x\r\n---\r\nBody.\r\n"
        let hidden = AssistPageVisibility.setting(
            published: false, in: windowsWritten, forSection: 1, isSectionLocal: true
        )
        XCTAssertTrue(hidden.changed)
        XCTAssertEqual(hidden.text, "---\r\npublish: false\r\ntitle: x\r\n---\r\nBody.\r\n")
        XCTAssertEqual(PageVisibilityReader.answer(in: hidden.text, forSection: 1), .hidden)
    }

    // MARK: - What the corrected reading changes for a teacher

    /// A re-date that runs off the end of the timetable now HIDES such a page,
    /// where before it left it alone.
    ///
    /// This is the second teacher-visible consequence of the reader change,
    /// and it is a WRITE rather than a sentence: `SectionReDatePlanner` asks
    /// `unpublishes = isOverflow && page.isVisibleToStudents`, and a page whose
    /// flag reads `cannotTell` is now visible-and-uncertain where it used to be
    /// hidden-and-certain. It is the right direction — measured, the site
    /// PUBLISHES this page, so a class pushed past the last day of the
    /// timetable really was still in front of students.
    ///
    /// (The first consequence has no test of its own because it is an absence:
    /// such a page stops appearing in `ScheduledDeploy`'s "classes students
    /// cannot see yet" list, for the same reason and in the same direction.)
    @MainActor
    func testARedateThatOverflowsNowHidesAPageWhoseValueContinues() throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        let plan: RememberTimetablePlan = try SectionTimetableStore.planRememberTimetable(
            dates: ["2026-09-08"], source: "timetable.xlsx, block H", forSection: 1,
            in: made.course
        )
        try SectionTimetableStore.applyRememberTimetable(plan)
        try AssistFixture.write(
            page: "Unit 1, Day 1", publish: "false", date: "2026-09-08", body: "one",
            in: made.course
        )
        // The whole point: a key line that LOOKS complete, with its value
        // continuing below it. The site publishes this page.
        try AssistFixture.write(
            page: "Unit 1, Day 2", publish: "false\n  false", date: "2026-09-10", body: "two",
            in: made.course
        )

        let overflowURL: URL = AssistFixture.pageURL(of: "Unit 1, Day 2", in: made.course)
        XCTAssertEqual(
            PageVisibilityReader.answer(
                in: try String(contentsOf: overflowURL, encoding: .utf8), forSection: 1
            ),
            .cannotTell
        )

        let reDate: SectionReDatePlan = try SectionReDatePlanner.plan(
            forSection: 1, in: made.course, workspaceURL: made.root
        )
        var overflowMove: ReDatedPage? = nil
        for move in reDate.moves where move.title == "Unit 1, Day 2" {
            overflowMove = move
        }
        XCTAssertEqual(
            try XCTUnwrap(overflowMove).unpublishes, true,
            "A class past the last day of the timetable is one students can still see"
        )

        _ = try SectionReDatePlanner.apply(reDate, forSection: 1, in: made.course)
        let after: String = try String(contentsOf: overflowURL, encoding: .utf8)
        XCTAssertTrue(after.contains("publish: false\n"), after)
        XCTAssertFalse(after.contains("\n  false"), "The continuation went with the key")
        XCTAssertEqual(PageVisibilityReader.answer(in: after, forSection: 1), .hidden)
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

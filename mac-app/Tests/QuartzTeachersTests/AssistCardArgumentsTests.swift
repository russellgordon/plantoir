import XCTest
@testable import QuartzTeachers

/// Every argument a card sends ARRIVES — the mac's counterpart of Windows'
/// `TheCardsArgumentsReachTheToolThatReadsThem` (#150, from Windows' #70).
///
/// **Arrival, not presence, and on this side that means removal.** Windows
/// checks that each key a card sends is declared on its tool's schema,
/// because there a binder drops any key the schema does not name (#116,
/// #149). The mac has no binder: the runner reads keys straight out of
/// `[String: Any]`, and the schema is only what the MODEL is shown. Measured
/// while planning #150, 35 card arguments are deliberately undeclared — `when`
/// on publish_class_on, `unit`/`days`/`duplicate` on add_next_class, `scope`,
/// `revise`, `rollover`, `answer` — and pushing them onto the schema would
/// spend routing accuracy to prove nothing. What CAN go wrong here is a tool
/// that forgets to READ a key it is sent, and the only observable proof that
/// it reads one is that taking the key away changes the answer.
@MainActor
final class AssistCardArgumentsTests: XCTestCase {

    // MARK: - Types

    /// One card, as the walk needs it.
    private struct Card {
        let phrasing: String
        let command: AssistCardCommand
        let inAClub: Bool
    }

    // MARK: - Functions

    /// Run each card's arguments against the tool they reach FIRST in the
    /// window — the twin, when the write has one — once whole and once with
    /// one key taken out, on two identically built worlds. Every key a tool
    /// is sent by any card must change that tool's answer when it is taken
    /// out, on at least one card.
    ///
    /// **Per tool and key, not per card, and this was measured rather than
    /// chosen.** Whether a key ARRIVES is a property of the tool that reads
    /// it: a tool that reads `howMany` reads it whichever card sends it. And
    /// two card arguments cannot be seen by removal on the card that sends
    /// them, in any world: "make room for a class" sends `howMany: 1`, which
    /// is also what the tool assumes without it, and "roll this section over
    /// onto a new website" sends `rollover` beside `website`, which alone
    /// already makes a rollover (`isARollover` — an MCP caller has no card,
    /// so `website` has to be enough). Both keys are proved by the OTHER card
    /// that sends them: "two classes", and the rollover to a new year.
    ///
    /// No exemption list, deliberately: a key no card can move is red. The
    /// fix for a world too thin to show it is a richer world, never a list
    /// for a real non-arrival to hide in.
    func testEveryArgumentACardSendsChangesWhatTheToolDoes() async throws {
        var cards: [Card] = []
        for shape in AssistCardCommand.everyFixedShape where !shape.command.arguments.isEmpty {
            cards.append(Card(phrasing: shape.phrasing, command: shape.command,
                              inAClub: shape.phrasing.contains("meeting")))
        }
        for family in AssistCardCommand.everyParsedShape {
            let command: AssistCardCommand = try XCTUnwrap(
                AssistCardCommand.matching(
                    family.example, numberedPageWord: family.numberedPageWord,
                    windowCourse: "ICS3U", windowSection: 1
                ),
                "The contract's example “\(family.example)” no longer matches its family."
            )
            cards.append(Card(phrasing: family.example, command: command,
                              inAClub: family.numberedPageWord != nil || family.example.contains("meeting")))
        }

        // "tool · key" → the cards that sent it, and whether any of them
        // showed it arriving.
        var sentBy: [String: [String]] = [:]
        var arrived: Set<String> = []
        for card in cards {
            let write: AssistToolDefinition = try XCTUnwrap(
                definition(named: card.command.toolName), "“\(card.phrasing)” reaches no tool."
            )
            let target: String = firstToolReached(by: write)
            let targetDefinition: AssistToolDefinition = try XCTUnwrap(definition(named: target))
            // Never a real write: every target is a read or a plan. A card
            // with arguments that reached a twin-less write would make this
            // walk change its world for real.
            XCTAssertTrue(
                targetDefinition.readOnly,
                "“\(card.phrasing)” sends arguments to \(target), which changes pages and has no plan — "
                + "this walk would run it for real. Give it a twin, or teach the walk what to do."
            )
            if !targetDefinition.readOnly {
                continue
            }

            for key in card.command.arguments.keys.sorted() {
                var everything: [String: Any] = [:]
                var withoutThisOne: [String: Any] = [:]
                for (name, value) in card.command.arguments {
                    everything[name] = value
                    if name != key {
                        withoutThisOne[name] = value
                    }
                }

                let whole: String = try await answer(of: card, calling: target, as: write,
                                                     with: everything)
                let lessOne: String = try await answer(of: card, calling: target, as: write,
                                                       with: withoutThisOne)
                let pair: String = target + " · " + key
                sentBy[pair, default: []].append("“\(card.phrasing)”")
                if whole != lessOne {
                    arrived.insert(pair)
                }
            }
        }

        for pair in sentBy.keys.sorted() where !arrived.contains(pair) {
            let cardsSending: String = (sentBy[pair] ?? []).joined(separator: ", ")
            XCTFail(
                "\(pair): sent by \(cardsSending), and the tool answered the same without it on every "
                + "one — the argument never arrives, and the card runs as the plainer sentence with "
                + "nothing reporting a fault (see Windows #116, #149)."
            )
        }
        XCTAssertGreaterThanOrEqual(sentBy.count, 14, "The walk checked fewer tool arguments than exist today.")
    }

    // MARK: - Helpers

    private func definition(named name: String) -> AssistToolDefinition? {
        for tool in AssistToolRunner.mcpTools where tool.name == name {
            return tool
        }
        return nil
    }

    /// The tool a card's arguments reach first in the window, whatever plan
    /// mode is set to: the twin when the write has one on the surface —
    /// `needsApproval` or not, since a scheduled deploy's card shows its plan
    /// before its button — otherwise the tool itself.
    private func firstToolReached(by write: AssistToolDefinition) -> String {
        guard let twin = write.planTwinName, definition(named: twin) != nil else {
            return write.name
        }
        return twin
    }

    /// The world a card is said in. A re-date's rollover and website only
    /// change its PLAN in a section with a site whose pages are already on
    /// their days (see `AssistFixture.makeSectionAlreadyReDated`); a club's
    /// own sentences need a club with a meeting on each day they name.
    private func makeWorld(for card: Card) async throws -> AssistFixture.Made {
        if card.command.toolName == "re_date_classes" {
            return try await AssistFixture.makeSectionAlreadyReDated(for: self)
        }
        if card.inAClub {
            return try AssistFixture.makeBusyClub()
        }
        return try AssistFixture.makeRichSection(for: self)
    }

    /// What the target said, with the world's own path taken out so two
    /// worlds built alike read alike — and with a check that nothing in the
    /// section was changed by asking.
    private func answer(of card: Card,
                        calling target: String,
                        as write: AssistToolDefinition,
                        with arguments: [String: Any]) async throws -> String {
        let made: AssistFixture.Made = try await makeWorld(for: card)
        defer { try? FileManager.default.removeItem(at: made.root) }

        // Settled the way the agent settles a card before anything runs, with
        // the same pinned day: otherwise "deploy at 6:30 am" is refused for a
        // reason that is not the card's.
        var settled: [String: Any] = AssistToolRunner.settlingTheClassDay(
            in: arguments, forTool: write, today: made.runner.today
        )
        settled = AssistToolRunner.settlingTheDeployMoment(
            in: settled, forTool: write, today: made.runner.today, now: Date()
        )

        let before: [String] = try pagesOnDisk(in: made.course)
        let outcome: AssistToolOutcome = await AssistFixture.run(target, with: settled, on: made.runner)
        XCTAssertEqual(try pagesOnDisk(in: made.course), before,
                       "Asking \(target) about “\(card.phrasing)” changed the section's pages.")

        let said: String = outcome.summary + "\n" + outcome.detail
        return said.replacingOccurrences(of: made.root.path, with: "<root>")
    }

    /// Every class page's name and words, so a walk that wrote anything shows.
    private func pagesOnDisk(in course: Course) throws -> [String] {
        let folderURL: URL = ClassPages.folderURL(forSection: 1, in: course)
        var pages: [String] = []
        for name in try FileManager.default.contentsOfDirectory(atPath: folderURL.path).sorted() {
            let text: String = (try? String(
                contentsOf: folderURL.appendingPathComponent(name), encoding: .utf8
            )) ?? ""
            pages.append(name + "\n" + text)
        }
        return pages
    }
}

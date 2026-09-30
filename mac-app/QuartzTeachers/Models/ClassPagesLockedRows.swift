import Foundation

/// Course Settings' locked Class Pages rows (#267), shown only for what a
/// course RECORDED (#376, Russell 2026-09-27: "if there's no point in showing
/// the setting … it should be hidden").
///
/// Only the wizard writes `class_page_scheme`, `front_page_heading` and
/// `class_noun`, and only for a club made since #267, so for every other
/// course — CODING and the ICS3U/ICS4U copies included — all three rows go,
/// and the group and its caption with them. For such a course the page-naming
/// row repeated, word for word, the caption three rows above it under "What
/// do you call a unit?", and the noun row read "class" for every course: rows
/// that can never change and never differ tell a teacher nothing.
///
/// The rule and its cases are `contracts/shared-rules.json` →
/// `wizard.clubToggle.settingsRows.shownWhen` / `shownWhenCases`.
enum ClassPagesLockedRows {

    // MARK: - Stored properties

    /// One locked row: its label, its value, its accessibility identifier,
    /// and the contract's name for it.
    struct Row: Equatable {
        var key: String
        var label: String
        var value: String
        var identifier: String
    }

    // MARK: - Functions

    /// The rows to draw, in order; empty when the course recorded none, and
    /// the view then omits the whole group.
    ///
    /// A recorded `class_page_scheme` this app does not know (written by a
    /// newer one) is still shown, as this app reads it, because that is
    /// what governs this app's behaviour here.
    static func rows(for configuration: CourseConfiguration) -> [Row] {
        var result: [Row] = []
        if configuration.recordedClassPageScheme != nil {
            result.append(Row(
                key: "pageNaming",
                label: WizardWording.settingsPageNamingLabel,
                value: WizardWording.settingsPageNamingValue(configuration.classPageNaming),
                identifier: "pageNamingValue"
            ))
        }
        if let heading = configuration.recordedFrontPageHeading {
            result.append(Row(
                key: "frontPageHeading",
                label: WizardWording.settingsFrontPageHeadingLabel,
                value: heading,
                identifier: "frontPageHeadingValue"
            ))
        }
        if configuration.recordedClassNoun != nil {
            result.append(Row(
                key: "noun",
                label: WizardWording.settingsNounLabel,
                value: configuration.classNoun.rawValue,
                identifier: "classNounValue"
            ))
        }
        return result
    }
}

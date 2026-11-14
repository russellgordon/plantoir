import SwiftUI

/// Section ▸ Roll Over to a New Year…'s choosing stage (#897 piece B), in its
/// own file so the sheet's main file changes by a case or two
/// (`SectionVerbSheet.swift`, which #900's tree of checkboxes rebuilds next).
extension SectionVerbSheet {

    // MARK: - Roll Over to a New Year…

    /// The dates the rollover will use, a line when they look like last
    /// year's, then the website: the question with NOTHING chosen where the
    /// section has a website (the window's own question, guessing neither
    /// answer), or one line saying why there is no question
    /// (`RollOverFromTheMenu.website`).
    @ViewBuilder
    var rollOverChoosing: some View {
        if !model.rollOver.datesLine.isEmpty {
            Text(model.rollOver.datesLine)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("sectionVerbSheetRollOverDates")
        }
        if model.rollOver.datesAreOld {
            Text(AssistWording.menuRollOverDatesAreOld(noun: model.noun))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("sectionVerbSheetRollOverDatesAreOld")
        }
        switch model.rollOver.website {
        case .asked:
            Text(AssistWording.rolloverWebsiteQuestion)
                .fixedSize(horizontal: false, vertical: true)
            // In the question's own order: a new website, or the same one.
            Picker("", selection: Binding(
                get: { return model.rollOver.answer },
                set: { chosen in model.rollOver.answer = chosen }
            )) {
                Text(AssistWording.menuRollOverNewWebsite)
                    .tag(Optional(RollOverFromTheMenu.Answer.startANewWebsite))
                Text(AssistWording.menuRollOverKeepWebsite)
                    .tag(Optional(RollOverFromTheMenu.Answer.keepTheSameWebsite))
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .accessibilityIdentifier("sectionVerbSheetRollOverWebsite")
        case .notDeployedYet:
            Text(AssistWording.menuRollOverNotDeployedYet)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("sectionVerbSheetRollOverNoQuestion")
        case .deploysToAFolder:
            Text(AssistWording.menuRollOverDeploysToAFolder)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("sectionVerbSheetRollOverNoQuestion")
        }
    }
}

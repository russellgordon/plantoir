import SwiftUI

/// The warning before a reference course is replaced (#572, second piece),
/// shared by the three doors that offer Replace It…: the New Course wizard,
/// Keep a Copy for Reference… and a one-course import.
///
/// A sheet since #834 (Russell: "This dialog reads as a wall of text"): the
/// title asks, one sentence says the new course takes the old one's place,
/// and the facts are rows (what is being replaced, the day it was kept, the
/// backup's name and how to undo). Cancel answers Return and Escape, which an
/// alert could not give one button (#832); Replace takes no key. Nothing is
/// made, backed up or moved until Replace is pressed.
struct ReplaceReferenceCourseAlert: ViewModifier {

    // MARK: - Stored properties

    /// The warning on screen, or nil.
    @Binding var warning: ReferenceReplacer.Warning?

    /// Called with the folder of the course to replace, once Replace is
    /// pressed.
    let onReplace: (String) -> Void

    // MARK: - Functions

    func body(content: Content) -> some View {
        content
            .sheet(item: $warning) { (shown: ReferenceReplacer.Warning) in
                FactsQuestionSheet(
                    question: shown.question,
                    identifier: "replaceReferenceCourse",
                    goAhead: {
                        warning = nil
                        onReplace(shown.folderName)
                    },
                    cancel: {
                        warning = nil
                    }
                )
            }
    }
}

extension View {

    /// The warning before a reference course is replaced.
    func replaceReferenceCourseAlert(
        _ warning: Binding<ReferenceReplacer.Warning?>,
        onReplace: @escaping (String) -> Void
    ) -> some View {
        return modifier(ReplaceReferenceCourseAlert(warning: warning, onReplace: onReplace))
    }
}

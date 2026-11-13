import SwiftUI

/// The warning before a reference course is replaced (#572, second piece),
/// shared by the three doors that offer Replace It…: the New Course wizard,
/// Keep a Copy for Reference… and a one-course import.
///
/// Escape is Cancel, and Return presses neither button, so a Return never
/// replaces anything; Replace is the destructive one. (Until #832 Cancel
/// carried Return, which in an alert takes Escape off it: measured, the
/// warning could not be closed with Escape.) Nothing is made, backed up or
/// moved until Replace is pressed.
struct ReplaceReferenceCourseAlert: ViewModifier {

    // MARK: - Stored properties

    /// The warning on screen, or nil.
    @Binding var warning: ReferenceReplacer.Warning?

    /// Called with the folder of the course to replace, once Replace is
    /// pressed.
    let onReplace: (String) -> Void

    // MARK: - Computed properties

    var isPresented: Binding<Bool> {
        return Binding(
            get: {
                return warning != nil
            },
            set: { isShowing in
                if !isShowing {
                    warning = nil
                }
            }
        )
    }

    // MARK: - Functions

    func body(content: Content) -> some View {
        content
            .alert(
                warning?.title ?? "",
                isPresented: isPresented,
                presenting: warning
            ) { shown in
                Button(ReferenceReplaceWording.confirmButton, role: .destructive) {
                    onReplace(shown.folderName)
                }
                .accessibilityIdentifier("replaceReferenceCourseConfirm")
                // Escape is Cancel; Return presses neither (#832): an alert
                // gives each button one key, and a Cancel given Return
                // lost Escape (measured, `QuestionKeysTests`).
                Button(ReferenceReplaceWording.cancelButton, role: .cancel) {
                }
            } message: { shown in
                Text(shown.message)
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

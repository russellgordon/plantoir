import Foundation

/// Every sentence a teacher reads about a course kept for reference — written
/// once, here.
///
/// Retyped from `contracts/shared-rules.json` → `referenceCourses.wording` and
/// pinned against it by `ReferenceCourseTests`, the same arrangement
/// `ScheduledDeployCleanup`'s sentences use. They are NOT in `AssistWording`:
/// most of them are said by the app rather than by the assistant, and a
/// sentence belongs beside the act that produces it. The one the assistant
/// also says — the deploy refusal — lives in both, with a test asserting the
/// two are the same string, because the shared Python has to say it too and
/// `scripts/contracts.py` can read `shared-rules.json` and not
/// `assist-wording.json`.
///
/// **The register is calm.** A teacher who keeps a course for reference asked
/// for this; being told about it should read like a fact rather than a
/// warning. No "cannot", no "error", no icon — and never a word about how it
/// is done.
nonisolated enum ReferenceWording {

    // MARK: - Functions

    /// Why an act that would change the course is not available.
    ///
    /// Says what the course IS and stops. It does not tell the teacher to
    /// copy anything: in this release there is nothing in Plantoir that
    /// copies pages between courses, and a sentence that sends them to do it
    /// by hand would be sending them somewhere the pages arrive locked.
    static func staysAsItIs(course: String) -> String {
        return "\(course) is kept for reference, so it stays as it is."
    }
}

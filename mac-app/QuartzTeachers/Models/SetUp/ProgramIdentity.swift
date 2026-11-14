import Foundation
import Security

/// Whose program a file is: the question Plantoir asks once a maker's own
/// set-up has put a program in the home folder (#855), before it calls the
/// program set up.
///
/// **What this proves, and when.** The check runs AFTER the maker's set-up
/// has run, and for Claude Code after the maker's own program has run too
/// (its set-up downloads the program and then starts it to finish the job,
/// measured in `claude.ai/install.sh` on 2026-11-13). So it never means "it
/// was checked before it ran". What it does mean: the program Plantoir is
/// about to offer under Revise With carries the maker's Developer ID
/// signature, with the maker's identifier and team, and its pages hash to
/// what was signed. That is the one check every route gets: GitHub's set-up
/// installs WITHOUT a checksum when its checksum file fails to download, and
/// Anthropic's checks a checksum from the same host as the program.
///
/// A protocol so a test can stand a checker in for the real one: a stand-in
/// installer writes a shell script, which nobody has signed.
nonisolated protocol ProgramIdentityChecking: Sendable {

    /// Whether the program at `path` (links followed) is signed as
    /// `identifier` by `team`.
    func isSigned(atPath path: String, identifier: String, team: String) -> Bool
}

/// The real check, through the Security framework.
nonisolated struct DeveloperIDCheck: ProgramIdentityChecking {

    // MARK: - Functions

    /// The full Developer ID requirement for one program: an Apple-issued
    /// Developer ID certificate (the two certificate fields), the maker's
    /// team, AND the program's own identifier, so a different program from
    /// the same team does not pass. Measured passing on Claude Code 2.1.323
    /// by the plan's review, 2026-11-13.
    static func requirement(identifier: String, team: String) -> String {
        return "anchor apple generic and identifier \"\(identifier)\""
            + " and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
            + " and certificate leaf[subject.OU] = \"\(team)\""
    }

    /// Checks the signature, the requirement AND every page of the program
    /// (no `kSecCSDoNotValidateExecutable`, unlike the door's quick check in
    /// `CopilotLauncher`): this runs once, after a set-up, off the main
    /// actor, where 0.4 to 1.2 s a program is affordable and a program
    /// altered after signing must not pass.
    func isSigned(atPath path: String, identifier: String, team: String) -> Bool {
        let resolvedPath: String = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        var staticCode: SecStaticCode?
        let created: OSStatus = SecStaticCodeCreateWithPath(URL(fileURLWithPath: resolvedPath) as CFURL, [], &staticCode)
        guard created == errSecSuccess, let staticCode else {
            return false
        }
        var requirement: SecRequirement?
        let requirementText: String = DeveloperIDCheck.requirement(identifier: identifier, team: team)
        let parsed: OSStatus = SecRequirementCreateWithString(requirementText as CFString, [], &requirement)
        guard parsed == errSecSuccess, let requirement else {
            return false
        }
        let flags: SecCSFlags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)
        return SecStaticCodeCheckValidity(staticCode, flags, requirement) == errSecSuccess
    }
}

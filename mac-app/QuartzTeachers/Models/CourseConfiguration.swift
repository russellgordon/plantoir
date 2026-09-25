import Foundation
import Observation

/// An in-memory copy of one course's `course_config.json`.
///
/// This type deliberately stores the decoded JSON as a dictionary and exposes
/// typed accessors over it, rather than using `Codable`. The command-line
/// scripts own this file format; keeping unknown keys intact means a config
/// written by a newer script version survives a round trip through this app.
@Observable
class CourseConfiguration {

    // MARK: - Stored properties

    /// The decoded contents of `course_config.json`.
    var values: [String: Any]

    /// The bytes most recently read from or written to disk: what a Save
    /// merges against, and what `revertToFile(at:)` falls back to when the
    /// file cannot be read.
    private var lastSavedData: Data

    // MARK: - Computed properties

    var courseCode: String {
        return stringValue(forKey: "course_code")
    }

    var courseName: String {
        get { return stringValue(forKey: "course_name") }
        set { values["course_name"] = newValue }
    }

    /// Where deploys go: "netlify" (the default), "cloudflare_pages", or
    /// "local_folder" — a folder on this computer, for teachers who upload
    /// to their own web host themselves (e.g. over SFTP). Course-level:
    /// every section of the course deploys the same way.
    ///
    /// These spellings are shared with the Windows app, which reads and
    /// writes the same `course_config.json`, so they are not ours alone to
    /// change.
    var deployTarget: String {
        get {
            let stored: String = stringValue(forKey: "deploy_target")
            return stored.isEmpty ? "netlify" : stored
        }
        set {
            values["deploy_target"] = newValue
            // A destination can never be both primary and additional at
            // once — deploying to the same place twice makes no sense.
            additionalDeployTargets = CourseConfiguration.pruningAdditionalTargets(
                additionalDeployTargets, ofType: newValue
            )
        }
    }

    /// The folder local-folder deploys publish into; each section lands
    /// in its own sectionN subfolder inside it.
    var deployFolderPath: String {
        get { return stringValue(forKey: "deploy_folder_path") }
        set { values["deploy_folder_path"] = newValue }
    }

    /// True when this course deploys to a folder rather than to a web host.
    var deploysToLocalFolder: Bool {
        return deployTarget == "local_folder" && !deployFolderPath.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// True when this course deploys to Cloudflare Pages.
    var deploysToCloudflare: Bool {
        return deployTarget == "cloudflare_pages"
    }

    /// One additional (non-primary) destination this course also
    /// publishes to, for redundancy — `deployTarget` remains the primary.
    /// `type` uses the same spellings as `deployTarget`; `path` is only
    /// meaningful when `type` is "local_folder".
    struct AdditionalDeployTarget: Equatable {
        var type: String
        var path: String
    }

    /// The three destinations Plantoir knows how to publish to, in the
    /// order they are offered — shared by the primary picker and the
    /// additional-targets list, so "one of each type" has a single place
    /// that defines what a "type" even is.
    static let knownDeployTargetTypes: [String] = ["netlify", "cloudflare_pages", "local_folder"]

    /// Extra places this course ALSO publishes to, beyond `deployTarget` —
    /// for redundancy against one host having a bad day, never a
    /// replacement for the primary choice: `deployTarget` still decides
    /// where the "Live URL" link on a finished deploy points.
    ///
    /// Empty for every course that has not opted in, which is the
    /// overwhelming majority: the key is OMITTED from `course_config.json`
    /// entirely rather than written as `[]`, so a course nobody has
    /// touched writes the exact same file this app has always written.
    /// At most one entry per known type, and never a type that already
    /// IS the primary — `deployTarget` already covers that one.
    var additionalDeployTargets: [AdditionalDeployTarget] {
        get {
            guard let rawList = values["additional_deploy_targets"] as? [[String: Any]] else {
                return []
            }
            var result: [AdditionalDeployTarget] = []
            for entry in rawList {
                guard let type = entry["type"] as? String, !type.isEmpty else {
                    continue
                }
                let path = entry["path"] as? String ?? ""
                result.append(AdditionalDeployTarget(type: type, path: path))
            }
            return result
        }
        set {
            if newValue.isEmpty {
                values.removeValue(forKey: "additional_deploy_targets")
                return
            }
            var encoded: [[String: Any]] = []
            for target in newValue {
                var entry: [String: Any] = ["type": target.type]
                if !target.path.isEmpty {
                    entry["path"] = target.path
                }
                encoded.append(entry)
            }
            values["additional_deploy_targets"] = encoded
        }
    }

    /// How late a deploy set to happen on its own may still go ahead, in
    /// days. Course-level, like every other deploying setting.
    ///
    /// The teacher chooses it in Course Settings; absent, or anything that is
    /// not one of the offered choices, means a week. The rule and the reasons
    /// live in `ScheduledDeployLateness`, which is also what reads this key at
    /// the scheduled moment, when no `CourseConfiguration` is loaded.
    ///
    /// Read through `intValue(forKey:fallback:)` with the key written out as a
    /// LITERAL rather than through `ScheduledDeployLateness.configurationKey`,
    /// for the reason spelled out beside `unitWord`:
    /// `FileFormatsContractTests` counts the keys this file reads by scanning
    /// the SOURCE for that labelled argument, so a key reached through a
    /// constant is invisible to the very check that exists to stop a config
    /// key being added without telling Windows. The two spellings are pinned
    /// to the same contract entry by tests on both sides of it.
    var scheduledDeployMayRunLateDays: Int {
        get {
            return ScheduledDeployLateness.days(
                fromStoredValue: intValue(
                    forKey: "scheduled_deploy_may_run_late_days",
                    fallback: ScheduledDeployLateness.defaultDays
                )
            )
        }
        set {
            values["scheduled_deploy_may_run_late_days"] =
                ScheduledDeployLateness.days(fromStoredValue: newValue)
        }
    }

    /// One place this course publishes to — either the primary
    /// (`deployTarget`) or one of `additionalDeployTargets`, both reduced
    /// to the same shape so a deploy can walk one plain list instead of
    /// treating the primary as a special case.
    struct DeployDestination: Equatable {
        var type: String
        var path: String
    }

    /// Every destination this course publishes to, in deploy order — the
    /// primary first, then each additional target in the order it was
    /// added. This is the one list a multi-destination deploy walks; the
    /// primary is not special beyond going first, which is only how the
    /// "Live URL" link on a finished deploy is chosen.
    var allDeployDestinations: [DeployDestination] {
        var result: [DeployDestination] = [
            DeployDestination(type: deployTarget, path: deployFolderPath),
        ]
        for target in additionalDeployTargets {
            result.append(DeployDestination(type: target.type, path: target.path))
        }
        return result
    }

    /// Removes `type` from `targets` if present — the one place that knows
    /// how to keep a primary choice and an additional-targets list from
    /// ever agreeing on the same destination twice. Used by this class's
    /// own `deployTarget` setter (so Course Settings, which binds straight
    /// to this model, can never reach the inconsistent state) and by
    /// `PublishingChoiceView`'s picker (so the wizard's plain `@State`,
    /// which is not backed by a `CourseConfiguration` until course
    /// creation, keeps the same guarantee live on screen). A plain
    /// function rather than a method on an instance, so it is testable
    /// without standing up either a model or a rendered view.
    static func pruningAdditionalTargets(
        _ targets: [AdditionalDeployTarget], ofType type: String
    ) -> [AdditionalDeployTarget] {
        var result: [AdditionalDeployTarget] = []
        for target in targets where target.type != type {
            result.append(target)
        }
        return result
    }

    /// Types available to add as an ADDITIONAL target: every known type
    /// except whichever one is already primary — a course cannot list the
    /// same destination twice.
    func availableAdditionalDeployTargetTypes() -> [String] {
        var result: [String] = []
        for type in CourseConfiguration.knownDeployTargetTypes where type != deployTarget {
            result.append(type)
        }
        return result
    }

    /// Whether `type` is currently configured as an additional target.
    func hasAdditionalDeployTarget(ofType type: String) -> Bool {
        for target in additionalDeployTargets where target.type == type {
            return true
        }
        return false
    }

    /// The stored path for an additional local-folder target, or "" when
    /// that type is not configured (or is not "local_folder", which never
    /// has one).
    func additionalDeployTargetPath(ofType type: String) -> String {
        for target in additionalDeployTargets where target.type == type {
            return target.path
        }
        return ""
    }

    /// Turns an additional target on or off. Turning one off drops it
    /// entirely, including any path it carried — re-enabling it later
    /// starts from a blank path rather than resurrecting the old one, so
    /// a stale folder from months ago can never come back silently.
    func setAdditionalDeployTarget(_ enabled: Bool, ofType type: String) {
        var targets: [AdditionalDeployTarget] = []
        for target in additionalDeployTargets where target.type != type {
            targets.append(target)
        }
        if enabled {
            targets.append(AdditionalDeployTarget(type: type, path: ""))
        }
        additionalDeployTargets = targets
    }

    /// Updates the folder path for an additional local-folder target. A
    /// no-op if that type is not currently enabled as an additional target.
    func setAdditionalDeployTargetPath(_ path: String, ofType type: String) {
        var targets: [AdditionalDeployTarget] = []
        for target in additionalDeployTargets {
            if target.type == type {
                targets.append(AdditionalDeployTarget(type: type, path: path))
            } else {
                targets.append(target)
            }
        }
        additionalDeployTargets = targets
    }

    /// What is wrong with the Cloudflare Account ID, or nil when it is
    /// usable.
    ///
    /// The ID is asked for in the app rather than discovered, because a
    /// token scoped only to Cloudflare Pages cannot list its own account:
    /// `/user/tokens/verify` reports it active while `/accounts` answers
    /// success with an empty list. Validity and account lookup are
    /// therefore separate questions, and this one has to be put to the
    /// teacher — a deploy driven from the app has no console to answer on.
    ///
    /// The ID belongs to the teacher rather than to any one course, so it
    /// lives in app settings (`AppSettings`), not in `course_config.json`.
    static func cloudflareAccountProblem(forID rawID: String) -> String? {
        let identifier: String = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        if identifier.isEmpty {
            return "Paste your Cloudflare Account ID."
        }
        if identifier.count != 32 {
            return "That doesn’t look like an Account ID — it’s 32 letters and digits."
        }
        for character in identifier {
            if !character.isHexDigit {
                return "That doesn’t look like an Account ID — it’s 32 letters and digits."
            }
        }
        return nil
    }

    /// What a teacher is told when the publishing folder they typed is not a
    /// full location — a name on its own, or a path that does not start at
    /// the top of the disk. Contract data: `app-rules.json` →
    /// `configurationRules.deployFolder`.
    static let deployFolderIsNotAFullLocation: String =
        "That isn’t a full folder location — use Choose… to pick the folder."

    /// What is wrong with a folder chosen for local-folder publishing, or
    /// nil when the folder is usable. Both the settings form and the
    /// wizard check this live — and block saving — so a deploy never
    /// discovers the problem after the fact.
    static func deployFolderProblem(forPath rawPath: String) -> String? {
        let path: String = rawPath.trimmingCharacters(in: .whitespaces)
        if path.isEmpty {
            return "Choose the folder this course deploys into."
        }
        // Asked BEFORE the folder is looked for, because a partial path is
        // looked for in the wrong place: the app's own current folder is
        // "/", so "Users/Shared" exists here, while `deploy.sh` would publish
        // into "<working folder>/Users/Shared". A path that is validated in
        // one folder and published into another is the hole GitHub issue
        // #227 is about; the other half of it — a colon read as a remote
        // host — is closed in the launcher, and is documented in
        // documentation/07-deployment.md. `Choose…` always hands back a full
        // path, so only a typed one can reach this.
        if !path.hasPrefix("/") {
            return deployFolderIsNotAFullLocation
        }
        let fileManager: FileManager = FileManager.default
        var isDirectory: ObjCBool = false
        let exists: Bool = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
        if !exists {
            return "That folder doesn’t exist — use Choose… to pick or create one."
        }
        if !isDirectory.boolValue {
            return "That’s a file — deploying needs a folder."
        }
        if !fileManager.isWritableFile(atPath: path) {
            return "That folder can’t be written to — choose a different one."
        }
        return nil
    }

    /// Whether this course is kept for reference: last year's course, or a
    /// course full of example content, sitting in this year's sidebar so the
    /// teacher can read it — and which Plantoir never deploys.
    ///
    /// **Absent means false**, which is what every course written before this
    /// key existed says, and it is the only safe direction: a course that
    /// forgot to say it is ordinary is a course a teacher can still deploy,
    /// while the reverse would make a live course silently undeployable.
    ///
    /// The marker is NOT the defence on its own. A reference course is also
    /// left with nowhere to deploy to (`neutraliseForReference`), so an OLDER
    /// Plantoir sharing the same folder — one that has never heard of this key
    /// — refuses it too, in sentences it already ships.
    /// **Read STRICTLY: a real JSON `true` and nothing else.**
    ///
    /// Not `boolValue`, and that is measured rather than fastidious.
    /// `JSONSerialization` hands back an `NSNumber` for `1`, and `NSNumber`
    /// conditionally bridges to `Bool` for 0 and 1 — so `as? Bool` reads
    /// `"kept_for_reference": 1` (and `1.0`) as TRUE, while all three
    /// launchers read the same file as an ordinary course and DEPLOY it.
    /// Both directions of the fault at once: the app freezes and locks a
    /// course, with no way back to live, that the launchers then publish.
    ///
    /// `CFBooleanGetTypeID` is the only reading that tells a JSON boolean
    /// from a number, and it keeps this key strict without widening
    /// `boolValue`, which every other boolean setting uses. The four readers
    /// — this app, `deploy.sh`, `deploy.ps1` and `reference_course.py` — then
    /// agree on every row of
    /// `contracts/shared-rules.json` → `referenceCourses.markerAgreement`,
    /// which is where the spellings a person plainly MEANT are dealt with:
    /// the launchers refuse those with "cannot tell", which deploys nothing
    /// and freezes nothing, and this app treats them as an ordinary course.
    var keptForReference: Bool {
        get { return strictBoolValue(forKey: "kept_for_reference") }
        set { values["kept_for_reference"] = newValue }
    }

    /// Which school year a reference course was taught in, as the calendar
    /// year it STARTED in: `2025` for 2025–26.
    ///
    /// Absent, null, or anything that is not a year reads as "Other" — the
    /// rule is `SchoolYear.offeredYear(storedYear:on:)`, and the label
    /// ("2025–26", with an en dash) is derived rather than stored so the dash
    /// never reaches the file format.
    ///
    /// Nil clears the key rather than writing `null`: a course nobody has
    /// filed under a year writes the same file it always did.
    var referenceSchoolYear: Int? {
        get { return optionalIntValue(forKey: "reference_school_year") }
        set {
            guard let newValue else {
                values.removeValue(forKey: "reference_school_year")
                return
            }
            values["reference_school_year"] = newValue
        }
    }

    /// Leaves this course with NOWHERE TO DEPLOY TO, as the second half of
    /// making it a reference course.
    ///
    /// The marker above is what this version of Plantoir reads. This is what
    /// every OTHER version reads: a teacher may keep their working folder in
    /// iCloud Drive and open it on a second Mac still running an older
    /// Plantoir, which has never heard of `kept_for_reference` and would show
    /// a working Deploy button aimed at last year's real class site.
    ///
    /// Measured on a real previous-generation working folder: those configs
    /// carry no `deploy_target` at all, and an absent `deploy_target` reads as
    /// `"netlify"` — so a plain copy really would arrive ready to deploy.
    /// Written as a folder deploy with no folder, every shipped version
    /// refuses it with a sentence it already has
    /// (`MultiDestinationDeployRunner.refusalReason` and
    /// `ScheduledDeploy.problem`).
    ///
    /// The site markers are dealt with separately, by whatever COPIES the
    /// course: they are files rather than settings.
    func neutraliseForReference() {
        values["deploy_target"] = "local_folder"
        values["deploy_folder_path"] = ""
        values.removeValue(forKey: "additional_deploy_targets")
        // A reference course must never claim last year's domain — the live
        // course that replaces it may be using it.
        values.removeValue(forKey: "custom_domains")
    }

    var customShortName: String {
        get { return stringValue(forKey: "custom_short_name") }
        set { values["custom_short_name"] = newValue }
    }

    var locale: String {
        get {
            let stored: String = stringValue(forKey: "locale")
            if stored.isEmpty {
                return "en-US"
            }
            return stored
        }
        set { values["locale"] = newValue }
    }

    /// True when the course code has no numeric grade in position four
    /// (e.g. "CODING") — the scripts treat these as clubs.
    var isClub: Bool {
        let code: String = courseCode
        if code.count < 4 {
            return true
        }
        let characters: [Character] = Array(code)
        return !characters[3].isNumber
    }

    var sectionNumbers: [Int] {
        if let numbers = values["section_numbers"] as? [Int] {
            var sortedNumbers: [Int] = numbers
            sortedNumbers.sort()
            return sortedNumbers
        }
        // Older configs may store numbers as NSNumber via JSONSerialization.
        if let rawNumbers = values["section_numbers"] as? [Any] {
            var result: [Int] = []
            for rawNumber in rawNumbers {
                if let number = rawNumber as? NSNumber {
                    result.append(number.intValue)
                }
            }
            if !result.isEmpty {
                result.sort()
                return result
            }
        }
        let count: Int = intValue(forKey: "num_sections", fallback: 1)
        var result: [Int] = []
        for sectionNumber in 1...max(count, 1) {
            result.append(sectionNumber)
        }
        return result
    }

    /// What this course calls a unit — "Unit 2, Day 3", or "Module 2, Day 3".
    /// Absent means "Unit"; see `ClassPageTerm`.
    var unitWord: String {
        // Read through `stringValue(forKey:)` like every other string here,
        // rather than by subscript. Not decoration: `FileFormatsContractTests`
        // counts the keys this file reads by scanning the SOURCE for that
        // labelled argument, and compares the count against the contract — so
        // a key reached only by subscript is invisible to the very check that
        // exists to stop a config key being added without telling Windows.
        // Caught by the suite on 2026-09-04, after the key HAD been
        // documented: the intent was met and the mechanism could not see it.
        // (Which is also why this comment describes the literal rather than
        // spelling it out — the scan would count the comment as a key.)
        get { return ClassPageTerm.cleaned(stringValue(forKey: "unit_word")) }
        set { values["unit_word"] = ClassPageTerm.cleaned(newValue) }
    }

    /// The shape of this course's class-page names (#267). Absent and unknown
    /// read as "Unit 2, Day 3"; see `ClassPageScheme`.
    var classPageScheme: ClassPageScheme {
        get { return ClassPageScheme.reading(stringValue(forKey: "class_page_scheme")) }
        set { values["class_page_scheme"] = newValue.rawValue }
    }

    /// The heading this course's front pages were created with, as
    /// `front_page_heading` records it — nil when the course has none, which
    /// is every course made before #267 (CODING included).
    ///
    /// **No default is filled in, on purpose.** The first version answered
    /// "Most Recent Class" for a course without the key, and Course Settings'
    /// locked row then showed that for CODING, whose front page reads "Most
    /// Recent Meeting" — a locked row stating something the page does not
    /// say. Nothing rewrites a heading after creation, so the only honest
    /// answer for a course without the key is that none was recorded.
    var recordedFrontPageHeading: String? {
        let stored: String = stringValue(forKey: "front_page_heading").trimmingCharacters(in: .whitespaces)
        if stored.isEmpty {
            return nil
        }
        return stored
    }

    /// What the assistant calls one class page to the teacher (#267).
    var classNoun: ClassNoun {
        get { return ClassNoun.reading(stringValue(forKey: "class_noun")) }
        set { values["class_noun"] = newValue.rawValue }
    }

    /// The word and the scheme together — what every planner names pages by.
    var classPageNaming: ClassPageNaming {
        return ClassPageNaming(word: unitWord, scheme: classPageScheme)
    }

    var sharedFolders: [String] {
        get { return stringListValue(forKey: "shared_folders") }
        set { values["shared_folders"] = newValue }
    }

    var sharedFiles: [String] {
        get { return stringListValue(forKey: "shared_files") }
        set { values["shared_files"] = newValue }
    }

    var perSectionFolders: [String] {
        get { return stringListValue(forKey: "per_section_folders") }
        set { values["per_section_folders"] = newValue }
    }

    var perSectionFiles: [String] {
        get { return stringListValue(forKey: "per_section_files") }
        set { values["per_section_files"] = newValue }
    }

    /// What this course calls the folder holding one page per curriculum
    /// expectation.
    ///
    /// Declared by every payload and skeleton manifest and carried into the
    /// config at creation. The build tries it FIRST and only then falls back to
    /// scanning for a top-level folder whose name contains "curriculum" — which
    /// is still the real path for a course made from scratch, but would never
    /// have found a folder called something else entirely.
    /// What this course calls the folder holding its class pages. Absent means
    /// the old guess — the first per-section folder whose name mentions
    /// "class" — which is what every course made before this key existed
    /// relies on. See `ClassFolder`.
    var classFolder: String? {
        get { return values["class_folder"] as? String }
        set {
            if let newValue, !newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                values["class_folder"] = newValue
            } else {
                values.removeValue(forKey: "class_folder")
            }
        }
    }

    var curriculumFolder: String? {
        get { return values["curriculum_folder"] as? String }
        set {
            if let newValue {
                values["curriculum_folder"] = newValue
            } else {
                values.removeValue(forKey: "curriculum_folder")
            }
        }
    }

    /// The folders whose contents count for marks — what makes an expectation
    /// "assessed" on the Curriculum Coverage map.
    ///
    /// **Nil is not empty**, and that distinction is the whole migration.
    /// Nil means the teacher has never been asked, so the build applies the
    /// historical rule (any folder whose name contains "task") and every course
    /// made before this existed keeps exactly the marks it had. `[]` means they
    /// were asked and cleared it, which is a real answer.
    ///
    /// Seeding an existing course with ["Tasks"] would NOT have been safe: the
    /// exact-name rule is narrower than the substring one, and the skeletons
    /// ship a family whose folder is "Thinking Tasks" — counted by the old rule,
    /// not by that pool. See `contracts/shared-rules.json` → `gradedFolders`.
    var gradedFolders: [String]? {
        get {
            guard values["graded_folders"] != nil else {
                return nil
            }
            return stringListValue(forKey: "graded_folders")
        }
        set {
            if let newValue {
                values["graded_folders"] = newValue
            } else {
                values.removeValue(forKey: "graded_folders")
            }
        }
    }

    /// Folders or files excluded from previews and deploys, separated by scope.
    ///
    /// Keyed by scope ("shared" and/or "per_section") to match the config's
    /// structure. ABSENT (not `{}`) when nothing is excluded.
    var excludedItems: [String: [String]]? {
        get {
            guard let dict = values["excluded_items"] as? [String: Any] else {
                return nil
            }
            var result: [String: [String]] = [:]
            for (scope, items) in dict {
                if let list = items as? [String], !list.isEmpty {
                    result[scope] = list
                }
            }
            if result.isEmpty {
                return nil
            }
            return result
        }
        set {
            if let newValue {
                var cleaned: [String: [String]] = [:]
                for (scope, items) in newValue {
                    if !items.isEmpty {
                        cleaned[scope] = items
                    }
                }
                if cleaned.isEmpty {
                    values.removeValue(forKey: "excluded_items")
                } else {
                    values["excluded_items"] = cleaned
                }
            } else {
                values.removeValue(forKey: "excluded_items")
            }
        }
    }

    /// Excluded items for a specific scope ("shared" or "per_section").
    func excludedItems(forScope scope: String) -> [String] {
        if let dict = values["excluded_items"] as? [String: Any] {
            if let list = dict[scope] as? [String] {
                return list
            }
        }
        return []
    }

    /// Checks whether an item name is excluded in a given scope.
    func isExcluded(_ name: String, inScope scope: String) -> Bool {
        let items: [String] = excludedItems(forScope: scope)
        for item in items {
            if item == name {
                return true
            }
        }
        return false
    }

    /// Marks an item name as excluded in a given scope.
    func exclude(_ name: String, inScope scope: String) {
        var dict: [String: [String]] = [:]
        if let existing = excludedItems {
            dict = existing
        }
        var list: [String] = []
        if let existingList = dict[scope] {
            list = existingList
        }
        var alreadyPresent: Bool = false
        for item in list {
            if item == name {
                alreadyPresent = true
                break
            }
        }
        if !alreadyPresent {
            list.append(name)
        }
        dict[scope] = list
        excludedItems = dict
    }

    /// Removes an item name from exclusions in a given scope (re-including it).
    ///
    /// Returns true only if the name WAS excluded, so a caller can tell a
    /// genuine re-inclusion from an ordinary add and record only the former
    /// on the trail — a line saying a folder was re-included when it never
    /// was excluded would be believed.
    @discardableResult
    func reinclude(_ name: String, inScope scope: String) -> Bool {
        guard isExcluded(name, inScope: scope) else {
            return false
        }
        guard var dict = excludedItems else {
            return false
        }
        guard let list = dict[scope] else {
            return false
        }
        var updated: [String] = []
        for item in list {
            if item != name {
                updated.append(item)
            }
        }
        if updated.isEmpty {
            dict.removeValue(forKey: scope)
        } else {
            dict[scope] = updated
        }
        if dict.isEmpty {
            excludedItems = nil
        } else {
            excludedItems = dict
        }
        return true
    }

    var hiddenItems: [String] {
        get { return stringListValue(forKey: "hidden") }
        set { values["hidden"] = newValue }
    }

    var expandableItems: [String] {
        get { return stringListValue(forKey: "expandable") }
        set { values["expandable"] = newValue }
    }

    var expandOnFolderClick: Bool {
        get { return boolValue(forKey: "expandOnFolderClick", fallback: false) }
        set { values["expandOnFolderClick"] = newValue }
    }

    var footerHTML: String {
        get { return stringValue(forKey: "footer_html") }
        set { values["footer_html"] = newValue }
    }

    /// Whether a section's site title leads with the grade ("Grade 12
    /// Computer Science…") — per section, like the section marker. On by
    /// default; the build recomputes the landing title on every build.
    /// An older config that stored one course-wide Bool is honoured.
    func showsGradeInTitle(forSection sectionNumber: Int) -> Bool {
        if let legacy = values["show_grade_in_title"] as? Bool {
            return legacy
        }
        let sectionsMap: [String: Any] = nestedDictionary(forKey: "show_grade_in_title", childKey: "sections")
        if let stored = sectionsMap["section\(sectionNumber)"] as? Bool {
            return stored
        }
        return true
    }

    func setShowsGradeInTitle(_ shows: Bool, forSection sectionNumber: Int) {
        // A legacy course-wide Bool would shadow the per-section map, so
        // it is replaced by the map the first time a section is set.
        if values["show_grade_in_title"] is Bool {
            values["show_grade_in_title"] = [String: Any]()
        }
        setNestedValue(shows, forKey: "show_grade_in_title", childKey: "sections", entryKey: "section\(sectionNumber)")
    }

    /// The landing page's title as the build will compute it — the same
    /// literal rule as `computed_landing_title` in `scripts/build_site.py`:
    /// the grade prefix when its switch is on and the code carries a grade
    /// digit, the course name, and ", Section N" when the marker switch is
    /// on. Used wherever the app previews the site's own headline.
    static func landingTitle(
        courseName: String,
        courseCode: String,
        showsGrade: Bool,
        showsSectionMarker: Bool,
        sectionNumber: Int
    ) -> String {
        let name: String = courseName.trimmingCharacters(in: .whitespaces)
        var prefix: String = ""
        let gradeLabel: String = SectionAdder.gradeLabel(forCourseCode: courseCode)
        if showsGrade && !gradeLabel.isEmpty {
            prefix = "\(gradeLabel) "
        }
        var title: String = "\(prefix)\(name)"
        if showsSectionMarker {
            title = "\(title), Section \(sectionNumber)"
        }
        return title
    }

    /// A quiet warning when turning the grade on would repeat a grade the
    /// course name already carries — "Computer Science, Grade 12, U" would
    /// become "Grade 12 Computer Science, Grade 12, U". The behaviour
    /// stays exactly what the switch says; this only points the problem
    /// out, and the teacher decides: edit the name, or turn the switch off.
    static func gradeInTitleWarning(courseName: String, courseCode: String, showsGrade: Bool) -> String? {
        guard showsGrade else {
            return nil
        }
        let label: String = SectionAdder.gradeLabel(forCourseCode: courseCode)
        guard !label.isEmpty, courseName.contains(label) else {
            return nil
        }
        return "The course name already includes “\(label)”, so the site title would repeat it. Edit the name, or turn this off."
    }

    var showReadingTime: Bool {
        get { return boolValue(forKey: "show_reading_time", fallback: false) }
        set { values["show_reading_time"] = newValue }
    }

    /// Whether this course publishes the Curriculum Coverage page.
    var includesCurriculumCoverage: Bool {
        get { return boolValue(forKey: "include_curriculum_coverage", fallback: true) }
        set {
            values["include_curriculum_coverage"] = newValue
            // The sections cannot outlive the page they sit on.
            if !newValue {
                values["include_coverage_notes"] = false
            }
        }
    }

    /// Whether the coverage page carries its two explanatory sections.
    var includesCoverageNotes: Bool {
        get {
            return CourseConfiguration.coverageNotesEnabled(
                curriculumCoverageEnabled: includesCurriculumCoverage,
                includesCoverageNotes: boolValue(forKey: "include_coverage_notes", fallback: true)
            )
        }
        set { values["include_coverage_notes"] = newValue }
    }

    /// Every item that can be hidden or made expandable in the sidebar.
    var allSidebarItems: [String] {
        var result: [String] = []
        for folder in sharedFolders {
            result.append(folder)
        }
        for file in sharedFiles {
            result.append(file)
        }
        for folder in perSectionFolders {
            result.append(folder)
        }
        for file in perSectionFiles {
            result.append(file)
        }
        return result
    }

    // MARK: - Initializer

    init(values: [String: Any], lastSavedData: Data) {
        self.values = values
        self.lastSavedData = lastSavedData
    }

    /// Loads a configuration from `course_config.json` on disk.
    convenience init(contentsOf url: URL) throws {
        let data: Data = try Data(contentsOf: url)
        let decoded: Any = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = decoded as? [String: Any] else {
            throw CourseConfigurationError.notADictionary
        }
        self.init(values: dictionary, lastSavedData: data)
    }

    // MARK: - Functions

    /// Changes the course code recorded in the settings, so it matches the
    /// folder the course lives in after a rename.
    ///
    /// Both have to move together **for a course a teacher teaches**. The app
    /// reads a course's code from its FOLDER name, while the site builder and
    /// the social-card maker read it from here — so a pair that disagree
    /// produce a sidebar saying one thing and a deployed page saying another,
    /// with no error anywhere.
    ///
    /// **A reference course is the one exception, and it disagrees on
    /// purpose.** Its folder carries a year suffix so two ICS3Us can sit side
    /// by side, while `course_code` stays the real code the teacher
    /// recognises — which is also what keeps its preview's site title, grade
    /// label and social card right. The second half of the warning above
    /// cannot happen there, because a reference course is never deployed;
    /// what a teacher READS comes from `Course.displayCode`. So
    /// `CourseRenamer` must not rewrite `course_code` on one.
    func setCourseCode(_ courseCode: String) {
        values["course_code"] = courseCode
    }

    /// Replaces the course's timetable section numbers (used when a
    /// section is archived and removed).
    func setSectionNumbers(_ sectionNumbers: [Int]) {
        var sortedNumbers: [Int] = sectionNumbers
        sortedNumbers.sort()
        values["section_numbers"] = sortedNumbers
        values["num_sections"] = sortedNumbers.count
    }

    /// The emoji shown beside the site title for a given section.
    func emoji(forSection sectionNumber: Int) -> String {
        let sectionsMap: [String: Any] = nestedDictionary(forKey: "emojis", childKey: "sections")
        if let stored = sectionsMap["section\(sectionNumber)"] as? String {
            if !stored.isEmpty {
                return stored
            }
        }
        return "📚"
    }

    func setEmoji(_ emoji: String, forSection sectionNumber: Int) {
        setNestedValue(emoji, forKey: "emojis", childKey: "sections", entryKey: "section\(sectionNumber)")
    }

    /// The teacher's own domain for ONE DESTINATION of a section's
    /// published site — shown in links to that destination's live site in
    /// place of the address it would otherwise be assigned (a
    /// `.netlify.app` or `.pages.dev` subdomain). Empty when that
    /// destination's own address is used as-is.
    ///
    /// Keyed by destination TYPE, not just by section: a course publishing
    /// to both Netlify and Cloudflare Pages for redundancy may want a
    /// domain on one and not the other. A single section-wide domain (the
    /// shape this replaces) had to guess which destination it was for and
    /// got applied to every destination regardless — the reported bug this
    /// shape exists to fix ("only Cloudflare, the second deploy target, is
    /// visible" had a sibling: a Netlify-only domain silently overriding
    /// the Cloudflare link too).
    ///
    /// Reads an OLDER shape too: `custom_domains.sections.sectionN` used
    /// to be a bare string, written before a course could have more than
    /// one destination. That value is treated as belonging to the
    /// section's PRIMARY destination (`deployTarget`) — the only
    /// destination that existed when it could have been set — and is
    /// invisible to every other destination type, which is exactly
    /// correct for a course that has never touched additional
    /// destinations at all.
    func customDomain(forSection sectionNumber: Int, destinationType: String) -> String {
        let sectionsMap: [String: Any] = nestedDictionary(forKey: "custom_domains", childKey: "sections")
        guard let stored = sectionsMap["section\(sectionNumber)"] else {
            return ""
        }
        if let perDestination = stored as? [String: Any] {
            return perDestination[destinationType] as? String ?? ""
        }
        // Old shape: a bare string, meant for whichever destination was
        // primary when it was set — never for any other type.
        if let legacyDomain = stored as? String, destinationType == deployTarget {
            return legacyDomain
        }
        return ""
    }

    func setCustomDomain(_ domain: String, forSection sectionNumber: Int, destinationType: String) {
        let sectionsMap: [String: Any] = nestedDictionary(forKey: "custom_domains", childKey: "sections")
        let sectionKey: String = "section\(sectionNumber)"
        var perDestination: [String: Any] = [:]
        if let existing = sectionsMap[sectionKey] as? [String: Any] {
            perDestination = existing
        } else if let legacyDomain = sectionsMap[sectionKey] as? String, !legacyDomain.isEmpty {
            // A stray old-shape string, meant for the primary destination,
            // is carried forward into the new shape rather than silently
            // dropped the first time ANY destination's domain is set here.
            perDestination[deployTarget] = legacyDomain
        }
        perDestination[destinationType] = domain
        setNestedValue(perDestination, forKey: "custom_domains", childKey: "sections", entryKey: sectionKey)
    }

    /// A typed or pasted domain, reduced to just the domain: whitespace
    /// trimmed, any scheme stripped, and anything from the first slash on
    /// dropped — so a pasted "https://ics3u.school.ca/" stores as
    /// "ics3u.school.ca".
    /// Whether this course may be offered the curriculum pages written for
    /// its code.
    ///
    /// Two starting points reach them, and it took until GitHub issue #251
    /// for the second to be noticed. A teacher TAKING the ready-made pages
    /// gets the payload's curriculum folder with them. A teacher who
    /// DECLINES the pages still gets the subject's skeleton (#248) — and
    /// the expectations written for their code still exist, so they come
    /// along too rather than leaving the skeleton's placeholder folder and
    /// a coverage map with one fake cell to colour.
    ///
    /// For the ~1,900 codes with no payload there is nothing to offer,
    /// whatever the skeleton toggle says: the skeleton ships an empty
    /// Curriculum folder, ready for expectations the teacher adds by hand.
    ///
    /// ONE rule, read by the three toggles, the config keys and the
    /// coverage rule below, so that the surfaces cannot drift apart — the
    /// same reason `SkeletonCatalog.hasSkeleton(forCode:takingExampleContent:numbered:)`
    /// exists, and `skeletonIsOffered` is that function's own answer rather
    /// than a second copy of its rule.
    static func curriculumPagesOffered(
        codeHasExampleContent: Bool,
        payloadIncludesCurriculum: Bool,
        prepopulatesExampleContent: Bool,
        skeletonIsOffered: Bool,
        startsFromSkeleton: Bool
    ) -> Bool {
        guard codeHasExampleContent, payloadIncludesCurriculum else {
            return false
        }
        if prepopulatesExampleContent {
            return true
        }
        return skeletonIsOffered && startsFromSkeleton
    }

    /// Whether the curriculum coverage map should be switched on for a new
    /// course.
    ///
    /// The map is drawn from the site's own links to the curriculum pages,
    /// so it cannot exist without them: declining the curriculum forces the
    /// map off, whatever the toggle was last left at. The reverse is not
    /// true — keeping the curriculum pages and declining the map is a
    /// reasonable choice, and this returns exactly what the teacher asked
    /// for in that case.
    ///
    /// The rule lives here rather than inside the wizard view so that it
    /// can be tested: a SwiftUI `@State` property has no backing store
    /// until the view is on screen, so a test that sets one and reads a
    /// computed result gets the default back every time.
    /// `curriculumPagesOffered` is asked for rather than re-derived here:
    /// the three guards this used to carry said "the teacher is taking the
    /// payload", which stopped being the only way a course gets curriculum
    /// pages when #251 landed.
    static func curriculumCoverageEnabled(
        curriculumPagesOffered: Bool,
        includesCurriculumPages: Bool,
        includesCurriculumCoverage: Bool
    ) -> Bool {
        guard curriculumPagesOffered,
              includesCurriculumPages else {
            return false
        }
        return includesCurriculumCoverage
    }

    /// Whether the coverage page's two explanatory sections should be
    /// switched on for a new course.
    ///
    /// The sections live on the coverage page, so they cannot exist without
    /// it: declining the map forces them off whatever the toggle was last
    /// left at. Keeping the map and declining the sections is a reasonable
    /// choice — a page published to students is often better as the map
    /// alone — and this returns exactly that.
    static func coverageNotesEnabled(
        curriculumCoverageEnabled: Bool,
        includesCoverageNotes: Bool
    ) -> Bool {
        guard curriculumCoverageEnabled else {
            return false
        }
        return includesCoverageNotes
    }

    static func normalizedCustomDomain(_ raw: String) -> String {
        var domain: String = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for scheme in ["https://", "http://"] {
            if domain.hasPrefix(scheme) {
                domain = String(domain.dropFirst(scheme.count))
            }
        }
        if let slashIndex = domain.firstIndex(of: "/") {
            domain = String(domain[..<slashIndex])
        }
        return domain
    }

    /// Whether the site title shows the "S1"-style marker for a given section.
    func showsSectionMarker(forSection sectionNumber: Int) -> Bool {
        let sectionsMap: [String: Any] = nestedDictionary(forKey: "show_section_marker", childKey: "sections")
        if let stored = sectionsMap["section\(sectionNumber)"] as? Bool {
            return stored
        }
        return true
    }

    func setShowsSectionMarker(_ shows: Bool, forSection sectionNumber: Int) {
        setNestedValue(shows, forKey: "show_section_marker", childKey: "sections", entryKey: "section\(sectionNumber)")
    }

    /// The colour scheme id chosen for a given section, or "" when unset.
    func colourSchemeID(forSection sectionNumber: Int) -> String {
        if let map = values["color_schemes"] as? [String: Any] {
            if let stored = map["section\(sectionNumber)"] as? String {
                return stored
            }
        }
        return ""
    }

    func setColourSchemeID(_ schemeID: String, forSection sectionNumber: Int) {
        var map: [String: Any] = [:]
        if let existing = values["color_schemes"] as? [String: Any] {
            map = existing
        }
        map["section\(sectionNumber)"] = schemeID
        values["color_schemes"] = map
    }

    /// The font choices for a section, falling back to the course default.
    func fontChoice(forSection sectionNumber: Int) -> FontChoice {
        let sectionsMap: [String: Any] = nestedDictionary(forKey: "fonts", childKey: "sections")
        if let stored = sectionsMap["section\(sectionNumber)"] as? [String: Any] {
            return FontChoice(dictionary: stored)
        }
        if let fonts = values["fonts"] as? [String: Any] {
            if let defaultChoice = fonts["default"] as? [String: Any] {
                return FontChoice(dictionary: defaultChoice)
            }
        }
        return FontChoice.systemDefault
    }

    func setFontChoice(_ choice: FontChoice, forSection sectionNumber: Int) {
        setNestedValue(choice.dictionaryRepresentation, forKey: "fonts", childKey: "sections", entryKey: "section\(sectionNumber)")
    }

    var defaultFontChoice: FontChoice {
        get {
            if let fonts = values["fonts"] as? [String: Any] {
                if let stored = fonts["default"] as? [String: Any] {
                    return FontChoice(dictionary: stored)
                }
            }
            return FontChoice.systemDefault
        }
        set {
            var fonts: [String: Any] = [:]
            if let existing = values["fonts"] as? [String: Any] {
                fonts = existing
            }
            fonts["default"] = newValue.dictionaryRepresentation
            values["fonts"] = fonts
        }
    }

    /// Writes the configuration to disk in the same shape the setup wizard
    /// uses: pretty-printed JSON with a trailing newline.
    ///
    /// **Only the settings THIS copy changed are written over the file**
    /// (issue #265). Two windows on one working folder each hold their own
    /// copy of a course's settings, and this used to be a blind whole-file
    /// write — so a Save in the window that had not seen the other's Save put
    /// back every setting as that window last read it. Measured with this
    /// file compiled standalone and a copy of a real course: window A saved
    /// three sidebar hides, window B then saved an unrelated setting, and the
    /// file went back to B's ten hides while both windows said "nothing
    /// unsaved". Every Save — Course Settings, Add Section, archive, restore,
    /// rename, school year — comes through here, so all six are covered.
    ///
    /// The rule, per top-level key, with `lastSavedData` as what this copy
    /// last read or wrote:
    /// - the file has not changed since then → write this copy, as before;
    /// - otherwise, a key this copy did NOT change keeps the file's value
    ///   (somebody else's Save, or a build adding a folder it discovered);
    /// - a key this copy DID change is written, and when the file had also
    ///   changed it, that is reported so the trail can say so.
    ///
    /// Per KEY rather than per list element, deliberately: merging inside a
    /// list would need rules for order and for an item removed on one side and
    /// added on the other, and nothing a teacher reported needs them. The same
    /// read-then-check-then-write loop as `recordOnDisk` guards against a
    /// build writing between the read and the write.
    ///
    /// Afterwards the in-memory copy IS the file, so a form that is open
    /// shows what was really saved, and every other window's copy of this
    /// course is brought up to date (`WorkspaceModel.followWrite`).
    @discardableResult
    func write(to url: URL) throws -> WriteResult {
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var attempts: Int = 0
        while true {
            let before: Data? = try? Data(contentsOf: url)
            var result: WriteResult = WriteResult()
            var toWrite: [String: Any] = values
            if let before, before != lastSavedData {
                let base: [String: Any]? = CourseConfiguration.decodedDictionary(lastSavedData)
                let onDisk: [String: Any]? = CourseConfiguration.decodedDictionary(before)
                if let base, let onDisk {
                    toWrite = CourseConfiguration.merged(mine: values, base: base, onDisk: onDisk, result: &result)
                }
            }
            var data: Data = try JSONSerialization.data(withJSONObject: toWrite, options: options)
            data.append(contentsOf: [0x0A])

            // Something wrote the file between the read and here (a build's
            // preflight, most likely): read it again and redo the merge. After
            // three tries this Save goes ahead with the last merge, which is
            // still right for every key except one written in that instant.
            let nowOnDisk: Data? = try? Data(contentsOf: url)
            if nowOnDisk != before && attempts < 3 {
                attempts += 1
                continue
            }
            try data.write(to: url, options: [.atomic])
            lastSavedData = data
            values = toWrite
            WorkspaceModel.followWrite(of: self, at: url)
            return result
        }
    }

    /// What a write found in the file that this copy had not read.
    struct WriteResult {

        // MARK: - Stored properties

        /// Settings changed in the file since this copy read it, which this
        /// copy had not touched — kept as the file had them.
        var keptFromElsewhere: [String] = []

        /// Settings changed BOTH in the file and in this copy. This copy's
        /// value was written, because it is the Save the teacher just made.
        var replacedChangesFromElsewhere: [String] = []

        // MARK: - Computed properties

        /// True when the file had been changed by something else since this
        /// copy read it.
        var fileHadChangedElsewhere: Bool {
            return !keptFromElsewhere.isEmpty || !replacedChangesFromElsewhere.isEmpty
        }
    }

    /// The per-key merge `write(to:)` describes. `base` is what this copy last
    /// read or wrote, `mine` is this copy now, `onDisk` is the file now.
    static func merged(
        mine: [String: Any],
        base: [String: Any],
        onDisk: [String: Any],
        result: inout WriteResult
    ) -> [String: Any] {
        var allKeys: Set<String> = []
        for key in mine.keys {
            allKeys.insert(key)
        }
        for key in base.keys {
            allKeys.insert(key)
        }
        for key in onDisk.keys {
            allKeys.insert(key)
        }

        var output: [String: Any] = [:]
        for key in allKeys.sorted() {
            let changedHere: Bool = !sameValue(mine[key], base[key])
            let changedThere: Bool = !sameValue(onDisk[key], base[key])
            if changedHere {
                if let value = mine[key] {
                    output[key] = value
                }
                if changedThere && !sameValue(mine[key], onDisk[key]) {
                    result.replacedChangesFromElsewhere.append(key)
                }
            } else {
                if let value = onDisk[key] {
                    output[key] = value
                }
                if changedThere {
                    result.keptFromElsewhere.append(key)
                }
            }
        }
        return output
    }

    /// Reads the file again when this copy has nothing unsaved — what Course
    /// Settings does each time it is opened (issue #265), so a folder the
    /// build discovered, or a Save made in another window, is on screen
    /// without relaunching. Unsaved edits are never replaced. Returns whether
    /// the file was read.
    @discardableResult
    func reloadIfNothingUnsaved(url: URL) -> Bool {
        if hasUnsavedChanges {
            return false
        }
        do {
            try reloadFromDisk(url: url)
            return true
        } catch {
            return false
        }
    }

    /// Replaces this copy with what is in the file now — for a copy with
    /// nothing unsaved, after something else wrote the file. Callers check
    /// `hasUnsavedChanges` first: this discards unsaved edits.
    func reloadFromDisk(url: URL) throws {
        let data: Data = try Data(contentsOf: url)
        if data == lastSavedData {
            return
        }
        guard let dictionary = CourseConfiguration.decodedDictionary(data) else {
            throw CourseConfigurationError.notADictionary
        }
        lastSavedData = data
        values = dictionary
    }

    /// Records a change that has ALREADY happened on disk — a folder rename —
    /// in both the file and the in-memory copy, without saving anything else.
    ///
    /// Settings normally holds edits in memory until Save, and Cancel reverts
    /// them. A renamed folder cannot be reverted by a Cancel, so the rename
    /// has to reach the file at once or the two will disagree the moment the
    /// teacher presses either button. What must NOT reach the file is
    /// everything else they have typed and not saved, so the change is applied
    /// to a FRESH read of the file rather than to the in-memory values, and
    /// then to the in-memory values separately. `lastSavedData` follows the
    /// file, so Cancel reverts their other edits and leaves the rename alone —
    /// which is the only honest answer, because the folder really has moved.
    func recordOnDisk(_ change: ([String: Any]) -> [String: Any], at url: URL) throws {
        // Read, change, and write only if nothing else wrote in between.
        //
        // A build's own `preflight_update_course_config` writes this same file,
        // and the loser of that race used to be silent — whichever write landed
        // second simply erased the other's keys. The Python side now does the
        // same compare-and-swap, so between them a rename and a build can no
        // longer quietly undo each other; whoever notices re-reads and redoes
        // its work rather than overwriting.
        //
        // Re-applying `change` to the fresh read is safe because it is what
        // `change` is: a rename of names that either are there or are not.
        var attempts: Int = 0
        while true {
            let before: Data = try Data(contentsOf: url)
            guard let onDisk = try JSONSerialization.jsonObject(with: before) as? [String: Any] else {
                throw CourseConfigurationError.notADictionary
            }
            let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            var written: Data = try JSONSerialization.data(withJSONObject: change(onDisk), options: options)
            written.append(contentsOf: [0x0A])

            let nowOnDisk: Data = (try? Data(contentsOf: url)) ?? before
            if nowOnDisk != before {
                attempts += 1
                // Three tries, then write anyway. A folder that has MOVED and a
                // configuration that does not say so is the worse of the two
                // states, so this ends by recording the truth rather than by
                // giving up on it.
                if attempts < 3 {
                    continue
                }
                // But it writes the FRESHEST computation, not the stale one.
                // Falling through with `written` — derived from `before`, which
                // `nowOnDisk` has just proved out of date — would clobber the
                // other writer's keys, which is the very failure this loop
                // exists to stop. Apply the change to what is there now.
                if let latest = try? JSONSerialization.jsonObject(with: nowOnDisk) as? [String: Any] {
                    written = try JSONSerialization.data(
                        withJSONObject: change(latest), options: options
                    )
                    written.append(contentsOf: [0x0A])
                }
            }
            try written.write(to: url, options: [.atomic])
            lastSavedData = written
            values = change(values)
            WorkspaceModel.followWrite(of: self, at: url)
            return
        }
    }

    /// What Course Settings' Revert button does: the settings as the FILE
    /// has them now, not as this copy last read them (issue #265).
    ///
    /// A copy with unsaved edits is deliberately left alone when another
    /// window saves (`WorkspaceModel.followWrite`), so the bytes it last read
    /// can be older than the file. Reverting to those put the other window's
    /// Save back on screen as "nothing unsaved" — measured by the review: B
    /// with an unsaved edit, A saves three hides, B reverts and shows the old
    /// ten — and B's next Save wrote the old list back over A's, because it
    /// now looked like a change B had made. Reading the file is what "put it
    /// back the way it was saved" means when somebody else saved last.
    ///
    /// When the file cannot be read, falls back to the bytes this copy last
    /// read, which is what Revert did before.
    func revertToFile(at url: URL) throws {
        if let data = try? Data(contentsOf: url),
           let dictionary = CourseConfiguration.decodedDictionary(data) {
            lastSavedData = data
            values = dictionary
            return
        }
        try discardChanges()
    }

    /// Reverts all in-memory edits back to the last data read from or
    /// written to disk. Course Settings' Revert uses `revertToFile(at:)`.
    func discardChanges() throws {
        let decoded: Any = try JSONSerialization.jsonObject(with: lastSavedData)
        guard let dictionary = decoded as? [String: Any] else {
            throw CourseConfigurationError.notADictionary
        }
        values = dictionary
    }

    /// True when the in-memory values differ from what was last saved.
    var hasUnsavedChanges: Bool {
        guard let savedDecoded = try? JSONSerialization.jsonObject(with: lastSavedData) else {
            return true
        }
        guard let savedDictionary = savedDecoded as? [String: Any] else {
            return true
        }
        let current = values as NSDictionary
        let saved = savedDictionary as NSDictionary
        return !current.isEqual(to: saved as! [AnyHashable: Any])
    }

    // MARK: - Private helpers

    /// The JSON object in `data`, when it is a dictionary.
    private static func decodedDictionary(_ data: Data) -> [String: Any]? {
        guard let decoded = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return decoded as? [String: Any]
    }

    /// Whether two values from a decoded (or edited) configuration are the
    /// same JSON value — a missing key is only the same as a missing key.
    private static func sameValue(_ first: Any?, _ second: Any?) -> Bool {
        guard let first else {
            return second == nil
        }
        guard let second else {
            return false
        }
        let firstWrapped: NSArray = [first]
        return firstWrapped.isEqual(to: [second])
    }

    private func stringValue(forKey key: String) -> String {
        if let stored = values[key] as? String {
            return stored
        }
        return ""
    }

    /// A whole number, or nil when the key is absent or holds something that
    /// is not one. Unlike `intValue(forKey:fallback:)` this keeps the
    /// difference between "no answer" and a number, which is what a key
    /// whose absence MEANS something needs.
    private func optionalIntValue(forKey key: String) -> Int? {
        guard let stored = values[key] as? NSNumber else {
            return nil
        }
        let whole: Int = stored.intValue
        if Double(whole) != stored.doubleValue {
            return nil
        }
        return whole
    }

    private func intValue(forKey key: String, fallback: Int) -> Int {
        if let stored = values[key] as? NSNumber {
            return stored.intValue
        }
        return fallback
    }

    /// A real JSON boolean `true`, and nothing else — not `1`, not `1.0`,
    /// not `"true"`, not `TRUE`.
    ///
    /// `CFGetTypeID` is the discriminator, because Swift's own `is Bool` is
    /// not one: measured, an `NSNumber` holding 1 satisfies `is Bool` exactly
    /// as `kCFBooleanTrue` does.
    private func strictBoolValue(forKey key: String) -> Bool {
        guard let stored = values[key] else {
            return false
        }
        guard CFGetTypeID(stored as CFTypeRef) == CFBooleanGetTypeID() else {
            return false
        }
        return (stored as? NSNumber)?.boolValue == true
    }

    private func boolValue(forKey key: String, fallback: Bool) -> Bool {
        if let stored = values[key] as? Bool {
            return stored
        }
        return fallback
    }

    private func stringListValue(forKey key: String) -> [String] {
        if let stored = values[key] as? [String] {
            return stored
        }
        return []
    }

    private func nestedDictionary(forKey key: String, childKey: String) -> [String: Any] {
        if let outer = values[key] as? [String: Any] {
            if let inner = outer[childKey] as? [String: Any] {
                return inner
            }
        }
        return [:]
    }

    private func setNestedValue(_ value: Any, forKey key: String, childKey: String, entryKey: String) {
        var outer: [String: Any] = [:]
        if let existing = values[key] as? [String: Any] {
            outer = existing
        }
        var inner: [String: Any] = [:]
        if let existingInner = outer[childKey] as? [String: Any] {
            inner = existingInner
        }
        inner[entryKey] = value
        outer[childKey] = inner
        values[key] = outer
    }
}

enum CourseConfigurationError: Error {
    case notADictionary
}

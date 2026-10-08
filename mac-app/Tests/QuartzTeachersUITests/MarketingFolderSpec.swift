import Foundation

/// The two demo working folders plantoir.app's pictures are taken in, as
/// `website/shots/marketing/folders.json` describes them (#445).
///
/// The marketing UI tests read their course codes, sections and scene pages
/// from here rather than from literals of their own, so the Python that
/// provisions a folder, the Windows capture and these tests cannot disagree
/// about what the folder holds. `capture.py` passes the file's path as
/// `MARKETING_FOLDERS_SPEC`; a run started by hand from Xcode finds it beside
/// this source file instead.
///
/// The one thing NOT here is the school year a reference copy is filed
/// under: that is read from the folder's own copy (`referenceSchoolYear`),
/// because a kept copy stays where it was filed whatever the clock says.
struct MarketingFolderSpec: Decodable {

    // MARK: - Stored properties

    let demo: DemoFolder
    let marketing: MarketingFolder

    struct Course: Decodable {

        // MARK: - Stored properties

        let code: String
        let sections: [Int]

        // MARK: - Computed properties

        /// The sections the way a teacher types them into the new-course panel.
        var sectionsAsTyped: String {
            var words: [String] = []
            for number in sections {
                words.append(String(number))
            }
            return words.joined(separator: ", ")
        }
    }

    struct DemoFolder: Decodable {

        // MARK: - Stored properties

        let courses: [Course]
    }

    struct MarketingFolder: Decodable {

        // MARK: - Stored properties

        let courses: [Course]
        let curriculumCourse: String
        let collegeBoardPages: CollegeBoardPages
        let scenes: Scenes
    }

    struct CollegeBoardPages: Decodable {

        // MARK: - Stored properties

        let folder: String
    }

    struct Scenes: Decodable {

        // MARK: - Stored properties

        let newCourse: NewCourse
        let pageToBorrow: String
        let bothCurricula: BothCurricula
    }

    struct NewCourse: Decodable {

        // MARK: - Stored properties

        let code: String
        let sections: String
    }

    struct BothCurricula: Decodable {

        // MARK: - Stored properties

        let page: String
        let ontario: String
        let collegeBoard: String
    }

    /// Read once per test run. A spec that cannot be read stops the run with
    /// the reason, rather than letting every test fall back to a guess.
    static let shared: MarketingFolderSpec = MarketingFolderSpec.load()

    // MARK: - Computed properties

    /// The first demo course: the one the app windows and the assistant are
    /// photographed in.
    var firstDemoCourse: String {
        return demo.courses[0].code
    }

    /// The marketing course that is not the curriculum course: where Copy a
    /// Page copies TO.
    var secondMarketingCourse: String {
        for course in marketing.courses where course.code != marketing.curriculumCourse {
            return course.code
        }
        return marketing.curriculumCourse
    }

    // MARK: - Functions

    /// Where folders.json is: named by `capture.py`, or beside this source file.
    static func location() -> URL {
        let environment: [String: String] = ProcessInfo.processInfo.environment
        if let named = environment["MARKETING_FOLDERS_SPEC"], !named.isEmpty {
            return URL(fileURLWithPath: named)
        }
        // mac-app/Tests/QuartzTeachersUITests/<this file> → the repository.
        let repository: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repository.appendingPathComponent("website/shots/marketing/folders.json")
    }

    static func load() -> MarketingFolderSpec {
        let url: URL = location()
        do {
            let data: Data = try Data(contentsOf: url)
            return try JSONDecoder().decode(MarketingFolderSpec.self, from: data)
        } catch {
            fatalError("The marketing tests read their courses from \(url.path), which could not be read: \(error)")
        }
    }

    /// How the app writes a school year: 2025 becomes "2025–26".
    static func yearTitle(_ schoolYear: Int) -> String {
        let next: Int = (schoolYear + 1) % 100
        let padded: String = next < 10 ? "0\(next)" : "\(next)"
        return "\(schoolYear)–\(padded)"
    }

    /// The school year the folder's reference copy is filed under.
    ///
    /// `capture.py` passes it as `MARKETING_REFERENCE_YEAR` (read from the
    /// copy when there is one, the year before this one for a folder about to
    /// be given one). Without it, the folder's own copy is read. Neither is
    /// an error said plainly: there is no year to fall back to that would
    /// still be right next year.
    static func referenceSchoolYear(inWorkspace workspacePath: String) throws -> Int {
        let environment: [String: String] = ProcessInfo.processInfo.environment
        if let given = environment["MARKETING_REFERENCE_YEAR"], let year = Int(given) {
            return year
        }
        let courses: URL = URL(fileURLWithPath: workspacePath).appendingPathComponent("courses")
        let entries: [URL] = (try? FileManager.default.contentsOfDirectory(
            at: courses, includingPropertiesForKeys: nil
        )) ?? []
        for entry in entries {
            let configURL: URL = entry.appendingPathComponent("course_config.json")
            guard let data = try? Data(contentsOf: configURL),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let config = object as? [String: Any] else {
                continue
            }
            let kept: Bool = (config["kept_for_reference"] as? Bool) ?? false
            if kept, let year = config["reference_school_year"] as? Int {
                return year
            }
        }
        throw MarketingFolderSpecProblem.noReferenceYear(workspacePath)
    }
}

/// What is missing when a scene needs a school year and has none.
enum MarketingFolderSpecProblem: Error, CustomStringConvertible {
    case noReferenceYear(String)

    // MARK: - Computed properties

    var description: String {
        switch self {
        case .noReferenceYear(let path):
            return "No reference copy in \(path) says which school year it is filed under, and "
                + "MARKETING_REFERENCE_YEAR is not set. `python3 website/shots/capture.py` sets it."
        }
    }
}

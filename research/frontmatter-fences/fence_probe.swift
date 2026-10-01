// The Swift half of fuzz_fences.py: reads a JSON array of page texts on
// stdin and writes, for each, the lines `PageVisibilityReader.fenceIndices`
// puts between the fences — or null when it finds no block. Compiled against
// the app's own sources; see RESULTS.md for the command.
import Foundation

@main
struct FenceProbe {

    // MARK: - Functions

    static func main() throws {
        let input: Data = FileHandle.standardInput.readDataToEndOfFile()
        let pages: [String] = (try JSONSerialization.jsonObject(with: input) as? [String]) ?? []
        var answers: [Any] = []
        for page in pages {
            answers.append(blockText(in: page) ?? NSNull())
        }
        let output: Data = try JSONSerialization.data(withJSONObject: answers)
        FileHandle.standardOutput.write(output)
    }

    static func blockText(in page: String) -> String? {
        guard let fences = PageVisibilityReader.fenceIndices(in: page) else {
            return nil
        }
        let lines: [String] = page.components(separatedBy: "\n")
        var inside: [String] = []
        var index: Int = fences.openIndex + 1
        while index < fences.closeIndex {
            inside.append(lines[index])
            index += 1
        }
        return inside.joined(separator: "\n")
    }
}

// Reads the learning objectives and essential knowledge statements out of the
// AP Computer Science Principles Course and Exam Description, by position.
//
// Usage: swift ced_statements.swift <ced.pdf>
// Prints one JSON object per line: {"code", "page", "text"} — one for EVERY
// place a code is printed with its statement, so the caller can check the
// copies against each other. college_board.py does the cleaning and checking.
//
// Two things about this document decide how it is read, both measured on the
// Fall 2023 edition:
//
// 1. Many of its word spaces are drawn with a glyph that maps to U+0007, not
//    U+0020. `pdftotext` drops that character, so lines come out as
//    "self-drivingcar),nonphysicalcomputing". PDFKit keeps it, and it is
//    turned back into a space here.
// 2. Learning objectives and essential knowledge sit in side-by-side columns,
//    and every reading-order extraction (pdftotext raw or layout, PDFKit's
//    page string) interleaves them line by line. So each statement is read as
//    the text inside a RECTANGLE: from its code down to the next code in the
//    same column, and across to the next column. `characterBounds(at:)` was
//    tried first and returns positions that do not belong to the character
//    asked about; `selection(for: NSRange)` and `selection(for: CGRect)` are
//    right, and are what this uses.
//
// Only the Course Framework's topic pages and the Appendix's conceptual
// framework are read: unit openers and exam pages quote codes in lists and
// answer keys, where there is no statement beside them.

import Foundation
import PDFKit

struct Statement: Encodable {
    let code: String
    let page: Int
    let text: String
}

struct CodeOnPage {
    let code: String
    let bounds: CGRect
}

let arguments: [String] = CommandLine.arguments
guard arguments.count == 2,
      let document: PDFDocument = PDFDocument(url: URL(fileURLWithPath: arguments[1])) else {
    FileHandle.standardError.write("usage: swift ced_statements.swift <ced.pdf>\n".data(using: .utf8)!)
    exit(2)
}

let codePattern: NSRegularExpression = try! NSRegularExpression(
    pattern: "(?m)^([A-Z]{3}-[0-9]+\\.[A-Z](?:\\.[0-9]+)?)[ \\u0007]*$"
)
let encoder: JSONEncoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

func readable(_ text: String) -> String {
    var result: String = text.replacingOccurrences(of: "\u{07}", with: " ")
    result = result.replacingOccurrences(of: "\u{08}", with: " ")
    return result
}

for pageIndex in 0..<document.pageCount {
    guard let page: PDFPage = document.page(at: pageIndex), let content: String = page.string else {
        continue
    }
    let plain: String = readable(content)
    // The framework pages head their columns "LEARNING OBJECTIVE" and
    // "ESSENTIAL KNOWLEDGE"; the appendix, "Learning Objective" and
    // "Essential Knowledge". Unit openers carry the same footer but list
    // codes against topics, with no statement beside them.
    let framework: Bool = plain.contains("Framework V.1") && plain.contains("ESSENTIAL KNOWLEDGE")
    let appendix: Bool = plain.contains("Appendix V.1") && plain.contains("Essential Knowledge")
    guard framework || appendix else {
        continue
    }
    let pageBox: CGRect = page.bounds(for: .mediaBox)
    let nsContent: NSString = content as NSString

    // Where the running footer starts: nothing below it is a statement.
    var floor: CGFloat = 50
    let footerRange: NSRange = nsContent.range(of: "AP Computer Science Principles")
    if footerRange.location != NSNotFound, let footer: PDFSelection = page.selection(for: footerRange) {
        let footerBounds: CGRect = footer.bounds(for: page)
        if footerBounds.maxY < pageBox.height * 0.2 {
            floor = footerBounds.maxY + 1
        }
    }

    var codes: [CodeOnPage] = []
    let matches: [NSTextCheckingResult] = codePattern.matches(
        in: content, range: NSRange(location: 0, length: nsContent.length)
    )
    for match in matches {
        let range: NSRange = match.range(at: 1)
        guard let selection: PDFSelection = page.selection(for: range) else {
            continue
        }
        codes.append(CodeOnPage(code: nsContent.substring(with: range), bounds: selection.bounds(for: page)))
    }

    for code in codes {
        // The column's right edge: the left edge of the nearest column of
        // codes to the right, or the page margin.
        var right: CGFloat = pageBox.width - 24
        for other in codes {
            if other.bounds.minX > code.bounds.minX + 40 && other.bounds.minX - 4 < right {
                right = other.bounds.minX - 4
            }
        }
        // The statement's lower edge: the next code below in the same column.
        var bottom: CGFloat = floor
        for other in codes {
            let sameColumn: Bool = abs(other.bounds.minX - code.bounds.minX) < 6
            if sameColumn && other.bounds.maxY < code.bounds.minY - 1 && other.bounds.maxY + 1 > bottom {
                bottom = other.bounds.maxY + 1
            }
        }
        let rectangle: CGRect = CGRect(
            x: code.bounds.minX - 6,
            y: bottom,
            width: right - code.bounds.minX + 6,
            height: code.bounds.maxY + 1 - bottom
        )
        guard let selection: PDFSelection = page.selection(for: rectangle),
              let text: String = selection.string else {
            continue
        }
        let statement: Statement = Statement(code: code.code, page: pageIndex + 1, text: readable(text))
        if let data: Data = try? encoder.encode(statement), let line: String = String(data: data, encoding: .utf8) {
            print(line)
        }
    }
}

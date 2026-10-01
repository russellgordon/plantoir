import Foundation

/// Who made a backup — the first thing a teacher looking at five of them
/// needs to know.
///
/// This rides in the file's NAME rather than in a note beside it: a sidecar
/// file can fall out of step with the zip it describes, or be lost when the
/// zip is moved, and then the record is worse than none at all. In the name,
/// the zip stays the whole record.
enum BackupMaker: Hashable {

    /// The teacher asked for it — by pressing Back Up, or by doing something
    /// (adding a class, say) that saves a copy on their behalf.
    case teacher

    /// Plantoir's assistant made it, before the first change of one
    /// conversation about this section.
    case assistant(sectionNumber: Int)

    // MARK: - Computed properties

    /// What this adds to a backup's file name. A teacher's backup adds
    /// NOTHING, which is what keeps every backup ever made — all of them
    /// theirs — readable by the parser below.
    var nameSuffix: String {
        switch self {
        case .teacher:
            return ""
        case .assistant(let sectionNumber):
            return "_assistant-section\(sectionNumber)"
        }
    }

    /// The end of the sentence a teacher reads in the Backups list.
    var description: String {
        switch self {
        case .teacher:
            return "made by you"
        case .assistant(let sectionNumber):
            return "before an assistant chat about Section \(sectionNumber)"
        }
    }

    // MARK: - Functions

    /// Reads the "assistant-section3" piece of a backup's name. Returns nil
    /// for anything else, so an unrecognised piece makes the whole name
    /// unrecognised rather than quietly reading as a teacher's own backup.
    static func reading(_ piece: String) -> BackupMaker? {
        let assistantPrefix: String = "assistant-section"
        if piece.hasPrefix(assistantPrefix) {
            if let sectionNumber = Int(piece.dropFirst(assistantPrefix.count)) {
                return .assistant(sectionNumber: sectionNumber)
            }
        }
        return nil
    }
}

/// A saved copy of a whole course, made on purpose before risky editing —
/// handing a pile of pages to an LLM, say — so there is always a way back.
///
/// Backups live beside the archives in `courses/_backups/<CODE>/`, told
/// apart by name: a backup is `<CODE>_backup_<timestamp>.zip`, an archive
/// is `<CODE>_<timestamp>.zip`, and the setup wizard's automatic zips are
/// `<timestamp>.zip` alone. Each parser accepts only its own form, so the
/// three kinds can never appear in each other's lists.
///
/// One backup carries more than its date: the assistant's own are named
/// `<CODE>_backup_<timestamp>_assistant-section<N>.zip`, so a teacher can
/// see which copies Plantoir made and what each one was for. A name without
/// that ending is one of the teacher's own — which is exactly what every
/// backup made before this existed is.
struct BackupItem: Identifiable, Hashable {

    // MARK: - Stored properties

    /// The course this is a copy of.
    let courseCode: String

    /// When the copy was made.
    let backedUpAt: Date

    /// Where the zip is, so it can be restored, revealed, or deleted.
    let fileURL: URL

    /// Who made it: the teacher, or the assistant before a conversation
    /// changed anything.
    let maker: BackupMaker

    // MARK: - Computed properties

    var id: String {
        return fileURL.path
    }

    var title: String {
        return courseCode
    }

    /// "11 August 2026 at 10:15 PM" — the moment alone, with the time,
    /// because a careful teacher may make several backups in one evening.
    var whenDescription: String {
        let formatter: DateFormatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: backedUpAt)
    }

    /// "Backed up 11 August 2026 at 10:15 PM · made by you", or
    /// "Backed up 11 August 2026 at 10:15 PM · before an assistant chat
    /// about Section 1" — because choosing between five copies of the same
    /// course is a choice about what each one was FOR.
    var subtitle: String {
        return "Backed up \(whenDescription) · \(maker.description)"
    }

    /// A different mark for the assistant's own, so the two kinds can be
    /// told apart down a list without reading a word.
    /// What happens to this copy over time, which differs by who made it.
    ///
    /// Said per item rather than once for the list, because the two answers
    /// are genuinely different and a teacher deciding whether to keep their
    /// own copy needs THEIR answer, not the assistant's.
    var keptDescription: String {
        switch maker {
        case .teacher:
            return "You made this one, so it is kept until you delete it."
        case .assistant:
            return "The assistant made this one; its five most recent are kept."
        }
    }

    var symbolName: String {
        switch maker {
        case .teacher:
            return "clock.arrow.circlepath"
        case .assistant:
            return "sparkles"
        }
    }

    // MARK: - Functions

    /// Reads a backup's name: `<CODE>_backup_<timestamp>.zip` for one the
    /// teacher made, and `<CODE>_backup_<timestamp>_assistant-section<N>.zip`
    /// for one the assistant made. Returns nil for anything else — archives
    /// and the wizard's automatic zips included.
    static func from(fileURL: URL, courseCode: String) -> BackupItem? {
        if fileURL.pathExtension.lowercased() != "zip" {
            return nil
        }
        let name: String = fileURL.deletingPathExtension().lastPathComponent
        let expectedPrefix: String = "\(courseCode)_backup_"
        if !name.hasPrefix(expectedPrefix) {
            return nil
        }

        // What is left is "2026-08-11_221530", possibly followed by one more
        // underscore-separated piece saying who made it. The timestamp holds
        // an underscore of its own, so it is the first two pieces.
        let remainder: String = String(name.dropFirst(expectedPrefix.count))
        let pieces: [String] = remainder.components(separatedBy: "_")
        if pieces.count < 2 || pieces.count > 3 {
            return nil
        }
        let stamp: String = pieces[0] + "_" + pieces[1]
        guard let backedUpAt = ArchiveStamp.moment(from: stamp) else {
            return nil
        }

        var maker: BackupMaker = .teacher
        if pieces.count == 3 {
            guard let namedMaker = BackupMaker.reading(pieces[2]) else {
                return nil
            }
            maker = namedMaker
        }

        return BackupItem(
            courseCode: courseCode,
            backedUpAt: backedUpAt,
            fileURL: fileURL,
            maker: maker
        )
    }
}

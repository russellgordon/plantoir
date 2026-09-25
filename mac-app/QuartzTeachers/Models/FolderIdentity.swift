import Foundation

/// One folder, however it was spelled (GitHub #189).
///
/// A working folder can reach Plantoir under several spellings of one path:
/// through a link, with `/tmp` for `/private/tmp`, by the firmlink
/// `/System/Volumes/Data/…`, in the wrong case (the Mac's disk ignores case),
/// or with an accented letter in the other Unicode form (é stored as one
/// character by Terminal, a zip or a Windows PC; as e plus an accent by
/// Finder — and the disk treats the two as the same name). Every one of them
/// names the SAME folder, so every one must give the same answer here.
///
/// **This is the one place that decides it, and the launchers ask the same
/// question.** The container a folder builds in and the folder its websites
/// are kept in are both named by a hash of this path
/// (`BuildOutputLocation.folderIdentifier`), and the launchers hash
/// `/bin/pwd -P` after moving into `$(/bin/pwd -P)`. `fcntl(F_GETPATH)` on an
/// open folder and `/bin/pwd -P` both ask the disk for the folder's own name:
/// measured byte for byte the same on all seventeen spellings in
/// documentation/09-mac-app.md, "One folder, however it is spelled".
///
/// **What was rejected, and why.** `realpath(3)` — what this used to be —
/// keeps a `/System/Volumes/Data` prefix where `/bin/pwd -P` drops it, so
/// the firmlink spelling hashed differently on the two sides. bash's
/// BUILT-IN `pwd -P`, which the launchers ran until #189, keeps the TYPED
/// case and Unicode form, so a wrong-case or differently-normalised
/// spelling gave the launchers a second container and a second builds
/// folder. Foundation's `resolvingSymlinksInPath()` strips `/private` and
/// folds neither case nor form.
///
/// **Changing this changes the hash AND every comparison**, because they are
/// the same function on purpose: a comparison that disagreed with the hash
/// would call two spellings of the open folder different folders, and
/// re-choosing it would stop the workspace it is using.
nonisolated enum FolderIdentity {

    // MARK: - Functions

    /// The disk's own spelling of `path`: links resolved, `/private` kept,
    /// the firmlink prefix dropped, and each name in the case and Unicode
    /// form the disk stored it in.
    ///
    /// A path that cannot be opened (gone, on a disk that is not plugged in,
    /// or behind a permission Plantoir has not been given) falls back to
    /// `realpath`, and then to the text as it came in — the honest answer
    /// when the disk cannot be asked.
    static func canonicalPath(_ path: String) -> String {
        // O_EVTONLY: opened only to be asked its name. It needs no read
        // permission on the folder, and it does not stop a disk from being
        // ejected while it is open. O_NONBLOCK: a FIFO would otherwise block
        // the open until a writer came (measured, #189 review L2), and this
        // runs on the main actor; F_GETPATH still answers.
        let descriptor: Int32 = open(path, O_EVTONLY | O_NONBLOCK)
        if descriptor >= 0 {
            var buffer: [CChar] = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let answer: Int32 = fcntl(descriptor, F_GETPATH, &buffer)
            close(descriptor)
            if answer != -1 {
                return String(cString: buffer)
            }
        }
        if let resolved = realpath(path, nil) {
            let physical: String = String(cString: resolved)
            free(resolved)
            return physical
        }
        return path
    }

    /// True when two spellings name the same folder.
    ///
    /// Both sides are put in the disk's own spelling first, so case, links,
    /// `/private` and the firmlink stop mattering. A path that cannot be
    /// resolved compares by its text — Swift's `==` already treats the two
    /// Unicode forms of a name as equal, though not two cases — which is what
    /// every comparison here did before #189.
    static func isSameFolder(_ first: String, _ second: String) -> Bool {
        let firstCanonical: String = canonicalPath(first)
        let secondCanonical: String = canonicalPath(second)
        return firstCanonical == secondCanonical
    }
}

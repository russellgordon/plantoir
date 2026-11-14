import CryptoKit
import Darwin
import Foundation

/// The file calls the shared Media store makes on a course's own files, by
/// NAME BYTES and relative to an open folder (#785 implementation review,
/// W1 and W2).
///
/// **Why not `URL` or `FileManager`.** A name is carried as the exact bytes
/// the directory listing gave, end to end, because that is what a whole zip
/// keeps: `zip` stores the bytes and `ditto` puts the same bytes back.
/// Measured on APFS: `URL.appendingPathComponent(…).path` and
/// `withUnsafeFileSystemRepresentation` turn a precomposed `café.png`
/// (`caf\xc3\xa9`) into the decomposed `cafe\xcc\x81`, so a restore built on
/// them brought the picture back under other bytes. Finder and Obsidian on
/// APFS do not tell the two apart; the website builder, which reads the
/// course from Linux, does. A Swift `String` passed straight to a POSIX call
/// is handed over as its UTF-8, unchanged, so every call here takes one.
///
/// **Why relative to an open folder.** `zip -r` walks the course from its
/// parent folder, following links, and stops where the system refuses to
/// follow any more of them in one path (`ELOOP`, 32 links on macOS:
/// measured, a link back to its own parent gave 100 entries before it
/// stopped). Paths resolved from the same folder (`openat`, `fstatat`)
/// count the same links, where an absolute path would also count any link
/// above the working folder and stop one level early.
nonisolated enum SharedMediaFiles {

    // MARK: - Types

    /// What `fstatat` says about one path, links followed.
    struct Facts: Sendable {

        // MARK: - Stored properties

        let isFolder: Bool
        let isRegularFile: Bool
        let size: Int64
        let modified: Date
        let mode: Int
    }

    /// An open folder that relative paths are resolved from. Closed by
    /// `close()` or when the last reference goes.
    final class Folder: @unchecked Sendable {

        // MARK: - Stored properties

        let descriptor: Int32

        // MARK: - Initializer

        /// Opens the folder at `path`, or nil when it cannot be opened.
        init?(path: String) {
            let opened: Int32 = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
            if opened < 0 {
                return nil
            }
            descriptor = opened
        }

        deinit {
            Darwin.close(descriptor)
        }
    }

    // MARK: - Functions

    /// The names in a folder, as the listing gives their bytes, `.` and `..`
    /// left out, in byte order (Swift's own `<` treats the two Unicode forms
    /// of a name as equal, so it cannot order them).
    static func names(in folder: Folder, at relativePath: String) -> [String]? {
        let opened: Int32 = openat(folder.descriptor, relativePath, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        if opened < 0 {
            return nil
        }
        guard let listing = fdopendir(opened) else {
            Darwin.close(opened)
            return nil
        }
        defer {
            closedir(listing)
        }
        var found: [[UInt8]] = []
        while let entry = readdir(listing) {
            var bytes: [UInt8] = []
            let length: Int = Int(entry.pointee.d_namlen)
            withUnsafeBytes(of: entry.pointee.d_name) { (raw: UnsafeRawBufferPointer) in
                for index in 0..<length {
                    bytes.append(raw[index])
                }
            }
            if bytes == [46] || bytes == [46, 46] {
                continue
            }
            found.append(bytes)
        }
        found.sort { (first: [UInt8], second: [UInt8]) -> Bool in
            return first.lexicographicallyPrecedes(second)
        }
        var names: [String] = []
        for bytes in found {
            names.append(String(decoding: bytes, as: UTF8.self))
        }
        return names
    }

    /// What a path is, following links; nil when it leads nowhere (a link
    /// to nothing, or too many links in one path), as `zip -r` finds it.
    static func facts(in folder: Folder, at relativePath: String) -> Facts? {
        var status: stat = stat()
        if fstatat(folder.descriptor, relativePath, &status, 0) != 0 {
            return nil
        }
        let kind: mode_t = status.st_mode & S_IFMT
        let seconds: Double = Double(status.st_mtimespec.tv_sec) + Double(status.st_mtimespec.tv_nsec) / 1_000_000_000
        return Facts(
            isFolder: kind == S_IFDIR,
            isRegularFile: kind == S_IFREG,
            size: Int64(status.st_size),
            modified: Date(timeIntervalSince1970: seconds),
            mode: Int(status.st_mode & 0o7777)
        )
    }

    /// The SHA-256 of a file, read a megabyte at a time; nil when it cannot
    /// be read.
    static func checksum(in folder: Folder, at relativePath: String) -> String? {
        let opened: Int32 = openat(folder.descriptor, relativePath, O_RDONLY | O_CLOEXEC)
        if opened < 0 {
            return nil
        }
        defer {
            Darwin.close(opened)
        }
        return checksum(ofOpenFile: opened)
    }

    static func checksum(ofOpenFile descriptor: Int32) -> String? {
        var hasher: SHA256 = SHA256()
        var buffer: [UInt8] = [UInt8](repeating: 0, count: 1 << 20)
        while true {
            let count: Int = buffer.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) -> Int in
                return read(descriptor, raw.baseAddress, raw.count)
            }
            if count < 0 {
                if errno == EINTR {
                    continue
                }
                return nil
            }
            if count == 0 {
                break
            }
            buffer.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: raw[0..<count]))
            }
        }
        var text: String = ""
        for byte in hasher.finalize() {
            text += String(format: "%02x", byte)
        }
        return text
    }

    /// Copies one file's bytes from `source` in one folder to a NEW name in
    /// another: cloned where the volume can (APFS: no new blocks until
    /// either copy changes), copied where it cannot. Extended attributes are
    /// taken off and the permissions set to 0644, so the copy carries what a
    /// whole zip's restore would (`zip -X` keeps neither).
    static func copy(
        from sourceFolder: Folder, at sourcePath: String,
        to destinationFolder: Folder, at destinationPath: String
    ) -> Bool {
        let source: Int32 = openat(sourceFolder.descriptor, sourcePath, O_RDONLY | O_CLOEXEC)
        if source < 0 {
            return false
        }
        defer {
            Darwin.close(source)
        }
        if fclonefileat(source, destinationFolder.descriptor, destinationPath, 0) != 0 {
            let destination: Int32 = openat(
                destinationFolder.descriptor, destinationPath,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o644
            )
            if destination < 0 {
                return false
            }
            let copied: Int32 = fcopyfile(source, destination, nil, copyfile_flags_t(COPYFILE_DATA))
            Darwin.close(destination)
            if copied != 0 {
                unlinkat(destinationFolder.descriptor, destinationPath, 0)
                return false
            }
        }
        removeExtendedAttributes(in: destinationFolder, at: destinationPath)
        fchmodat(destinationFolder.descriptor, destinationPath, 0o644, 0)
        return true
    }

    static func removeExtendedAttributes(in folder: Folder, at relativePath: String) {
        let opened: Int32 = openat(folder.descriptor, relativePath, O_RDONLY | O_CLOEXEC)
        if opened < 0 {
            return
        }
        defer {
            Darwin.close(opened)
        }
        let size: Int = flistxattr(opened, nil, 0, 0)
        if size <= 0 {
            return
        }
        var buffer: [CChar] = [CChar](repeating: 0, count: size)
        let read: Int = flistxattr(opened, &buffer, size, 0)
        if read <= 0 {
            return
        }
        var names: [String] = []
        var current: [UInt8] = []
        for index in 0..<read {
            if buffer[index] == 0 {
                names.append(String(decoding: current, as: UTF8.self))
                current = []
            } else {
                current.append(UInt8(bitPattern: buffer[index]))
            }
        }
        for name in names {
            fremovexattr(opened, name, 0)
        }
    }

    /// Makes every missing folder along a relative path.
    static func makeFolders(in folder: Folder, at relativePath: String) -> Bool {
        var built: String = ""
        for part in relativePath.split(separator: "/", omittingEmptySubsequences: true) {
            built = built.isEmpty ? String(part) : built + "/" + String(part)
            if mkdirat(folder.descriptor, built, 0o755) != 0 && errno != EEXIST {
                return false
            }
        }
        return true
    }

    static func flush(in folder: Folder, at relativePath: String) {
        let opened: Int32 = openat(folder.descriptor, relativePath, O_RDONLY | O_CLOEXEC)
        if opened < 0 {
            return
        }
        fsync(opened)
        Darwin.close(opened)
    }

    static func rename(in folder: Folder, from source: String, to destination: String) -> Bool {
        return renameat(folder.descriptor, source, folder.descriptor, destination) == 0
    }

    static func remove(in folder: Folder, at relativePath: String) {
        unlinkat(folder.descriptor, relativePath, 0)
    }

    static func setMode(in folder: Folder, at relativePath: String, _ mode: Int) {
        fchmodat(folder.descriptor, relativePath, mode_t(mode & 0o7777), 0)
    }

    static func setModified(in folder: Folder, at relativePath: String, _ moment: Date) {
        let seconds: Double = moment.timeIntervalSince1970
        let whole: Double = seconds.rounded(.down)
        let nanoseconds: Int = Int(((seconds - whole) * 1_000_000_000).rounded())
        let when: timespec = timespec(tv_sec: Int(whole), tv_nsec: min(nanoseconds, 999_999_999))
        var times: [timespec] = [when, when]
        utimensat(folder.descriptor, relativePath, &times, 0)
    }
}

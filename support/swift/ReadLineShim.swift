// readLine() support for Embedded Swift on wasm32-unknown-wasip1 (#493).
// Embedded Swift's library declares this C entry point and does not provide
// it, so without this file every block that calls readLine() fails to link
// (Phase 0 §3). Same contract as the full library's Stubs.cpp: answer the
// number of bytes read (including the newline) and hand back a malloc'd
// buffer, or -1 at the end of input.
//
// It flushes stdout first, as a terminal would show it: a prompt printed with
// `terminator: ""` is still in stdout's buffer when the program reads, and
// without the flush the input box's line - which the page echoes as it is
// read - would appear BEFORE the prompt (measured 2026-10-17). The full
// library gets the same flush from FlushBeforeRead.c.
import WASILibc

@_cdecl("swift_stdlib_readLine_stdin")
func swiftStdlibReadLineStdin(_ lineBuffer: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int {
    fflush(stdout)
    var capacity: Int = 0
    let bytesRead: Int = getline(lineBuffer, &capacity, stdin)
    if bytesRead < 0 {
        return -1
    }
    return bytesRead
}

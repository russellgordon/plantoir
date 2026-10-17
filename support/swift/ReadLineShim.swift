// readLine() support for Embedded Swift on wasm32-unknown-wasip1.
// Same contract as the full stdlib's Stubs.cpp: return the number of bytes
// read (including the newline) and hand back a malloc'd buffer, or -1 at EOF.
import WASILibc

@_cdecl("swift_stdlib_readLine_stdin")
func swiftStdlibReadLineStdin(_ lineBuffer: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int {
    var capacity: Int = 0
    let bytesRead: Int = getline(lineBuffer, &capacity, stdin)
    if bytesRead < 0 {
        return -1
    }
    return bytesRead
}

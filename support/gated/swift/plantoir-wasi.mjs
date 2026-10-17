// Runnable Swift (#493): the small piece of an operating system a compiled
// Swift program asks for, hand-rolled (wasi_snapshot_preview1).
//
// One file, used by BOTH the page's Swift thread (plantoir-swift-worker.js,
// beside it in a site's static/swift/) and the gate that checks every
// swift-gate/ fragment in Node (browser-checks/wasi_run.mjs) - so the gate
// tests exactly what students run. No packages: what is here is what a
// program compiled by support/swift/compile.py calls, measured (#493 Phase 0
// and the spike):
//
//   Embedded binaries import 8: args_get, args_sizes_get, fd_fdstat_get,
//   fd_read, fd_seek, fd_write, proc_exit, random_get. Full-library binaries
//   import 6 more: environ_get, environ_sizes_get, fd_close, fd_prestat_get,
//   fd_prestat_dir_name, path_open. Neither imports clock_time_get today; it
//   is here so a toolchain that does never fails to link. Any OTHER
//   wasi_snapshot_preview1 import answers ENOSYS, filled in from the module's
//   own import list.
//
// The rules that matter, each measured (contracts/shared-rules.json ->
// codeRunnerBlocks.swift.wasi):
//
// * fds 0-2 report themselves as a CHARACTER DEVICE whose rights do NOT
//   include FD_SEEK or FD_TELL. wasi-libc's isatty() wants both; without
//   them stdout is fully buffered, output arrives all at once at the end,
//   and Embedded Swift's `Fatal error:` line - which goes to stdout - is
//   LOST when the program traps (spike G5; the gate's must-fail).
// * stdin hands over ONE line per fd_read, and each line is echoed into the
//   output as it is taken, straight after the prompt (review S6; the same
//   transcript as Python's input(), codeRunnerBlocks.stdin). Past the last
//   line, fd_read answers 0 bytes: the end of input, so readLine() is nil.
// * proc_exit throws ProgramExit carrying the code; a trap is the engine's
//   own error (WebAssembly.RuntimeError, or RangeError when the program
//   recursed past the engine's stack - review S5), which the caller maps.

export const ERRNO = { SUCCESS: 0, BADF: 8, INVAL: 28, NOSYS: 52, SPIPE: 70, NOTCAPABLE: 76 }

const CHARACTER_DEVICE = 2
const RIGHT_FD_SEEK = 0x4n
const RIGHT_FD_TELL = 0x20n
export const TERMINAL_RIGHTS = 0xffffffffn & ~(RIGHT_FD_SEEK | RIGHT_FD_TELL)
// Every right, seek and tell included: only the gate's must-fail uses it, to
// show the Fatal-error line is lost without the rule above.
export const ALL_RIGHTS = 0xffffffffn
const MOST_RANDOM_BYTES = 65536 // crypto.getRandomValues' own limit per call

export class ProgramExit {
  constructor(code) {
    this.code = code
  }
}

// `lines`: the input box's lines, without their newlines. `out(text, err)`:
// called with each piece of output as it is written, decoded per stream
// (a character split across two writes is held until it is whole), and with
// each input line as it is read (err false) unless `echo` is false. `rights`
// and `echo` are for the gate alone.
export function wasiFor(module, { lines = [], out = () => {}, rights = TERMINAL_RIGHTS, echo = true } = {}) {
  let memory = null
  const encoder = new TextEncoder()
  const decoders = { 1: new TextDecoder(), 2: new TextDecoder() }
  const waiting = lines.slice()
  let pending = null // the bytes of a line not yet handed over whole
  const calls = new Map()

  const view = () => new DataView(memory.buffer)
  const bytes = () => new Uint8Array(memory.buffer)
  const ioVectors = (pointer, count) => {
    const data = view()
    const list = []
    for (let index = 0; index < count; index += 1) {
      list.push([data.getUint32(pointer + index * 8, true), data.getUint32(pointer + index * 8 + 4, true)])
    }
    return list
  }

  const implemented = {
    fd_write(fd, iovs, count, written) {
      if (fd !== 1 && fd !== 2) return ERRNO.BADF
      let total = 0
      for (const [pointer, length] of ioVectors(iovs, count)) {
        const text = decoders[fd].decode(bytes().slice(pointer, pointer + length), { stream: true })
        if (text.length > 0) out(text, fd === 2)
        total += length
      }
      view().setUint32(written, total, true)
      return ERRNO.SUCCESS
    },
    fd_read(fd, iovs, count, read) {
      if (fd !== 0) return ERRNO.BADF
      if (pending === null && waiting.length > 0) {
        const line = waiting.shift()
        if (echo) out(line + "\n", false)
        pending = encoder.encode(line + "\n")
      }
      let total = 0
      if (pending !== null) {
        for (const [pointer, length] of ioVectors(iovs, count)) {
          const take = Math.min(length, pending.length)
          bytes().set(pending.subarray(0, take), pointer)
          pending = pending.subarray(take)
          total += take
          if (pending.length === 0) {
            pending = null
            break
          }
        }
      }
      view().setUint32(read, total, true)
      return ERRNO.SUCCESS
    },
    fd_fdstat_get(fd, stat) {
      if (fd > 2) return ERRNO.BADF
      const data = view()
      data.setUint8(stat, CHARACTER_DEVICE)
      data.setUint16(stat + 2, 0, true)
      data.setBigUint64(stat + 8, rights, true)
      data.setBigUint64(stat + 16, 0xffffffffn, true)
      return ERRNO.SUCCESS
    },
    fd_seek(fd) {
      return fd <= 2 ? ERRNO.SPIPE : ERRNO.BADF
    },
    fd_close(fd) {
      return fd <= 2 ? ERRNO.SUCCESS : ERRNO.BADF
    },
    fd_prestat_get() {
      return ERRNO.BADF // no folders are given to the program
    },
    fd_prestat_dir_name() {
      return ERRNO.BADF
    },
    path_open() {
      return ERRNO.NOTCAPABLE
    },
    proc_exit(code) {
      throw new ProgramExit(code)
    },
    args_sizes_get(count, size) {
      view().setUint32(count, 1, true)
      view().setUint32(size, 5, true)
      return ERRNO.SUCCESS
    },
    args_get(argv, buffer) {
      view().setUint32(argv, buffer, true)
      bytes().set([109, 97, 105, 110, 0], buffer) // "main"
      return ERRNO.SUCCESS
    },
    environ_sizes_get(count, size) {
      view().setUint32(count, 0, true)
      view().setUint32(size, 0, true)
      return ERRNO.SUCCESS
    },
    environ_get() {
      return ERRNO.SUCCESS
    },
    random_get(pointer, length) {
      for (let offset = 0; offset < length; offset += MOST_RANDOM_BYTES) {
        const piece = Math.min(MOST_RANDOM_BYTES, length - offset)
        crypto.getRandomValues(bytes().subarray(pointer + offset, pointer + offset + piece))
      }
      return ERRNO.SUCCESS
    },
    clock_time_get(id, precision, time) {
      const nanoseconds = BigInt(Math.round((performance.timeOrigin + performance.now()) * 1e6))
      view().setBigUint64(time, nanoseconds, true)
      return ERRNO.SUCCESS
    },
  }

  const imports = {}
  for (const entry of WebAssembly.Module.imports(module)) {
    if (entry.module !== "wasi_snapshot_preview1" || entry.kind !== "function") continue
    const call = implemented[entry.name]
    imports[entry.name] = (...args) => {
      calls.set(entry.name, (calls.get(entry.name) ?? 0) + 1)
      return call ? call(...args) : ERRNO.NOSYS
    }
  }

  return {
    imports: { wasi_snapshot_preview1: imports },
    attach(instance) {
      memory = instance.exports.memory
    },
    // Anything a decoder still holds when the program ends (a character
    // left half-written).
    flush() {
      for (const fd of [1, 2]) {
        const rest = decoders[fd].decode()
        if (rest.length > 0) out(rest, fd === 2)
      }
    },
    calls,
  }
}

// Run one program to its end: a fresh instance every time (a Swift program
// runs once). Answers {exit: code} when it returned or called exit, or
// {crashed: true, error} when it trapped.
export async function runProgram(module, { lines = [], out = () => {}, rights = TERMINAL_RIGHTS, echo = true } = {}) {
  const wasi = wasiFor(module, { lines, out, rights, echo })
  const instance = await WebAssembly.instantiate(module, wasi.imports)
  wasi.attach(instance)
  try {
    instance.exports._start()
    wasi.flush()
    return { exit: 0, calls: wasi.calls }
  } catch (error) {
    wasi.flush()
    if (error instanceof ProgramExit) {
      return { exit: error.code, calls: wasi.calls }
    }
    if (error instanceof WebAssembly.RuntimeError || error instanceof RangeError) {
      return { crashed: true, error, calls: wasi.calls }
    }
    throw error
  }
}

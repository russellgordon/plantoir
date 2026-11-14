// The processes a browser check starts, ended whenever the check ends (#906).
//
// A check started its headless Chrome with a plain spawn and ended it in its
// own finish(). Killed from outside before finish() ran, Node ended at once
// and left the browser running with no parent: measured 2026-11-13, a stand-in
// check given SIGTERM left all 10 of its Chrome for Testing processes running.
// They hold memory and a debugging port, and the next run meets them as a
// fault with no obvious cause.
//
// So a check starts its browser with spawnOwned(), and every way a check
// can end ends what it started: a normal exit, process.exit(), an uncaught
// error, and SIGINT, SIGTERM or SIGHUP from outside (each answered by ending
// the children, then exiting 128 + the signal's number, the code the shell
// gives a process the signal ended). Only the children this process started,
// and only while Node has not yet seen them end, are sent anything: a process
// the check did not start is never touched.
//
// SIGKILL cannot be answered. A browser left by a check killed that way still
// carries checkoutMark() on its command line, which is how leftovers() finds
// it: a process carrying THIS checkout's mark whose parent is gone (it has
// been handed to launchd, pid 1). verify.sh names them before its browser
// checks; ending them is left to whoever reads the line (the run did not
// start them), unless PLANTOIR_END_LEFTOVER_BROWSERS=1 asks for it.
//
// Rejected: starting the browser in a process group of its own and ending
// the group. A browser in the check's own group already receives a signal
// sent to the whole group, SIGKILL included, so detaching it would make the
// one case nothing can answer worse. Ending Chrome's main process ends its
// helpers: measured, all 10 gone within 3 s of a SIGTERM to the main one.
//
//   node browser-checks/lib/own_processes.mjs leftovers [--end]
//
// No packages; Node 22.

import { execFileSync, spawn } from "node:child_process"
import { fileURLToPath } from "node:url"
import { dirname, resolve } from "node:path"

const CHECKOUT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..")
const SIGNAL_NUMBERS = { SIGHUP: 1, SIGINT: 2, SIGTERM: 15 }
const owned = new Set()
let answering = false

// The switch every browser a check starts carries: Chrome keeps a switch it
// does not know on its main process's command line and does nothing with it.
// The checkout is written with encodeURI, so the mark holds no space and ends
// where the argument ends: unencoded, the mark of a checkout /x/plantoir was
// the start of the mark of a checkout "/x/plantoir two", followed by a space.
export function checkoutMark(checkout = CHECKOUT) {
  return `--plantoir-check-of=${encodeURI(checkout)}`
}

function stillRunning(child) {
  return child.exitCode === null && child.signalCode === null
}

// Ends every child this process started that Node has not seen end.
export function endOwned(signal = "SIGTERM") {
  for (const child of owned) {
    if (!stillRunning(child)) continue
    try {
      child.kill(signal)
    } catch {}
  }
}

function answerEveryEnding() {
  if (answering) return
  answering = true
  process.on("exit", () => endOwned())
  for (const [signal, number] of Object.entries(SIGNAL_NUMBERS)) {
    process.on(signal, () => {
      endOwned()
      process.exit(128 + number)
    })
  }
}

// spawn(), with the child ended whenever this process ends. `mark` adds
// checkoutMark() as the first argument, for a browser.
export function spawnOwned(command, args, options = {}, { mark = false } = {}) {
  answerEveryEnding()
  const child = spawn(command, mark ? [checkoutMark(), ...args] : args, options)
  owned.add(child)
  child.once("exit", () => owned.delete(child))
  return child
}

// A check's browser: spawnOwned() with this checkout's mark on it.
export function spawnBrowser(command, args, options = {}) {
  return spawnOwned(command, args, options, { mark: true })
}

// Browsers left by an earlier check of this checkout: carrying its mark,
// with their parent gone. Answers [{ pid, command }].
export function leftovers(checkout = CHECKOUT) {
  const mark = checkoutMark(checkout)
  let table = ""
  try {
    table = execFileSync("/bin/ps", ["-axww", "-o", "pid=,ppid=,command="], { encoding: "utf-8" })
  } catch {
    return []
  }
  const found = []
  for (const line of table.split("\n")) {
    const row = /^\s*(\d+)\s+(\d+)\s+(.*)$/.exec(line)
    if (row === null) continue
    const [, pid, parent, command] = row
    // The mark ends at the end of the argument: a checkout whose path is
    // this one's with more after it is another checkout. The mark holds no
    // space (checkoutMark), so a space after it is the end of the argument.
    const at = command.indexOf(mark)
    if (at === -1) continue
    const after = command.slice(at + mark.length, at + mark.length + 1)
    if (after !== "" && after !== " ") continue
    if (Number(parent) !== 1) continue
    found.push({ pid: Number(pid), command: command.slice(0, 160) })
  }
  return found
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [what, ...rest] = process.argv.slice(2)
  if (what !== "leftovers") {
    console.error("usage: node browser-checks/lib/own_processes.mjs leftovers [--end]")
    process.exit(2)
  }
  const left = leftovers()
  if (left.length === 0) {
    console.log("NONE: no browser from an earlier check of this checkout is still running")
    process.exit(0)
  }
  const pids = left.map((leftover) => leftover.pid).join(" ")
  if (rest.includes("--end")) {
    for (const { pid } of left) {
      try {
        process.kill(pid, "SIGTERM")
      } catch {}
    }
    console.log(`ENDED: ${left.length} browser(s) left running by an earlier check of this checkout, pid ${pids}`)
  } else {
    console.log(`LEFTOVER: ${left.length} browser(s) left running by an earlier check of this checkout, pid ${pids}; end them with: kill ${pids}`)
  }
  process.exit(0)
}

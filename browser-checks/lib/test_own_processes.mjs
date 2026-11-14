// Tests for browser-checks/lib/own_processes.mjs (#906): a check that is
// ended from outside ends what it started, and nothing else.
//
// Each case starts a stand-in check (a child Node running this file with
// --as-check) that starts a sleeper through spawnOwned, then ends the
// stand-in the way a gate might, and asks whether the sleeper is still
// running. A sleeper started with a plain spawn is the must-fail: it
// survives, which proves the test can see a leak. With Chrome for Testing
// on this Mac (PLANTOIR_CHROME, or the copy fetch-browsers.sh installs) the
// same is done to a real headless Chrome, counting its processes before and
// after; without it that case is a SKIP by name.
//
//   node browser-checks/lib/test_own_processes.mjs
//
// Every process this test starts is ended by it: by pid, never by name.

import { spawn } from "node:child_process"
import { existsSync, mkdirSync, mkdtempSync, readdirSync, rmSync } from "node:fs"
import { homedir, tmpdir } from "node:os"
import { join } from "node:path"
import { fileURLToPath } from "node:url"
import { checkoutMark, leftovers, spawnBrowser, spawnOwned } from "./own_processes.mjs"

const HERE = fileURLToPath(import.meta.url)
const SLEEPER = ["-e", "setTimeout(() => {}, 600000)"]
const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))

// ---- the stand-in check -------------------------------------------------

if (process.argv[2] === "--as-check") {
  const [, , , how, ending, extra] = process.argv
  let child
  if (how === "owned") child = spawnOwned(process.execPath, SLEEPER, { stdio: "ignore" })
  else if (how === "plain") child = spawn(process.execPath, SLEEPER, { stdio: "ignore" })
  else if (how === "marked") child = spawnOwned(process.execPath, [...SLEEPER, "--", checkoutMark(extra)], { stdio: "ignore" })
  else if (how === "chrome") {
    child = spawnBrowser(extra, [
      "--headless=new", "--remote-debugging-port=0", `--user-data-dir=${join(process.argv[7], "profile")}`,
      "--no-first-run", "--no-default-browser-check", "--use-mock-keychain", "--password-store=basic",
      "--mute-audio", "about:blank",
    ], { stdio: ["ignore", "ignore", "pipe"] })
    child.stderr.on("data", () => {})
  }
  console.log(`child ${child.pid}`)
  if (ending === "exit") setTimeout(() => process.exit(1), 300)
  else if (ending === "throw") setTimeout(() => { throw new Error("a check's own mistake") }, 300)
  else setTimeout(() => {}, 600000)
} else {
  await main()
}

// ---- the tests ------------------------------------------------------------

function running(pid) {
  try {
    process.kill(pid, 0)
    return true
  } catch (error) {
    return error.code === "EPERM"
  }
}

async function gone(pid, milliseconds = 5000) {
  const until = Date.now() + milliseconds
  while (Date.now() < until) {
    if (!running(pid)) return true
    await pause(50)
  }
  return !running(pid)
}

// Starts the stand-in; answers it once it has said its child's pid.
function standIn(how, ending, extra = "", work = "") {
  const check = spawn(process.execPath, [HERE, "--as-check", how, ending, extra, "", work], { stdio: ["ignore", "pipe", "ignore"] })
  const exited = new Promise((resolve) => check.once("exit", (code, signal) => resolve({ code, signal })))
  const child = new Promise((resolve, reject) => {
    let said = ""
    check.stdout.on("data", (chunk) => {
      said += chunk.toString()
      const found = /child (\d+)/.exec(said)
      if (found) resolve(Number(found[1]))
    })
    check.once("exit", () => reject(new Error("the stand-in ended before it started its child")))
  })
  return { check, exited, child }
}

function endOurs(pid) {
  try {
    process.kill(pid, "SIGTERM")
  } catch {}
}

async function main() {
  let failures = 0
  let skips = 0
  const expect = (what, ok, detail = "") => {
    if (!ok) failures += 1
    console.log(`${ok ? "ok  " : "FAIL"} ${what}${ok ? "" : " - " + detail}`)
  }

  for (const [signal, number] of [["SIGTERM", 15], ["SIGINT", 2], ["SIGHUP", 1]]) {
    const run = standIn("owned", "wait")
    const child = await run.child
    run.check.kill(signal)
    const { code } = await run.exited
    const ended = await gone(child)
    expect(`a check sent ${signal} ends the child it started, then exits ${128 + number}`, ended && code === 128 + number, `child ${ended ? "gone" : "still running"}, exit ${code}`)
    if (!ended) endOurs(child)
  }

  for (const ending of ["exit", "throw"]) {
    const run = standIn("owned", ending)
    const child = await run.child
    const { code } = await run.exited
    const ended = await gone(child)
    expect(`a check that ends by ${ending === "exit" ? "process.exit" : "an uncaught error"} ends the child it started`, ended && code !== 0, `child ${ended ? "gone" : "still running"}, exit ${code}`)
    if (!ended) endOurs(child)
  }

  {
    // The must-fail: what every check did before #906.
    const run = standIn("plain", "wait")
    const child = await run.child
    run.check.kill("SIGTERM")
    await run.exited
    const survived = !(await gone(child, 1500))
    expect("must-fail: a child started with a plain spawn outlives a check sent SIGTERM", survived, "it ended, so this test could not see a leak")
    endOurs(child)
  }

  {
    // Nothing the check did not start: a sleeper of this test's own, beside it.
    const bystander = spawn(process.execPath, SLEEPER, { stdio: "ignore" })
    const run = standIn("owned", "wait")
    const child = await run.child
    run.check.kill("SIGTERM")
    await run.exited
    const ended = await gone(child)
    expect("a check that is ended leaves a process it did not start running", running(bystander.pid), "the bystander was ended")
    endOurs(bystander.pid)
    if (!ended) endOurs(child)
  }

  {
    // SIGKILL cannot be answered: leftovers() finds what it leaves, by this
    // checkout's mark and a parent that is gone, and nothing else.
    // The checkout's path has a space in it, and another checkout's path is
    // the part before the space: neither may name the other's leftovers.
    const parent = mkdtempSync(join(tmpdir(), "plantoir-own-processes-checkout-"))
    const shorter = join(parent, "plantoir")
    const checkout = join(parent, "plantoir two")
    mkdirSync(shorter)
    mkdirSync(checkout)
    const run = standIn("marked", "wait", checkout)
    const child = await run.child
    await pause(200)
    const whileItsCheckRuns = leftovers(checkout)
    expect("a marked process whose check is still running is not a leftover", whileItsCheckRuns.length === 0, JSON.stringify(whileItsCheckRuns))
    run.check.kill("SIGKILL")
    await run.exited
    let found = []
    for (let attempt = 0; attempt < 40 && found.length === 0; attempt += 1) {
      await pause(50)
      found = leftovers(checkout)
    }
    expect("after SIGKILL, the check's child is named as a leftover of its checkout", found.length === 1 && found[0].pid === child, JSON.stringify(found))
    expect("and is no leftover of a checkout whose path only starts the same", leftovers(checkout.slice(0, -1)).length === 0 && leftovers(checkout + "x").length === 0)
    expect("nor of a checkout whose path is the part of this one's before a space", leftovers(shorter).length === 0, JSON.stringify(leftovers(shorter)))
    endOurs(child)
    await gone(child)
    rmSync(parent, { recursive: true, force: true })
  }

  {
    // A real headless Chrome, counted by its profile folder.
    const chrome = findChrome()
    if (chrome === null) {
      skips += 1
      console.log("SKIP a check's real Chrome is ended with it: no Chrome for Testing on this Mac (PLANTOIR_CHROME, or browser-checks/fetch-browsers.sh)")
    } else {
      const work = mkdtempSync(join(tmpdir(), "plantoir-own-processes-chrome-"))
      const count = () => countProcessesNaming(work)
      const before = await count()
      const run = standIn("chrome", "wait", chrome, work)
      const child = await run.child
      let during = 0
      for (let attempt = 0; attempt < 100 && during < 2; attempt += 1) {
        await pause(100)
        during = await count()
      }
      run.check.kill("SIGTERM")
      await run.exited
      let after = await count()
      for (let attempt = 0; attempt < 100 && after > 0; attempt += 1) {
        await pause(100)
        after = await count()
      }
      expect(`a check's real Chrome is ended with it: ${before} of its processes before, ${during} while it ran, ${after} after SIGTERM`, before === 0 && during >= 1 && after === 0)
      if (after > 0) endOurs(child)
      await gone(child)
      rmSync(work, { recursive: true, force: true })
    }
  }

  console.log(failures === 0 ? `OK: own_processes${skips ? `, ${skips} skipped` : ""}` : `FAILED: ${failures}`)
  process.exit(failures === 0 ? 0 : 1)
}

function findChrome() {
  if (process.env.PLANTOIR_CHROME && existsSync(process.env.PLANTOIR_CHROME)) return process.env.PLANTOIR_CHROME
  const root = join(homedir(), "Library", "Caches", "Plantoir-dev", "browsers", "chrome")
  let found = null
  const entries = (folder) => {
    try {
      return readdirSync(folder)
    } catch {
      return []
    }
  }
  for (const version of entries(root)) {
    for (const build of entries(join(root, version))) {
      const binary = join(root, version, build, "Google Chrome for Testing.app", "Contents", "MacOS", "Google Chrome for Testing")
      if (existsSync(binary)) found = binary
    }
  }
  return found
}

// Processes whose command line names `text` (Chrome's main process and its
// helpers each name the profile folder).
function countProcessesNaming(text) {
  return new Promise((resolve) => {
    const ps = spawn("/bin/ps", ["-axww", "-o", "command="], { stdio: ["ignore", "pipe", "ignore"] })
    let table = ""
    ps.stdout.on("data", (chunk) => (table += chunk.toString()))
    ps.once("exit", () => {
      let count = 0
      for (const line of table.split("\n")) if (line.includes(text)) count += 1
      resolve(count)
    })
  })
}

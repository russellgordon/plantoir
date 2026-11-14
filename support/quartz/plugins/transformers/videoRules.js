// YouTube and Vimeo videos written as a picture (#692): the rules the site's
// transformer (plantoirVideo.ts) and its check share, so the two cannot
// drift. contracts/shared-rules.json -> videoEmbeds holds every case, and
// scripts/check_video_rules_against_the_site.py runs each one through the
// site's own Markdown reader, this file, and Quartz's own YouTube step.
//
// Plain JavaScript (an ES module, like pictureSizes.js), with no imports:
// the transformer imports it through esbuild and the check imports the SAME
// file in Node.
//
// What a teacher writes is the address the video site's Share button gives,
// in the picture form, on its own line:
//
//   ![Mitosis in three minutes](https://vimeo.com/76979871)
//   ![](https://vimeo.com/123456789/abcdef1234)         an unlisted video
//   ![](https://www.youtube.com/watch?v=WUvTyaaNkzM&t=90)
//
// playerFor(src) answers one of:
//   { host: "youtube" | "vimeo", src: <player address> }
//   { host: "vimeo", notAVideo: true }   a vimeo.com address that is not one
//                                        video (a showcase, a profile): it
//                                        stays the picture it always was
//   null                                 not a video address at all
//
// YouTube. Every address Quartz v4.5.0's own YouTube step reads
// (ofm.ts, ytLinkRegex and ytPlaylistLinkRegex, copied below unchanged, so
// an address that played before still plays), plus Shorts
// (youtube.com/shorts/<id>, the form the Share button gives for a Short).
// The player is the privacy-enhanced one, www.youtube-nocookie.com (Russell's
// ruling on #692, 2026-11-13), with the start time a `t=` or `start=` asked
// for as `start=<seconds>`.
//
// Vimeo. vimeo.com/<id>, vimeo.com/<id>/<hash> (unlisted: the hash is the
// video's privacy part and the player needs it), the channel and group
// forms, and a player address pasted as it is. The player is
// player.vimeo.com/video/<id>, with `h=<hash>` FIRST when there is one and
// then `dnt=1` (Vimeo's do-not-track setting, the same ruling). Vimeo's own
// help: "All additional parameters ... must be added after this privacy
// hash" (help.vimeo.com, article 12426285089681, read 2026-11-13). A start
// time is kept as Vimeo's own `#t=`.

// Quartz v4.5.0, quartz/plugins/transformers/ofm.ts lines 142 and 143.
const ytLinkRegex = /^.*(youtu.be\/|v\/|u\/\w\/|embed\/|watch\?v=|\&v=)([^#\&\?]*).*/
const ytPlaylistLinkRegex = /[?&]list=([^#?&]*)/

const YOUTUBE_PLAYER = "https://www.youtube-nocookie.com/embed/"
const VIMEO_PLAYER = "https://player.vimeo.com/video/"

// The title a player carries when the brackets were left empty
// (videoEmbeds.titles). Never "iframe" or "embed" (CLAUDE.md rule 1).
export const FALLBACK_TITLES = { youtube: "YouTube video", vimeo: "Vimeo video" }

// What the build prints for a vimeo.com address that is not one video
// (videoEmbeds.notes.notAVideo), after "plantoir: note: ".
export const NOT_A_VIDEO =
  "{page}: line {line}: {address} is not the address of one Vimeo video, so the page shows it as a broken picture. Use the address the video's Share button gives."

export function notAVideoNote(page, line, address) {
  return NOT_A_VIDEO.replace("{page}", page).replace("{line}", String(line)).replace("{address}", address)
}

// Every player's attributes beside src and title (videoEmbeds.player).
// referrerpolicy is the one Vimeo's own embed code carries, so a video its
// owner limited to "specific domains" still sees the class site's address;
// a player sent no referrer at all may refuse to play. Do not tighten it to
// no-referrer.
export const PLAYER_ATTRIBUTES = {
  loading: "lazy",
  allow: "fullscreen; picture-in-picture; encrypted-media",
  allowfullscreen: true,
  referrerpolicy: "strict-origin-when-cross-origin",
  frameborder: "0",
}

function parsed(src) {
  try {
    return new URL(src)
  } catch {
    return null
  }
}

// "90", "90s", "1m30s", "1h2m3s" -> seconds; anything else -> null.
export function secondsOf(value) {
  if (typeof value !== "string" || value === "") {
    return null
  }
  if (/^\d+$/.test(value)) {
    return Number(value)
  }
  const match = value.match(/^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$/)
  if (match === null || (match[1] === undefined && match[2] === undefined && match[3] === undefined)) {
    return null
  }
  let seconds = 0
  if (match[1] !== undefined) {
    seconds += Number(match[1]) * 3600
  }
  if (match[2] !== undefined) {
    seconds += Number(match[2]) * 60
  }
  if (match[3] !== undefined) {
    seconds += Number(match[3])
  }
  return seconds
}

// The value of `name` in the address's query or in a `#name=` part.
function partNamed(src, name) {
  const pattern = new RegExp("[?&#]" + name + "=([^&#]*)")
  const match = src.match(pattern)
  if (match === null) {
    return null
  }
  return match[1]
}

function youtubePlayer(src) {
  let videoId = null
  const address = parsed(src)
  const short = address !== null && /(^|\.)youtube\.com$/i.test(address.hostname)
    ? address.pathname.match(/^\/shorts\/([A-Za-z0-9_-]{11})\/?$/)
    : null
  if (short !== null) {
    videoId = short[1]
  } else {
    const match = src.match(ytLinkRegex)
    if (match !== null && match[2].length === 11) {
      videoId = match[2]
    }
  }
  const playlistMatch = src.match(ytPlaylistLinkRegex)
  const playlistId = playlistMatch !== null ? playlistMatch[1] : undefined
  if (videoId === null && playlistId === undefined) {
    return null
  }
  const asked = []
  if (playlistId !== undefined) {
    asked.push("list=" + playlistId)
  }
  if (videoId !== null) {
    let start = secondsOf(partNamed(src, "t"))
    if (start === null) {
      start = secondsOf(partNamed(src, "start"))
    }
    if (start !== null && start > 0) {
      asked.push("start=" + start)
    }
  }
  const path = videoId !== null ? videoId : "videoseries"
  const query = asked.length > 0 ? "?" + asked.join("&") : ""
  return { host: "youtube", src: YOUTUBE_PLAYER + path + query }
}

function vimeoPlayer(address) {
  const host = address.hostname.toLowerCase()
  const parts = []
  for (const part of address.pathname.split("/")) {
    if (part !== "") {
      parts.push(part)
    }
  }
  let id = null
  let hash = null
  if (host === "player.vimeo.com") {
    if (parts.length === 2 && parts[0] === "video" && /^\d+$/.test(parts[1])) {
      id = parts[1]
    }
  } else if (parts.length >= 1 && /^\d+$/.test(parts[0]) && parts.length <= 2) {
    id = parts[0]
    if (parts.length === 2) {
      hash = parts[1]
    }
  } else if (parts.length === 3 && parts[0] === "channels" && /^\d+$/.test(parts[2])) {
    id = parts[2]
  } else if (parts.length === 4 && parts[0] === "groups" && parts[2] === "videos" && /^\d+$/.test(parts[3])) {
    id = parts[3]
  }
  if (id === null) {
    return { host: "vimeo", notAVideo: true }
  }
  if (hash === null) {
    const asked = address.searchParams.get("h")
    if (asked !== null && asked !== "") {
      hash = asked
    }
  }
  if (hash !== null && !/^[A-Za-z0-9]+$/.test(hash)) {
    return { host: "vimeo", notAVideo: true }
  }
  let player = VIMEO_PLAYER + id + "?"
  if (hash !== null) {
    player += "h=" + hash + "&"
  }
  player += "dnt=1"
  let start = partNamed(address.hash, "t")
  if (start === null) {
    start = address.searchParams.get("t")
  }
  const seconds = secondsOf(start)
  if (seconds !== null && seconds > 0) {
    player += "#t=" + seconds + "s"
  }
  return { host: "vimeo", src: player }
}

export function playerFor(src) {
  if (typeof src !== "string" || src === "") {
    return null
  }
  const address = parsed(src)
  if (address !== null && (address.protocol === "https:" || address.protocol === "http:")) {
    const host = address.hostname.toLowerCase()
    if (host === "vimeo.com" || host === "www.vimeo.com" || host === "player.vimeo.com") {
      return vimeoPlayer(address)
    }
  }
  return youtubePlayer(src)
}

// The words in the brackets, without an Obsidian width (`Title|400`,
// `Title|400x300`), or the host's fallback title when they are empty.
export function titleFor(alt, host) {
  let words = typeof alt === "string" ? alt : ""
  words = words.replace(/\|\s*\d+(x\d+)?\s*$/, "").trim()
  if (words === "") {
    return FALLBACK_TITLES[host]
  }
  return words
}

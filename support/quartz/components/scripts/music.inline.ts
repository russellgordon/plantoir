// Tunes played in the reader's browser (#679): every `<figure class=
// "pl-figure pl-music" data-music=...>` the site's transformer placed
// (plugins/transformers/plantoirMusic.ts) plays its tune when a student
// presses Play, from the class site's OWN copy of abcjs and of the sounds
// (static/abcjs/, which the build puts in a site only when a page has a tune
// with Play), never from another site.
//
// On every page of every site, so it does nothing at all until a press: no
// file is fetched and nothing watches the page.
//
// * The first press loads abcjs (about 150 KB as a browser downloads it),
//   draws the tune again in the same place with the build's own options so
//   the notes it lights are the ones on the page, and then plays it, each
//   note lit as it sounds. While the sounds load, the status line says so,
//   once, in a polite live region. The button then reads Stop.
// * The drawing is made with getBBox answering no size, as the build's
//   document has none (musicFences.drawing): abcjs then estimates text
//   widths exactly as it did when the site was built, and the picture does
//   not move on the press (measured identical in Chromium and WebKit).
// * Quartz's page change stops whatever is playing, and frees it.
// * Printing: the controls never print (music.scss); the drawing does.

type MusicSpec = {
  abc: string
  options: Record<string, unknown>
  engine: string
  sounds: string
  play: string
  stop: string
  playLabel: string
  stopLabel: string
  gettingReady: string
  couldNotPlay: string
}

type Playing = {
  synth: { stop: () => void }
  timing: { stop: () => void }
  figure: HTMLElement
}

let musicEngine: Promise<boolean> | null = null
let musicPlaying: Playing | null = null
let musicPageChanges = 0
// The sound set's files are quiet; abcjs plays them at three times their
// level from its own address for that reason, and does the same here.
const MUSIC_VOLUME = 3.0

function musicAbcjs(): any {
  return (window as unknown as { ABCJS?: unknown }).ABCJS ?? null
}

function loadMusicEngine(url: string): Promise<boolean> {
  if (musicAbcjs() !== null) {
    return Promise.resolve(true)
  }
  if (musicEngine !== null) {
    return musicEngine
  }
  musicEngine = new Promise((resolve) => {
    const script = document.createElement("script")
    script.src = new URL(url, window.location.href).href
    script.setAttribute("spa-preserve", "")
    script.addEventListener("load", () => resolve(musicAbcjs() !== null), { once: true })
    script.addEventListener(
      "error",
      () => {
        musicEngine = null
        script.remove()
        resolve(false)
      },
      { once: true },
    )
    document.head.appendChild(script)
  })
  return musicEngine
}

function musicSay(figure: HTMLElement, words: string) {
  const status = figure.querySelector<HTMLElement>(".pl-music-status")
  if (status !== null) {
    status.textContent = words
  }
}

function musicButton(figure: HTMLElement, spec: MusicSpec, playing: boolean) {
  const button = figure.querySelector<HTMLButtonElement>(".pl-music-play")
  if (button === null) {
    return
  }
  button.textContent = playing ? spec.stop : spec.play
  button.setAttribute("aria-label", playing ? spec.stopLabel : spec.playLabel)
  button.disabled = false
}

function musicUnlight(figure: HTMLElement) {
  for (const lit of Array.from(figure.querySelectorAll(".pl-music-now"))) {
    lit.classList.remove("pl-music-now")
  }
}

function stopMusic() {
  const playing = musicPlaying
  musicPlaying = null
  if (playing === null) {
    return
  }
  try {
    playing.timing.stop()
  } catch {}
  try {
    playing.synth.stop()
  } catch {}
  musicUnlight(playing.figure)
  playing.figure.dataset.musicState = "stopped"
  try {
    const spec = JSON.parse(playing.figure.dataset.music ?? "") as MusicSpec
    musicButton(playing.figure, spec, false)
  } catch {}
}

// Draws the tune again where the build drew it, with getBBox answering no
// size for the length of the call (musicFences.drawing).
function redraw(ABCJS: any, holder: HTMLElement, spec: MusicSpec): any {
  const proto = SVGGraphicsElement.prototype as unknown as { getBBox: () => unknown }
  const measured = proto.getBBox
  proto.getBBox = function () {
    return { x: 0, y: 0, width: NaN, height: NaN }
  }
  try {
    return ABCJS.renderAbc(holder, spec.abc, spec.options)[0]
  } finally {
    proto.getBBox = measured
  }
}

async function playTune(figure: HTMLElement) {
  if (figure.dataset.musicState === "playing") {
    stopMusic()
    return
  }
  if (figure.dataset.musicState === "loading") {
    return
  }
  let spec: MusicSpec
  try {
    spec = JSON.parse(figure.dataset.music ?? "") as MusicSpec
  } catch {
    return
  }
  stopMusic()
  const page = musicPageChanges
  const button = figure.querySelector<HTMLButtonElement>(".pl-music-play")
  const holder = figure.querySelector<HTMLElement>(":scope > .pl-music-drawing")
  if (button === null || holder === null) {
    return
  }
  figure.dataset.musicState = "loading"
  button.disabled = true
  musicSay(figure, spec.gettingReady)
  // The sound must be started from the press itself on Safari: the audio
  // context is made here, before anything is awaited.
  const Context = (window.AudioContext ??
    (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext) as
    | typeof AudioContext
    | undefined
  let context: AudioContext | null = null
  try {
    context = Context ? new Context() : null
    void context?.resume()
  } catch {
    context = null
  }
  const failed = () => {
    if (page !== musicPageChanges || !figure.isConnected) {
      return
    }
    figure.dataset.musicState = "failed"
    musicButton(figure, spec, false)
    musicSay(figure, spec.couldNotPlay)
  }
  if (context === null || !(await loadMusicEngine(spec.engine))) {
    failed()
    return
  }
  if (page !== musicPageChanges || !figure.isConnected) {
    return
  }
  const ABCJS = musicAbcjs()
  try {
    ABCJS.synth.registerAudioContext(context)
    const tune = redraw(ABCJS, holder, spec)
    const synth = new ABCJS.synth.CreateSynth()
    await synth.init({
      audioContext: context,
      visualObj: tune,
      options: { soundFontUrl: new URL(spec.sounds, window.location.href).href, soundFontVolumeMultiplier: MUSIC_VOLUME },
    })
    await synth.prime()
    if (page !== musicPageChanges || !figure.isConnected) {
      synth.stop()
      return
    }
    const timing = new ABCJS.TimingCallbacks(tune, {
      eventCallback: (event: { elements?: Element[][] } | null) => {
        musicUnlight(figure)
        if (event === null || event === undefined) {
          if (musicPlaying !== null && musicPlaying.figure === figure) {
            stopMusic()
          }
          return "continue"
        }
        for (const group of event.elements ?? []) {
          for (const lit of group) {
            lit.classList.add("pl-music-now")
          }
        }
        return "continue"
      },
    })
    musicPlaying = { synth, timing, figure }
    figure.dataset.musicState = "playing"
    musicButton(figure, spec, true)
    musicSay(figure, "")
    synth.start()
    timing.start()
  } catch {
    failed()
  }
}

document.addEventListener("nav", () => {
  const figures = Array.from(document.querySelectorAll<HTMLElement>("figure.pl-music[data-music]"))
  if (figures.length === 0) {
    return
  }
  for (const figure of figures) {
    const button = figure.querySelector<HTMLButtonElement>(".pl-music-play")
    if (button === null) {
      continue
    }
    const pressed = () => {
      void playTune(figure)
    }
    button.addEventListener("click", pressed)
    window.addCleanup(() => button.removeEventListener("click", pressed))
  }
  window.addCleanup(() => {
    musicPageChanges += 1
    stopMusic()
  })
})

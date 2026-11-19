// YouTube and Vimeo videos written as a picture (#692): the site's half.
//
// A teacher writes the address the video site's Share button gives in the
// picture form, on its own line (`![Mitosis in three minutes](https://vimeo.com/76979871)`),
// and the page shows the video's player. The rules (which addresses, which
// player address, which title) are in videoRules.js, shared with
// scripts/check_video_rules_against_the_site.py; every case is in
// contracts/shared-rules.json -> videoEmbeds.
//
// Html stage, wired straight BEFORE ObsidianFlavoredMarkdown
// (build_site._wire_video_transformer). Quartz runs every transformer's html
// plugins in the order the transformers are listed, and OFM's own YouTube
// step REPLACES the picture's properties, so after it the words in the
// brackets are gone. Running first, this turns both hosts' pictures into
// players itself, and OFM's YouTube step then finds no picture to change.
//
// Every player carries the class `plantoir-video`, which videos.scss sizes
// (600 px wide at most, 16:9; Russell, 2026-10-24), and `external-embed
// youtube` / `external-embed vimeo` beside it, so anything that already
// reads Quartz's class for a YouTube player still finds one.
//
// A vimeo.com address that is not one video (a showcase, a profile) stays
// the picture it always was, and the build prints a `plantoir: note:` line
// naming the page and line (videoEmbeds.notes.notAVideo). It reaches the
// build's console only, not the Problems tab (#692 review, S4: accepted;
// the page itself shows the broken picture, which is what a teacher sees
// in a preview).
//
// Rejected (#692 plan 3.2): running after OFM and patching its player (the
// title is already gone); turning OFM's enableYouTubeEmbed off (an edit to
// every section's settings that buys nothing over leaving it to find
// nothing); a per-video width (the size is ruled); Vimeo's title, byline and
// portrait switches (the video's owner sets them); a tap before the player
// loads (offered on #692 and not chosen).

import { Element, Root as HtmlRoot } from "hast"
import { visit } from "unist-util-visit"
import type { QuartzTransformerPlugin } from "../types"
// @ts-ignore - plain JavaScript, shared with the site's check
import { playerFor, titleFor, notAVideoNote, PLAYER_ATTRIBUTES } from "./videoRules.js"

export const PlantoirVideo: QuartzTransformerPlugin = () => ({
  name: "PlantoirVideo",
  htmlPlugins() {
    return [
      () => (tree: HtmlRoot, file) => {
        const page = String(file.data.relativePath ?? String(file.data.slug ?? "") + ".md")
        visit(tree, "element", (node: Element) => {
          if (node.tagName !== "img" || typeof node.properties?.src !== "string") {
            return
          }
          const src = node.properties.src as string
          const player = playerFor(src)
          if (player === null) {
            return
          }
          if (player.notAVideo === true) {
            const line = node.position?.start.line ?? 0
            console.log("plantoir: note: " + notAVideoNote(page, line, src))
            return
          }
          const alt = typeof node.properties.alt === "string" ? (node.properties.alt as string) : ""
          node.tagName = "iframe"
          node.children = []
          node.properties = {
            className: ["external-embed", "plantoir-video", player.host],
            src: player.src,
            title: titleFor(alt, player.host),
            loading: PLAYER_ATTRIBUTES.loading,
            allow: PLAYER_ATTRIBUTES.allow,
            allowFullScreen: PLAYER_ATTRIBUTES.allowfullscreen,
            referrerPolicy: PLAYER_ATTRIBUTES.referrerpolicy,
            frameBorder: PLAYER_ATTRIBUTES.frameborder,
          }
        })
      },
    ]
  },
})

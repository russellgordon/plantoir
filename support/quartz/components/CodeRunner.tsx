// Runnable code (#455): the component that carries the page's script and
// styles. It renders NOTHING - placed in the layout's afterBody
// (build_site.wire_quartz_additions), it only puts codeRunner.inline.ts into
// the site's one postscript.js and codeRunner.scss into its one index.css, so
// no page's HTML changes because of it (afterBody's page-footer is rendered
// on every page whatever it holds). The script does nothing on a page with
// no runnable block, and every style is scoped under .plantoir-runner.

import { QuartzComponent, QuartzComponentConstructor } from "./types"
import style from "./styles/codeRunner.scss"
// @ts-ignore
import script from "./scripts/codeRunner.inline"

export default (() => {
  const CodeRunner: QuartzComponent = () => <></>
  CodeRunner.afterDOMLoaded = script
  CodeRunner.css = style
  return CodeRunner
}) satisfies QuartzComponentConstructor

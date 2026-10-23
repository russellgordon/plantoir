#!/bin/bash
# The Print button in REAL Safari, driven by AppleScript (#576). A
# measurement record, not a gate: it takes over a Safari window, and needs
# Safari's Develop > "Allow JavaScript from Apple Events" and Accessibility
# access for the terminal (System Events reads and cancels the print sheet).
# safaridriver cannot do this: under automation print() returns in 0 ms with
# no event and no sheet (measured, Safari 26.6) - see FINDINGS.md.
#
#   safari_print.sh <site base URL> <direct|fromhome> [page path]
#
# Serve a built site with serve.mjs (its `nopaged` argument answers the print
# layout's script with a 404, forcing the fallback; a delay holds pictures).
# Environment: KEEP=1 stops the page removing the print frame (the run that
# showed WebKit's postponed print arriving), PREP=<js> runs before the press,
# LATE=<s> how long to look for a late sheet once the frame is gone, WIN=<id>
# reuses a Safari window, SHEETACT=<name> runs <name>.applescript on the
# sheet instead of cancel.applescript (only cancel is kept here). Prints the
# result line and the event log.
SITE=$1; HOW=$2; PAGE=${3:-Concepts/Variables-and-Data-Types}
S=$(dirname "$0")
if [ "$HOW" = direct ]; then FIRST="$SITE/$PAGE"; else FIRST="$SITE/"; fi
if [ -n "$WIN" ]; then W=$WIN; osascript -e "tell application \"Safari\" to set URL of current tab of window id $W to \"$FIRST\""; else W=$(osascript -e "tell application \"Safari\"" -e "make new document with properties {URL:\"$FIRST\"}" -e "return id of front window" -e "end tell"); fi
echo "window $W" >&2
sleep 4
[ -z "$WIN" ] && trap 'osascript -e "tell application \"Safari\" to close window id $W" >/dev/null 2>&1' EXIT
js() { osascript -e 'on run argv' -e 'with timeout of 6 seconds' -e 'tell application "Safari" to return do JavaScript (item 1 of argv) in current tab of window id '"$W" -e 'end timeout' -e 'end run' "$1" 2>&1; }
if [ "$HOW" = direct ]; then
  for i in $(seq 1 40); do sleep 0.5; r=$(js 'document.readyState + (document.querySelector(".plantoir-print button[data-mode]")?" btn":"")'); [ "$r" = "complete btn" ] && break; done
else
  for i in $(seq 1 40); do sleep 0.5; r=$(js 'document.readyState'); [ "$r" = complete ] && break; done
  sleep 1.5
  js "window.spaNavigate(new URL('$SITE/$PAGE')); 1" >/dev/null
  for i in $(seq 1 40); do sleep 0.5; r=$(js '(document.querySelector(".plantoir-print button[data-mode]")?"btn":"no")'); [ "$r" = btn ] && break; done
fi
sleep 1.5
[ -n "$PREP" ] && echo "prep: $(js "$PREP")"; [ -n "$KEEP" ] && js "window.__keepFrame=true; 1" >/dev/null; js "document.title='PROBE576 '+document.title; 1" >/dev/null
echo "instrument: $(js "$(cat $S/instrument.js)")"
echo "page: $(js 'location.pathname + " pre=" + document.querySelectorAll(".center pre").length + " imgs=" + document.querySelectorAll(".center article img").length')"
js 'window.__p.log("press"); window.__p.t0 = performance.now(); const b=[...document.querySelectorAll(".plantoir-print button[data-mode]")].find(x=>x.offsetWidth>0) || document.querySelector(".plantoir-print button[data-mode]"); setTimeout(()=>b.click(),0); b.textContent'; T0=$(perl -MTime::HiRes=time -e 'printf q(%d),time*1000')
result=""
for i in $(seq 1 60); do
  sleep 0.5
  sh=$(osascript -e 'tell application "System Events" to tell process "Safari" to count of sheets of (first window whose name contains "PROBE576")' 2>/dev/null)
  if [ "$sh" = 1 ]; then echo "sheet-detected-shell $(($(perl -MTime::HiRes=time -e "printf q(%d),time*1000")-T0))ms"; sleep 1; result="SHEET at poll $i: $(osascript $S/${SHEETACT:-cancel}.applescript PROBE576 $SHEETARGS) at $(($(perl -MTime::HiRes=time -e "printf q(%d),time*1000")-T0))ms"; sleep ${AFTER:-3}; break; fi
  ev=$(js 'JSON.stringify(window.__p.ev)')
  case "$ev" in *frame-removed*|*frame-remove-suppressed*) sleep ${LATE:-2}; sh=$(osascript -e 'tell application "System Events" to tell process "Safari" to count of sheets of (first window whose name contains "PROBE576")' 2>/dev/null); [ "$sh" = 1 ] && { echo "late-sheet-detected-shell $(($(perl -MTime::HiRes=time -e "printf q(%d),time*1000")-T0))ms"; result="LATE SHEET: $(osascript $S/${SHEETACT:-cancel}.applescript PROBE576 $SHEETARGS) at $(($(perl -MTime::HiRes=time -e "printf q(%d),time*1000")-T0))ms"; sleep ${AFTER:-3}; } || result="NO SHEET after frame-removed"; break;; esac
done
sleep 1
echo "result: ${result:-timeout}"
echo "events: $(js 'JSON.stringify(window.__p.ev) + " errors=" + JSON.stringify(window.__p.errors)')"

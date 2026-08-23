# native-control-metrics/ — what a real AppKit control actually measures

**Conditions.** macOS 26.6 (Darwin 25.6.0), Apple silicon, 2x display scale,
Xcode 26.6 toolchain, `NSComboBox` and `NSTextField` at the **regular** control
size with the system 13pt UI font, rendered offscreen at 260pt wide in both
`.aqua` and `.darkAqua`. Measured 2026-08-23. Re-run rather than re-trust if
the OS major version changes — these are Apple's artwork, not a spec.

## Why this exists

`CourseCodePickerView` in the macOS app is a SwiftUI imitation of an
`NSComboBox` (a real one was tried and reverted twice — its popup can only
show plain strings, which loses the "example content" badge). An imitation is
only as good as its numbers, and for a day those numbers were matched against
screenshots of our own app, which is how the field ended up 30pt tall beside a
native 24pt one.

`measure-combo-box.swift` renders the real control to an `NSBitmapImageRep`
and prints the cell's own rects; the findings below come from reading those
PNGs back pixel by pixel. Run it with `xcrun swift measure-combo-box.swift`.

## Findings

| What | Value | How it was established |
|---|---|---|
| Field height | **24pt** | `fittingSize`. A `.roundedBezel` `NSTextField` reports the same 24. |
| Field corner radius | **6pt** | Circle fit to the antialiased corner: leading inset per row 8,6,4,3,2,2,1,1,0 device px; a 12px radius predicts every row to within one pixel. `NSComboBox` and `NSTextField` render byte-identical corners. |
| Text container inset | 4pt | `NSComboBoxCell.titleRect(forBounds:)` → `(4, 4, 222, 16)` on a 260×24 box. `NSTextFieldCell.drawingRect` agrees. |
| Text GLYPH origin | **~5.7pt** | Not the same as the container. "B" of "Banana" starts 7.0pt from the field's outer edge; "C" of "Chemistry" in a rounded `NSTextField` starts 6.5pt; subtracting each letter's left side bearing at 13pt gives ~5.7 either way. The difference is the text system's own line-fragment padding. |
| Text trailing reserve | 34pt | `titleRect` width 222 of 260 — the button's 24 plus its 4pt inset plus a 6pt gap. |
| Chevron button | **24 × 19pt** | Fill bounds x 464–511, y 4–41 in 2x device px on a 520×48 render. |
| Button trailing inset | **4pt** | Same bounds against the field's outer edge. |
| Button corner radius | **5pt** | Circle fit: inset per row 8,5,3,2,2,1,1,1,0 → 10px. |
| Button fill (dark) | (41,41,41) — `tertiarySystemFill` | Composited over the field background. `secondarySystemFill` lands at 48. |
| Button fill (light) | (235,235,235) — `secondarySystemFill` | `tertiarySystemFill` lands at 243. |
| Chevron glyph | **7.5 × 4.5pt** | `chevron.down` rendered across sizes 8–13 at four weights, tight bounds measured: 8.5pt semibold is the match. |
| Chevron colour | label colour | (222,222,222) dark, (36,36,36) light. **Not tinted.** |

## Two measurements about SwiftUI's own approximations

These are not AppKit's numbers — they are what SwiftUI renders — and they are
here because matching the native control and matching our own sibling field
turn out NOT to be quite the same target.

- **`.textFieldStyle(.roundedBorder)` renders 26pt tall**, where a real
  `NSTextField` with `.roundedBezel` reports 24pt from `fittingSize`.
  Measured off a screenshot of two wizard rows together: 52 vs 48 device
  pixels at 2x. **`.frame(height: 24)` does not correct it** — SwiftUI draws
  that bezel at its own intrinsic height regardless of the frame it is
  given, so the field still measured 26 and merely overflowed its box
  (tried 2026-08-23). Getting 24 means drawing the bezel yourself; the
  wizard's three fields now share a `WizardFieldChrome` modifier built to
  the figures in the table above.
- **A `.plain` `TextField`'s glyphs ride low inside its own intrinsic box**,
  so giving it `.frame(height:)` centres the BOX and still leaves the text
  low in the field. Measured with the capital "I" that both fields' contents
  happened to start with, which needs no font metrics: Course Name put 17
  device px above the cap and 16 below the baseline, while the course-code
  field put 18 above and 11 below — 3.5px (1.75pt) low. 3pt of BOTTOM padding
  inside the fixed-height frame corrects it (padding P moves centred content
  up by P/2), and re-measuring gives 15 above / 14 below against Course
  Name's 17/16 — the same half-pixel convention.

## The two things worth remembering

**The button is not tinted.** A real combo box's chevron sits on a barely
lighter grey than the field. An accent-coloured pill is the single loudest tell
that a control is imitated.

**No one semantic colour matches both appearances**, because AppKit draws the
button with control artwork rather than from a named fill. Two different tokens
are needed, resolved per appearance.

## Known difference we did NOT chase

A native combo box's interior renders (23,23,23) in dark; ours renders
(30,30,30) from `textBackgroundColor`. No semantic colour is (23,23,23) —
AppKit shades its own bezel — and hard-coding it would break light mode (where
`textBackgroundColor` matches the native white exactly) and would be a guess
against the next macOS.

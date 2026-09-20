import AppKit

// Render a real NSComboBox offscreen and report its own metrics, so our
// SwiftUI imitation can be matched to numbers rather than to a guess.

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

func report(appearanceName: NSAppearance.Name, label: String) {
    let appearance = NSAppearance(named: appearanceName)!

    let combo = NSComboBox(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
    combo.appearance = appearance
    combo.addItems(withObjectValues: ["Banana", "Cherry", "Date"])
    combo.stringValue = "Banana"
    combo.isEditable = true

    let fitting = combo.fittingSize
    combo.frame = NSRect(x: 0, y: 0, width: 260, height: fitting.height)
    combo.layoutSubtreeIfNeeded()

    print("=== \(label) ===")
    print("fittingSize: \(fitting)")
    print("frame: \(combo.frame)")
    print("controlSize: \(combo.controlSize.rawValue)  font: \(String(describing: combo.font))")

    if let cell = combo.cell as? NSComboBoxCell {
        let bounds = combo.bounds
        print("cell.drawingRect(forBounds:): \(cell.drawingRect(forBounds: bounds))")
        print("cell.titleRect(forBounds:):   \(cell.titleRect(forBounds: bounds))")
    }

    // Render at 2x so we can measure the bezel corner and the button
    // region in device pixels, the same units a screenshot gives us.
    let scale: CGFloat = 2
    let pixelsWide = Int(combo.bounds.width * scale)
    let pixelsHigh = Int(combo.bounds.height * scale)
    guard let rep = combo.bitmapImageRepForCachingDisplay(in: combo.bounds) else { return }
    rep.size = combo.bounds.size
    combo.cacheDisplay(in: combo.bounds, to: rep)

    print("bitmap px: \(rep.pixelsWide) x \(rep.pixelsHigh) (expected ~\(pixelsWide)x\(pixelsHigh))")

    let data = rep.representation(using: .png, properties: [:])!
    let out = "/private/tmp/claude-501/-Users-russellgordon-plantoir/e02f41ef-4bfe-4519-af1c-bdb605a405ca/scratchpad/combo/combo-\(label).png"
    try! data.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
    print("")
}

report(appearanceName: .darkAqua, label: "dark")
report(appearanceName: .aqua, label: "light")

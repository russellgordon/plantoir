import AppKit
import SwiftUI

/// One emoji, chosen any way the teacher likes: picked from the wizard's
/// presets, typed straight into the field, or taken from the macOS emoji
/// palette — the smiley button summons it, and whatever is chosen there
/// lands in the field. The field always holds exactly one emoji: the most
/// recently entered one wins, and anything that is not an emoji is ignored.
struct EmojiChoiceField: View {

    // MARK: - Stored properties

    let label: String

    @Binding var emoji: String

    /// The field's live text, which may briefly hold "📚🔬" (the palette
    /// inserts beside what is there) before settling back to one emoji.
    @State var entry: String = ""

    @FocusState var fieldHasFocus: Bool

    // MARK: - Body

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                Menu {
                    ForEach(EmojiCatalog.presets, id: \.self) { presetEmoji in
                        Button(presetEmoji) {
                            emoji = presetEmoji
                            entry = presetEmoji
                        }
                    }
                } label: {
                    Text("Presets")
                }
                .fixedSize()

                TextField("", text: $entry)
                    .borderedTextField()
                    .frame(width: 44)
                    .multilineTextAlignment(.center)
                    .focused($fieldHasFocus)
                    .accessibilityIdentifier("emojiChoiceField")
                    .onChange(of: entry) {
                        acceptLatestEmoji()
                    }

                Button {
                    // The palette types into whichever field has focus, so
                    // focus ours before summoning it — and empty it first,
                    // so the choice arrives into a clean field rather than
                    // beside the old emoji.
                    entry = ""
                    fieldHasFocus = true
                    // On the next turn of the main actor, once the focus
                    // change above has reached the field — a hop, not a
                    // guessed delay.
                    Task { @MainActor in
                        NSApp.orderFrontCharacterPalette(nil)
                    }
                } label: {
                    Image(systemName: "face.smiling")
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Choose any emoji")
                .accessibilityIdentifier("emojiPaletteButton")
            }
        }
        .onAppear {
            entry = emoji
        }
        .onChange(of: emoji) {
            if entry != emoji {
                entry = emoji
            }
        }
        .onChange(of: fieldHasFocus) {
            // A field left empty (palette dismissed without choosing, or a
            // deleted entry) goes back to showing the current choice.
            if !fieldHasFocus && entry.isEmpty {
                entry = emoji
            }
        }
    }

    // MARK: - Functions

    /// Settles the field on one emoji the moment anything changes, so it
    /// never shows more than one. An emptied field is left empty while the
    /// teacher decides; anything that is not an emoji snaps back to the
    /// current choice.
    func acceptLatestEmoji() {
        if entry.isEmpty {
            return
        }
        if let newest = EmojiChoiceField.newestEmoji(in: entry, previous: emoji) {
            if entry != newest {
                entry = newest
            }
            if emoji != newest {
                emoji = newest
            }
        } else {
            entry = emoji
        }
    }

    /// The emoji the teacher just entered. When the text holds several —
    /// an insertion can land on either side of what was there — the one
    /// that DIFFERS from the previous choice is the new one; if they all
    /// match it, any of them will do. Nil when there is no emoji at all.
    static func newestEmoji(in text: String, previous: String) -> String? {
        var lastSeen: String?
        for character in text {
            if EmojiChoiceField.isEmoji(character) {
                let candidate: String = String(character)
                lastSeen = candidate
                if candidate != previous {
                    return candidate
                }
            }
        }
        return lastSeen
    }

    /// Whether one character (one grapheme cluster) reads as an emoji.
    /// Letters and digits report `isEmoji` in Unicode, so a lone scalar
    /// must also insist on emoji *presentation*; multi-scalar clusters
    /// (skin tones, ZWJ sequences like 🧑‍🚀, flags, keycaps) are trusted by
    /// their first scalar.
    static func isEmoji(_ character: Character) -> Bool {
        let scalars: [Unicode.Scalar] = Array(character.unicodeScalars)
        guard let firstScalar = scalars.first else {
            return false
        }
        if scalars.count > 1 {
            return firstScalar.properties.isEmoji
        }
        return firstScalar.properties.isEmojiPresentation && firstScalar.value > 0x238C
    }
}

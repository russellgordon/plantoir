import AppKit
import SwiftUI

/// Which assistant runs on this Mac, and what it is costing in space.
///
/// Two jobs, and they are separate on purpose. The top half is a CHOICE — one
/// of three, remembered, with the cost of each stated before it is made. The
/// bottom half is HOUSEKEEPING — what is actually on the disk, and a way to
/// get the space back. A teacher who wants their 2.5 GB back has not
/// necessarily changed their mind about which assistant they want, and being
/// made to do the second by doing the first would be a trap.
struct AssistantSettingsView: View {

    // MARK: - Stored properties

    /// What is on this Mac and what may be done about it.
    @State private var library: AssistModelLibrary = AssistModelLibrary()

    /// The download the teacher pressed Remove beside, while the question
    /// about it is asked (#987, D22).
    @State private var removing: AssistModelTier?

    // MARK: - Computed properties

    var body: some View {
        Form {
            if library.budget.canRunAssistant {
                confirmationSection
                choiceSection
                housekeepingSection
            } else {
                Section {
                    Text("The assistant needs an Apple silicon Mac. "
                         + "Everything else in Plantoir works as usual.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 560)
        .onAppear {
            library.refresh()
            ActivityTrail.note(
                .settingsPanelOpened,
                "opened Settings — the assistant is set to \(library.choice.label.lowercased())"
            )
        }
        // macOS HIDES a settings window rather than closing it, so this view
        // and its `@State` outlive every visit. Everything it says about what
        // is downloaded is read from the file system, which nothing can
        // observe — so without looking again each time the window comes
        // forward, a panel opened in the morning describes the morning's disk
        // for the rest of the day. Found by restoring a file underneath a
        // panel that went on insisting it was not there.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            library.refresh()
        }
        // #987, D22. Drawn like the app's other removal alerts: Cancel
        // answers Escape, and Remove is destructive so that it takes no
        // Return (in a SwiftUI alert only that role keeps Return off it,
        // `AlertKeysTests`); whether those alerts keep their red waits on
        // the question sheet's redesign (#1000).
        .alert(
            AssistModelLibrary.removeQuestion(for: removing ?? .small),
            isPresented: Binding(
                get: { return removing != nil },
                set: { (showing: Bool) in
                    if !showing {
                        removing = nil
                    }
                }
            ),
            presenting: removing
        ) { (tier: AssistModelTier) in
            Button("Cancel", role: .cancel) {
                removing = nil
            }
            .keyboardShortcut(.cancelAction)
            Button(AssistModelLibrary.removeButton, role: .destructive) {
                removing = nil
                library.remove(tier)
            }
            .accessibilityIdentifier("assistantRemoveConfirm")
        } message: { (tier: AssistModelTier) in
            Text(AssistModelLibrary.removeMessage(for: tier))
        }
    }

    // MARK: - Asking before it changes anything

    /// The gate, as a switch rather than as something the assistant offers
    /// once and then never mentions again.
    ///
    /// **On by default, and the default is the point.** The local model is a
    /// router and routers are wrong sometimes; showing what it understood
    /// before it acts turns a misroute from a thing that HAPPENS into a thing
    /// a teacher declines. Turning it off is an invitation, offered because a
    /// gate in front of every action teaches people to click through gates —
    /// somebody who has pressed Go on forty correct plans is not reading the
    /// forty-first, and at that point the gate costs attention without buying
    /// safety.
    ///
    /// It is available on BOTH assistants. Which one is running changes the
    /// odds, not whose decision it is, so the smaller one gets a caution with
    /// its measured number in it rather than a disabled switch.
    private var confirmationSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { library.asksBeforeChanging },
                set: { asks in library.asksBeforeChanging = asks }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ask me before changing anything")
                    Text("The assistant says what it is about to do, and waits, before it "
                         + "publishes or hides pages. Deploying always asks, whatever this "
                         + "is set to.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityIdentifier("assistantAsksBeforeChanging")

            if let caution = library.confirmationCaution {
                Label(caution, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("assistantConfirmationCaution")
            }
        } header: {
            Text("Before it changes your pages")
        }
    }

    // MARK: - The choice

    private var choiceSection: some View {
        Section {
            ForEach(AssistModelChoice.allCases, id: \.rawValue) { choice in
                choiceRow(for: choice)
            }
        } header: {
            Text("Which assistant runs on this Mac")
        } footer: {
            Text(library.whatHappensNext)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("assistantWhatHappensNext")
        }
    }

    /// One option: a radio button, a label, the sentence under it, and the
    /// caution when there is one.
    ///
    /// Built by hand rather than with `Picker(.radioGroup)` because each
    /// option carries two or three lines of explanation, and a picker gives
    /// every option a single line of title. The explanation is the part that
    /// makes this a choice rather than a guess, so it is the picker that had
    /// to go.
    private func choiceRow(for choice: AssistModelChoice) -> some View {
        let isChosen: Bool = library.choice == choice
        return Button {
            library.choice = choice
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isChosen ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isChosen ? Color.accentColor : Color.secondary)
                    .font(.system(size: 15))
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(choice.label)
                        .fontWeight(isChosen ? .semibold : .regular)

                    Text(choice.detail(for: library.budget))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let caution = choice.caution(for: library.budget) {
                        Label(caution, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("assistantChoiceCaution" + identifier(for: choice))
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("assistantChoice" + identifier(for: choice))
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : [.isButton])
    }

    // MARK: - Housekeeping

    private var housekeepingSection: some View {
        Section {
            ForEach(library.tiers, id: \.rawValue) { tier in
                downloadRow(for: tier)
            }
        } header: {
            Text("On this Mac")
        } footer: {
            Text(spaceSummary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("assistantSpaceSummary")
        }
    }

    /// One rung's presence on disk, and the button that changes it.
    private func downloadRow(for tier: AssistModelTier) -> some View {
        let store: AssistModelStore = library.store(for: tier)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tier.choiceLabel)
                    Text(status(for: tier))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("assistantStatus" + identifier(for: tier))
                }
                Spacer(minLength: 12)

                if case .downloading = store.state {
                    Button("Stop") {
                        store.cancel()
                    }
                    .accessibilityIdentifier("assistantStopDownload" + identifier(for: tier))
                } else if library.isDownloaded(tier) {
                    // Asks first (#987, D22): a download of gigabytes is not
                    // taken back by a click. "Remove…" because it opens a
                    // question (Buttons ▸ macOS: "Append a trailing ellipsis
                    // to the title when a push button opens another window,
                    // view, or app").
                    Button("Remove…") {
                        removing = tier
                    }
                    .disabled(!library.mayRemove(tier))
                    .accessibilityIdentifier("assistantRemove" + identifier(for: tier))
                } else {
                    Button("Download") {
                        library.download(tier)
                    }
                    .accessibilityIdentifier("assistantDownload" + identifier(for: tier))
                }
            }

            if case .downloading(let fraction, let received, let total) = store.state {
                ProgressView(value: fraction)
                Text("\(AssistantSettingsView.describe(received)) of \(AssistantSettingsView.describe(total))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if case .failed(let reason) = store.state {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let reason = library.reasonItCannotBeRemoved(tier) {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("assistantRemovalBlocked" + identifier(for: tier))
            }
        }
        .padding(.vertical, 2)
    }

    /// What this rung's line says about itself.
    private func status(for tier: AssistModelTier) -> String {
        if let space = library.spaceDescription(for: tier), library.isDownloaded(tier) {
            return "Downloaded · \(space) on this Mac"
        }
        if library.spaceDescription(for: tier) != nil {
            return "A part-finished download · downloading again replaces it"
        }
        return "Not downloaded · \(tier.downloadDescription)"
    }

    /// The line under the housekeeping list.
    private var spaceSummary: String {
        guard let bytes = library.bytesOnDisk else {
            return "Nothing is downloaded yet, so the assistant is taking no space."
        }
        return "The assistant is using \(AssistantSettingsView.describe(bytes)) on this Mac. "
             + "Removing one frees its space; opening the assistant offers to download "
             + "whichever one you have chosen."
    }

    // MARK: - Functions

    private static func describe(_ bytes: Int64) -> String {
        let formatter: ByteCountFormatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// A stable suffix for an accessibility identifier, so a test can press
    /// exactly the row it means.
    private func identifier(for choice: AssistModelChoice) -> String {
        return choice.rawValue.prefix(1).uppercased() + choice.rawValue.dropFirst()
    }

    private func identifier(for tier: AssistModelTier) -> String {
        return tier.rawValue.prefix(1).uppercased() + tier.rawValue.dropFirst()
    }
}

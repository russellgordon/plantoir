import SwiftUI

/// The status of every configured destination in a multi-destination
/// deploy, shown above that run's own progress view. Only appears once a
/// course has more than one destination — a course with exactly one (the
/// overwhelming majority) never shows this at all, and the progress panel
/// beneath it looks exactly as it always has.
struct DeployDestinationChecklist: View {

    // MARK: - Stored properties

    let legs: [MultiDestinationDeployRunner.Leg]

    // MARK: - Body

    var body: some View {
        HStack(spacing: 16) {
            ForEach(legs) { leg in
                HStack(spacing: 4) {
                    Image(systemName: DeployDestinationChecklist.symbolName(for: leg))
                        .foregroundStyle(DeployDestinationChecklist.tint(for: leg))
                        // The state in words as well as colour (#993, D19):
                        // VoiceOver reads "Netlify, Done" rather than a
                        // symbol's name.
                        .accessibilityLabel(Text(DeployDestinationChecklist.stateName(
                            isFinished: leg.isFinished,
                            succeeded: leg.succeeded,
                            isRunning: leg.runner.isRunning
                        )))
                    Text(DeployCommand.destinationDescription(for: leg.destination))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("deployDestinationStatus-\(leg.destination.type)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    // MARK: - Functions

    static func symbolName(for leg: MultiDestinationDeployRunner.Leg) -> String {
        if leg.isFinished {
            return leg.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill"
        }
        return leg.runner.isRunning ? "arrow.triangle.2.circlepath.circle.fill" : "circle"
    }

    /// What a destination's symbol means, in a word, for VoiceOver (#993,
    /// D19). The same four states `symbolName(for:)` draws.
    static func stateName(isFinished: Bool, succeeded: Bool, isRunning: Bool) -> String {
        if isFinished {
            if succeeded {
                return AccessibilityNames.destinationDone
            }
            return AccessibilityNames.destinationFailed
        }
        if isRunning {
            return AccessibilityNames.destinationDeploying
        }
        return AccessibilityNames.destinationWaiting
    }

    static func tint(for leg: MultiDestinationDeployRunner.Leg) -> Color {
        if leg.isFinished {
            return leg.succeeded ? .green : .red
        }
        return leg.runner.isRunning ? .blue : .secondary
    }
}

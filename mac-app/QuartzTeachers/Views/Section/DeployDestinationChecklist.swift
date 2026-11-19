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
                    Text(DeployCommand.destinationDescription(for: leg.destination))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("deployDestinationStatus-\(leg.destination.type)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    // MARK: - Functions

    static func symbolName(for leg: MultiDestinationDeployRunner.Leg) -> String {
        if leg.isFinished {
            // A failed leg stopped: the stop symbol, one per meaning (#994).
            return leg.succeeded ? "checkmark.circle.fill" : StatusColour.blocking.filledSymbolName
        }
        return leg.runner.isRunning ? "arrow.triangle.2.circlepath.circle.fill" : "circle"
    }

    static func tint(for leg: MultiDestinationDeployRunner.Leg) -> AnyShapeStyle {
        if leg.isFinished {
            if leg.succeeded {
                return AnyShapeStyle(Color.green)
            }
            // A failed leg is the stopping red (#994).
            return AnyShapeStyle(StatusColour.blocking.style)
        }
        if leg.runner.isRunning {
            return AnyShapeStyle(Color.blue)
        }
        return AnyShapeStyle(Color.secondary)
    }
}

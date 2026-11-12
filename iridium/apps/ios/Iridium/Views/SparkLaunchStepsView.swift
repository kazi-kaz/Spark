import SwiftUI

/// A compact progress strip for a starting game: one segment per launch step.
struct SparkLaunchStepsView: View {
    let active: SparkLaunchStep

    private func tone(_ step: SparkLaunchStep) -> Color {
        if step.rawValue < active.rawValue { return SparkTheme.good }
        return step == active ? SparkTheme.accent : Color.white.opacity(0.25)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(SparkLaunchStep.allCases, id: \.rawValue) { step in
                    Capsule().fill(tone(step)).frame(height: 5)
                }
            }
            .frame(maxWidth: 260)
            Text("Step \(active.rawValue + 1) of \(SparkLaunchStep.allCases.count) · \(active.title)")
                .font(.caption).foregroundStyle(Color.white.opacity(0.8))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(active.rawValue + 1) of \(SparkLaunchStep.allCases.count): \(active.title)")
        .accessibilityIdentifier("playerLaunchSteps")
    }
}

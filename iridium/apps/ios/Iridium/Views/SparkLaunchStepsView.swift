import SwiftUI

/// Launch progress for a starting game: a checklist when there is room, and a
/// four-segment strip when the screen is short (a phone held sideways).
struct SparkLaunchStepsView: View {
    let active: SparkLaunchStep
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private func tone(_ step: SparkLaunchStep) -> Color {
        if step.rawValue < active.rawValue { return SparkTheme.good }
        return step == active ? SparkTheme.accent : Color.white.opacity(0.3)
    }

    private func symbol(_ step: SparkLaunchStep) -> String {
        if step.rawValue < active.rawValue { return "checkmark.circle.fill" }
        return step == active ? "arrow.right.circle.fill" : "circle"
    }

    private var summary: String {
        "Step \(active.rawValue + 1) of \(SparkLaunchStep.allCases.count): \(active.title)"
    }

    var body: some View {
        Group {
            if verticalSizeClass == .compact { strip } else { checklist }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
        .accessibilityIdentifier("playerLaunchSteps")
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(SparkLaunchStep.allCases, id: \.rawValue) { step in
                HStack(spacing: 12) {
                    Image(systemName: symbol(step)).font(.body.weight(.semibold))
                        .foregroundStyle(tone(step)).frame(width: 24)
                    Text(step.title).font(.callout.weight(step == active ? .bold : .medium))
                        .foregroundStyle(step.rawValue > active.rawValue ? Color.white.opacity(0.5)
                                         : step == active ? SparkTheme.accent : Color.white)
                }
            }
        }
    }

    private var strip: some View {
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
    }
}

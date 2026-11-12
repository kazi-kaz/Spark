import SwiftUI

/// A rounded surface that groups related rows, with an optional heading above it.
struct SparkCard<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.65)).padding(.leading, 6)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.horizontal, 16).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SparkTheme.surface, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

/// One row inside a card: icon tile, title, optional value and chevron.
struct SparkRow: View {
    let title: String
    let systemImage: String
    var value: String? = nil
    var chevron = true
    var tone: Color = SparkTheme.accent
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).font(.subheadline.weight(.semibold)).foregroundStyle(tone)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            Text(title).font(.body.weight(.medium)).foregroundStyle(Color.white)
            Spacer(minLength: 8)
            if let value {
                Text(value).font(.subheadline).foregroundStyle(Color.white.opacity(0.6)).lineLimit(1)
            }
            if chevron {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.35)).accessibilityHidden(true)
            }
        }
        .frame(minHeight: 50)
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.45)
    }
}

/// Hairline between rows of a card, inset to line up with the row titles.
struct SparkDivider: View {
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 44)
            .accessibilityHidden(true)
    }
}

/// A game's artwork, or a tinted tile with its initials when it has none.
struct SparkGameArt: View {
    let image: UIImage?
    let title: String
    var position = 0.5

    private var hue: Double {
        Double(title.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 360 }) / 360
    }

    private var initials: String {
        let words = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.count >= 2 {
            return (String(words[0].prefix(1)) + String(words[1].prefix(1))).uppercased()
        }
        return String(title.prefix(2))
    }

    var body: some View {
        if let image {
            ArtworkImage(image: image, title: "", position: position)
        } else {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [Color(hue: hue, saturation: 0.45, brightness: 0.52),
                                        Color(hue: hue, saturation: 0.55, brightness: 0.16)],
                               startPoint: .topTrailing, endPoint: .bottomLeading)
                Text(initials).font(.system(size: 44, weight: .heavy))
                    .foregroundStyle(Color.white.opacity(0.8)).padding(12)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Capsule buttons: amber for the main action, a raised surface for the rest.
struct SparkPillButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, prominent: prominent)
    }

    private struct Pill: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(prominent && isEnabled ? SparkTheme.onAccent : Color.white.opacity(isEnabled ? 1 : 0.5))
                .background(prominent && isEnabled ? SparkTheme.accent : SparkTheme.raised, in: Capsule())
                .opacity(configuration.isPressed ? 0.75 : 1)
        }
    }
}

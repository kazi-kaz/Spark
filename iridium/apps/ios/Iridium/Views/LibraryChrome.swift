import SwiftUI

private struct LibraryGlass: ViewModifier {
    let prominent: Bool
    /// Spark's accent (#FFB627). Written out because a check compiles this file on its own.
    private let accent = Color(red: 1.0, green: 0.714, blue: 0.153)
    @Environment(\.isEnabled) private var isEnabled
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if prominent && isEnabled { content.buttonStyle(.glassProminent).tint(accent).foregroundStyle(.black) }
            else { content.buttonStyle(.glass) }
        } else {
            if prominent && isEnabled { content.buttonStyle(.borderedProminent).tint(accent).foregroundStyle(.black) }
            else { content.buttonStyle(.bordered) }
        }
    }
}
extension View {
    func libraryGlass(prominent: Bool = false) -> some View { modifier(LibraryGlass(prominent: prominent)) }
}

/// Shared backdrop for native settings, editors, activity and game details.
struct IridiumPageSurface: ViewModifier {
    @ObservedObject var artwork: LibraryArtwork
    var gameID: UUID?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background {
                ZStack {
                    Color.black
                    if !reduceTransparency, let id = gameID ?? artwork.backdropGameID,
                       let image = artwork.displayImage(artwork.appearance(id).background) {
                        ArtworkImage(image: image, title: "", position: artwork.appearance(id).backgroundY)
                            .blur(radius: 14).overlay(.black.opacity(0.62))
                    }
                }.ignoresSafeArea()
            }
            // Leave native controls on their semantic tint. White is only a local
            // Play button fill, paired with black text, never a page-wide accent.
            .preferredColorScheme(.dark)
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}
extension View {
    @MainActor func iridiumPageSurface(artwork: LibraryArtwork? = nil, gameID: UUID? = nil) -> some View {
        modifier(IridiumPageSurface(artwork: artwork ?? .shared, gameID: gameID))
    }
    @MainActor func iridiumListChrome(onBack: (() -> Void)? = nil) -> some View {
        listStyle(.insetGrouped)
            .environment(\.defaultMinListRowHeight, 54)
            .iridiumPageSurface()
            .controllerMenuScope(onBack: onBack)
    }
}

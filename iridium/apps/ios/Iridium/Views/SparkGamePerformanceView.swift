#if MADEIRA_RUNTIME
import IridiumCore
import SwiftUI

/// Per-game performance settings, saved to the game's own config file.
struct SparkGamePerformanceView: View {
    let game: GameRecord
    /// nil means the game follows the app-wide JIT Memory Limit.
    @State private var pool: Int?
    @State private var saveError: String?

    private var root: URL { URL(fileURLWithPath: game.installPath) }

    var body: some View {
        List {
            Section("JIT Memory for This Game") {
                ForEach([0, 128, 256, 512, 1024], id: \.self) { mb in
                    MenuButton { choose(mb == 0 ? nil : mb) } label: {
                        HStack {
                            Text(mb == 0 ? "Use App Setting" : "\(mb) MB")
                            Spacer()
                            if (pool ?? 0) == mb {
                                Image(systemName: "checkmark").foregroundStyle(SparkTheme.accent)
                            }
                        }
                    }
                }
                Text("Applies to this game's next launch and is saved to its iridium.cfg. Large Unreal games usually need 512 MB.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let saveError {
                    Text(saveError).font(.footnote).foregroundStyle(SparkTheme.problem)
                }
            }
        }
        .iridiumListChrome().navigationTitle("Performance")
        .onAppear { pool = MadeiraGameConfig.jitPoolMB(in: MadeiraGameConfig.locate(gameRoot: root)) }
    }

    private func choose(_ mb: Int?) {
        do {
            try MadeiraGameConfig.setJITPoolMB(mb, gameRoot: root)
            pool = mb
            saveError = nil
        } catch {
            saveError = "The setting could not be saved: \(error.localizedDescription)"
        }
    }
}
#endif

#if MADEIRA_RUNTIME
import IridiumCore
import SwiftUI

/// Per-game performance settings, saved to the game's own config file.
struct SparkGamePerformanceView: View {
    let game: GameRecord
    /// nil means the game follows the app-wide JIT Memory Limit.
    @State private var pool: Int?
    @State private var saveError: String?
    @State private var looksLikeUnreal = false

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
                if looksLikeUnreal && (pool ?? 0) < 512 {
                    Text("This looks like an Unreal Engine game. 512 MB usually works best.")
                        .font(.footnote).foregroundStyle(SparkTheme.accent)
                }
                if let saveError {
                    Text(saveError).font(.footnote).foregroundStyle(SparkTheme.problem)
                }
            }
            Section("Advanced") {
                MenuNavigationLink {
                    SparkConfigEditorView(title: "iridium.cfg",
                                          file: MadeiraGameConfig.locate(gameRoot: root) ?? root.appendingPathComponent(MadeiraGameConfig.fileName))
                } label: {
                    Label("Edit This Game's Config", systemImage: "doc.plaintext")
                }
                Text("Every setting and env. line for this game only. It overrides madeira.cfg.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .iridiumListChrome().navigationTitle("Performance")
        .onAppear {
            pool = MadeiraGameConfig.jitPoolMB(in: MadeiraGameConfig.locate(gameRoot: root))
            looksLikeUnreal = Self.isUnreal(root)
        }
    }

    /// Unreal games ship an Engine folder or a "-Win64-Shipping.exe" program.
    private static func isUnreal(_ root: URL) -> Bool {
        let files = FileManager.default
        var isFolder: ObjCBool = false
        if files.fileExists(atPath: root.appendingPathComponent("Engine").path, isDirectory: &isFolder),
           isFolder.boolValue { return true }
        guard let walker = files.enumerator(at: root, includingPropertiesForKeys: nil,
                                            options: [.skipsHiddenFiles]) else { return false }
        var seen = 0
        for case let url as URL in walker {
            seen += 1
            if seen > 4000 { break }
            if walker.level > 4 { walker.skipDescendants(); continue }
            if url.lastPathComponent.hasSuffix("-Win64-Shipping.exe") { return true }
        }
        return false
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

/// The game's JIT memory choice as a segmented control, for the game page.
struct SparkJITMemoryControl: View {
    let game: GameRecord
    /// 0 means the game follows the app-wide JIT Memory Limit.
    @State private var pool = 0
    @State private var failed = false

    private static let choices = [0, 128, 256, 512, 1024]
    private var root: URL { URL(fileURLWithPath: game.installPath) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("JIT memory").font(.body.weight(.medium)).foregroundStyle(Color.white)
            Picker("JIT memory", selection: Binding(get: { pool }, set: { choose($0) })) {
                ForEach(Self.choices, id: \.self) { mb in
                    Text(mb == 0 ? "Auto" : "\(mb)").tag(mb)
                }
            }
            .pickerStyle(.segmented)
            .menuFocusable(adjust: { step in
                let index = Self.choices.firstIndex(of: pool) ?? 0
                choose(Self.choices[min(Self.choices.count - 1, max(0, index + step))])
            })
            if failed {
                Text("The setting could not be saved.").font(.footnote).foregroundStyle(SparkTheme.problem)
            }
        }
        .padding(.vertical, 10)
        .onAppear { pool = MadeiraGameConfig.jitPoolMB(in: MadeiraGameConfig.locate(gameRoot: root)) ?? 0 }
    }

    private func choose(_ mb: Int) {
        do {
            try MadeiraGameConfig.setJITPoolMB(mb == 0 ? nil : mb, gameRoot: root)
            pool = mb
            failed = false
        } catch {
            failed = true
        }
    }
}
#endif

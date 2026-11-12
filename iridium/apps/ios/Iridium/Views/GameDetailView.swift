import IridiumCore
import IridiumRuntime
import SwiftUI
import UniformTypeIdentifiers

struct GameDetailView: View {
    let game: GameRecord
    @ObservedObject var viewModel: AppViewModel
    var locate: () -> Void = {}
    let launch: () -> Void
    @ObservedObject private var artwork = LibraryArtwork.shared
    @ObservedObject private var statuses = SparkGameStatusStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var facts: SparkGameFacts?
    @State private var rename = false
    @State private var confirmRemoval = false
    @State private var confirmRefresh = false
    @State private var installerPicker = false
    @State private var installerURL: URL?
    @State private var confirmInstaller = false
    @State private var installerError: String?
    @Environment(\.menuController) private var controller

    @ViewBuilder private var playRow: some View {
        HStack(spacing: 10) {
            MenuButton {
                dismiss()
                launch()
            } label: {
                Label(viewModel.launchActionTitle(for: game), systemImage: "play.fill")
                    .font(.title3.weight(.heavy)).frame(maxWidth: .infinity).frame(height: 58)
            }
            .buttonStyle(SparkPillButtonStyle(prominent: true))
            .disabled(viewModel.isLaunchActionDisabled(for: game))
            .accessibilityIdentifier("gameOptionsPlay")
            MenuButton {
                do { try artwork.update(game.id) { $0.favorite.toggle() } } catch { artwork.error = error.localizedDescription }
            } label: {
                Image(systemName: artwork.appearance(game.id).favorite ? "heart.fill" : "heart")
                    .font(.title3.weight(.semibold)).frame(width: 58, height: 58)
            }
            .buttonStyle(SparkPillButtonStyle())
            .accessibilityLabel(artwork.appearance(game.id).favorite ? "Remove from Favorites" : "Add to Favorites")
        }
    }

    @ViewBuilder private var beforeYouPlay: some View {
        if viewModel.isLaunchActionDisabled(for: game) && !viewModel.preparingInstaller {
            SparkCard(title: "Before You Play") {
                Text(viewModel.launchActionDetail(for: game) ?? "Check the game files and runtime settings.")
                    .font(.callout).padding(.vertical, 10)
                if viewModel.jitStatus != .ready {
                    SparkDivider()
                    MenuButton { viewModel.enableJITWithRecommendedTool() } label: {
                        SparkRow(title: "Enable JIT", systemImage: "bolt.fill", chevron: false)
                    }
                }
                if !FileManager.default.fileExists(atPath: game.launchProfile.executablePath) {
                    SparkDivider()
                    MenuButton { locate() } label: {
                        SparkRow(title: "Locate Game Folder", systemImage: "folder.badge.questionmark", chevron: false)
                    }
                    Text("Choose the folder containing this game and its executable. Spark copies it to a new location and keeps your existing saves.")
                        .font(.footnote).foregroundStyle(Color.white.opacity(0.6)).padding(.bottom, 8)
                }
                SparkDivider()
                MenuButton { viewModel.verifyGameRegistration(game) } label: {
                    SparkRow(title: "Check Game Files", systemImage: "checkmark.shield", chevron: false)
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var gameCard: some View {
        SparkCard(title: "For This Game") {
            #if MADEIRA_RUNTIME
            if viewModel.usesMadeiraRuntime {
                SparkJITMemoryControl(game: game)
                SparkDivider()
            }
            #endif
            MenuNavigationLink { GameInputSettingsView(game: game) } label: { SparkRow(title: "Controls", systemImage: "gamecontroller") }
                .accessibilityIdentifier("gameControlsLink")
            SparkDivider()
            MenuNavigationLink { GameStorageView(game: game, viewModel: viewModel, usesMadeiraRuntime: viewModel.usesMadeiraRuntime) } label: {
                SparkRow(title: "Files & Saves", systemImage: "folder")
            }
            #if MADEIRA_RUNTIME
            if viewModel.usesMadeiraRuntime {
                SparkDivider()
                MenuNavigationLink { SparkGamePerformanceView(game: game) } label: {
                    SparkRow(title: "Performance & Config", systemImage: "bolt")
                }
            }
            #endif
            if let target = SteamCloudTarget(game: game) {
                SparkDivider()
                MenuNavigationLink { SteamCloudView(target: target, viewModel: viewModel) } label: {
                    SparkRow(title: "Steam Cloud", systemImage: "icloud")
                }
            }
            SparkDivider()
            MenuButton { rename = true } label: {
                SparkRow(title: "Rename & Artwork", systemImage: "photo", chevron: false)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var maintenance: some View {
        if viewModel.usesMadeiraRuntime {
            SparkCard(title: "Maintenance") {
                MenuButton { installerPicker = true } label: {
                    SparkRow(title: "Run Installer", systemImage: "gearshape", chevron: false)
                }
                .disabled(viewModel.isLaunchActionDisabled(for: game))
                if viewModel.preparingInstaller { ProgressView("Copying installer…").padding(.vertical, 8) }
                SparkDivider()
                MenuButton { confirmRefresh = true } label: {
                    SparkRow(title: "Refresh Game Copy", systemImage: "arrow.clockwise", chevron: false)
                }
                .disabled(viewModel.refreshingGameCopy || viewModel.isLaunchActionDisabled(for: game))
            }
            .buttonStyle(.plain)
            Text("Run Installer starts a Windows installer in this game's environment; the game starts after setup. Refresh Game Copy rebuilds the isolated copy from the imported files and keeps the current copy as a backup. Restart Spark before refreshing after a game session.")
                .font(.footnote).foregroundStyle(Color.white.opacity(0.55)).padding(.horizontal, 6)
        }
    }

    @ViewBuilder private var advancedCard: some View {
        SparkCard {
            MenuNavigationLink {
                List {
                    Section("Launch") {
                        MenuValue("Executable", value: game.launchProfile.executablePath)
                        MenuNavigationLink("Custom Arguments") { GameArgumentsEditor(game: game, viewModel: viewModel) }
                            .disabled(!viewModel.canEditGameArguments(game.id))
                        MenuNavigationLink("Launch Checks") { GameCompatibilityView(game: game, viewModel: viewModel) }
                    }
                    Section {
                        MenuNavigationLink("Runtime Settings") { SettingsView(viewModel: viewModel) }
                        if !viewModel.usesMadeiraRuntime { MenuNavigationLink("Windows Environment") { GameEnvironmentView(game: game, viewModel: viewModel) } }
                    }
                }.iridiumListChrome().navigationTitle("Advanced")
            } label: {
                SparkRow(title: "Advanced", systemImage: "wrench.and.screwdriver")
            }
            SparkDivider()
            MenuButton(role: .destructive) { confirmRemoval = true } label: {
                SparkRow(title: "Remove from Library", systemImage: "trash", chevron: false, tone: SparkTheme.problem)
            }
            .disabled(viewModel.preparingInstaller || viewModel.activeRuntimePlayerSession?.gameID == game.id)
        }
        .buttonStyle(.plain)
    }

    /// The game's artwork with its title, facts and last-run status over it.
    private var hero: some View {
        let appearance = artwork.appearance(game.id)
        return ZStack(alignment: .bottomLeading) {
            SparkGameArt(image: artwork.displayImage(appearance.background) ?? artwork.displayImage(appearance.cover),
                         title: artwork.title(game),
                         position: appearance.background != nil ? appearance.backgroundY : appearance.coverY)
            LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.9)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                SparkStatusChip(status: statuses.status(for: game.id))
                Text(artwork.title(game)).font(.system(size: 34, weight: .heavy)).lineLimit(2).minimumScaleFactor(0.6)
                if let facts {
                    Text(facts.summary).font(.caption.monospaced()).foregroundStyle(Color.white.opacity(0.75)).lineLimit(2)
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity).frame(height: 270)
        .clipShape(RoundedRectangle(cornerRadius: 30))
        .overlay { RoundedRectangle(cornerRadius: 30).strokeBorder(Color.white.opacity(0.10), lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                playRow
                if let reason = statuses.status(for: game.id).detail {
                    SparkCard(title: "Last Run") {
                        Text(reason).font(.callout).foregroundStyle(SparkTheme.problem).padding(.vertical, 10)
                    }
                }
                if let facts, !facts.notes.isEmpty {
                    SparkCard(title: "Good to Know") {
                        ForEach(facts.notes, id: \.self) { note in
                            Text(note).font(.callout).foregroundStyle(Color.white.opacity(0.85)).padding(.vertical, 8)
                        }
                    }
                }
                beforeYouPlay
                gameCard
                maintenance
                advancedCard
                Text("Removing only deletes this library entry. Game files, artwork, and saves stay on your device.")
                    .font(.footnote).foregroundStyle(Color.white.opacity(0.55)).padding(.horizontal, 6)
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(SparkTheme.ground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .controllerMenuScope()
        .navigationTitle("Game Options").navigationBarTitleDisplayMode(.inline)
        .task(id: game.id) {
            // Reading the program's headers touches the disk, so do it off the main thread.
            let path = game.launchProfile.executablePath
            facts = await Task.detached(priority: .utility) { SparkGameFacts.read(executablePath: path) }.value
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            ZStack {
                Text("Game Options").font(.headline)
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left").font(.title3.weight(.semibold))
                            .frame(width: 32, height: 32)
                    }
                    .libraryGlass().buttonBorderShape(.circle)
                    .accessibilityLabel("Back")
                    Spacer()
                }
            }.padding(.horizontal, 16).padding(.vertical, 8)
        }
        .confirmationDialog("Refresh the isolated game copy?", isPresented: $confirmRefresh, titleVisibility: .visible) {
            Button("Refresh and Keep Backup") { viewModel.refreshMadeiraGameCopy(game) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Conflicting files, including any saves stored in the game folder, will be replaced by the imported versions. The complete previous copy is kept in Documents/MadeiraTestPrefixes/<game ID>/game-backup-<ID>. Windows profile saves are not replaced. Updating first copies the entire game and needs extra storage.")
        }
        .sheet(isPresented: $rename) { LibraryAppearanceEditor(game: game, artwork: artwork) }
        .fileImporter(isPresented: $installerPicker, allowedContentTypes: [
            UTType(filenameExtension: "exe") ?? .data, UTType(filenameExtension: "msi") ?? .data
        ]) { result in
            do { installerURL = try result.get(); confirmInstaller = true }
            catch let error as CocoaError where error.code == .userCancelled { installerURL = nil }
            catch { installerError = error.localizedDescription }
        }
        .confirmationDialog("Run installer for \(artwork.title(game))?", isPresented: $confirmInstaller, titleVisibility: .visible) {
            Button("Run Installer") {
                guard let source = installerURL else { return }
                installerURL = nil
                Task {
                    do {
                        try await viewModel.prepareInstaller(source, for: game)
                        dismiss()
                        launch()
                    } catch { installerError = error.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) { installerURL = nil }
        } message: {
            Text("\(installerURL?.lastPathComponent ?? "The installer") will run in this game's Windows environment. Complete setup to start the game.")
        }
        .alert("Could Not Run Installer", isPresented: Binding(
            get: { installerError != nil }, set: { if !$0 { installerError = nil } }
        )) {
            Button("OK", role: .cancel) { installerError = nil }
        } message: { Text(installerError ?? "") }
        .onChange(of: installerPicker || confirmInstaller || installerError != nil) { _, presented in
            controller?.nativeMenuActive = presented
        }
        .onChange(of: viewModel.games.map(\.id)) { _, ids in
            if !ids.contains(game.id) { dismiss() }
        }
        .sheet(isPresented: $confirmRemoval) {
            NavigationStack {
                List {
                    Section {
                        Text("Game files and saves will not be deleted.")
                        MenuButton("Cancel", role: .cancel) { confirmRemoval = false }
                        MenuButton("Remove", role: .destructive) {
                            viewModel.removeLibraryEntry(game); confirmRemoval = false; dismiss()
                        }
                    }
                }.iridiumListChrome().navigationTitle("Remove from Library?")
                    .navigationBarTitleDisplayMode(.inline)
            }.presentationDetents([.medium])
        }

    }
}

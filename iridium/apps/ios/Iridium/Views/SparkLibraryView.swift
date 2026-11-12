import SwiftUI
import IridiumCore

/// Spark's library: the selected game on a large card, then every game in a
/// grid, with a floating bar for the app's other areas.
struct SparkLibraryView: View {
    let games: [GameRecord]
    @ObservedObject var artwork: LibraryArtwork
    @ObservedObject var controller: LibraryController
    let play: (GameRecord) -> Void
    let disabled: (GameRecord) -> Bool
    let launchTitle: (GameRecord) -> String
    var launchDetail: (GameRecord) -> String? = { _ in nil }
    let details: (GameRecord) -> Void
    @Binding var search: String
    @Binding var favorites: Bool
    @Binding var selectedID: UUID?
    var importGame: () -> Void = {}
    var settings: () -> Void = {}
    var showDownloads: () -> Void = {}
    var showLogs: () -> Void = {}
    var acceptsControllerInput = true
    @ObservedObject var statuses = SparkGameStatusStore.shared

    /// Remembers the last selected game so the top card survives a restart.
    @AppStorage("SparkLastSelectedGame") private var lastSelected = ""
    @State private var stoppedOnly = false
    @State private var visible = false
    @State private var searchPresented = false
    @FocusState private var searching: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Where controller input currently lands, top to bottom on screen.
    private enum Zone { case hero, filter, grid, bar }
    @State private var zone: Zone = .grid
    @State private var heroAction = 0
    @State private var barIndex = 0
    @State private var columns = 2

    private static let filterTitles = ["All Games", "Favorites", "Stopped"]

    private var filtered: [GameRecord] {
        games.filter {
            (!favorites || artwork.appearance($0.id).favorite)
                && (!stoppedOnly || statuses.status(for: $0.id).detail != nil)
                && (search.isEmpty || artwork.title($0).localizedCaseInsensitiveContains(search))
        }
    }
    private var selected: GameRecord? { filtered.first { $0.id == selectedID } ?? filtered.first }
    /// 0 = All Games, 1 = Favorites, 2 = Stopped.
    private var filterIndex: Int { stoppedOnly ? 2 : favorites ? 1 : 0 }
    private func setFilter(_ index: Int) {
        let bounded = min(2, max(0, index))
        favorites = bounded == 1
        stoppedOnly = bounded == 2
    }

    var body: some View {
        GeometryReader { geometry in
            let count = max(2, Int((geometry.size.width - 20) / 182))
            ZStack(alignment: .bottom) {
                SparkTheme.ground.ignoresSafeArea()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            header.id("sparkLibraryTop")
                            if searchPresented { searchField }
                            if let selected, !searchPresented { hero(selected) }
                            filterBar
                            if filtered.isEmpty { emptyState } else { grid(count: count) }
                        }
                        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 120)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: selectedID) { _, id in
                        guard controller.showingControllerHints, zone == .grid, let id else { return }
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
                    }
                    .onChange(of: zone) { _, zone in
                        guard zone == .hero || zone == .filter else { return }
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { proxy.scrollTo("sparkLibraryTop", anchor: .top) }
                    }
                }
                tabBar.padding(.horizontal, 16).padding(.bottom, 6)
            }
            .onChange(of: count, initial: true) { _, value in columns = value }
        }
        .preferredColorScheme(.dark)
        .simultaneousGesture(TapGesture().onEnded {
            if controller.showingControllerHints { controller.showingControllerHints = false }
        })
        .onChange(of: searchPresented) { _, open in
            controller.backAction = open ? { closeSearch() } : nil
        }
        .onDisappear { visible = false; controller.libraryNavigationActive = false; controller.backAction = nil }
        .onChange(of: acceptsControllerInput) { _, accepts in controller.libraryNavigationActive = visible && accepts }
        .onReceive(controller.input) { action in
            guard visible && acceptsControllerInput else { return }
            handleController(action)
        }
        .onKeyPress(.escape) {
            guard searchPresented else { return .ignored }
            closeSearch()
            return .handled
        }
        .onAppear {
            visible = true
            controller.libraryNavigationActive = acceptsControllerInput
            if selectedID == nil, let id = UUID(uuidString: lastSelected), games.contains(where: { $0.id == id }) {
                selectedID = id
            }
            artwork.backdropGameID = selected?.id
        }
        .onChange(of: selected?.id) { _, id in
            artwork.backdropGameID = id
            if let id { lastSelected = id.uuidString }
        }
    }

    // MARK: Header and search

    private var header: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    SparkMark(size: 15)
                    Text("SPARK").font(.caption.weight(.heavy)).tracking(2.4).foregroundStyle(SparkTheme.accent)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Spark")
                Text("Library").font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 8)
            circleButton("magnifyingglass", label: "Search") {
                if searchPresented { closeSearch() } else { searchPresented = true; searching = true }
            }
            circleButton("plus", label: "Add Game", action: importGame)
                .keyboardShortcut("o", modifiers: .command)
        }
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(SparkTheme.raised, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.white.opacity(0.6)).accessibilityHidden(true)
            TextField("Search games", text: $search, prompt: Text("Search games").foregroundStyle(Color.white.opacity(0.6)))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($searching).submitLabel(.search)
                .onSubmit { searching = false }
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 16).padding(.trailing, 4).frame(height: 50)
        .background(SparkTheme.surface, in: Capsule())
    }

    private func closeSearch() {
        search = ""
        searching = false
        searchPresented = false
    }

    // MARK: Selected game

    private func hero(_ game: GameRecord) -> some View {
        let appearance = artwork.appearance(game.id)
        let status = statuses.status(for: game.id)
        return ZStack(alignment: .bottomLeading) {
            SparkGameArt(image: artwork.displayImage(appearance.background) ?? artwork.displayImage(appearance.cover),
                         title: artwork.title(game),
                         position: appearance.background != nil ? appearance.backgroundY : appearance.coverY)
                .background { RuntimeLaunchSource(gameID: game.id, role: .backdrop) }
            LinearGradient(colors: [Color.black.opacity(0.05), Color.black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 10) {
                SparkStatusChip(status: status)
                Text(artwork.title(game)).font(.title.bold()).lineLimit(1).truncationMode(.tail)
                    .background { RuntimeLaunchSource(gameID: game.id, role: .title) }
                    .accessibilityIdentifier("libraryGameTitle")
                HStack(spacing: 10) {
                    Button {
                        searching = false
                        play(game)
                    } label: {
                        Label(launchTitle(game), systemImage: "play.fill").font(.headline).lineLimit(1)
                            .padding(.horizontal, 24).frame(height: 50)
                    }
                    .buttonStyle(SparkPillButtonStyle(prominent: true))
                    .disabled(disabled(game))
                    .overlay { focusRing(zone == .hero && heroAction == 0) }
                    Button { details(game) } label: {
                        Label("Options", systemImage: "slider.horizontal.3").font(.headline)
                            .padding(.horizontal, 18).frame(height: 50)
                    }
                    .buttonStyle(SparkPillButtonStyle())
                    .overlay { focusRing(zone == .hero && heroAction == 1) }
                    .accessibilityIdentifier("gameOptions")
                }
                if let reason = launchDetail(game) ?? status.detail {
                    Text(reason).font(.footnote).foregroundStyle(Color.white.opacity(0.8)).lineLimit(2)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity).frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(Color.white.opacity(0.10), lineWidth: 1).allowsHitTesting(false) }
    }

    // MARK: Filter and grid

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Button { setFilter(index) } label: {
                        Text(Self.filterTitles[index]).font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 18).frame(height: 44)
                            .foregroundStyle(filterIndex == index ? SparkTheme.ground : Color.white.opacity(0.85))
                            .background(filterIndex == index ? Color.white : SparkTheme.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .overlay { focusRing(zone == .filter && filterIndex == index) }
                    .accessibilityAddTraits(filterIndex == index ? [.isSelected] : [])
                }
            }
            .padding(.vertical, 6).padding(.horizontal, 6)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -6)
        .accessibilityIdentifier("libraryFilter")
    }

    private func grid(count: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: count), spacing: 18) {
            ForEach(filtered, id: \.id) { game in tile(game) }
        }
        .accessibilityIdentifier("gameGrid")
    }

    private func tile(_ game: GameRecord) -> some View {
        let appearance = artwork.appearance(game.id)
        let isSelected = game.id == selected?.id
        let focused = controller.showingControllerHints && zone == .grid && isSelected
        return Button {
            closeSearch()
            selectedID = game.id
            zone = .grid
            details(game)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                SparkGameArt(image: artwork.displayImage(appearance.cover), title: artwork.title(game), position: appearance.coverY)
                    .aspectRatio(0.75, contentMode: .fit)
                    .background { if isSelected { RuntimeLaunchSource(gameID: game.id, role: .cover) } }
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(alignment: .topLeading) { SparkStatusChip(status: statuses.status(for: game.id)).padding(10) }
                    .overlay {
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(focused ? SparkTheme.accent : Color.white.opacity(0.08), lineWidth: focused ? 3 : 1)
                    }
                Text(artwork.title(game)).font(.subheadline.weight(.bold)).lineLimit(1).truncationMode(.tail)
                    .padding(.horizontal, 4)
            }
        }
        .buttonStyle(.plain)
        .id(game.id)
        .accessibilityLabel(artwork.title(game))
        .accessibilityValue(statuses.status(for: game.id).title)
        .accessibilityHint("Opens the game's page.")
    }

    @ViewBuilder private var emptyState: some View {
        Group {
            if !search.isEmpty {
                ContentUnavailableView.search(text: search)
            } else if stoppedOnly {
                ContentUnavailableView("Nothing Stopped", systemImage: "checkmark.circle",
                    description: Text("Games whose last run stopped appear here."))
            } else if favorites {
                ContentUnavailableView("No Favorites Yet", systemImage: "heart",
                    description: Text("Add favorites from a game's page."))
            } else {
                ContentUnavailableView("Add Your First Game", systemImage: "gamecontroller",
                    description: Text("Use Add Game (+) to download from your Steam library or import a Windows game folder. Artwork is optional."))
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 32)
    }

    // MARK: Floating bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            barItem(0, "Library", "square.grid.2x2.fill", current: true) {}
            barItem(1, "Steam", "arrow.down.circle", action: showDownloads)
            barItem(2, "Logs", "list.bullet.rectangle", action: showLogs)
            barItem(3, "Settings", "slider.horizontal.3", action: settings)
        }
        .padding(7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1).allowsHitTesting(false) }
        .shadow(color: Color.black.opacity(0.5), radius: 20, y: 10)
        .frame(maxWidth: 440)
    }

    private func barItem(_ index: Int, _ title: String, _ symbol: String, current: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 19, weight: .semibold))
                Text(title).font(.caption2.weight(current ? .bold : .semibold))
            }
            .frame(maxWidth: .infinity).frame(height: 52)
            .foregroundStyle(current ? SparkTheme.accent : Color.white.opacity(0.85))
            .background(current ? Color.white.opacity(0.10) : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .overlay { focusRing(zone == .bar && barIndex == index) }
        .accessibilityAddTraits(current ? [.isSelected] : [])
    }

    private func focusRing(_ on: Bool) -> some View {
        Capsule().strokeBorder(SparkTheme.accent, lineWidth: 2).padding(-4)
            .opacity(controller.showingControllerHints && on ? 1 : 0)
            .allowsHitTesting(false)
    }

    // MARK: Controller

    /// Moves the selection by `offset` games. Returns false at either end of the grid.
    @discardableResult private func moveSelection(_ offset: Int) -> Bool {
        guard !filtered.isEmpty else { return false }
        let index = filtered.firstIndex(where: { $0.id == selected?.id }) ?? 0
        let next = index + offset
        guard filtered.indices.contains(next) else { return false }
        selectedID = filtered[next].id
        return true
    }

    private func handleController(_ input: LibraryController.Input) {
        switch input {
        case .back:
            if searchPresented { closeSearch() }
            zone = .grid
        case .previousTab, .nextTab:
            setFilter(filterIndex + (input == .nextTab ? 1 : -1))
        case .play:
            if !searchPresented, let selected, !disabled(selected) { play(selected) }
        case .options:
            if !searchPresented, let selected { details(selected) }
        case .search:
            searchPresented = true
            searching = true
        case .left, .right:
            let step = input == .left ? -1 : 1
            switch zone {
            case .hero: heroAction = min(1, max(0, heroAction + step))
            case .filter: setFilter(filterIndex + step)
            case .grid: moveSelection(step)
            case .bar: barIndex = min(3, max(0, barIndex + step))
            }
        case .up:
            switch zone {
            case .hero: break
            case .filter: if selected != nil && !searchPresented { zone = .hero }
            case .grid: if !moveSelection(-columns) { zone = .filter }
            case .bar: zone = filtered.isEmpty ? .filter : .grid
            }
        case .down:
            switch zone {
            case .hero: zone = .filter
            case .filter: zone = filtered.isEmpty ? .bar : .grid
            case .grid: if !moveSelection(columns) { zone = .bar }
            case .bar: break
            }
        case .select:
            switch zone {
            case .hero:
                guard let selected else { return }
                if heroAction == 1 { details(selected) } else if !disabled(selected) { play(selected) }
            case .filter: setFilter((filterIndex + 1) % 3)
            case .grid: if let selected { details(selected) }
            case .bar:
                let actions: [() -> Void] = [{}, showDownloads, showLogs, settings]
                actions[barIndex]()
            }
        }
    }
}

/// The latest launch's log lines and one-tap sharing of the full logs.
struct SparkLogsView: View {
    @State private var lines: [String] = []
    @State private var loaded = false

    private var logURLs: [URL] {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
        return RuntimeDiagnosticLogFiles.existing(in: documents)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !logURLs.isEmpty {
                    ShareLink(items: logURLs) {
                        Label("Share Full Logs", systemImage: "square.and.arrow.up").font(.headline)
                            .frame(maxWidth: .infinity).frame(height: 54)
                    }
                    .buttonStyle(SparkPillButtonStyle(prominent: true))
                    Text("Includes the app log and the Wine, FEX and DXMT logs. Logs can contain file paths; review before sharing.")
                        .font(.footnote).foregroundStyle(Color.white.opacity(0.6)).padding(.horizontal, 6)
                }
                SparkCard(title: "Latest Launch") {
                    if lines.isEmpty {
                        Text(loaded ? "No launch has been logged yet." : "Reading the log…")
                            .font(.callout).foregroundStyle(Color.white.opacity(0.7)).padding(.vertical, 12)
                    } else {
                        ForEach(lines.indices, id: \.self) { index in
                            Text(lines[index]).font(.caption.monospaced())
                                .foregroundStyle(Color.white.opacity(0.9))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 7)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 32)
        }
        .background(SparkTheme.ground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .controllerMenuScope()
        .task {
            // Reading the log touches the disk, so do it off the main thread.
            lines = await Task.detached(priority: .utility) { SparkLaunchDiagnosis.latestLaunchLines() }.value
            loaded = true
        }
    }
}

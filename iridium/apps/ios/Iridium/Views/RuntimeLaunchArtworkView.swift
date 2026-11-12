import SwiftUI

/// Keeps the library artwork on screen until the renderer presents a frame.
@MainActor struct RuntimeLaunchArtworkView: View {
    let session: RuntimePlayerSession
    let phase: RuntimeLaunchPresentation
    let safeInsets: EdgeInsets
    let viewLogs: () -> Void
    let close: () -> Void
    let memory: RuntimeMemorySnapshot?
    @State private var artwork: RuntimeLaunchArtworkSnapshot
    @State private var diagnosis: SparkLaunchDiagnosis?
    @ObservedObject private var progress = SparkLaunchProgress.shared
    @ObservedObject var motionState: RuntimeLaunchMotionState
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(session: RuntimePlayerSession, phase: RuntimeLaunchPresentation, safeInsets: EdgeInsets,
         memory: RuntimeMemorySnapshot? = nil,
         artwork: RuntimeLaunchArtworkSnapshot? = nil,
         motionState: RuntimeLaunchMotionState,
         viewLogs: @escaping () -> Void, close: @escaping () -> Void) {
        self.session = session
        self.phase = phase
        self.safeInsets = safeInsets
        self.viewLogs = viewLogs
        self.close = close
        self.memory = memory
        self.motionState = motionState
        if let artwork, artwork.gameID == session.gameID {
            _artwork = State(initialValue: artwork)
        } else {
            _artwork = State(initialValue: .capture(session: session))
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            let landscape = bounds.width > bounds.height && !typeSize.isAccessibilitySize
            let side = max(safeInsets.leading, safeInsets.trailing) + (landscape ? 32 : 20)
            let motion = !reduceMotion && !typeSize.isAccessibilitySize && !motionState.settled
            let sourceTitle = artwork.retainedFrame(artwork.titleFrame, in: bounds)
            let sourceCover = artwork.retainedFrame(artwork.coverFrame, in: bounds)
            let ended = !phase.isBusy && phase != .playing
            let top = safeInsets.top + (landscape ? 20 : (ended ? 12 : 56))
            let bottom = safeInsets.bottom + 20
            let room = max(0, bounds.height - top - bottom)

            ZStack(alignment: .topLeading) {
                SparkTheme.ground
                backdrop(in: bounds)
                ScrollView {
                    Group {
                        if ended {
                            stoppedContent.frame(minHeight: room, alignment: .top)
                        } else if landscape {
                            HStack(alignment: .center, spacing: 28) {
                                identity(landscape: true, sourceTitle: sourceTitle, sourceCover: sourceCover, motion: motion)
                                    .frame(maxWidth: .infinity)
                                VStack(spacing: 14) {
                                    progressCard
                                    startingActions
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .frame(minHeight: room)
                        } else {
                            VStack(spacing: 24) {
                                identity(landscape: false, sourceTitle: sourceTitle, sourceCover: sourceCover, motion: motion)
                                progressCard
                                Spacer(minLength: 8)
                                startingActions
                            }
                            .frame(minHeight: room, alignment: .top)
                        }
                    }
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, side)
                    .padding(.top, top)
                    .padding(.bottom, bottom)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .coordinateSpace(name: "launchWindow")
            .foregroundStyle(.white)
        }
        .accessibilityIdentifier("playerLaunchArtwork")
        .task(id: phase) {
            // Read the logs off the main thread, and only after a failed launch.
            guard phase == .failed else { diagnosis = nil; return }
            diagnosis = await Task.detached(priority: .utility) { SparkLaunchDiagnosis.latest() }.value
            // Keep the cause with the game so the library can show it later.
            if let diagnosis { SparkGameStatusStore.shared.record(.stopped(diagnosis.cause), for: session.gameID) }
        }
    }

    // MARK: Starting

    /// The game's icon inside the progress ring, with its title underneath.
    private func identity(landscape: Bool, sourceTitle: CGRect?, sourceCover: CGRect?, motion: Bool) -> some View {
        VStack(spacing: 16) {
            ZStack {
                progressRing
                if let cover = artwork.cover {
                    movingCover(cover, width: 96, height: 96, source: sourceCover, motion: motion)
                } else {
                    SparkGameArt(image: nil, title: artwork.title)
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 26))
                }
            }
            .frame(width: 136, height: 136)
            VStack(spacing: 4) {
                Text(phase == .closing ? "CLOSING" : "STARTING")
                    .font(.caption.weight(.bold)).tracking(1.6)
                    .foregroundStyle(.white.opacity(0.75))
                movingTitle(landscape: landscape, source: sourceTitle, motion: motion)
            }
        }
    }

    /// Fills as launch steps complete; it never claims the launch is done.
    private var progressRing: some View {
        let steps = Double(SparkLaunchStep.allCases.count + 1)
        let fraction = phase == .starting ? Double(progress.active.rawValue + 1) / steps : 1
        return ZStack {
            Circle().stroke(Color.white.opacity(0.14), lineWidth: 6)
            Circle().trim(from: 0, to: fraction)
                .stroke(SparkTheme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: fraction)
        }
        .frame(width: 130, height: 130)
        .accessibilityHidden(true)
    }

    private func movingTitle(landscape: Bool, source: CGRect?, motion: Bool) -> some View {
        Text(artwork.title)
            .font(landscape ? .title2.weight(.heavy) : .largeTitle.weight(.heavy))
            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            .truncationMode(.tail)
            .visualEffect { content, geometry in
                let target = geometry.frame(in: .named("launchWindow"))
                let start = source ?? target
                return content.offset(x: motion ? start.minX - target.minX : 0,
                                      y: motion ? start.minY - target.minY : 0)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("playerLaunchTitle")
    }

    private func movingCover(_ cover: UIImage, width: CGFloat, height: CGFloat,
                             source: CGRect?, motion: Bool) -> some View {
        ArtworkImage(image: cover, title: "", position: artwork.coverY, fit: artwork.coverFits)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .visualEffect { content, geometry in
                let target = geometry.frame(in: .named("launchWindow"))
                let start = source ?? target
                return content.scaleEffect(x: motion ? start.width / max(1, target.width) : 1,
                                           y: motion ? start.height / max(1, target.height) : 1,
                                           anchor: .topLeading)
                    .offset(x: motion ? start.minX - target.minX : 0,
                            y: motion ? start.minY - target.minY : 0)
            }
            .accessibilityIdentifier("playerLaunchCover")
    }

    /// The launch steps, the runtime's own status line and the memory meter.
    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if phase == .starting { SparkLaunchStepsView(active: progress.active) }
            HStack(spacing: 10) {
                Text(phase == .starting ? session.statusSummary : phase.title)
                    .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("playerLaunchStatus")
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("playerLaunchPanel")
            if let memory { RuntimeMemoryReadout(memory: memory) }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SparkTheme.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 26))
        .overlay {
            RoundedRectangle(cornerRadius: 26).strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    /// Live Log and Cancel, only while the game is still starting.
    @ViewBuilder private var startingActions: some View {
        if phase == .starting {
            HStack(spacing: 10) {
                Button(action: viewLogs) {
                    Label("Live Log", systemImage: "doc.text").font(.headline)
                        .frame(maxWidth: .infinity).frame(height: 54)
                }
                .buttonStyle(SparkPillButtonStyle())
                Button(action: close) {
                    Text("Cancel").font(.headline)
                        .frame(maxWidth: .infinity).frame(height: 54)
                }
                .buttonStyle(SparkPillButtonStyle())
                .accessibilityLabel("Cancel launch")
            }
        }
    }

    // MARK: Stopped

    private var headline: String {
        phase == .failed ? (diagnosis?.cause ?? phase.title) : phase.title
    }

    private var chipText: String {
        switch phase {
        case .failed: "\(artwork.title) stopped"
        case .stopped: "\(artwork.title) closed"
        default: artwork.title
        }
    }

    private var chipTone: Color {
        phase == .failed ? SparkTheme.problem : phase == .stopped ? SparkTheme.good : SparkTheme.accent
    }

    /// What happened, the log line behind it, how far the launch got, and what to do next.
    private var stoppedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: close) {
                Image(systemName: "chevron.left").font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.45), in: Circle())
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to Library")
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: phase == .stopped ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .accessibilityHidden(true)
                    Text(chipText).lineLimit(1)
                }
                .font(.caption.weight(.bold)).foregroundStyle(chipTone)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.black.opacity(0.5), in: Capsule())
                Text(headline).font(.title.weight(.heavy))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("playerLaunchStatus")
                if let message = phase.message {
                    Text(message).font(.callout).foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if phase == .failed, let diagnosis {
                SparkCard(title: "The Line That Matters") {
                    Text(diagnosis.line).font(.footnote.monospaced())
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(4).padding(.vertical, 12)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("playerLaunchDiagnosis")
            }
            if phase == .failed {
                SparkCard(title: "How Far It Got") {
                    ForEach(SparkLaunchStep.allCases, id: \.rawValue) { step in
                        reachedRow(step.title, state: step.rawValue < progress.active.rawValue ? 0 : step == progress.active ? 1 : 2)
                    }
                }
            }
            Spacer(minLength: 8)
            recoveryActions
        }
    }

    /// One launch step in the summary: 0 passed, 1 stopped here, 2 not reached.
    private func reachedRow(_ title: String, state: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: state == 0 ? "checkmark" : state == 1 ? "xmark" : "circle")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(state == 0 ? SparkTheme.good : state == 1 ? SparkTheme.problem : Color.white.opacity(0.35))
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(state == 1 ? "\(title) (stopped here)" : title)
                .font(.callout.weight(state == 1 ? .bold : .medium))
                .foregroundStyle(state == 1 ? SparkTheme.problem : state == 0 ? Color.white : Color.white.opacity(0.5))
        }
        .frame(minHeight: 40)
        .accessibilityElement(children: .combine)
        .accessibilityValue(state == 0 ? "Passed" : state == 1 ? "Stopped here" : "Not reached")
    }

    private var recoveryActions: some View {
        VStack(spacing: 10) {
            if !shareableLogs.isEmpty {
                ShareLink(items: shareableLogs) {
                    Label("Share Logs", systemImage: "square.and.arrow.up").font(.headline)
                        .frame(maxWidth: .infinity).frame(height: 56)
                }
                .buttonStyle(SparkPillButtonStyle(prominent: true))
            }
            HStack(spacing: 10) {
                Button("View Logs", systemImage: "doc.text", action: viewLogs).libraryGlass()
                Button("Back to Library", action: close).libraryGlass()
            }
            .frame(minHeight: 44)
        }
    }

    /// The app and runtime logs that exist, for one-tap sharing after a stop.
    private var shareableLogs: [URL] {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
        return RuntimeDiagnosticLogFiles.existing(in: documents)
    }

    private func backdrop(in bounds: CGRect) -> some View {
        let frame = artwork.retainedFrame(artwork.backdropFrame, in: bounds) ?? bounds
        return Group {
            if let background = artwork.background {
                LibraryBackdrop(image: background, isLoading: false, position: artwork.backgroundY, reduceMotion: true)
            } else {
                Color.black
            }
        }
        .frame(width: frame.width, height: frame.height)
        .overlay { LibraryBackdropScrim() }
        .position(x: frame.midX, y: frame.midY)
        .clipped()
        .accessibilityHidden(true)
    }
}

struct RuntimeMemoryReadout: View {
    let memory: RuntimeMemorySnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let used = ByteCountFormatter.string(fromByteCount: Int64(clamping: memory.usedBytes), countStyle: .memory)
            Text("RAM: \(used)")
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("App RAM: \(used)")
            if let available = memory.availableBytes {
                // iOS closes the app when little is left, so warn by color before that.
                ProgressView(value: Double(memory.usedBytes), total: max(1, Double(memory.usedBytes) + Double(available)))
                    .tint(available < 300_000_000 ? SparkTheme.problem : available < 700_000_000 ? SparkTheme.accent : Color.white)
                    .accessibilityLabel("App memory use")
                let remaining = ByteCountFormatter.string(fromByteCount: Int64(clamping: available), countStyle: .memory)
                Text("Available: \(remaining)")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Available to app: \(remaining)")
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("playerMemoryStatus")
    }
}

import Combine
import Foundation

/// Launch milestones, in the order the runtime logs them.
enum SparkLaunchStep: Int, CaseIterable {
    case jit, files, memory, process

    var title: String {
        switch self {
        case .jit: "JIT permission"
        case .files: "Game files"
        case .memory: "Code memory"
        case .process: "Windows environment"
        }
    }

    /// The step a "[Launch] ..." log line starts, if it starts one.
    static func starting(at line: String) -> SparkLaunchStep? {
        if line.contains("Waiting for JIT permission") { return .jit }
        if line.contains("Preparing the isolated game environment") { return .files }
        if line.contains("Reserving memory for translated game code") { return .memory }
        if line.contains("Starting the game process") { return .process }
        return nil
    }
}

/// Follows the current launch through its milestones by listening for the
/// launch lines the app already writes to its log.
final class SparkLaunchProgress: ObservableObject {
    static let shared = SparkLaunchProgress()

    @Published private(set) var active: SparkLaunchStep = .jit
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: RuntimeLogCapture.launchLineNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let line = note.object as? String,
                  let step = SparkLaunchStep.starting(at: line) else { return }
            self?.active = step
        }
    }
}

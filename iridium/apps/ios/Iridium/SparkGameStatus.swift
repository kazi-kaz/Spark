import Combine
import Foundation

/// What happened the last time a game was started from the library.
/// It describes one run on this device, not general compatibility.
enum SparkGameStatus: Equatable {
    case notRun
    case ranAndClosed
    case stopped(String)

    var title: String {
        switch self {
        case .notRun: "Not run yet"
        case .ranAndClosed: "Last run OK"
        case .stopped: "Stopped last run"
        }
    }

    /// The reason recorded with a stopped run.
    var detail: String? {
        if case .stopped(let reason) = self { return reason }
        return nil
    }
}

/// Remembers each game's last run outcome across app restarts.
final class SparkGameStatusStore: ObservableObject {
    static let shared = SparkGameStatusStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static func key(_ id: UUID) -> String { "SparkGameStatus.\(id.uuidString)" }

    func status(for id: UUID) -> SparkGameStatus {
        guard let saved = defaults.dictionary(forKey: Self.key(id)),
              let outcome = saved["outcome"] as? String else { return .notRun }
        switch outcome {
        case "ok": return .ranAndClosed
        case "stopped": return .stopped(saved["detail"] as? String ?? "The game stopped.")
        default: return .notRun
        }
    }

    func record(_ status: SparkGameStatus, for id: UUID) {
        switch status {
        case .notRun: defaults.removeObject(forKey: Self.key(id))
        case .ranAndClosed: defaults.set(["outcome": "ok"], forKey: Self.key(id))
        case .stopped(let reason): defaults.set(["outcome": "stopped", "detail": reason], forKey: Self.key(id))
        }
        if Thread.isMainThread {
            objectWillChange.send()
        } else {
            DispatchQueue.main.async { self.objectWillChange.send() }
        }
    }
}

import Foundation

/// A plain-language reading of why the latest launch stopped, with the log
/// line it rests on. It is a best guess from known signatures, not a verdict.
struct SparkLaunchDiagnosis: Equatable, Sendable {
    let cause: String
    let line: String

    /// Known failure signatures, most specific first. Matching ignores case.
    private static let signatures: [(needle: String, cause: String)] = [
        ("ChoosePixelFormat failed", "This game needs OpenGL, which Spark can't draw yet."),
        ("mscorlib.dll was not found", "The game's Mono files are incomplete. Copy the game folder again."),
        ("unrecognized arguments", "The game rejected a launch argument. Check its Launch Options."),
        ("Built-in JIT failed", "JIT did not attach. Connect LocalDevVPN, then restart Spark."),
        ("[fex-unimpl]", "The x86 translator reached something it does not support yet."),
        ("jumbo reserve failed", "The game asked for more address space than iOS gives this app."),
        ("c0000135", "A Windows component (DLL) the game needs is missing."),
        ("c0000018", "The game needs a fixed memory address that was not free."),
        ("c0000142", "A Windows component failed to initialize."),
        ("c0000017", "The game could not reserve the memory it asked for."),
        ("Launch stopped with exit code", "The game closed on its own before showing a window."),
    ]

    /// The line every launch writes first. Earlier lines belong to older launches.
    private static let launchMarker = "[Launch] Waiting for JIT permission."

    /// Finds the most specific known signature in `log`, reporting its latest line.
    static func find(in log: String) -> SparkLaunchDiagnosis? {
        var text = Substring(log)
        if let marker = log.range(of: launchMarker, options: .backwards) {
            text = log[marker.upperBound...]
        }
        let lines = text.split(whereSeparator: \.isNewline)
        for signature in signatures {
            guard let match = lines.last(where: {
                $0.range(of: signature.needle, options: .caseInsensitive) != nil
            }) else { continue }
            let trimmed = match.trimmingCharacters(in: .whitespaces)
            return SparkLaunchDiagnosis(cause: signature.cause, line: String(trimmed.prefix(220)))
        }
        return nil
    }

    /// Reads the end of the app and runtime logs and looks for a known signature.
    static func latest(documents: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first) -> SparkLaunchDiagnosis? {
        guard let documents else { return nil }
        let app = tail(of: documents.appendingPathComponent("iridium-runtime.log"))
        let runtime = tail(of: documents.appendingPathComponent("madeira-log.txt"))
        // The app log goes first so its launch marker also bounds the search.
        return find(in: app + "\n" + runtime)
    }

    private static func tail(of file: URL, bytes: UInt64 = 256 * 1024) -> String {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return "" }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return "" }
        guard (try? handle.seek(toOffset: size > bytes ? size - bytes : 0)) != nil,
              let data = try? handle.readToEnd() else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

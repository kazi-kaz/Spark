import Foundation

/// A game's own configuration, layered on top of the global madeira.cfg.
///
/// Iridium looks for `iridium.cfg` in the game's folder first (Files: Iridium >
/// Games > the game). Games outside the Files-visible library, such as Steam
/// installs, can use `Documents/GameConfigs/<game folder name>.cfg` instead.
/// The file uses madeira.cfg syntax; every key it sets, including `env.` lines,
/// wins over madeira.cfg for that game only. Iridium itself reads
/// `jit-pool-mb` (128, 256, 512 or 1024), which replaces the JIT Memory Limit setting
/// for this game, and `steam-client` / `steam-client-args` (MadeiraSteamClient).
/// The native readers find the file through MADEIRA_GAME_CFG
/// (build/madeira_cfg.h). Game preparation leaves iridium.cfg out of the
/// isolated game copy, so editing it never triggers a copy update.
enum MadeiraGameConfig {
    static let fileName = "iridium.cfg"   // MadeiraGamePreparation.gameConfigName
    static let sharedFolderName = "GameConfigs"
    static let environmentKey = "MADEIRA_GAME_CFG"
    static let jitPoolKey = "jit-pool-mb"
    static let allowedJITPoolMB: Set<Int> = [128, 256, 512, 1024]

    static func locate(gameRoot: URL, documents: URL? = defaultDocuments()) -> URL? {
        let fm = FileManager.default
        let inGame = gameRoot.appendingPathComponent(fileName)
        if fm.isReadableFile(atPath: inGame.path) { return inGame }
        guard let documents else { return nil }
        let shared = documents.appendingPathComponent(sharedFolderName, isDirectory: true)
            .appendingPathComponent(gameRoot.lastPathComponent + ".cfg")
        return fm.isReadableFile(atPath: shared.path) ? shared : nil
    }

    static func defaultDocuments() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    /// The value of `key`, following madeira_cfg.h: '#' comments, trimmed key and
    /// value, value may contain '=', the last occurrence wins.
    static func value(_ key: String, in text: String) -> String? {
        var found: String?
        for raw in text.components(separatedBy: .newlines) {
            let line = (raw.hasPrefix("\u{FEFF}") ? String(raw.dropFirst()) : raw)
                .trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            guard line[..<eq].trimmingCharacters(in: .whitespaces) == key else { continue }
            found = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        }
        return found
    }

    static func value(_ key: String, in file: URL) -> String? {
        guard let data = try? Data(contentsOf: file), data.count <= 64 * 1024,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return value(key, in: text)
    }

    /// The game's JIT pool size, or nil to use the JIT Memory Limit setting.
    static func jitPoolMB(in file: URL?) -> Int? {
        guard let file, let text = value(jitPoolKey, in: file), let mb = Int(text),
              allowedJITPoolMB.contains(mb) else { return nil }
        return mb
    }

    /// `text` with `key` set to `value`, or with the key removed when `value` is nil.
    /// Comments, other keys and their order are kept. Every existing line for the
    /// key is dropped first, because the last occurrence wins when the file is read.
    static func setting(_ key: String, to value: String?, in text: String) -> String {
        var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        lines.removeAll { raw in
            let line = (raw.hasPrefix("\u{FEFF}") ? String(raw.dropFirst()) : raw)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { return false }
            return line[..<eq].trimmingCharacters(in: .whitespaces) == key
        }
        if let value { lines.append("\(key) = \(value)") }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    /// Saves this game's JIT pool size, or clears it when `mb` is nil. Writes the
    /// config file already in use for the game, else iridium.cfg in its folder.
    static func setJITPoolMB(_ mb: Int?, gameRoot: URL, documents: URL? = defaultDocuments()) throws {
        if let mb, !allowedJITPoolMB.contains(mb) { throw CocoaError(.featureUnsupported) }
        let file = locate(gameRoot: gameRoot, documents: documents) ?? gameRoot.appendingPathComponent(fileName)
        var text = ""
        if FileManager.default.fileExists(atPath: file.path) {
            let data = try Data(contentsOf: file)
            guard data.count <= 64 * 1024, let existing = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            text = existing
        } else if mb == nil {
            return
        }
        let updated = setting(jitPoolKey, to: mb.map { String($0) }, in: text)
        try Data(updated.utf8).write(to: file, options: .atomic)
    }
}

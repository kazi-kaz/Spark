import Foundation

/// Facts read from a game's Windows program and its folder: what it was
/// built for, which engine it looks like, and anything worth knowing before
/// playing. Read-only; nothing in the game is changed.
struct SparkGameFacts: Equatable, Sendable {
    var fileName: String
    var architecture: String?
    var fixedAddress = false
    var steamDRM = false
    var importsOpenGL = false
    var engine: String?

    /// For example "kincaid.exe · x86-64 · GameMaker".
    var summary: String {
        [fileName, architecture, engine].compactMap { $0 }.joined(separator: " · ")
    }

    var notes: [String] {
        var notes: [String] = []
        if importsOpenGL { notes.append("Uses OpenGL. OpenGL games may not display yet.") }
        if steamDRM { notes.append("Protected by Steam DRM. It starts through Steam, so set up Steam Games in Settings first.") }
        if fixedAddress { notes.append("Needs a fixed memory address. Spark reserves it at launch.") }
        return notes
    }

    static func read(executablePath: String) -> SparkGameFacts? {
        let file = URL(fileURLWithPath: executablePath)
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        var facts = SparkGameFacts(fileName: file.lastPathComponent)
        facts.engine = engine(in: file.deletingLastPathComponent(), executable: file.lastPathComponent)
        readHeaders(handle, into: &facts)
        return facts
    }

    /// Guesses the engine from well-known files beside the program.
    private static func engine(in folder: URL, executable: String) -> String? {
        let listing = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let names = Set(listing.map { $0.lowercased() })
        if names.contains("unityplayer.dll") || names.contains(where: { $0.hasSuffix("_data") }) {
            return names.contains("gameassembly.dll") ? "Unity (IL2CPP)" : "Unity"
        }
        if names.contains("data.win") { return "GameMaker" }
        if names.contains("renpy") { return "Ren'Py" }
        if names.contains("engine") || executable.lowercased().hasSuffix("-win64-shipping.exe") { return "Unreal Engine" }
        if names.contains(where: { $0.hasSuffix(".pck") }) { return "Godot" }
        if names.contains("nw.dll") || names.contains("package.nw") { return "NW.js" }
        return nil
    }

    private static func bytes(_ handle: FileHandle, at offset: Int, count: Int) -> [UInt8]? {
        guard offset >= 0, count > 0, (try? handle.seek(toOffset: UInt64(offset))) != nil,
              let data = try? handle.read(upToCount: count), data.count == count else { return nil }
        return [UInt8](data)
    }

    private static func u16(_ bytes: [UInt8], _ index: Int) -> Int {
        Int(bytes[index]) | (Int(bytes[index + 1]) << 8)
    }

    private static func u32(_ bytes: [UInt8], _ index: Int) -> Int {
        u16(bytes, index) | (u16(bytes, index + 2) << 16)
    }

    /// Reads the Windows program headers: machine type, the relocations-stripped
    /// flag, the section names and the list of imported libraries.
    private static func readHeaders(_ handle: FileHandle, into facts: inout SparkGameFacts) {
        guard let dos = bytes(handle, at: 0, count: 64), dos[0] == 0x4D, dos[1] == 0x5A else { return }
        let header = u32(dos, 0x3C)
        guard header > 0, header < 0x10000, let coff = bytes(handle, at: header, count: 24),
              coff[0] == 0x50, coff[1] == 0x45, coff[2] == 0, coff[3] == 0 else { return }
        switch u16(coff, 4) {
        case 0x8664: facts.architecture = "x86-64"
        case 0x014C: facts.architecture = "x86 (32-bit)"
        case 0xAA64: facts.architecture = "ARM64"
        default: facts.architecture = nil
        }
        let sectionCount = min(u16(coff, 6), 96)
        let optionalSize = u16(coff, 20)
        facts.fixedAddress = u16(coff, 22) & 0x0001 != 0

        let optionalStart = header + 24
        guard optionalSize >= 2, optionalSize <= 1024, sectionCount > 0,
              let optional = bytes(handle, at: optionalStart, count: optionalSize),
              let table = bytes(handle, at: optionalStart + optionalSize, count: sectionCount * 40) else { return }

        var sections: [(address: Int, size: Int, fileOffset: Int)] = []
        let bind: [UInt8] = [0x2E, 0x62, 0x69, 0x6E, 0x64, 0x00]   // ".bind", SteamStub's section
        for index in 0..<sectionCount {
            let base = index * 40
            if Array(table[base..<base + 6]) == bind { facts.steamDRM = true }
            sections.append((address: u32(table, base + 12),
                             size: max(u32(table, base + 8), u32(table, base + 16)),
                             fileOffset: u32(table, base + 20)))
        }

        // The import directory sits at a different place in 32-bit and 64-bit headers.
        let importEntry: Int
        switch u16(optional, 0) {
        case 0x10B: importEntry = 104
        case 0x20B: importEntry = 120
        default: return
        }
        guard importEntry + 8 <= optional.count else { return }

        func fileOffset(_ address: Int) -> Int? {
            for section in sections where address >= section.address && address < section.address + section.size {
                return section.fileOffset + (address - section.address)
            }
            return nil
        }

        let importAddress = u32(optional, importEntry)
        guard importAddress > 0, var cursor = fileOffset(importAddress) else { return }
        for _ in 0..<256 {
            guard let entry = bytes(handle, at: cursor, count: 20) else { return }
            let nameAddress = u32(entry, 12)
            if nameAddress == 0 { return }
            if let nameOffset = fileOffset(nameAddress), let raw = bytes(handle, at: nameOffset, count: 13) {
                let name = String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self).lowercased()
                if name == "opengl32.dll" {
                    facts.importsOpenGL = true
                    return
                }
            }
            cursor += 20
        }
    }
}

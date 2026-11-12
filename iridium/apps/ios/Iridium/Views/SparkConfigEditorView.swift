import SwiftUI

/// A plain text editor for a Madeira config file. The Files app cannot edit
/// text, so without this a config change means replacing the whole file.
struct SparkConfigEditorView: View {
    let title: String
    let file: URL
    @State private var text = ""
    @State private var saved = ""
    @State private var message: String?
    @State private var failed = false

    /// madeira.cfg in the app's top-level Files folder, applied to every game.
    static var globalConfig: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return documents.appendingPathComponent("madeira.cfg")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $text)
                .font(.callout.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.asciiCapable)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(SparkTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("\(title) contents")
            Text("One setting per line, for example env.NAME=value. Lines starting with # are comments. Changes apply to the next launch.")
                .font(.footnote).foregroundStyle(.secondary)
            if let message {
                Text(message).font(.footnote).foregroundStyle(failed ? SparkTheme.problem : SparkTheme.good)
            }
        }
        .padding()
        .background(SparkTheme.ground.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).disabled(text == saved)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        guard let data = try? Data(contentsOf: file), data.count <= 64 * 1024,
              let contents = String(data: data, encoding: .utf8) else {
            message = "This file could not be read as text, so it was left alone."
            failed = true
            return
        }
        text = contents
        saved = contents
    }

    private func save() {
        // iOS turns typed quotes and double hyphens into typographic characters,
        // which the config reader and Windows programs do not understand.
        var contents = text
        for (typographic, plain) in [("\u{201C}", "\""), ("\u{201D}", "\""), ("\u{2018}", "'"),
                                     ("\u{2019}", "'"), ("\u{2014}", "--"), ("\u{2013}", "-")] {
            contents = contents.replacingOccurrences(of: typographic, with: plain)
        }
        if !contents.isEmpty && !contents.hasSuffix("\n") { contents += "\n" }
        do {
            try Data(contents.utf8).write(to: file, options: .atomic)
            text = contents
            saved = contents
            message = "Saved."
            failed = false
        } catch {
            message = "The file could not be saved: \(error.localizedDescription)"
            failed = true
        }
    }
}

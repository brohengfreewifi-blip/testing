import Foundation
import WebKit

@MainActor
final class GameLibrary: ObservableObject {
    @Published var games: [Game] = []
    @Published var busy = false
    @Published var errorMessage: String?

    nonisolated static var gamesDir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Games", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    nonisolated static func folderURL(for g: Game) -> URL {
        gamesDir.appendingPathComponent(g.folderName, isDirectory: true)
    }
    private var indexURL: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("library.json")
    }

    init() { load() }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let g = try? JSONDecoder().decode([Game].self, from: data) else { return }
        games = g
    }
    private func save() {
        if let data = try? JSONEncoder().encode(games) { try? data.write(to: indexURL) }
    }

    // MARK: Import

    func importFolder(_ src: URL) {
        busy = true
        let scoped = src.startAccessingSecurityScopedResource()
        Task {
            defer { if scoped { src.stopAccessingSecurityScopedResource() }; busy = false }
            do {
                let g = try await Task.detached(priority: .userInitiated) {
                    try Self.copyFolder(src)
                }.value
                games.append(g); save()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func importFile(_ src: URL) {
        busy = true
        let scoped = src.startAccessingSecurityScopedResource()
        Task {
            defer { if scoped { src.stopAccessingSecurityScopedResource() }; busy = false }
            do {
                let g = try await Task.detached(priority: .userInitiated) {
                    try Self.copySingleFile(src)
                }.value
                games.append(g); save()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func remove(_ g: Game) {
        try? FileManager.default.removeItem(at: Self.folderURL(for: g))
        games.removeAll { $0.id == g.id }
        save()
        Task { try? await WKWebsiteDataStore.remove(forIdentifier: g.id) }
        UserDefaults.standard.removeObject(forKey: "bindings.\(g.id.uuidString)")
    }

    struct ImportError: LocalizedError {
        let msg: String
        var errorDescription: String? { msg }
    }

    nonisolated private static func copyFolder(_ src: URL) throws -> Game {
        let id = UUID()
        let dst = gamesDir.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.copyItem(at: src, to: dst)
        guard let d = detect(in: dst, fallbackTitle: src.lastPathComponent) else {
            try? FileManager.default.removeItem(at: dst)
            throw ImportError(msg: "No RPG Maker, Flash or HTML5 project found in that folder. Pick the folder that contains index.html, Game.ini or a .swf file.")
        }
        return Game(id: id, title: d.title, engine: d.engine, folderName: id.uuidString,
                    entry: d.entry, isMZ: d.isMZ, dateAdded: Date())
    }

    nonisolated private static func copySingleFile(_ src: URL) throws -> Game {
        let id = UUID()
        let dst = gamesDir.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: src, to: dst.appendingPathComponent(src.lastPathComponent))
        let ext = src.pathExtension.lowercased()
        let title = src.deletingPathExtension().lastPathComponent
        if ext == "swf" {
            return Game(id: id, title: title, engine: .flash, folderName: id.uuidString,
                        entry: src.lastPathComponent, isMZ: false, dateAdded: Date())
        } else if ext == "html" || ext == "htm" {
            return Game(id: id, title: title, engine: .html5, folderName: id.uuidString,
                        entry: src.lastPathComponent, isMZ: false, dateAdded: Date())
        }
        try? FileManager.default.removeItem(at: dst)
        throw ImportError(msg: "Only .swf and .html files can be imported as single files.")
    }

    // MARK: Detection

    struct Detected { var engine: Engine; var entry: String; var isMZ: Bool; var title: String }

    nonisolated private static func detect(in dir: URL, fallbackTitle: String) -> Detected? {
        let fm = FileManager.default
        func exists(_ p: String) -> Bool { fm.fileExists(atPath: dir.appendingPathComponent(p).path) }

        for sub in ["", "www/"] {
            if exists(sub + "index.html") {
                let title = htmlTitle(dir.appendingPathComponent(sub + "index.html")) ?? fallbackTitle
                if exists(sub + "js/rmmz_core.js") {
                    return Detected(engine: .mvmz, entry: sub + "index.html", isMZ: true, title: title)
                }
                if exists(sub + "js/rpg_core.js") {
                    return Detected(engine: .mvmz, entry: sub + "index.html", isMZ: false, title: title)
                }
                return Detected(engine: .html5, entry: sub + "index.html", isMZ: false, title: title)
            }
        }
        if exists("Game.ini") {
            var title = fallbackTitle
            if let ini = try? String(contentsOf: dir.appendingPathComponent("Game.ini"), encoding: .utf8) {
                for line in ini.split(whereSeparator: \.isNewline) where line.lowercased().hasPrefix("title=") {
                    title = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                }
            }
            return Detected(engine: .rgss, entry: "Game.ini", isMZ: false, title: title)
        }
        if let en = fm.enumerator(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let url as URL in en {
                if url.pathComponents.count - dir.pathComponents.count > 3 { en.skipDescendants() }
                if url.pathExtension.lowercased() == "swf" {
                    let rel = url.path.replacingOccurrences(of: dir.path + "/", with: "")
                    return Detected(engine: .flash, entry: rel, isMZ: false,
                                    title: url.deletingPathExtension().lastPathComponent)
                }
            }
        }
        return nil
    }

    nonisolated private static func htmlTitle(_ url: URL) -> String? {
        guard let s = try? String(contentsOf: url, encoding: .utf8),
              let r = s.range(of: "<title>", options: .caseInsensitive),
              let e = s.range(of: "</title>", options: .caseInsensitive, range: r.upperBound..<s.endIndex)
        else { return nil }
        let t = s[r.upperBound..<e.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var library: GameLibrary
    @State private var selected: Game?
    @State private var importMode: ImportMode?
    @State private var showImporter = false
    @State private var unsupported = false

    enum ImportMode { case folder, file }

    private var importTypes: [UTType] {
        if importMode == .folder { return [.folder] }
        var t: [UTType] = [.html, .data]
        if let swf = UTType(filenameExtension: "swf") { t.append(swf) }
        return t
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.games.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "gamecontroller").font(.system(size: 56)).foregroundStyle(.secondary)
                        Text("No games yet").font(.title3.bold())
                        Text("V-RPGMaker is a player only. Tap + to add a project folder you own.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 40)
                    }
                } else {
                    List {
                        ForEach(library.games) { g in
                            Button { open(g) } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: g.engine.icon).font(.title2).frame(width: 40)
                                        .foregroundStyle(.tint)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(g.title).font(.headline).foregroundStyle(.primary)
                                        Text(g.engine.label + (g.engine == .mvmz ? (g.isMZ ? " (MZ)" : " (MV)") : ""))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .swipeActions { Button("Delete", role: .destructive) { library.remove(g) } }
                        }
                    }
                }
            }
            .navigationTitle("V-RPGMaker")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if library.busy { ProgressView() } else {
                        Menu {
                            Button { importMode = .folder; showImporter = true } label: {
                                Label("Import game folder", systemImage: "folder.badge.plus")
                            }
                            Button { importMode = .file; showImporter = true } label: {
                                Label("Import SWF / HTML file", systemImage: "doc.badge.plus")
                            }
                        } label: { Image(systemName: "plus") }
                    }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: importTypes) { result in
                guard case .success(let url) = result else { return }
                if importMode == .folder { library.importFolder(url) } else { library.importFile(url) }
            }
            .alert("Import failed", isPresented: Binding(
                get: { library.errorMessage != nil },
                set: { if !$0 { library.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(library.errorMessage ?? "") }
            .alert("Engine not available", isPresented: $unsupported) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Native RPG Maker XP / VX / Ace support (RGSS) is not included in this build yet. MV, MZ, Flash, HTML5, Godot, Unity WebGL, Construct, Ren'Py and Tyrano web games run normally.")
            }
            .fullScreenCover(item: $selected) { GameScreen(game: $0) }
        }
    }

    private func open(_ g: Game) {
        if g.engine == .rgss { unsupported = true } else { selected = g }
    }
}

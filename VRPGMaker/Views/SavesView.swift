import SwiftUI

struct SaveSlot: Codable {
    let id: Int
    let title: String
    let playtime: String
    let timestamp: Double
}

struct ShareItem: Identifiable { let id = UUID(); let url: URL }

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct SavesView: View {
    @ObservedObject var session: GameSession
    @State private var slots: [SaveSlot?] = Array(repeating: nil, count: 20)
    @State private var importSlot = 1
    @State private var showImporter = false
    @State private var share: ShareItem?
    @State private var message: String?

    private var ext: String { session.game.isMZ ? "rmmzsave" : "rpgsave" }

    var body: some View {
        List(0..<20, id: \.self) { idx in
            let slot = slots[idx]
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Slot \(idx + 1)").font(.headline)
                    if let s = slot {
                        Text([s.title, s.playtime].filter { !$0.isEmpty }.joined(separator: "  ·  "))
                            .font(.caption)
                        if s.timestamp > 0 {
                            Text(Date(timeIntervalSince1970: s.timestamp / 1000), format: .dateTime)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Empty").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Menu {
                    if slot != nil { Button("Export…") { export(idx + 1) } }
                    Button("Import here…") { importSlot = idx + 1; showImporter = true }
                } label: { Image(systemName: "ellipsis.circle").font(.title3) }
            }
        }
        .navigationTitle("Saves")
        .task { await reload() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data, .text]) { result in
            guard case .success(let url) = result else { return }
            Task { await importSave(url) }
        }
        .sheet(item: $share) { ShareSheet(url: $0.url) }
        .alert("Saves", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    private func reload() async {
        let js = #"""
        var out = [];
        var mz = (Utils.RPGMAKER_NAME === 'MZ');
        for (var i = 1; i <= 20; i++) {
          try {
            var info = mz ? DataManager.savefileInfo(i) : DataManager.loadSavefileInfo(i);
            out.push(info ? {id: i, title: info.title || '', playtime: info.playtime || '', timestamp: info.timestamp || 0} : null);
          } catch (e) { out.push(null); }
        }
        return JSON.stringify(out);
        """#
        if let s = await session.run(js) as? String, let d = s.data(using: .utf8),
           let arr = try? JSONDecoder().decode([SaveSlot?].self, from: d) {
            slots = (arr + Array(repeating: nil, count: 20)).prefix(20).map { $0 }
        }
    }

    private func export(_ n: Int) {
        Task {
            let js = #"""
            if (Utils.RPGMAKER_NAME === 'MZ') { return await StorageManager.loadZip(DataManager.makeSavename(i)); }
            return localStorage.getItem(StorageManager.webStorageKey(i));
            """#
            guard let text = await session.run(js, args: ["i": n]) as? String, !text.hasPrefix("ERROR:") else {
                message = "Could not read that save."; return
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("file\(n).\(ext)")
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                share = ShareItem(url: url)
            } catch { message = error.localizedDescription }
        }
    }

    private func importSave(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            message = "Could not read that file."; return
        }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let js = #"""
        function pt(f){ var s = Math.floor((f || 0) / 60); var h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, c = s % 60;
          return [h, m, c].map(function(x){ return ('0' + x).slice(-2); }).join(':'); }
        function mk(c){
          var ids = (c.party && c.party._actors) || [];
          var ad = (c.actors && c.actors._data) || [];
          return {
            title: ($dataSystem && $dataSystem.gameTitle) || '',
            characters: ids.map(function(id){ var a = ad[id]; return a ? [a._characterName, a._characterIndex] : ['', 0]; }),
            faces: ids.map(function(id){ var a = ad[id]; return a ? [a._faceName, a._faceIndex] : ['', 0]; }),
            playtime: pt(c.system && c.system._framesOnSave),
            timestamp: Date.now()
          };
        }
        try {
          if (Utils.RPGMAKER_NAME === 'MZ') {
            var c = JsonEx.parse(await StorageManager.zipToJson(text));
            await StorageManager.saveZip(DataManager.makeSavename(i), text);
            if (DataManager._globalInfo) { DataManager._globalInfo[i] = mk(c); DataManager.saveGlobalInfo(); }
          } else {
            var c2 = JsonEx.parse(LZString.decompressFromBase64(text));
            localStorage.setItem(StorageManager.webStorageKey(i), text);
            var g = DataManager.loadGlobalInfo() || [];
            g[i] = mk(c2);
            DataManager.saveGlobalInfo(g);
          }
          return 'OK';
        } catch (e) { return 'ERROR: ' + e; }
        """#
        let r = await session.run(js, args: ["i": importSlot, "text": text]) as? String
        message = (r == "OK") ? "Imported into slot \(importSlot)." : "Import failed. \(r ?? "")"
        await reload()
    }
}

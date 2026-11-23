import WebKit
import Compression

/// Serves  vrpg://game/...   from the game's folder
///         vrpg://ruffle/... from the bundled Ruffle build
///         vrpg://cheat/...  from the bundled Cheat UI plugin (paramonos, MIT)
/// Avoids file:// CORS / XHR problems and gives every game a stable origin.
final class VRPGSchemeHandler: NSObject, WKURLSchemeHandler {
    let gameRoot: URL
    let ruffleRoot: URL?
    let cheatRoot: URL?
    let swfEntry: String?
    /// Godot threaded builds need SharedArrayBuffer, which needs COOP/COEP on the page.
    let crossOriginIsolated: Bool

    private let queue = DispatchQueue(label: "vrpg.scheme", attributes: .concurrent)
    private let lock = NSLock()
    private var stopped = Set<ObjectIdentifier>()

    init(gameRoot: URL, ruffleRoot: URL?, cheatRoot: URL?, swfEntry: String?,
         crossOriginIsolated: Bool = false) {
        self.gameRoot = gameRoot
        self.ruffleRoot = ruffleRoot
        self.cheatRoot = cheatRoot
        self.swfEntry = swfEntry
        self.crossOriginIsolated = crossOriginIsolated
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        queue.async { self.serve(urlSchemeTask) }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        lock.lock(); stopped.insert(ObjectIdentifier(urlSchemeTask as AnyObject)); lock.unlock()
    }

    private func take(_ id: ObjectIdentifier) -> Bool {   // true if task was stopped
        lock.lock(); defer { lock.unlock() }
        return stopped.remove(id) != nil
    }

    private func serve(_ task: WKURLSchemeTask) {
        let req = task.request
        guard let url = req.url else { return }
        let host = url.host ?? ""
        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }

        var data: Data?
        var mime = "application/octet-stream"

        if host == "game", path == "/__swf.html", let swf = swfEntry {
            data = Data(Self.swfPage(entry: swf).utf8)
            mime = "text/html"
        } else {
            let root: URL?
            switch host {
            case "game": root = gameRoot
            case "ruffle": root = ruffleRoot
            case "cheat": root = cheatRoot
            default: root = nil
            }
            if let root = root {
                let file = root.appendingPathComponent(String(path.dropFirst())).standardizedFileURL
                if file.path.hasPrefix(root.standardizedFileURL.path) {
                    data = try? Data(contentsOf: file, options: .mappedIfSafe)
                    mime = Self.mime(for: file.pathExtension)
                    // Unity WebGL ships foo.wasm.br / foo.data.gz and expects the server to send
                    // Content-Encoding. We decode here and serve the inner type instead.
                    let ext = file.pathExtension.lowercased()
                    let inner = file.deletingPathExtension().pathExtension.lowercased()
                    if host == "game", ext == "br" || ext == "gz", Self.compressedInner.contains(inner) {
                        mime = Self.mime(for: inner)
                        if let raw = data { data = (ext == "br" ? Self.brotli(raw) : Self.gunzip(raw)) ?? raw }
                    }
                }
            }
        }

        var status = 200
        var body = data ?? Data()
        var headers = [
            "Content-Type": mime,
            "Access-Control-Allow-Origin": "*",
            "Accept-Ranges": "bytes",
            "Cache-Control": "no-cache"
        ]
        if data == nil {
            status = 404
            headers["Content-Type"] = "text/plain"
        } else if let range = req.value(forHTTPHeaderField: "Range"), range.hasPrefix("bytes=") {
            let total = body.count
            let parts = range.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
            if parts.count == 2, let start = Int(parts[0]), start < total {
                let end = min(Int(parts[1]) ?? (total - 1), total - 1)
                if start <= end {
                    body = body.subdata(in: start..<(end + 1))
                    status = 206
                    headers["Content-Range"] = "bytes \(start)-\(end)/\(total)"
                }
            }
        }
        headers["Content-Length"] = String(body.count)
        if crossOriginIsolated {
            headers["Cross-Origin-Resource-Policy"] = "cross-origin"
            if mime == "text/html" {
                headers["Cross-Origin-Opener-Policy"] = "same-origin"
                headers["Cross-Origin-Embedder-Policy"] = "require-corp"
            }
        }

        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        let id = ObjectIdentifier(task as AnyObject)
        let payload = body
        DispatchQueue.main.async {
            if self.take(id) { return }
            task.didReceive(response)
            task.didReceive(payload)
            task.didFinish()
        }
    }

    // MARK: Compressed Unity builds

    private static let compressedInner: Set<String> = ["js", "wasm", "data", "json", "mem"]

    /// gzip -> raw deflate (Foundation's .zlib is raw deflate) after skipping the gzip header and trailer.
    static func gunzip(_ d: Data) -> Data? {
        guard d.count > 18, d[d.startIndex] == 0x1f, d[d.startIndex + 1] == 0x8b, d[d.startIndex + 2] == 8 else { return nil }
        func at(_ k: Int) -> UInt8? { k < d.count ? d[d.startIndex + k] : nil }
        let flg = d[d.startIndex + 3]
        var i = 10
        if flg & 4 != 0 {                                   // FEXTRA
            guard let l0 = at(i), let l1 = at(i + 1) else { return nil }
            i += 2 + Int(l0) + (Int(l1) << 8)
        }
        for bit: UInt8 in [8, 16] where flg & bit != 0 {   // FNAME, FCOMMENT (zero-terminated)
            while let c = at(i) { i += 1; if c == 0 { break } }
        }
        if flg & 2 != 0 { i += 2 }                          // FHCRC
        guard i < d.count - 8 else { return nil }
        let body = d.subdata(in: (d.startIndex + i)..<(d.endIndex - 8))
        guard let out = try? (body as NSData).decompressed(using: .zlib) else { return nil }
        return out as Data
    }

    static func brotli(_ d: Data) -> Data? {
        let cap = 1 << 18
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
        defer { dst.deallocate() }
        var s = compression_stream(dst_ptr: dst, dst_size: 0, src_ptr: UnsafePointer(dst), src_size: 0, state: nil)
        guard compression_stream_init(&s, COMPRESSION_STREAM_DECODE, COMPRESSION_BROTLI) == COMPRESSION_STATUS_OK else { return nil }
        defer { compression_stream_destroy(&s) }
        var out = Data()
        let ok: Bool = d.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return false }
            s.src_ptr = base
            s.src_size = raw.count
            while true {
                s.dst_ptr = dst
                s.dst_size = cap
                let st = compression_stream_process(&s, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let n = cap - s.dst_size
                if n > 0 { out.append(dst, count: n) }
                if st == COMPRESSION_STATUS_END { return true }
                if st != COMPRESSION_STATUS_OK || (n == 0 && s.src_size == 0) { return false }
            }
        }
        return ok ? out : nil
    }

    static func mime(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html"
        case "js", "mjs": return "text/javascript"
        case "json": return "application/json"
        case "css": return "text/css"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "ogg", "oga": return "audio/ogg"
        case "m4a": return "audio/mp4"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "mp4": return "video/mp4"
        case "webm": return "video/webm"
        case "wasm": return "application/wasm"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "txt", "ini": return "text/plain"
        case "swf": return "application/x-shockwave-flash"
        case "ico": return "image/x-icon"
        case "avif": return "image/avif"
        case "bmp": return "image/bmp"
        case "opus": return "audio/ogg"
        case "flac": return "audio/flac"
        case "aac": return "audio/aac"
        case "ogv": return "video/ogg"
        case "xml": return "application/xml"
        case "map": return "application/json"
        case "webmanifest": return "application/manifest+json"
        default: return "application/octet-stream"
        }
    }

    static func swfPage(entry: String) -> String {
        let enc = entry.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? entry
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#p{width:100%;height:100%}</style>
        <script>window.RufflePlayer=window.RufflePlayer||{};
        window.RufflePlayer.config={publicPath:"vrpg://ruffle/",autoplay:"on",unmuteOverlay:"hidden",letterbox:"on",splashScreen:false};</script>
        <script src="vrpg://ruffle/ruffle.js"></script></head>
        <body><div id="p"></div>
        <script>window.addEventListener("load",function(){
          if(!window.RufflePlayer||!RufflePlayer.newest){
            document.body.innerHTML='<p style="color:#fff;font:16px sans-serif;padding:24px">Ruffle is not bundled in this build.</p>';return;}
          var r=RufflePlayer.newest();var p=r.createPlayer();
          p.style.width="100%";p.style.height="100%";
          document.getElementById("p").appendChild(p);
          p.load("vrpg://game/\(enc)");
        });</script></body></html>
        """
    }
}

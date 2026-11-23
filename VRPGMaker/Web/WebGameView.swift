import SwiftUI
import WebKit

/// Web view that tells the game to re-measure itself whenever its size changes (rotation, split view).
final class GameWebView: WKWebView {
    private var lastSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.size != lastSize else { return }
        lastSize = bounds.size
        for delay in [0.0, 0.25, 0.7] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.evaluateJavaScript("window.dispatchEvent(new Event('resize'));", completionHandler: nil)
            }
        }
    }
}

struct WebGameView: UIViewRepresentable {
    let session: GameSession

    private static let bootJS = #"""
    window.__vk = function(type, key, code, kc) {
      var e = new KeyboardEvent(type, {key: key, code: code, bubbles: true, cancelable: true});
      try {
        Object.defineProperty(e, 'keyCode', {get: function(){ return kc; }});
        Object.defineProperty(e, 'which', {get: function(){ return kc; }});
      } catch (err) {}
      document.dispatchEvent(e);
    };
    document.addEventListener('DOMContentLoaded', function() {
      var m = document.querySelector('meta[name=viewport]');
      if (!m) { m = document.createElement('meta'); m.name = 'viewport'; document.head.appendChild(m); }
      m.content = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover';
      var s = document.createElement('style');
      s.textContent = 'html,body{margin:0;padding:0;overflow:hidden;background:#000}' +
        '*{-webkit-touch-callout:none;-webkit-user-select:none;user-select:none;-webkit-tap-highlight-color:transparent}' +
        'input,textarea,[contenteditable],.cheat-root,.cheat-root *{-webkit-user-select:text;user-select:text}';
      document.head.appendChild(s);
    });
    """#

    func makeUIView(context: Context) -> WKWebView {
        let game = session.game
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = WKWebsiteDataStore(forIdentifier: game.id)   // separate storage per game
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []

        let handler = VRPGSchemeHandler(
            gameRoot: GameLibrary.folderURL(for: game),
            ruffleRoot: Bundle.main.url(forResource: "ruffle", withExtension: nil),
            cheatRoot: Bundle.main.url(forResource: "cheat", withExtension: nil),
            swfEntry: game.engine == .flash ? game.entry : nil,
            crossOriginIsolated: game.engine == .godot)
        session.schemeHandler = handler
        cfg.setURLSchemeHandler(handler, forURLScheme: "vrpg")
        cfg.userContentController.addUserScript(
            WKUserScript(source: Self.bootJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let wv = GameWebView(frame: .zero, configuration: cfg)
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.bounces = false
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.scrollView.minimumZoomScale = 1
        wv.scrollView.maximumZoomScale = 1
        wv.scrollView.pinchGestureRecognizer?.isEnabled = false
        wv.isOpaque = false
        wv.backgroundColor = .black
        wv.scrollView.backgroundColor = .black
        session.webView = wv

        let start: String
        if game.engine == .flash {
            start = "vrpg://game/__swf.html"
        } else {
            let enc = game.entry.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? game.entry
            start = "vrpg://game/\(enc)"
        }
        if let url = URL(string: start) { wv.load(URLRequest(url: url)) }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

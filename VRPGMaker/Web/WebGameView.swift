import SwiftUI
import WebKit

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
      var s = document.createElement('style');
      s.textContent = '*{-webkit-touch-callout:none;-webkit-user-select:none;user-select:none;-webkit-tap-highlight-color:transparent}';
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
            swfEntry: game.engine == .flash ? game.entry : nil)
        session.schemeHandler = handler
        cfg.setURLSchemeHandler(handler, forURLScheme: "vrpg")
        cfg.userContentController.addUserScript(
            WKUserScript(source: Self.bootJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.bounces = false
        wv.scrollView.contentInsetAdjustmentBehavior = .never
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

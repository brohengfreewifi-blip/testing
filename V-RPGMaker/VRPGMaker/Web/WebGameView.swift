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

/// Receives "a text field was focused" from the page and opens the typing bar (auto-show mode).
final class KeyboardMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var session: GameSession?
    init(session: GameSession) { self.session = session }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let s = session, s.autoKeyboard else { return }
        DispatchQueue.main.async { s.showKeyboard() }
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
    (function() {
      var touched = [];
      function isEditable(el) {
        if (!el || el.nodeType !== 1) return false;
        if (el.isContentEditable) return true;
        if (el.tagName === 'TEXTAREA') return !el.readOnly && !el.disabled;
        if (el.tagName !== 'INPUT') return false;
        var ty = (el.type || 'text').toLowerCase();
        return ['text','search','url','tel','email','password','number'].indexOf(ty) >= 0 && !el.readOnly && !el.disabled;
      }
      function post(m) { try { window.webkit.messageHandlers.vrpgKeyboard.postMessage(m); } catch (e) {} }
      window.__vkTarget = null;
      window.__vkAuto = window.__vkAuto === true;
      // Auto mode: keep iOS's own keyboard away (inputmode=none) and ask the app for its typing bar instead.
      document.addEventListener('focusin', function(e) {
        var el = e.target;
        if (!isEditable(el)) return;
        window.__vkTarget = el;
        if (window.__vkAuto) {
          if (touched.indexOf(el) < 0) { touched.push(el); el.__vkIm = el.getAttribute('inputmode'); }
          el.setAttribute('inputmode', 'none');
          post({focus: true});
        }
      }, true);
      // Games often cancel touchstart (so the browser never focuses the field). Focus it ourselves on touchend.
      document.addEventListener('touchend', function(e) {
        var el = e.target;
        if (isEditable(el) && document.activeElement !== el) { try { el.focus(); } catch (x) {} }
      }, true);
      window.__vkSetAuto = function(on) {
        window.__vkAuto = !!on;
        if (!on) {
          touched.forEach(function(el) {
            if (el.__vkIm === null || el.__vkIm === undefined) el.removeAttribute('inputmode');
            else el.setAttribute('inputmode', el.__vkIm);
          });
          touched = [];
        }
      };
      window.__vkBegin = function() {
        var el = document.activeElement;
        window.__vkTarget = isEditable(el) ? el : null;
        if (!window.__vkTarget) return '';
        try { var n = el.value.length; el.setSelectionRange(n, n); } catch (x) {}
        return el.isContentEditable ? (el.textContent || '') : (el.value || '');
      };
      function ev(t, type, key, code, kc) {
        var e = new KeyboardEvent(type, {key: key, code: code, bubbles: true, cancelable: true});
        try {
          Object.defineProperty(e, 'keyCode', {get: function(){ return kc; }});
          Object.defineProperty(e, 'which', {get: function(){ return kc; }});
        } catch (x) {}
        return t.dispatchEvent(e);
      }
      function fire(el, type, data, inputType) {
        try { el.dispatchEvent(new InputEvent('input', {bubbles: true, data: data, inputType: inputType})); }
        catch (x) { el.dispatchEvent(new Event('input', {bubbles: true})); }
      }
      function insert(el, c) {
        if (el.isContentEditable) { document.execCommand('insertText', false, c); return; }
        try {
          var s = el.selectionStart, e = el.selectionEnd;
          if (s === null || s === undefined) throw 0;
          el.setRangeText(c, s, e, 'end');
        } catch (x) { el.value = (el.value || '') + c; }
        fire(el, 'input', c, 'insertText');
      }
      function removeBack(el) {
        if (el.isContentEditable) { document.execCommand('delete'); return; }
        try {
          var s = el.selectionStart, e = el.selectionEnd;
          if (s === null || s === undefined) throw 0;
          if (s === e) { if (s === 0) return; s -= 1; }
          el.setRangeText('', s, e, 'end');
        } catch (x) { el.value = (el.value || '').slice(0, -1); }
        fire(el, 'input', null, 'deleteContentBackward');
      }
      function info(c) {
        if (c === ' ') return ['Space', 32];
        if (/^[a-z]$/i.test(c)) return ['Key' + c.toUpperCase(), c.toUpperCase().charCodeAt(0)];
        if (/^[0-9]$/.test(c)) return ['Digit' + c, c.charCodeAt(0)];
        return ['', c.charCodeAt(0) < 256 ? c.charCodeAt(0) : 0];
      }
      // Types into the focused field (value + input events) and always sends the matching key events,
      // so games that read the keyboard directly (no text field) receive them on document.
      window.__vkType = function(del, ins, special) {
        var el = window.__vkTarget;
        if (el && !document.contains(el)) el = window.__vkTarget = null;
        var t = el || document;
        for (var i = 0; i < del; i++) {
          var ok = ev(t, 'keydown', 'Backspace', 'Backspace', 8);
          if (ok && el) removeBack(el);
          ev(t, 'keyup', 'Backspace', 'Backspace', 8);
        }
        Array.from(ins || '').forEach(function(c) {
          var k = info(c);
          var ok = ev(t, 'keydown', c, k[0], k[1]);
          if (ok && el) insert(el, c);
          ev(t, 'keyup', c, k[0], k[1]);
        });
        if (special) {
          var codes = {Enter: 13, Escape: 27, Tab: 9};
          ev(t, 'keydown', special, special, codes[special] || 0);
          ev(t, 'keyup', special, special, codes[special] || 0);
        }
      };
    })();
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
            WKUserScript(source: "window.__vkAuto=\(session.autoKeyboard);" + Self.bootJS,
                         injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cfg.userContentController.add(KeyboardMessageHandler(session: session), name: "vrpgKeyboard")

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

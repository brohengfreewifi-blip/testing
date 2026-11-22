import SwiftUI
import WebKit
import GameController

/// Owns the web view, the key-binding map and controller state for one running game.
final class GameSession: ObservableObject {
    let game: Game
    weak var webView: WKWebView?
    var schemeHandler: VRPGSchemeHandler?

    @Published var padVisible = true
    @Published var controllerConnected = false
    @Published var bindings: [PadAction: String] = [:]
    @Published var layout: PadLayout { didSet { layout.save(for: game.id) } }
    @Published var editingLayout = false
    @Published var cheatError: String?
    private var heldKeys = Set<String>()

    private var held = Set<PadAction>()
    private var observers: [NSObjectProtocol] = []

    init(game: Game) {
        self.game = game
        self.layout = PadLayout.load(for: game.id)
        var map: [PadAction: String] = [:]
        let saved = UserDefaults.standard.dictionary(forKey: bindKey) as? [String: String] ?? [:]
        for a in PadAction.allCases { map[a] = saved[a.rawValue] ?? a.defaultKey }
        bindings = map
    }

    private var bindKey: String { "bindings.\(game.id.uuidString)" }

    func setBinding(_ a: PadAction, _ keyName: String) {
        bindings[a] = keyName
        let raw = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })
        UserDefaults.standard.set(raw, forKey: bindKey)
    }
    func resetBindings() {
        for a in PadAction.allCases { bindings[a] = a.defaultKey }
        UserDefaults.standard.removeObject(forKey: bindKey)
    }

    // MARK: Input

    /// Press / release a logical control. Duplicate events are filtered.
    func set(_ a: PadAction, _ down: Bool) {
        if down == held.contains(a) { return }
        if down { held.insert(a) } else { held.remove(a) }
        let k = KeyChoice.named(bindings[a] ?? a.defaultKey)
        let js = "window.__vk&&window.__vk('\(down ? "keydown" : "keyup")','\(k.key)','\(k.code)',\(k.keyCode));"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Press / release a raw key by name (used by custom buttons).
    func sendKey(_ name: String, _ down: Bool) {
        if down == heldKeys.contains(name) { return }
        if down { heldKeys.insert(name) } else { heldKeys.remove(name) }
        let k = KeyChoice.named(name)
        let js = "window.__vk&&window.__vk('\(down ? "keydown" : "keyup")','\(k.key)','\(k.code)',\(k.keyCode));"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Opens / closes the Cheat UI plugin window (paramonos). Loads it on first use.
    /// The plugin has no direct API, so we load it through its own `__mvMzCheatGuard` hook
    /// (which reports load and startup failures), wait until it has started, work out which key
    /// it currently listens for (the user can rebind it), and send that key to the page.
    /// Anything that goes wrong is shown to the user instead of failing silently.
    func toggleCheat() {
        guard game.engine == .mvmz else { return }
        Task { @MainActor in
            let r = await run(Self.cheatJS) as? String
            if let r, r != "ok" { cheatError = r.hasPrefix("ERROR: ") ? String(r.dropFirst(7)) : r }
        }
    }

    private static let cheatJS = #"""
    try {
      function sleep(ms){ return new Promise(function(r){ setTimeout(r, ms); }); }
      var G = window.__vrpgCheat;
      if (!G) {
        G = window.__vrpgCheat = { fatal: [], evaluated: false, started: false, match: null, label: '', loaded: false };
        function msg(e){ return (e && e.message) || String(e); }
        window.__mvMzCheatGuard = {
          evaluated: function(){ G.evaluated = true; },
          evaluateFailed: function(e){ G.fatal.push('script error: ' + msg(e)); },
          stageFailed: function(name, essential, e){ if (essential) G.fatal.push(name + ': ' + msg(e)); },
          started: function(){ G.started = true; },
          setOpenKey: function(label, fn){ G.label = label; G.match = fn; }
        };
        var l = document.createElement('link');
        l.rel = 'stylesheet'; l.href = 'vrpg://cheat/cheat.css';
        document.head.appendChild(l);
        await new Promise(function(resolve, reject){
          var s = document.createElement('script');
          s.src = 'vrpg://cheat/cheat.js';
          s.onload = resolve;
          s.onerror = function(){ reject(new Error('Could not load the cheat plugin files (vrpg://cheat/cheat.js).')); };
          document.body.appendChild(s);
        });
        G.loaded = true;
      }
      for (var i = 0; i < 50 && !G.started && G.fatal.length === 0; i++) await sleep(100);
      if (G.fatal.length) throw new Error('The cheat plugin failed to start: ' + G.fatal.join('; '));
      if (!G.evaluated || !G.started || !document.getElementById('cheat-root'))
        throw new Error('The cheat plugin loaded but did not start. Wait for the game to finish loading, then try again.');

      var k = 67, mods = {ctrl: false, alt: false, shift: false, meta: false};
      if (G.match) {
        var found = false;
        for (var m = 0; m < 16 && !found; m++) {
          var c = !!(m & 1), a = !!(m & 2), sh = !!(m & 4), me = !!(m & 8);
          for (var kc = 8; kc <= 255; kc++) {
            if ([16, 17, 18, 91, 93, 224].indexOf(kc) >= 0) continue;
            var ok = false;
            try { ok = G.match({keyCode: kc, ctrlKey: c, altKey: a, shiftKey: sh, metaKey: me}); } catch (x) {}
            if (ok) { k = kc; mods = {ctrl: c, alt: a, shift: sh, meta: me}; found = true; break; }
          }
        }
        if (!found) throw new Error('Could not work out the cheat open key (' + G.label + ').');
      }
      function fire(type){
        var e = new KeyboardEvent(type, {
          key: (k >= 65 && k <= 90) ? String.fromCharCode(k + 32) : '', code: '',
          ctrlKey: mods.ctrl, altKey: mods.alt, shiftKey: mods.shift, metaKey: mods.meta,
          bubbles: true, cancelable: true
        });
        try {
          Object.defineProperty(e, 'keyCode', {get: function(){ return k; }});
          Object.defineProperty(e, 'which', {get: function(){ return k; }});
        } catch (x) {}
        window.dispatchEvent(e);
      }
      await sleep(80);
      fire('keydown');
      await sleep(40);
      fire('keyup');
      return 'ok';
    } catch (e) { return 'ERROR: ' + ((e && e.message) || e); }
    """#

    func releaseAll() {
        for a in held { set(a, false) }
        for k in heldKeys { sendKey(k, false) }
    }

    // MARK: Controllers

    func startControllers() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] n in
            if let c = n.object as? GCController { self?.attach(c) }
        })
        observers.append(nc.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            self?.controllerConnected = !GCController.controllers().isEmpty
            self?.releaseAll()
        })
        GCController.controllers().forEach(attach)
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        GCController.controllers().forEach { $0.extendedGamepad?.valueChangedHandler = nil }
        releaseAll()
    }

    private func attach(_ c: GCController) {
        guard let pad = c.extendedGamepad else { return }
        controllerConnected = true
        pad.valueChangedHandler = { [weak self] gp, _ in
            DispatchQueue.main.async { self?.apply(gp) }
        }
    }

    private func apply(_ gp: GCExtendedGamepad) {
        var want = Set<PadAction>()
        let sx = gp.leftThumbstick.xAxis.value, sy = gp.leftThumbstick.yAxis.value
        if gp.dpad.left.isPressed || sx < -0.5 { want.insert(.left) }
        if gp.dpad.right.isPressed || sx > 0.5 { want.insert(.right) }
        if gp.dpad.up.isPressed || sy > 0.5 { want.insert(.up) }
        if gp.dpad.down.isPressed || sy < -0.5 { want.insert(.down) }
        if gp.buttonA.isPressed { want.insert(.ok) }
        if gp.buttonB.isPressed { want.insert(.cancel) }
        if gp.buttonX.isPressed { want.insert(.shift) }
        if gp.buttonY.isPressed || gp.buttonMenu.isPressed { want.insert(.menu) }
        if gp.leftShoulder.isPressed { want.insert(.pageUp) }
        if gp.rightShoulder.isPressed { want.insert(.pageDown) }
        for a in PadAction.allCases { set(a, want.contains(a)) }
    }

    // MARK: JS helper

    /// Runs a JS function body (may use `await` and `return`). Arguments become local variables.
    @discardableResult
    func run(_ body: String, args: [String: Any] = [:]) async -> Any? {
        guard let wv = webView else { return nil }
        do {
            return try await wv.callAsyncJavaScript(body, arguments: args, in: nil, contentWorld: .page)
        } catch {
            return "ERROR: \(error.localizedDescription)"
        }
    }
}

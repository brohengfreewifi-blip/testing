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

    private var held = Set<PadAction>()
    private var observers: [NSObjectProtocol] = []

    init(game: Game) {
        self.game = game
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

    func releaseAll() { for a in held { set(a, false) } }

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

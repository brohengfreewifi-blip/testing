import Foundation
import CoreGraphics

/// One on-screen control. Positions are fractions of the screen (0...1),
/// stored separately for portrait and landscape so rotating keeps both layouts.
struct PadElement: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case move, action, key, cheat }
    var id: String
    var kind: Kind
    var value: String          // PadAction rawValue (action) or key name (key)
    var label: String
    var size: Double
    var visible: Bool
    var portrait: [Double]
    var landscape: [Double]

    func pos(_ land: Bool) -> CGPoint {
        let p = land ? landscape : portrait
        return CGPoint(x: p[0], y: p[1])
    }
    mutating func setPos(_ x: Double, _ y: Double, land: Bool) {
        let c = [min(max(x, 0.04), 0.96), min(max(y, 0.06), 0.96)]
        if land { landscape = c } else { portrait = c }
    }
}

struct PadLayout: Codable, Equatable {
    var elements: [PadElement]
    var opacity: Double
    var joystick: Bool

    /// The 🎮 button that opens the Cheat UI plugin (MV/MZ games only).
    static var cheatElement: PadElement {
        PadElement(id: "cheat", kind: .cheat, value: "", label: "🎮", size: 52, visible: true,
                   portrait: [0.10, 0.10], landscape: [0.07, 0.14])
    }

    static var `default`: PadLayout {
        PadLayout(elements: [
            PadElement(id: "move", kind: .move, value: "", label: "Move", size: 150, visible: true,
                       portrait: [0.24, 0.86], landscape: [0.14, 0.72]),
            PadElement(id: "ok", kind: .action, value: PadAction.ok.rawValue, label: "A", size: 66, visible: true,
                       portrait: [0.88, 0.84], landscape: [0.90, 0.74]),
            PadElement(id: "cancel", kind: .action, value: PadAction.cancel.rawValue, label: "B", size: 66, visible: true,
                       portrait: [0.68, 0.89], landscape: [0.79, 0.85]),
            PadElement(id: "shift", kind: .action, value: PadAction.shift.rawValue, label: "Dash", size: 46, visible: true,
                       portrait: [0.90, 0.70], landscape: [0.92, 0.55]),
            PadElement(id: "menu", kind: .action, value: PadAction.menu.rawValue, label: "Menu", size: 46, visible: true,
                       portrait: [0.76, 0.72], landscape: [0.81, 0.62]),
            cheatElement,
        ], opacity: 0.65, joystick: false)
    }

    private static func key(_ id: UUID) -> String { "padlayout.\(id.uuidString)" }

    static func load(for id: UUID) -> PadLayout {
        if let d = UserDefaults.standard.data(forKey: key(id)),
           var l = try? JSONDecoder().decode(PadLayout.self, from: d) {
            if !l.elements.contains(where: { $0.id == "cheat" }) { l.elements.append(cheatElement) }
            return l
        }
        return .default
    }
    func save(for id: UUID) {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key(id)) }
    }
}

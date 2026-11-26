import Foundation
import CoreGraphics

/// One on-screen control. Positions are fractions of the screen (0...1),
/// stored separately for portrait and landscape so rotating keeps both layouts.
struct PadElement: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case move, action, key, cheat }
    enum CodingKeys: String, CodingKey {
        case id, kind, value, label, size, visible, portrait, landscape, opacity, latch
    }

    var id: String
    var kind: Kind
    var value: String          // PadAction rawValue (action) or key name (key)
    var label: String
    var size: Double
    var visible: Bool
    var portrait: [Double]
    var landscape: [Double]
    var opacity: Double = 1    // multiplies the layout-wide opacity
    var latch: Bool = false    // tap to hold, tap again to release (key / action buttons)

    /// Ids of the controls that come with the default layout. Everything else is user-made.
    static let builtInIDs: Set<String> = ["move", "ok", "cancel", "shift", "menu", "cheat"]
    var isCustom: Bool { !Self.builtInIDs.contains(id) }

    func pos(_ land: Bool) -> CGPoint {
        let p = land ? landscape : portrait
        return CGPoint(x: p[0], y: p[1])
    }
    mutating func setPos(_ x: Double, _ y: Double, land: Bool) {
        let c = [min(max(x, 0.04), 0.96), min(max(y, 0.06), 0.96)]
        if land { landscape = c } else { portrait = c }
    }
}

extension PadElement {
    // Layouts saved by older versions have no opacity / latch keys; they must still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        value = try c.decode(String.self, forKey: .value)
        label = try c.decode(String.self, forKey: .label)
        size = try c.decode(Double.self, forKey: .size)
        visible = try c.decode(Bool.self, forKey: .visible)
        portrait = try c.decode([Double].self, forKey: .portrait)
        landscape = try c.decode([Double].self, forKey: .landscape)
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        latch = try c.decodeIfPresent(Bool.self, forKey: .latch) ?? false
    }
}

struct PadLayout: Codable, Equatable {
    enum CodingKeys: String, CodingKey { case elements, opacity, joystick, snap, haptics }

    var elements: [PadElement]
    var opacity: Double
    var joystick: Bool
    var snap: Bool = false      // snap dragged controls to a grid
    var haptics: Bool = true    // light vibration when a button is pressed

    static let sizeRange: ClosedRange<Double> = 36...240
    static let snapStep = 0.025

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
        ], opacity: AppSettings.padOpacity, joystick: AppSettings.padJoystick, haptics: AppSettings.padHaptics)
    }

    // MARK: Quick adjustments

    /// Swaps left and right (left-handed layout). The 🎮 button stays put so it never lands under the menu buttons.
    mutating func mirrorHorizontally() {
        for i in elements.indices where elements[i].kind != .cheat {
            elements[i].portrait[0] = 1 - elements[i].portrait[0]
            elements[i].landscape[0] = 1 - elements[i].landscape[0]
        }
    }

    mutating func scaleSizes(by factor: Double) {
        for i in elements.indices {
            elements[i].size = min(max(elements[i].size * factor, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
        }
    }

    // MARK: Persistence

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

extension PadLayout {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        elements = try c.decode([PadElement].self, forKey: .elements)
        opacity = try c.decode(Double.self, forKey: .opacity)
        joystick = try c.decode(Bool.self, forKey: .joystick)
        snap = try c.decodeIfPresent(Bool.self, forKey: .snap) ?? false
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? true
    }
}

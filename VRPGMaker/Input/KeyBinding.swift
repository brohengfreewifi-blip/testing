import Foundation

struct KeyChoice: Hashable, Identifiable {
    let name: String
    let key: String
    let code: String
    let keyCode: Int
    var id: String { name }

    static let all: [KeyChoice] = {
        var a: [KeyChoice] = []
        for (i, ch) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() {
            a.append(KeyChoice(name: String(ch), key: String(ch).lowercased(), code: "Key\(ch)", keyCode: 65 + i))
        }
        a += [
            KeyChoice(name: "Enter", key: "Enter", code: "Enter", keyCode: 13),
            KeyChoice(name: "Space", key: " ", code: "Space", keyCode: 32),
            KeyChoice(name: "Escape", key: "Escape", code: "Escape", keyCode: 27),
            KeyChoice(name: "Shift", key: "Shift", code: "ShiftLeft", keyCode: 16),
            KeyChoice(name: "Tab", key: "Tab", code: "Tab", keyCode: 9),
            KeyChoice(name: "Ctrl", key: "Control", code: "ControlLeft", keyCode: 17),
            KeyChoice(name: "Alt", key: "Alt", code: "AltLeft", keyCode: 18),
            KeyChoice(name: "Up", key: "ArrowUp", code: "ArrowUp", keyCode: 38),
            KeyChoice(name: "Down", key: "ArrowDown", code: "ArrowDown", keyCode: 40),
            KeyChoice(name: "Left", key: "ArrowLeft", code: "ArrowLeft", keyCode: 37),
            KeyChoice(name: "Right", key: "ArrowRight", code: "ArrowRight", keyCode: 39),
            KeyChoice(name: "PageUp", key: "PageUp", code: "PageUp", keyCode: 33),
            KeyChoice(name: "PageDown", key: "PageDown", code: "PageDown", keyCode: 34),
        ]
        return a
    }()

    static func named(_ n: String) -> KeyChoice { all.first { $0.name == n } ?? all[0] }
}

/// Logical controls. On-screen buttons and controllers drive these,
/// and each one is mapped to whatever key the game reads.
enum PadAction: String, CaseIterable, Codable, Identifiable {
    case up, down, left, right, ok, cancel, shift, menu, pageUp, pageDown
    var id: String { rawValue }

    var title: String {
        switch self {
        case .up: return "D-pad Up"
        case .down: return "D-pad Down"
        case .left: return "D-pad Left"
        case .right: return "D-pad Right"
        case .ok: return "A (OK)"
        case .cancel: return "B (Cancel)"
        case .shift: return "Shift (Dash)"
        case .menu: return "Menu"
        case .pageUp: return "Page Up (L)"
        case .pageDown: return "Page Down (R)"
        }
    }

    var defaultKey: String {
        switch self {
        case .up: return "Up"
        case .down: return "Down"
        case .left: return "Left"
        case .right: return "Right"
        case .ok: return "Z"
        case .cancel: return "X"
        case .shift: return "Shift"
        case .menu: return "Escape"
        case .pageUp: return "Q"
        case .pageDown: return "W"
        }
    }
}

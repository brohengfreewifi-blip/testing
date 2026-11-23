import Foundation

enum Engine: String, Codable {
    case mvmz, rgss, flash, html5
    // Added later. Never rename or remove cases: Engine is persisted in library.json.
    case godot, unity, construct, renpy, tyrano

    var label: String {
        switch self {
        case .mvmz: return "MV / MZ"
        case .rgss: return "XP / VX / Ace"
        case .flash: return "Flash"
        case .html5: return "HTML5"
        case .godot: return "Godot"
        case .unity: return "Unity WebGL"
        case .construct: return "Construct"
        case .renpy: return "Ren'Py"
        case .tyrano: return "TyranoScript"
        }
    }
    var icon: String {
        switch self {
        case .mvmz: return "gamecontroller.fill"
        case .rgss: return "cpu"
        case .flash: return "bolt.fill"
        case .html5: return "globe"
        case .godot: return "cube.fill"
        case .unity: return "square.stack.3d.up.fill"
        case .construct: return "hammer.fill"
        case .renpy: return "text.book.closed.fill"
        case .tyrano: return "book.fill"
        }
    }
}

struct Game: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var engine: Engine
    var folderName: String      // folder under Documents/Games
    var entry: String           // relative path of index.html / .swf
    var isMZ: Bool
    var dateAdded: Date
}

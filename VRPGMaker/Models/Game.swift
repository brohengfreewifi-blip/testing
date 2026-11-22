import Foundation

enum Engine: String, Codable {
    case mvmz, rgss, flash, html5

    var label: String {
        switch self {
        case .mvmz: return "MV / MZ"
        case .rgss: return "XP / VX / Ace"
        case .flash: return "Flash"
        case .html5: return "HTML5"
        }
    }
    var icon: String {
        switch self {
        case .mvmz: return "gamecontroller.fill"
        case .rgss: return "cpu"
        case .flash: return "bolt.fill"
        case .html5: return "globe"
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

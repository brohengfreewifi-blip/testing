import SwiftUI

@main
struct VRPGMakerApp: App {
    @StateObject private var library = GameLibrary()
    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(library)
                .preferredColorScheme(.dark)
        }
    }
}

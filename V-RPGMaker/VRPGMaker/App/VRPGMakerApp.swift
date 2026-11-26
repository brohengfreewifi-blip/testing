import SwiftUI

@main
struct VRPGMakerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var library = GameLibrary()
    @AppStorage(AppSettings.appearanceKey) private var appearance = AppSettings.Appearance.dark.rawValue

    init() { AppSettings.registerDefaults() }

    var body: some Scene {
        WindowGroup {
            TabView {
                LibraryView()
                    .tabItem { Label("Games", systemImage: "gamecontroller.fill") }
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            }
            .environmentObject(library)
            .preferredColorScheme(AppSettings.Appearance(rawValue: appearance)?.scheme)
        }
    }
}

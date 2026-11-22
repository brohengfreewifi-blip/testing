import SwiftUI

struct GameMenu: View {
    @ObservedObject var session: GameSession
    let onQuit: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Resume") { dismiss() }
                }
                // Only rows that do something for this engine are shown.
                Section {
                    if session.game.engine == .mvmz {
                        NavigationLink("Saves") { SavesView(session: session) }
                        NavigationLink("Cheats") { CheatsView(session: session) }
                    }
                    NavigationLink("Controls") { ControlsView(session: session) }
                    Toggle("On-screen gamepad", isOn: $session.padVisible)
                    Button("Reload game") { session.webView?.reload(); dismiss() }
                }
                Section {
                    Button("Quit to library", role: .destructive, action: onQuit)
                }
            }
            .navigationTitle(session.game.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct ControlsView: View {
    @ObservedObject var session: GameSession
    var body: some View {
        List {
            Section("Each control sends this key to the game") {
                ForEach(PadAction.allCases) { a in
                    Picker(a.title, selection: Binding(
                        get: { session.bindings[a] ?? a.defaultKey },
                        set: { session.setBinding(a, $0) })) {
                        ForEach(KeyChoice.all) { Text($0.name).tag($0.name) }
                    }
                }
            }
            Section { Button("Reset to defaults", role: .destructive) { session.resetBindings() } }
            if session.controllerConnected {
                Section { Label("Controller connected. The on-screen pad is hidden.", systemImage: "gamecontroller") }
            }
        }
        .navigationTitle("Controls")
    }
}

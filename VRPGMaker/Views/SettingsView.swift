import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.appearanceKey) private var appearance = AppSettings.Appearance.dark.rawValue
    @AppStorage(AppSettings.keepScreenOnKey) private var keepScreenOn = true
    @AppStorage(AppSettings.lockLandscapeKey) private var lockLandscape = false
    @AppStorage(AppSettings.padOpacityKey) private var padOpacity = 0.65
    @AppStorage(AppSettings.padJoystickKey) private var padJoystick = false
    @AppStorage(AppSettings.padHapticsKey) private var padHaptics = true

    private var version: String {
        let i = Bundle.main.infoDictionary
        let v = i?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = i?["CFBundleVersion"] as? String ?? "1"
        return "v\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("General") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppSettings.Appearance.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                }
                Section("Gameplay") {
                    Toggle("Keep screen on", isOn: $keepScreenOn)
                    Toggle("Lock games to landscape", isOn: $lockLandscape)
                }
                Section {
                    Toggle("Joystick instead of D-pad", isOn: $padJoystick)
                    Toggle("Vibrate on press", isOn: $padHaptics)
                    HStack {
                        Text("Opacity")
                        Slider(value: $padOpacity, in: 0.2...1)
                    }
                } header: {
                    Text("Default on-screen pad")
                } footer: {
                    Text("Used by games whose pad you have not customised yet. Per-game changes are made in the game menu.")
                }
                Section("About") {
                    LabeledContent("Version", value: version)
                    NavigationLink("Open source licenses") { LicensesView() }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

struct LicensesView: View {
    private func text(_ file: String) -> String {
        guard let root = Bundle.main.url(forResource: "cheat", withExtension: nil),
              let s = try? String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
        else { return "License text not found in this build." }
        return s
    }

    var body: some View {
        List {
            NavigationLink {
                doc("Cheat UI license", text("LICENSE-paramonos-cheat-ui.txt"))
            } label: { row("RPG Maker MV/MZ Cheat UI (paramonos)", "MIT") }
            NavigationLink {
                doc("Third-party notices", text("LICENSES.txt"))
            } label: { row("Cheat UI third-party notices", "Multiple licenses") }
            row("Ruffle (Flash emulator)", "MIT / Apache-2.0, bundled by CI builds")
        }
        .navigationTitle("Open source licenses")
    }

    private func row(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(sub).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func doc(_ title: String, _ body: String) -> some View {
        ScrollView { Text(body).font(.footnote.monospaced()).padding() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

import SwiftUI
import UIKit

/// App-wide preferences (UserDefaults). `@AppStorage` in SettingsView and plain reads elsewhere share these keys.
enum AppSettings {
    static let appearanceKey = "set.appearance"
    static let keepScreenOnKey = "set.keepScreenOn"
    static let lockLandscapeKey = "set.lockLandscape"
    static let padOpacityKey = "set.padOpacity"
    static let padJoystickKey = "set.padJoystick"
    static let padHapticsKey = "set.padHaptics"

    enum Appearance: String, CaseIterable, Identifiable {
        case auto, light, dark
        var id: String { rawValue }
        var title: String {
            switch self {
            case .auto: return "Auto"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
        var scheme: ColorScheme? {
            switch self {
            case .auto: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    /// Call once at launch so `@AppStorage` defaults and plain `UserDefaults` reads agree.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            appearanceKey: Appearance.dark.rawValue,
            keepScreenOnKey: true,
            lockLandscapeKey: false,
            padOpacityKey: 0.65,
            padJoystickKey: false,
            padHapticsKey: true,
        ])
    }

    // Defaults for a game's pad before the user has customised it (see PadLayout.default).
    static var padOpacity: Double {
        let v = UserDefaults.standard.double(forKey: padOpacityKey)
        return v == 0 ? 0.65 : min(max(v, 0.2), 1)
    }
    static var padJoystick: Bool { UserDefaults.standard.bool(forKey: padJoystickKey) }
    static var padHaptics: Bool {
        UserDefaults.standard.object(forKey: padHapticsKey) as? Bool ?? true
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationMask: UIInterfaceOrientationMask = .allButUpsideDown

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientationMask
    }
}

/// Screen-wake and orientation rules that apply only while a game is on screen.
@MainActor
enum GameEnvironment {
    private static var orientationLocked = false

    static func enter() {
        let d = UserDefaults.standard
        UIApplication.shared.isIdleTimerDisabled = d.bool(forKey: AppSettings.keepScreenOnKey)
        if d.bool(forKey: AppSettings.lockLandscapeKey) {
            orientationLocked = true
            setOrientation(.landscape)
        }
    }

    static func exit() {
        UIApplication.shared.isIdleTimerDisabled = false
        if orientationLocked {
            orientationLocked = false
            setOrientation(.allButUpsideDown)
        }
    }

    private static func setOrientation(_ mask: UIInterfaceOrientationMask) {
        AppDelegate.orientationMask = mask
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        var vc = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        while let p = vc?.presentedViewController { vc = p }
        vc?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
    }
}

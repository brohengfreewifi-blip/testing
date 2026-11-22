---
name: vrpgmaker
description: Project guide for V-RPGMaker, a SwiftUI iOS app that plays the user's own RPG Maker MV/MZ, Flash (Ruffle) and HTML5 games inside WKWebView, with on-screen gamepad, key remapping, save import/export and a bundled cheat UI. Use this skill whenever working in this repo - editing any Swift file under VRPGMaker/, changing project.yml, the GitHub Actions workflow, build_ipa.sh/.bat, the vrpg:// scheme handler, game detection or import, pad layout or key bindings, the save or cheat JavaScript bridge, or the bundled cheat/ruffle resources. Also use it for building or sideloading the unsigned IPA, adding a new engine or pad control, or debugging a game that will not load, resize, accept input or save. Consult it even for small changes, because the xcodegen setup, the JS bridge and the CI-only Ruffle bundling have non-obvious constraints.
---

# V-RPGMaker

An iOS 17+ SwiftUI app (Swift 5 mode, bundle id `com.vrpgmaker.player`) that imports a game folder or a single `.swf`/`.html`, then runs it in a `WKWebView` served through a custom `vrpg://` URL scheme. It is a **player only**: games are copied into the app sandbox and never modified on disk. Keep it that way (the cheat plugin is injected into the page at runtime, not written into the game).

## Environment reality check

- The project is built **on macOS only** (Xcode). Run `uname -s` first. On Linux/Windows there is no Swift toolchain, so you cannot compile or test. Review carefully by reading, and rely on CI for verification (see `references/build-and-ci.md`).
- The `.xcodeproj` and `Config/Info.plist` are **generated** by XcodeGen from `project.yml` and are git-ignored. Never hand-edit or commit them. Any Info.plist key, entitlement, target setting, or new resource folder goes in `project.yml`.
- `VRPGMaker/Resources/ruffle/` is intentionally empty in git (only `.gitkeep`). CI downloads Ruffle from npm into it. Locally, Flash games show "Ruffle is not bundled in this build" until you populate it (`npm i @ruffle-rs/ruffle`, copy contents in).
- `VRPGMaker/Resources/cheat/cheat.js` is a 1.2 MB minified third-party bundle. Do not `cat` or grep it broadly; treat it as a vendored blob (see "Vendored cheat plugin").

## Layout

```
VRPGMaker/
  App/VRPGMakerApp.swift        entry point, injects GameLibrary, forces dark mode
  Models/Game.swift             Engine enum (mvmz, rgss, flash, html5) + Game struct (Codable)
  Models/GameLibrary.swift      import, engine detection, persistence, removal
  Web/VRPGSchemeHandler.swift   serves vrpg://game | ruffle | cheat, Range support, SWF host page
  Web/WebGameView.swift         WKWebView setup, boot JS (__vk, viewport, CSS), resize forwarding
  Input/GameSession.swift       per-game state: key dispatch, controller, cheat toggle, JS runner
  Input/KeyBinding.swift        KeyChoice table (name -> key/code/keyCode), PadAction enum + defaults
  Input/PadLayout.swift         on-screen control layout, portrait/landscape positions, persistence
  Views/LibraryView.swift       game list, import menu, "engine not available" alert
  Views/GameScreen.swift        full-screen game, top-right menu + hide/show-controls buttons, PadOverlay (edit mode), HoldButton/DPad/Joystick
  Views/GameMenu.swift          in-game sheet + ControlsView
  Views/SavesView.swift         20 save slots, export/import via JS
  Views/CheatsView.swift        quick cheats form (gold, items, variables, switches, party)
  Resources/cheat/              vendored paramonos Cheat UI v2.2.0 (MIT)
  Resources/ruffle/             populated by CI only
project.yml                     XcodeGen spec (source of truth for the Xcode project)
.github/workflows/build-ipa.yml macOS runner: bundle Ruffle, xcodegen, unsigned build, zip IPA
build_ipa.bat / build_ipa.sh    push + run workflow + download IPA (Windows / Codespaces)
```

Read `references/architecture.md` for how the pieces connect before changing anything that crosses the Swift/JS boundary or the import pipeline.

## Core invariants

1. **All game content goes through `vrpg://`**, never `file://`. Hosts: `game` (the copied game folder), `ruffle`, `cheat`. This avoids CORS/XHR failures and gives each game a stable origin. When adding a new bundled resource root, add a host case in `VRPGSchemeHandler.serve` and pass the URL in from `WebGameView.makeUIView`.
2. **Path traversal guard**: the handler standardizes the file URL and checks `hasPrefix(root)`. Preserve this on any change to path resolution.
3. **One storage partition per game**: `WKWebsiteDataStore(forIdentifier: game.id)`. MV saves live in that game's `localStorage`; MZ saves in its IndexedDB/localforage. `GameLibrary.remove` must keep deleting the data store, the folder, and the `bindings.<uuid>` defaults. `PadLayout` is stored under `padlayout.<uuid>` and should also be cleaned up there if you touch removal.
4. **Input is synthetic keyboard events**, not touches. Everything (on-screen pad, controller, custom buttons) funnels into `window.__vk(type, key, code, keyCode)`, which dispatches a `KeyboardEvent` on `document` and overrides `keyCode`/`which` (RPG Maker reads `keyCode`). New input paths must go through `GameSession.set(_:_:)` (logical `PadAction`, remappable) or `sendKey` (raw key name) so duplicate filtering and `releaseAll()` keep working.
5. **Engine gating**: MV/MZ-only features (saves, cheats, cheat button) are guarded by `game.engine == .mvmz`. RGSS (XP/VX/Ace) games are detected but deliberately not launched (`LibraryView.open` shows an alert).
6. **Main-actor discipline**: `GameLibrary` is `@MainActor`; file copying and detection are `nonisolated static` and run in `Task.detached`. Keep disk-heavy work off the main actor.
7. **Layout fractions, not points**: `PadElement` positions are 0...1 fractions stored separately for portrait and landscape (clamped 0.04...0.96 / 0.06...0.96). Orientation is derived from `geo.size.width > geo.size.height`.

## Common tasks

### Add or change a pad action / default key
Edit `PadAction` in `KeyBinding.swift` (add `title` and `defaultKey` cases), map it in `GameSession.apply(_:)` for controllers, and add a default element in `PadLayout.default` if it needs an on-screen button. Bindings load via `PadAction.allCases` with a default fallback, so old saved bindings stay valid. For a new **default on-screen element**, follow the `cheatElement` pattern: also append it in `PadLayout.load` when missing, otherwise existing users never see it.

### Add a supported key
Append a `KeyChoice` in `KeyChoice.all` (`name`, DOM `key`, `code`, legacy `keyCode`). The `name` is what gets persisted, so do not rename existing ones.

### Add or change engine detection
`GameLibrary.detect` order matters: `index.html` (root, then `www/`) wins, then `Game.ini` (RGSS), then a `.swf` within 3 levels. MZ is identified by `js/rmmz_core.js`, MV by `js/rpg_core.js`, otherwise plain HTML5. To add an engine: extend `Engine` (label + SF Symbol icon), `detect`, the start URL in `WebGameView.makeUIView`, the `open` gate in `LibraryView`, and any menu rows in `GameMenu`. `Engine` is `Codable` and persisted in `library.json`, so never rename or remove existing cases (it would silently drop users' libraries because `load()` swallows decode errors).

### Touch the Swift/JS bridge (saves, cheats)
Use `GameSession.run(_ body:args:)`: it wraps `callAsyncJavaScript` in the **page** content world, so the body can `await` and `return`, and `args` become local variables (never string-interpolate user input into JS). Errors come back as the string `"ERROR: ..."`; callers check for that prefix. The RPG Maker globals involved ($gameParty, $dataItems, DataManager, StorageManager, Utils.RPGMAKER_NAME, ...) differ between MV and MZ; see `references/architecture.md` ("JS bridge").

### Change import behavior
Folder import copies the whole folder to `Documents/Games/<uuid>/`; single-file import copies one `.swf`/`.html` into its own UUID folder. On a failed detection the copy is deleted and an `ImportError` is thrown. Library metadata lives in `Application Support/library.json`. `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` are set in `project.yml`.

### Build, verify, ship
See `references/build-and-ci.md`. Short version: on a Mac, `brew install xcodegen && xcodegen generate && open VRPGMaker.xcodeproj`; otherwise push to `main` and let the workflow produce the unsigned `V-RPGMaker.ipa`, which is sideloaded with Sideloadly, AltStore or TrollStore.

## Vendored cheat plugin

`Resources/cheat/` is the paramonos RPG Maker MV/MZ Cheat UI, **v2.2.0, MIT**, bundled unmodified. It has no public API: it listens for a keyboard shortcut on `window` (default `c`, user-rebindable inside the plugin, matched on `keyCode` + modifiers) and mounts a `#cheat-root` div when it starts. `GameSession.toggleCheat()` therefore:
1. installs a `window.__mvMzCheatGuard` object *before* loading `cheat.css`/`cheat.js` (the plugin's official host hook: `evaluated`, `evaluateFailed`, `stageFailed`, `started`, `setOpenKey`);
2. waits for `started` and `#cheat-root`, and turns any required-stage failure into a user-visible alert (`session.cheatError`, shown in `GameScreen`) instead of failing silently;
3. brute-forces the plugin's own `setOpenKey` matcher over keyCode 8...255 and the 16 modifier combinations to find the real open key, so a rebound shortcut still works (falls back to `c`);
4. dispatches that keydown/keyup on `window`.

Rules:
- Do not edit `cheat.js`/`cheat.css` (1.2 MB minified; never `cat` or broad-grep it, target with a small Python regex instead). To upgrade, replace the files and update `VERSION.json`, keep `LICENSES.txt` and `LICENSE-paramonos-cheat-ui.txt`, and update the version in `README.md` credits.
- Keep the attribution in the README. The MIT notice must ship with the bundle.
- `bootJS` disables text selection on `*` for the games; it re-enables it for `input, textarea, [contenteditable], .cheat-root *`. iOS will not let you type into a `user-select:none` input, so keep that exception.
- Never interpolate user input into the cheat JS; pass it through `run(_:args:)`.
- A user-defined custom button bound to the open key will also toggle the cheat window. Expected, not a bug.

## Known limitations (do not "fix" accidentally)

- XP/VX/Ace (RGSS) is detected only; no runtime exists.
- Saves UI is hard-coded to 20 slots and the MV/MZ file extensions `.rpgsave` / `.rmmzsave`.
- The on-screen pad hides automatically when a `GCExtendedGamepad` is connected.
- `build_ipa.sh` sleeps 20 s then takes the most recent workflow run; it can latch onto the previous run if the new one has not registered yet.

## Conventions

Match the existing style: terse code, `// MARK:` sections, `///` doc comments only where the why is not obvious, `#"""` raw strings for embedded JS, and small single-purpose SwiftUI views. UI copy is plain English, sentence case. Do not add third-party Swift packages; the project has none.

# Architecture

## Contents
- Runtime flow
- Import pipeline and detection
- vrpg:// scheme handler
- Web view boot script
- Input pipeline
- JS bridge (saves and cheats)
- Persistence map

## Runtime flow

`VRPGMakerApp` creates one `GameLibrary` (environment object) and shows `LibraryView`. Tapping a game sets `selected`, which presents `GameScreen` as a `fullScreenCover`. `GameScreen` owns a `GameSession` (`@StateObject`) for that game and stacks: black background, `WebGameView`, `PadOverlay` (when editing, or when the pad is visible and no controller is connected), and a top-right menu button that opens `GameMenu` as a sheet. `onAppear` starts controller observation; `onDisappear` calls `session.stop()` (removes observers, clears handlers, releases held keys).

`WebGameView.makeUIView` builds the `WKWebViewConfiguration`: per-game data store, inline media, no autoplay restrictions, the `vrpg` scheme handler, and the boot user script. The start URL is `vrpg://game/<percent-encoded entry>`, or `vrpg://game/__swf.html` for Flash.

## Import pipeline and detection

`GameLibrary.importFolder` / `importFile` take a security-scoped URL, run the copy on a detached task, then append and persist. Copies go to `Documents/Games/<uuid>`.

`detect(in:fallbackTitle:)` order:
1. For `""` then `"www/"` (`detectWeb`): if `index.html` exists, title from `<title>` (fallback: folder name). `js/rmmz_core.js` -> MV/MZ with `isMZ = true`; `js/rpg_core.js` -> MV/MZ with `isMZ = false`; otherwise `webEngine` picks Tyrano, Unity, Godot, Construct, Ren'Py or HTML5 from file names and the first 256 KB of index.html.
2. `Game.ini` -> `.rgss`, title from the `Title=` line.
3. First `.swf` found while enumerating (skips descendants deeper than 3 levels) -> `.flash`, entry is the relative path.
4. `detectWeb` again on each immediate subfolder (user picked a parent folder).
5. Otherwise `nil`, and the import fails with a user-facing message.

`Game` fields: `id`, `title`, `engine`, `folderName` (the uuid string), `entry` (relative path), `isMZ`, `dateAdded`. `isMZ` selects save file extension and the JS save APIs.

## vrpg:// scheme handler

`VRPGSchemeHandler` is a `WKURLSchemeHandler`. Requests are handled on a concurrent queue; the response is delivered on the main queue, and a lock-protected `stopped` set drops responses for tasks WebKit already cancelled.

- Host `game` -> game folder; `ruffle` -> `Bundle.main` `ruffle` folder reference; `cheat` -> `cheat` folder reference. Unknown host or missing file -> 404 `text/plain`.
- Empty path -> `/index.html`.
- `/__swf.html` on host `game` is generated in code (`swfPage`): sets `RufflePlayer.config` (`publicPath: vrpg://ruffle/`, autoplay on, letterbox on), loads `ruffle.js`, creates a player filling the page, and `load`s `vrpg://game/<swf>`. It shows a notice if Ruffle is not bundled.
- On host `game`, `*.js|wasm|data|json|mem` with a `.br` or `.gz` suffix (Unity builds) are decoded in `brotli`/`gunzip` and served with the inner MIME and no `Content-Encoding`.
- With `crossOriginIsolated` (Godot only) every response gets `Cross-Origin-Resource-Policy: cross-origin` and HTML also gets COOP `same-origin` + COEP `require-corp`, for threaded Godot 4 builds.
- Always sends `Access-Control-Allow-Origin: *`, `Accept-Ranges: bytes`, `Cache-Control: no-cache`. Handles single `bytes=start-end` ranges with 206 (needed for audio/video seeking). Files are read with `.mappedIfSafe`.
- `mime(for:)` is the extension table. Add new extensions there (wrong MIME types break audio, wasm and ES modules).

## Web view boot script

`bootJS` runs at document start in the main frame only:
- defines `window.__vk(type, key, code, keyCode)` (see Input pipeline);
- at `DOMContentLoaded` forces a no-zoom viewport meta (`viewport-fit=cover`) and injects CSS: zero margins, hidden overflow, black background, disabled text selection/callout/tap highlight (text selection stays enabled for inputs and the cheat window).

`GameWebView` (subclass of `WKWebView`) dispatches `window` `resize` events at 0, 0.25 and 0.7 s whenever its bounds change, because RPG Maker's canvas only re-measures on resize (rotation, split view). The scroll view is locked: no scroll, bounce, zoom or inset adjustment.

## Input pipeline

Sources: on-screen controls (`HoldButton`, `DPadView`, `JoystickView`), game controllers (`GameController`), custom key buttons.

- `PadAction` is the logical control set (up, down, left, right, ok, cancel, shift, menu, pageUp, pageDown). `GameSession.bindings` maps each to a `KeyChoice` name, persisted per game in `UserDefaults` under `bindings.<uuid>`. Defaults: arrows, Z, X, Shift, Escape, Q, W (RPG Maker's keyboard defaults).
- `set(action, down)` ignores repeats (`held` set), resolves the key via `KeyChoice.named`, and evaluates `window.__vk&&window.__vk(...)`.
- `sendKey(name, down)` does the same for raw key names (custom buttons) with its own `heldKeys` set.
- `apply(_ gp:)` maps `GCExtendedGamepad` to actions: d-pad or left stick (threshold 0.5), A=ok, B=cancel, X=shift, Y/Menu=menu, shoulders=page up/down. It recomputes the full wanted set each change, so releases are implicit.
- `DPadView` and `JoystickView` both emit 4-way `PadAction`s from a drag (joystick adds a following knob; diagonals are two simultaneous directions).
- `PadLayout` holds `elements`, `opacity`, `joystick`, `snap`, `haptics`, persisted as JSON under `padlayout.<uuid>` (older saves without the newer keys still decode). Element kinds: `move`, `action` (value = PadAction raw value), `key` (value = KeyChoice name), `cheat` (MV/MZ only). Edit mode (`session.editingLayout`) swaps controls for draggable, pinch-resizable dashed boxes plus a two-tab panel: Control (size 36...240, opacity, label max 6 chars, key, sticky, visibility, nudge, duplicate, delete) and Layout (joystick, opacity, snap, vibration, mirror/smaller/larger, add Key or Action button, reset). Sticky buttons are handled inside `HoldButton`; haptics use `UIImpactFeedbackGenerator`.

## JS bridge (saves and cheats)

All calls use `GameSession.run`, which uses `callAsyncJavaScript` in the page world. The game must be loaded; otherwise `webView` is nil or the globals are missing and an `ERROR:` string returns.

MV vs MZ is decided in JS by `Utils.RPGMAKER_NAME === 'MZ'`.

Saves (`SavesView`):
- List: slots 1...20 via `DataManager.savefileInfo(i)` (MZ) or `loadSavefileInfo(i)` (MV); returns title, playtime, timestamp.
- Export: MZ -> `await StorageManager.loadZip(DataManager.makeSavename(i))`; MV -> `localStorage.getItem(StorageManager.webStorageKey(i))`. The string is written to `file<N>.rmmzsave|rpgsave` in the temp dir and shared via `UIActivityViewController`.
- Import: MZ validates with `StorageManager.zipToJson`, writes with `saveZip`; MV validates with `LZString.decompressFromBase64` + `JsonEx.parse`, writes to `localStorage`. Then rebuilds the global info entry (title, character/face sprites for the party, playtime from `_framesOnSave`, timestamp) so the slot appears in the game's own load screen.

Cheat UI window (`GameSession.toggleCheat`): see "Vendored cheat plugin" in SKILL.md. Result strings other than `ok` are shown in an alert via `cheatError`.

Quick cheats (`CheatsView`): small JS snippets over `$gameParty`, `$dataItems`, `$gameVariables`, `$gameSwitches`, `$gameActors`. Each is wrapped in `try/catch` and must return `'ok'` on success.

## Persistence map

| What | Where |
|---|---|
| Game files | `Documents/Games/<uuid>/` |
| Library index | `Application Support/library.json` |
| Key bindings | `UserDefaults` `bindings.<uuid>` |
| Pad layout | `UserDefaults` `padlayout.<uuid>` |
| In-game saves/settings | per-game `WKWebsiteDataStore(forIdentifier: uuid)` |

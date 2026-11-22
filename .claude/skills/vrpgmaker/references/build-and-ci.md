# Build and CI

## Why CI
iOS apps compile only on macOS. The repo is set up so a Windows or Linux user can still produce an IPA through a free GitHub macOS runner. The IPA is **unsigned** (`CODE_SIGNING_ALLOWED=NO`); install it with Sideloadly, AltStore or TrollStore.

## On a Mac
```bash
brew install xcodegen
xcodegen generate
open VRPGMaker.xcodeproj
```
Optional Flash support: `npm i @ruffle-rs/ruffle` somewhere, then copy `node_modules/@ruffle-rs/ruffle/.` into `VRPGMaker/Resources/ruffle/`. That folder is git-ignored apart from `.gitkeep`.

## project.yml essentials
- Deployment target iOS 17.0 (required by `WKWebsiteDataStore(forIdentifier:)`). Swift 5.0 language mode. Universal iPhone and iPad.
- `Resources/ruffle/**` and `Resources/cheat/**` are **excluded** from normal sources and re-added with `type: folder`. This makes them folder references, so the directory structure is preserved in the bundle and `Bundle.main.url(forResource: "ruffle", withExtension: nil)` works. If you add another bundled web root, copy this pattern.
- Info.plist is generated from `info.properties` into `Config/Info.plist` (git-ignored; `Config/` is empty in git). Orientation lists, `UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace` and the display name live here.
- Version numbers: `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` under `settings.base`.

## Workflow: .github/workflows/build-ipa.yml
Triggers: push to `main`, or manual `workflow_dispatch`. Steps on `macos-latest`: checkout, Node 20, install `@ruffle-rs/ruffle` into `/tmp/rf` and copy it into `Resources/ruffle`, `brew install xcodegen`, `xcodegen generate`, `xcodebuild` (Release, `iphoneos` SDK, derived data in `build/`, signing disabled), copy the built `.app` into `Payload/` and `zip -qry V-RPGMaker.ipa Payload`, upload artifact `V-RPGMaker-ipa`.

If a build fails because a Swift file does not compile, the error is only visible in the Actions log: `gh run view <id> --log-failed`.

## Scripts
- `build_ipa.bat` (Windows): checks `git` and `gh`, logs in if needed, inits the repo on `main`, creates a **private** repo `V-RPGMaker` if no `origin`, pushes, triggers the workflow, waits ~15 s, finds the latest run, watches it, downloads artifact to `build\V-RPGMaker.ipa`. Uses CRLF line endings; keep them.
- `build_ipa.sh` (Codespaces/Linux): commit, push, sleep 20, take the latest run id, watch, download to `./V-RPGMaker.ipa`. It also triggers via the push to `main`, so it does not call `workflow_dispatch`.

## Verification checklist when you cannot compile
1. Re-read every changed Swift file for missing imports (`SwiftUI`, `WebKit`, `GameController`, `UniformTypeIdentifiers`), actor isolation (`@MainActor` on `GameLibrary`, `nonisolated static` helpers) and exhaustive `switch` over `Engine`/`PadAction`/`PadElement.Kind`.
2. If you added a file, confirm it sits under `VRPGMaker/` (XcodeGen picks it up automatically; no project edits needed).
3. If you added a resource folder, confirm the `excludes` + `type: folder` pair in `project.yml`.
4. Push and watch the workflow; a green run proves it compiles, not that it behaves correctly. Say so plainly when reporting.

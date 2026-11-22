# V-RPGMaker

Player for your own RPG Maker MV/MZ, Flash (Ruffle) and HTML5 projects on iOS.

## Build the IPA from Windows
1. Install Git (https://git-scm.com) and GitHub CLI (https://cli.github.com).
2. Double-click `build_ipa.bat`. It creates a private GitHub repo, pushes this project,
   builds on a macOS runner, and downloads `build\V-RPGMaker.ipa`.
3. The IPA is unsigned. Install with Sideloadly, AltStore or TrollStore.

## Build on a Mac
    brew install xcodegen && xcodegen generate && open VRPGMaker.xcodeproj
(Optional for Flash: `npm i @ruffle-rs/ruffle` and copy its contents into VRPGMaker/Resources/ruffle.)

## Status
- MV/MZ, HTML5, Flash (Ruffle), saves import/export, cheats, remappable on-screen pad, controller support
- XP/VX/Ace (native RGSS): not included. Games are detected, but opening one shows a notice.

## Credits
The 🎮 cheat button opens the **RPG Maker MV/MZ Cheat UI** plugin by paramonos (MIT license),
bundled unmodified from release v2.2.0: https://github.com/paramonos/RPG-Maker-MV-MZ-Cheat-UI-Plugin
Its license and third-party notices are in `VRPGMaker/Resources/cheat/`.
It is loaded into the page on first tap, so games are never modified on disk.

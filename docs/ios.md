# iOS prototype

This branch adds an iPhone and iPad target using SDL3's Metal renderer, with on-screen touch controls for offline play. The previous build has been confirmed working on an iPhone with touch and an Xbox controller. New features still need hands-on device validation.

The build can run on a hosted macOS GitHub Actions runner, so you do not need to own a Mac to compile it. Installing the resulting app on a physical iPhone or iPad is a separate signing step.

## Recommended phone setup

[Download the 0.4.0 iPhone build ZIP](https://github.com/spl01nkuh/3sx/actions/runs/42730771313/artifacts/13725121246). Both iPhone and simulator builds passed, including native preview/tester/editor compilation, controller/touch sensitivity and motion input through the game pipeline, and Apple bundle recognition. All nine effects passed actual offscreen Metal rendering. Hands-on device validation of the new interface and individual controller mappings remains outstanding.

1. Download and extract the device build artifact. It contains `3SX-unsigned.ipa` and `INSTALL.txt`.
2. Sign and install the IPA with iLoader or your usual sideloading app.
3. Put the extracted `SF33RD.AFS` in Files on the phone, open 3SX, and tap **Import SF33RD.AFS**.

The phone copies and verifies the archive. No desktop AFS script is required.
When updating, update the existing app with the same signing account; avoid deleting the app if you want to retain its imported data and settings.

## iOS options

Tap the small gear in the top-right safe area. It hides after five seconds without touch input; touch anywhere to reveal it again, including when touch controls are disabled. It stays visible while touching or using the menu. The game and audio pause while the menu or control editor is open. Settings save automatically between launches. The Filter page previews changes immediately; gameplay resumes with those settings when the menu closes.

- Toggle touch controls without disconnecting controllers.
- Choose **Hybrid**, **Stick**, or **D-pad** for the touch direction control.
- Open **Edit controls & custom buttons** to drag and resize controls, or add custom simultaneous button combinations.
- Choose Sharp Bilinear, CRT zfast, CRT Lottes, CRT Caligari, CRT EasyMode, Composite TV, CRT Aperture, CRT Geom, or CRT Hyllian, with adjustable strength; Off is the default. The Filter menu keeps a preview of the paused game visible above the list, with a strength slider and **Original** comparison.
- Set 4:3, original pixel aspect, or Fill. **Screen size** scales both axes from 25–100%; separate **Screen width** and **Screen height** sliders stretch each axis from 25–200%. Values above 100% zoom and can crop the picture. Set all three to 100% to restore the fitted aspect ratio.
- Adjust stick sensitivity (1–100%, default 50%) and radial dead zone (0–35%). This now applies to on-screen **Stick** and **Hybrid** controls as well as controllers. Higher sensitivity activates a direction with less stick travel; full-throw movement speed stays the same because the game uses digital directions. It works with the game's legacy analog-stick option enabled or disabled. D-pads are unaffected.
- Open **Sticks → Test stick sensitivity** to compare actual controller raw axes with activated directions, try the on-screen control, and adjust sensitivity without leaving the test. A controller exposing only D-pad buttons has no analog travel to adjust; the tester identifies its axes and mapping.
- Reset just iOS options without deleting game data.

All 28 Carlos presets and eight GLSL sources remain in `third_party_sources/carlos-crt/`, with attribution. Pinned original Lottes, zfast, Caligari, Aperture, Geom and Hyllian sources and licenses are in `third_party_sources/libretro-crt/`. The menu provides nine single-pass Metal adaptations plus Off: crisp scaling, flat scanlines, curved Gaussian beams, phosphor dots, slot mask, YIQ color bleed/noise, Aperture glow, Geom glass curvature/corners, and sharp Hyllian reconstruction. Multi-pass and feedback presets requiring additional libretro dependencies remain retained as source for future integration. A shader initialization failure is shown in the filter menu instead of silently pretending filters work.

The in-menu preview copies the last rendered game canvas and uses the same production fragment shader as gameplay. It does not advance the game or play shortcut sequences. The picture remains frozen while animated filter noise and settings can change. Preview appearance and performance at its smaller resolution can differ from full-screen output.

To check a controller whose response appears unchanged, open **Test stick sensitivity**, hold its stick partway out, and compare 1% with 100%. The raw axis values should stay the same while the tuned response and activated direction change. If raw values stay at zero, the controller name and axis availability show whether an analog stick is being received. The touch-stick bypass is fixed in 0.4.0; physical controllers pass both legacy-analog input tests, but individual controller mappings still need hardware confirmation.

## Touch layout and custom buttons

In **iOS Options → Edit controls & custom buttons**, drag any control to move it. Tap a control to adjust its size and position precisely. **Controls** lists every control, including ones covered by another control. The direction **Style** menu offers the same Hybrid / Stick / D-pad choices as settings. A normal stick uses a circular dead zone and a movable thumb; the hybrid preserves the original sliding control. All three produce the game's eight digital movement directions.

Use **Add** to create up to 16 custom buttons. Give each a name and select one or more bindings from the six attacks, Start, Select, and four directions. For example, select LP + MP + HP for a PPP button. Without a motion shortcut these are simultaneous holds. Buttons follow the game's current mapping. **Size** includes a slider and an exact percentage input (55–200%), so several buttons can share a size. Tap the keyboard's **Done** to commit the number. Custom buttons can be deleted, and **Reset** restores the layout after confirmation. Layout and custom buttons save separately from the other iOS options.

Custom buttons also have a **Motion shortcut** picker with eight sequences:

- Quarter circle forward: ↓ ↘ →
- Quarter circle back: ↓ ↙ ←
- Left to down: ← ↙ ↓
- Dragon punch forward: → ↓ ↘
- Dragon punch back: ← ↓ ↙
- Full circle: 360°
- Half circle forward: ← ↙ ↓ ↘ →
- Half circle back: → ↘ ↓ ↙ ←

Directions are screen-relative; **Mirror left / right** reverses the entire motion. The selected attack buttons finish the motion, or unselect them for a direction-only shortcut. Tap once to play; lifting your finger lets the sequence complete, and holding does not repeat. A new shortcut replaces the current one. Playback uses game frames rather than a wall-clock timer, so extra input polling does not speed it up. Motion directions temporarily override manual touch directions, while other attack buttons can still be pressed. Opening iOS Options, hiding controls, or a system touch cancellation clears playback. A 360 finishes its attack when all four cardinal directions have been entered and holds it through the remaining rotation to limit jump delay. Move recognition still depends on the selected character, game state and button mapping; test shortcuts in training mode.

## Optional private app icon

Personal icons are deliberately excluded from the public repository and build artifacts. The device ZIP includes a generic local-only `personalize-ios-ipa.py` helper, which uses file pickers to choose your IPA, icon, and private output file. The tool makes no uploads or network calls.

Install Python with Tk support, install Pillow once, then run the helper from its extracted folder:

```powershell
py -3 -m pip install pillow
py -3 personalize-ios-ipa.py
```

Select the downloaded IPA, your local `.ico` or `.png`, and a new output name. Sign and install that output with iLoader. Keep personal image files and the personalized IPA outside your public repository. The supplied image is converted locally into the required iPhone/iPad PNG sizes; it is never part of the public CI build.

## Requirements

- For the hosted build: a GitHub repository containing this branch, with GitHub Actions enabled. Runner availability and usage limits depend on your GitHub account.
- An iPhone or iPad running iOS/iPadOS 15 or newer.
- A sideloading tool, such as Sideloadly or an AltStore-style installer, that signs the app with your Apple account during installation. Signing expiry and renewal depend on that tool and account.
- Your own legally obtained PS2 game data: `SF33RD.AFS` from *Street Fighter III: 3rd Strike* or *Street Fighter Anniversary Collection*.

An external iOS-compatible Xbox, PlayStation, or MFi controller is optional.

## Game data

Extract `THIRD/SF33RD.AFS` from your PS2 disc image on your computer; some disc layouts put `SF33RD.AFS` in the root directory. The iOS importer accepts the extracted AFS archive. It does not read a PS2 ISO or use an arcade ROM ZIP as a replacement for that archive.

The iOS build validates the archive against the upstream SHA-256:

```text
f9fa50f3a124ec9fa9465aa9c8546c2d867887eb39f711a070762a0324ba5604
```

You can check the extracted file on Windows in PowerShell:

```powershell
Get-FileHash -Algorithm SHA256 C:\path\to\SF33RD.AFS
```

Or on macOS/Linux:

```sh
shasum -a 256 /path/to/SF33RD.AFS
```

The source ZIP contains no game data. You can import your archive after installation, or include it in a personal IPA using the steps below. Neither method needs the AFS uploaded to GitHub.

## Build without a Mac

If you downloaded this port from the `ios-port` branch of a fork, pushes to that branch start **Build (iOS)** automatically when GitHub Actions is enabled. GitHub may initially disable Actions in a new fork: open **Actions** and enable workflows if prompted. The manual **Run workflow** button requires this workflow to be present on the repository's default branch. A build failure does not prevent downloading the source ZIP from **Code → Download ZIP**.

1. Extract the source ZIP. Put its contents in your own GitHub repository or fork, including `.github/workflows/build_ios.yml`. `CMakeLists.txt` must be at the repository root. Forking upstream alone does not add the port changes.
2. Open the repository's **Actions** tab and enable workflows if prompted.
3. Select **Build (iOS)**, choose **Run workflow**, and select the branch containing the port.
4. Open the completed run. Under **Artifacts**, download **3SX-iOS-device-unsigned** and extract its ZIP to get `3SX-unsigned.ipa`.

The workflow uses a hosted macOS runner and builds the dependencies automatically. It also creates a **3SX-iOS-simulator** artifact for Mac-based simulator testing; use the device IPA for sideloading onto your phone or tablet. If the build fails, the run's logs and `ios-device-build-log` artifact contain the compiler error to investigate. The recommended download above points to the latest verified device build.

If starting with a new repository, create an empty one on GitHub without adding a README. Install Git on your computer, open a terminal in the extracted source folder, and run these commands, replacing the repository URL with your own:

```sh
git init -b main
git add .
git commit -m "Add 3SX iOS prototype"
git remote add origin https://github.com/YOUR-USERNAME/YOUR-REPOSITORY.git
git push -u origin main
```

If Git asks for your name and email, configure them as instructed by Git, then retry the commit. Complete GitHub's sign-in prompt when pushing. Keep the hidden `.github` directory: it contains the hosted build workflow. Your game archive stays outside the repository.

## Advanced: include the AFS in your IPA without uploading it

1. Extract `SF33RD.AFS` from your `.7z` with 7-Zip on your computer. The helper needs the extracted AFS, not the `.7z` archive.
2. Download `3SX-unsigned.ipa` from the hosted build, as described above.
3. Install Python 3, then open a terminal in the extracted source folder and run:

```powershell
py -3 tools/bundle-ios-afs.py C:\path\to\3SX-unsigned.ipa C:\path\to\SF33RD.AFS --output C:\path\to\3SX-with-data.ipa
```

On macOS or Linux, use `python3` in place of `py -3`. Put quotation marks around paths containing spaces.

The helper checks the AFS checksum and embeds it as `Payload/3SX.app/game-data/SF33RD.AFS`. It processes the large file in chunks and leaves the original IPA unchanged. It does not upload your archive. Use a new output filename; existing output files are not overwritten unless you pass `--force`.

4. Give **3SX-with-data.ipa** to Sideloadly or your AltStore-style tool. That tool signs the modified IPA during installation. Add the AFS before this signing step, since changing app contents invalidates an existing signature.

The app checks for valid data already in Documents, then for the bundled archive. A valid bundled archive skips the import screen and is read directly from the app bundle without creating a second large copy on the phone.

## Install and run

Download the unsigned IPA from the completed hosted build and import it into your sideloading tool. Let that tool sign and install it using your Apple account. An unsigned IPA cannot be installed directly by tapping it in Files. No App Store submission or signing certificates in this repository are needed for this workflow.

On first launch, tap **Import SF33RD.AFS** and select the extracted archive from Files. The app copies and validates it before placing it at `Documents/resources/SF33RD.AFS` inside its sandbox. A failed or cancelled import can be retried. Alternatively, use Files > On My iPhone/iPad > 3SX, or Finder file sharing, to place the archive in the app's `resources` folder, then relaunch the app. Keep the filename `SF33RD.AFS`.

The default landscape touch overlay has a hybrid direction control on the left, **LP MP HP / LK MK HK** on the right, and **SELECT / START** near the bottom center. It supports holding a direction while pressing multiple attack buttons. Attack labels describe the game's default button assignment; remapping buttons in the game changes their actions. Use the gear menu to hide controls, change direction style, or edit the layout.

Touch input controls player 1. You can also pair a supported controller in the device's Bluetooth settings. Configuration and keymap files live in the app's Documents directory.

## Optional local Mac build

Local compilation needs full Xcode with its iOS SDK, CMake 3.29 or newer, and Git. Command Line Tools alone cannot build an iOS app. Use a recent Xcode whose Apple Clang supports the project's C23 code, including enums with explicit underlying types. Check that Xcode is selected:

```sh
xcode-select -p
xcrun --sdk iphoneos --show-sdk-path
xcodebuild -version
```

If the selected directory points to `/Library/Developer/CommandLineTools`, select the full Xcode installation in Xcode's Settings > Locations > Command Line Tools.

Run from the repository root:

```sh
bash tools/build-ios.sh device
```

To include an AFS during a local Mac build instead of using the IPA helper:

```sh
IOS_AFS_FILE="/path/to/SF33RD.AFS" bash tools/build-ios.sh device
```

The build validates the archive and bundles it under `game-data/SF33RD.AFS`. `IOS_AFS_FILE` is optional; leaving it unset produces the usual app with an import screen. The equivalent CMake option is `THREESX_IOS_AFS_FILE`.

For a simulator build instead:

```sh
bash tools/build-ios.sh simulator
```

The unsigned device IPA is written to `build/ios-device/3SX-unsigned.ipa`; the generated device project is `build/ios-device/3sx.xcodeproj`. The simulator app is `build/ios-simulator/Release-iphonesimulator/3SX.app`.

The script downloads and builds the iOS dependencies itself; do not run the desktop `build-deps.sh` for this target. To install through Xcode, configure a signed build with your development team:

```sh
IOS_DEVELOPMENT_TEAM=YOURTEAMID bash tools/build-ios.sh device \
    -DTHREESX_IOS_BUNDLE_IDENTIFIER=com.example.threesx
```

Open the generated project, select the `3sx` scheme and your connected device, then build and run. Signing requires a team available to your Xcode account. Run `bash tools/build-ios.sh --help` for build-directory, architecture, and configuration overrides.

## Current scope and validation

- Metal rendering, native AFS import, sandbox paths, on-screen controls, and background/foreground handling are included in the prototype.
- Netplay, replay statcheck, and the desktop debug UI are excluded from the initial iOS target.
- The iOS menu adjusts stick response, screen geometry, filters and touch layout. Button remapping remains in the game's own options; custom buttons can hold several mapped buttons together.
- Hosted Xcode Release builds for iPhone and simulator pass, including UIKit and CommonCrypto compilation and Apple bundle recognition. Version 0.3.0 passed regression tests through the real controller-to-game input path, portable layout and display tests, and actual Metal image rendering for every filter at multiple strengths. The rendering test reports an explicit skip if a future runner has no GPU; this verified run did have one.
- The user confirmed signed installation and gameplay with touch and Xbox input on the previous build. The new editor, control styles, manual stretching and filters still need physical-device feedback. Frame-rate measurements remain outstanding.

Additional Linux host checks passed with GCC and Clang for C syntax in Release and Debug, portable touch direction/chord/controller merging, malformed AFS headers, bundle resource selection, build-script syntax, plist parsing, and CMake configuration logic. Host C checks use `CHECKSUM=0`; the hosted Xcode builds validate the Apple-specific compilation. The source is based on upstream commit `6187364`.

For the update, test all three direction styles, custom button combinations, stretched/zoomed display sizes, filter visibility, idle gear hiding, and background/resume on a physical device. Simulator testing cannot establish device performance or controller compatibility.

Bundled data in version 0.1.1 uses `game-data`, avoiding Apple's reserved bundle Resources directory. Re-download both the updated IPA and helper before recreating a preloaded IPA from an older build.

The corrected iPhone build passed the Apple Foundation bundle-recognition check with preloaded data present in [run 42338032772](https://github.com/spl01nkuh/3sx/actions/runs/42338032772). Phone-side AFS import is the recommended setup and has been confirmed working by the user.

Version 0.2.0 build 3 was verified in [run 42341591104](https://github.com/spl01nkuh/3sx/actions/runs/42341591104). The public ZIP was inspected to confirm that it contains the generic local-only personalization helper and no personal icon or AFS.

Version **0.3.0 build 4**, source commit `9a8b34fa0bb6fd0f1177ddccd8f7fbc20fbbcc9a`, was verified in [run 42440558011](https://github.com/spl01nkuh/3sx/actions/runs/42440558011). The downloaded IPA passed ZIP integrity, arm64/iPhoneOS metadata, version, and production-shader checks. It contains no AFS archive or private app icon. The ZIP includes only the IPA, generic local personalization helper, and installation instructions. [Actual Metal comparison images and metrics](https://github.com/spl01nkuh/3sx/actions/runs/42440558011/artifacts/13601268768) are available separately; these use an original synthetic fixture, with no game assets.

Version **0.4.0 build 5**, source commit `55f2699172fc0198184d0426c2e6bd1ef39e78a9`, passed both Apple jobs in [run 42730771313](https://github.com/spl01nkuh/3sx/actions/runs/42730771313). The downloaded IPA passed ZIP integrity, bundle/version/arm64 metadata, native-feature class, and packaged-shader checks. The public ZIP contains the IPA, generic local icon helper and instructions, with no AFS or private icon. [Actual Metal images, metrics and filter manifests](https://github.com/spl01nkuh/3sx/actions/runs/42730771313/artifacts/13724741882) cover nine effects at multiple strengths; every pair differs and strength zero matches Off exactly. Portable tests, real input-pipeline sensitivity/motion tests, and 700 C translation units checked with Clang in Release and Debug also passed. These checks verify emitted input sequences; recognizing a specific character's special move and the live menu's appearance still need device testing with game data.

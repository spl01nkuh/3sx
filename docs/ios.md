# iOS prototype

This branch adds an experimental iPhone and iPad target using SDL3's Metal renderer, with on-screen touch controls for offline play. Release builds for iPhone and simulator pass on a hosted Mac. Signing, installation, and gameplay testing on a physical device are still required.

The build can run on a hosted macOS GitHub Actions runner, so you do not need to own a Mac to compile it. Installing the resulting app on a physical iPhone or iPad is a separate signing step.

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

The workflow uses a hosted macOS runner and builds the dependencies automatically. It also creates a **3SX-iOS-simulator** artifact for Mac-based simulator testing; use the device IPA for sideloading onto your phone or tablet. If the build fails, the run's logs and `ios-device-build-log` artifact contain the compiler error to investigate. Both Release jobs passed in [this verified build](https://github.com/spl01nkuh/3sx/actions/runs/42334103610).

For the corrected 0.1.1 build, [download the device artifact ZIP](https://github.com/spl01nkuh/3sx/actions/runs/42338032772/artifacts/13560114086) while signed in to GitHub. Extract it to obtain `3SX-unsigned.ipa`. The IPA was checked for ZIP integrity, an arm64 iPhone executable, iOS 15.0 minimum, and the packaged Metal shaders and assets. It contains no AFS archive; use the local helper below to add yours before signing, or import it after installation.

If starting with a new repository, create an empty one on GitHub without adding a README. Install Git on your computer, open a terminal in the extracted source folder, and run these commands, replacing the repository URL with your own:

```sh
git init -b main
git add .
git commit -m "Add 3SX iOS prototype"
git remote add origin https://github.com/YOUR-USERNAME/YOUR-REPOSITORY.git
git push -u origin main
```

If Git asks for your name and email, configure them as instructed by Git, then retry the commit. Complete GitHub's sign-in prompt when pushing. Keep the hidden `.github` directory: it contains the hosted build workflow. Your game archive stays outside the repository.

## Include the AFS in your IPA without uploading it

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

The landscape touch overlay has a sliding D-pad on the left, **LP MP HP / LK MK HK** on the right, and **SELECT / START** near the bottom center. It supports holding a direction while pressing multiple attack buttons. Attack labels describe the game's default button assignment; remapping buttons in the game changes their actions. There is no touch layout editor or hide toggle yet.

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
- An in-app controller configuration screen is not implemented.
- Hosted Xcode Release builds for iPhone and simulator pass, including UIKit and CommonCrypto compilation and the portable touch/IPA helper tests. The verified code commit is `b6da0bb292c897fffae647bacff1ffd81ba119b3`.
- Signed installation, frame-rate measurement, audio output, and full gameplay on a physical device remain untested.

Additional Linux host checks passed with GCC and Clang for C syntax in Release and Debug, portable touch direction/chord/controller merging, malformed AFS headers, bundle resource selection, build-script syntax, plist parsing, and CMake configuration logic. Host C checks use `CHECKSUM=0`; the hosted Xcode builds validate the Apple-specific compilation. The source is based on upstream commit `6187364`.

Before treating the port as playable, test archive import, menus, a complete match with simultaneous touch inputs, audio interruptions, landscape rotation, and background/resume on a physical device. Simulator testing can help with startup and import, but cannot establish device performance or controller compatibility.

Bundled data in version 0.1.1 uses `game-data`, avoiding Apple's reserved bundle Resources directory. Re-download both the updated IPA and helper before recreating a preloaded IPA from an older build.

The corrected iPhone build passed the Apple Foundation bundle-recognition check with preloaded data present in [run 42338032772](https://github.com/spl01nkuh/3sx/actions/runs/42338032772). Physical-device installation still requires confirmation.

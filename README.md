# MLRC ACCS

This repository contains a Flutter-based prototype for an audio/video (AV) watcher and control terminal designed to manage streaming or mirroring workflows across USB and Wi‑Fi transports. The app presents a desktop-style terminal dashboard with transmission controls, event logs, and a debug inspector panel. The panel can capture the local display on demand and discover opted-in app peers on the local network.

## Project purpose

The codebase is best understood as a UI-oriented prototype for a screen-sharing / remote-display system. It focuses on the operator experience and low-level signal flow modeling rather than a production-ready media stack. The interface exposes controls for:

- toggling between standby, transmit, and receive modes
- choosing the communication path (USB preferred, Wi‑Fi fallback)
- observing streaming lifecycle events in a live terminal log
- inspecting real local screen captures and discovered opted-in peers in debug mode

## Repository layout

- `screen_mirror/` — the Flutter application source
- `screen_mirror/packages/` — locally maintained compatibility copies of Android plugins that need Gradle updates
- `config/` — environment configuration files and setup/test helper scripts
- `run_app.ps1` — Windows launcher for the app in debug or production mode
- `run_app.sh` — Linux launcher for the app in debug or production mode
- `LICENSE` — project license

## Technology stack

- Dart / Flutter SDK
- Material Design UI components
- JSON-driven environment configuration via `--dart-define-from-file`
- PowerShell and Bash startup scripts for local execution
- Rust toolchain setup and verification scripts

## Application overview

The main application entry is in `screen_mirror/lib/main.dart`. It creates a `WatcherTerminalApp` with a dark-themed dashboard named "AV Watcher Control Terminal". The dashboard includes:

- status cards for operation mode, communication channel, and stream status
- action buttons to start or stop transmitting or receiving
- a live event stream console that logs simulated network and display activity
- an optional debug inspector panel for on-demand local screen capture, LAN peer discovery, and host-side ADB device listing

The app uses compile-time environment variables loaded from JSON config files:

- `OPERATION_MODE`
- `ENABLE_DEBUG_LOGS`
- `SHOW_DEBUG_PANEL`
- `ENVIRONMENT`

These values are defined in the configuration profiles under `config/` and passed into the Flutter app at runtime.

## Configuration profiles

The project ships with two profile files:

- `config/config_debug.json` — debug mode with logs and debug panel enabled
- `config/config_production.json` — production mode with logs and panel disabled

Example debug profile:

```json
{
  "OPERATION_MODE": "Standby",
  "ENABLE_DEBUG_LOGS": true,
  "SHOW_DEBUG_PANEL": true,
  "ENVIRONMENT": "debug"
}
```

The runtime startup scripts load the selected config and invoke Flutter with `--dart-define-from-file`.

## Setup, build, and run

The launchers are the one-stop developer entrypoints. They check for Flutter and Rust, run the matching setup scripts if either is missing, select an environment profile, and build or run for a supported target. The Flutter SDK installed by the setup script is kept in `config/flutter/`.

### Windows host

Run these commands from the repository root in PowerShell:

```powershell
.\run_app.ps1 debug                 # Run on Windows desktop
.\run_app.ps1 prod windows build    # Build a production Windows desktop app
.\run_app.ps1 debug android         # Run on a connected Android device/emulator
.\run_app.ps1 prod android build    # Build a production APK
```

### Linux host

Run these commands from the repository root:

```bash
./run_app.sh debug                  # Run on Linux desktop
./run_app.sh prod linux build      # Build a production Linux desktop app
./run_app.sh debug android         # Run on a connected Android device/emulator
./run_app.sh prod android build    # Build a production APK
```

The command format is:

```text
run_app [debug|prod] [host|windows|linux|android] [run|build]
```

Show launcher-specific usage and examples with `.\run_app.ps1 -Help` in PowerShell or `./run_app.sh --help` in Bash. Help exits before checking or installing any tools.

Target defaults to `host` and action defaults to `run`. Windows desktop builds must run on Windows; Linux desktop builds must run on Linux. Android run requires exactly one authorized Android device or running emulator; the launcher checks ADB and explicitly targets that device instead of offering desktop or web targets. Unlock a USB-connected device and accept its USB debugging prompt, or start an emulator in Android Studio Device Manager first. Android builds do not require a connected device and produce an APK under `screen_mirror/build/app/outputs/flutter-apk/`. Production APKs currently use Flutter's debug signing configuration and are not ready for store distribution.

### What setup automates

- Flutter stable SDK is installed under `config/flutter/` if no SDK is available.
- Rust is installed if missing, using the platform scripts in `config/setup/`.
- Android SDK Platform-Tools (ADB) are checked for Windows and Linux desktop runs and Android targets. If ADB is unavailable, the launcher downloads the official Platform-Tools into `config/adb/` and adds them to the current process's `PATH`.
- Android builds check the NDK version required by the selected Flutter SDK and install it through the Android CLI or `sdkmanager` if it is missing.
- Linux desktop dependencies are installed through `apt` when missing. This requires an apt-based distribution and `sudo`.
- For Windows desktop builds, Visual Studio 2022 with the **Desktop development with C++** workload and C++ ATL is required. The launcher installs Visual Studio Build Tools with `winget` if Visual Studio is absent, or adds the missing components to an existing Visual Studio installation.
- Windows desktop builds also require symbolic-link creation. The launcher checks this before setup; if the check fails, enable Developer Mode in Settings (`start ms-settings:developers`) or run PowerShell as an administrator, then rerun.
- For Android, Windows automatically installs Android Studio with `winget` if the Android SDK is absent. On Linux, Android Studio is installed with `snap` when available. In either case, open Android Studio once, finish its setup wizard, install the Android SDK, Platform-Tools, and Command-line Tools (latest), then rerun the launcher. Android SDK licenses are presented for acceptance by the launcher.

Tool installation requires network access. Some setup steps require administrator privileges or `sudo`. Android devices need USB debugging enabled and authorization on the device; emulators must be started before running the Android target.

The setup helpers can also be run directly:

- `config/setup/setup_flutter.ps1` / `config/setup/setup_flutter.sh`
- `config/setup/setup_rust.ps1` / `config/setup/setup_rust.sh`
- `config/setup/setup_adb.ps1` / `config/setup/setup_adb.sh`
- `config/setup/setup_ndk.ps1` / `config/setup/setup_ndk.sh`

The `config/test/test_rust.ps1` and `config/test/test_rust.sh` scripts compile and run a small Rust verification program in four parallel instances.

## Debug panel features and limits

The debug panel uses real OS capture and device discovery APIs, but these features are separate from the prototype's simulated AV transmit/receive controls:

- **Screen capture:** click **Capture** to request a single current-screen preview. Windows and Linux use the desktop screenshot API. Android invokes the OS screen-capture consent flow, briefly records to the app-private cache, extracts one frame, and deletes the temporary recording. The preview is kept in app memory only and is discarded when replaced or when the app exits. Android requires the user to approve the system prompt for each capture session; audio capture is not enabled.
- **Wi-Fi discovery:** click **Discover** to advertise this app and discover other MLRC instances on the same LAN using mDNS service type `_mlrc-accs._tcp`. Discovery is opt-in and limited to peers advertising that service; it does not sweep the subnet or identify arbitrary devices. The app advertises a small TCP presence endpoint that returns `MLRC-ACCS/1`; it does not carry screen frames.
- **USB discovery:** on Windows and Linux hosts, **Discover** runs `adb devices -l` and shows ADB-reported devices, including their authorization state. The desktop launchers set up Platform-Tools if needed. Connect the device, enable USB debugging, and authorize the host on the device. An Android app cannot run host-side ADB to enumerate its own USB connection.

Discovery requires devices to be on the same network with multicast/mDNS allowed. For Android, local network access is declared in the manifest. The same application must be running with discovery active on another device for that device to appear. The prototype's transmit/receive buttons and their event stream remain simulated; discovery does not yet establish a video stream.

Android screen capture support raises the app's minimum Android SDK level to API 23 (Android 6.0).

The Android Gradle scripts for `flutter_screen_recording` and `video_thumbnail` are maintained as local copies under `screen_mirror/packages/` because their published scripts use obsolete repositories and Gradle APIs. Their upstream MIT license files are retained alongside the source.

## Important implementation note

The current code is a prototype rather than a complete, production-grade media transport system. The debug panel can capture a local screen and discover opted-in peers, but the main AV transmit/receive workflow still generates simulated network and display events. There is no real USB video driver, Wi‑Fi video transport, pairing/authentication flow, or remote screen streaming implementation in this repository.

This means the project is not yet an end-to-end deployed stream service.

## Testing status

The project includes a starter widget test in `screen_mirror/test/widget_test.dart`, but it is a generic Flutter template and does not reflect the actual app behavior. It should be replaced or reworked if the project is expanded into a real application with testable UI behavior.

## Summary

`MLRC ACCS` is a compact Flutter prototype for a USB/Wi‑Fi AV control interface. It combines a dark terminal-style dashboard, environmental configuration profiles, and helper scripts for setup and launch, making it a useful demonstration project for future development of a real distributed streaming or mirroring application.

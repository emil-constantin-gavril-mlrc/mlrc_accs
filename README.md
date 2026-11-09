# MLRC ACCS

This repository contains a Flutter-based prototype for screen mirroring over Wi-Fi. The Windows and Android apps can discover one another and send captured still-image frames through the Rust backend. It is not yet a live audio/video streamer; USB transport currently exists only as a standalone Rust option.

## Project purpose

The codebase is best understood as a UI-oriented prototype for a screen-sharing / remote-display system. It focuses on the operator experience and low-level signal flow modeling rather than a production-ready media stack. The interface exposes controls for:

- toggling between standby, transmit, and receive modes
- selecting an opted-in Wi-Fi peer and starting a transmit or receive session
- observing transport activity in a live terminal log
- inspecting real local screen captures and discovered opted-in peers in debug mode

## Repository layout

- `architecture/ARCHITECTURE.puml` — UML class diagram of the current application, Rust FFI bridge, and transports
- `architecture/render_plantuml.mjs` — renders a PlantUML file to SVG through the configured `@plantuml/mcp-js` MCP server
- `screen_mirror/` — the Flutter application source
- `screen_mirror/packages/` — locally maintained compatibility copies of Android plugins that need Gradle updates
- `rust_backend/` — the Rust watcher core, C ABI, and USB/Wi-Fi transport implementations
- `config/` — environment configuration files and setup/test helper scripts
- `run_app.ps1` — Windows launcher for the app in debug or production mode
- `run_app.sh` — Linux launcher for the app in debug or production mode
- `LICENSE` — project license

## Technology stack

- Dart / Flutter SDK
- Material Design UI components
- JSON-driven environment configuration via `--dart-define-from-file`
- PowerShell and Bash startup scripts for local execution
- Rust watcher and USB/Wi-Fi transport core with toolchain setup scripts
- Dart FFI bridge to the Rust Wi-Fi transport on Windows and Android

## Application overview

The main application entry is in `screen_mirror/lib/main.dart`. It creates a `WatcherTerminalApp` with a dark-themed dashboard named "AV Watcher Control Terminal". The dashboard includes:

- status cards for operation mode, communication channel, and stream status
- action buttons to start or stop transmitting or receiving
- a live event console reporting actual Wi-Fi frame transport activity
- peer selection and opt-in LAN discovery
- an optional debug inspector panel for on-demand screen capture and host-side ADB device listing

The app uses compile-time environment variables loaded from JSON config files:

- `OPERATION_MODE`
- `ENABLE_DEBUG_LOGS`
- `SHOW_DEBUG_PANEL`
- `ENVIRONMENT`

These values are defined in the configuration profiles under `config/` and passed into the Flutter app at runtime.

## Rust backend

The Rust library in `rust_backend/` is connected to Flutter through a small C ABI and Dart FFI wrapper. It provides mode-checked watcher operations, UDP frame fragmentation/reassembly with sequence tracking and a bounded jitter buffer, and an optional libusb bulk transport. Windows builds compile and bundle the Rust DLL from the Flutter Windows CMake build. Android builds compile armeabi-v7a, arm64-v8a, and x86_64 Rust libraries against the installed NDK before Flutter packages the APK.

Run the backend tests with:

```powershell
cd rust_backend
cargo test
```

Enable the hardware USB implementation with `cargo test --features usb` (and `cargo build --features usb` for builds). USB requires the peer device to use the configured interface/endpoints and the backend's 4-byte big-endian frame-length prefix. The UDP transport takes encoded frame bytes from its caller; it does not capture or encode video.

### Current Wi-Fi transport workflow

1. Launch the app on both devices while they are on the same local network.
2. Press **Discover** on both devices and select the other device from the **Wi-Fi peer** list.
3. On the receiving device, press **Start Receiving**.
4. On the sending device, press **Start Transmitting** and approve Android's screen-capture prompt if requested. The app captures and sends one still image. Use **Capture** in the debug panel to send another image.
5. The receiving app displays the latest received image and logs its byte count.

Both apps must be discoverable and connected to the same LAN; allow the app through host firewalls if prompted. Discovery advertises a TCP presence port and the Rust UDP socket binds to that same local port. Peer addresses currently use IPv4.

This is a working transport slice, not live screen mirroring: each capture sends a single encoded screenshot frame. Continuous capture, video encoding/decoding, audio, encryption, pairing/authentication, and USB device-to-device support are not implemented. UDP frame packets are acknowledged and the sender retries a frame up to three times, but the transport remains unencrypted and should only be used on a trusted LAN.

The project launchers build the required native Rust library automatically. The Windows CMake build compiles the DLL. For Android, the launcher uses `config/build/build_android_rust.ps1` on Windows or `config/build/build_android_rust.sh` on Linux. These scripts use the Flutter-selected NDK, install any missing Rust targets, and package the armeabi-v7a, arm64-v8a, and x86_64 libraries for Android API 23 under `screen_mirror/android/app/src/main/jniLibs/`. Direct Flutter Android commands bypass this preparation step; use `run_app.ps1` / `run_app.sh` or run the platform build script first.

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

### Render the architecture diagram

With Node.js and npm available, run this from the repository root:

```powershell
node .\architecture\render_plantuml.mjs
```

The script starts the same `npx -y @plantuml/mcp-js` server configured in `.mcp.json`, calls its `render_diagram` tool, and writes `architecture/ARCHITECTURE.svg`. Optional arguments specify a different input and output:

```powershell
node .\architecture\render_plantuml.mjs .\architecture\ARCHITECTURE.puml .\architecture\output.svg
```

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

### Create Windows and Android builds

From the repository root, run the Windows commands in PowerShell on a Windows host. The launcher selects the production profile and builds each target in release mode:

```powershell
.\run_app.ps1 prod windows build
.\run_app.ps1 prod android build
```

The Windows app is written under `screen_mirror\build\windows\`; the Android APK is written under `screen_mirror\build\app\outputs\flutter-apk\`. Android builds do not require a connected device. Windows desktop builds must run on Windows and require Visual Studio 2022 with the **Desktop development with C++** workload and C++ ATL. The launcher checks and installs required tooling where possible; see [What setup automates](#what-setup-automates) for details.

On Linux, build the Android APK with:

```bash
./run_app.sh prod android build
```

The generated APK currently uses Flutter's debug signing configuration, so it is not ready for store distribution.

If a build reports missing Dart files under the Pub cache (for example `jni.dart` or `desktop_screenshot.dart`), first restore network access to `pub.dev` and `storage.googleapis.com`, then repair the cache and dependencies:

```powershell
Push-Location .\screen_mirror
..\config\flutter\bin\flutter.bat pub cache repair
..\config\flutter\bin\flutter.bat pub get
Pop-Location
```

The launch scripts resolve Flutter packages before building so incomplete dependencies fail before the native compiler runs.

Show launcher-specific usage and examples with `.\run_app.ps1 -Help` in PowerShell or `./run_app.sh --help` in Bash. Help exits before checking or installing any tools.

Target defaults to `host` and action defaults to `run`. Windows desktop builds must run on Windows; Linux desktop builds must run on Linux. Android run requires exactly one authorized Android device or running emulator; the launcher checks ADB and explicitly targets that device instead of offering desktop or web targets. Unlock a USB-connected device and accept its USB debugging prompt, or start an emulator in Android Studio Device Manager first. Android builds do not require a connected device and produce an APK under `screen_mirror/build/app/outputs/flutter-apk/`. Production APKs currently use Flutter's debug signing configuration and are not ready for store distribution.

### What setup automates

- Flutter stable SDK is installed under `config/flutter/` if no SDK is available.
- On Windows, the Flutter clone enables Git long-path support for checkout. If setup detects a partial checkout from an earlier path-length failure, remove `config\flutter\` and rerun the setup or launcher.
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
- `config/build/build_android_rust.ps1` / `config/build/build_android_rust.sh` build and package the Android Rust libraries (the Android launchers run these automatically).

The `config/test/test_rust.ps1` and `config/test/test_rust.sh` scripts compile and run a small Rust verification program in four parallel instances.

## Debug panel features and limits

The debug panel uses real OS capture and device discovery APIs:

- **Screen capture:** click **Capture** to request a single current-screen preview. Windows and Linux use the desktop screenshot API. Android invokes the OS screen-capture consent flow, briefly records to the app-private cache, extracts one frame, and deletes the temporary recording. The preview is kept in app memory only and is discarded when replaced or when the app exits. While transmitting, each captured frame is sent to the selected peer. Android requires the user to approve the system prompt for each capture session; audio capture is not enabled.
- **Wi-Fi discovery:** click **Discover** to advertise this app and discover other MLRC instances on the same LAN using mDNS service type `_mlrc-accs._tcp`. Discovery is opt-in and limited to peers advertising that service; it does not sweep the subnet or identify arbitrary devices. The app advertises a small TCP presence endpoint that returns `MLRC-ACCS/1`; Rust binds a UDP socket to the advertised port for frame transport.
- **USB discovery:** on Windows and Linux hosts, **Discover** runs `adb devices -l` and shows ADB-reported devices, including their authorization state. The desktop launchers set up Platform-Tools if needed. Connect the device, enable USB debugging, and authorize the host on the device. An Android app cannot run host-side ADB to enumerate its own USB connection.

Discovery requires devices to be on the same network with multicast/mDNS allowed. For Android, local network access is declared in the manifest. The same application must be running with discovery active on another device for that device to appear. After selecting a peer, start **Receive** on one device and **Transmit** on the other to open the Rust transport.

Android screen capture support raises the app's minimum Android SDK level to API 23 (Android 6.0).

The Android Gradle scripts for `flutter_screen_recording` and `video_thumbnail` are maintained as local copies under `screen_mirror/packages/` because their published scripts use obsolete repositories and Gradle APIs. Their upstream MIT license files are retained alongside the source.

## Important implementation note

The Flutter app now invokes the Rust UDP transport over FFI on Windows and Android, and a still-image frame can be sent between discovered peers. This is not yet a live or production-ready media streaming system: there is no continuous video capture, video codec pipeline, audio, pairing/authentication, encryption, or USB device-to-device support. UDP does not guarantee delivery, and the current frame protocol is intended only for trusted local networks.

## Testing status

The project includes a starter widget test in `screen_mirror/test/widget_test.dart`, but it is a generic Flutter template and does not reflect the actual app behavior. It should be replaced or reworked if the project is expanded into a real application with testable UI behavior.

## Summary

`MLRC ACCS` is a compact Flutter prototype for a Wi-Fi still-frame mirroring workflow with a Rust transport backend. It combines a dark terminal-style dashboard, environmental configuration profiles, peer discovery, and helper scripts for setup and launch.

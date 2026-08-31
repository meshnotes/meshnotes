# Mesh Notes - Platform-Specific Implementation

## Overview

Mesh Notes uses Flutter for cross-platform support with platform-specific adaptations for:
- Windows
- macOS
- Linux
- iOS
- iPadOS
- Android

## Platform Detection

**Location**: [lib/mindeditor/controller/environment.dart](../lib/mindeditor/controller/environment.dart)

```dart
class Environment {
  // Platform checks
  bool isWindows() => Platform.isWindows;
  bool isMac() => Platform.isMacOS;
  bool isLinux() => Platform.isLinux;
  bool isAndroid() => Platform.isAndroid;
  bool isIos() => Platform.isIOS;

  // Platform categories
  bool isMobile() => isAndroid() || isIos();
  bool isDesktop() => isWindows() || isMac() || isLinux();

  // Screen size
  bool isSmallScreen(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  bool isLargeScreen(BuildContext context) {
    return MediaQuery.of(context).size.width >= 1024;
  }
}
```

## Device Identity

### Overview

Each device needs a unique ID for node identification in the P2P network. Different platforms use different sources.

**Location**: [lib/mindeditor/user/user_manager.dart](../lib/mindeditor/user/user_manager.dart)

### Android

Use the `android_id` plugin:

```dart
Future<String> getAndroidDeviceId() async {
  final androidIdPlugin = AndroidId();
  final androidId = await androidIdPlugin.getId();
  return androidId ?? 'unknown-android';
}
```

**Notes**:
- Android ID is unique per app
- Changes after a factory reset
- Persists across uninstall/reinstall

### iOS/iPadOS

Use `device_info_plus` `identifierForVendor`:

```dart
Future<String> getIosDeviceId() async {
  final deviceInfo = DeviceInfoPlugin();
  final iosInfo = await deviceInfo.iosInfo;
  return iosInfo.identifierForVendor ?? 'unknown-ios';
}
```

**Notes**:
- Shared by apps from the same vendor
- Resets after all apps from that vendor are removed
- No special permission needed

### macOS

Use system GUID:

```dart
Future<String> getMacDeviceId() async {
  final deviceInfo = DeviceInfoPlugin();
  final macInfo = await deviceInfo.macOsInfo;
  return macInfo.systemGUID ?? 'unknown-mac';
}
```

**Notes**:
- System-level unique ID
- Changes after reinstalling macOS
- No special permission needed

### Windows

Use device ID API:

```dart
Future<String> getWindowsDeviceId() async {
  final deviceInfo = DeviceInfoPlugin();
  final windowsInfo = await deviceInfo.windowsInfo;
  return windowsInfo.deviceId ?? 'unknown-windows';
}
```

**Notes**:
- Hardware-related unique ID
- Highly stable
- No special permission needed

### Linux

Use machine ID:

```dart
Future<String> getLinuxDeviceId() async {
  final deviceInfo = DeviceInfoPlugin();
  final linuxInfo = await deviceInfo.linuxInfo;
  return linuxInfo.machineId ?? 'unknown-linux';
}
```

**Notes**:
- Reads `/etc/machine-id` or `/var/lib/dbus/machine-id`
- Generated during OS install
- Stable

### Unified interface

```dart
Future<String> getDeviceId() async {
  if (Environment().isAndroid()) {
    return getAndroidDeviceId();
  } else if (Environment().isIos()) {
    return getIosDeviceId();
  } else if (Environment().isMac()) {
    return getMacDeviceId();
  } else if (Environment().isWindows()) {
    return getWindowsDeviceId();
  } else if (Environment().isLinux()) {
    return getLinuxDeviceId();
  } else {
    return 'unknown-device';
  }
}
```

## UI Adaptation

### Desktop features

**Location**: [lib/mindeditor/view/mind_edit_block.dart](../lib/mindeditor/view/mind_edit_block.dart)

#### Block handler

Desktop-only control buttons:

```dart
Widget _buildBlockHandler() {
  if (Environment().isMobile()) {
    return SizedBox.shrink();  // hide on mobile
  }

  return Container(
    width: 32,
    child: Column(
      children: [
        // Drag icon
        Icon(Icons.drag_indicator, size: 16, color: Colors.grey),
        // Add button
        IconButton(
          icon: Icon(Icons.add, size: 16),
          onPressed: _onAddBlock,
        ),
        // More menu
        IconButton(
          icon: Icon(Icons.more_vert, size: 16),
          onPressed: _onShowMenu,
        ),
      ],
    ),
  );
}
```

#### Mouse cursor

```dart
Widget _buildBlock() {
  return MouseRegion(
    cursor: SystemMouseCursors.text,
    onEnter: (event) {
      setState(() => _isHovered = true);
    },
    onExit: (event) {
      setState(() => _isHovered = false);
    },
    child: _buildBlockContent(),
  );
}
```

#### Window close

**Location**: [lib/page/mesh_app.dart](../lib/page/mesh_app.dart)

```dart
void initState() {
  super.initState();

  if (Environment().isDesktop()) {
    FlutterWindowClose.setWindowShouldCloseHandler(() async {
      // Save data
      await controller.docManager.saveAll();

      // Stop network
      controller.network.stop();

      return true;  // allow closing
    });
  }
}
```

### Mobile features

#### Soft keyboard management

```dart
class MindEditFieldState extends State<MindEditField> {
  void showKeyboard() {
    if (Environment().isMobile()) {
      TextInput.attach(this, TextInputConfiguration(
        inputType: TextInputType.multiline,
        inputAction: TextInputAction.newline,
        enableSuggestions: true,
        autocorrect: true,
      ));
      TextInput.show();
    }
  }

  void hideKeyboard() {
    if (Environment().isMobile()) {
      TextInput.hide();
    }
  }
}
```

#### iOS backspace handling

iOS backspace cannot be detected directly via `TextInputClient`, so it is handled specially:

```dart
@override
void updateEditingValue(TextEditingValue value) {
  if (Environment().isIos()) {
    // iOS: empty value after leading marker means backspace
    if (value.text.isEmpty && _lastValue.text.startsWith('\u200b')) {
      _handleBackspace();
      return;
    }

    // Prefix with invisible char to detect backspace
    if (!value.text.startsWith('\u200b')) {
      value = TextEditingValue(
        text: '\u200b${value.text}',
        selection: TextSelection.collapsed(
          offset: value.selection.baseOffset + 1,
        ),
      );
    }
  }

  // Normal handling
  _processTextChange(value);
}
```

#### Lifecycle listener

```dart
void initState() {
  super.initState();

  if (Environment().isMobile()) {
    AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.paused) {
          // Save when backgrounded
          controller.docManager.saveAll();
        } else if (state == AppLifecycleState.resumed) {
          // Refresh network when resumed
          controller.network.checkStatus();
        }
      },
    );
  }
}
```

## Network Adaptation

### LAN discovery

**Location**: [packages/libp2p/lib/overlay/discovery/](../packages/libp2p/lib/overlay/discovery/)

#### mDNS/Bonjour

Use the `bonsoir` plugin:

```dart
class BonjourDiscovery {
  BonsoirService? _service;
  BonsoirDiscovery? _discovery;

  void start() {
    if (Environment().isMobile() || Environment().isDesktop()) {
      _startAdvertising();
      _startDiscovery();
    }
  }

  void _startAdvertising() {
    _service = BonsoirService(
      name: _deviceId,
      type: '_meshnotes._udp',
      port: _port,
    );
    _service!.start();
  }

  void _startDiscovery() {
    _discovery = BonsoirDiscovery(type: '_meshnotes._udp');
    _discovery!.listen((event) {
      if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
        _onServiceFound(event.service!);
      }
    });
    _discovery!.start();
  }
}
```

**Platform support**:
- iOS/macOS: native Bonjour
- Android: NSD (Network Service Discovery)
- Linux: Avahi
- Windows: requires Bonjour service

#### Permissions

**Android**:
```xml
<!-- AndroidManifest.xml -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CHANGE_NETWORK_MULTICAST_STATE" />
```

**iOS**:
```xml
<!-- Info.plist -->
<key>NSLocalNetworkUsageDescription</key>
<string>Need LAN access to discover other devices.</string>
<key>NSBonjourServices</key>
<array>
  <string>_meshnotes._udp</string>
</array>
```

### UDP socket

Use Dart `dart:io`:

```dart
import 'dart:io';

class UdpSocket {
  RawDatagramSocket? _socket;

  Future<void> bind(String host, int port) async {
    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
    );

    _socket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = _socket!.receive();
        if (datagram != null) {
          _onDataReceived(datagram.data, datagram.address, datagram.port);
        }
      }
    });
  }

  void send(Uint8List data, InternetAddress address, int port) {
    _socket?.send(data, address, port);
  }
}
```

**Cross-platform**:
- UDP sockets available everywhere
- No platform-specific code needed

## Storage Adaptation

### SQLite

Use `sqlite3` and `sqlite3_flutter_libs`:

```dart
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

class DbHelper {
  Database? _db;

  Future<void> open(String path) async {
    // Mobile needs native library loading
    if (Environment().isMobile()) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }

    _db = sqlite3.open(path);
  }
}
```

**Platform differences**:
- **Desktop**: use system SQLite
- **Mobile**: bundled SQLite library
- **DB locations**:
  - Android: `/data/data/<package>/databases/`
  - iOS: `Library/Application Support/`
  - macOS: `~/Library/Application Support/<app>/`
  - Windows: `%APPDATA%/<app>/`
  - Linux: `~/.local/share/<app>/`

### File paths

```dart
import 'package:path_provider/path_provider.dart';

Future<String> getDatabasePath() async {
  final directory = await getApplicationDocumentsDirectory();
  return '${directory.path}/meshnotes.db';
}

Future<String> getConfigPath() async {
  final directory = await getApplicationSupportDirectory();
  return '${directory.path}/config.json';
}
```

## Permissions

### Storage (Android)

```dart
Future<bool> requestStoragePermission() async {
  if (!Environment().isAndroid()) {
    return true;  // others do not need it
  }

  final status = await Permission.storage.status;
  if (status.isGranted) {
    return true;
  }

  final result = await Permission.storage.request();
  return result.isGranted;
}
```

### Photos (iOS/Android)

```dart
Future<bool> requestPhotoPermission() async {
  if (!Environment().isMobile()) {
    return true;  // desktop does not need it
  }

  final status = await Permission.photos.status;
  if (status.isGranted) {
    return true;
  }

  final result = await Permission.photos.request();
  return result.isGranted;
}
```

### Network

- **Android**: declare in `AndroidManifest.xml`
- **iOS**: declare in `Info.plist`
- **Desktop**: no special permission

## Build Configuration

### Android

**Location**: `android/app/build.gradle`

```gradle
android {
    compileSdk = 36  // Must be >= targetSdk. Google Play requires targetSdk 36 as of 2026-08-31.

    defaultConfig {
        applicationId "xyz.meshnotes.meshnotes"
        minSdk = 26    // Android 8.0+
        targetSdk = 36  // Required by Google Play (Android 16)
        versionCode flutter.versionCode
        versionName flutter.versionName
    }

    buildTypes {
        release {
            signingConfig signingConfigs.release
            minifyEnabled true
            shrinkResources true
        }
    }
}
```

Google Play requires phone/tablet app updates to target Android 16 (API 36) from 2026-08-31. `compileSdk` must be at least as high as `targetSdk`. `minSdk` stays at 26 — targeting 36 does not drop older-device support. Plugin subprojects get the same 36 values from the `flutter` shim in `android/build.gradle` (see [Android build hangs](#6-android-build-hangs-at-running-gradle-task-assemblerelease) below).

Targeting 36 turns on Android 16 behavior changes. Mesh Notes already runs edge-to-edge (`SystemUiOverlayStyle` in `lib/init.dart`) and does not lock orientation, so the large-screen orientation/resizability change does not apply. Test camera, microphone, WebRTC, and LAN discovery on an Android 16 device or emulator before shipping the Play production update.

### iOS

**Location**: `ios/Runner.xcodeproj/project.pbxproj`

```
IPHONEOS_DEPLOYMENT_TARGET = 12.0
SWIFT_VERSION = 5.0
```

**Location**: `ios/Podfile`

```ruby
platform :ios, '12.0'

target 'Runner' do
  use_frameworks!
  use_modular_headers!

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
end
```

### macOS

**Location**: `macos/Runner/Info.plist`

```xml
<key>NSCameraUsageDescription</key>
<string>Need camera access to take photos.</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>Need photo library access to pick photos.</string>
```

**Entitlements**:
```xml
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.network.server</key>
<true/>
```

### Windows

**Location**: `windows/runner/main.cpp`

```cpp
// DPI awareness
SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

// Window config
Win32Window::Size size(1280, 720);
```

### Linux

**Location**: `linux/my_application.cc`

```cpp
gtk_window_set_default_size(window, 1280, 720);
gtk_window_set_title(window, "Mesh Notes");
```

## Icons and Splash Screen

### App icons

**Config**: `pubspec.yaml`

```yaml
flutter_launcher_icons:
  android: true
  ios: true
  image_path: "assets/icon/app_icon.png"

  # Android adaptive icon
  adaptive_icon_background: "#FFFFFF"
  adaptive_icon_foreground: "assets/icon/app_icon_foreground.png"

  # macOS icon
  macos:
    generate: true
    image_path: "assets/icon/app_icon.png"

  # Windows icon
  windows:
    generate: true
    image_path: "assets/icon/app_icon.png"
    icon_size: 256
```

**Generate**:
```bash
dart run flutter_launcher_icons
```

### Splash screen

**Config**: `flutter_native_splash.yaml`

```yaml
flutter_native_splash:
  color: "#FFFFFF"
  image: assets/splash/splash.png

  android: true
  ios: true
  web: false

  android_12:
    color: "#FFFFFF"
    image: assets/splash/splash.png
```

**Generate**:
```bash
dart run flutter_native_splash:create
```

## Platform Issues and Solutions

### 1. Android back button

```dart
class DocumentView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Save data
        await controller.docManager.saveCurrentDocument();
        return true;
      },
      child: Scaffold(/* ... */),
    );
  }
}
```

### 2. iOS safe area

```dart
Widget build(BuildContext context) {
  return SafeArea(
    child: Scaffold(/* ... */),
  );
}
```

### 3. Windows high DPI

```cpp
// windows/runner/main.cpp
SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
```

### 4. macOS sandbox

**Location**: `macos/Runner/DebugProfile.entitlements`

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
```

### 5. Linux dependencies

```bash
# Ubuntu/Debian
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev

# Network discovery dependencies
sudo apt-get install libavahi-client-dev
```

### 6. Android build hangs at "Running Gradle task 'assembleRelease'"

**Location**: `android/build.gradle`

**Symptom**: `flutter build apk` prints `Running Gradle task 'assembleRelease'...` and never finishes. The Gradle daemon burns 100% of one CPU core with a flat memory footprint, and no error is ever printed.

**Cause**: Flutter 3.24's Gradle plugin creates the `flutter` extension only on the `:app` project (`FlutterExtension` in `packages/flutter_tools/gradle/src/main/groovy/flutter.groovy`). Plugins published for Flutter 3.27+ read `flutter.compileSdkVersion` inside their own `android { }` block, for example `record_android >= 1.4.3` (pulled in by `record: 6.2.0`) and `shared_preferences_android >= 2.4.15`. Configuring such a plugin throws `MissingPropertyException: Could not get unknown property 'flutter' for extension 'android'`. Gradle then hangs in `DefaultExceptionAnalyser.findDeepestRootException` while building the failure report, so the underlying error is never reported — the build only *looks* like it is stuck downloading or compiling.

**Solution**: `android/build.gradle` injects a `flutter` extra property into every non-`app` subproject before it is evaluated, mirroring the values `android/app/build.gradle` uses (and the values Flutter 3.27's own `FlutterExtension` vends).

```gradle
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects { subproject ->
    if(subproject.name != "app" && subproject.extensions.findByName("flutter") == null) {
        subproject.ext.flutter = [
            compileSdkVersion: 36,
            minSdkVersion    : 26,
            targetSdkVersion : 36,
            ndkVersion       : "23.1.7779620",
        ]
    }
}
```

The block order is load-bearing. Evaluating `:app` is what runs Flutter's `configurePluginProject()`, which on 3.27+ calls `pluginProject.extensions.create("flutter", FlutterExtension)` for every plugin project. Placing the shim after `evaluationDependsOn(":app")` means the `findByName` guard sees that real extension and skips, so the shim disables itself as soon as the SDK is upgraded and no cleanup is required.

Order matters because a Gradle extra property shadows a same-named extension during dynamic property lookup — an unguarded shim on 3.27+ would silently replace the SDK's own `FlutterExtension` rather than fail. Verified on this project: forcing `ext.flutter` onto `:app` (which does own a real extension) makes `project.flutter` resolve to the map and the build dies with `Must provide Flutter source directory`.

**Diagnosing similar hangs**: because Gradle swallows configuration failures this way, use [tools/gradle_diagnose_init.gradle](../tools/gradle_diagnose_init.gradle), which prints the failure the moment it happens instead of waiting for Gradle's own report. From `android/`:

```bash
./gradlew :<plugin_project>:properties -I ../tools/gradle_diagnose_init.gradle
```

This is worth reaching for whenever an Android build hangs with no output — any plugin that starts reading `flutter.compileSdkVersion` reproduces the same silent hang. See [08-tools.md](08-tools.md#gradle_diagnose_initgradle---android-configuration-failure-diagnostics) for details.

## Testing and Debugging

### Platform-specific tests

```dart
void main() {
  testWidgets('Block handler visible on desktop', (tester) async {
    await tester.pumpWidget(MyApp());

    if (Environment().isDesktop()) {
      expect(find.byIcon(Icons.drag_indicator), findsWidgets);
    } else {
      expect(find.byIcon(Icons.drag_indicator), findsNothing);
    }
  });
}
```

### Emulators/Simulators

- **Android**: Android Emulator
- **iOS**: Xcode Simulator
- **Windows**: run directly
- **macOS**: run directly
- **Linux**: run directly

### Real devices

```bash
# List devices
flutter devices

# Run on a device
flutter run -d <device-id>

# iOS device (dev account required)
flutter run -d <iphone-id> --release

# Android device (USB debugging on)
flutter run -d <android-id>
```

## Release

### Android

```bash
# Generate keystore
keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias release

# Build APK
flutter build apk --release

# Build App Bundle
flutter build appbundle --release
```

### iOS

```bash
# Build
flutter build ios --release

# Upload via Xcode
open ios/Runner.xcworkspace
```

### macOS

```bash
flutter build macos --release
```

### Windows

```bash
flutter build windows --release
```

### Linux

```bash
flutter build linux --release
```


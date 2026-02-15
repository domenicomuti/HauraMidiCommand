# flutter_midi_command

A Flutter plugin for sending and receiving MIDI messages between Flutter and physical and virtual MIDI devices.

Wraps CoreMIDI/android.media.midi/ALSA/win32 in a thin dart/flutter layer.
Supports

| Transports | iOS | macos | Android | Linux | Windows | Web |
|---|---|---|---|---|---|---|
| USB | &check; | &check; | &check; | &check; | &check; | &check;* |
| BLE | &check; | &check; | &check; | &cross; | &check; | &cross;** |
| Virtual | &check; | &check; | &check; | &cross; | &cross; | &cross; |
| Network Session | &check; | &check; | &cross; | &cross; | &cross; | &cross; |

\* via browser Web MIDI API support.
\** BLE MIDI on web is not handled by `flutter_midi_command_ble`; web MIDI exposure depends on browser/OS.


## To install

- Make sure your project is created with Kotlin and Swift support.
- Add `flutter_midi_command` to your `pubspec.yaml` (path/git while this monorepo is unpublished).
- Add `flutter_midi_command_ble` only if you want BLE MIDI support.
- In ios/Podfile uncomment and change the platform to 11.0 `platform :ios, '11.0'`
- If BLE is enabled on iOS, add `NSBluetoothAlwaysUsageDescription` (and related bluetooth/location keys as required by your BLE flow) to `Info.plist`.
- If using network MIDI on iOS, add `NSLocalNetworkUsageDescription`.
- On Linux, make sure ALSA is installed.
- On web, use HTTPS and a browser with Web MIDI enabled (for example Chrome/Edge).

## Getting Started

This plugin is built using Swift and Kotlin on the native side, so make sure your project supports this.

Import flutter_midi_command

`import 'package:flutter_midi_command/flutter_midi_command.dart';`

- Get a list of available MIDI devices by calling `MidiCommand().devices` which returns a list of `MidiDevice`
- Start bluetooth subsystem by calling `MidiCommand().startBluetooth()`
- Observe the bluetooth system state by listening to `MidiCommand().onBluetoothStateChanged`
- Get the current bluetooth system state from `MidiCommand().bluetoothState`
- Start scanning for BLE MIDI devices by calling `MidiCommand().startScanningForBluetoothDevices()`
- Connect to a specific `MidiDevice` by calling `MidiCommand().connectToDevice(selectedDevice)`.
  The returned `Future` completes when a connection is established, throws a `StateError` when connection fails, or throws on timeout (default 10 seconds).
- Stop scanning for BLE MIDI devices by calling `MidiCommand().stopScanningForBluetoothDevices()`
- Disconnect from a device by calling `MidiCommand().disconnectDevice(device)`
- Listen for updates in the MIDI setup by subscribing to `MidiCommand().onMidiSetupChanged`
- Listen for incoming MIDI messages from the current device by subscribing to `MidiCommand().onMidiDataReceived`, after which the listener will receive inbound MIDI messages as a `Uint8List` of variable length.
- Send a MIDI message by calling `MidiCommand.sendData(data)`, where data is an UInt8List of bytes following the MIDI spec.
- Or use the various `MidiCommand` subtypes to send PC, CC, NoteOn and NoteOff messages.
- Use `MidiCommand().addVirtualDevice(name: "Your Device Name")` to create a virtual MIDI destination and a virtual MIDI source. These virtual MIDI devices show up in other apps and can be used by other apps to send and receive MIDI to or from your app. The name parameter is ignored on Android and the Virtual Device is always called FlutterMIDICommand. To make this feature work on iOS, enable background audio for your app, i.e., add key `UIBackgroundModes` with value `audio` to your app's `info.plist` file.

See example folder for how to use.

### Dependency examples

With serial/native transports only:

```yaml
dependencies:
  flutter_midi_command:
    path: ../flutter_midi_command
```

With BLE support enabled:

```yaml
dependencies:
  flutter_midi_command:
    path: ../flutter_midi_command
  flutter_midi_command_ble:
    path: ../flutter_midi_command/packages/flutter_midi_command_ble
```

For help getting started with Flutter, view our online
[documentation](https://flutter.dev/).

For help on editing plugin code, view the [documentation](https://docs.flutter.dev/development/packages-and-plugins/developing-packages#edit-plugin-package).

## Workspace and architecture

This repository is now managed as a melos monorepo.

### Packages

- `flutter_midi_command` (this package): public API and transport policies
- `packages/flutter_midi_command_platform_interface`: shared platform contracts
- `packages/flutter_midi_command_linux`: Linux serial MIDI wrapper
- `packages/flutter_midi_command_windows`: Windows serial MIDI wrapper
- `packages/flutter_midi_command_ble`: shared BLE MIDI transport using `universal_ble`
- `packages/flutter_midi_command_web`: browser Web MIDI transport
  See `packages/flutter_midi_command_web/README.md` for web-specific runtime/permission details.

### Transport policies

You can include/exclude transports at runtime:

```dart
final midi = MidiCommand();
midi.configureTransportPolicy(
  const MidiTransportPolicy(
    excludedTransports: {MidiTransport.ble},
  ),
);
```

When a transport is disabled, transport-specific calls throw a `StateError`.

### Device types

`MidiDevice.type` is now strongly typed as `MidiDeviceType` (for example `MidiDeviceType.serial`, `MidiDeviceType.ble`, `MidiDeviceType.virtual`).

### Device connection state

Each `MidiDevice` now exposes connection state updates:

```dart
final sub = selectedDevice.onConnectionStateChanged.listen((state) {
  // state is MidiConnectionState.disconnected/connecting/connected/disconnecting
});
```

### Compile-time BLE include/exclude

BLE is now optional at dependency level:

- If you only depend on `flutter_midi_command`, BLE is not included.
- To include BLE, add `flutter_midi_command_ble` and attach it to `MidiCommand`:

```dart
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command_ble/flutter_midi_command_ble.dart';

final midi = MidiCommand();
midi.configureBleTransport(UniversalBleMidiTransport());
```

To disable BLE completely:

```dart
midi.configureBleTransport(null);
```

The normal BLE API remains unchanged:

```dart
await midi.startBluetooth();
await midi.startScanningForBluetoothDevices();
final state = midi.bluetoothState;
final stateStream = midi.onBluetoothStateChanged;
```

### Architecture note

`MidiCommandPlatform` now only describes native serial/host MIDI operations.
BLE lives in `MidiBleTransport`, implemented in shared Dart (`flutter_midi_command_ble`).
Web MIDI is implemented by `flutter_midi_command_web` using browser Web MIDI APIs.

### Native API contracts with Pigeon

Pigeon definitions are tracked in `pigeons/midi_api.dart` and should be used as the source-of-truth for generated host/flutter messaging code.

# flutter_midi_command_platform_interface

Shared platform contracts for the `flutter_midi_command` plugin family.

## Scope

- `MidiCommandPlatform`: native serial/host MIDI contract
- `MidiBleTransport`: optional BLE transport contract implemented in Dart
- Shared models (`MidiDevice`, `MidiPacket`, `MidiPort`)

BLE is intentionally not part of `MidiCommandPlatform`.
The app-facing `MidiCommand` API composes native MIDI + optional BLE transport.

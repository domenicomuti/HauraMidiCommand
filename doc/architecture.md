# Flutter MIDI Command architecture (monorepo migration)

## Goals

- Use a melos workspace for coordinated package versioning and CI.
- Keep platform code focused on serial/virtual host MIDI APIs.
- Keep BLE behavior in shared Dart logic (using `universal_ble` in follow-up packages).
- Define host <-> Flutter contracts through Pigeon.
- Expose transport capabilities and policy controls to apps.

## Current baseline in this branch

- `melos.yaml` introduces workspace scripts for analyze/test/format.
- `pigeons/midi_api.dart` defines source-of-truth host and flutter APIs.
- `MidiTransportPolicy` and `MidiCapabilities` are exposed in Dart.
- `MidiCommand.configureTransportPolicy(...)` allows include/exclude control per transport.

## Follow-up

- Split packages under `packages/` for core BLE transport and per-platform wrappers.
- Create platform-specific packages for Android (Media MIDI APIs) and Linux (ALSA APIs) to keep host wrappers focused and independent.
- Wire generated Pigeon stubs on Android/iOS/macOS/native implementations.
- Add web package (`flutter_midi_command_web`) as stretch deliverable.

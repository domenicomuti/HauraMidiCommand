import 'dart:typed_data';

import 'package:flutter_midi_command_platform_interface/flutter_midi_command_platform_interface.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

class FlutterMidiCommandWeb extends MidiCommandPlatform {
  static void registerWith(Registrar registrar) {
    MidiCommandPlatform.instance = FlutterMidiCommandWeb();
  }

  UnsupportedError _unsupported(String operation) {
    return UnsupportedError(
      'flutter_midi_command_web does not implement $operation yet.',
    );
  }

  @override
  Future<List<MidiDevice>?> get devices =>
      Future<List<MidiDevice>?>.error(_unsupported('devices'));

  @override
  Future<void> connectToDevice(MidiDevice device, {List<MidiPort>? ports}) {
    return Future<void>.error(_unsupported('connectToDevice'));
  }

  @override
  void disconnectDevice(MidiDevice device) {
    throw _unsupported('disconnectDevice');
  }

  @override
  void sendData(Uint8List data, {int? timestamp, String? deviceId}) {
    throw _unsupported('sendData');
  }

  @override
  Stream<MidiPacket>? get onMidiDataReceived =>
      Stream<MidiPacket>.error(_unsupported('onMidiDataReceived'));

  @override
  Stream<String>? get onMidiSetupChanged =>
      Stream<String>.error(_unsupported('onMidiSetupChanged'));

  @override
  void teardown() {
    // No resources to release on web placeholder implementation.
  }
}

import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MidiTransportPolicy', () {
    test('defaults to all supported transports', () {
      const policy = MidiTransportPolicy();
      final result = policy.resolveEnabledTransports({
        MidiTransport.serial,
        MidiTransport.ble,
      });

      expect(result, {MidiTransport.serial, MidiTransport.ble});
    });

    test('can include only selected transports', () {
      const policy = MidiTransportPolicy(
        includedTransports: {MidiTransport.serial},
      );

      final result = policy.resolveEnabledTransports({
        MidiTransport.serial,
        MidiTransport.ble,
      });

      expect(result, {MidiTransport.serial});
    });

    test('excluded transports are always removed', () {
      const policy = MidiTransportPolicy(
        excludedTransports: {MidiTransport.ble},
      );

      final result = policy.resolveEnabledTransports({
        MidiTransport.serial,
        MidiTransport.ble,
      });

      expect(result, {MidiTransport.serial});
    });

    test('unknown transports are ignored', () {
      const policy = MidiTransportPolicy(
        includedTransports: {MidiTransport.serial, MidiTransport.network},
      );

      final result = policy.resolveEnabledTransports({MidiTransport.serial});

      expect(result, {MidiTransport.serial});
    });
  });

  group('MidiCapabilities', () {
    test('tracks supported and enabled transports', () {
      const capabilities = MidiCapabilities(
        supportedTransports: {MidiTransport.serial, MidiTransport.ble},
        enabledTransports: {MidiTransport.serial},
      );

      expect(capabilities.supports(MidiTransport.serial), isTrue);
      expect(capabilities.supports(MidiTransport.virtualDevice), isFalse);
      expect(capabilities.isEnabled(MidiTransport.serial), isTrue);
      expect(capabilities.isEnabled(MidiTransport.ble), isFalse);
    });
  });

  group('MidiDeviceType', () {
    test('maps to and from wire values', () {
      expect(MidiDeviceType.serial.wireValue, 'native');
      expect(MidiDeviceType.ble.wireValue, 'BLE');

      expect(MidiDeviceTypeWire.fromWireValue('native'), MidiDeviceType.serial);
      expect(MidiDeviceTypeWire.fromWireValue('BLE'), MidiDeviceType.ble);
      expect(
        MidiDeviceTypeWire.fromWireValue('own-virtual'),
        MidiDeviceType.ownVirtual,
      );
    });
  });

  group('MidiConnectionState', () {
    test('updates per-device state stream', () async {
      final device = MidiDevice(
        'serial-1',
        'Serial',
        MidiDeviceType.serial,
        false,
      );
      final states = <MidiConnectionState>[];
      final sub = device.onConnectionStateChanged.listen(states.add);

      device.connected = true;
      device.setConnectionState(MidiConnectionState.disconnecting);
      device.connected = false;

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();
      device.dispose();

      expect(states, <MidiConnectionState>[
        MidiConnectionState.connected,
        MidiConnectionState.disconnecting,
        MidiConnectionState.disconnected,
      ]);
    });
  });
}

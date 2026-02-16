import 'package:flutter_midi_command_linux/flutter_midi_command_linux.dart';
import 'package:flutter_midi_command_platform_interface/flutter_midi_command_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registerWith installs linux platform implementation', () {
    FlutterMidiCommandLinux.registerWith();
    expect(MidiCommandPlatform.instance, isA<FlutterMidiCommandLinux>());
  });

  test('linux plugin exposes streams and no-op virtual device APIs', () {
    final plugin = FlutterMidiCommandLinux();

    expect(plugin.onMidiDataReceived, isNotNull);
    expect(plugin.onMidiSetupChanged, isNotNull);
    expect(
      () => plugin.addVirtualDevice(name: 'Test Virtual'),
      returnsNormally,
    );
    expect(
      () => plugin.removeVirtualDevice(name: 'Test Virtual'),
      returnsNormally,
    );
  });

  test('teardown closes midi data stream', () async {
    final plugin = FlutterMidiCommandLinux();
    final done = expectLater(plugin.onMidiDataReceived!, emitsDone);

    plugin.teardown();

    await done;
  });
}

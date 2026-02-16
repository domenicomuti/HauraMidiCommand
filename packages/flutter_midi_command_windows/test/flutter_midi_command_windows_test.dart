import 'package:flutter_midi_command_windows/flutter_midi_command_windows.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win32/win32.dart';

void main() {
  test('midiErrorMessage maps known WinMM status codes', () {
    expect(midiErrorMessage(MMSYSERR_ALLOCATED), 'Resource already allocated');
    expect(midiErrorMessage(MMSYSERR_BADDEVICEID), 'Device ID out of range');
    expect(midiErrorMessage(MMSYSERR_INVALFLAG), 'Invalid dwFlags');
    expect(
      midiErrorMessage(MMSYSERR_INVALPARAM),
      'Invalid pointer or structure',
    );
    expect(midiErrorMessage(MMSYSERR_NOMEM), 'Unable to allocate memory');
    expect(midiErrorMessage(MMSYSERR_INVALHANDLE), 'Invalid handle');
  });

  test('midiErrorMessage falls back for unknown status', () {
    expect(midiErrorMessage(-12345), 'Status -12345');
  });
}

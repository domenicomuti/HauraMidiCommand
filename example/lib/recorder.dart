import 'dart:async';
import 'dart:io';

import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';

class MidiRecorder {
  factory MidiRecorder() {
    _instance ??= MidiRecorder._();
    return _instance!;
  }

  static MidiRecorder? _instance;

  MidiRecorder._();

  bool _recording = false;

  bool get recording => _recording;

  final List<MidiDataReceivedEvent> _messages = [];

  StreamSubscription<MidiDataReceivedEvent>? _midiSub;

  startRecording() {
    _recording = true;
    _midiSub = MidiCommand().onMidiDataReceived?.listen(_messages.add);
  }

  stopRecording() {
    _recording = false;
    _midiSub?.cancel();
  }

  exportRecording() async {
    var rows = _messages
        .map(
          (event) => [
            event.timestamp,
            ...event.message.data.map((byte) => byte.toString()),
          ],
        )
        .toList();

    var csv = const ListToCsvConverter().convert(rows);

    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Please select an output file:',
      fileName: 'midi_recording.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (outputFile == null) {
      // User canceled the picker
    } else {
      await File(outputFile).writeAsString(csv);
    }

    print("recording exported");
  }

  clearRecording() {
    _messages.clear();
  }
}

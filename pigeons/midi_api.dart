import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/pigeon/midi_api.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/src/main/kotlin/com/invisiblewrench/fluttermidicommand/pigeon/MidiApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.invisiblewrench.fluttermidicommand.pigeon'),
    swiftOut: 'ios/Classes/pigeon/MidiApi.g.swift',
    swiftOptions: SwiftOptions(),
  ),
)
class MidiHostDevice {
  String? id;
  String? name;
  String? type;
}

@HostApi()
abstract class MidiHostApi {
  List<MidiHostDevice> listDevices();
  void connect(String deviceId);
  void disconnect(String deviceId);
  void sendData(String? deviceId, Uint8List data, int? timestamp);
}

@FlutterApi()
abstract class MidiFlutterApi {
  void onSetupChanged();
  void onDataReceived(String deviceId, Uint8List data, int? timestamp);
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_midi_command_platform_interface/flutter_midi_command_platform_interface.dart';

export 'package:flutter_midi_command_platform_interface/flutter_midi_command_platform_interface.dart'
    show MidiDevice, MidiPacket, MidiPort;
export 'src/midi_transports.dart';

enum BluetoothState {
  poweredOn,
  poweredOff,
  resetting,
  unauthorized,
  unknown,
  unsupported,
  other,
}

class MidiCommand {
  static const Set<MidiTransport> _supportedTransports = {
    MidiTransport.serial,
    MidiTransport.ble,
    MidiTransport.network,
    MidiTransport.virtualDevice,
  };

  factory MidiCommand() {
    if (_instance == null) {
      _instance = MidiCommand._();
    }
    return _instance!;
  }

  MidiCommand._();


  MidiTransportPolicy _transportPolicy = const MidiTransportPolicy();

  Set<MidiTransport> get enabledTransports =>
      _transportPolicy.resolveEnabledTransports(_supportedTransports);

  MidiCapabilities get capabilities => MidiCapabilities(
        supportedTransports: _supportedTransports,
        enabledTransports: enabledTransports,
      );

  void configureTransportPolicy(MidiTransportPolicy policy) {
    _transportPolicy = policy;
  }

  bool isTransportEnabled(MidiTransport transport) =>
      enabledTransports.contains(transport);

  void _requireTransport(MidiTransport transport, String operation) {
    if (!isTransportEnabled(transport)) {
      throw StateError('$operation requires transport $transport, but it is disabled by policy.');
    }
  }
  void dispose() {
    _bluetoothStateStream.close();
    _onBluetoothStateChangedStreamSubscription?.cancel();
  }

  static MidiCommand? _instance;

  static MidiCommandPlatform? __platform;

  StreamController<Uint8List> _txStreamCtrl = StreamController.broadcast();

  final _bluetoothStateStream = StreamController<BluetoothState>.broadcast();

  var _bluetoothCentralIsStarted = false;

  BluetoothState _bluetoothState = BluetoothState.unknown;
  StreamSubscription? _onBluetoothStateChangedStreamSubscription;
  _listenToBluetoothState() async {
    _onBluetoothStateChangedStreamSubscription =
        _platform.onBluetoothStateChanged?.listen((s) {
      _bluetoothState = BluetoothState.values.byName(s);
      _bluetoothStateStream.add(_bluetoothState);
    });

    scheduleMicrotask(() async {
      if (_bluetoothState == BluetoothState.unknown) {
        _bluetoothState =
            BluetoothState.values.byName(await _platform.bluetoothState());
        _bluetoothStateStream.add(_bluetoothState);
      }
    });
  }

  /// Get the platform specific implementation
  static MidiCommandPlatform get _platform {
    if (__platform != null) return __platform!;

    __platform = MidiCommandPlatform.instance;

    return __platform!;
  }

  /// Gets a list of available MIDI devices and returns it
  Future<List<MidiDevice>?> get devices async {
    return _platform.devices;
  }

  /// Stream firing events whenever the bluetooth state changes
  Stream<BluetoothState> get onBluetoothStateChanged =>
      _bluetoothStateStream.stream.distinct();

  /// Returns the state of the bluetooth central
  BluetoothState get bluetoothState => _bluetoothState;

  /// Starts the bluetooth central
  Future<void> startBluetoothCentral() async {
    _requireTransport(MidiTransport.ble, 'startBluetoothCentral');

    if (_bluetoothCentralIsStarted) {
      return;
    }
    _bluetoothCentralIsStarted = true;
    await _platform.startBluetoothCentral();
    await _listenToBluetoothState();
  }

  /// Wait for the blueetooth state to be initialized
  ///
  /// Found devices will be included in the list returned by [devices]
  Future<void> waitUntilBluetoothIsInitialized() async {
    _requireTransport(MidiTransport.ble, 'waitUntilBluetoothIsInitialized');
    bool isInitialized() => _bluetoothState != BluetoothState.unknown;

    print(_bluetoothState);

    if (isInitialized()) {
      return;
    }

    await for (final _ in onBluetoothStateChanged) {
      if (isInitialized()) {
        break;
      }
    }
    return;
  }

  /// Starts scanning for BLE MIDI devices
  ///
  /// Found devices will be included in the list returned by [devices]
  Future<void> startScanningForBluetoothDevices() async {
    _requireTransport(MidiTransport.ble, 'startScanningForBluetoothDevices');
    return _platform.startScanningForBluetoothDevices();
  }

  /// Stop scanning for BLE MIDI devices
  void stopScanningForBluetoothDevices() {
    _requireTransport(MidiTransport.ble, 'stopScanningForBluetoothDevices');
    _platform.stopScanningForBluetoothDevices();
  }

  /// Connects to the device
  Future<void> connectToDevice(MidiDevice device) async {
    return _platform.connectToDevice(device);
  }

  /// Disconnects from the device
  void disconnectDevice(MidiDevice device) {
    _platform.disconnectDevice(device);
  }

  /// Disconnects from all devices
  void teardown() {
    _platform.teardown();
  }

  /// Sends data to the currently connected device
  ///
  /// Data is an UInt8List of individual MIDI command bytes
  void sendData(Uint8List data, {String? deviceId, int? timestamp}) {
    _platform.sendData(data, deviceId: deviceId, timestamp: timestamp);
    _txStreamCtrl.add(data);
  }

  /// Stream firing events whenever a midi package is received
  ///
  /// The event contains the raw bytes contained in the MIDI package
  Stream<MidiPacket>? get onMidiDataReceived {
    return _platform.onMidiDataReceived;
  }

  /// Stream firing events whenever a change in the MIDI setup occurs
  ///
  /// For example, when a new BLE devices is discovered
  Stream<String>? get onMidiSetupChanged {
    return _platform.onMidiSetupChanged;
  }

  /// Stream firing events whenever a midi package is sent
  ///
  /// The event contains the raw bytes contained in the MIDI package
  Stream<Uint8List> get onMidiDataSent {
    return _txStreamCtrl.stream;
  }

  /// Creates a virtual MIDI source
  ///
  /// The virtual MIDI source appears as a virtual port in other apps.
  /// Other apps can receive MIDI from this source.
  /// Currently only supported on iOS.
  void addVirtualDevice({String? name}) {
    _requireTransport(MidiTransport.virtualDevice, 'addVirtualDevice');
    _platform.addVirtualDevice(name: name);
  }

  /// Removes a previously created virtual MIDI source.
  /// Currently only supported on iOS.
  void removeVirtualDevice({String? name}) {
    _requireTransport(MidiTransport.virtualDevice, 'removeVirtualDevice');
    _platform.removeVirtualDevice(name: name);
  }

  /// Returns the current state of the network session
  ///
  /// This is functional on iOS only, will return null on other platforms
  Future<bool?> get isNetworkSessionEnabled {
    _requireTransport(MidiTransport.network, 'isNetworkSessionEnabled');
    return _platform.isNetworkSessionEnabled;
  }

  /// Sets the enabled state of the network session
  ///
  /// This is functional on iOS only
  void setNetworkSessionEnabled(bool enabled) {
    _requireTransport(MidiTransport.network, 'setNetworkSessionEnabled');
    _platform.setNetworkSessionEnabled(enabled);
  }
}

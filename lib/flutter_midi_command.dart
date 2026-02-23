import 'dart:async';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:flutter_midi_command_platform_interface/flutter_midi_command_platform_interface.dart';
import 'package:flutter_midi_command/src/midi_transports.dart';

export 'package:flutter_midi_command_platform_interface/flutter_midi_command_platform_interface.dart'
    show MidiDevice, MidiDeviceTypeWire, MidiPacket, MidiPort;
export 'package:flutter_midi_command_platform_interface/midi_device.dart'
    show MidiConnectionState, MidiDeviceType;
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

enum _MidiDeviceRoute { platform, bleTransport }

class MidiCommand {
  static const Set<MidiTransport> supportedTransports = {
    MidiTransport.serial,
    MidiTransport.ble,
    MidiTransport.network,
    MidiTransport.virtualDevice,
  };

  factory MidiCommand({MidiBleTransport? bleTransport}) {
    if (_instance == null) {
      _instance = MidiCommand._(bleTransport: bleTransport);
    } else if (bleTransport != null) {
      _instance!.configureBleTransport(bleTransport);
    }
    return _instance!;
  }

  MidiCommand._({MidiBleTransport? bleTransport})
    : _bleTransport = bleTransport;

  MidiTransportPolicy _transportPolicy = const MidiTransportPolicy();
  MidiBleTransport? _bleTransport;
  final Expando<_MidiDeviceRoute> _deviceRouteByInstance =
      Expando<_MidiDeviceRoute>('midi_device_route');
  final Map<String, _MidiDeviceRoute> _deviceRouteById =
      <String, _MidiDeviceRoute>{};

  Set<MidiTransport> get enabledTransports =>
      _transportPolicy.resolveEnabledTransports(supportedTransports);

  MidiCapabilities get capabilities => MidiCapabilities(
    supportedTransports: supportedTransports,
    enabledTransports: enabledTransports,
  );

  void configureTransportPolicy(MidiTransportPolicy policy) {
    _transportPolicy = policy;
  }

  /// Attaches or detaches the BLE implementation.
  ///
  /// Pass `null` to disable BLE integration entirely for this instance.
  void configureBleTransport(MidiBleTransport? transport) {
    if (identical(_bleTransport, transport)) {
      return;
    }
    _onBluetoothStateChangedStreamSubscription?.cancel();
    _onBluetoothStateChangedStreamSubscription = null;
    _bleTransport?.teardown();
    _bleTransport = transport;
    _bluetoothIsStarted = false;
    _bluetoothState = BluetoothState.unknown;
    _deviceRouteById.clear();
  }

  bool isTransportEnabled(MidiTransport transport) =>
      enabledTransports.contains(transport);

  void _requireTransport(MidiTransport transport, String operation) {
    if (!isTransportEnabled(transport)) {
      throw StateError(
        '$operation requires transport $transport, but it is disabled by policy.',
      );
    }
  }

  void _requireBleTransport(String operation) {
    if (_bleTransport == null) {
      throw StateError(
        '$operation requires a BLE transport implementation. '
        'Add flutter_midi_command_ble and pass UniversalBleMidiTransport() to MidiCommand().',
      );
    }
  }

  void dispose() {
    __platform?.teardown();
    _txStreamCtrl.close();
    _bluetoothStateStream.close();
    _onBluetoothStateChangedStreamSubscription?.cancel();
    _bleTransport?.teardown();
    _bleTransport = null;
    _bluetoothIsStarted = false;
    _bluetoothStartFuture = null;
    _bluetoothState = BluetoothState.unknown;
    _deviceRouteById.clear();
    if (identical(_instance, this)) {
      _instance = null;
    }
  }

  static MidiCommand? _instance;

  static MidiCommandPlatform? __platform;

  static void setPlatformOverride(MidiCommandPlatform platform) {
    __platform = platform;
  }

  static void resetForTest() {
    _instance = null;
    __platform = null;
  }

  final StreamController<Uint8List> _txStreamCtrl =
      StreamController<Uint8List>.broadcast();

  final _bluetoothStateStream = StreamController<BluetoothState>.broadcast();

  var _bluetoothIsStarted = false;
  Future<void>? _bluetoothStartFuture;

  BluetoothState _bluetoothState = BluetoothState.unknown;
  StreamSubscription? _onBluetoothStateChangedStreamSubscription;
  _listenToBluetoothState() async {
    _onBluetoothStateChangedStreamSubscription = _bleTransport
        ?.onBluetoothStateChanged
        .listen((s) {
          _bluetoothState = BluetoothState.values.byName(s);
          _bluetoothStateStream.add(_bluetoothState);
        });

    scheduleMicrotask(() async {
      if (_bluetoothState == BluetoothState.unknown) {
        _bluetoothState = BluetoothState.values.byName(
          await _bleTransport!.bluetoothState(),
        );
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
    final devices = <MidiDevice>[];
    _deviceRouteById.clear();

    final platformDevices = await _platform.devices ?? <MidiDevice>[];
    for (final device in platformDevices) {
      _rememberDeviceRoute(device, _MidiDeviceRoute.platform);
    }
    devices.addAll(platformDevices);

    if (_bleTransport != null && isTransportEnabled(MidiTransport.ble)) {
      final bleDevices = await _bleTransport!.devices;
      for (final device in bleDevices) {
        _rememberDeviceRoute(device, _MidiDeviceRoute.bleTransport);
      }
      devices.addAll(bleDevices);
    }

    return devices;
  }

  /// Stream firing events whenever the bluetooth state changes
  Stream<BluetoothState> get onBluetoothStateChanged =>
      _bluetoothStateStream.stream.distinct();

  /// Returns the current Bluetooth state
  BluetoothState get bluetoothState => _bluetoothState;

  /// Starts the Bluetooth subsystem used for BLE MIDI discovery/connection.
  Future<void> startBluetooth() async {
    _requireTransport(MidiTransport.ble, 'startBluetooth');
    _requireBleTransport('startBluetooth');

    if (_bluetoothIsStarted) {
      return;
    }
    if (_bluetoothStartFuture != null) {
      return _bluetoothStartFuture!;
    }

    _bluetoothStartFuture = () async {
      try {
        await _bleTransport!.startBluetooth();
        await _listenToBluetoothState();
        _bluetoothIsStarted = true;
      } catch (_) {
        _bluetoothIsStarted = false;
        rethrow;
      } finally {
        _bluetoothStartFuture = null;
      }
    }();

    return _bluetoothStartFuture!;
  }

  /// Wait for the blueetooth state to be initialized
  ///
  /// Found devices will be included in the list returned by [devices]
  Future<void> waitUntilBluetoothIsInitialized() async {
    _requireTransport(MidiTransport.ble, 'waitUntilBluetoothIsInitialized');
    bool isInitialized() => _bluetoothState != BluetoothState.unknown;

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
    _requireBleTransport('startScanningForBluetoothDevices');
    return _bleTransport!.startScanningForBluetoothDevices();
  }

  /// Stop scanning for BLE MIDI devices
  void stopScanningForBluetoothDevices() {
    _requireTransport(MidiTransport.ble, 'stopScanningForBluetoothDevices');
    _requireBleTransport('stopScanningForBluetoothDevices');
    _bleTransport!.stopScanningForBluetoothDevices();
  }

  /// Connects to the device
  Future<void> connectToDevice(
    MidiDevice device, {
    Duration? awaitConnectionTimeout = const Duration(seconds: 10),
  }) async {
    if (!device.connected) {
      device.setConnectionState(MidiConnectionState.connecting);
    }
    final connectionEstablished = _awaitConnectedOrFailed(device);

    try {
      final route = _resolveDeviceRoute(device);
      if (route == _MidiDeviceRoute.bleTransport) {
        _requireTransport(MidiTransport.ble, 'connectToDevice');
        _requireBleTransport('connectToDevice');
        await _bleTransport!.connectToDevice(device);
      } else {
        await _platform.connectToDevice(device);
      }
    } catch (_) {
      if (device.connectionState == MidiConnectionState.connecting) {
        device.setConnectionState(MidiConnectionState.disconnected);
      }
      rethrow;
    }

    if (device.connected) {
      return;
    }

    if (awaitConnectionTimeout == null) {
      await connectionEstablished;
      return;
    }
    try {
      await connectionEstablished.timeout(awaitConnectionTimeout);
    } on TimeoutException {
      if (device.connectionState == MidiConnectionState.connecting) {
        device.setConnectionState(MidiConnectionState.disconnected);
      }
      rethrow;
    }
  }

  /// Disconnects from the device
  void disconnectDevice(MidiDevice device) {
    if (device.connected) {
      device.setConnectionState(MidiConnectionState.disconnecting);
    }
    final route = _resolveDeviceRoute(device);
    if (route == _MidiDeviceRoute.bleTransport) {
      _requireTransport(MidiTransport.ble, 'disconnectDevice');
      _requireBleTransport('disconnectDevice');
      _bleTransport!.disconnectDevice(device);
      return;
    }
    _platform.disconnectDevice(device);
  }

  /// Disconnects from all devices
  void teardown() {
    _platform.teardown();
    _bleTransport?.teardown();
    _deviceRouteById.clear();
  }

  /// Sends data to the currently connected device
  ///
  /// Data is an UInt8List of individual MIDI command bytes
  void sendData(Uint8List data, {String? deviceId, int? timestamp}) {
    if (deviceId != null) {
      final route = _deviceRouteById[deviceId];
      if (route == _MidiDeviceRoute.platform) {
        _platform.sendData(data, deviceId: deviceId, timestamp: timestamp);
        _txStreamCtrl.add(data);
        return;
      }
      if (route == _MidiDeviceRoute.bleTransport &&
          _bleTransport != null &&
          isTransportEnabled(MidiTransport.ble)) {
        _bleTransport!.sendData(data, deviceId: deviceId, timestamp: timestamp);
        _txStreamCtrl.add(data);
        return;
      }
    }

    _platform.sendData(data, deviceId: deviceId, timestamp: timestamp);
    if (_bleTransport != null && isTransportEnabled(MidiTransport.ble)) {
      _bleTransport!.sendData(data, deviceId: deviceId, timestamp: timestamp);
    }
    _txStreamCtrl.add(data);
  }

  /// Stream firing events whenever a midi package is received
  ///
  /// The event contains the raw bytes contained in the MIDI package
  Stream<MidiPacket>? get onMidiDataReceived {
    final streams = <Stream<MidiPacket>>[];
    if (_platform.onMidiDataReceived != null) {
      streams.add(_platform.onMidiDataReceived!);
    }
    if (_bleTransport != null && isTransportEnabled(MidiTransport.ble)) {
      streams.add(_bleTransport!.onMidiDataReceived);
    }
    if (streams.isEmpty) {
      return null;
    }
    if (streams.length == 1) {
      return streams.first;
    }
    return StreamGroup.merge(streams).asBroadcastStream();
  }

  /// Stream firing events whenever a change in the MIDI setup occurs
  ///
  /// For example, when a new BLE devices is discovered
  Stream<String>? get onMidiSetupChanged {
    final streams = <Stream<String>>[];
    if (_platform.onMidiSetupChanged != null) {
      streams.add(_platform.onMidiSetupChanged!);
    }
    if (_bleTransport != null && isTransportEnabled(MidiTransport.ble)) {
      streams.add(_bleTransport!.onMidiSetupChanged);
    }
    if (streams.isEmpty) {
      return null;
    }
    if (streams.length == 1) {
      return streams.first;
    }
    return StreamGroup.merge(streams).asBroadcastStream();
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

  Future<void> _awaitConnectedOrFailed(MidiDevice device) {
    if (device.connected) {
      return Future<void>.value();
    }

    final completer = Completer<void>();
    var wasConnecting =
        device.connectionState == MidiConnectionState.connecting;
    late StreamSubscription<MidiConnectionState> sub;

    void completeSuccess() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    void completeFailure() {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Failed to connect to MIDI device ${device.id}.'),
        );
      }
    }

    sub = device.onConnectionStateChanged.listen((state) {
      if (state == MidiConnectionState.connecting) {
        wasConnecting = true;
        return;
      }
      if (state == MidiConnectionState.connected) {
        completeSuccess();
        return;
      }
      if (state == MidiConnectionState.disconnected && wasConnecting) {
        completeFailure();
      }
    });

    if (device.connected) {
      completeSuccess();
    } else if (device.connectionState == MidiConnectionState.disconnected &&
        wasConnecting) {
      completeFailure();
    }

    return completer.future.whenComplete(() => sub.cancel());
  }

  void _rememberDeviceRoute(MidiDevice device, _MidiDeviceRoute route) {
    _deviceRouteByInstance[device] = route;
    if (device.id.isNotEmpty) {
      _deviceRouteById.putIfAbsent(device.id, () => route);
    }
  }

  _MidiDeviceRoute _resolveDeviceRoute(MidiDevice device) {
    final byInstance = _deviceRouteByInstance[device];
    if (byInstance != null) {
      return byInstance;
    }

    final byId = _deviceRouteById[device.id];
    if (byId != null) {
      return byId;
    }

    if (device.type == MidiDeviceType.ble && _bleTransport != null) {
      return _MidiDeviceRoute.bleTransport;
    }

    return _MidiDeviceRoute.platform;
  }
}

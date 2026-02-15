package com.invisiblewrench.fluttermidicommand

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.midi.MidiDevice
import android.media.midi.MidiDeviceInfo
import android.media.midi.MidiDeviceStatus
import android.media.midi.MidiManager
import android.os.Handler
import com.invisiblewrench.fluttermidicommand.pigeon.FlutterError
import com.invisiblewrench.fluttermidicommand.pigeon.MidiDeviceType
import com.invisiblewrench.fluttermidicommand.pigeon.MidiFlutterApi
import com.invisiblewrench.fluttermidicommand.pigeon.MidiHostApi
import com.invisiblewrench.fluttermidicommand.pigeon.MidiHostDevice
import com.invisiblewrench.fluttermidicommand.pigeon.MidiPacket
import com.invisiblewrench.fluttermidicommand.pigeon.MidiPort
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger

/** FlutterMidiCommandPlugin */
class FlutterMidiCommandPlugin : FlutterPlugin, ActivityAware, MidiHostApi {

  private lateinit var context: Context
  private var activity: Activity? = null
  private lateinit var messenger: BinaryMessenger

  private lateinit var midiManager: MidiManager
  private lateinit var handler: Handler

  private var isSupported: Boolean = false
  private var isMidiCallbackRegistered: Boolean = false

  private val connectedDevices = mutableMapOf<String, Device>()
  private lateinit var flutterApi: MidiFlutterApi

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    messenger = binding.binaryMessenger
    context = binding.applicationContext
    handler = Handler(context.mainLooper)

    isSupported = context.packageManager.hasSystemFeature(PackageManager.FEATURE_MIDI)

    flutterApi = MidiFlutterApi(messenger)
    MidiHostApi.setUp(messenger, this)

    if (!isSupported) {
      MidiLogger.debug("MIDI not supported")
      return
    }

    midiManager = context.getSystemService(Context.MIDI_SERVICE) as MidiManager
    midiManager.registerDeviceCallback(deviceConnectionCallback, handler)
    isMidiCallbackRegistered = true

    VirtualDeviceService.onDataReceived = this::sendDataPacket
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    teardownInternal()
    MidiHostApi.setUp(messenger, null)
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivity() {
    activity = null
  }

  private fun sendSetupUpdate(update: String) {
    handler.post {
      flutterApi.onSetupChanged(update) { result ->
        result.exceptionOrNull()?.let {
          MidiLogger.debug("Failed to send setup update: $it")
        }
      }
    }
  }

  private fun sendConnectionStateUpdate(deviceId: String, connected: Boolean) {
    handler.post {
      flutterApi.onDeviceConnectionStateChanged(deviceId, connected) { result ->
        result.exceptionOrNull()?.let {
          MidiLogger.debug("Failed to send connection state update: $it")
        }
      }
    }
  }

  private fun sendDataPacket(packet: MidiPacket) {
    handler.post {
      flutterApi.onDataReceived(packet) { result ->
        result.exceptionOrNull()?.let {
          MidiLogger.debug("Failed to send MIDI packet: $it")
        }
      }
    }
  }

  override fun listDevices(): List<MidiHostDevice> {
    if (!isSupported) {
      return emptyList()
    }

    return midiManager.devices
      .mapNotNull { info ->
        val type = mapDeviceType(info)

        // BLE transport is intentionally implemented in shared Dart code.
        if (type == MidiDeviceType.BLE) {
          return@mapNotNull null
        }

        val id = Device.deviceIdForInfo(info)
        MidiHostDevice(
          id = id,
          name = info.properties.getString(MidiDeviceInfo.PROPERTY_NAME) ?: "-",
          type = type,
          connected = connectedDevices.contains(id),
          inputs = listOfPorts(info.inputPortCount, isInput = true),
          outputs = listOfPorts(info.outputPortCount, isInput = false),
        )
      }
  }

  override fun connect(device: MidiHostDevice, ports: List<MidiPort>?) {
    if (!isSupported) {
      throw FlutterError("ERROR", "MIDI not supported", null)
    }

    val deviceId = device.id ?: throw FlutterError("ERROR", "Missing device id", null)
    val deviceType = device.type ?: MidiDeviceType.UNKNOWN

    if (deviceType == MidiDeviceType.BLE) {
      throw FlutterError("ERROR", "bluetoothNotAvailable", null)
    }

    val target = midiManager.devices.firstOrNull { info -> Device.deviceIdForInfo(info) == deviceId }
      ?: throw FlutterError("ERROR", "Device not found", null)

    midiManager.openDevice(target, { openedDevice: MidiDevice? ->
      if (openedDevice == null) {
        sendSetupUpdate("connectionFailed")
        sendConnectionStateUpdate(deviceId, false)
        return@openDevice
      }

      val connectedDevice = ConnectedDevice(
        openedDevice,
        this::sendSetupUpdate,
        this::sendDataPacket,
        this::sendConnectionStateUpdate,
      )
      connectedDevices[connectedDevice.id] = connectedDevice
      connectedDevice.connect()
    }, handler)
  }

  override fun disconnect(deviceId: String) {
    connectedDevices[deviceId]?.also {
      it.close()
      connectedDevices.remove(deviceId)
    }
  }

  override fun teardown() {
    teardownInternal()
  }

  private fun teardownInternal() {
    stopVirtualService()

    connectedDevices.values.forEach { device ->
      device.close()
    }
    connectedDevices.clear()

    if (isSupported && isMidiCallbackRegistered) {
      midiManager.unregisterDeviceCallback(deviceConnectionCallback)
      isMidiCallbackRegistered = false
    }

    VirtualDeviceService.onDataReceived = null
  }

  override fun sendData(packet: MidiPacket) {
    val data = packet.data ?: return
    val timestamp = packet.timestamp
    val deviceId = packet.device?.id

    if (deviceId != null) {
      connectedDevices[deviceId]?.send(data, timestamp)
      return
    }

    connectedDevices.values.forEach { device ->
      device.send(data, timestamp)
    }
  }

  override fun addVirtualDevice(name: String?) {
    startVirtualService()
  }

  override fun removeVirtualDevice(name: String?) {
    stopVirtualService()
  }

  override fun isNetworkSessionEnabled(): Boolean? {
    return false
  }

  override fun setNetworkSessionEnabled(enabled: Boolean) {
    // Android has no equivalent CoreMIDI network session.
  }

  private fun listOfPorts(count: Int, isInput: Boolean): List<MidiPort> {
    return (0 until count).map { index ->
      MidiPort(
        id = index.toLong(),
        connected = false,
        isInput = isInput,
      )
    }
  }

  private fun mapDeviceType(info: MidiDeviceInfo): MidiDeviceType {
    val serviceInfo = info.properties.getParcelable<ServiceInfo>("service_info")
    return when {
      serviceInfo?.name == "com.invisiblewrench.fluttermidicommand.VirtualDeviceService" -> MidiDeviceType.OWN_VIRTUAL
      info.type == MidiDeviceInfo.TYPE_BLUETOOTH -> MidiDeviceType.BLE
      info.type == MidiDeviceInfo.TYPE_VIRTUAL -> MidiDeviceType.VIRTUAL_DEVICE
      else -> MidiDeviceType.SERIAL
    }
  }

  private fun startVirtualService() {
    val component = ComponentName(context, "com.invisiblewrench.fluttermidicommand.VirtualDeviceService")
    context.packageManager.setComponentEnabledSetting(
      component,
      PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
      PackageManager.SYNCHRONOUS or PackageManager.DONT_KILL_APP,
    )
  }

  private fun stopVirtualService() {
    val component = ComponentName(context, "com.invisiblewrench.fluttermidicommand.VirtualDeviceService")
    context.packageManager.setComponentEnabledSetting(
      component,
      PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
      PackageManager.DONT_KILL_APP,
    )
  }

  private val deviceConnectionCallback = object : MidiManager.DeviceCallback() {

    override fun onDeviceAdded(device: MidiDeviceInfo?) {
      super.onDeviceAdded(device)
      if (device != null) {
        sendSetupUpdate("deviceFound")
      }
    }

    override fun onDeviceRemoved(device: MidiDeviceInfo?) {
      super.onDeviceRemoved(device)
      if (device == null) {
        return
      }

      val id = Device.deviceIdForInfo(device)
      connectedDevices[id]?.also {
        connectedDevices.remove(id)
        sendConnectionStateUpdate(id, false)
      }
      sendSetupUpdate("deviceLost")
    }

    override fun onDeviceStatusChanged(status: MidiDeviceStatus?) {
      super.onDeviceStatusChanged(status)
      if (status != null) {
        sendSetupUpdate(status.toString())
      }
    }
  }
}

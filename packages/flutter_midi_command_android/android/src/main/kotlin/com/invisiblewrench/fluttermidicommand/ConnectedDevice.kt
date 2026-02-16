package com.invisiblewrench.fluttermidicommand

import android.content.pm.ServiceInfo
import android.media.midi.*
import com.invisiblewrench.fluttermidicommand.pigeon.MidiDeviceType
import com.invisiblewrench.fluttermidicommand.pigeon.MidiHostDevice
import com.invisiblewrench.fluttermidicommand.pigeon.MidiPacket

class ConnectedDevice(
    device: MidiDevice,
    private val onSetupChanged: (String) -> Unit,
    private val onDataReceived: (MidiPacket) -> Unit,
    private val onConnectionChanged: (String, Boolean) -> Unit,
    private val deviceType: MidiDeviceType,
) : Device(deviceIdForInfo(device.info), device.info.type.toString()) {
    var inputPort: MidiInputPort? = null
    var outputPort: MidiOutputPort? = null

    private var isOwnVirtualDevice = false

    init {
        this.midiDevice = device
    }

    override fun connect() {
        this.midiDevice.info.let {
            val serviceInfo = it.properties.getParcelable<ServiceInfo>("service_info")
            if (serviceInfo?.name == "com.invisiblewrench.fluttermidicommand.VirtualDeviceService") {
                isOwnVirtualDevice = true
                this.receiver = RXReceiver(_toHostDevice(MidiDeviceType.OWN_VIRTUAL), onDataReceived)
            } else {
                this.receiver = RXReceiver(_toHostDevice(deviceType), onDataReceived)
                if (it.inputPortCount > 0) {
                    this.inputPort = this.midiDevice.openInputPort(0)
                }
            }
            if (it.outputPortCount > 0) {
                this.outputPort = this.midiDevice.openOutputPort(0)
                this.outputPort?.connect(this.receiver)
            }
        }
        onSetupChanged("deviceConnected")
        onConnectionChanged(id, true)
    }

    private fun _toHostDevice(type: MidiDeviceType): MidiHostDevice {
        return MidiHostDevice(
            id = deviceIdForInfo(this.midiDevice.info),
            name = this.midiDevice.info.properties.getString(MidiDeviceInfo.PROPERTY_NAME),
            type = type,
            connected = true,
            inputs = null,
            outputs = null,
        )
    }

    override fun send(data: ByteArray, timestamp: Long?) {
        if(isOwnVirtualDevice) {
            if (timestamp == null)
                this.receiver?.send(data, 0, data.size)
            else
                this.receiver?.send(data, 0, data.size, timestamp)

        } else {
            this.inputPort?.send(data, 0, data.count(), if (timestamp is Long) timestamp else 0)
        }
    }

    override fun close() {
        this.inputPort?.flush()
        this.inputPort?.close()
        this.outputPort?.close()
        this.outputPort?.disconnect(this.receiver)
        this.receiver = null
        this.midiDevice.close()

        onSetupChanged("deviceDisconnected")
        onConnectionChanged(id, false)
    }

    class RXReceiver(
        private val deviceInfo: MidiHostDevice,
        private val onDataReceived: (MidiPacket) -> Unit,
    ) : MidiReceiver() {
        private val parser = MidiPacketParser { bytes, timestamp ->
            onDataReceived(
                MidiPacket(
                    device = deviceInfo,
                    data = bytes,
                    timestamp = timestamp,
                ),
            )
        }

        override fun onSend(msg: ByteArray?, offset: Int, count: Int, timestamp: Long) {
            msg?.also { parser.parse(it, offset, count, timestamp) }
        }
    }

}

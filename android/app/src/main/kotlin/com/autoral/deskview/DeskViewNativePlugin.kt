package com.autoral.deskview

import android.content.Context
import android.content.Intent
import android.hardware.input.InputManager
import android.provider.Settings
import android.view.InputDevice

/**
 * Gerenciador nativo Android para detecção em tempo real (e hotplug) de mouses USB/Bluetooth,
 * teclados físicos, controles de videogame (Gamepad) e Joysticks via InputManager.
 */
class DeskViewNativePlugin(private val context: Context) : InputManager.InputDeviceListener {

    private val inputManager = context.getSystemService(Context.INPUT_SERVICE) as InputManager
    var onPeripheralsChanged: ((List<Map<String, Any>>) -> Unit)? = null

    fun startListening() {
        inputManager.registerInputDeviceListener(this, null)
    }

    fun stopListening() {
        inputManager.unregisterInputDeviceListener(this)
    }

    fun enumerateConnectedPeripherals(): List<Map<String, Any>> {
        val result = mutableListOf<Map<String, Any>>()
        for (deviceId in inputManager.inputDeviceIds) {
            val dev = inputManager.getInputDevice(deviceId) ?: continue
            if (dev.isVirtual) continue

            val sources = dev.sources
            val category = when {
                (sources and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD -> "gamepad"
                (sources and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK -> "joystick"
                (sources and InputDevice.SOURCE_MOUSE) == InputDevice.SOURCE_MOUSE -> "mouse"
                (sources and InputDevice.SOURCE_KEYBOARD) == InputDevice.SOURCE_KEYBOARD -> "keyboard"
                else -> continue
            }

            val vendorHex = dev.vendorId.toString(16).padStart(4, '0').uppercase()
            val productHex = dev.productId.toString(16).padStart(4, '0').uppercase()

            result.add(
                mapOf(
                    "id" to "android_dev_${dev.id}",
                    "name" to dev.name,
                    "category" to category,
                    "vendorProductId" to "$vendorHex:$productHex",
                    "isConnected" to true,
                    "isTransmitEnabled" to true,
                    "buttonCount" to 16,
                    "axisCount" to dev.motionRanges.size,
                    "connectionBus" to if (dev.isExternal) "USB OTG / Bluetooth" else "Interno"
                )
            )
        }
        return result
    }

    fun openAccessibilitySettings() {
        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    override fun onInputDeviceAdded(deviceId: Int) {
        onPeripheralsChanged?.invoke(enumerateConnectedPeripherals())
    }

    override fun onInputDeviceRemoved(deviceId: Int) {
        onPeripheralsChanged?.invoke(enumerateConnectedPeripherals())
    }

    override fun onInputDeviceChanged(deviceId: Int) {
        onPeripheralsChanged?.invoke(enumerateConnectedPeripherals())
    }
}

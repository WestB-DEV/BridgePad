package dev.bridgepad.bridgepad

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "dev.bridgepad.bridgepad/android"
    private val permissionRequestCode = 4101
    private var permissionResult: MethodChannel.Result? = null
    private var bondResult: MethodChannel.Result? = null

    private val bondReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != BluetoothDevice.ACTION_BOND_STATE_CHANGED) return
            val state = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.ERROR)
            if (state == BluetoothDevice.BOND_BONDED) finishBond(true)
            if (state == BluetoothDevice.BOND_NONE) finishBond(false)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler(::handleMethodCall)
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestBlePermissions" -> requestBlePermissions(result)
            "bond" -> bond(call.argument<String>("deviceId"), result)
            else -> result.notImplemented()
        }
    }

    private fun requestBlePermissions(result: MethodChannel.Result) {
        val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        if (permissions.all { ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED }) {
            result.success(true)
            return
        }
        if (permissionResult != null) {
            result.error("busy", "A permission request is already active", null)
            return
        }
        permissionResult = result
        requestPermissions(permissions, permissionRequestCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequestCode) return
        val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        permissionResult?.success(granted)
        permissionResult = null
    }

    private fun bond(deviceId: String?, result: MethodChannel.Result) {
        if (deviceId.isNullOrBlank()) {
            result.error("invalid_device", "Missing Bluetooth device ID", null)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED
        ) {
            result.error("permissions_denied", "Bluetooth connect permission is required", null)
            return
        }
        val adapter = BluetoothAdapter.getDefaultAdapter()
        if (adapter == null || !adapter.isEnabled) {
            result.error("bluetooth_off", "Turn Bluetooth on and try again", null)
            return
        }
        val device = try {
            adapter.getRemoteDevice(deviceId)
        } catch (_: IllegalArgumentException) {
            result.error("invalid_device", "The selected Bluetooth device is invalid", null)
            return
        }
        if (device.bondState == BluetoothDevice.BOND_BONDED) {
            result.success(true)
            return
        }
        if (bondResult != null) {
            result.error("busy", "A pairing request is already active", null)
            return
        }
        bondResult = result
        val filter = IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(bondReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(bondReceiver, filter)
        }
        if (!device.createBond()) finishBond(false)
    }

    private fun finishBond(success: Boolean) {
        try {
            unregisterReceiver(bondReceiver)
        } catch (_: IllegalArgumentException) {
            // Receiver was already removed.
        }
        bondResult?.success(success)
        bondResult = null
    }

    override fun onDestroy() {
        if (bondResult != null) finishBond(false)
        permissionResult?.error("cancelled", "Activity closed", null)
        permissionResult = null
        super.onDestroy()
    }
}

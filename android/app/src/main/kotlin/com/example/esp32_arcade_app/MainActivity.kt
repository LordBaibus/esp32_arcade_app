package com.example.esp32_arcade_app

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Small bridge used by lib/native_network.dart.
 *
 * When the phone joins a Wi-Fi network that has no internet, Android can
 * quietly send an app's traffic over mobile data instead. bindToWifi() pins
 * this app's traffic to the Wi-Fi network so the ESP32 is always reached.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "arcade/network"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "bindToWifi" -> result.success(bindToWifi())
                    "wifiConnected" -> result.success(findWifiNetwork() != null)
                    "openWifiSettings" -> result.success(openWifiSettings())
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun findWifiNetwork(): Network? {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return null
        for (network in cm.allNetworks) {
            val caps = cm.getNetworkCapabilities(network) ?: continue
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) return network
        }
        return null
    }

    private fun bindToWifi(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        return try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false
            val wifi = findWifiNetwork() ?: return false
            cm.bindProcessToNetwork(wifi)
        } catch (e: Exception) {
            false
        }
    }

    private fun openWifiSettings(): Boolean {
        return try {
            startActivity(Intent(Settings.ACTION_WIFI_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (e: Exception) {
            false
        }
    }
}

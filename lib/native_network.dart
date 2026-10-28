import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin wrapper over the Android side in MainActivity.kt.
///
/// Why it exists: when a phone joins a Wi-Fi network that has no internet,
/// Android can quietly send app traffic over mobile data instead. The ESP32
/// answers Android's connectivity check so that rarely happens, but binding
/// the app's own traffic to the Wi-Fi network makes it certain.
///
/// Every call is best effort and never throws -- on iOS / desktop / tests it
/// simply does nothing.
class NativeNetwork {
  NativeNetwork._();

  static const MethodChannel _channel = MethodChannel('arcade/network');

  static bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Sends this app's network traffic over Wi-Fi. Returns true when bound.
  static Future<bool> bindToWifi() async {
    if (!_isAndroid) return false;
    try {
      return (await _channel.invokeMethod<bool>('bindToWifi')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// True when the phone is on any Wi-Fi network right now (Android only).
  /// Returns null where that can't be checked.
  static Future<bool?> wifiConnected() async {
    if (!_isAndroid) return null;
    try {
      return await _channel.invokeMethod<bool>('wifiConnected');
    } catch (_) {
      return null;
    }
  }

  /// Opens the phone's Wi-Fi settings page (Android only).
  static Future<bool> openWifiSettings() async {
    if (!_isAndroid) return false;
    try {
      return (await _channel.invokeMethod<bool>('openWifiSettings')) ?? false;
    } catch (_) {
      return false;
    }
  }
}

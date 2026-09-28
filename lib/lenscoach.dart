/// LensCoach — Platform Bridge
///
/// Bridges Flutter UI with Kotlin native camera/ML/sensor plugin
/// via MethodChannel (commands) and EventChannel (continuous streams).
library;

import 'dart:async';
import 'package:flutter/services.dart';

class LenscoachBridge {
  static const MethodChannel _methodChannel =
      MethodChannel('com.lenscoach/method');
  static const EventChannel _sensorChannel =
      EventChannel('com.lenscoach/sensors');

  /// Start the camera session. Returns the texture ID for preview.
  static Future<int?> startCamera() async {
    final result = await _methodChannel.invokeMethod<int>('startCamera');
    return result;
  }

  /// Stop the camera session.
  static Future<void> stopCamera() async {
    await _methodChannel.invokeMethod('stopCamera');
  }

  /// Capture a photo. Returns the saved file URI.
  static Future<String?> capturePhoto() async {
    final result = await _methodChannel.invokeMethod<String>('capturePhoto');
    return result;
  }

  /// Set the active scene type (landscape, architecture, portrait, street, macro, lowlight).
  static Future<void> setSceneType(String sceneType) async {
    await _methodChannel.invokeMethod('setSceneType', {'sceneType': sceneType});
  }

  /// Get the current texture ID for the camera preview.
  static Future<int?> getTextureId() async {
    final result = await _methodChannel.invokeMethod<int>('getTextureId');
    return result;
  }

  /// Get a single snapshot of sensor data.
  static Future<Map<String, dynamic>?> getSensorData() async {
    final result = await _methodChannel.invokeMethod<Map>('getSensorData');
    return result?.cast<String, dynamic>();
  }

  /// Trigger tap-to-segment at normalized coordinates (0.0–1.0).
  /// Returns segmentation result + composition guidance, or null if failed.
  static Future<Map<String, dynamic>?> tapToSegment(double x, double y) async {
    final result = await _methodChannel.invokeMethod<Map>(
      'tapToSegment',
      {'x': x, 'y': y},
    );
    return result?.cast<String, dynamic>();
  }

  /// Deselect the current subject (clear segmentation).
  static Future<void> deselectSubject() async {
    await _methodChannel.invokeMethod('deselectSubject');
  }

  /// Get current thermal status.
  static Future<Map<String, dynamic>?> getThermalStatus() async {
    final result = await _methodChannel.invokeMethod<Map>('getThermalStatus');
    return result?.cast<String, dynamic>();
  }

  /// Stream continuous sensor data updates (~30fps).
  static Stream<Map<String, dynamic>> get sensorDataStream {
    return _sensorChannel.receiveBroadcastStream().map((event) {
      return (event as Map).cast<String, dynamic>();
    });
  }
}

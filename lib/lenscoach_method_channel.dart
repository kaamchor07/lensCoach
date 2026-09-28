import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'lenscoach_platform_interface.dart';

/// An implementation of [LenscoachPlatform] that uses method channels.
class MethodChannelLenscoach extends LenscoachPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('com.lenscoach/method');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'lenscoach_method_channel.dart';

abstract class LenscoachPlatform extends PlatformInterface {
  /// Constructs a LenscoachPlatform.
  LenscoachPlatform() : super(token: _token);

  static final Object _token = Object();

  static LenscoachPlatform _instance = MethodChannelLenscoach();

  /// The default instance of [LenscoachPlatform] to use.
  ///
  /// Defaults to [MethodChannelLenscoach].
  static LenscoachPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [LenscoachPlatform] when
  /// they register themselves.
  static set instance(LenscoachPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}

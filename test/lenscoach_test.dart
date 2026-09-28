import 'package:flutter_test/flutter_test.dart';
import 'package:lenscoach/lenscoach.dart';
import 'package:lenscoach/lenscoach_platform_interface.dart';
import 'package:lenscoach/lenscoach_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockLenscoachPlatform
    with MockPlatformInterfaceMixin
    implements LenscoachPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final LenscoachPlatform initialPlatform = LenscoachPlatform.instance;

  test('$MethodChannelLenscoach is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelLenscoach>());
  });

  test('getPlatformVersion', () async {
    Lenscoach lenscoachPlugin = Lenscoach();
    MockLenscoachPlatform fakePlatform = MockLenscoachPlatform();
    LenscoachPlatform.instance = fakePlatform;

    expect(await lenscoachPlugin.getPlatformVersion(), '42');
  });
}

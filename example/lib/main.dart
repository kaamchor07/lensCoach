import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import 'package:permission_handler/permission_handler.dart';
import 'package:lenscoach/lenscoach.dart';
import 'package:lenscoach/models/scene_type.dart';
import 'package:lenscoach/models/hud_state.dart';
import 'package:lenscoach/utils/scoring.dart';
import 'package:lenscoach/utils/constants.dart';

import 'widgets/hud_bar.dart';
import 'widgets/shutter_button.dart';
import 'widgets/scene_selector.dart';
import 'widgets/overlay_painter.dart';
import 'widgets/guidance_painter.dart';
import 'widgets/post_shot_review.dart';
import 'package:lenscoach/models/guidance_payload.dart';
import 'dart:io';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const LensCoachApp());
}

class LensCoachApp extends StatelessWidget {
  const LensCoachApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LensCoach',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          secondary: Color(0xFFFFAB00),
          surface: Color(0xFF1A1A2E),
        ),
      ),
      home: const ViewfinderScreen(),
    );
  }
}

class ViewfinderScreen extends StatefulWidget {
  const ViewfinderScreen({super.key});

  @override
  State<ViewfinderScreen> createState() => _ViewfinderScreenState();
}

class _ViewfinderScreenState extends State<ViewfinderScreen>
    with TickerProviderStateMixin {
  // Camera state
  int? _textureId;
  bool _cameraReady = false;
  bool _permissionDenied = false;
  int _cameraRotation = 90; // Default portrait rotation on Android back camera

  // Scene & overlay state
  SceneType _currentScene = SceneType.street;
  int _overlayStyleIndex = 0;

  // HUD state
  HudState _hudState = HudState.defaultState();

  // Scoring
  ConfidenceScore _confidenceScore = ConfidenceScore.mock();

  // Sensor stream
  StreamSubscription? _sensorSubscription;

  // Touch tracking for HUD opacity
  DateTime _lastTouchTime = DateTime.now();
  bool _isTouching = false;

  // Tap-to-segment state
  GuidancePayload? _guidancePayload;
  Map<String, dynamic>? _segmentationResult;

  // Post-shot review state
  Uint8List? _capturedImageBytes;
  bool _showReview = false;

  // Animation controllers
  late AnimationController _overlayFadeController;
  late Animation<double> _overlayFadeAnimation;

  @override
  void initState() {
    super.initState();

    _overlayFadeController = AnimationController(
      duration: const Duration(milliseconds: overlayCrossfadeMs),
      vsync: this,
    );
    _overlayFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _overlayFadeController, curve: Curves.easeInOut),
    );
    _overlayFadeController.forward();

    _requestPermissionAndStart();
  }

  Future<void> _requestPermissionAndStart() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      await _startCamera();
    } else if (status.isPermanentlyDenied) {
      if (mounted) {
        setState(() => _permissionDenied = true);
      }
      openAppSettings();
    } else {
      if (mounted) {
        setState(() => _permissionDenied = true);
      }
    }
  }

  Future<void> _startCamera() async {
    try {
      final textureId = await LenscoachBridge.startCamera();
      if (textureId != null && mounted) {
        setState(() {
          _textureId = textureId;
          _cameraReady = true;
        });
        _startSensorStream();
      }
    } on PlatformException catch (e) {
      debugPrint('Camera error: ${e.message}');
    }
  }

  void _startSensorStream() {
    _sensorSubscription = LenscoachBridge.sensorDataStream.listen(
      (data) {
        if (!mounted) return;
        setState(() {
          // Parse HUD state from sensor data
          final hudMap = data['hud'] as Map<String, dynamic>?;
          _hudState = HudState.fromMap(hudMap);

          // Update confidence score with real settings score
          final cameraMeta = data['cameraMetadata'] as Map<String, dynamic>?;
          final afConfidence = cameraMeta?['afConfidence'] as double? ?? 0.8;
          
          if (cameraMeta != null && cameraMeta['rotationDegrees'] != null) {
            _cameraRotation = cameraMeta['rotationDegrees'] as int;
          }

          // Parse composition engine outputs if we have segmentation active
          final segMap = data['segmentation'] as Map<String, dynamic>?;
          if (segMap != null) {
            _segmentationResult = segMap;
          }

          _confidenceScore = ConfidenceScore.compute(
            compositionScore: _guidancePayload?.compositionScore ?? 1.0,
            settingsScore: _hudState.settingsScore,
            focusScore: afConfidence,
          );
        });
      },
      onError: (e) => debugPrint('Sensor stream error: $e'),
    );
  }

  void _onSceneChanged(SceneType scene) {
    setState(() {
      _currentScene = scene;
      _overlayStyleIndex = 0;
    });
    _overlayFadeController.reset();
    _overlayFadeController.forward();
    LenscoachBridge.setSceneType(scene.channelValue);
  }

  void _cycleOverlayStyle() {
    setState(() {
      _overlayStyleIndex = (_overlayStyleIndex + 1) % 3;
    });
    _overlayFadeController.reset();
    _overlayFadeController.forward();
  }

  Future<void> _capturePhoto() async {
    try {
      // Haptic feedback based on tier
      switch (_confidenceScore.tier) {
        case ScoreTier.good:
          HapticFeedback.lightImpact();
          break;
        case ScoreTier.excellent:
          HapticFeedback.mediumImpact();
          await Future.delayed(const Duration(milliseconds: 100));
          HapticFeedback.mediumImpact();
          break;
        default:
          break;
      }

      final path = await LenscoachBridge.capturePhoto();
      if (path != null && mounted) {
        // Read image bytes for the review
        final file = File(path.replaceFirst('file://', ''));
        final bytes = await file.readAsBytes();

        setState(() {
          _capturedImageBytes = bytes;
          _showReview = true;
        });
      }
    } catch (e) {
      debugPrint('Capture error: $e');
    }
  }

  void _dismissReview() {
    setState(() {
      _showReview = false;
      _capturedImageBytes = null;
    });
  }

  @override
  void dispose() {
    _sensorSubscription?.cancel();
    _overlayFadeController.dispose();
    LenscoachBridge.stopCamera();
    super.dispose();
  }

  double get _currentOverlayOpacity {
    // Reduce opacity when user is actively composing (touching screen)
    if (_isTouching) return overlayActiveOpacity;
    return overlayDefaultOpacity;
  }

  double get _hudOpacity {
    final elapsed = DateTime.now().difference(_lastTouchTime);
    if (elapsed.inSeconds > 2) return hudIdleOpacity;
    return 1.0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Listener(
        onPointerDown: (_) {
          setState(() {
            _isTouching = true;
            _lastTouchTime = DateTime.now();
          });
        },
        onPointerUp: (_) {
          setState(() => _isTouching = false);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Layer 1: Camera preview
            _buildCameraPreview(),

            // Layer 2: Composition overlays and tap detection
            GestureDetector(
              onTapUp: _onTapToSegment,
              child: AnimatedBuilder(
                animation: _overlayFadeAnimation,
                builder: (context, child) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(
                        painter: OverlayPainter(
                          sceneType: _currentScene,
                          styleIndex: _overlayStyleIndex,
                          opacity: _currentOverlayOpacity *
                              _overlayFadeAnimation.value,
                          horizonAngle: 0, // Will be wired to sensor in integration
                        ),
                        size: Size.infinite,
                      ),
                      if (_guidancePayload != null && _segmentationResult != null)
                        CustomPaint(
                          painter: GuidancePainter(
                            guidance: _guidancePayload,
                            opacity: _currentOverlayOpacity,
                            showSubjectOutline: true,
                            bboxLeft: _segmentationResult!['bboxLeft'] as double?,
                            bboxTop: _segmentationResult!['bboxTop'] as double?,
                            bboxRight: _segmentationResult!['bboxRight'] as double?,
                            bboxBottom: _segmentationResult!['bboxBottom'] as double?,
                            maskConfidence: (_segmentationResult!['confidence'] as num?)?.toDouble() ?? 1.0,
                          ),
                          size: Size.infinite,
                        ),
                    ],
                  );
                },
              ),
            ),

            // Layer 3: UI controls
            SafeArea(
              child: Column(
                children: [
                  // Top bar: scene selector
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        // Scene selector
                        Expanded(
                          child: SceneSelector(
                            currentScene: _currentScene,
                            onSceneChanged: _onSceneChanged,
                          ),
                        ),
                        // Overlay cycle button
                        _buildOverlayCycleButton(),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Bottom: HUD + Shutter
                  AnimatedOpacity(
                    opacity: _hudOpacity,
                    duration: const Duration(milliseconds: 300),
                    child: HudBar(hudState: _hudState),
                  ),

                  const SizedBox(height: 16),

                  // Shutter button with confidence ring
                  Padding(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: ShutterButton(
                      tier: _confidenceScore.tier,
                      score: _confidenceScore.finalScore,
                      onCapture: _capturePhoto,
                    ),
                  ),
                ],
              ),
            ),

            // Layer 4: Post-shot review overlay
            if (_showReview && _capturedImageBytes != null)
              Positioned.fill(
                child: PostShotReview(
                  imageBytes: _capturedImageBytes!,
                  onDismiss: _dismissReview,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _onTapToSegment(TapUpDetails details) async {
    // Normalise coordinates 0.0 - 1.0
    final size = MediaQuery.of(context).size;
    final x = details.globalPosition.dx / size.width;
    final y = details.globalPosition.dy / size.height;

    // Deselect if tapping near the edge or outside a reasonable area
    if (y < 0.1 || y > 0.85) {
      await LenscoachBridge.deselectSubject();
      setState(() {
        _guidancePayload = null;
        _segmentationResult = null;
      });
      return;
    }

    try {
      final result = await LenscoachBridge.tapToSegment(x, y);
      if (result != null && mounted) {
        setState(() {
          _segmentationResult = result['segmentation'] as Map<String, dynamic>?;
          _guidancePayload = GuidancePayload.fromMap(
              result['guidance'] as Map<String, dynamic>?);
        });
      }
    } catch (e) {
      debugPrint('Segmentation error: $e');
    }
  }

  Widget _buildCameraPreview() {
    if (_permissionDenied) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.camera_alt_outlined,
                  color: Colors.white24, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Camera Permission Required',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _requestPermissionAndStart,
                child: const Text('Grant Permission',
                    style: TextStyle(color: Color(0xFF00E676))),
              ),
            ],
          ),
        ),
      );
    }

    if (!_cameraReady || _textureId == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: Color(0xFF00E676),
                strokeWidth: 2,
              ),
              SizedBox(height: 16),
              Text(
                'Initializing Camera...',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RotatedBox(
      quarterTurns: _cameraRotation ~/ 90,
      child: Texture(textureId: _textureId!),
    );
  }

  Widget _buildOverlayCycleButton() {
    return GestureDetector(
      onTap: _cycleOverlayStyle,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black38,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: const Icon(
          Icons.grid_on_rounded,
          color: Colors.white70,
          size: 20,
        ),
      ),
    );
  }
}

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:lenscoach/models/review_result.dart';
import 'package:lenscoach/services/vlm_service.dart';

/// PostShotReview — Full-screen review overlay shown after photo capture.
///
/// Shows captured image + AI analysis via Gemini/Groq VLM.
/// Falls back to offline heuristic if no connectivity.
class PostShotReview extends StatefulWidget {
  final Uint8List imageBytes;
  final VoidCallback onDismiss;

  const PostShotReview({
    super.key,
    required this.imageBytes,
    required this.onDismiss,
  });

  @override
  State<PostShotReview> createState() => _PostShotReviewState();
}

class _PostShotReviewState extends State<PostShotReview>
    with SingleTickerProviderStateMixin {
  final VlmService _vlmService = VlmService();
  ReviewResult? _result;
  bool _loading = true;
  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    )..forward();

    _requestReview();
  }

  Future<void> _requestReview() async {
    final result = await _vlmService.reviewImage(widget.imageBytes);
    if (mounted) {
      setState(() {
        _result = result ?? _vlmService.offlineFallback(widget.imageBytes);
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeController,
      child: Container(
        color: Colors.black.withValues(alpha: 0.95),
        child: SafeArea(
          child: Column(
            children: [
              // Top bar with close button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'AI REVIEW',
                      style: TextStyle(
                        color: Color(0xFF00E676),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                    GestureDetector(
                      onTap: widget.onDismiss,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.close, color: Colors.white70, size: 20),
                      ),
                    ),
                  ],
                ),
              ),

              // Image preview
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.memory(
                      widget.imageBytes,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Review content
              Expanded(
                flex: 4,
                child: _loading ? _buildLoading() : _buildReviewCard(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: Color(0xFF00E676),
            strokeWidth: 2,
          ),
          SizedBox(height: 16),
          Text(
            'Analyzing your photo...',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 14,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard() {
    final result = _result!;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ratings row
          Row(
            children: [
              _buildRatingBadge(
                'Composition',
                result.compositionRating,
                const Color(0xFF00E676),
              ),
              const SizedBox(width: 12),
              _buildRatingBadge(
                'Lighting',
                result.lightingRating,
                const Color(0xFFFFAB00),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Scene detected
          _buildInfoRow(
            icon: Icons.landscape_rounded,
            label: 'SCENE DETECTED',
            value: result.sceneTypeDetected.toUpperCase(),
          ),

          const SizedBox(height: 16),

          // Strength (what's good)
          _buildFeedbackCard(
            icon: Icons.check_circle_outline,
            iconColor: const Color(0xFF00E676),
            title: 'STRENGTH',
            content: result.strength,
          ),

          const SizedBox(height: 12),

          // Top issue
          _buildFeedbackCard(
            icon: Icons.info_outline,
            iconColor: const Color(0xFFFFAB00),
            title: 'TOP ISSUE',
            content: result.topIssue,
          ),

          const SizedBox(height: 12),

          // Suggestion
          _buildFeedbackCard(
            icon: Icons.lightbulb_outline,
            iconColor: const Color(0xFF64B5F6),
            title: 'TRY THIS',
            content: result.improvementSuggestion,
          ),

          if (result.isOfflineFallback) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.wifi_off, color: Colors.white38, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Offline — basic analysis only',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildRatingBadge(String label, int rating, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              '$rating/10',
              style: TextStyle(
                color: color,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: color.withValues(alpha: 0.8),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, color: Colors.white38, size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildFeedbackCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String content,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: iconColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

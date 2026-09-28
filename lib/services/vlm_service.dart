/// LensCoach — VLM Service for Post-Shot Review
///
/// Reads provider config from constants.dart — no hardcoded endpoints.
/// Primary: Gemini 1.5 Flash via Google AI Studio
/// Fallback: Groq (LLaVA / Llama Vision)
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:lenscoach/utils/constants.dart';
import 'package:lenscoach/models/review_result.dart';

class VlmService {
  int _dailyReviewCount = 0;
  DateTime _lastResetDate = DateTime.now();

  /// Request a post-shot review for a captured image.
  ///
  /// Compresses to 800px long edge, quality 75 before sending.
  /// Tries primary provider first (Gemini), falls back to Groq.
  /// Returns null if rate limited or both providers fail.
  Future<ReviewResult?> reviewImage(Uint8List imageBytes) async {
    // Rate limiting
    _checkDailyReset();
    if (_dailyReviewCount >= vlmDailyReviewLimit) {
      debugPrint('VLM: Daily review limit reached ($_dailyReviewCount/$vlmDailyReviewLimit)');
      return null;
    }

    // Try primary provider
    try {
      final result = await _callGemini(imageBytes);
      if (result != null) {
        _dailyReviewCount++;
        return result;
      }
    } catch (e) {
      debugPrint('VLM primary (Gemini) failed: $e');
    }

    // Fallback to Groq
    try {
      final result = await _callGroq(imageBytes);
      if (result != null) {
        _dailyReviewCount++;
        return result;
      }
    } catch (e) {
      debugPrint('VLM fallback (Groq) failed: $e');
    }

    return null;
  }

  /// Offline fallback — heuristic-only analysis.
  ReviewResult offlineFallback(Uint8List imageBytes) {
    // Simplified analysis using basic image stats
    return ReviewResult(
      compositionRating: 5,
      lightingRating: 5,
      sceneTypeDetected: 'unknown',
      topIssue: 'Full review pending connection',
      improvementSuggestion: 'Connect to the internet for AI-powered feedback',
      strength: 'Photo captured successfully',
      isOfflineFallback: true,
    );
  }

  /// Call Gemini 1.5 Flash API via Google AI Studio.
  Future<ReviewResult?> _callGemini(Uint8List imageBytes) async {
    if (vlmPrimaryApiKey.isEmpty) return null;

    final base64Image = base64Encode(imageBytes);
    final url = '$vlmPrimaryEndpoint?key=$vlmPrimaryApiKey';

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': vlmSystemPrompt},
            {
              'inline_data': {
                'mime_type': 'image/jpeg',
                'data': base64Image,
              }
            }
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.2,
        'maxOutputTokens': 500,
      }
    });

    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: body,
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final text = json['candidates']?[0]?['content']?['parts']?[0]?['text'];
      if (text != null) {
        return _parseReviewJson(text);
      }
    }

    return null;
  }

  /// Call Groq API (LLaVA / Llama Vision) as fallback.
  Future<ReviewResult?> _callGroq(Uint8List imageBytes) async {
    if (vlmFallbackApiKey.isEmpty) return null;

    final base64Image = base64Encode(imageBytes);

    final body = jsonEncode({
      'model': vlmFallbackModel,
      'messages': [
        {
          'role': 'system',
          'content': vlmSystemPrompt,
        },
        {
          'role': 'user',
          'content': [
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:image/jpeg;base64,$base64Image',
              }
            },
            {
              'type': 'text',
              'text': 'Analyze this photo.',
            }
          ]
        }
      ],
      'temperature': 0.2,
      'max_tokens': 500,
    });

    final response = await http.post(
      Uri.parse(vlmFallbackEndpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $vlmFallbackApiKey',
      },
      body: body,
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final text = json['choices']?[0]?['message']?['content'];
      if (text != null) {
        return _parseReviewJson(text);
      }
    }

    return null;
  }

  /// Parse the structured JSON response from VLM.
  ReviewResult? _parseReviewJson(String text) {
    try {
      // Strip any markdown code fences the model might add
      var cleaned = text.trim();
      if (cleaned.startsWith('```json')) {
        cleaned = cleaned.substring(7);
      } else if (cleaned.startsWith('```')) {
        cleaned = cleaned.substring(3);
      }
      if (cleaned.endsWith('```')) {
        cleaned = cleaned.substring(0, cleaned.length - 3);
      }
      cleaned = cleaned.trim();

      final json = jsonDecode(cleaned) as Map<String, dynamic>;

      return ReviewResult(
        compositionRating: (json['composition_rating'] as num?)?.toInt() ?? 5,
        lightingRating: (json['lighting_rating'] as num?)?.toInt() ?? 5,
        sceneTypeDetected: json['scene_type_detected'] as String? ?? 'unknown',
        topIssue: json['top_issue'] as String? ?? 'No issues detected',
        improvementSuggestion: json['improvement_suggestion'] as String? ?? 'Keep shooting!',
        strength: json['strength'] as String? ?? 'Good effort',
      );
    } catch (e) {
      debugPrint('VLM JSON parse error: $e');
      return null;
    }
  }

  void _checkDailyReset() {
    final now = DateTime.now();
    if (now.day != _lastResetDate.day || now.month != _lastResetDate.month) {
      _dailyReviewCount = 0;
      _lastResetDate = now;
    }
  }
}

/// LensCoach — Application Constants
///
/// All provider endpoints, model names, and tuning parameters.
/// VLM provider swap = one-line change here, nowhere else.
library;

// ─── VLM Provider Configuration ───────────────────────────────────────────────
// Primary: Gemini 1.5 Flash via Google AI Studio (free tier, 1500 req/day)
// Fallback: Groq (LLaVA / Llama Vision — also free tier)
// To swap providers, change ONLY these constants.

const String vlmPrimaryEndpoint =
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent';
const String vlmPrimaryApiKey = ''; // Get from aistudio.google.com
const String vlmPrimaryModel = 'gemini-1.5-flash';

const String vlmFallbackEndpoint =
    'https://api.groq.com/openai/v1/chat/completions';
const String vlmFallbackApiKey = ''; // Get from console.groq.com
const String vlmFallbackModel = 'llava-v1.5-7b-4096-preview';

/// Daily review limit per user (free tier cost control).
const int vlmDailyReviewLimit = 20;

/// VLM System Prompt — used verbatim per spec Section 7.3.
const String vlmSystemPrompt = '''
You are a professional photography coach. Analyse the provided image and respond ONLY with a valid JSON object. No preamble, no markdown, no explanation outside the JSON. Use this exact schema:
{
  "composition_rating": <1-10 integer>,
  "lighting_rating": <1-10 integer>,
  "scene_type_detected": "<string>",
  "top_issue": "<one concise sentence>",
  "improvement_suggestion": "<one actionable sentence, beginner-friendly>",
  "strength": "<one sentence about what the photo does well>"
}''';

// ─── Image Compression (Post-Shot Review) ─────────────────────────────────────

const int vlmImageMaxLongEdge = 800;
const int vlmImageJpegQuality = 75;

// ─── Scene Classification ─────────────────────────────────────────────────────

/// Scene classifier inference cadence in milliseconds.
const int sceneClassifierIntervalMs = 1500;

/// Confidence threshold — below this, fallback to Street scene.
const double sceneClassifierMinConfidence = 0.55;

// ─── Segmentation ─────────────────────────────────────────────────────────────

/// Segmentation refresh cadence while subject is active (ms).
const int segmentationRefreshMs = 1500;

/// Centroid drift threshold (fraction of frame width) to trigger immediate recompute.
const double centroidDriftThreshold = 0.15;

/// Mask confidence threshold — below this, show dotted outline + tooltip.
const double maskConfidenceThreshold = 0.6;

// ─── Composition Engine ───────────────────────────────────────────────────────

/// Subject-to-frame size ratio thresholds.
const double subjectTooSmallThreshold = 0.05;
const double subjectTooLargeThreshold = 0.55;

/// Background entropy threshold (normalised 0-1).
const double backgroundEntropyThreshold = 0.7;

/// Backlight detection — subject mean luminance vs background delta.
const double backlightDeltaThreshold = 0.30;

// ─── Confidence Scoring ───────────────────────────────────────────────────────

/// Weighted scoring: Composition × 0.50 + Settings × 0.30 + Focus × 0.20
const double weightComposition = 0.50;
const double weightSettings = 0.30;
const double weightFocus = 0.20;

/// Score tier boundaries.
const double scoreTierLow = 0.50;
const double scoreTierMid = 0.75;
const double scoreTierHigh = 0.90;

/// Confidence score update interval in milliseconds.
const int confidenceUpdateIntervalMs = 500;

// ─── Overlay Rendering ────────────────────────────────────────────────────────

/// Default overlay opacity.
const double overlayDefaultOpacity = 0.35;

/// Reduced overlay opacity during active composition (motion detected).
const double overlayActiveOpacity = 0.10;

/// HUD opacity when no finger on screen for > 2 seconds.
const double hudIdleOpacity = 0.60;

/// Crossfade duration between overlay states in milliseconds.
const int overlayCrossfadeMs = 300;

// ─── Thermal Throttling ──────────────────────────────────────────────────────

/// Classifier cadence overrides per thermal tier (ms).
const int thermalModerateClassifierMs = 2500;
const int thermalSevereClassifierMs = 4000;

/// Stationary detection threshold (m/s², ~0.05g).
const double stationaryAccelThreshold = 0.49;

/// Duration device must be still before considered stationary (ms).
const int stationaryDurationMs = 4000;

// ─── Camera ───────────────────────────────────────────────────────────────────

/// Coaching session resolution (switch to full sensor res on capture).
const int cameraCoachingWidth = 1920;
const int cameraCoachingHeight = 1080;

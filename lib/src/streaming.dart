import 'dart:convert';

import 'partial_json.dart';

/// Pulls the incremental text out of one streamed chunk from a provider.
///
/// A provider streams Server-Sent Events; once you have decoded one event into a
/// [Map], an extractor returns the text fragment it carries, or `null` for
/// events that carry no text (role headers, usage, stop reasons).
typedef DeltaExtractor = String? Function(Map<String, dynamic> chunk);

/// OpenAI chat completions stream: `choices[0].delta.content`.
///
/// When you ask for JSON (response_format json_object / json_schema) the model's
/// JSON arrives as `content` fragments, which is exactly what this returns.
String? openAiDelta(Map<String, dynamic> chunk) {
  final choices = chunk['choices'];
  if (choices is List && choices.isNotEmpty) {
    final first = choices.first;
    if (first is Map) {
      final delta = first['delta'];
      if (delta is Map) {
        final content = delta['content'];
        if (content is String) return content;
      }
    }
  }
  return null;
}

/// Anthropic messages stream: the `content_block_delta` event carries either
/// `delta.text` (plain output) or `delta.partial_json` (tool input / structured
/// output). Both are returned as they arrive.
String? anthropicDelta(Map<String, dynamic> chunk) {
  final delta = chunk['delta'];
  if (delta is Map) {
    final text = delta['text'];
    if (text is String) return text;
    final partial = delta['partial_json'];
    if (partial is String) return partial;
  }
  return null;
}

/// Gemini generateContent stream: `candidates[0].content.parts[0].text`.
String? geminiDelta(Map<String, dynamic> chunk) {
  final candidates = chunk['candidates'];
  if (candidates is List && candidates.isNotEmpty) {
    final first = candidates.first;
    if (first is Map) {
      final content = first['content'];
      if (content is Map) {
        final parts = content['parts'];
        if (parts is List && parts.isNotEmpty) {
          final part = parts.first;
          if (part is Map) {
            final text = part['text'];
            if (text is String) return text;
          }
        }
      }
    }
  }
  return null;
}

/// Accumulates a stream of text [deltas] and, after each one, emits the JSON
/// value parsed so far.
///
/// Frames that do not parse yet, and frames whose value is unchanged from the
/// previous emission, are skipped, so listeners only see the object actually
/// growing. Unlike calling [parsePartialJson] on each buffer, a resolved
/// top-level `null` is told apart from "nothing parseable yet" here, and is
/// emitted once as that value rather than skipped forever.
Stream<Object?> streamPartialJson(Stream<String> deltas) async* {
  final buffer = StringBuffer();
  String? lastEncoded;
  await for (final delta in deltas) {
    buffer.write(delta);
    final result = parsePartialJsonResult(buffer.toString());
    if (!result.hasValue) continue;
    final encoded = jsonEncode(result.value);
    if (encoded == lastEncoded) continue;
    lastEncoded = encoded;
    yield result.value;
  }
}

/// Like [streamPartialJson] but takes provider [chunks] and a [DeltaExtractor],
/// so you can pipe a decoded SSE stream straight in:
///
/// ```dart
/// streamPartialJsonFrom(openAiChunks, openAiDelta)
///     .listen((partial) => setState(() => _draft = partial));
/// ```
Stream<Object?> streamPartialJsonFrom(
  Stream<Map<String, dynamic>> chunks,
  DeltaExtractor extractor,
) {
  return streamPartialJson(
    chunks.map(extractor).where((d) => d != null && d.isNotEmpty).cast<String>(),
  );
}

/// [streamPartial] over a provider's decoded chunks: pulls each text fragment
/// out with [extractor], then maps the growing object through [build].
///
/// This is the whole path in one call, which is the shape most callers want:
///
/// ```dart
/// streamPartialFrom(sseJson(response), openAiDelta, Recipe.fromPartial)
///     .listen((recipe) => setState(() => _recipe = recipe));
/// ```
///
/// Without it, wanting both a typed value and a provider's chunks meant
/// rebuilding the map/where/cast that [streamPartialJsonFrom] already does.
Stream<T> streamPartialFrom<T>(
  Stream<Map<String, dynamic>> chunks,
  DeltaExtractor extractor,
  T Function(Map<String, dynamic> partial) build,
) async* {
  await for (final value in streamPartialJsonFrom(chunks, extractor)) {
    if (value is Map<String, dynamic>) {
      yield build(value);
    }
  }
}

/// Maps each partial JSON object through [build] to yield a typed value as the
/// object fills in.
///
/// Write [build] to tolerate an incomplete map (read fields with `??` defaults);
/// it is called on every growth of the object. This gives typed streaming today
/// with a small hand-written builder; generated builders are planned for a later
/// release. Non-object partials (a bare array or scalar) are skipped.
///
/// Use [streamPartialFrom] when the source is a provider's chunk stream rather
/// than bare text deltas.
Stream<T> streamPartial<T>(
  Stream<String> deltas,
  T Function(Map<String, dynamic> partial) build,
) async* {
  await for (final value in streamPartialJson(deltas)) {
    if (value is Map<String, dynamic>) {
      yield build(value);
    }
  }
}

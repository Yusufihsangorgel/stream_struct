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
///
/// Ask for the JSON with `tools` and `tool_choice` instead and `content` stays
/// null for the whole answer: this returns nothing for every chunk and the
/// stream ends having emitted no frames at all, with no exception to notice.
/// Use [openAiToolDelta] for that shape.
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

/// A [DeltaExtractor] for the JSON of a **forced tool call** on an OpenAI chat
/// completions stream, which arrives as
/// `choices[0].delta.tool_calls[n].function.arguments`.
///
/// Forcing a tool call is the other way to make the model answer in your
/// schema, and [openAiDelta] cannot read it: that shape leaves `content` null
/// throughout, so the stream ends having emitted nothing and no error is
/// raised. The two are separate rather than one adapter because a single
/// answer can carry both — a model may narrate before it calls the tool, and
/// returning that prose too would put `Let me look that up.` in front of the
/// JSON buffer, where it stops parsing.
///
/// Parallel tool calls interleave in that one `tool_calls` list, each entry
/// tagged with its own `index`, and their fragments are different JSON values.
/// The extractor this returns locks onto one — by default the first `index` it
/// sees, or pass [index] to follow a known one — and ignores the rest. Because
/// it remembers the call it chose, create one per stream rather than sharing
/// it:
///
/// ```dart
/// streamPartialJsonFrom(openAiChunks, openAiToolDelta())
///     .listen((partial) => setState(() => _draft = partial));
/// ```
///
/// To read a second call, run the stream again with its [index]. One
/// [streamPartialJson] carries one JSON value; two calls are two values and
/// cannot share a buffer.
///
/// Servers that answer OpenAI's shape without the `index` field — Ollama, LM
/// Studio, vLLM — are announcing a single call, so their entries are followed
/// whatever [index] says. One shape is not handled: a server that sends
/// `arguments` already decoded into an object rather than as string fragments
/// is sending a finished value, not something to accumulate, and this returns
/// `null` for it.
DeltaExtractor openAiToolDelta({int? index}) {
  var followed = index;
  return (Map<String, dynamic> chunk) {
    final choices = chunk['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    final delta = first['delta'];
    if (delta is! Map) return null;
    final calls = delta['tool_calls'];
    if (calls is! List) return null;
    for (final call in calls) {
      if (call is! Map) continue;
      final callIndex = call['index'];
      if (callIndex is int) {
        // Lock onto the first call announced, so a stream that opens with a
        // call the caller did not name still resolves to one of them rather
        // than to nothing.
        followed ??= callIndex;
        if (callIndex != followed) continue;
      }
      final function = call['function'];
      if (function is! Map) continue;
      final arguments = function['arguments'];
      if (arguments is String) return arguments;
    }
    return null;
  };
}

/// Anthropic Messages stream for **tool-based structured output**: the JSON of
/// a forced tool call, which arrives as `delta.partial_json` on the tool block's
/// `content_block_delta` events.
///
/// This is the way to get structured output from Anthropic, and it is why this
/// adapter follows only the tool block. A model usually emits a text block
/// first ("Let me look that up.") whose fragments arrive as `delta.text`; those
/// are prose, not part of the JSON, so this returns `null` for them. Returning
/// both would splice the prose onto the front of the JSON buffer and the whole
/// thing would stop parsing — for a `Let me look that up.{"name":"Ada"}` buffer,
/// zero frames. If instead you asked the model for raw JSON with no tool, the
/// JSON is in the text block; use [anthropicTextDelta] for that.
/// Every `partial_json` fragment is returned whichever content block it came
/// from, so this is only correct while the answer holds a single tool call.
/// Ask for parallel tool use and the model opens one block per call: their
/// fragments interleave into one buffer, the concatenation stops parsing, and
/// every call after the first is silently dropped rather than reported. Use
/// [anthropicToolDelta] there — it follows one block and ignores the rest.
String? anthropicDelta(Map<String, dynamic> chunk) {
  final delta = chunk['delta'];
  if (delta is Map) {
    final partial = delta['partial_json'];
    if (partial is String) return partial;
  }
  return null;
}

/// A [DeltaExtractor] for one tool call out of an Anthropic stream that may
/// carry several.
///
/// [anthropicDelta] returns every `partial_json` fragment it is handed. With
/// parallel tool use the model opens a content block per call, each with its
/// own `index`, and those fragments belong to different JSON values: appended
/// to one buffer they stop parsing, so the second call and everything after
/// it vanish without an error.
///
/// The extractor this returns locks onto a single block — by default the
/// first tool call that starts, or pass [index] to follow a known one — and
/// ignores fragments from the others. Because it remembers which block it
/// chose, create one per stream rather than sharing it:
///
/// ```dart
/// streamPartialJsonFrom(anthropicChunks, anthropicToolDelta())
///     .listen((partial) => setState(() => _draft = partial));
/// ```
///
/// To read a second call, run the stream again with another extractor and its
/// [index]. One [streamPartialJson] carries one JSON value; two calls are two
/// values and cannot share a buffer.
DeltaExtractor anthropicToolDelta({int? index}) {
  var followed = index;
  return (Map<String, dynamic> chunk) {
    final chunkIndex = chunk['index'];
    if (followed == null) {
      // Lock onto the first tool block that opens. A text block ("Let me look
      // that up.") usually comes first and never carries partial_json, so it
      // must not claim the slot.
      if (chunk['type'] == 'content_block_start' && chunkIndex is int) {
        final block = chunk['content_block'];
        if (block is Map && block['type'] == 'tool_use') followed = chunkIndex;
      }
      // Without a content_block_start to go on — a caller feeding only delta
      // events — fall back to the first block that actually carries JSON.
      if (followed == null && chunkIndex is int) {
        final delta = chunk['delta'];
        if (delta is Map && delta['partial_json'] is String) {
          followed = chunkIndex;
        }
      }
    }
    if (chunkIndex is int && chunkIndex != followed) return null;
    return anthropicDelta(chunk);
  };
}

/// Anthropic Messages stream for **plain-text output**: the model's text block,
/// which arrives as `delta.text` on `content_block_delta` events.
///
/// Use this when you asked the model for JSON as ordinary text, with no tool
/// call, so the JSON is what it is typing. For the recommended tool-based path,
/// where the JSON is a forced tool call's arguments, use [anthropicDelta]. The
/// two never both apply to one answer, which is why they are separate: a single
/// extractor that took both would concatenate a leading prose block onto the
/// tool JSON and break parsing.
String? anthropicTextDelta(Map<String, dynamic> chunk) {
  final delta = chunk['delta'];
  if (delta is Map) {
    final text = delta['text'];
    if (text is String) return text;
  }
  return null;
}

/// Gemini `generateContent` stream: the answer text from
/// `candidates[0].content.parts`.
///
/// With thinking enabled a chunk can carry more than one part, and the model's
/// reasoning arrives as a part flagged `thought: true` — which is not the
/// answer and must not be spliced into the JSON. This returns the first part
/// that is *not* a thought and has text, so a `[{thought}, {answer}]` chunk
/// yields the answer, and it does not assume the answer is always `parts[0]`.
String? geminiDelta(Map<String, dynamic> chunk) {
  final candidates = chunk['candidates'];
  if (candidates is List && candidates.isNotEmpty) {
    final first = candidates.first;
    if (first is Map) {
      final content = first['content'];
      if (content is Map) {
        final parts = content['parts'];
        if (parts is List) {
          for (final part in parts) {
            if (part is! Map) continue;
            if (part['thought'] == true) continue;
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
    chunks
        .map(extractor)
        .where((d) => d != null && d.isNotEmpty)
        .cast<String>(),
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

import 'dart:async';
import 'dart:convert';

/// Decoding for Server-Sent Events, the wire format every streaming LLM API
/// uses.
///
/// The rest of this package starts from decoded events; this is the step
/// before it, so a response body can go straight through to
/// [streamPartialJson] without every caller writing the same line handling.
/// It stays provider-agnostic: it hands back each event's `data` payload and
/// leaves the shape of that payload to you, because that shape is where
/// providers differ.

/// The sentinel an event stream sends to say it is finished. Providers that
/// use it send `data: [DONE]` as the last event.
const sseDoneSentinel = '[DONE]';

/// Decodes an SSE response body into the `data` payload of each event.
///
/// [bytes] is the raw response stream, whose chunks do not line up with lines
/// or events; the decoding handles that. Per the SSE format, a `data:` line's
/// value has one leading space stripped, several `data:` lines in one event
/// are joined with newlines, lines starting with `:` are comments, other
/// fields (`event:`, `id:`, `retry:`) are ignored, and a blank line ends the
/// event. Events with no `data` line produce nothing.
///
/// ```dart
/// final response = await request.close();
/// final payloads = sseData(response); // Stream<String>
/// ```
Stream<String> sseData(Stream<List<int>> bytes) =>
    sseDataFromLines(utf8.decoder.bind(bytes).transform(const LineSplitter()));

/// Like [sseData], but for a stream that is already split into lines.
///
/// Use this when the transport hands you lines, or in tests. A trailing event
/// that the stream ends on without a blank line is still emitted, so a body
/// that stops right after its last `data:` line does not lose it.
Stream<String> sseDataFromLines(Stream<String> lines) async* {
  final data = <String>[];
  await for (final rawLine in lines) {
    // A stream produced by LineSplitter keeps a trailing \r on CRLF bodies.
    final line = rawLine.endsWith('\r')
        ? rawLine.substring(0, rawLine.length - 1)
        : rawLine;

    if (line.isEmpty) {
      if (data.isNotEmpty) {
        yield data.join('\n');
        data.clear();
      }
      continue;
    }
    if (line.startsWith(':')) continue; // comment, often a keep-alive

    final colon = line.indexOf(':');
    final field = colon == -1 ? line : line.substring(0, colon);
    if (field != 'data') continue; // event:, id:, retry: are not our business

    var value = colon == -1 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    data.add(value);
  }
  if (data.isNotEmpty) yield data.join('\n');
}

/// Decodes an SSE response body into one JSON object per event, which is what
/// [streamPartialJson]'s callers actually want.
///
/// Each event's `data` payload is parsed with `jsonDecode`. The
/// [sseDoneSentinel] event is dropped rather than parsed, so the stream simply
/// ends where the provider says it does.
///
/// ```dart
/// await for (final event in sseJson(response)) {
///   final delta = event['choices'][0]['delta']['content'] as String?;
///   if (delta != null) yield delta;
/// }
/// ```
///
/// Throws [FormatException] if an event's payload is not valid JSON.
Stream<Map<String, dynamic>> sseJson(Stream<List<int>> bytes) =>
    sseJsonFromData(sseData(bytes));

/// Like [sseJson], but starting from payloads you already decoded with
/// [sseData] or [sseDataFromLines].
Stream<Map<String, dynamic>> sseJsonFromData(Stream<String> payloads) async* {
  await for (final payload in payloads) {
    if (payload == sseDoneSentinel) return;
    final decoded = jsonDecode(payload);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('SSE event payload is not a JSON object', payload);
    }
    yield decoded;
  }
}

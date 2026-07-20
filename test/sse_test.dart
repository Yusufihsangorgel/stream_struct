import 'dart:convert';

import 'package:stream_struct/stream_struct.dart';
import 'package:test/test.dart';

/// Emits [text] as byte chunks of [size], so chunk edges fall in the middle of
/// lines and events the way a real HTTP body's do.
Stream<List<int>> chunked(String text, int size) async* {
  final bytes = utf8.encode(text);
  for (var i = 0; i < bytes.length; i += size) {
    yield bytes.sublist(i, i + size > bytes.length ? bytes.length : i + size);
  }
}

void main() {
  group('sseData', () {
    test('yields the payload of each event', () async {
      const body = 'data: one\n\ndata: two\n\n';
      expect(await sseData(chunked(body, 1024)).toList(), ['one', 'two']);
    });

    test('survives chunk boundaries inside lines and events', () async {
      const body = 'data: {"a":1}\n\ndata: {"a":2}\n\ndata: {"a":3}\n\n';
      // One byte at a time is the worst case a response stream can hand you.
      expect(
        await sseData(chunked(body, 1)).toList(),
        ['{"a":1}', '{"a":2}', '{"a":3}'],
      );
      // And a few odd sizes in between.
      for (final size in [2, 3, 7, 13]) {
        expect(
          await sseData(chunked(body, size)).toList(),
          ['{"a":1}', '{"a":2}', '{"a":3}'],
          reason: 'chunk size $size',
        );
      }
    });

    test('joins several data lines in one event with newlines', () async {
      const body = 'data: first\ndata: second\n\n';
      expect(await sseData(chunked(body, 4)).toList(), ['first\nsecond']);
    });

    test('skips comments and fields other than data', () async {
      const body = ': keep-alive\n'
          'event: message\n'
          'id: 7\n'
          'retry: 1000\n'
          'data: payload\n'
          '\n';
      expect(await sseData(chunked(body, 5)).toList(), ['payload']);
    });

    test('strips exactly one leading space after the colon', () async {
      const body = 'data:  two spaces\n\ndata:none\n\n';
      expect(
        await sseData(chunked(body, 1024)).toList(),
        [' two spaces', 'none'],
      );
    });

    test('handles CRLF bodies', () async {
      const body = 'data: one\r\n\r\ndata: two\r\n\r\n';
      expect(await sseData(chunked(body, 3)).toList(), ['one', 'two']);
    });

    test('emits a final event that the body ends without a blank line',
        () async {
      const body = 'data: one\n\ndata: last';
      expect(await sseData(chunked(body, 1024)).toList(), ['one', 'last']);
    });

    test('an event with no data line produces nothing', () async {
      const body = 'event: ping\n\ndata: real\n\n';
      expect(await sseData(chunked(body, 1024)).toList(), ['real']);
    });
  });

  group('sseJson', () {
    test('decodes each payload and stops at the done sentinel', () async {
      const body = 'data: {"i":1}\n\n'
          'data: {"i":2}\n\n'
          'data: $sseDoneSentinel\n\n'
          'data: {"i":3}\n\n'; // after [DONE], must not be delivered
      final events = await sseJson(chunked(body, 6)).toList();
      expect(events.map((e) => e['i']).toList(), [1, 2]);
    });

    test('an OpenAI-shaped body flows through to the delta extractor',
        () async {
      // The end-to-end path this release exists for: response bytes in,
      // growing structured value out, with no hand-written SSE handling.
      const body = 'data: {"choices":[{"delta":{"content":"{\\"na"}}]}\n\n'
          'data: {"choices":[{"delta":{"content":"me\\":\\"ada"}}]}\n\n'
          'data: {"choices":[{"delta":{"content":"\\"}"}}]}\n\n'
          'data: $sseDoneSentinel\n\n';
      final values = await streamPartialJsonFrom(
        sseJson(chunked(body, 9)),
        openAiDelta,
      ).toList();
      expect(values.last, {'name': 'ada'});
    });

    test('invalid JSON in an event throws FormatException', () {
      expect(
        sseJson(chunked('data: {not json\n\n', 1024)).toList(),
        throwsFormatException,
      );
    });
  });
}

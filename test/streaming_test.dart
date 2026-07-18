import 'package:stream_struct/stream_struct.dart';
import 'package:test/test.dart';

void main() {
  group('streamPartialJson', () {
    test('emits the object growing and ends on the final value', () async {
      final deltas = Stream.fromIterable([
        '{"name": "Ad',
        'a", "age": ',
        '36}',
      ]);
      final frames = await streamPartialJson(deltas).toList();
      expect(frames.last, {'name': 'Ada', 'age': 36});
      // Every frame is a prefix-consistent view; the name appears before age.
      expect(frames.first, {'name': 'Ad'});
    });

    test('skips unchanged frames', () async {
      final deltas = Stream.fromIterable(['{"a":1', '', '   ']);
      final frames = await streamPartialJson(deltas).toList();
      expect(frames, [
        {'a': 1},
      ]);
    });
  });

  group('provider adapters', () {
    test('openAiDelta reads choices[0].delta.content', () {
      expect(
        openAiDelta({
          'choices': [
            {'delta': {'content': 'he'}},
          ],
        }),
        'he',
      );
      expect(openAiDelta({'choices': []}), isNull);
    });

    test('anthropicDelta reads text and partial_json', () {
      expect(anthropicDelta({'delta': {'text': 'hi'}}), 'hi');
      expect(anthropicDelta({'delta': {'partial_json': '{"a"'}}), '{"a"');
    });

    test('geminiDelta reads candidates[0].content.parts[0].text', () {
      expect(
        geminiDelta({
          'candidates': [
            {'content': {'parts': [{'text': 'yo'}]}},
          ],
        }),
        'yo',
      );
    });
  });

  test('streamPartialJsonFrom pipes provider chunks through an extractor',
      () async {
    final chunks = Stream<Map<String, dynamic>>.fromIterable([
      {'choices': [{'delta': {'content': '{"ok":'}}]},
      {'choices': [{'delta': {'content': 'true}'}}]},
    ]);
    final frames = await streamPartialJsonFrom(chunks, openAiDelta).toList();
    expect(frames.last, {'ok': true});
  });

  test('streamPartial maps growing objects into a typed value', () async {
    final deltas = Stream.fromIterable(['{"n": "A', 'da"}']);
    final names = await streamPartial(
      deltas,
      (m) => (m['n'] as String?) ?? '',
    ).toList();
    expect(names.last, 'Ada');
  });
}

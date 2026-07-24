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

    test('emits a frame when the value itself is a top-level null', () async {
      // A resolved `null` and "nothing parseable yet" both read as `null`
      // from parsePartialJson; without disambiguation this stream would end
      // having emitted nothing, indistinguishable from a stalled connection.
      final deltas = Stream.fromIterable(['nu', 'll']);
      final frames = await streamPartialJson(deltas).toList();
      expect(frames, [null]);
    });
  });

  group('provider adapters', () {
    test('openAiDelta reads choices[0].delta.content', () {
      expect(
        openAiDelta({
          'choices': [
            {
              'delta': {'content': 'he'}
            },
          ],
        }),
        'he',
      );
      expect(openAiDelta({'choices': []}), isNull);
    });

    test('anthropicDelta reads the tool JSON and ignores prose text', () {
      expect(
          anthropicDelta({
            'delta': {'partial_json': '{"a"'}
          }),
          '{"a"');
      // A leading text block is prose, not JSON; splicing it in front of the
      // tool JSON would break parsing, so it must be dropped.
      expect(
          anthropicDelta({
            'delta': {'text': 'Let me look that up.'}
          }),
          isNull);
    });

    test('anthropicTextDelta reads prose text and ignores tool JSON', () {
      expect(
          anthropicTextDelta({
            'delta': {'text': 'hi'}
          }),
          'hi');
      expect(
          anthropicTextDelta({
            'delta': {'partial_json': '{"a"'}
          }),
          isNull);
    });

    test(
        'a tool stream with a leading text block parses through anthropicDelta',
        () async {
      // Regression: text_delta prose used to be concatenated onto the tool
      // JSON, so a real Anthropic answer yielded zero frames.
      final events = <Map<String, dynamic>>[
        {
          'delta': {'type': 'text_delta', 'text': 'Let me '}
        },
        {
          'delta': {'type': 'text_delta', 'text': 'help.'}
        },
        {
          'delta': {'type': 'input_json_delta', 'partial_json': '{"name"'}
        },
        {
          'delta': {'type': 'input_json_delta', 'partial_json': ':"Ada"}'}
        },
      ];
      Object? last;
      await for (final v in streamPartialJsonFrom(
        Stream.fromIterable(events),
        anthropicDelta,
      )) {
        last = v;
      }
      expect(last, {'name': 'Ada'});
    });

    test('geminiDelta reads candidates[0].content.parts[0].text', () {
      expect(
        geminiDelta({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'yo'}
                ]
              }
            },
          ],
        }),
        'yo',
      );
    });

    test('geminiDelta skips a thought part and does not assume parts[0]', () {
      // With thinking on, the reasoning arrives as a thought part before the
      // answer; returning it would splice reasoning into the JSON buffer.
      expect(
        geminiDelta({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'let me think', 'thought': true},
                  {'text': '{"answer":1}'},
                ]
              }
            },
          ],
        }),
        '{"answer":1}',
      );
    });
  });

  test('streamPartialJsonFrom pipes provider chunks through an extractor',
      () async {
    final chunks = Stream<Map<String, dynamic>>.fromIterable([
      {
        'choices': [
          {
            'delta': {'content': '{"ok":'}
          }
        ]
      },
      {
        'choices': [
          {
            'delta': {'content': 'true}'}
          }
        ]
      },
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

  group('streamPartialFrom', () {
    test('goes from provider chunks to a typed value in one call', () async {
      final chunks = Stream.fromIterable(<Map<String, dynamic>>[
        {
          'choices': [
            {
              'delta': {'role': 'assistant'},
            },
          ],
        },
        {
          'choices': [
            {
              'delta': {'content': '{"name": "Ad'},
            },
          ],
        },
        {
          'choices': [
            {
              'delta': {'content': 'a", "age": 3'},
            },
          ],
        },
        {
          'choices': [
            {
              'delta': {'content': '6}'},
            },
          ],
        },
      ]);

      final names = await streamPartialFrom(
        chunks,
        openAiDelta,
        (partial) => '${partial['name'] ?? ''}/${partial['age'] ?? '?'}',
      ).toList();

      // One frame per chunk that carries text, so the role-only chunk produces
      // none, and the chunk that both finishes the name and opens the age
      // produces one rather than two.
      //
      // The age reads 3 before it reads 36: a number's digits arrive like any
      // other characters, so a partial value is not merely incomplete, it can
      // be provisionally wrong. Render it, but don't act on it until the end.
      expect(names, ['Ad/?', 'Ada/3', 'Ada/36']);
    });

    test('skips a stream that never forms an object', () async {
      final chunks = Stream.fromIterable(<Map<String, dynamic>>[
        {
          'choices': [
            {
              'delta': {'content': '[1, 2'},
            },
          ],
        },
      ]);
      expect(
        await streamPartialFrom(chunks, openAiDelta, (p) => p.length).toList(),
        isEmpty,
      );
    });
  });
}

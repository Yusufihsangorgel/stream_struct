import 'dart:convert';
import 'package:stream_struct/stream_struct.dart';
import 'package:test/test.dart';

void main() {
  test('every prefix of a valid document parses consistently', () {
    // The strongest property a partial parser can have: for every prefix of a
    // real document, parsing must not throw, must not lose structure it has
    // already reported, and the complete document must decode exactly.
    const documents = [
      '{"name":"Ada","score":12.5,"ok":true}',
      '{"a":1,"b":[1,2.5,"x",null,false],"c":{"d":{"e":"deep"}}}',
      '[{"id":1,"tags":["x","y"]},{"id":2,"tags":[]},{"id":3}]',
      '{"neg":-5,"exp":1.2e10,"frac":0.001,"zero":0}',
      r'{"esc":"a \"quoted\" and \\ backslash","uni":"café🎉"}',
      '{"empty":{},"emptyArr":[],"nullv":null}',
      '{"nested":[[1,2],[3,[4,[5]]]]}',
      '[1,2,3]',
      '{"k":"v with {braces} and [brackets] inside"}',
    ];

    for (final document in documents) {
      var seenContainer = false;
      for (var i = 1; i <= document.length; i++) {
        final prefix = document.substring(0, i);
        final frame = parsePartialJson(prefix);

        if ((frame is Map && frame.isNotEmpty) ||
            (frame is List && frame.isNotEmpty)) {
          seenContainer = true;
        } else if (seenContainer) {
          expect(
            frame,
            isNotNull,
            reason: 'structure vanished at prefix ${jsonEncode(prefix)} '
                'of $document',
          );
        }
      }

      expect(
        jsonEncode(parsePartialJson(document)),
        jsonEncode(jsonDecode(document)),
        reason: 'the complete document must decode exactly',
      );
    }
  });

  group('parsePartialJson', () {
    test('returns null for empty or whitespace', () {
      expect(parsePartialJson(''), isNull);
      expect(parsePartialJson('   '), isNull);
    });

    test('decodes already-complete JSON unchanged', () {
      expect(parsePartialJson('{"a":1,"b":"x"}'), {'a': 1, 'b': 'x'});
      expect(parsePartialJson('[1,2,3]'), [1, 2, 3]);
    });

    test('closes an open object', () {
      expect(parsePartialJson('{"a":1'), {'a': 1});
      expect(parsePartialJson('{"a":1,"b":2'), {'a': 1, 'b': 2});
    });

    test('keeps a half-written string value and closes it', () {
      expect(parsePartialJson('{"title":"The quick bro'),
          {'title': 'The quick bro'});
    });

    test('drops a half-written object key', () {
      expect(parsePartialJson('{"a":1,"titl'), {'a': 1});
      expect(parsePartialJson('{"titl'), <String, Object?>{});
    });

    test('drops a dangling colon (key with no value yet)', () {
      expect(parsePartialJson('{"a":1,"color":'), {'a': 1});
      expect(parsePartialJson('{"color":'), <String, Object?>{});
    });

    test('drops a trailing comma', () {
      expect(parsePartialJson('{"a":1,'), {'a': 1});
      expect(parsePartialJson('[1,2,'), [1, 2]);
    });

    test('handles nested containers', () {
      expect(parsePartialJson('{"user":{"name":"Al'), {
        'user': {'name': 'Al'}
      });
      expect(parsePartialJson('{"tags":["a","b'), {
        'tags': ['a', 'b']
      });
    });

    test('reports an element that has only just opened as an empty one', () {
      expect(parsePartialJson('[{"a": 1}, {"b'), [
        {'a': 1},
        <String, Object?>{}
      ]);
    });

    test('keeps a valid partial number', () {
      expect(parsePartialJson('{"n":12'), {'n': 12});
    });

    test('drops an unresolved-value field but keeps the object', () {
      // "tr" is not yet "true", so the field is dropped — but the object has
      // arrived and is returned, matching a colon with no value ({"ok":} is {}).
      // A resolved sibling must survive: the object must not vanish because one
      // field is still being typed.
      expect(parsePartialJson('{"ok":tr'), <String, Object?>{});
      expect(parsePartialJson('{"a":1,"ok":tr'), {'a': 1});
      expect(parsePartialJson('{"a":1,"n":12.'), {'a': 1});
      // A complete key with no colon yet is a dangling key, dropped the same way.
      expect(parsePartialJson('{"a":1,"next"'), {'a': 1});
    });

    test('an object never vanishes mid-stream once it has a resolved field',
        () {
      // Streaming a value character by character used to null the whole object
      // the instant a value or key started but had not resolved. Feed several
      // shapes one char at a time and assert the value never drops back to null
      // after a non-empty container has appeared.
      for (final full in [
        '{"name": "Ada", "score": 12.5}',
        '{"a": 1, "b": true, "c": [1, 2.5, "x"], "d": {"e": null}}',
        '[{"id": 1, "tags": ["x", "y"]}, {"id": 2}]',
        '{"neg": -5, "exp": 1.2e10}',
      ]) {
        final buf = StringBuffer();
        var seenNonEmpty = false;
        for (var i = 0; i < full.length; i++) {
          buf.write(full[i]);
          final frame = parsePartialJson(buf.toString());
          if ((frame is Map && frame.isNotEmpty) ||
              (frame is List && frame.isNotEmpty)) {
            seenNonEmpty = true;
          } else if (seenNonEmpty) {
            expect(frame, isNotNull,
                reason: 'vanished at "${buf.toString()}" for $full');
          }
        }
      }
    });

    test('does not confuse braces inside a string', () {
      expect(parsePartialJson('{"expr":"a { b } c'), {'expr': 'a { b } c'});
    });

    test('handles an escaped quote inside a value', () {
      expect(parsePartialJson(r'{"q":"she said \"hi'), {'q': 'she said "hi'});
    });

    test('progressive stream converges to the final object', () {
      const full = '{"name":"Ada","age":36,"langs":["Dart","Rust"]}';
      Object? last;
      for (var i = 1; i <= full.length; i++) {
        final partial = parsePartialJson(full.substring(0, i));
        if (partial != null) last = partial;
      }
      expect(last, {
        'name': 'Ada',
        'age': 36,
        'langs': ['Dart', 'Rust'],
      });
    });
  });
  test('a completed string value survives the frame that closes it', () {
    // The closing quote of a value and the closing quote of a key look the
    // same at the tail; only the colon before it tells them apart. Getting
    // that wrong drops a finished value at the exact moment it lands.
    expect(parsePartialJson('{"name":"Ada"'), {'name': 'Ada'});
    expect(parsePartialJson('{"a":1,"b":"x"'), {'a': 1, 'b': 'x'});
    expect(parsePartialJson('{"a":["x"'), {
      'a': ['x'],
    });

    // The other side of the same branch: a key with no colon yet is not a
    // value, so its entry goes.
    expect(parsePartialJson('{"name":"Ada","score"'), {'name': 'Ada'});
  });
}

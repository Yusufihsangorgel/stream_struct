import 'package:stream_struct/stream_struct.dart';
import 'package:test/test.dart';

void main() {
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
      expect(parsePartialJson('{"user":{"name":"Al'),
          {'user': {'name': 'Al'}});
      expect(parsePartialJson('{"tags":["a","b'),
          {'tags': ['a', 'b']});
    });

    test('reports an element that has only just opened as an empty one', () {
      expect(parsePartialJson('[{"a": 1}, {"b'),
          [{'a': 1}, <String, Object?>{}]);
    });

    test('keeps a valid partial number', () {
      expect(parsePartialJson('{"n":12'), {'n': 12});
    });

    test('skips a frame with an unresolved literal', () {
      // "tr" is not yet "true"; better to emit nothing than a wrong value.
      expect(parsePartialJson('{"ok":tr'), isNull);
    });

    test('does not confuse braces inside a string', () {
      expect(parsePartialJson('{"expr":"a { b } c'),
          {'expr': 'a { b } c'});
    });

    test('handles an escaped quote inside a value', () {
      expect(parsePartialJson(r'{"q":"she said \"hi'),
          {'q': 'she said "hi'});
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
}

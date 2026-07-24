/// The whole path a streamed JSON answer takes: response bytes in, a typed
/// object out, updated on every fragment.
///
/// The bytes here are canned, so this runs with no API key and no network. They
/// are fed in at arbitrary boundaries, cutting through the middle of lines and
/// of the JSON inside them, because that is what a socket does. Examples that
/// yield one tidy line at a time skip the only part that is hard.
///
///     dart run example/openai_end_to_end.dart
library;

import 'dart:convert';
import 'dart:math';

import 'package:stream_struct/stream_struct.dart';

/// What the model was asked for, as the app wants to hold it.
class Recipe {
  Recipe({required this.title, this.prepMinutes, required this.ingredients});

  /// Built from a partial object, so every field has to tolerate not being
  /// there yet. This is called on each growth of the JSON, not once at the end.
  factory Recipe.fromPartial(Map<String, dynamic> partial) => Recipe(
        title: partial['title'] as String? ?? '',
        prepMinutes: partial['prep_min'] as int?,
        ingredients: (partial['ingredients'] as List?)?.cast<String>() ??
            const <String>[],
      );

  final String title;
  final int? prepMinutes;
  final List<String> ingredients;

  @override
  String toString() {
    final prep = prepMinutes == null ? '?' : '$prepMinutes min';
    return '${title.padRight(22)} $prep'.padRight(34) + ingredients.join(', ');
  }
}

/// An OpenAI chat-completions stream, the shape the API actually sends: one
/// `data:` line per chunk, the JSON arriving as `content` fragments, and a
/// `[DONE]` sentinel at the end.
const _responseBody = '''
data: {"choices":[{"delta":{"role":"assistant"}}]}

data: {"choices":[{"delta":{"content":"{\\"title\\": \\"Foc"}}]}

data: {"choices":[{"delta":{"content":"accia\\", \\"prep_min\\": 2"}}]}

data: {"choices":[{"delta":{"content":"0, \\"ingredients\\": [\\"flour\\""}}]}

data: {"choices":[{"delta":{"content":", \\"water\\", \\"olive oil\\""}}]}

data: {"choices":[{"delta":{"content":"]}"}}]}

data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

data: [DONE]

''';

/// Delivers the body in fixed-size byte runs, which land wherever they land:
/// mid-line, mid-token, between the two newlines that end an event.
Stream<List<int>> _socket(String body, {int runLength = 37}) async* {
  final bytes = utf8.encode(body);
  for (var i = 0; i < bytes.length; i += runLength) {
    await Future<void>.delayed(const Duration(milliseconds: 40));
    yield bytes.sublist(i, min(i + runLength, bytes.length));
  }
}

Future<void> main() async {
  print('title                  prep   ingredients');
  print('-' * 60);

  // With a real request this is the only line that changes: `_socket(...)`
  // becomes the response body, for instance
  //
  //   final request = await HttpClient().postUrl(endpoint);
  //   request.headers.set('authorization', 'Bearer $key');
  //   request.write(jsonEncode({'model': ..., 'stream': true, ...}));
  //   final response = await request.close();
  //   streamPartialFrom(sseJson(response), openAiDelta, Recipe.fromPartial)
  //
  // `response` is a Stream<List<int>>, which is what sseJson takes.
  final recipes = streamPartialFrom(
    sseJson(_socket(_responseBody)),
    openAiDelta,
    Recipe.fromPartial,
  );

  Recipe? last;
  await for (final recipe in recipes) {
    print('  $recipe');
    last = recipe;
  }

  print('\nfinished with ${last?.ingredients.length} ingredients.');
  print(
    'Every line above was a render opportunity. Look at the prep time: it\n'
    'reads 2 before it reads 20, because the digits of a number arrive one at\n'
    'a time like everything else. A partial value is provisional, not just\n'
    'incomplete, so show it, but do not act on it until the stream ends.',
  );
}

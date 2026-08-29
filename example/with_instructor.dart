// Live UI from this package, schema-validated result from instructor_dart.
//
//   dart run example/with_instructor.dart
//
// The two packages sit on either side of one object and do not share a type
// or a lifecycle. stream_struct turns a provider's token stream into that
// object as it fills in. instructor_dart takes a finished reply, validates
// it against a Schema, and either yields a typed value or lists what failed
// (and, given an adapter, would send the violations back for a retry).
//
// There is no function that does both. This file is the join: render the
// partials as they arrive, then one Schema.validate on the last frame.
// Instructor.extract is not that second step -- it always calls a model --
// so the public surface that actually matches a stream that has already
// ended is Schema.validate / Schema.normalize.
//
// instructor_dart asked with a forced tool call, so the extractor is
// openAiToolDelta(), not openAiDelta. The content extractor on this stream
// would emit nothing and raise nothing. On Gemini the function call arrives
// complete in one chunk, so geminiToolDelta yields one frame rather than a
// growing prefix: the live-updating half of this join is a no-op there.
//
// instructor_dart is a dev dependency used by this file only. The published
// package does not depend on it.
import 'package:instructor_dart/instructor_dart.dart';
import 'package:stream_struct/stream_struct.dart';

/// What the model was asked for, as the app wants to hold it.
///
/// Two factories, because the two packages disagree about when the object
/// is allowed to be incomplete. [Recipe.fromPartial] is called on every
/// growth and has to tolerate missing fields. [Recipe.fromJson] runs only
/// after [Schema.validate] passed, and can assume required fields are
/// present and correctly typed -- the same split [Instructor.extract] makes
/// internally. Reusing fromJson on a partial throws on the first fragment.
class Recipe {
  Recipe({
    required this.title,
    this.prepMinutes,
    required this.ingredients,
  });

  factory Recipe.fromPartial(Map<String, dynamic> partial) => Recipe(
        title: (partial['title'] as String?) ?? '',
        prepMinutes: partial['prep_min'] as int?,
        ingredients: (partial['ingredients'] as List?)?.cast<String>() ??
            const <String>[],
      );

  factory Recipe.fromJson(Map<String, Object?> json) => Recipe(
        title: json['title']! as String,
        prepMinutes: json['prep_min']! as int,
        ingredients: (json['ingredients']! as List).cast<String>(),
      );

  final String title;
  final int? prepMinutes;
  final List<String> ingredients;

  @override
  String toString() {
    final prep = prepMinutes == null ? '?' : '$prepMinutes min';
    final items = ingredients.isEmpty ? '(none yet)' : ingredients.join(', ');
    return '$title | $prep | $items';
  }
}

/// The schema instructor_dart would have sent as the tool parameters.
///
/// stream_struct never sees this. Extra keys, out-of-range numbers, and
/// missing required fields all render; the schema is consulted once, on
/// the last frame. Validating a mid-stream frame reports "required
/// property is missing" while the model is still typing, which is not a
/// repair opportunity.
final recipeSchema = Schema.object({
  'title': Schema.string(description: 'Recipe title'),
  'prep_min': Schema.integer(
    description: 'Prep time in minutes',
    min: 1,
    max: 180,
  ),
  'ingredients': Schema.list(Schema.string(), minItems: 1),
});

/// One OpenAI chat-completions chunk carrying a tool-call arguments fragment.
///
/// instructor_dart always asks with a forced tool call, so the JSON arrives
/// as `choices[0].delta.tool_calls[n].function.arguments`, not as `content`.
Map<String, dynamic> _arguments(String fragment) => {
      'choices': [
        {
          'delta': {
            'tool_calls': [
              {
                'index': 0,
                'function': {'arguments': fragment},
              },
            ],
          },
        },
      ],
    };

/// A complete answer that matches [recipeSchema].
///
/// The digits of `prep_min` arrive as `2` then `20`, the same provisional
/// number the other examples show. Render it; do not validate it yet.
final validChunks = <Map<String, dynamic>>[
  {
    'choices': [
      {
        'delta': {
          'tool_calls': [
            {
              'index': 0,
              'function': {
                'name': 'extract',
                'arguments': '{"title": "Foc',
              },
            },
          ],
        },
      },
    ],
  },
  _arguments('accia", "prep_min": 2'),
  _arguments('0, "ingredients": ["flour"'),
  _arguments(', "water", "olive oil"]}'),
];

/// A complete answer that fails [recipeSchema]: prep time 999 is past 180.
///
/// It looks in range at `99`, then it does not. The last frame is what you
/// hand to the schema, not "it looked fine a moment ago".
final invalidChunks = <Map<String, dynamic>>[
  _arguments('{"title": "Burnt toast", "prep_min": 99'),
  _arguments('9, "ingredients": ["bread"]}'),
];

Future<void> play(
  String label,
  List<Map<String, dynamic>> chunks,
) async {
  print(label);

  // streamPartialFrom would eat the map inside fromPartial, and the
  // validator wants the map, not the UI type. Keep the Object? frames.
  Map<String, dynamic>? last;
  await for (final partial in streamPartialJsonFrom(
    Stream.fromIterable(chunks),
    openAiToolDelta(),
  )) {
    if (partial is! Map<String, dynamic>) continue;
    last = partial;
    print('  ${Recipe.fromPartial(partial)}');
  }

  if (last == null) {
    print('  (no frames -- wrong extractor, or the model said nothing)');
    print('');
    return;
  }

  // Map<String, dynamic> here, Map<String, Object?> there. Same JSON;
  // the copy is the whole conversion.
  final json = Map<String, Object?>.from(last);
  final violations = recipeSchema.validate(json);
  if (violations.isEmpty) {
    // Schema.normalize is typed Object? even on ObjectSchema. extractRaw
    // does this same cast after validate has passed.
    final normalized = recipeSchema.normalize(json);
    if (normalized is! Map<String, Object?>) {
      print('  -> normalize did not return an object');
      print('');
      return;
    }
    print('  -> ${Recipe.fromJson(normalized)}');
  } else {
    print('  -> rejected');
    for (final violation in violations) {
      print('     $violation');
    }
    print('     a real Instructor.extract would send that back and retry;');
    print('     that is a new request, not a replay of this stream.');
  }
  print('');
}

Future<void> main() async {
  print('');
  print('The object fills in as fragments arrive. The schema runs once,');
  print('on the last frame.');
  print('');

  await play('matches the schema', validChunks);
  await play('fails the schema (prep_min 999 > 180)', invalidChunks);

  print('Each line above is a state your UI could render. Only the arrow');
  print('is a value you should keep: either a typed Recipe, or the list of');
  print('what failed.');
}

// Simulates a model streaming a JSON object one token at a time and prints the
// object as it fills in. Run with: dart run example/stream_struct_example.dart
import 'package:stream_struct/stream_struct.dart';

/// A recipe the "model" is streaming back.
const _tokens = [
  '{"title": "Focaccia',
  '", "prep_min": ',
  '20, "ingredients": ["flour"',
  ', "water", "olive oil"',
  '], "done": ',
  'true}',
];

Stream<String> _fakeModel() async* {
  for (final t in _tokens) {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    yield t;
  }
}

Future<void> main() async {
  print('Streaming a recipe as it arrives:\n');
  await for (final partial in streamPartialJson(_fakeModel())) {
    final map = partial as Map<String, dynamic>;
    final title = map['title'] ?? '...';
    final ingredients = (map['ingredients'] as List?)?.length ?? 0;
    print('  title: $title | ingredients so far: $ingredients');
  }
  print('\nDone. The last line is the fully parsed object.');
}

// The same object filled from two providers' wire formats, with no network.
//
//   dart run example/two_providers.dart
//
// The package's headline is "OpenAI, Anthropic and Gemini extractors", and no
// example used one: the other two call `sseJson` and `streamPartialJson`,
// which is the middle of the pipeline. The extractors are the ends, and the
// reason the abstraction exists at all.
//
// A forced tool call is the case worth showing. Both providers stream one, and
// they put the JSON in completely different places -- OpenAI under
// `choices[0].delta.tool_calls[0].function.arguments`, Anthropic under
// `delta.partial_json` after a `content_block_start` names the block. Swapping
// the extractor is the entire difference on this side.
//
// The chunks below are the shapes those APIs send, written out rather than
// fetched, so this runs offline and the same every time.
import 'package:stream_struct/stream_struct.dart';

/// What OpenAI streams for a forced tool call, one event per element.
///
/// The arguments arrive as text fragments that are not valid JSON on their
/// own; that is what the partial parser is for.
const openAiChunks = <Map<String, dynamic>>[
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
        'delta': {
          'tool_calls': [
            {
              'index': 0,
              'function': {'name': 'record_order', 'arguments': '{"item":"'},
            },
          ],
        },
      },
    ],
  },
  {
    'choices': [
      {
        'delta': {
          'tool_calls': [
            {
              'index': 0,
              'function': {'arguments': 'flat white","siz'},
            },
          ],
        },
      },
    ],
  },
  {
    'choices': [
      {
        'delta': {
          'tool_calls': [
            {
              'index': 0,
              'function': {'arguments': 'e":"large","shots":2}'},
            },
          ],
        },
      },
    ],
  },
  {
    'choices': [
      {'finish_reason': 'tool_calls'},
    ],
  },
];

/// The same order, the way Anthropic streams it.
const anthropicChunks = <Map<String, dynamic>>[
  {
    'type': 'content_block_start',
    'index': 0,
    'content_block': {'type': 'tool_use', 'name': 'record_order'},
  },
  {
    'type': 'content_block_delta',
    'index': 0,
    'delta': {'type': 'input_json_delta', 'partial_json': '{"item":"flat '},
  },
  {
    'type': 'content_block_delta',
    'index': 0,
    'delta': {'type': 'input_json_delta', 'partial_json': 'white","size":"la'},
  },
  {
    'type': 'content_block_delta',
    'index': 0,
    'delta': {'type': 'input_json_delta', 'partial_json': 'rge","shots":2}'},
  },
  {'type': 'content_block_stop', 'index': 0},
];

Future<void> show(
  String label,
  List<Map<String, dynamic>> chunks,
  DeltaExtractor extractor,
) async {
  print(label);
  var frames = 0;
  Object? last;
  await for (final partial
      in streamPartialJsonFrom(Stream.fromIterable(chunks), extractor)) {
    frames++;
    last = partial;
    print('  $partial');
  }
  print('  -> $frames usable states on the way to $last');
  print('');
}

Future<void> main() async {
  print('');
  print('One order, two wire formats, one extractor swap.');
  print('');

  await show('OpenAI, forced tool call', openAiChunks, openAiToolDelta());
  await show(
      'Anthropic, tool_use block', anthropicChunks, anthropicToolDelta());

  print('Each line above is a state your UI could render. The fragments the');
  print('providers send are not valid JSON on their own -- `{"item":"` is');
  print('half a key and an open quote -- so the value only appears once');
  print('enough has arrived to close it, and never appears twice unchanged.');
  print('');
  print('The two chunk lists have nothing in common. The code below them is');
  print('identical apart from which extractor is passed, which is the whole');
  print('reason they exist.');
}

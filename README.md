![stream_struct: a token stream parsed into the object as it fills in](https://raw.githubusercontent.com/Yusufihsangorgel/stream_struct/main/doc/banner.png)

# stream_struct

Turn a language model's token stream into a stream of the structured object as
it fills in.

![stream_struct parses a JSON object and fills it in token by token as it streams](https://raw.githubusercontent.com/Yusufihsangorgel/stream_struct/main/doc/demo.gif)

A model asked for JSON emits it one token at a time. Mid-stream you are holding
something like `{"title": "The quick bro` , which `jsonDecode` throws on until
the very last token lands. So the usual choices are to wait for the whole
response before showing anything, or to hand-roll a fragile parser. `stream_struct`
is the parser, done once and tested, plus the provider glue.

```
dart pub add stream_struct
```

## Parse one partial buffer

`parsePartialJson` decodes a truncated buffer into the value it holds so far. It
closes an open string value and any open array or object, and drops a dangling
key, colon, or comma.

```dart
import 'package:stream_struct/stream_struct.dart';

parsePartialJson('{"title": "The quick bro');   // {title: The quick bro}
parsePartialJson('{"a": 1, "tags": ["x"');       // {a: 1, tags: [x]}
parsePartialJson('{"a": 1, "colo');              // {a: 1}   (partial key dropped)
```

It returns `null` while nothing is decodable yet: an empty buffer, or a value
that is still an unresolved scalar (`tr` on its way to `true`, `12.` on its way
to a number). Treat `null` as "no update this frame" and keep the previous
value; the next token resolves it.

Structure that has already arrived is returned even when it is still empty, so
`parsePartialJson('{"titl')` is `{}` rather than `null`: the buffer has told you
it is an object, only the first key is incomplete. The same goes for a growing
array, where an element that has only just opened shows up as an empty one:
`parsePartialJson('[{"a": 1}, {"b')` is `[{a: 1}, {}]`.

## Stream the object as it grows

`streamPartialJson` accumulates a delta stream and emits the value after each
token, skipping frames that do not parse yet or that did not change.

```dart
await for (final partial in streamPartialJson(modelDeltas)) {
  // A model can answer with something that is not an object — `null`, a bare
  // string, an array — and that arrives here as a frame too, so check before
  // casting rather than assuming the happy shape.
  if (partial is! Map<String, dynamic>) continue;
  setState(() => _draft = partial);   // render the object filling in
}
```

## Plug in your provider

`sseJson` decodes the Server-Sent Events body providers stream, and an adapter
pulls the text fragment out of each event. OpenAI, Anthropic, and Gemini shapes
are built in, so a response goes end to end with no line handling of your own:

```dart
final response = await request.close();

streamPartialJsonFrom(sseJson(response), openAiDelta)  // choices[0].delta.content
    .listen((partial) => print(partial));

streamPartialJsonFrom(sseJson(response), anthropicDelta); // tool call's delta.partial_json
streamPartialJsonFrom(sseJson(response), geminiDelta);    // candidates[0].content.parts[0].text
```

Anthropic has two shapes and they must not be mixed. `anthropicDelta` follows a
forced tool call's `partial_json`, which is the way to get structured output;
it ignores the prose text block a model usually emits first, because splicing
that onto the JSON would break parsing. If instead you asked for raw JSON as
plain text with no tool, use `anthropicTextDelta`.

`sseJson` takes the raw byte stream, so chunk boundaries falling inside a line
or an event are handled for you. It follows the event-stream format: several
`data:` lines in one event are joined with newlines, one leading space after
the colon is stripped, `:` comments and the `event:`/`id:`/`retry:` fields are
ignored, and the `[DONE]` sentinel ends the stream rather than being parsed. If
you want the payloads without the JSON decode, use `sseData`, and if your
transport already gives you lines, `sseDataFromLines`.

## Type it

`streamPartial<T>` maps each growing object through a builder. Write the builder
to tolerate a half-filled map and you get a typed value on every step.

```dart
final titles = streamPartial<String>(
  modelDeltas,
  (m) => (m['title'] as String?) ?? '',
);
```

From an HTTP response, `streamPartialFrom` is the same thing over a provider's
chunks, which is the whole path in one call:

```dart
streamPartialFrom(sseJson(response), openAiDelta, Recipe.fromPartial)
    .listen((recipe) => setState(() => _recipe = recipe));
```

|                  | text fragments      | a provider's chunks     |
| ---------------- | ------------------- | ----------------------- |
| `Object?` frames | `streamPartialJson` | `streamPartialJsonFrom` |
| your type        | `streamPartial`     | `streamPartialFrom`     |

`example/openai_end_to_end.dart` runs that path end to end with no API key, on
bytes chopped at arbitrary boundaries the way a socket delivers them.

## What it handles

- open string values are kept and closed, so partial text shows as it types
- open objects and arrays are closed to any depth
- dangling keys, colons, and commas are dropped
- braces and quotes inside strings, and escaped quotes, do not confuse it
- a valid partial number is kept; an unresolved literal skips that one frame

It does the retrieval-of-structure, not generation. It never calls a model; you
bring the stream. An unresolved scalar yields `null` rather than a guess, which
keeps a half-written value off your screen; structure that has arrived is
reported as far as it goes, so a container the model has opened but not yet
filled appears as an empty one.

## Roadmap

Typed streaming today needs a small hand-written builder. Generated builders,
so `streamPartial<T>` needs no mapping for your own classes, are planned next.

## License

MIT.

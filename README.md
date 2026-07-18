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

It returns `null` while nothing is decodable yet (an empty buffer, a lone `{`
with only a partial key, a half-written `tr`). Treat `null` as "no update this
frame" and keep the previous value; the next token resolves it.

## Stream the object as it grows

`streamPartialJson` accumulates a delta stream and emits the value after each
token, skipping frames that do not parse yet or that did not change.

```dart
await for (final partial in streamPartialJson(modelDeltas)) {
  final map = partial as Map<String, dynamic>;
  setState(() => _draft = map);   // render the object filling in
}
```

## Plug in your provider

Decode each Server-Sent Event into a `Map`, then let an adapter pull the text
fragment out. OpenAI, Anthropic, and Gemini shapes are built in.

```dart
// chunks is Stream<Map<String, dynamic>> of decoded SSE events
streamPartialJsonFrom(chunks, openAiDelta)      // choices[0].delta.content
    .listen((partial) => print(partial));

streamPartialJsonFrom(chunks, anthropicDelta);  // delta.text / delta.partial_json
streamPartialJsonFrom(chunks, geminiDelta);     // candidates[0].content.parts[0].text
```

## Type it

`streamPartial<T>` maps each growing object through a builder. Write the builder
to tolerate a half-filled map and you get a typed value on every step.

```dart
final titles = streamPartial<String>(
  modelDeltas,
  (m) => (m['title'] as String?) ?? '',
);
```

## What it handles

- open string values are kept and closed, so partial text shows as it types
- open objects and arrays are closed to any depth
- dangling keys, colons, and commas are dropped
- braces and quotes inside strings, and escaped quotes, do not confuse it
- a valid partial number is kept; an unresolved literal skips that one frame

It does the retrieval-of-structure, not generation. It never calls a model; you
bring the stream. A frame that still will not parse yields `null` rather than a
guess, which keeps a wrong intermediate value off your screen.

## Roadmap

Typed streaming today needs a small hand-written builder. Generated builders,
so `streamPartial<T>` needs no mapping for your own classes, are planned next.

## License

MIT.

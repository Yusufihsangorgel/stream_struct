![stream_struct: a token stream parsed into the object as it fills in](https://raw.githubusercontent.com/Yusufihsangorgel/stream_struct/main/doc/banner.png)

# stream_struct

Turn a language model's token stream into a stream of the structured object as
it fills in.

![stream_struct parses a JSON object and fills it in token by token as it streams](https://raw.githubusercontent.com/Yusufihsangorgel/stream_struct/main/doc/demo.gif)

## Why this instead of what you already have

**Instead of waiting for the whole response.** `jsonDecode` accepts a truncated
buffer only by accident. Replay one 150-character model answer a character at a
time and it accepts 1 of the 150 non-empty prefixes, while `parsePartialJson`
accepts all 150. `dart run tool/growth_figure.dart` measures that and refuses to
write the drawing when the numbers stop holding.

**Instead of `llm_json_stream`.** It is the larger reactive parser, with path
subscriptions and per-property streams, and it starts one layer above the wire.
Its provider snippets all take a chunk some SDK has already decoded
(`README.md:449` and `:466`); grep it for `event-stream` or `HttpClientResponse`
and there are no hits at all. The only nearby string in the whole package is a
`utf8.decoder` call in an example CLI that reads from stdin, not from a
provider's HTTP response, so it doesn't change the picture: a plain
`package:http` call still means writing the SSE framing first. `sseData`
(`lib/src/sse.dart:31`) is that step. Its Anthropic snippet reads
`event.delta?.text` (`README.md:466`), which is the prose block. A forced tool
call streams through `partial_json`, a string that appears nowhere in that
package; `anthropicDelta` (`lib/src/streaming.dart:49`) reads it, and
`anthropicTextDelta` (`:115`) reads the other one.

**Reach for it when**

- You render model output into a form or a card and want fields to appear as
  they arrive.
- You call a provider over HTTP yourself and are holding a raw
  `text/event-stream` body.
- You use an Anthropic tool call for structured output and need the arguments,
  not the sentence the model writes before them.

Skip it if the whole response lands in well under a second, because then partial
parsing buys you nothing that a spinner does not.

A model asked for JSON emits it one token at a time. Mid-stream you are holding
something like `{"title": "The quick bro` , which `jsonDecode` throws on until
the very last token lands. So the usual choices are to wait for the whole
response before showing anything, or to hand-roll a fragile parser. `stream_struct`
is the parser, done once and tested, plus the provider glue.

![A step chart. One 150-character model answer is replayed a character at a time and both parsers are asked for a value at every prefix. The green parsePartialJson line climbs in steps from zero to all eight fields as the characters arrive, with half of them on screen by character 68. The red dart:convert jsonDecode line stays flat on zero for the whole stream and jumps to eight only at the final character. Below the chart, three of those prefixes are listed, each showing the truncated buffer next to the value returned for it.](https://raw.githubusercontent.com/Yusufihsangorgel/stream_struct/main/doc/growth.png)

That is one answer replayed a character at a time, with both parsers asked for a
value at every prefix. `jsonDecode` accepts 1 of the 150 non-empty prefixes and
`parsePartialJson` accepts all 150; the height of the green line is what a UI
could have on screen at that point. The notch near character 68 is `rating`. Its
value has reached only `4.` there, which is not a number yet, and the field
drops out for a single character. `dart run tool/growth_figure.dart` measures
all of it and writes the drawing.

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
value; the next token resolves it. A fully decoded top-level `null` also comes
back as `null`, which means `parsePartialJson` alone cannot tell "the value is
`null`" from "nothing yet". If you need to, use `parsePartialJsonResult`, whose
`hasValue` distinguishes them (this is why the streaming helpers can emit a
resolved `null` exactly once).

Structure that has already arrived is returned even when it is still empty.
`parsePartialJson('{"titl')` is `{}` rather than `null`: the buffer has told you
it is an object, only the first key is incomplete. The same goes for a growing
array, where an element that has only just opened shows up as an empty one:
`parsePartialJson('[{"a": 1}, {"b')` is `[{a: 1}, {}]`.

## Stream the object as it grows

`streamPartialJson` accumulates a delta stream and emits the value after each
token, skipping frames that do not parse yet or that did not change.

```dart
await for (final partial in streamPartialJson(modelDeltas)) {
  // A model can answer with something that is not an object: `null`, a bare
  // string, an array. Those arrive here as frames too, so check before
  // casting rather than assuming the happy shape.
  if (partial is! Map<String, dynamic>) continue;
  setState(() => _draft = partial);   // render the object filling in
}
```

## Plug in your provider

`sseJson` decodes the Server-Sent Events body providers stream, and an adapter
pulls the text fragment out of each event. OpenAI, Anthropic, and Gemini shapes
are built in, and a response goes end to end with no line handling of your own:

```dart
final response = await request.close();

streamPartialJsonFrom(sseJson(response), openAiDelta)  // choices[0].delta.content
    .listen((partial) => print(partial));

streamPartialJsonFrom(sseJson(response), anthropicDelta); // tool call's delta.partial_json
streamPartialJsonFrom(sseJson(response), geminiDelta);    // candidates[0].content.parts[].text
```

OpenAI, Anthropic, and Gemini each have two shapes, and picking the wrong one
gives you a stream that emits nothing and raises no error.

On OpenAI it depends on how you asked for the schema. With `response_format`
the JSON is the model's `content`, which is what `openAiDelta` reads. Force a
tool call instead, with `tools` and `tool_choice`, and the JSON arrives as
`tool_calls[n].function.arguments` while `content` stays null the whole way:

```dart
streamPartialJsonFrom(sseJson(response), openAiToolDelta())
    .listen((partial) => print(partial));
```

`openAiToolDelta` is a factory because parallel tool calls interleave in one
`tool_calls` list, each entry carrying its own `index`, and their fragments are
different JSON values. It follows the first call by default, takes `index:` to
follow another, and keeps that choice — so create one per stream.

Anthropic splits the same way. `anthropicDelta` follows a forced tool call's
`partial_json`, and ignores the prose text block a model usually emits first,
because splicing that onto the JSON would break parsing. If instead you asked
for raw JSON as plain text with no tool, use `anthropicTextDelta`; for an
answer holding several tool calls, `anthropicToolDelta`.

Gemini splits the same way. `geminiDelta` reads `parts[].text`. A function call
puts the payload in `functionCall.args` while `text` stays empty, so
`geminiDelta` is blind to it:

```dart
streamPartialJsonFrom(sseJson(response), geminiToolDelta())
    .listen((partial) => print(partial));
```

Gemini does not stream those arguments token by token. On
`streamGenerateContent` the call arrives complete in one chunk, `args` already
a JSON object, not a string fragment. `geminiToolDelta` encodes that object so
you get one frame — the finished arguments — rather than a growing prefix.
Vertex AI's `streamFunctionCallArguments` flag is a different shape
(`partialArgs` with `jsonPath`); those are not concatenable JSON, and this
extractor does not read them. Parallel calls are several `functionCall` parts
on one content: it follows the first by default, takes `index:` to follow
another, and keeps that choice — so create one per stream.

`sseJson` decodes SSE frames; it does not interpret what is in them. A provider
that signals a mid-stream failure with a data event (an OpenAI `{"error": ...}`
frame, say, after a rate limit) sends that as data, and the delta extractor
returns nothing for it, the same as for any non-content event. The stream then
ends normally with whatever partial value had accumulated, and no error is
raised: a truncated answer can look like a finished one. A genuine stream error
(a dropped socket) still propagates; it is only an in-band error *event* that is
skipped. If a provider signals errors this way, check for its error frame
yourself rather than trusting that a completed stream means a complete answer.

`sseJson` takes the raw byte stream and handles chunk boundaries that fall
inside a line or an event. It follows the event-stream format: several
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

It extracts structure; it does not produce content. It never calls a model; you
bring the stream. An unresolved scalar yields `null` rather than a guess, which
keeps a half-written value off your screen; structure that has arrived is
reported as far as it goes: a container the model has opened but not yet
filled appears as an empty one.

## Cost

`streamPartialJson` re-parses the whole buffer on every delta, so the work is
quadratic in the length of the response: a stream twice as long costs about four
times as much, not twice. Measured on a growing JSON array, 1,000 elements took
about a second and 4,000 took about fourteen. For the interactive case this is
built for (a model streaming a UI-sized object at reading speed) that cost is
invisible. It becomes real for a large machine-to-machine payload: if you are
streaming a multi-megabyte document only to consume the final value, decode it
once at the end with `dart:convert` instead, and use this package for the
partials you actually render.

## Roadmap

Typed streaming today needs a small hand-written builder. Generated builders
are planned next: `streamPartial<T>` will need no mapping for your own classes.

## License

MIT.

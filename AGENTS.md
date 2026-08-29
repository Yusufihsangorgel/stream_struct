# stream_struct

`stream_struct` turns a language model's truncated JSON token stream into a stream of the structured value as it fills in. It does not make HTTP requests, handle API keys, or validate a schema; you supply the raw SSE body or the text deltas.

## Usage

From `example/openai_end_to_end.dart`. The raw byte stream enters at `sseJson`: `_socket(_responseBody)` is a `Stream<List<int>>` (the same type as `HttpClientResponse`).

```dart
final recipes = streamPartialFrom(
  sseJson(_socket(_responseBody)),
  openAiDelta,
  Recipe.fromPartial,
);
```

Text fragments already in hand: `streamPartialJson(deltas)`. Decoded event maps already in hand: `streamPartialJsonFrom(chunks, openAiDelta)`.

## Contracts

**`parsePartialJson`.** Returns `null` before anything is decodable (empty/whitespace, or an unresolved scalar such as `tr` or `12.`). It does not throw. Completing the buffer and still failing `jsonDecode` is the same `null`: `parsePartialJsonResult` catches `FormatException` and reports `hasValue: false`. That is not an SSE failure; `sseJson` throws `FormatException` when an event payload is not a JSON object. Opened structure is returned even if empty: `parsePartialJson('{"titl')` is `{}`. A resolved JSON `null` also comes back as `null`; `parsePartialJson` cannot tell those apart. `streamPartialJson` emits a top-level `null` once, using `parsePartialJsonResult.hasValue` internally. `parsePartialJsonResult` is `@internal` and is not exported from `package:stream_struct/stream_struct.dart`.

**Extractors.** A `DeltaExtractor` returns the text fragment from one decoded event, or `null`. The wrong extractor returns `null` on every chunk; `streamPartialJsonFrom` then emits nothing and raises nothing.

| Symbol | Reads | Use when |
| --- | --- | --- |
| `openAiDelta` | `choices[0].delta.content` | JSON via `response_format` |
| `openAiToolDelta()` | `choices[0].delta.tool_calls[n].function.arguments` | forced tool call (`tools` + `tool_choice`) |
| `anthropicDelta` | `delta.partial_json` | one forced tool call |
| `anthropicToolDelta()` | one block's `partial_json` | several tool calls |
| `anthropicTextDelta` | `delta.text` | JSON as plain text, no tool |
| `geminiDelta` | first non-thought `candidates[0].content.parts[].text` | Gemini text |

`openAiToolDelta` and `anthropicToolDelta` are factories: they remember which `index` they locked onto. Call once per stream.

A forced tool call is not content. On OpenAI, `content` stays `null` for the whole answer while JSON arrives in `arguments`, so `openAiDelta` is blind to it. On Anthropic, JSON is `partial_json` on the tool block; a leading prose `delta.text` is not part of it. `anthropicDelta` ignores that text so it is not spliced onto the JSON (`Let me look that up.{"name":"Ada"}` yields zero frames). `geminiDelta` skips a part with `thought: true` for the same reason.

**SSE helpers.**

- `sseJson` / `sseData`: `Stream<List<int>>` — raw HTTP body bytes. Not lines, not maps. Chunks may split mid-line.
- `sseDataFromLines`: `Stream<String>` — lines already split.
- `sseJsonFromData`: `Stream<String>` — `data:` payloads already extracted.
- `sseDoneSentinel` (`[DONE]`) ends `sseJson`; it is not decoded.

## Mistakes

- Wrong extractor (`openAiDelta` on a tool-call stream, `openAiToolDelta()` on a content stream, `anthropicTextDelta` on a tool stream, or the reverse). Symptom: zero frames, stream ends, no error. Fix: match the table to how you asked for JSON.
- `anthropicDelta` on parallel tool use. Symptom: fragments from two JSON values concatenate; later calls vanish. Fix: `anthropicToolDelta()` or `anthropicToolDelta(index: n)`.
- One `openAiToolDelta()` / `anthropicToolDelta()` shared across streams. Symptom: the second stream follows the first locked `index`. Fix: one factory call per stream.
- Lines or `Map` chunks passed to `sseJson`. Symptom: type error. Fix: bytes → `sseJson`; lines → `sseDataFromLines`; maps → `streamPartialJsonFrom`.
- Builder field read as `partial['title'] as String`. Symptom: cast throw on the first fragment. Fix: `as String? ?? ''` (`Recipe.fromPartial` in the example).
- `jsonDecode` on the live buffer. Symptom: `FormatException` until the last token. Fix: `parsePartialJson` / `streamPartialJson`.
- Treating stream completion as a complete answer. Symptom: an in-band `{"error": ...}` data event is skipped like any non-content chunk. Fix: inspect the provider's error frame yourself.
- Branching on a partial number. Symptom: `2` then `20`. Render; do not commit until the stream ends.
- `streamPartial` / `streamPartialFrom` when the value is an array or scalar. Symptom: empty typed stream. Those skip non-objects; use `streamPartialJson`.

## Layout

- Public API: `lib/stream_struct.dart` (re-exports `lib/src/partial_json.dart`, `lib/src/sse.dart`, `lib/src/streaming.dart`).
- Tests: `test/partial_json_test.dart`, `test/sse_test.dart`, `test/streaming_test.dart`.
- Examples (offline, no key): `example/openai_end_to_end.dart`, `example/stream_struct_example.dart`, `example/two_providers.dart`.

```
dart test
dart run example/openai_end_to_end.dart
dart run example/stream_struct_example.dart
dart run example/two_providers.dart
```

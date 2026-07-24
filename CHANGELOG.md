## 0.3.5

- **Fix `anthropicDelta` for tool-based structured output.** It returned both a
  content block's `delta.text` and a tool block's `delta.partial_json`, and a
  real Anthropic answer emits a prose text block ("Let me look that up.") before
  the tool call — so the prose was spliced onto the front of the JSON buffer and
  the whole thing stopped parsing. Reproduced end to end: a tool stream with a
  leading text block yielded **zero frames**. `anthropicDelta` now follows only
  the tool block's `partial_json`, which is the way to get structured output
  from Anthropic; the same stream now resolves to `{"name": "Ada"}`.
- Add `anthropicTextDelta` for the other Anthropic shape — a model asked for raw
  JSON as plain text, with no tool — which reads `delta.text`. The two modes
  never both apply to one answer, so they are separate functions rather than one
  that guesses and occasionally concatenates.

  Breaking only if you were using `anthropicDelta` against a no-tool prose-JSON
  stream; switch that call to `anthropicTextDelta`.

## 0.3.4

- **Fix the README's own streaming example.** It cast every frame with
  `partial as Map<String, dynamic>`, and 0.3.2 added the top-level-`null` frame
  on purpose — so a model that answers `null` made the documented example throw
  `_TypeError`. Reproduced with the README lines verbatim over the deltas `nu`
  then `ll`. The example now checks the shape before using it, which is what a
  caller has to do anyway once the answer can be a scalar or an array.
- Stop shipping `doc/blog/` in the published archive. It held a diagram used by
  a write-up, not by the package. 249 KB compressed before, 112 KB after.

## 0.3.3

- Correct what `parsePartialJson` says it returns. The README and the doc
  comment both listed "a lone `{` with only a partial key" among the cases that
  return `null`, and that has never been what the code does: `'{"titl'` decodes
  to `{}`, not to `null`, and the package's own test has asserted exactly that
  since the function was written. So the documentation contradicted both the
  behaviour and the test suite.
- The real rule, now written down in both places: `null` means an empty buffer
  or a value still resolving into a scalar, such as `tr` on its way to `true`.
  Structure that has already arrived comes back even when it is still empty,
  because the buffer has established what the value is: an object whose first
  key is half-written reads as `{}`, and an array whose newest element has only
  just opened reads with an empty element at the end, `[{a: 1}, {}]`. That
  second case is now covered by a test as well, since it is the one that shows
  up as an unexpected frame in a stream.
- No behaviour change: this release only makes the documentation describe the
  code. It lands before 1.0.0 because 1.0.0 would freeze the documented
  contract, and freezing a false one leaves no good way out.

## 0.3.2

- Fix `streamPartialJson` (and `streamPartialJsonFrom`, which wraps it)
  silently dropping every frame of a stream that resolves to a top-level JSON
  `null`. `parsePartialJson` returns `null` both for "nothing decodable yet"
  and for a buffer that decodes to the literal `null`, and `streamPartialJson`
  treated the two the same: skip the frame. A model answering bare `null` (a
  common "nothing matched" schema) produced no frames and no error, on every
  delta, for the rest of the stream, which reads as a stalled connection
  rather than a real answer. `streamPartialJson` now resolves that ambiguity
  internally, so a genuine top-level `null` is emitted once, like any other
  value. `parsePartialJson`'s own `Object?` contract is unchanged: called
  directly, it still cannot tell the two cases apart.

## 0.3.1

- Declare the recording in `pubspec.yaml` so pub.dev renders it on the package
  page. It was already in the repository and the README, but pub.dev shows only
  what the `screenshots:` field points at.

## 0.3.0

- `streamPartialFrom` completes the four ways in. There were entry points for
  text fragments to `Object?` frames, for text fragments to your own type, and
  for a provider's chunks to `Object?` frames, but not for a provider's chunks
  to your own type, which is the combination an app actually wants: a typed
  value rendered as an SSE response arrives. Reaching it meant rebuilding by
  hand the map/where/cast that `streamPartialJsonFrom` already does. Now it is
  `streamPartialFrom(sseJson(response), openAiDelta, Recipe.fromPartial)`.
- `example/openai_end_to_end.dart` runs that path end to end with no API key and
  no network, on a canned OpenAI body fed in at arbitrary byte boundaries so the
  cuts land mid-line and mid-token, which is what a socket does and the only
  part of SSE that is hard.
- `example/README.md` covers writing a builder that tolerates a half-filled
  object, choosing among the four entry points, and the thing the output makes
  visible: a partial number reads 2 before it reads 20, so a partial value is
  not merely incomplete, it can be provisionally wrong. Render it, don't act on
  it.

## 0.2.1

- Shorten the pub.dev description back under the 180-character limit. The
  previous release grew it past that, which costs the "valid pubspec" points
  and truncates the text search engines show.

## 0.2.0

- Add Server-Sent Events decoding: `sseJson` turns a provider's raw response
  stream into one JSON event per message, and `sseData` gives the payloads
  undecoded. The package started after that step, so every caller wrote the
  same line handling; now a response body goes end to end,
  `streamPartialJsonFrom(sseJson(response), openAiDelta)`. Chunk boundaries
  inside a line or an event are handled, several `data:` lines in one event are
  joined with newlines, one leading space after the colon is stripped, `:`
  comments and the `event:`/`id:`/`retry:` fields are ignored, CRLF bodies work,
  and the `[DONE]` sentinel ends the stream instead of being parsed.
  `sseDataFromLines` and `sseJsonFromData` take over if your transport already
  split the stream.
- Docs: correct the pub.dev description. It said "provider-agnostic, you bring
  the token stream", which undersold the package: `openAiDelta`,
  `anthropicDelta` and `geminiDelta` ship with it and always have.

## 0.1.2

- Docs: sharpen the pub.dev description to lead with the value and the terms people search.

## 0.1.1

- Shorten the pubspec description so it fits pub.dev's 180-character
  guideline; no API or behaviour change.

## 0.1.0

- Initial release.
- `parsePartialJson`: tolerant decode of a truncated JSON buffer into the value
  it holds so far (closes open string values and containers, drops dangling
  keys, colons, and commas).
- `streamPartialJson` / `streamPartialJsonFrom`: turn a delta stream into a
  stream of the growing value, skipping unparseable and unchanged frames.
- `streamPartial<T>`: map growing objects into a typed value with a hand-written
  builder.
- Provider delta adapters: `openAiDelta`, `anthropicDelta`, `geminiDelta`.

Planned for a later release: generated builders so `streamPartial<T>` needs no
hand-written mapping.

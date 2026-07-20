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

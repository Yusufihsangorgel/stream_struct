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

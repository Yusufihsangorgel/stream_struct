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

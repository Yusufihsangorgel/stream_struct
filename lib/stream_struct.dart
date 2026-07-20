/// Turn a language model's token stream into a stream of the structured object
/// as it fills in.
///
/// [parsePartialJson] decodes a truncated JSON buffer into the value it holds so
/// far. [streamPartialJson] and [streamPartialJsonFrom] turn a delta stream into
/// a stream of growing values, and [streamPartial] maps those into a typed
/// object. [openAiDelta], [anthropicDelta], and [geminiDelta] pull the text
/// fragment out of each provider's streamed chunk.
///
/// [sseJson] decodes the Server-Sent Events body those providers actually send,
/// so an HTTP response can go straight through without hand-written line
/// handling; [sseData] gives the raw payloads if you want to decode them
/// yourself.
library;

export 'src/partial_json.dart' show parsePartialJson;
export 'src/sse.dart'
    show
        sseData,
        sseDataFromLines,
        sseDoneSentinel,
        sseJson,
        sseJsonFromData;
export 'src/streaming.dart'
    show
        DeltaExtractor,
        openAiDelta,
        anthropicDelta,
        geminiDelta,
        streamPartialJson,
        streamPartialJsonFrom,
        streamPartial;

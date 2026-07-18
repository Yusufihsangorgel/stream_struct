/// Turn a language model's token stream into a stream of the structured object
/// as it fills in.
///
/// [parsePartialJson] decodes a truncated JSON buffer into the value it holds so
/// far. [streamPartialJson] and [streamPartialJsonFrom] turn a delta stream into
/// a stream of growing values, and [streamPartial] maps those into a typed
/// object. [openAiDelta], [anthropicDelta], and [geminiDelta] pull the text
/// fragment out of each provider's streamed chunk.
library;

export 'src/partial_json.dart' show parsePartialJson;
export 'src/streaming.dart'
    show
        DeltaExtractor,
        openAiDelta,
        anthropicDelta,
        geminiDelta,
        streamPartialJson,
        streamPartialJsonFrom,
        streamPartial;

# Package engineering rules: stream_struct

Rules-Version: stream_struct/165993ecd7416f2bd4fcceff95ae04f951e57e3c52fc732fd912977624e269b4
Core-Version: 1
Core-Digest: 1825fa7ff346dca23e65b1b3bf9b2e3e06959f1414bae9952d596d2f62f09b8f
Survey-Digest: f90f45c8a172068c3ed3b9488ba5a7cb4e58efa93c380d2d9a70b399349ec35e
Evidence-Revision: 98a44bd
Verified-Revision: unverified

Read CONTRIBUTING.md and docs/engineering/debt.json before editing.

## Current architecture
A small class-free, function-based streaming library: two independent leaves and one combiner. partial_json.dart is a tolerant partial JSON parser. It never throws. sse.dart is a provider-independent SSE decoder. streaming.dart holds the provider-specific DeltaExtractor functions and the streamPartial* stream combiners. It depends on partial_json. The caller builds the chain: sseJson → extractor → streamPartialFrom. Stateful extractors are factories that return closures under a 'one per stream' rule. The only runtime dependency is meta (@internal). Integration with instructor_dart is a dev dependency and goes through an example. Scanned HEAD: 98a44bd (version 1.4.2).

## Layers and responsibilities
- lib/stream_struct.dart: Exposes functions and typedefs with `show`. @internal helpers stay out.
- lib/src/partial_json.dart: Completes and decodes a truncated JSON buffer. Returns null when no value exists. It does not throw.
- lib/src/sse.dart: Conversion of bytes, lines, or payloads into SSE `data` payloads and JSON objects, with a [DONE] sentinel.
- lib/src/streaming.dart: DeltaExtractors that pull the text fragment from each event (5-315), streamPartial* functions that accumulate fragments and emit the growing value (317-401).
- example/, tool/growth_figure.dart, test/: Offline, key-free examples, a README figure, unit and regression tests.

## Public API and dependency direction
lib/stream_struct.dart exposes with `show`: parsePartialJson; sseData, sseDataFromLines, sseDoneSentinel, sseJson, sseJsonFromData; DeltaExtractor and seven provider extractors (text and tool call variants for three providers); streamPartialJson, streamPartialJsonFrom, streamPartial, streamPartialFrom (stream_struct.dart:18-34). @internal and not exported: PartialJsonResult, parsePartialJsonResult (partial_json.dart:39-53). No classes. The event type in public signatures is Map<String, dynamic> (streaming.dart:10; sse.dart:82, 87).

streaming.dart → dart:convert, partial_json.dart (1-3). sse.dart → dart:async, dart:convert, no other package files (1-2). partial_json.dart → dart:convert, package:meta (1-3). SSE and the extractors do not know about each other. Direction: combiner → parser, transport layer independent. The only runtime dependency is meta. instructor_dart is dev only (pubspec.yaml:32-36).

## Error, state and platform contracts
- Tolerant parser: returns null instead of throwing, meaning 'no update this frame' (partial_json.dart:18-21, 53-63).
- @internal for helpers shared across files but outside the API (partial_json.dart:46-53).
- Extractor = `typedef DeltaExtractor`. Stateless ones are top-level functions. Stateful ones that lock state are factories returning closures (streaming.dart:10, 70-98, 159-185, 287-315).
- An extractor returns null for an event it does not own. It guards every read with a type test. It never throws on an unknown shape (streaming.dart:21-34, 218-238).
- The symptom of picking the wrong extractor is written in dartdoc: zero frames, no error (streaming.dart:17-20, 214-217).
- Stream transformation with async* generators (sse.dart:39-65; streaming.dart:325-401).
- Every fix ships with a regression test that replays the event sequence and a CHANGELOG entry that names the symptom (98a44bd → streaming_test.dart:473-487, CHANGELOG.md:1-20).

## Package rules
### stream_struct/SS-01 [MUST]
lib/src/partial_json.dart and lib/src/sse.dart stay provider-neutral. Only the extractors read provider event shapes.
Reason: Provider differences stay in one place. The parser and the SSE decoder are reused with every provider.
Evidence: lib/src/sse.dart:4-12; lib/src/partial_json.dart:1-3; lib/src/streaming.dart:5-10
Evidence role: current-pattern
Existing violation: none

### stream_struct/SS-02 [MUST]
An extractor is a `DeltaExtractor`. It returns the text fragment of an event it owns and `null` for any other event, type-checks every value it reads, and never throws on an unexpected shape.
Reason: Streams also carry role headers, usage information and finish events. The extractor must skip all of them silently.
Evidence: lib/src/streaming.dart:10, 21-34, 118-125, 196-203, 218-238
Evidence role: current-pattern
Existing violation: none

### stream_struct/SS-03 [MUST]
An extractor that remembers which call it follows is a factory returning a fresh closure, and its dartdoc says to create one per stream.
Reason: A shared closure tracks, on the second stream, the index at which the first stream locked (AGENTS.md Mistakes).
Evidence: lib/src/streaming.dart:50-53, 70-98, 146-150, 159-185, 266-272, 287-315
Evidence role: current-pattern
Existing violation: none

### stream_struct/SS-04 [MUST]
`parsePartialJson` never throws. An undecodable buffer yields `null`, and structure already received stays visible.
Reason: The progressive UI draws every frame. A single throw breaks the stream.
Evidence: lib/src/partial_json.dart:18-33, 53-63; test/partial_json_test.dart:6
Evidence role: current-pattern
Existing violation: none

### stream_struct/SS-05 [MUST]
Helpers shared across files but outside the API carry `@internal` and stay out of the `show` list in lib/stream_struct.dart.
Reason: The split between public API and internal helper is marked with meta.
Evidence: lib/src/partial_json.dart:39-53; lib/stream_struct.dart:18
Evidence role: current-pattern
Existing violation: none

### stream_struct/SS-06 [MUST]
A fix lands with a regression test that replays the event sequence that broke, and a CHANGELOG entry that names the symptom.
Reason: Repository practice. The last fix arrived in this shape.
Evidence: commit 98a44bd → test/streaming_test.dart:473-487 and CHANGELOG.md:1-20; all of the last 8 lib commits carry a CHANGELOG and a test
Evidence role: current-pattern
Existing violation: none

### stream_struct/SS-07 [MUST_NOT]
Do not add a runtime dependency on a provider SDK or a schema validator. Integration with a validator stays in example/ under a dev dependency.
Reason: The package does no schema validation. The dependency would spread to consumers that never use streaming.
Evidence: pubspec.yaml:29-36; example/with_instructor.dart
Evidence role: current-pattern
Existing violation: none

### stream_struct/SS-08 [SHOULD]
An extractor's dartdoc names the symptom of picking the wrong one: zero frames and no error.
Reason: A wrong choice silently produces nothing. The notation being documented is the only warning.
Evidence: lib/src/streaming.dart:17-20, 214-217, 241-247
Evidence role: current-pattern
Existing violation: none

### stream_struct/SS-09 [MUST_NOT]
Do not change the `Map<String, dynamic>` event type in public signatures outside a major version.
Reason: Compatible with jsonDecode and part of the public API. Changing it is a breaking change.
Evidence: lib/src/streaming.dart:10, 346-349, 370-374, 392-395; lib/src/sse.dart:82, 87
Evidence role: current-pattern
Existing violation: none

## Required verification
- Working directory: repository root; command: dart pub get; conditions: ci.yaml job build; evidence: .github/workflows/ci.yaml:22.
- Working directory: repository root; command: dart format --output=none --set-exit-if-changed .; conditions: ci.yaml job build; evidence: .github/workflows/ci.yaml:23.
- Working directory: repository root; command: dart analyze --fatal-infos; conditions: ci.yaml job build; evidence: .github/workflows/ci.yaml:24.
- Working directory: repository root; command: dart test; conditions: ci.yaml job build; evidence: .github/workflows/ci.yaml:25.
Not verified by the survey:
- The scan used the local HEAD (98a44bd). Equality with origin and uncommitted changes were not measured.
- Whether the orphaned `///` block at sse.dart:4-12 attaches to sseDoneSentinel in dartdoc was not measured.
- streamPartialJson re-parses the whole buffer and calls jsonEncode on every delta (streaming.dart:325-337). The size of the quadratic cost on long responses was not measured.
- Cognitive complexity scores were not measured. Candidates: partial_json.dart:80-143 (_completeJson), 145-182 (_trimTail).
- Finding count with strict-inference enabled and the current test status: analyze and test were not run.

## Existing debt
The complete register is docs/engineering/debt.json.
- stream_struct-D001 | small | lib/src/partial_json.dart:85-118, 206-227 | duplicated logic
  Fix: A single private scanner that returns the open-container stack. Safety net: the prefix property test at partial_json_test.dart:6.
  Closure: A single private scanner returns the open-container stack and both _completeJson and _openClosers use it. The prefix property test in partial__test.dart passes.
- stream_struct-D002 | small | lib/src/partial_json.dart:138, 146, 173, 188-189, 193 | needless work on the hot path
  Fix: Top-level `final` RegExp constants.
  Closure: The RegExps are top-level final constants and none is built inside the per-delta path.
- stream_struct-D003 | small | lib/src/streaming.dart:386-388 | untracked promise
  Fix: The dartdoc should describe only current behavior. Keep the plan in the README or in an issue.
  Closure: The streaming.dart dartdoc describes only current behavior and the builders plan lives in the README or a tracked issue.
- stream_struct-D004 | small | lib/src/streaming.dart:5-315, 317-401 (370-380 and 392-401) | single responsibility violation + small duplication
  Fix: Move the extractors to a separate lib/src file (the export stays the same). The From variant should delegate to a shared private helper.
  Closure: Provider extractors live in a separate lib/src file and the show list in lib/stream_struct.dart is unchanged. streamPartialFrom delegates to one shared helper and the public signatures keep the Map<String, dynamic> event type.

# Examples

Two programs, neither needing an API key or a network.

## The idea, in isolation

```
dart run example/stream_struct_example.dart
```

`stream_struct_example.dart` feeds a JSON object in a token at a time and prints
it as it fills. This is `streamPartialJson` on its own: give it text fragments,
get the value the buffer holds so far, on every fragment.

## The whole path, the way it arrives

```
dart run example/openai_end_to_end.dart
```

`openai_end_to_end.dart` starts where your code actually starts, at response
bytes, and ends where your UI wants to be, at a typed object:

```
title                  prep   ingredients
------------------------------------------------------------
  Foc                    ?
  Focaccia               2 min
  Focaccia               20 min     flour
  Focaccia               20 min     flour, water, olive oil

finished with 3 ingredients.
```

That is one call:

```dart
streamPartialFrom(sseJson(response), openAiDelta, Recipe.fromPartial)
    .listen((recipe) => setState(() => _recipe = recipe));
```

`response` is the `Stream<List<int>>` an `HttpClient` request gives you.
`sseJson` decodes the Server-Sent Events framing, `openAiDelta` pulls the text
fragment out of each chunk, and `Recipe.fromPartial` turns each growing object
into your type. Swap `anthropicDelta` or `geminiDelta` for another provider;
nothing else changes.

### Why the bytes are chopped up oddly

The canned body is fed in fixed 37-byte runs, so the cuts land mid-line,
mid-token, and between the two newlines that terminate an event. A socket
delivers exactly this, and it is the only part of SSE that is hard: an example
that yields one tidy line at a time has quietly skipped it. Everything the
decoder has to survive is in there, including a `[DONE]` sentinel that ends the
stream rather than being parsed as JSON.

### One thing to take from the output

Read the prep time down the column: `?`, then `2`, then `20`. The digits of a
number arrive one at a time like every other character, so a partial value is
not merely incomplete, it can be **provisionally wrong**. The same goes for a
string that has not finished (`Foc` before `Focaccia`) and a list still gaining
elements.

Render partials, that is the point of the package. Do not branch on them, store
them, or send them anywhere. Only the last value is the answer.

## Writing the builder

`Recipe.fromPartial` is called on every growth, so each field has to tolerate
not being there yet:

```dart
factory Recipe.fromPartial(Map<String, dynamic> partial) => Recipe(
      title: partial['title'] as String? ?? '',
      prepMinutes: partial['prep_min'] as int?,
      ingredients:
          (partial['ingredients'] as List?)?.cast<String>() ?? const <String>[],
    );
```

Read with `??` defaults and keep genuinely-unknown values nullable, so the UI
can tell "not here yet" from "empty". A builder that does `partial['title'] as
String` throws on the first fragment, which is the mistake to avoid.

## Picking the entry point

|                  | text fragments      | a provider's chunks     |
| ---------------- | ------------------- | ----------------------- |
| `Object?` frames | `streamPartialJson` | `streamPartialJsonFrom` |
| your type        | `streamPartial`     | `streamPartialFrom`     |

Take the right-hand column when the source is a decoded SSE stream, which it is
whenever you are talking to OpenAI, Anthropic, or Gemini. Take the left when you
already hold the text deltas, for instance from a provider SDK that has done the
decoding for you.

## A validated object at the end

```
dart run example/with_instructor.dart
```

A live-updating UI is only half of it. If you also want a schema-validated typed
value, that is [`instructor_dart`](https://pub.dev/packages/instructor_dart):
this package fills the object as tokens arrive, that one validates (and, on a
miss, retries). `with_instructor.dart` is the seam, on canned forced-tool-call
chunks so it runs offline.

There is no shared function. Render the partials, then one `Schema.validate` on
the last frame. `Instructor.extract` always talks to a model, so it is not the
call you make on a stream that has already ended. The extractor has to match how
instructor asked: a forced tool call, so `openAiToolDelta()`, not `openAiDelta`.

import 'package:stream_struct/stream_struct.dart';
import 'package:test/test.dart';

/// One chunk of an OpenAI chat completions stream in which the model is
/// answering with a tool call, so the JSON arrives as
/// `choices[0].delta.tool_calls[n].function.arguments`.
///
/// Pass `index: null` for the servers that omit the field entirely.
Map<String, dynamic> _toolChunk(String arguments, {int? index = 0}) => {
      'choices': [
        {
          'index': 0,
          'delta': {
            'tool_calls': [
              {
                if (index != null) 'index': index,
                'function': {'arguments': arguments},
              },
            ],
          },
        },
      ],
    };

/// A whole forced tool call, in the shape OpenAI streams it: an opening chunk
/// carrying the id, the name and an empty `arguments`, then the argument
/// fragments, then a chunk that only reports the finish reason.
final _forcedToolCall = <Map<String, dynamic>>[
  {
    'choices': [
      {
        'index': 0,
        'delta': {
          'role': 'assistant',
          'content': null,
          'tool_calls': [
            {
              'index': 0,
              'id': 'call_abc123',
              'type': 'function',
              'function': {'name': 'extract_recipe', 'arguments': ''},
            },
          ],
        },
      },
    ],
  },
  _toolChunk('{"title": "Foc'),
  _toolChunk('accia", "prep_min": 2'),
  _toolChunk('0}'),
  {
    'choices': [
      {'index': 0, 'delta': <String, dynamic>{}, 'finish_reason': 'tool_calls'},
    ],
  },
];

/// One chunk of a Gemini `streamGenerateContent` body in which the model is
/// answering with a function call, so the JSON arrives as
/// `candidates[0].content.parts[n].functionCall.args` — already a decoded
/// object, not a string fragment.
Map<String, dynamic> _geminiFunctionChunk(
  Map<String, dynamic> args, {
  String name = 'extract_recipe',
}) =>
    {
      'candidates': [
        {
          'content': {
            'role': 'model',
            'parts': [
              {
                'functionCall': {
                  'name': name,
                  'args': args,
                },
              },
            ],
          },
        },
      ],
    };

/// A whole function call, in the shape Gemini streams it: a thought chunk,
/// an empty-parts chunk, the complete `functionCall.args` object in one
/// event, then a finish-reason chunk. Arguments do not arrive as growing
/// JSON text; the payload is one finished object.
final _forcedGeminiFunctionCall = <Map<String, dynamic>>[
  {
    'candidates': [
      {
        'content': {
          'role': 'model',
          'parts': [
            {'text': 'I will extract the recipe.', 'thought': true},
          ],
        },
      },
    ],
  },
  {
    'candidates': [
      {
        'content': {
          'role': 'model',
          'parts': <Object?>[],
        },
      },
    ],
  },
  _geminiFunctionChunk({'title': 'Focaccia', 'prep_min': 20}),
  {
    'candidates': [
      {
        'finishReason': 'STOP',
        'content': {
          'role': 'model',
          'parts': [
            {'text': ''},
          ],
        },
      },
    ],
  },
];

void main() {
  group('streamPartialJson', () {
    test('emits the object growing and ends on the final value', () async {
      final deltas = Stream.fromIterable([
        '{"name": "Ad',
        'a", "age": ',
        '36}',
      ]);
      final frames = await streamPartialJson(deltas).toList();
      expect(frames.last, {'name': 'Ada', 'age': 36});
      // Every frame is a prefix-consistent view; the name appears before age.
      expect(frames.first, {'name': 'Ad'});
    });

    test('skips unchanged frames', () async {
      final deltas = Stream.fromIterable(['{"a":1', '', '   ']);
      final frames = await streamPartialJson(deltas).toList();
      expect(frames, [
        {'a': 1},
      ]);
    });

    test('emits a frame when the value itself is a top-level null', () async {
      // A resolved `null` and "nothing parseable yet" both read as `null`
      // from parsePartialJson; without disambiguation this stream would end
      // having emitted nothing, indistinguishable from a stalled connection.
      final deltas = Stream.fromIterable(['nu', 'll']);
      final frames = await streamPartialJson(deltas).toList();
      expect(frames, [null]);
    });
  });

  group('provider adapters', () {
    test('openAiDelta reads choices[0].delta.content', () {
      expect(
        openAiDelta({
          'choices': [
            {
              'delta': {'content': 'he'}
            },
          ],
        }),
        'he',
      );
      expect(openAiDelta({'choices': []}), isNull);
    });

    test('openAiDelta returns null for a tool-call chunk', () {
      // The split between the two OpenAI adapters is deliberate, and this is
      // what makes it necessary: a forced tool call leaves content null for
      // the whole answer, so the content adapter has nothing to return.
      expect(
        openAiDelta({
          'choices': [
            {
              'delta': {
                'content': null,
                'tool_calls': [
                  {
                    'index': 0,
                    'function': {'arguments': '{"a"'},
                  },
                ],
              },
            },
          ],
        }),
        isNull,
      );
    });

    test("openAiToolDelta reassembles a forced tool call's arguments", () {
      final extractor = openAiToolDelta();
      final fragments =
          _forcedToolCall.map(extractor).whereType<String>().toList();
      expect(fragments.join(), '{"title": "Focaccia", "prep_min": 20}');
      // The opening chunk carries an empty arguments string, and the closing
      // one carries no tool_calls at all; neither is an error.
      expect(fragments.first, isEmpty);
      expect(extractor(_forcedToolCall.last), isNull);
    });

    test('openAiToolDelta ignores a content stream', () {
      expect(
        openAiToolDelta()({
          'choices': [
            {
              'delta': {'content': '{"a"'}
            },
          ],
        }),
        isNull,
      );
    });

    test('openAiToolDelta does not splice leading prose onto the tool JSON',
        () async {
      // A model can narrate before it calls the tool, and both arrive on the
      // one stream. Fold content into this adapter and the buffer reads
      // `Let me look that up.{"name":"Ada"}`, which never parses: zero frames.
      final chunks = <Map<String, dynamic>>[
        {
          'choices': [
            {
              'delta': {'content': 'Let me look '}
            },
          ],
        },
        {
          'choices': [
            {
              'delta': {'content': 'that up.'}
            },
          ],
        },
        _toolChunk('{"name":'),
        _toolChunk('"Ada"}'),
      ];
      final frames = await streamPartialJsonFrom(
        Stream.fromIterable(chunks),
        openAiToolDelta(),
      ).toList();
      expect(frames.last, {'name': 'Ada'});
    });

    test('openAiToolDelta follows one tool call out of several', () async {
      // Parallel calls interleave in the same tool_calls list, each entry
      // tagged with its own index, and their fragments are different JSON
      // values: appended to one buffer they stop parsing and the second call
      // disappears without an error.
      final chunks = <Map<String, dynamic>>[
        _toolChunk('{"city":'),
        _toolChunk('{"tz":', index: 1),
        _toolChunk('"Oslo"}'),
        _toolChunk('"CET"}', index: 1),
      ];
      Future<List<Object?>> collect(DeltaExtractor extractor) =>
          streamPartialJsonFrom(Stream.fromIterable(chunks), extractor)
              .toList();

      // No index given: lock onto the first one seen and ignore the other.
      expect((await collect(openAiToolDelta())).last, {'city': 'Oslo'});
      // The second call is reachable by running the stream again for it.
      expect((await collect(openAiToolDelta(index: 1))).last, {'tz': 'CET'});
    });

    test('openAiToolDelta picks its call out of a chunk carrying several', () {
      // tool_calls is a list and one chunk can carry more than one entry.
      // Reading only the first would drop every later call's fragments: the
      // same silent loss as before, one level down.
      Map<String, dynamic> pair(String a, String b) => {
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'function': {'arguments': a},
                    },
                    {
                      'index': 1,
                      'function': {'arguments': b},
                    },
                  ],
                },
              },
            ],
          };

      expect(openAiToolDelta()(pair('{"city":', '{"tz":')), '{"city":');
      expect(openAiToolDelta(index: 1)(pair('{"city":', '{"tz":')), '{"tz":');
    });

    test('openAiToolDelta reads a server that omits the call index', () {
      // Ollama, LM Studio and vLLM answer OpenAI's shape without the index
      // field. A server that omits it is announcing a single call.
      final extractor = openAiToolDelta();
      expect(extractor(_toolChunk('{"a":', index: null)), '{"a":');
      expect(extractor(_toolChunk('1}', index: null)), '1}');
    });

    test('openAiToolDelta returns null for malformed chunk shapes', () {
      final shapes = <Map<String, dynamic>>[
        <String, dynamic>{},
        {'choices': <Object?>[]},
        {
          'choices': [null]
        },
        {
          'choices': [
            {'delta': null}
          ]
        },
        {
          'choices': [
            {
              'delta': {'tool_calls': 'nope'}
            }
          ]
        },
        {
          'choices': [
            {
              'delta': {
                'tool_calls': [null]
              }
            }
          ]
        },
        {
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {'function': 'nope'}
                ]
              }
            }
          ]
        },
        // A server that decoded arguments into an object rather than sending
        // string fragments. Not something that can be accumulated, but it must
        // not throw either.
        {
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {
                    'function': {'arguments': 42}
                  }
                ]
              }
            }
          ]
        },
      ];
      for (final shape in shapes) {
        expect(openAiToolDelta()(shape), isNull, reason: '$shape');
      }
    });

    test('a forced tool call goes end to end through streamPartialJsonFrom',
        () async {
      final frames = await streamPartialJsonFrom(
        Stream.fromIterable(_forcedToolCall),
        openAiToolDelta(),
      ).toList();
      // Read through openAiDelta this same stream yields nothing at all, with
      // no exception: the failure this adapter exists to end.
      expect(frames, isNotEmpty, reason: 'a silent zero-frame stream');
      expect(frames.last, {'title': 'Focaccia', 'prep_min': 20});
    });

    test('anthropicDelta reads the tool JSON and ignores prose text', () {
      expect(
          anthropicDelta({
            'delta': {'partial_json': '{"a"'}
          }),
          '{"a"');
      // A leading text block is prose, not JSON; splicing it in front of the
      // tool JSON would break parsing, so it must be dropped.
      expect(
          anthropicDelta({
            'delta': {'text': 'Let me look that up.'}
          }),
          isNull);
    });

    test('anthropicTextDelta reads prose text and ignores tool JSON', () {
      expect(
          anthropicTextDelta({
            'delta': {'text': 'hi'}
          }),
          'hi');
      expect(
          anthropicTextDelta({
            'delta': {'partial_json': '{"a"'}
          }),
          isNull);
    });

    test('anthropicToolDelta follows one tool call out of several', () async {
      // Parallel tool use opens a content block per call. anthropicDelta
      // returns every fragment whichever block it came from, so the two JSON
      // values land in one buffer, the concatenation stops parsing, and the
      // second call disappears with no error.
      final events = <Map<String, dynamic>>[
        {
          'type': 'content_block_start',
          'index': 0,
          'content_block': {'type': 'text'},
        },
        {
          'index': 0,
          'delta': {'type': 'text_delta', 'text': 'One moment.'},
        },
        {
          'type': 'content_block_start',
          'index': 1,
          'content_block': {'type': 'tool_use', 'name': 'get_weather'},
        },
        {
          'index': 1,
          'delta': {
            'type': 'input_json_delta',
            'partial_json': '{"city":"Oslo"}'
          },
        },
        {
          'type': 'content_block_start',
          'index': 2,
          'content_block': {'type': 'tool_use', 'name': 'get_time'},
        },
        {
          'index': 2,
          'delta': {'type': 'input_json_delta', 'partial_json': '{"tz":"CET"}'},
        },
      ];
      Future<List<Object?>> collect(DeltaExtractor extractor) async {
        final seen = <Object?>[];
        await for (final value in streamPartialJsonFrom(
          Stream.fromIterable(events),
          extractor,
        )) {
          seen.add(value);
        }
        return seen;
      }

      // The leading text block must not claim the slot.
      expect(await collect(anthropicToolDelta()), [
        {'city': 'Oslo'},
      ]);
      // The second call is reachable by running the stream again for it.
      expect(await collect(anthropicToolDelta(index: 2)), [
        {'tz': 'CET'},
      ]);
      // Without the index filter the second call is lost, which is the bug
      // this extractor exists to avoid.
      expect(await collect(anthropicDelta), [
        {'city': 'Oslo'},
      ]);
    });

    test(
        'a tool stream with a leading text block parses through anthropicDelta',
        () async {
      // Regression: text_delta prose used to be concatenated onto the tool
      // JSON, so a real Anthropic answer yielded zero frames.
      final events = <Map<String, dynamic>>[
        {
          'delta': {'type': 'text_delta', 'text': 'Let me '}
        },
        {
          'delta': {'type': 'text_delta', 'text': 'help.'}
        },
        {
          'delta': {'type': 'input_json_delta', 'partial_json': '{"name"'}
        },
        {
          'delta': {'type': 'input_json_delta', 'partial_json': ':"Ada"}'}
        },
      ];
      Object? last;
      await for (final v in streamPartialJsonFrom(
        Stream.fromIterable(events),
        anthropicDelta,
      )) {
        last = v;
      }
      expect(last, {'name': 'Ada'});
    });

    test('geminiDelta reads candidates[0].content.parts[0].text', () {
      expect(
        geminiDelta({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'yo'}
                ]
              }
            },
          ],
        }),
        'yo',
      );
    });

    test('geminiDelta skips a thought part and does not assume parts[0]', () {
      // With thinking on, the reasoning arrives as a thought part before the
      // answer; returning it would splice reasoning into the JSON buffer.
      expect(
        geminiDelta({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'let me think', 'thought': true},
                  {'text': '{"answer":1}'},
                ]
              }
            },
          ],
        }),
        '{"answer":1}',
      );
    });

    test('geminiDelta returns null for a function-call chunk', () {
      // The split between the two Gemini adapters is deliberate, and this is
      // what makes it necessary: a function call leaves text empty, so the
      // text adapter has nothing to return.
      expect(geminiDelta(_geminiFunctionChunk({'title': 'Focaccia'})), isNull);
    });

    test(
        "geminiToolDelta reads a function call's args from a multi-chunk stream",
        () {
      final extractor = geminiToolDelta();
      final fragments =
          _forcedGeminiFunctionCall.map(extractor).whereType<String>().toList();
      expect(fragments, ['{"title":"Focaccia","prep_min":20}']);
      // Thought, empty parts, and the finish chunk carry no args; none of
      // those is an error.
      expect(extractor(_forcedGeminiFunctionCall.first), isNull);
      expect(extractor(_forcedGeminiFunctionCall.last), isNull);
    });

    test('geminiToolDelta returns null for a chunk carrying nothing', () {
      expect(
        geminiToolDelta()({
          'candidates': [
            {
              'content': {
                'role': 'model',
                'parts': <Object?>[],
              },
            },
          ],
        }),
        isNull,
      );
    });

    test('geminiToolDelta ignores a text stream', () {
      expect(
        geminiToolDelta()({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': '{"a"'}
                ]
              }
            },
          ],
        }),
        isNull,
      );
    });

    test('geminiToolDelta does not splice thought or prose onto the tool JSON',
        () async {
      // A thought part, or a prose text part, can sit on the same stream as
      // the function call. Fold either into this adapter and the buffer reads
      // `Let me look that up.{"name":"Ada"}`, which never parses: zero frames.
      final chunks = <Map<String, dynamic>>[
        {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'Let me look that up.', 'thought': true},
                ]
              }
            },
          ],
        },
        {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'Let me look that up.'},
                ]
              }
            },
          ],
        },
        _geminiFunctionChunk({'name': 'Ada'}),
      ];
      final frames = await streamPartialJsonFrom(
        Stream.fromIterable(chunks),
        geminiToolDelta(),
      ).toList();
      expect(frames.last, {'name': 'Ada'});
    });

    test('geminiToolDelta follows one function call out of several', () async {
      // Parallel calls are several functionCall parts on one content, and
      // their args are different JSON values: appended to one buffer they
      // stop parsing and the second call disappears without an error.
      final chunks = <Map<String, dynamic>>[
        {
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'functionCall': {
                      'name': 'get_weather',
                      'args': {'city': 'Oslo'},
                    },
                  },
                  {
                    'functionCall': {
                      'name': 'get_time',
                      'args': {'tz': 'CET'},
                    },
                  },
                ]
              }
            },
          ],
        },
      ];
      Future<List<Object?>> collect(DeltaExtractor extractor) =>
          streamPartialJsonFrom(Stream.fromIterable(chunks), extractor)
              .toList();

      // No index given: lock onto the first one seen and ignore the other.
      expect((await collect(geminiToolDelta())).last, {'city': 'Oslo'});
      // The second call is reachable by running the stream again for it.
      expect((await collect(geminiToolDelta(index: 1))).last, {'tz': 'CET'});
    });

    test('geminiToolDelta index skips thought parts', () {
      final chunk = <String, dynamic>{
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'thinking', 'thought': true},
                {
                  'functionCall': {
                    'name': 'get_weather',
                    'args': {'city': 'Oslo'},
                  },
                },
                {
                  'functionCall': {
                    'name': 'get_time',
                    'args': {'tz': 'CET'},
                  },
                },
              ]
            }
          },
        ],
      };
      expect(geminiToolDelta()(chunk), '{"city":"Oslo"}');
      expect(geminiToolDelta(index: 1)(chunk), '{"tz":"CET"}');
    });

    test('geminiToolDelta picks its call out of a chunk carrying several', () {
      Map<String, dynamic> pair(
        Map<String, dynamic> a,
        Map<String, dynamic> b,
      ) =>
          {
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'functionCall': {'name': 'get_weather', 'args': a},
                    },
                    {
                      'functionCall': {'name': 'get_time', 'args': b},
                    },
                  ]
                }
              },
            ],
          };

      expect(
        geminiToolDelta()(pair({'city': 'Oslo'}, {'tz': 'CET'})),
        '{"city":"Oslo"}',
      );
      expect(
        geminiToolDelta(index: 1)(pair({'city': 'Oslo'}, {'tz': 'CET'})),
        '{"tz":"CET"}',
      );
    });

    test('geminiToolDelta returns null for Vertex partialArgs', () {
      // streamFunctionCallArguments emits jsonPath + typed values, not
      // concatenable JSON. Pretending those are fragments would write
      // garbage onto the buffer; this waits for `args` instead.
      expect(
        geminiToolDelta()({
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'functionCall': {
                      'name': 'controlLight',
                      'partialArgs': [
                        {
                          'jsonPath': r'$.brightness',
                          'numberValue': 50,
                        },
                      ],
                      'willContinue': true,
                    },
                  },
                ]
              }
            },
          ],
        }),
        isNull,
      );
    });

    test('geminiToolDelta returns null for malformed chunk shapes', () {
      final shapes = <Map<String, dynamic>>[
        <String, dynamic>{},
        {'candidates': <Object?>[]},
        {
          'candidates': [null]
        },
        {
          'candidates': [
            {'content': null}
          ]
        },
        {
          'candidates': [
            {
              'content': {'parts': 'nope'}
            }
          ]
        },
        {
          'candidates': [
            {
              'content': {
                'parts': [null]
              }
            }
          ]
        },
        {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'functionCall': 'nope'}
                ]
              }
            }
          ]
        },
        // A name-only opening chunk, before args exist.
        {
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'functionCall': {'name': 'extract_recipe'}
                  }
                ]
              }
            }
          ]
        },
        // args that is neither a Map nor a String. Not something that can
        // be accumulated, but it must not throw either.
        {
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'functionCall': {'args': 42}
                  }
                ]
              }
            }
          ]
        },
      ];
      for (final shape in shapes) {
        expect(geminiToolDelta()(shape), isNull, reason: '$shape');
      }
    });

    test('a function call goes end to end through streamPartialJsonFrom',
        () async {
      final frames = await streamPartialJsonFrom(
        Stream.fromIterable(_forcedGeminiFunctionCall),
        geminiToolDelta(),
      ).toList();
      // Read through geminiDelta this same stream yields nothing at all, with
      // no exception: the failure this adapter exists to end.
      expect(frames, isNotEmpty, reason: 'a silent zero-frame stream');
      expect(frames, [
        {'title': 'Focaccia', 'prep_min': 20},
      ]);
    });
  });

  test('streamPartialJsonFrom pipes provider chunks through an extractor',
      () async {
    final chunks = Stream<Map<String, dynamic>>.fromIterable([
      {
        'choices': [
          {
            'delta': {'content': '{"ok":'}
          }
        ]
      },
      {
        'choices': [
          {
            'delta': {'content': 'true}'}
          }
        ]
      },
    ]);
    final frames = await streamPartialJsonFrom(chunks, openAiDelta).toList();
    expect(frames.last, {'ok': true});
  });

  test('streamPartial maps growing objects into a typed value', () async {
    final deltas = Stream.fromIterable(['{"n": "A', 'da"}']);
    final names = await streamPartial(
      deltas,
      (m) => (m['n'] as String?) ?? '',
    ).toList();
    expect(names.last, 'Ada');
  });

  group('streamPartialFrom', () {
    test('goes from provider chunks to a typed value in one call', () async {
      final chunks = Stream.fromIterable(<Map<String, dynamic>>[
        {
          'choices': [
            {
              'delta': {'role': 'assistant'},
            },
          ],
        },
        {
          'choices': [
            {
              'delta': {'content': '{"name": "Ad'},
            },
          ],
        },
        {
          'choices': [
            {
              'delta': {'content': 'a", "age": 3'},
            },
          ],
        },
        {
          'choices': [
            {
              'delta': {'content': '6}'},
            },
          ],
        },
      ]);

      final names = await streamPartialFrom(
        chunks,
        openAiDelta,
        (partial) => '${partial['name'] ?? ''}/${partial['age'] ?? '?'}',
      ).toList();

      // One frame per chunk that carries text, so the role-only chunk produces
      // none, and the chunk that both finishes the name and opens the age
      // produces one rather than two.
      //
      // The age reads 3 before it reads 36: a number's digits arrive like any
      // other characters, so a partial value is not merely incomplete, it can
      // be provisionally wrong. Render it, but don't act on it until the end.
      expect(names, ['Ad/?', 'Ada/3', 'Ada/36']);
    });

    test('skips a stream that never forms an object', () async {
      final chunks = Stream.fromIterable(<Map<String, dynamic>>[
        {
          'choices': [
            {
              'delta': {'content': '[1, 2'},
            },
          ],
        },
      ]);
      expect(
        await streamPartialFrom(chunks, openAiDelta, (p) => p.length).toList(),
        isEmpty,
      );
    });
  });
}

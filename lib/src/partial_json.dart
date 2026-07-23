import 'dart:convert';

import 'package:meta/meta.dart';

/// Decodes a possibly-truncated JSON [buffer] into the value it represents so
/// far.
///
/// A language model emits a JSON object one token at a time, so the buffer you
/// hold mid-stream is almost never valid JSON: a string is half-written, an
/// object is still open, a comma dangles. [jsonDecode] throws on all of those
/// until the final token lands.
///
/// This closes an open string *value* and any open array or object, drops a
/// dangling object key, colon, or comma, and then decodes. Each delta therefore
/// yields the structure built up to that point, which is what a progressive UI
/// wants to render.
///
/// Returns `null` while nothing is decodable yet: an empty buffer, or a value
/// still resolving into a scalar, such as a half-written literal `tr` or the
/// number `12.`. A caller streaming deltas should treat `null` as "no update
/// this frame" and keep the previous value; the next delta usually resolves it.
///
/// Structure that has already arrived is returned even when it is empty, so a
/// buffer whose only content is an opened container reads as that container
/// rather than as `null`: `parsePartialJson('{"titl')` is `{}`, because the
/// buffer has established that the value is an object and only the first key
/// is incomplete. In a growing array, an element that has just opened appears
/// as an empty one: `parsePartialJson('[{"a": 1}, {"b')` is `[{a: 1}, {}]`.
/// This also
/// means a buffer that fully decodes to the JSON literal `null` reads the same
/// as "not decodable yet"; called directly, [parsePartialJson] cannot tell the
/// two apart. [streamPartialJson] can, and emits a resolved top-level `null`
/// rather than dropping it.
Object? parsePartialJson(String buffer) {
  final result = parsePartialJsonResult(buffer);
  return result.hasValue ? result.value : null;
}

/// The outcome of decoding a partial buffer: whether it decoded to a value at
/// all, and the value if so.
///
/// [parsePartialJson] collapses this to a plain `Object?`, where "nothing
/// decodable yet" and "decoded to the JSON literal `null`" both read as
/// `null`. [streamPartialJson] uses this instead so it can tell those two
/// cases apart. Not part of the package's public API.
@internal
typedef PartialJsonResult = ({bool hasValue, Object? value});

/// Like [parsePartialJson], but returns a [PartialJsonResult] so "nothing
/// decodable yet" and "decoded to `null`" stay distinguishable. Not part of
/// the package's public API.
@internal
PartialJsonResult parsePartialJsonResult(String buffer) {
  final json = _completeJson(buffer);
  if (json == null) return (hasValue: false, value: null);
  try {
    return (hasValue: true, value: jsonDecode(json));
  } on FormatException {
    // The completion was still not valid (for example a half-written number or
    // literal). Skip this frame rather than throw; the next delta resolves it.
    return (hasValue: false, value: null);
  }
}

class _Frame {
  _Frame({required this.isObject, required this.entryStart});

  final bool isObject;

  /// Object member has seen its key and `:` and now expects (or holds) a value.
  bool sawColon = false;

  /// Source index where the current member or element began: just after the
  /// opening `{`/`[` or the last `,`. Used to drop a half-written entry.
  int entryStart;
}

/// Builds a valid JSON string from a partial [s], or `null` if there is nothing
/// completable yet.
String? _completeJson(String s) {
  final frames = <_Frame>[];
  var inString = false;
  var escaped = false;

  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    switch (ch) {
      case '"':
        inString = true;
      case '{':
        frames.add(_Frame(isObject: true, entryStart: i + 1));
      case '[':
        frames.add(_Frame(isObject: false, entryStart: i + 1));
      case '}':
      case ']':
        if (frames.isNotEmpty) frames.removeLast();
      case ':':
        if (frames.isNotEmpty && frames.last.isObject) {
          frames.last.sawColon = true;
        }
      case ',':
        if (frames.isNotEmpty) {
          frames.last
            ..entryStart = i + 1
            ..sawColon = false;
        }
    }
  }

  var keep = s;
  var tail = '';

  if (inString) {
    final top = frames.isEmpty ? null : frames.last;
    final isValueString = top == null || !top.isObject || top.sawColon;
    if (isValueString) {
      // Keep the partial value; complete a dangling escape pair first.
      if (escaped) keep = '$keep\\';
      tail = '"';
    } else {
      // Half-written object key: drop it and any separator before it.
      keep = _dropCurrentEntry(s, top.entryStart);
    }
  } else {
    keep = _trimTail(s, frames);
  }

  keep = keep.replaceFirst(RegExp(r'\s+$'), '');
  if (keep.isEmpty) return null;

  final closers = _openClosers(keep + tail);
  return keep + tail + closers;
}

String _trimTail(String s, List<_Frame> frames) {
  final t = s.replaceFirst(RegExp(r'\s+$'), '');
  if (t.isEmpty) return t;
  final last = t[t.length - 1];
  if (last == ',') return t.substring(0, t.length - 1);
  if (last == ':') {
    // Dangling colon: drop the whole `key:` member.
    if (frames.isNotEmpty) return _dropCurrentEntry(s, frames.last.entryStart);
    return t.substring(0, t.length - 1);
  }
  // A complete value, an empty container, or a trailing scalar. A valid partial
  // number ("12") completes fine; an invalid one ("12." / "tr") is caught by
  // the jsonDecode fallback in parsePartialJson.
  return t;
}

String _dropCurrentEntry(String s, int entryStart) {
  var t = s.substring(0, entryStart).replaceFirst(RegExp(r'\s+$'), '');
  if (t.isNotEmpty && t[t.length - 1] == ',') {
    t = t.substring(0, t.length - 1);
  }
  return t;
}

/// Returns the closing brackets, in order, for every container still open in
/// [s] (strings ignored).
String _openClosers(String s) {
  final stack = <String>[];
  var inString = false;
  var escaped = false;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
    } else if (ch == '{') {
      stack.add('}');
    } else if (ch == '[') {
      stack.add(']');
    } else if (ch == '}' || ch == ']') {
      if (stack.isNotEmpty) stack.removeLast();
    }
  }
  final b = StringBuffer();
  for (var i = stack.length - 1; i >= 0; i--) {
    b.write(stack[i]);
  }
  return b.toString();
}

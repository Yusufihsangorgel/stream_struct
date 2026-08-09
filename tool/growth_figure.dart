// Draws doc/growth.svg from a replay measured at run time.
//
//   dart run tool/growth_figure.dart
//   rsvg-convert -w 1600 doc/growth.svg -o doc/growth.png
//
// The figure is the package's argument in one picture. One model answer is
// replayed a character at a time, and at every prefix both parsers are asked
// for the value: `jsonDecode` throws on all but the last one, while
// `parsePartialJson` hands back the fields that have arrived. Every number,
// every buffer, and every rendered value in the drawing comes out of that
// replay rather than being typed into the drawing.

import 'dart:convert';
import 'dart:io';

import 'package:stream_struct/stream_struct.dart';

/// A model's answer to "give me a recipe as JSON", written the way one arrives.
const response = '{"title": "Lemon risotto", "servings": 4, "minutes": 32, '
    '"rating": 4.8, "ingredients": ["arborio rice", "lemon zest", '
    '"parmesan"], "vegetarian": true}';

/// How many fields of the answer a caller could put on screen.
///
/// Every non-container counts as one, so a half-written string counts: it is
/// text a progressive UI can already render. An opened but still empty object
/// or array counts as nothing, which is the honest reading of a container the
/// model has announced and not yet filled.
int fields(Object? value) {
  if (value is Map) {
    return value.values.fold<int>(0, (sum, v) => sum + fields(v));
  }
  if (value is List) return value.fold<int>(0, (sum, v) => sum + fields(v));
  return 1;
}

void main() {
  final n = response.length;

  // Index i holds the reading for the prefix of length i, so index 0 is the
  // empty buffer and index n is the whole answer.
  final available = List<int>.filled(n + 1, 0);
  final decodes = <int>[];
  var answered = 0;

  for (var i = 1; i <= n; i++) {
    final prefix = response.substring(0, i);
    try {
      jsonDecode(prefix);
      decodes.add(i);
    } on FormatException {
      // What the package exists for: a truncated buffer is not valid JSON.
    }
    final partial = parsePartialJson(prefix);
    if (partial != null) answered++;
    available[i] = partial == null ? 0 : fields(partial);
  }

  final total = available[n];

  if (decodes.length != 1 || decodes.single != n) {
    stderr.writeln(
      'the red line is drawn flat until the last character. jsonDecode must '
      'accept the whole answer and nothing shorter; it accepted $decodes',
    );
    exitCode = 1;
    return;
  }
  if (answered <= decodes.length) {
    stderr.writeln(
      'the figure claims the tolerant parser answers far more often; it '
      'answered $answered of $n prefixes against ${decodes.length}',
    );
    exitCode = 1;
    return;
  }
  if (total == 0) {
    stderr.writeln('the answer has no fields to count');
    exitCode = 1;
    return;
  }

  final half = available.indexWhere((f) => f * 2 >= total);
  // Three points spread evenly across the stream, rather than three chosen for
  // how well they read.
  final samples = [n ~/ 4, n ~/ 2, (n * 3) ~/ 4];

  // The one place the count goes backwards: a number that has reached `4.` is
  // not a number yet, and the package drops that entry until the next
  // character resolves it. Measured, because it is a claim about the code.
  var dip = -1, dipLength = 0;
  for (var i = 1; i <= n; i++) {
    if (available[i] < available[i - 1]) {
      dip = i;
      final was = available[i - 1];
      while (dip + dipLength <= n && available[dip + dipLength] < was) {
        dipLength++;
      }
      break;
    }
  }

  File('doc/growth.svg').writeAsStringSync(
    _svg(
      available,
      total: total,
      half: half,
      samples: samples,
      dip: dip,
      dipLength: dipLength,
    ),
  );

  stdout.writeln('answer length          $n characters');
  stdout.writeln('fields in the answer   $total');
  stdout.writeln('jsonDecode accepted    ${decodes.length} of $n prefixes');
  stdout.writeln('parsePartialJson       $answered of $n prefixes');
  stdout.writeln('half the fields by     character $half');
  stdout.writeln('count drops back at    character $dip, for $dipLength');
  for (final i in samples) {
    final at = 'at $i'.padRight(23);
    stdout.writeln(
      '$at${available[i]} of $total fields  '
      '${parsePartialJson(response.substring(0, i))}',
    );
  }
  stdout.writeln('wrote doc/growth.svg');
}

const _w = 920.0, _h = 540.0;
const _left = 84.0, _top = 92.0, _right = 880.0, _bottom = 306.0;

String _svg(
  List<int> available, {
  required int total,
  required int half,
  required List<int> samples,
  required int dip,
  required int dipLength,
}) {
  final n = available.length - 1;
  final plotW = _right - _left, plotH = _bottom - _top;

  double x(int chars) => _left + plotW * chars / n;
  double y(int f) => _bottom - plotH * f / total;

  // The staircase, kept to the points where the reading actually changes.
  final steps = <List<int>>[];
  var last = -1;
  for (var i = 0; i <= n; i++) {
    if (available[i] != last) {
      steps.add([i, available[i]]);
      last = available[i];
    }
  }

  final line =
      StringBuffer('M ${_f(x(steps.first[0]))} ${_f(y(steps.first[1]))}');
  for (var s = 1; s < steps.length; s++) {
    line.write(' L ${_f(x(steps[s][0]))} ${_f(y(steps[s - 1][1]))}');
    line.write(' L ${_f(x(steps[s][0]))} ${_f(y(steps[s][1]))}');
  }
  line.write(' L ${_f(x(n))} ${_f(y(steps.last[1]))}');

  final grid = StringBuffer();
  for (var f = 0; f <= total; f += 2) {
    final gy = y(f);
    grid.writeln(
      '<line x1="$_left" y1="${_f(gy)}" x2="$_right" y2="${_f(gy)}" '
      'stroke="#e5e7eb" stroke-width="1"/>',
    );
    grid.writeln(
      '<text x="${_left - 12}" y="${_f(gy + 4)}" text-anchor="end" '
      'font-size="12" fill="#6b7280">$f</text>',
    );
  }

  final ticks = StringBuffer();
  for (var c = 0; c <= n; c += 30) {
    if (c != 0 && n - c < 14) continue;
    ticks.writeln(
      '<text x="${_f(x(c))}" y="${_bottom + 22}" text-anchor="middle" '
      'font-size="12" fill="#6b7280">$c</text>',
    );
  }
  ticks.writeln(
    '<text x="${_f(x(n))}" y="${_bottom + 22}" text-anchor="middle" '
    'font-size="12" fill="#6b7280">$n</text>',
  );

  final rows = <String>[];
  for (var r = 0; r < samples.length; r++) {
    final i = samples[r];
    final ry = 430.0 + r * 28;
    final buffer = _tail(response.substring(0, i), 37);
    final value = _middle('${parsePartialJson(response.substring(0, i))}', 64);
    rows.add('''
<text x="40" y="$ry" font-size="12" fill="#6b7280">char $i</text>
<text x="112" y="$ry" font-size="12" font-family="ui-monospace, monospace"
      fill="#111827">${_x(buffer)}</text>
<text x="392" y="$ry" font-size="12" fill="#9ca3af">&#8594;</text>
<text x="414" y="$ry" font-size="12" font-family="ui-monospace, monospace"
      fill="#047857">${_x(value)}</text>''');
  }

  // The unresolved-number notch, labelled from the buffer rather than by hand.
  var notch = '';
  if (dip > 0) {
    final token = RegExp(r'''[^\s{}\[\]:,"]+$''')
        .firstMatch(response.substring(0, dip))
        ?.group(0);
    if (token != null) {
      final ny = y(total) + 62;
      final unit = dipLength == 1 ? 'character' : 'characters';
      notch = '''
<line x1="${_f(x(dip) - 10)}" y1="${_f(ny + 6)}" x2="${_f(x(dip) + 2)}"
      y2="${_f(y(available[dip]) - 10)}" stroke="#9ca3af" stroke-width="1"/>
<text x="${_f(x(dip) - 16)}" y="${_f(ny)}" text-anchor="end" font-size="12"
      fill="#6b7280">a number that has only reached <tspan
      font-family="ui-monospace, monospace">${_x(token)}</tspan> is not a</text>
<text x="${_f(x(dip) - 16)}" y="${_f(ny + 17)}" text-anchor="end"
      font-size="12" fill="#6b7280">number yet, and its field steps out of the
      frame for $dipLength $unit</text>''';
    }
  }

  return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${_w.toInt()} ${_h.toInt()}"
     font-family="-apple-system, Segoe UI, Roboto, sans-serif">
<rect width="100%" height="100%" fill="#ffffff"/>
<text x="40" y="34" font-size="17" font-weight="600" fill="#111827">
  How much of the answer you can put on screen, at each point in the stream
</text>
<text x="40" y="58" font-size="13" fill="#6b7280">
  One model answer of $n characters, replayed a character at a time and handed
  to both parsers at every prefix
</text>
$grid
<path d="$line L ${_f(x(n))} $_bottom L $_left $_bottom Z" fill="#ecfdf5"/>
<line x1="$_left" y1="$_bottom" x2="$_right" y2="$_bottom" stroke="#9ca3af"
      stroke-width="1"/>
<line x1="${_f(x(half))}" y1="${_f(y(total))}" x2="${_f(x(half))}" y2="$_bottom"
      stroke="#9ca3af" stroke-width="1" stroke-dasharray="4 4"/>
<line x1="${_f(x(n))}" y1="$_bottom" x2="${_f(x(n))}" y2="${_f(y(total))}"
      stroke="#dc2626" stroke-width="2.5"/>
<path d="$line" fill="none" stroke="#059669" stroke-width="2.5"/>
<circle cx="${_f(x(n))}" cy="${_f(y(total))}" r="4.5" fill="#dc2626"/>
$notch
<text x="${_left + 14}" y="${_top + 24}" font-size="13" font-weight="600"
      fill="#047857">parsePartialJson</text>
<text x="${_left + 14}" y="${_top + 42}" font-size="12" fill="#047857">
  fields available, out of $total
</text>
<text x="${_f(x(half) + 8)}" y="${_bottom - 10}" font-size="12" fill="#6b7280">
  half the answer is on screen by character $half of $n
</text>
<text x="${_f(x(n) - 14)}" y="${_f(y(total) + 4)}" text-anchor="end"
      font-size="13" font-weight="600" fill="#b91c1c">
  dart:convert jsonDecode throws until here, then returns all $total
</text>
$ticks
<text x="${_f(_left + plotW / 2)}" y="${_bottom + 46}" text-anchor="middle"
      font-size="12" fill="#6b7280">characters of the answer received</text>
<text x="20" y="${_f(_top + plotH / 2)}" font-size="12" fill="#6b7280"
      transform="rotate(-90 20 ${_f(_top + plotH / 2)})" text-anchor="middle">
  fields you can render
</text>
<line x1="40" y1="368" x2="880" y2="368" stroke="#e5e7eb" stroke-width="1"/>
<text x="40" y="396" font-size="14" font-weight="600" fill="#111827">
  Three of those prefixes
</text>
<text x="112" y="416" font-size="11" fill="#9ca3af">buffer received, tail</text>
<text x="414" y="416" font-size="11" fill="#9ca3af">
  what parsePartialJson returns
</text>
${rows.join('\n')}
</svg>
''';
}

String _f(double v) => v.toStringAsFixed(1);

String _x(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// The last [max] characters, marked with a leading ellipsis when cut.
String _tail(String s, int max) =>
    s.length <= max ? s : '…${s.substring(s.length - max + 1)}';

/// The opening and the newest content, with the settled middle elided.
///
/// Both cuts are pulled back to a space where one is close by, which keeps the
/// elision from landing inside a word.
String _middle(String s, int max) {
  if (s.length <= max) return s;
  final side = (max - 3) ~/ 2;

  var head = s.substring(0, side);
  final headCut = head.lastIndexOf(' ');
  if (headCut > side ~/ 2) head = head.substring(0, headCut);

  var tail = s.substring(s.length - side);
  final tailCut = tail.indexOf(' ');
  if (tailCut >= 0 && tailCut < side ~/ 2) tail = tail.substring(tailCut + 1);

  return '$head … $tail';
}

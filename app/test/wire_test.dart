import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/live/daemon_client.dart';
import 'package:orc_harness/src/live/grid.dart';

/// The bytes orc_protocol::wire encodes for its sample (wire.rs SAMPLE_HEX).
const sampleHex =
    '01020073310600030002000300010200000002000000000200006f6b0101010001000021'
    '020003000002008080010101000102c3a900000001000103e7958c40000001000100';

Uint8List hex(String h) => Uint8List.fromList([
  for (var i = 0; i < h.length; i += 2)
    int.parse(h.substring(i, i + 2), radix: 16),
]);

void main() {
  test('decodes the grid the daemon encodes', () {
    final b = hex(sampleHex);
    expect(binaryGridSession(b), 's1');
    final g = GridState();
    expect(g.applyBinary(b), isTrue);
    expect((g.cols, g.rows), (6, 3));
    expect((g.cursorRow, g.cursorCol, g.cursorVisible), (2, 3, true));
    expect(g.lineText(0), 'ok!');
    final bang = g.lines[0][2];
    expect(bang.fg, indexedColor(1));
    expect(bang.has(TermCell.bold), isTrue);
    expect(g.lines[0][0].fg, isNull);
    final row2 = g.lines[2];
    expect(row2.map((c) => c.text).toList(), ['é', '界', '']);
    expect(row2[0].fg, const Color.fromARGB(255, 0, 128, 128));
    expect(row2[0].bg, indexedColor(1));
    expect(row2[2].has(TermCell.wideSpacer), isTrue);
    expect(g.lines[1], isEmpty);
  });

  test('a cut-off grid is refused, nothing applied', () {
    final b = hex(sampleHex);
    final g = GridState();
    expect(g.applyBinary(Uint8List.sublistView(b, 0, b.length - 3)), isFalse);
    expect(g.rows, 0);
  });

  test('only changed rows get a new version', () {
    final g = GridState()..applyBinary(hex(sampleHex));
    final before = List.of(g.versions);
    g.apply({
      'cols': 6,
      'rows': 3,
      'lines': [
        [
          1,
          [
            {
              'text': 'x',
              'fg': {'kind': 'default'},
              'bg': {'kind': 'default'},
              'flags': 0,
            },
          ],
        ],
      ],
      'cursor': {'row': 0, 'col': 0, 'visible': true},
    });
    expect(g.versions[0], before[0]);
    expect(g.versions[2], before[2]);
    expect(g.versions[1], isNot(before[1]));
  });

  test('frames: JSON and binary grids reach the client', () {
    final d = DaemonClient();
    d.handleFrame(
      Uint8List.fromList([
        0,
        ...utf8.encode('{"type":"hello","accounts":["work"]}'),
      ]),
    );
    expect(d.accounts, ['work']);
    d.handleFrame(Uint8List.fromList([1, ...hex(sampleHex)]));
    expect(d.grids['s1']!.state.lineText(0), 'ok!');
    d.dispose();
  });
}
